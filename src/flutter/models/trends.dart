/// Trends models for Baseline.
///
/// Contains:
/// - TrendMetric enum - available metrics for timeline queries
/// - TrendPeriod enum - time window options (30d/90d/1y)
/// - TrendGranularity enum - bucketing options (day/week/month)
/// - TrendDataPoint - single time-series data point
/// - MetricTimeline - complete timeline response
/// - FramingRadarData - 5-axis framing distribution (current + previous)
///
/// Backend source: get-trends EF → A14A RPCs.
///
/// Two distinct query types through the same endpoint:
/// 1. Metrics Timeline (ENABLE_TRENDS) - time-series for a single metric
/// 2. Framing Radar (ENABLE_RADAR) - 5-axis distribution for current + previous period
///
/// EF routing: presence of `metric` field → timeline route. Absence → radar route.
///
/// Path: lib/models/trends.dart
library;
import 'package:flutter/foundation.dart';
import 'package:baseline_app/models/framing.dart';
//
// ════════════════════════════════════════════════════════════
// ═══════════
// TREND METRIC ENUM
//
// ════════════════════════════════════════════════════════════
// ═══════════
/// Available metrics for timeline queries.
///
/// Maps to consensus column averages in A14A get_historical_trends RPC.
/// Backend accepts these exact strings as the "metric" parameter.
enum TrendMetric {
repetition,
novelty,
affectiveLanguageRate,
topicEntropy,
baselineDelta,
signalRank;
/// Backend parameter value (exact string sent in request body).
String get value {
switch (this) {
case TrendMetric.repetition:
return 'repetition';
case TrendMetric.novelty:
return 'novelty';
case TrendMetric.affectiveLanguageRate:
return 'affective_language_rate';
case TrendMetric.topicEntropy:
return 'topic_entropy';
case TrendMetric.baselineDelta:
return 'baseline_delta';
case TrendMetric.signalRank:
return 'signal_rank';
}
}
/// Display label for UI (tappable metric selector).
String get label {
switch (this) {
case TrendMetric.repetition:
return 'Repetition';
case TrendMetric.novelty:
return 'Novelty';
case TrendMetric.affectiveLanguageRate:
return 'Affect';
case TrendMetric.topicEntropy:
return 'Entropy';
case TrendMetric.baselineDelta:
return 'Baseline Δ';
case TrendMetric.signalRank:
return 'Signal Rank';
}
}
/// Info sheet key for tap-to-explain (matches F1.10 kInfoSheetCopy keys).
String get infoKey {
switch (this) {
case TrendMetric.repetition:
return 'repetition';
case TrendMetric.novelty:
return 'novelty';
case TrendMetric.affectiveLanguageRate:
return 'affect';
case TrendMetric.topicEntropy:
return 'entropy';
case TrendMetric.baselineDelta:
return 'baseline_delta';
case TrendMetric.signalRank:
return 'signal_rank';
}
}
}
//
// ════════════════════════════════════════════════════════════
// ═══════════
// TREND PERIOD ENUM
//
// ════════════════════════════════════════════════════════════
// ═══════════
/// Time window options for trend queries.
///
/// UI shows these as pill selectors: [30d] [90d] [1y]
enum TrendPeriod {
thirtyDays,
ninetyDays,
oneYear;
/// Backend parameter value.
String get value {
switch (this) {
case TrendPeriod.thirtyDays:
return '30d';
case TrendPeriod.ninetyDays:
return '90d';
case TrendPeriod.oneYear:
return '1y';
}
}
/// Display label for pill selector.
String get label {
switch (this) {
case TrendPeriod.thirtyDays:
return '30d';
case TrendPeriod.ninetyDays:
return '90d';
case TrendPeriod.oneYear:
return '1y';
}
}
/// Parses backend period string to enum.
static TrendPeriod? fromString(String? value) {
if (value == null) return null;
switch (value) {
case '30d':
return TrendPeriod.thirtyDays;
case '90d':
return TrendPeriod.ninetyDays;
case '1y':
return TrendPeriod.oneYear;
default:
return null;
}
}
}
//
// ════════════════════════════════════════════════════════════
// ═══════════
// TREND GRANULARITY ENUM
//
// ════════════════════════════════════════════════════════════
// ═══════════
/// Bucketing granularity for metric timeline.
///
/// F0.1c lists "day | week | month". A14A RPCs support week/month
/// natively; day passes through and may return fine-grained data.
enum TrendGranularity {
day,
week,
month;
/// Backend parameter value.
String get value {
switch (this) {
case TrendGranularity.day:
return 'day';
case TrendGranularity.week:
return 'week';
case TrendGranularity.month:
return 'month';
}
}
}
//
// ════════════════════════════════════════════════════════════
// ═══════════
// TREND DATA POINT
//
// ════════════════════════════════════════════════════════════
// ═══════════
/// Single time-series data point from metrics timeline.
///
/// Represents one bucketed average for a metric over a time period.
/// [date] is the bucket start (ISO 8601 date string, parsed to DateTime).
/// [value] is the average metric value for that bucket (0–100 scale,
/// clamped defensively).
/// [count] is how many statements were in that bucket.
class TrendDataPoint {
const TrendDataPoint({
required this.date,
required this.value,
required this.count,
});

int get statementCount => count;
/// Bucket start date (UTC).
final DateTime date;
/// Average metric value for this bucket (0–100, clamped).
final double value;
/// Number of statements in this bucket.
final int count;
/// Parses a data point from the get-trends response.
///
/// Throws [FormatException] if required fields are missing,
/// value is non-finite, or date is unparseable.
factory TrendDataPoint.fromJson(Map<String, dynamic> json) {
final dateRaw = json['date'];
if (dateRaw is! String || dateRaw.isEmpty) {
throw FormatException(
'TrendDataPoint.fromJson: date missing or invalid',
json,
);
}
final date = DateTime.tryParse(dateRaw);
if (date == null) {
throw FormatException(
'TrendDataPoint.fromJson: date unparseable: "$dateRaw"',
json,
);
}
final valueRaw = json['value'];
if (valueRaw is! num) {
throw FormatException(
'TrendDataPoint.fromJson: value missing or not a number',
json,
);
}
final valueDouble = valueRaw.toDouble();
if (!valueDouble.isFinite) {
throw FormatException(
'TrendDataPoint.fromJson: value is non-finite ($valueRaw)',
json,
);
}
return TrendDataPoint(
date: date.toUtc(),
value: valueDouble.clamp(0.0, 100.0),
count: (json['count'] as num?)?.toInt() ?? 0,
);
}
}
//
// ════════════════════════════════════════════════════════════
// ═══════════
// METRIC TIMELINE
//
// ════════════════════════════════════════════════════════════
// ═══════════
/// Complete metrics timeline response.
///
/// Contains the time-series data points for a single metric over
/// a given period for a figure. Powers the Trends screen line charts.
class MetricTimeline {
const MetricTimeline({
required this.figureId,
required this.metric,
required this.period,
required this.dataPoints,
});

List<TrendDataPoint> get points => dataPoints;
/// Figure this timeline belongs to.
final String figureId;
/// Which metric this timeline represents (backend string).
final String metric;
/// Period requested (e.g. "30d", "90d", "1y").
final String period;
/// Time-series data points, ordered chronologically (oldest first).
final List<TrendDataPoint> dataPoints;
/// Whether this timeline has any data.
bool get isEmpty => dataPoints.isEmpty;
/// Total statements across all buckets.
int get totalStatements =>
dataPoints.fold(0, (sum, dp) => sum + dp.count);
/// Parses from get-trends response body.
///
/// Throws [FormatException] if required metadata fields are missing
/// or empty. Malformed data points are skipped (partial data > crash).
factory MetricTimeline.fromJson(Map<String, dynamic> json) {
final figureId = json['figure_id'] as String?;
if (figureId == null || figureId.isEmpty) {
throw FormatException(
'MetricTimeline.fromJson: figure_id missing or empty',
json,
);
}
final metric = json['metric'] as String?;
if (metric == null || metric.isEmpty) {
throw FormatException(
'MetricTimeline.fromJson: metric missing or empty',
json,
);
}
final period = json['period'] as String?;
if (period == null || period.isEmpty) {
throw FormatException(
'MetricTimeline.fromJson: period missing or empty',
json,
);
}
final rawPoints = json['data_points'];
if (rawPoints is! List) {
return MetricTimeline(
figureId: figureId,
metric: metric,
period: period,
dataPoints: const [],
);
}
final dataPoints = <TrendDataPoint>[];
for (final item in rawPoints) {
if (item is Map<String, dynamic>) {
try {
dataPoints.add(TrendDataPoint.fromJson(item));
} on FormatException {
// Skip malformed data points - partial data better than crash
}
}
}
return MetricTimeline(
figureId: figureId,
metric: metric,
period: period,
dataPoints: dataPoints,
);
}
}
//
// ════════════════════════════════════════════════════════════
// ═══════════
// FRAMING RADAR DATA
//
// ════════════════════════════════════════════════════════════
// ═══════════
/// 5-axis framing distribution for the Framing Radar™ screen.
///
/// Contains current period distribution + optional previous period
/// for comparison overlay (filled polygon vs outline polygon).
///
/// Values are 0.0–1.0 proportions (not 0–100). Backend EF divides
/// A14A's percentage by 100 before returning.
///
/// Framing axes use FramingCategory enum from F3.7 for type safety.
/// Unknown labels (e.g. "No Consensus") are skipped during parsing
/// with a debug log.
///
/// IMPORTANT: 5-axis pentagon ONLY. Never 6 axes.
class FramingRadarData {
const FramingRadarData({
required this.figureId,
required this.period,
required this.current,
this.previous,
this.totalStatements,
});

/// Current period framing distribution map (alias for [current]).
Map<FramingCategory, double> get currentPeriod => current;
/// Figure this radar belongs to.
final String figureId;
/// Period requested (e.g. "30d", "90d", "1y").
final String period;
/// Current period framing distribution.
/// Keys = FramingCategory enum values, Values = 0.0–1.0 proportion.
/// May have fewer than 5 entries if some categories had no statements.
final Map<FramingCategory, double> current;
/// Previous period framing distribution (for comparison overlay).
/// Null if insufficient historical data.
final Map<FramingCategory, double>? previous;
/// Total statements analyzed in the current period (from backend).
/// Null if backend omits.
final int? totalStatements;
/// Whether the current period has any data.
bool get isEmpty => current.isEmpty;
/// Whether comparison data is available.
bool get hasComparison => previous != null && previous!.isNotEmpty;
/// Safe total: uses backend value if available, else sums nothing (0).
/// Use this in UI instead of accessing totalStatements directly.
int get effectiveTotalStatements => totalStatements ?? 0;
/// Gets value for a specific axis, defaulting to 0.0 if missing.
/// Used by the radar chart painter for vertex positioning.
double currentValueFor(FramingCategory category) =>
current[category] ?? 0.0;
/// Gets previous value for a specific axis, defaulting to 0.0.
double previousValueFor(FramingCategory category) =>
previous?[category] ?? 0.0;
/// Parses the framing radar response from get-trends.
///
/// Throws [FormatException] if required metadata (figureId, period)
/// is missing or empty. Filters out unknown framing labels with
/// debug logging. Clamps values to 0.0–1.0 defensively.
factory FramingRadarData.fromJson(Map<String, dynamic> json) {
final figureId = json['figure_id'] as String?;
if (figureId == null || figureId.isEmpty) {
throw FormatException(
'FramingRadarData.fromJson: figure_id missing or empty',
json,
);
}
final period = json['period'] as String?;
if (period == null || period.isEmpty) {
throw FormatException(
'FramingRadarData.fromJson: period missing or empty',
json,
);
}
final currentRaw = json['current'];
final current = _parseFramingMap(currentRaw);
final previousRaw = json['previous'];
final previous = previousRaw != null ? _parseFramingMap(previousRaw) : null;
final totalStatements = (json['total_statements'] as num?)?.toInt();
return FramingRadarData(
figureId: figureId,
period: period,
current: current,
previous: previous,
totalStatements: totalStatements,
);
}
/// Parses a framing distribution map from JSON.
///
/// Expects: {"Adversarial / Oppositional": 0.35, ...}
/// Returns: {FramingCategory.adversarial: 0.35, ...}
/// Skips unknown labels (e.g. "No Consensus") with debug log.
/// Clamps values to 0.0–1.0.
static Map<FramingCategory, double> _parseFramingMap(dynamic raw) {
if (raw is! Map) return const {};
final result = <FramingCategory, double>{};
for (final entry in raw.entries) {
final label = entry.key?.toString();
if (label == null) continue;
final category = FramingCategory.fromBackendLabel(label);
if (category == null) {
if (kDebugMode) {
debugPrint(
'FramingRadarData: skipping unknown framing label: "$label"',
);
}
continue;
}
final value = entry.value;
if (value is! num) continue;
result[category] = value.toDouble().clamp(0.0, 1.0);
}
return result;
}
}
