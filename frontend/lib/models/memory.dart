/// BrainVault — Data Models
///
/// Simple data classes for memory records and API responses.

/// Represents a saved memory returned from the backend.
class Memory {
  final String id;
  final String? eventDate;
  final String subject;
  final List<String> tags;
  final String cleanedText;
  final DateTime? createdAt;

  Memory({
    required this.id,
    this.eventDate,
    required this.subject,
    required this.tags,
    required this.cleanedText,
    this.createdAt,
  });

  /// Parse a Memory from JSON returned by POST /api/memory/add
  factory Memory.fromJson(Map<String, dynamic> json) {
    return Memory(
      id: json['id'] as String,
      eventDate: json['event_date'] as String?,
      subject: json['subject'] as String? ?? 'other',
      tags: (json['tags'] as List<dynamic>?)
              ?.map((t) => t.toString())
              .toList() ??
          [],
      cleanedText: json['cleaned_text'] as String? ?? '',
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String)
          : null,
    );
  }
}

/// Represents the result of a memory query.
class QueryResult {
  final String answer;
  final List<SourceMemory> sources;

  QueryResult({required this.answer, required this.sources});

  factory QueryResult.fromJson(Map<String, dynamic> json) {
    return QueryResult(
      answer: json['answer'] as String? ?? 'No answer available.',
      sources: (json['sources'] as List<dynamic>?)
              ?.map((s) => SourceMemory.fromJson(s as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

/// A source memory reference returned with a query answer.
class SourceMemory {
  final String id;
  final String? eventDate;
  final String subject;
  final List<String> tags;
  final String summary;
  final String rawText;
  final DateTime? createdAt;
  final int relevance;

  SourceMemory({
    required this.id,
    this.eventDate,
    required this.subject,
    required this.tags,
    required this.summary,
    required this.rawText,
    this.createdAt,
    required this.relevance,
  });

  factory SourceMemory.fromJson(Map<String, dynamic> json) {
    return SourceMemory(
      id: json['id'] as String,
      eventDate: json['event_date'] as String?,
      subject: json['subject'] as String? ?? 'other',
      tags: (json['tags'] as List<dynamic>?)
              ?.map((t) => t.toString())
              .toList() ??
          [],
      summary: json['summary'] as String? ?? '',
      rawText: json['raw_text'] as String? ?? '',
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String)
          : null,
      relevance: json['relevance'] as int? ?? 0,
    );
  }
}
