/// Lens Lab™ data models for Baseline.
///
/// Contains:
/// - LensMetric — 4 numeric metrics (Repetition, Novelty, Affect, Entropy)
/// - LensMetricValue — single model's value for a metric
/// - MetricComparison — per-metric 3-model side-by-side
/// - LensFramingValue — single model's framing classification
/// - FramingComparison — framing agreement/split detection
/// - LensComparison — top-level view-model for Lens Lab screen
///
/// ALL data originates from get-statement (A9C) response.
/// No additional API calls. Pure transformation of Analysis + Consensus.
///
/// Brand neutrality: Models don't "think" or "believe" — they produce
/// measurements. Say "GP analysis:" not "OpenAI thinks..."
///
/// Path: lib/models/lens_lab.dart
library;
import 'package:baseline_app/models/analysis.dart';
import 'package:baseline_app/models/consensus.dart';
//
// ════════════════════════════════════════════════════════════
// ═══════════
// METRIC IDENTIFIERS
//
// ════════════════════════════════════════════════════════════
// ═══════════
/// The 4 numeric metrics displayed in the Lens Lab.
///
/// Maps to Analysis model fields and Consensus avg/stddev pairs.
/// Order here = display order on Lens Lab screen (matches mockup).
enum LensMetric {
/// Repetition score (0–100). Higher = more repetitive language.
repetition,
/// Novelty score (0–100). Higher = more novel semantic content.
novelty,
/// Affective language rate (0–100). Higher = more emotional language.
affective,
/// Topic entropy (0–100). Higher = more diverse topic coverage.
entropy;
/// Display label for section headers.
String get label {
switch (this) {
case LensMetric.repetition:
return 'Repetition';
case LensMetric.novelty:
return 'Novelty';
case LensMetric.affective:
return 'Affect';
case LensMetric.entropy:
return 'Entropy';
}
}
/// Info sheet key for tap-to-explain (maps to kInfoSheetCopy in F1.10).
String get infoKey {
switch (this) {
case LensMetric.repetition:
return 'lens_repetition';
case LensMetric.novelty:
return 'lens_novelty';
case LensMetric.affective:
return 'lens_affective';
case LensMetric.entropy:
return 'lens_entropy';
}
}
/// Extracts this metric's value from an [Analysis] object.
double valueFrom(Analysis analysis) {
switch (this) {
case LensMetric.repetition:
return analysis.repetition;
case LensMetric.novelty:
return analysis.novelty;
case LensMetric.affective:
return analysis.affectiveLanguageRate;
case LensMetric.entropy:
return analysis.topicEntropy;
}
}
/// Extracts this metric's consensus average from a [Consensus] object.
double avgFrom(Consensus consensus) {
switch (this) {
case LensMetric.repetition:
return consensus.repetitionAvg;
case LensMetric.novelty:
return consensus.noveltyAvg;
case LensMetric.affective:
return consensus.affectiveLanguageRateAvg;
case LensMetric.entropy:
return consensus.topicEntropyAvg;
}
}
/// Extracts this metric's consensus stddev from a [Consensus] object.
double stddevFrom(Consensus consensus) {
switch (this) {
case LensMetric.repetition:
return consensus.repetitionStddev;
case LensMetric.novelty:
return consensus.noveltyStddev;
case LensMetric.affective:
return consensus.affectiveLanguageRateStddev;
case LensMetric.entropy:
return consensus.topicEntropyStddev;
}
}
}
//
// ════════════════════════════════════════════════════════════
// ═══════════
// METRIC COMPARISON (per-metric, per-model)
//
// ════════════════════════════════════════════════════════════
// ═══════════
/// A single model's value for a given metric.
class LensMetricValue {
const LensMetricValue({
required this.provider,
required this.providerLabel,
required this.value,
});
/// Backend provider string: 'OPENAI', 'ANTHROPIC', 'XAI'.
final String provider;
/// Display label: 'GP', 'CL', 'GR'.
final String providerLabel;
/// Metric value (0–100).
final double value;
}
/// Per-metric comparison across all available models.
///
/// Used by the Lens Lab screen to render side-by-side bars for
/// GP / CL / GR within a single metric section (e.g., "Repetition").
class MetricComparison {
const MetricComparison({
required this.metric,
required this.values,
this.consensusAvg,
this.consensusStddev,
});
/// Which metric this comparison represents.
final LensMetric metric;
/// Per-model values, ordered: GP → CL → GR (display order).
/// May have 1–3 entries depending on which models have analyzed.
/// Never empty — MetricComparison is only created if ≥1 value exists.
final List<LensMetricValue> values;
/// Consensus average for ALL view. Null if consensus unavailable
/// or if fewer than 2 models contributed (consensus not meaningful).
final double? consensusAvg;
/// Consensus stddev for spread indicator. Null if unavailable.
final double? consensusStddev;
/// The range (max - min) across models. Useful for highlighting
/// divergence. Returns 0.0 if fewer than 2 models.
double get spread {
if (values.length < 2) return 0.0;
final vals = values.map((v) => v.value);
return vals.reduce((a, b) => a > b ? a : b) -
vals.reduce((a, b) => a < b ? a : b);
}
}
//
// ════════════════════════════════════════════════════════════
// ═══════════
// FRAMING COMPARISON
//
// ════════════════════════════════════════════════════════════
// ═══════════
/// A single model's framing classification.
class LensFramingValue {
const LensFramingValue({
required this.provider,
required this.providerLabel,
required this.framing,
});
/// Backend provider string.
final String provider;
/// Display label: 'GP', 'CL', 'GR'.
final String providerLabel;
/// Exact framing label from backend (e.g., "Adversarial / Oppositional").
final String framing;
}
/// Framing comparison across all available models.
///
/// Detects whether models agree (consensus) or disagree (split) on
/// framing classification. Drives the "SPLIT" indicator and
/// "Variance Detected" banner on the Lens Lab screen.
class FramingComparison {
const FramingComparison({
required this.values,
this.consensusFraming,
this.framingAgreementCount,
});
/// Per-model framing values, ordered: GP → CL → GR.
final List<LensFramingValue> values;
/// Consensus framing label. Null if no consensus or if split.
final String? consensusFraming;
/// Number of models that agree on framing from consensus data.
/// Null if consensus unavailable.
final int? framingAgreementCount;
/// Computed agreement count with fallback.
/// Uses consensus data if available, otherwise computes from values.
int get agreementCount {
if (framingAgreementCount != null) return framingAgreementCount!;
if (values.isEmpty) return 0;
if (isUnanimous) return values.length;
// Count the most common framing
final counts = <String, int>{};
for (final v in values) {
counts[v.framing] = (counts[v.framing] ?? 0) + 1;
}
return counts.values.reduce((a, b) => a > b ? a : b);
}
/// Whether all models agree on framing.
bool get isUnanimous =>
values.length > 1 &&
values.every((v) => v.framing == values.first.framing);
/// Whether there's a framing split (at least 2 models disagree).
bool get hasSplit => values.length > 1 && !isUnanimous;
/// Unique framing labels present across models.
Set<String> get uniqueFramings => values.map((v) => v.framing).toSet();
}
//
// ════════════════════════════════════════════════════════════
// ═══════════
// LENS COMPARISON (top-level view-model)
//
// ════════════════════════════════════════════════════════════
// ═══════════
/// Top-level view-model for the Lens Lab™ screen.
///
/// Aggregates all per-metric comparisons, framing comparison, and
/// metadata needed to render the full Lens Lab experience.
///
/// Created by [LensLabService.buildComparison] from raw Analysis +
/// Consensus data. No API calls — pure transformation.
class LensComparison {
const LensComparison({
required this.metrics,
required this.framing,
required this.availableLenses,
required this.modelCount,
required this.varianceDetected,
});
/// Per-metric comparisons in display order (Repetition → Novelty →
/// Affect → Entropy). Empty if no analyses available.
final List<MetricComparison> metrics;
/// Framing comparison across models.
final FramingComparison framing;
/// Which lens codes are available ('GP', 'CL', 'GR').
/// Used by LensToggle (F2.4) to disable missing model pills.
final Set<String> availableLenses;
/// Number of recognized models that contributed analyses.
final int modelCount;
/// Whether consensus flagged variance (from Consensus.varianceDetected).
final bool varianceDetected;
/// Whether the Lens Lab has enough data to show anything.
/// False if no analyses were available.
bool get hasData => metrics.isNotEmpty && modelCount > 0;
/// Retrieves a specific metric comparison by type.
///
/// Throws [StateError] if metric is missing — should never happen
/// when hasData is true, as buildComparison creates all 4 metrics.
MetricComparison metricFor(LensMetric metric) {
for (final m in metrics) {
if (m.metric == metric) return m;
}
throw StateError('LensComparison: missing metric $metric');
}
}
