/// BrainVault — API Service
///
/// HTTP client for communicating with the BrainVault backend.
/// Handles text/audio memory ingestion, querying, and health checks.
/// Includes cold-start retry logic for Render free-tier.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import '../models/memory.dart';

class ApiService {
  // ── Configuration ──────────────────────────────────────────────────────
  // TODO: Change this to your Render deployment URL in production
  // For local development with Android emulator: http://10.0.2.2:3000
  // For physical device on same WiFi: http://<your-local-ip>:3000
  static const String baseUrl = 'https://brainvault-qj2q.onrender.com';

  /// Request timeout — generous to account for Gemini API latency
  static const Duration _timeout = Duration(seconds: 30);

  /// Cold-start retry delay — wait for Render container to wake up
  static const Duration _coldStartDelay = Duration(seconds: 5);

  /// Maximum retry attempts for cold-start recovery
  static const int _maxRetries = 2;

  // ── Health Check (Pre-warm) ────────────────────────────────────────────

  /// Fire-and-forget health ping to pre-warm the backend container.
  /// Called on app launch so the container is ready by the time
  /// the user finishes composing their input.
  static Future<void> prewarm() async {
    try {
      await http
          .get(Uri.parse('$baseUrl/api/health'))
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      // Silently ignore — this is a best-effort pre-warm
    }
  }

  /// Check whether the backend is reachable and healthy.
  ///
  /// Returns `true` if the server responds with HTTP 200, `false` otherwise.
  /// Used by the UI status indicator to show a red/green connection light.
  static Future<bool> checkHealth() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/health'))
          .timeout(const Duration(seconds: 15));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ── Memory Ingestion ───────────────────────────────────────────────────

  /// Add a text memory to the vault.
  ///
  /// Returns the saved [Memory] on success.
  /// Throws [DisambiguationException] if duplicate names need conflict resolution.
  /// Throws [ApiException] on failure.
  static Future<dynamic> addTextMemory(String text) async {
    return _withRetry(() async {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/memory/add'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'text': text}),
          )
          .timeout(_timeout);

      return _handleAddResponse(response);
    });
  }

  /// Add an audio memory to the vault.
  ///
  /// [filePath] is the local path to the recorded audio file.
  /// Returns the saved [Memory] on success.
  /// Throws [DisambiguationException] if conflict resolution is required.
  /// Throws [ApiException] on failure.
  static Future<dynamic> addAudioMemory(String filePath) async {
    return _withRetry(() async {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/api/memory/add'),
      );

      // Attach the audio file as multipart form-data with explicit content-type
      request.files.add(
        await http.MultipartFile.fromPath(
          'audio',
          filePath,
          contentType: MediaType('audio', 'm4a'),
        ),
      );

      final streamedResponse = await request.send().timeout(_timeout);
      final response = await http.Response.fromStream(streamedResponse);

      return _handleAddResponse(response);
    });
  }

  /// Submit a manually constructed memory to the database.
  ///
  /// [data] contains description, location, event_date, people_ids, new_people.
  /// Returns the saved [Memory] on success.
  static Future<Memory> addConstructedMemory(Map<String, dynamic> data) async {
    return _withRetry(() async {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/memory/add'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(data),
          )
          .timeout(_timeout);

      final result = _handleAddResponse(response);
      if (result is Memory) {
        return result;
      }
      throw const ApiException('Invalid response format for constructed memory.');
    });
  }

  /// Finalize saving a memory after the user resolved a name conflict.
  /// Sends the resolved person IDs along with the temporary extraction payload.
  static Future<Memory> resolveMemoryConflict(
    List<String> resolvedIds,
    Map<String, dynamic> tempPayload,
  ) async {
    return _withRetry(() async {
      final payload = {
        'resolved_people_ids': resolvedIds,
        'temp_extraction': tempPayload['extraction'],
        'raw_text': tempPayload['raw_text'],
        'source_type': tempPayload['source_type'],
      };

      final response = await http
          .post(
            Uri.parse('$baseUrl/api/memory/add'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(_timeout);

      final result = _handleAddResponse(response);
      if (result is Memory) {
        return result;
      }
      throw const ApiException('Conflict resolution failed to save.');
    });
  }

  // ── People Directory API ──────────────────────────────────────────────────

  /// Get the list of all registered people profiles in the directory.
  static Future<List<dynamic>> getPeople() async {
    return _withRetry(() async {
      final response = await http
          .get(Uri.parse('$baseUrl/api/people'))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as List<dynamic>;
      } else {
        throw ApiException(_extractError(response));
      }
    });
  }

  /// Add a new person profile to the directory.
  static Future<Map<String, dynamic>> addPerson(
    String name,
    String relation,
    String notes,
  ) async {
    return _withRetry(() async {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/people'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'name': name,
              'relation': relation,
              'notes': notes,
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 201) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      } else {
        throw ApiException(_extractError(response));
      }
    });
  }

  // ── Memory Retrieval ───────────────────────────────────────────────────

  /// Query the memory vault with a natural language question.
  ///
  /// Returns a [QueryResult] with the synthesized answer and source memories.
  /// Throws [ApiException] on failure.
  static Future<QueryResult> queryMemories(String question) async {
    return _withRetry(() async {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/memory/query'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'question': question}),
          )
          .timeout(_timeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return QueryResult.fromJson(data);
      } else {
        throw ApiException(_extractError(response));
      }
    });
  }

  // ── Internal Helpers ───────────────────────────────────────────────────

  /// Parse the response from POST /api/memory/add
  /// Can return a [Memory] or trigger a [DisambiguationException]
  static dynamic _handleAddResponse(http.Response response) {
    final data = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode == 200 &&
        data['status'] == 'disambiguation_required') {
      throw DisambiguationException(
        data['conflicts'] as List<dynamic>,
        data['temp_payload'] as Map<String, dynamic>,
      );
    }

    if (response.statusCode == 201) {
      return Memory.fromJson(data['memory'] as Map<String, dynamic>);
    } else {
      throw ApiException(_extractError(response));
    }
  }

  /// Extract error message from a non-2xx response.
  static String _extractError(http.Response response) {
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return body['error'] as String? ??
          'Unknown error (${response.statusCode})';
    } catch (_) {
      return 'Server error (${response.statusCode})';
    }
  }

  /// Retry wrapper for cold-start resilience.
  ///
  /// If the first attempt fails with a timeout or connection error,
  /// waits [_coldStartDelay] then retries up to [_maxRetries] times.
  /// This handles Render free-tier cold starts gracefully.
  static Future<T> _withRetry<T>(Future<T> Function() action) async {
    for (int attempt = 0; attempt <= _maxRetries; attempt++) {
      try {
        return await action();
      } on TimeoutException {
        if (attempt == _maxRetries) {
          throw const ApiException(
            'Request timed out. The server may be waking up — please try again in a moment.',
          );
        }
        await Future.delayed(_coldStartDelay);
      } on SocketException {
        if (attempt == _maxRetries) {
          throw const ApiException(
            'Could not connect to the server. Please check your internet connection.',
          );
        }
        await Future.delayed(_coldStartDelay);
      }
    }
    throw const ApiException('Unexpected error during retry.');
  }
}

/// Custom exception for API errors, displayed to the user.
class ApiException implements Exception {
  final String message;
  const ApiException(this.message);

  @override
  String toString() => message;
}

/// Custom exception thrown when a name matches multiple profiles.
class DisambiguationException implements Exception {
  final List<dynamic> conflicts;
  final Map<String, dynamic> tempPayload;
  const DisambiguationException(this.conflicts, this.tempPayload);
}
