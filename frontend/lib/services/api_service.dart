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

  // ── Memory Ingestion ───────────────────────────────────────────────────

  /// Add a text memory to the vault.
  ///
  /// Returns the saved [Memory] on success.
  /// Throws [ApiException] on failure.
  static Future<Memory> addTextMemory(String text) async {
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
  /// Throws [ApiException] on failure.
  static Future<Memory> addAudioMemory(String filePath) async {
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
  static Memory _handleAddResponse(http.Response response) {
    if (response.statusCode == 201) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
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
