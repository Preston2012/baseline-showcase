/// FG-8b — Dossier Mode Controller
///
/// Riverpod family AsyncNotifier keyed by figure UUID. Aggregates ALL
/// figure data into a single [DossierState] for the Declassified
/// Dossier™ exhibit plate (FG-8a).
///
/// DATA SOURCES (parallel fetch):
///   Figure meta     │ F3.5 Figures    │ FATAL │ Header
///   Statements      │ PostgREST       │ NO    │ Timeline
///   Framing radar   │ F3.15 Trends    │ NO    │ Pentagon
///   Metric trend    │ F3.15 Trends    │ NO    │ Sparkline
///   Shift digest    │ N-2 ShiftAlert  │ NO    │ Badge
///   Vote record     │ F3.9 Votes      │ NO    │ Votes
///
/// COMPUTED INTELLIGENCE (zero math in build):
///   Activity class        │ Statement freq        │ Enum
///   Agreement trajectory  │ Framing agreement     │ Enum + delta
///   Topic evolution       │ Statement topics      │ New/recur
///   Variance frequency    │ variance_detected     │ Ratio + label
///   Metric extremes       │ Signal/delta/rep      │ Highs + lows
///   Framing distribution  │ framing_consensus     │ Category map
///   Statement velocity    │ Timestamps            │ Per-day rate
///   Last seen             │ Latest statement      │ DateTime
///   Avg baseline delta    │ baseline_delta_avg    │ Double
///   Avg repetition        │ repetition_avg        │ Double
///   Top topics            │ Topic frequency       │ Ranked list
///
/// TIER: Pro+. Caller gates via FeatureGate.dossier. Controller does
/// not gate internally (project pattern).
///
/// LIFECYCLE:
///   1. build(figureId): fetch Figure (fatal), then parallel fetch rest
///   2. refresh(): re-fetch all, existing data stays visible
///   3. ref.onDispose: closes keep-alive link automatically
///
/// CONCURRENCY: Epoch-guarded. Stale results silently discarded.
/// Refresh debounced via _isRefreshing bool guard.
///
/// Path: lib/controllers/dossier_mode_controller.dart
library;

// 1. Dart SDK
import 'dart:async';

// 2. Flutter

// 3. Third-party
import 'package:flutter_riverpod/flutter_riverpod.dart';

// 4. Project: config

// 5. Project: models
import 'package:baseline_app/models/figure.dart';
import 'package:baseline_app/models/vote.dart';
import 'package:baseline_app/models/trends.dart';

// 6. Project: services
import 'package:baseline_app/services/figures_service.dart';
import 'package:baseline_app/models/shift_types.dart';

// ═══════════════════════════════════════════════════════════
// CONSTANTS
// ═══════════════════════════════════════════════════════════

/// Timeout for the entire dossier aggregation (all parallel fetches).
const Duration _kDossierTimeout = Duration(seconds: 15);

// ═══════════════════════════════════════════════════════════
// JSON PARSE HELPERS
// ═══════════════════════════════════════════════════════════

/// Safely parses a dynamic JSONB value to double.
/// Rejects NaN and Infinity.
double? _parseDouble(dynamic value) {
  if (value == null) return null;
  if (value is num) {
    final d = value.toDouble();
    return d.isFinite ? d : null;
  }
  if (value is String) {
    final d = double.tryParse(value);
    return (d != null && d.isFinite) ? d : null;
  }
  return null;
}

/// Safely parses a dynamic JSONB value to int.
int? _parseInt(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

// ═══════════════════════════════════════════════════════════
// ENUMS
// ═══════════════════════════════════════════════════════════

/// Sections of the dossier that can independently fail.
///
/// Used by [DossierState.failedSections] to communicate partial
/// failures to FG-8a without killing the entire dossier.
enum DossierSection {
  /// Recent statements timeline.
  statements,

  /// 5-axis framing radar pentagon.
  framingRadar,

  /// Metric trend sparkline.
  metricTrend,

  /// Shift detection badge (N-2).
  shiftDigest,

  /// Congressional vote record.
  votes,
}

/// Availability status for a dossier section.
///
/// FG-8a uses this to distinguish "no data exists" from "fetch failed"
/// from "not available at this tier". Each renders differently.
enum SectionStatus {
  /// Data loaded successfully (may still be empty if figure has none).
  available,

  /// Fetch attempted but failed (network/parse/timeout).
  failed,

  /// Section skipped because entitlement token unavailable.
  gated,

  /// Section not applicable (e.g., votes for non-congressional).
  notApplicable,
}

/// How active this figure has been in the last [_kActivityWindowDays].
///
/// FG-8a renders this as a classification badge:
/// - silent: gray, no pulse
/// - quiet: dim teal, subtle
/// - active: teal, standard pulse
/// - surging: bright teal, accelerated pulse
enum ActivityLevel {
  /// Zero statements in the activity window.
  silent('SILENT'),

  /// 1-2 statements in the activity window.
  quiet('QUIET'),

  /// 3-6 statements in the activity window.
  active('ACTIVE'),

  /// 7+ statements in the activity window.
  surging('SURGING');

  const ActivityLevel(this.label);

  /// Display label for the activity badge.
  final String label;
}

/// Direction of model agreement trajectory over recent statements.
///
/// Computed from framing_agreement_count trend across statements.
/// FG-8a renders this as a directional indicator.
enum AgreementTrajectory {
  /// Agreement trending upward (models converging).
  converging('CONVERGING'),

  /// Agreement trending downward (models diverging).
  diverging('DIVERGING'),

  /// Agreement stable (minimal change).
  stable('STABLE'),

  /// Insufficient data to compute trajectory.
  unknown('-');

  const AgreementTrajectory(this.label);

  /// Display label for the trajectory indicator.
  final String label;
}

// ═══════════════════════════════════════════════════════════
// DOSSIER STATE
// ═══════════════════════════════════════════════════════════

/// Complete aggregated state for the Declassified Dossier™.
///
/// Wrapped in AsyncValue by the family AsyncNotifier:
/// - AsyncLoading: initial aggregation in progress
/// - AsyncData(DossierState): dossier ready (may have partial failures)
/// - AsyncError: fatal failure (figure fetch failed)
///
/// FG-8a reads sections via convenience getters and checks
/// [sectionAvailability] to decide how to render each section.
/// ALL computed intelligence is pre-baked. Zero iteration or
/// math in build().
///
/// **totalStatementCount convention:**
/// - Positive int: exact count from count query.
/// - -1 sentinel: count query failed but statements loaded. FG-8a
///   should render "20+" (or `recentStatements.length` + "+") instead
///   of displaying -1. Only set when count fails AND the data query
///   hit [_kDossierStatementLimit], meaning the true total is unknown.
class DossierState {
  const DossierState({
    required this.figure,
    this.recentStatements = const [],
    this.totalStatementCount = 0,
    this.framingRadar,
    this.metricTimeline,
    this.shiftDigest,
    this.votes = const [],
    this.totalVoteCount = 0,
    this.failedSections = const {},
    this.gatedSections = const {},
    this.isRefreshing = false,
    // Pre-computed intelligence.
    this.activityLevel = ActivityLevel.silent,
    this.agreementTrajectory = AgreementTrajectory.unknown,
    this.agreementTrajectoryDelta = 0.0,
    this.averageRepetition,
    this.averageBaselineDelta,
    this.averageAgreementRatio,
    this.topTopics = const [],
    this.newTopics = const [],
    this.recurringTopics = const [],
    this.varianceRatio = 0.0,
    this.varianceCount = 0,
    this.statementVelocity = 0.0,
    this.lastSeenAt,
    this.highestSignalRank,
    this.lowestSignalRank,
    this.mostNovelStatement,
    this.mostShiftedStatement,
    this.framingDistribution = const {},
    this.dominantFraming,
  });

  // ── Core (always present) ──────────────────────────────

  /// Figure metadata (name, role, party, photo, category).
  final Figure figure;

  // ── Statements ─────────────────────────────────────────

  /// Most recent statements (up to [_kDossierStatementLimit]).
  /// Sorted newest-first by created_at, then statement_id for
  /// deterministic tiebreak on identical timestamps.
  final List<StatementSummary> recentStatements;

  /// Total number of statements for this figure (all time).
  /// -1 sentinel = count query failed but data loaded at limit.
  /// FG-8a: render `recentStatements.length` + "+" when -1.
  final int totalStatementCount;

  // ── Framing ────────────────────────────────────────────

  /// 5-axis framing radar data (current + previous period).
  /// Null if section failed, gated, or no framing data available.
  final FramingRadarData? framingRadar;

  // ── Trends ─────────────────────────────────────────────

  /// Metric sparkline data (baseline_delta over 30d by default).
  /// Null if section failed, gated, or insufficient data.
  final MetricTimeline? metricTimeline;

  // ── Shifts ─────────────────────────────────────────────

  /// Active shift digest from N-2 (last 24h).
  /// Null if no shifts detected or section failed.
  final ShiftDigest? shiftDigest;

  // ── Votes (congressional only) ─────────────────────────

  /// Recent votes. Empty for non-congressional figures.
  final List<Vote> votes;

  /// Total vote count (all time). Zero for non-congressional.
  final int totalVoteCount;

  // ── Status ─────────────────────────────────────────────

  /// Sections that failed during fetch (network/parse/timeout).
  final Set<DossierSection> failedSections;

  /// Sections skipped because entitlement token was unavailable.
  final Set<DossierSection> gatedSections;

  /// Whether a background refresh is in progress.
  final bool isRefreshing;

  // ── Pre-computed Intelligence ──────────────────────────

  /// Activity classification based on statement frequency.
  final ActivityLevel activityLevel;

  /// Model agreement trajectory across recent statements.
  /// Computed from framing_agreement_count trend.
  final AgreementTrajectory agreementTrajectory;

  /// Magnitude of agreement trajectory change.
  /// Positive = converging, negative = diverging.
  final double agreementTrajectoryDelta;

  /// Average repetition score across recent statements.
  /// From consensus.repetition_avg. Null if unavailable.
  final double? averageRepetition;

  /// Average baseline delta across recent statements.
  /// From consensus.baseline_delta_avg. Null if unavailable.
  final double? averageBaselineDelta;

  /// Average model agreement ratio across recent statements.
  /// From framing_agreement_count / model_count. Null if unavailable.
  final double? averageAgreementRatio;

  /// Top topics by frequency (de-duplicated, min freq 2, max 8).
  final List<RankedTopic> topTopics;

  /// Topics present in the most recent statement that do NOT appear
  /// in any other statement within the current batch (up to
  /// [_kDossierStatementLimit]). Signals emerging focus areas.
  /// Note: evaluated against the recent batch only, not lifetime.
  final List<String> newTopics;

  /// Topics that appear in 50%+ of recent statements. Pattern.
  /// Uses `ceil()` threshold: at low N this is intentionally stricter
  /// (e.g., 3 statements requires 2 matches = 66%) to avoid noise.
  final List<String> recurringTopics;

  /// Ratio of statements with variance_detected == true.
  /// 0.0 = perfect agreement, 1.0 = every statement has variance.
  final double varianceRatio;

  /// Count of statements with variance detected.
  final int varianceCount;

  /// Statements per day over the activity window.
  /// Clamped to a minimum 60-minute span to prevent inflation
  /// from tightly clustered ingestion bursts.
  final double statementVelocity;

  /// Timestamp of the most recent statement (UTC). Null if none.
  final DateTime? lastSeenAt;

  /// Statement with the highest signal_rank in the batch.
  /// Null if no signal rank data available.
  final StatementSummary? highestSignalRank;

  /// Statement with the lowest signal_rank (most routine).
  /// Null if no signal rank data available.
  final StatementSummary? lowestSignalRank;

  /// Statement with the highest absolute baseline_delta.
  /// Null if no delta data available.
  final StatementSummary? mostShiftedStatement;

  /// Statement with the lowest repetition score (most novel).
  /// Null if no repetition data available.
  final StatementSummary? mostNovelStatement;

  /// Framing category distribution across recent statements.
  /// Keys = framing label, values = count.
  final Map<String, int> framingDistribution;

  /// Most frequent framing category. Null if no framing data.
  final String? dominantFraming;

  // ── Section Availability ───────────────────────────────

  /// Returns the availability status for a given section.
  ///
  /// FG-8a uses this to render distinct states:
  /// - available: show data (or "no data" if empty)
  /// - failed: show "data unavailable, retry"
  /// - gated: show tier badge / upgrade prompt
  /// - notApplicable: hide section entirely
  SectionStatus sectionAvailability(DossierSection section) {
    if (gatedSections.contains(section)) return SectionStatus.gated;
    if (failedSections.contains(section)) return SectionStatus.failed;
    if (section == DossierSection.votes && !figure.isCongressional) {
      return SectionStatus.notApplicable;
    }
    return SectionStatus.available;
  }

  // ── Convenience Getters ────────────────────────────────

  /// Figure display name.
  String get figureName => figure.name;

  /// Figure UUID.
  String get figureId => figure.figureId;

  /// Activity badge text (e.g., "ACTIVE", "SURGING").
  String get activityBadgeText => activityLevel.label;

  /// Whether this figure is congressional (has vote data).
  bool get isCongressional => figure.isCongressional;

  /// Whether framing radar data is available.
  bool get hasFramingRadar =>
      framingRadar != null &&
      sectionAvailability(DossierSection.framingRadar) ==
          SectionStatus.available;

  /// Whether metric trend data is available.
  bool get hasMetricTrend =>
      metricTimeline != null &&
      sectionAvailability(DossierSection.metricTrend) ==
          SectionStatus.available;

  /// Whether an active shift was detected.
  bool get hasActiveShift => shiftDigest != null;

  /// Shift severity for badge display. Null if no active shift.
  ShiftSeverity? get shiftSeverity => shiftDigest?.effectiveSeverity;

  /// Whether any section failed or was gated.
  bool get hasPartialFailures =>
      failedSections.isNotEmpty || gatedSections.isNotEmpty;

  /// Whether statements loaded successfully.
  bool get hasStatements =>
      recentStatements.isNotEmpty &&
      sectionAvailability(DossierSection.statements) ==
          SectionStatus.available;

  /// Whether vote data loaded successfully.
  bool get hasVotes =>
      votes.isNotEmpty &&
      sectionAvailability(DossierSection.votes) == SectionStatus.available;

  /// Whether the total statement count is an estimate (count query failed).
  bool get isTotalEstimated => totalStatementCount < 0;

  /// Human-readable "last seen" string (UTC-safe).
  /// "just now", "12 min ago", "1 hr ago", "3 hrs ago", "1 day ago", etc.
  String? get lastSeenLabel {
    if (lastSeenAt == null) return null;
    final diff = DateTime.now().toUtc().difference(lastSeenAt!);
    if (diff.isNegative) return 'just now';
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 2) return '1 hr ago';
    if (diff.inHours < 24) return '${diff.inHours} hrs ago';
    if (diff.inDays < 2) return '1 day ago';
    if (diff.inDays < 30) return '${diff.inDays} days ago';
    final months = (diff.inDays / 30).floor();
    return months == 1 ? '1 month ago' : '$months months ago';
  }

  /// Variance label for display.
  String get varianceLabel {
    if (recentStatements.isEmpty) return '-';
    if (varianceCount == 0) {
      return '0 of ${recentStatements.length}';
    }
    final pct = (varianceRatio * 100).round();
    return '$varianceCount of ${recentStatements.length} ($pct%)';
  }

  /// Velocity label for display.
  String get velocityLabel {
    if (statementVelocity >= 1.0) {
      return '${statementVelocity.toStringAsFixed(1)}/day';
    }
    final perWeek = statementVelocity * 7;
    if (perWeek >= 1.0) {
      return '${perWeek.toStringAsFixed(1)}/week';
    }
    return '< 1/week';
  }

  /// Creates a copy with optional overrides.
  DossierState copyWith({
    Figure? figure,
    List<StatementSummary>? recentStatements,
    int? totalStatementCount,
    FramingRadarData? framingRadar,
    MetricTimeline? metricTimeline,
    ShiftDigest? shiftDigest,
    List<Vote>? votes,
    int? totalVoteCount,
    Set<DossierSection>? failedSections,
    Set<DossierSection>? gatedSections,
    bool? isRefreshing,
    ActivityLevel? activityLevel,
    AgreementTrajectory? agreementTrajectory,
    double? agreementTrajectoryDelta,
    double? averageRepetition,
    double? averageBaselineDelta,
    double? averageAgreementRatio,
    List<RankedTopic>? topTopics,
    List<String>? newTopics,
    List<String>? recurringTopics,
    double? varianceRatio,
    int? varianceCount,
    double? statementVelocity,
    DateTime? lastSeenAt,
    StatementSummary? highestSignalRank,
    StatementSummary? lowestSignalRank,
    StatementSummary? mostNovelStatement,
    StatementSummary? mostShiftedStatement,
    Map<String, int>? framingDistribution,
    String? dominantFraming,
  }) {
    return DossierState(
      figure: figure ?? this.figure,
      recentStatements: recentStatements ?? this.recentStatements,
      totalStatementCount: totalStatementCount ?? this.totalStatementCount,
      framingRadar: framingRadar ?? this.framingRadar,
      metricTimeline: metricTimeline ?? this.metricTimeline,
      shiftDigest: shiftDigest ?? this.shiftDigest,
      votes: votes ?? this.votes,
      totalVoteCount: totalVoteCount ?? this.totalVoteCount,
      failedSections: failedSections ?? this.failedSections,
      gatedSections: gatedSections ?? this.gatedSections,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      activityLevel: activityLevel ?? this.activityLevel,
      agreementTrajectory: agreementTrajectory ?? this.agreementTrajectory,
      agreementTrajectoryDelta:
          agreementTrajectoryDelta ?? this.agreementTrajectoryDelta,
      averageRepetition: averageRepetition ?? this.averageRepetition,
      averageBaselineDelta: averageBaselineDelta ?? this.averageBaselineDelta,
      averageAgreementRatio:
          averageAgreementRatio ?? this.averageAgreementRatio,
      topTopics: topTopics ?? this.topTopics,
      newTopics: newTopics ?? this.newTopics,
      recurringTopics: recurringTopics ?? this.recurringTopics,
      varianceRatio: varianceRatio ?? this.varianceRatio,
      varianceCount: varianceCount ?? this.varianceCount,
      statementVelocity: statementVelocity ?? this.statementVelocity,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      highestSignalRank: highestSignalRank ?? this.highestSignalRank,
      lowestSignalRank: lowestSignalRank ?? this.lowestSignalRank,
      mostNovelStatement: mostNovelStatement ?? this.mostNovelStatement,
      mostShiftedStatement:
          mostShiftedStatement ?? this.mostShiftedStatement,
      framingDistribution: framingDistribution ?? this.framingDistribution,
      dominantFraming: dominantFraming ?? this.dominantFraming,
    );
  }
}

// ═══════════════════════════════════════════════════════════
// RANKED TOPIC
// ═══════════════════════════════════════════════════════════

/// Topic with frequency count for ranked display.
///
/// FG-8a uses both the label and ratio to render topic pills
/// with proportional sizing or opacity.
class RankedTopic {
  const RankedTopic({
    required this.label,
    required this.count,
    required this.ratio,
  });

  /// Topic label.
  final String label;

  /// Number of recent statements mentioning this topic.
  final int count;

  /// Ratio of recent statements mentioning this topic (0.0-1.0).
  final double ratio;
}

// ═══════════════════════════════════════════════════════════
// STATEMENT SUMMARY (dossier-specific projection)
// ═══════════════════════════════════════════════════════════

/// Lightweight statement projection for the dossier timeline.
///
/// Slimmer than [StatementDetail]. Only what FG-8a needs.
/// Field names match their actual data source (no misleading aliases).
class StatementSummary {
  const StatementSummary({
    required this.statementId,
    required this.headline,
    required this.createdAt,
    required this.sourceUrl,
    required this.topics,
    this.repetitionAvg,
    this.baselineDeltaAvg,
    this.signalRank,
    this.varianceDetected = false,
    this.framingConsensus,
    this.framingAgreementCount,
    this.modelCount,
  });

  final String statementId;

  /// Alias for [statementId].
  String get id => statementId;

  final String headline;

  /// Statement creation timestamp (UTC).
  final DateTime createdAt;
  final String sourceUrl;
  final List<String> topics;

  /// Average repetition score across models.
  /// From consensus.repetition_avg.
  final double? repetitionAvg;

  /// Average baseline delta (shift from historical).
  /// From consensus.baseline_delta_avg.
  final double? baselineDeltaAvg;

  /// Composite signal rank.
  /// From consensus.signal_rank.
  final double? signalRank;

  /// Whether models disagreed on this statement.
  /// From consensus.variance_detected.
  final bool varianceDetected;

  /// Consensus framing label (e.g., "Adversarial", "Commitment").
  /// Null if no consensus or split framing.
  /// From consensus.framing_consensus.
  final String? framingConsensus;

  /// Number of models that agreed on framing classification.
  /// From consensus.framing_agreement_count.
  final int? framingAgreementCount;

  /// Total number of models included in consensus.
  /// From consensus.model_count.
  final int? modelCount;

  /// Agreement ratio for this statement (0.0-1.0).
  /// Null if model_count unavailable.
  double? get agreementRatio {
    if (framingAgreementCount == null || modelCount == null) return null;
    if (modelCount == 0) return null;
    return framingAgreementCount! / modelCount!;
  }

  /// Parse from v_statements_public row (PostgREST).
  factory StatementSummary.fromRow(Map<String, dynamic> row) {
    final consensus = row['consensus'] as Map<String, dynamic>?;

    final topics = <String>[];
    final rawTopics = row['topics'];
    if (rawTopics is List) {
      for (final t in rawTopics) {
        if (t is String && t.isNotEmpty) topics.add(t);
      }
    }

    // Parse created_at as UTC to avoid local/UTC mixing.
    final rawCreatedAt = row['created_at'] as String? ?? '';
    DateTime createdAt;
    final parsed = DateTime.tryParse(rawCreatedAt);
    if (parsed != null) {
      createdAt = parsed.toUtc();
    } else {
      createdAt = DateTime.now().toUtc();
    }

    return StatementSummary(
      statementId: row['statement_id'] as String? ?? '',
      headline: row['headline'] as String? ?? '',
      createdAt: createdAt,
      sourceUrl: row['source_url'] as String? ?? '',
      topics: topics,
      repetitionAvg: _parseDouble(consensus?['repetition_avg']),
      baselineDeltaAvg: _parseDouble(consensus?['baseline_delta_avg']),
      signalRank: _parseDouble(consensus?['signal_rank']),
      varianceDetected: consensus?['variance_detected'] == true,
      framingConsensus: consensus?['framing_consensus'] as String?,
      framingAgreementCount:
          _parseInt(consensus?['framing_agreement_count']),
      modelCount: _parseInt(consensus?['model_count']),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// PROVIDER
// ═══════════════════════════════════════════════════════════

/// Riverpod family provider for dossier state, keyed by figure UUID.
///
/// Usage:
///   ref.watch(dossierProvider(figureId))
///   ref.read(dossierProvider(figureId).notifier).refresh()
final dossierProvider = AsyncNotifierProvider.family<
    DossierNotifier, DossierState, String>(
  DossierNotifier.new,
);

class DossierNotifier
    extends FamilyAsyncNotifier<DossierState, String> {
  final FiguresService _figuresService = const FiguresService();
  int _epoch = 0;

  @override
  Future<DossierState> build(String arg) async {
    ref.keepAlive();
    final epoch = ++_epoch;

    // Fatal: fetch figure metadata first.
    final figureResponse = await _figuresService
        .getActiveFigures()
        .timeout(_kDossierTimeout);

    if (epoch != _epoch) {
      throw StateError('Stale dossier build for $arg');
    }

    final figure = figureResponse.figures.cast<Figure?>().firstWhere(
      (f) => f!.figureId == arg,
      orElse: () => null,
    );

    if (figure == null) {
      throw Exception('Figure not found: $arg');
    }

    return DossierState(figure: figure);
  }

  /// Pull-to-refresh.
  Future<void> refresh() async {
    final current = state.valueOrNull;
    if (current == null) {
      ref.invalidateSelf();
      return;
    }
    if (current.isRefreshing) return;

    final epoch = ++_epoch;
    state = AsyncData(DossierState(
      figure: current.figure,
      isRefreshing: true,
    ));

    try {
      final result = await build(arg);
      if (epoch != _epoch) return;
      state = AsyncData(result);
    } catch (_) {
      if (epoch != _epoch) return;
      state = AsyncData(DossierState(
        figure: current.figure,
        isRefreshing: false,
      ));
    }
  }
}
