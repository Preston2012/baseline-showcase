/// F3.3 -- FeedStatement model
///
/// Represents a single statement as returned by get-feed (A9B v2.0.0).
/// This is the FLAT feed shape with inline consensus metrics - distinct
/// from the full Statement model (F3M.1) used by get-statement (A9C)
/// which has nested analyses[] and consensus{} objects.
///
/// source_type is nullable (removed from view in A9A V1.0.2).
/// If null, UI hides the source type row - does NOT render "Unknown".
///
/// Assumes backend timestamps are UTC ISO 8601 (confirmed in A9A/A9B).
///
/// Path: lib/models/feed_statement.dart
library;

class FeedStatement {
  FeedStatement({
    required this.statementId,
    required this.figureId,
    required this.figureName,
    required this.statementText,
    required this.statedAt,
    required this.ingestionTime,
    this.sourceUrl,
    this.sourceType,
    this.baselineDelta,
    this.topics,
    required this.rankStatus,
    this.signalRank,
    this.varianceDetected,
    this.noveltyAvg,
    this.repetitionAvg,
    this.affectiveLanguageRateAvg,
    this.topicEntropyAvg,
    this.baselineDeltaAvg,
    this.framingConsensus,
    this.modelCount,
    this.consensusComputedAt,
    this.figurePhotoUrl,
  });

  final String statementId;
  final String figureId;
  final String figureName;
  final String statementText;
  final DateTime statedAt;
  final DateTime ingestionTime;
  final String? sourceUrl;
  final String? sourceType;
  final double? baselineDelta;
  final List<String>? topics;
  final String rankStatus;
  final double? signalRank;
  final bool? varianceDetected;
  final double? noveltyAvg;
  final double? repetitionAvg;
  final double? affectiveLanguageRateAvg;
  final double? topicEntropyAvg;
  final double? baselineDeltaAvg;
  final String? framingConsensus;
  final int? modelCount;
  final DateTime? consensusComputedAt;

  /// Photo URL for the figure, populated from backend or figure cache.
  String? figurePhotoUrl;

  /// Alias getters for compatibility
  String get id => statementId;
  String get text => statementText;
  String get headline => statementText;
  DateTime get createdAt => statedAt;
  double? get consensusScore => baselineDeltaAvg;
  double? get repetition => repetitionAvg;
  double? get novelty => noveltyAvg;
  double? get affect => affectiveLanguageRateAvg;
  double? get entropy => topicEntropyAvg;
  String? get dominantFraming => framingConsensus;
  int? get vote => null; // user vote from separate provider
  bool get isSilentVote => false;
  Map<String, double>? get framingDistribution => null;
  int get points => 0;
  String? get votePosition => null;
  String? get response => null;

  /// Parses a single statement object from the get-feed response.
  ///
  /// Defensively handles:
  /// - Missing/null required IDs: throws FormatException
  /// - statement_text required non-empty: throws FormatException
  /// - rankStatus required: throws FormatException (no silent default)
  /// - Nullable numerics: null (not 0); non-finite: null
  /// - topics: only String items kept, non-strings silently dropped
  /// - Timestamps: UTC
  factory FeedStatement.fromJson(Map<String, dynamic> json) {
    // ── Required fields ──────────────────────────────────────────────
    final statementId = json['statement_id'];
    if (statementId is! String || statementId.isEmpty) {
      throw FormatException(
        'FeedStatement.fromJson: statement_id missing or invalid',
        json,
      );
    }

    final figureId = json['figure_id'];
    if (figureId is! String || figureId.isEmpty) {
      throw FormatException(
        'FeedStatement.fromJson: figure_id missing or invalid',
        json,
      );
    }

    final statementText = json['statement_text'];
    if (statementText is! String || statementText.isEmpty) {
      throw FormatException(
        'FeedStatement.fromJson: statement_text missing or empty',
        json,
      );
    }

    final rankStatusRaw = json['rank_status'];
    if (rankStatusRaw is! String || rankStatusRaw.isEmpty) {
      throw FormatException(
        'FeedStatement.fromJson: rank_status missing or invalid',
        json,
      );
    }

    // ── Timestamps (required, UTC) ───────────────────────────────────
    final statedAtRaw = json['stated_at'];
    if (statedAtRaw is! String) {
      throw FormatException(
        'FeedStatement.fromJson: stated_at missing or invalid',
        json,
      );
    }
    final statedAt = DateTime.tryParse(statedAtRaw);
    if (statedAt == null) {
      throw FormatException(
        'FeedStatement.fromJson: stated_at unparseable: $statedAtRaw',
      );
    }

    final ingestionTimeRaw = json['ingestion_time'];
    if (ingestionTimeRaw is! String) {
      throw FormatException(
        'FeedStatement.fromJson: ingestion_time missing or invalid',
        json,
      );
    }
    final ingestionTime = DateTime.tryParse(ingestionTimeRaw);
    if (ingestionTime == null) {
      throw FormatException(
        'FeedStatement.fromJson: ingestion_time unparseable: $ingestionTimeRaw',
      );
    }

    // ── Topics: keep only valid String items ─────────────────────────
    final rawTopics = json['topics'];
    final List<String>? topics = rawTopics is List
        ? rawTopics.whereType<String>().where((s) => s.isNotEmpty).toList()
        : null;

    // ── Consensus timestamp (nullable) ───────────────────────────────
    final consensusRaw = json['consensus_computed_at'];
    final DateTime? consensusComputedAt = consensusRaw is String
        ? DateTime.tryParse(consensusRaw)?.toUtc()
        : null;

    // ── Figure photo URL (nullable) ─────────────────────────────
    final rawPhotoUrl = json['figure_photo_url'] ?? json['photo_url'];
    final String? figurePhotoUrl =
        rawPhotoUrl is String && rawPhotoUrl.isNotEmpty ? rawPhotoUrl : null;

    return FeedStatement(
      statementId: statementId,
      figureId: figureId,
      figureName: json['figure_name'] as String? ?? '',
      statementText: statementText,
      statedAt: statedAt.toUtc(),
      ingestionTime: ingestionTime.toUtc(),
      sourceUrl: json['source_url'] as String?,
      sourceType: json['source_type'] as String?,
      baselineDelta: _safeDouble(json['baseline_delta']),
      topics: topics,
      rankStatus: rankStatusRaw,
      signalRank: _safeDouble(json['signal_rank']),
      varianceDetected: json['variance_detected'] as bool?,
      noveltyAvg: _safeDouble(json['novelty_avg']),
      repetitionAvg: _safeDouble(json['repetition_avg']),
      affectiveLanguageRateAvg:
          _safeDouble(json['affective_language_rate_avg']),
      topicEntropyAvg: _safeDouble(json['topic_entropy_avg']),
      baselineDeltaAvg: _safeDouble(json['baseline_delta_avg']),
      framingConsensus: json['framing_consensus'] as String?,
      modelCount: (json['model_count'] as num?)?.toInt(),
      consensusComputedAt: consensusComputedAt,
      figurePhotoUrl: figurePhotoUrl,
    );
  }

  /// Safely converts a JSON numeric to double, rejecting NaN/Infinity.
  static double? _safeDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) {
      final d = value.toDouble();
      return d.isFinite ? d : null;
    }
    return null;
  }

  /// Serializes for local caching / debugging.
  Map<String, dynamic> toJson() => {
        'statement_id': statementId,
        'figure_id': figureId,
        'figure_name': figureName,
        'figure_photo_url': figurePhotoUrl,
        'statement_text': statementText,
        'stated_at': statedAt.toIso8601String(),
        'ingestion_time': ingestionTime.toIso8601String(),
        'source_url': sourceUrl,
        'source_type': sourceType,
        'baseline_delta': baselineDelta,
        'topics': topics,
        'rank_status': rankStatus,
        'signal_rank': signalRank,
        'variance_detected': varianceDetected,
        'novelty_avg': noveltyAvg,
        'repetition_avg': repetitionAvg,
        'affective_language_rate_avg': affectiveLanguageRateAvg,
        'topic_entropy_avg': topicEntropyAvg,
        'baseline_delta_avg': baselineDeltaAvg,
        'framing_consensus': framingConsensus,
        'model_count': modelCount,
        'consensus_computed_at': consensusComputedAt?.toIso8601String(),
      };
}
