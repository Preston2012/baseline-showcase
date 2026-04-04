/// Statement model for Baseline.
///
/// Represents a political figure's public statement as returned by the
/// get-statement Edge Function (v_statements_public view).
///
/// Fields map 1:1 to STATEMENT_COLUMNS in get-statement.ts:
/// statement_id, figure_id, figure_name, statement_text, context_before,
/// context_after, source_url, stated_at, ingestion_time, baseline_delta, topics.
///
/// All parsed DateTimes are normalized to UTC via .toUtc().
///
/// JSON parsing is defensive: nullable fields use null-safe casts,
/// list fields fall back to empty lists, and date fields catch
/// FormatException to prevent crashes on malformed API responses.
///
/// Path: lib/models/statement.dart
class Statement {
  const Statement({
    required this.statementId,
    required this.figureId,
    required this.figureName,
    required this.statementText,
    this.contextBefore,
    this.contextAfter,
    this.sourceUrl,
    required this.statedAt,
    required this.ingestionTime,
    this.baselineDelta,
    this.topics = const [],
  });

  /// UUID primary key from the statements table.
  final String statementId;

  /// UUID foreign key to the figures table.
  final String figureId;

  /// Display name of the figure (denormalized from figures.name via view join).
  final String figureName;

  /// Full text of the public statement.
  final String statementText;

  /// Preceding context extracted during ingestion (nullable if unavailable).
  final String? contextBefore;

  /// Following context extracted during ingestion (nullable if unavailable).
  final String? contextAfter;

  /// Original source URL where the statement was published.
  final String? sourceUrl;

  /// When the statement was originally made (UTC).
  final DateTime statedAt;

  /// When the statement entered the Baseline pipeline (UTC).
  final DateTime ingestionTime;

  /// Computed delta between this statement's metrics and the figure's
  /// historical baseline. Null if not yet computed or insufficient history.
  final double? baselineDelta;

  /// Topic tags assigned during extraction (e.g., ECONOMY, IMMIGRATION).
  /// Stored as a text array in PostgreSQL, parsed from JSON list.
  final List<String> topics;

  /// Defensive JSON parser matching the Supabase PostgREST response shape.
  ///
  /// Handles null values, missing keys, and type mismatches without throwing.
  /// Date fields that fail to parse are assigned DateTime(0) as a sentinel
  /// rather than crashing the feed.
  factory Statement.fromJson(Map<String, dynamic> json) {
    return Statement(
      statementId: json['statement_id'] as String,
      figureId: json['figure_id'] as String,
      figureName: json['figure_name'] as String? ?? '',
      statementText: json['statement_text'] as String? ?? '',
      contextBefore: json['context_before'] as String?,
      contextAfter: json['context_after'] as String?,
      sourceUrl: json['source_url'] as String?,
      statedAt: _parseDate(json['stated_at']),
      ingestionTime: _parseDate(json['ingestion_time']),
      baselineDelta: (json['baseline_delta'] as num?)?.toDouble(),
      topics: _parseTopics(json['topics']),
    );
  }

  Map<String, dynamic> toJson() => {
        'statement_id': statementId,
        'figure_id': figureId,
        'figure_name': figureName,
        'statement_text': statementText,
        'context_before': contextBefore,
        'context_after': contextAfter,
        'source_url': sourceUrl,
        'stated_at': statedAt.toUtc().toIso8601String(),
        'ingestion_time': ingestionTime.toUtc().toIso8601String(),
        'baseline_delta': baselineDelta,
        'topics': topics,
      };

  Statement copyWith({
    String? statementId,
    String? figureId,
    String? figureName,
    String? statementText,
    String? contextBefore,
    String? contextAfter,
    String? sourceUrl,
    DateTime? statedAt,
    DateTime? ingestionTime,
    double? baselineDelta,
    List<String>? topics,
  }) {
    return Statement(
      statementId: statementId ?? this.statementId,
      figureId: figureId ?? this.figureId,
      figureName: figureName ?? this.figureName,
      statementText: statementText ?? this.statementText,
      contextBefore: contextBefore ?? this.contextBefore,
      contextAfter: contextAfter ?? this.contextAfter,
      sourceUrl: sourceUrl ?? this.sourceUrl,
      statedAt: statedAt ?? this.statedAt,
      ingestionTime: ingestionTime ?? this.ingestionTime,
      baselineDelta: baselineDelta ?? this.baselineDelta,
      topics: topics ?? this.topics,
    );
  }

  static DateTime _parseDate(dynamic value) {
    if (value is String) {
      try {
        return DateTime.parse(value).toUtc();
      } on FormatException {
        return DateTime.utc(0);
      }
    }
    return DateTime.utc(0);
  }

  static List<String> _parseTopics(dynamic value) {
    if (value is List) {
      return value.whereType<String>().toList();
    }
    return const [];
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Statement &&
          runtimeType == other.runtimeType &&
          statementId == other.statementId;

  @override
  int get hashCode => statementId.hashCode;

  @override
  String toString() => 'Statement($statementId, $figureName, ${statedAt.toIso8601String()})';
}
