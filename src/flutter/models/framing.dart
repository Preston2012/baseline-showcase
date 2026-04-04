/// Framing models for Baseline (Framing Radar™).
///
/// Contains:
/// - FramingCategory enum (type-safe mapping of backend framing strings)
/// - FramingDistribution (current + previous period radar data)
///
/// LOCKED: 5-axis pentagon. Never 6.
/// Backend framing labels (A1 + A3 + A14A):
/// 1. "Adversarial / Oppositional"
/// 2. "Problem Identification"
/// 3. "Commitment / Forward-Looking"
/// 4. "Justification / Reactive"
/// 5. "Imperative / Directive"
///
/// Path: lib/models/framing.dart
//
// ════════════════════════════════════════════════════════════
// ═══════════
// FRAMING CATEGORY ENUM
//
// ════════════════════════════════════════════════════════════
// ═══════════
/// Type-safe representation of the 5 framing categories.
///
/// Required by F0.1c: "Frontend MUST convert to internal enum keys for
/// type safety, chart mapping, and resistance to spacing drift."
///
/// Parse from backend: [fromBackendLabel]
/// Display to user: [label] (exact backend string preserved)
/// Radar chart axes: use enum for ordering, [label] for display
/// NEVER use raw strings as Map keys in business logic.
library;
enum FramingCategory {
/// "Adversarial / Oppositional"
adversarial,
/// "Problem Identification"
problem,
/// "Commitment / Forward-Looking"
commitment,
/// "Justification / Reactive"
justification,
/// "Imperative / Directive"
imperative;
/// Exact backend label string (with slashes and spacing preserved).
/// Used for display in radar chart axis labels.
String get label {
switch (this) {
case FramingCategory.adversarial:
return 'Adversarial / Oppositional';
case FramingCategory.problem:
return 'Problem Identification';
case FramingCategory.commitment:
return 'Commitment / Forward-Looking';
case FramingCategory.justification:
return 'Justification / Reactive';
case FramingCategory.imperative:
return 'Imperative / Directive';
}
}
/// Short label for compact display (e.g., radar axis when space-constrained).
String get shortLabel {
switch (this) {
case FramingCategory.adversarial:
return 'Adversarial';
case FramingCategory.problem:
return 'Problem ID';
case FramingCategory.commitment:
return 'Commitment';
case FramingCategory.justification:
return 'Justification';
case FramingCategory.imperative:
return 'Imperative';
}
}
/// Parses a backend framing label string to enum.
///
/// Matches the exact strings stored in A1 schema + returned by A3 prompts.
/// Trims whitespace to tolerate minor backend formatting variance.
/// Returns null if the string doesn't match any known category.
static FramingCategory? fromBackendLabel(String? label) {
if (label == null) return null;
final trimmed = label.trim();
for (final cat in FramingCategory.values) {
if (cat.label == trimmed) return cat;
}
return null;
}
/// Ordered list for radar chart rendering.
/// This order determines the polygon vertex positions (clockwise from top).
static const List<FramingCategory> radarOrder = [
FramingCategory.adversarial,
FramingCategory.problem,
FramingCategory.commitment,
FramingCategory.justification,
FramingCategory.imperative,
];
}
//
// ════════════════════════════════════════════════════════════
// ═══════════
// FRAMING DISTRIBUTION
//
// ════════════════════════════════════════════════════════════
// ═══════════
/// Framing distribution for the Framing Radar™.
///
/// Contains percentage distributions across the 5 framing categories
/// for a current and (optionally) previous time period.
///
/// Values are 0.0–1.0 proportions (not 0–100 percentages).
/// The radar chart maps these directly to vertex distances from center.
///
/// [current] always contains all 5 categories (missing ones default to 0.0).
/// [previous] is the equivalent preceding period for comparison overlay.
/// - 30d current → previous = prior 30d
/// - 90d current → previous = prior 90d
/// - 1y current → previous = prior 1y
/// Null if insufficient historical data.
class FramingDistribution {
const FramingDistribution({
required this.figureId,
required this.period,
required this.current,
this.previous,
this.totalStatements,
});
/// Figure this distribution belongs to.
final String figureId;
/// Period string (e.g., "30d", "90d", "1y").
final String period;
/// Current period distribution: category → proportion (0.0–1.0).
/// Always contains all 5 categories (missing ones filled with 0.0).
final Map<FramingCategory, double> current;
/// Previous period distribution for comparison overlay. Null if
/// insufficient data for a full previous period.
/// When present, always contains all 5 categories.
final Map<FramingCategory, double>? previous;
/// Total statements analyzed in the current period. Null if not
/// returned by backend.
final int? totalStatements;
/// Safe total: uses backend value if available, else 0.
int get effectiveTotalStatements => totalStatements ?? 0;

/// Whether previous period data is available for comparison.
bool get hasPrevious => previous != null && previous!.isNotEmpty;
/// The dominant framing category in the current period.
/// Null if all values are 0.0 (no data).
FramingCategory? get dominantCategory {
if (current.isEmpty) return null;
final max = current.entries
.reduce((a, b) => a.value >= b.value ? a : b);
// If dominant value is 0.0, there's no meaningful data
if (max.value == 0.0) return null;
return max.key;
}
/// Whether framing shifted between periods (dominant category changed).
/// Null if no previous data.
bool? get hasShift {
if (!hasPrevious) return null;
final prevMax = previous!.entries
.reduce((a, b) => a.value >= b.value ? a : b);
if (prevMax.value == 0.0) return null;
return dominantCategory != prevMax.key;
}
/// Parses the get-trends (Framing Radar) response.
///
/// Response shape (from A14A RPCs + F0.1c + backend reference):
/// ```json
/// {
/// "figure_id": "uuid",
/// "period": "30d",
/// "current": { "Adversarial / Oppositional": 0.35, ... },
/// "previous": { ... } | null,
/// "total_statements": 45
/// }
/// ```
///
/// Backend returns framing labels as keys. This parser converts
/// them to FramingCategory enums. Unknown labels are skipped to
/// tolerate backend noise (NOT to support adding a 6th axis —
/// the radar is locked at 5 axes).
///
/// Scale auto-detection: if any value > 1.0, assumes 0–100 scale
/// and divides all values by 100. This handles the case where the
/// EF returns A14A's raw percentage instead of converting to
/// proportions.
///
/// Output is always normalized to include all 5 categories
/// (missing ones filled with 0.0) for deterministic radar rendering.
///
/// Throws [FormatException] if required fields are missing.
factory FramingDistribution.fromJson(Map<String, dynamic> json) {
final figureId = json['figure_id'];
if (figureId is! String || figureId.isEmpty) {
throw FormatException(
'FramingDistribution.fromJson: figure_id missing or invalid',
json,
);
}
final period = json['period'];
if (period is! String || period.isEmpty) {
throw FormatException(
'FramingDistribution.fromJson: period missing or invalid',
json,
);
}
final currentRaw = json['current'];
if (currentRaw is! Map) {
throw FormatException(
'FramingDistribution.fromJson: current missing or not a map',
json,
);
}
final current = _parseDistribution(Map<String, dynamic>.from(currentRaw));
final previousRaw = json['previous'];
final Map<FramingCategory, double>? previous;
if (previousRaw is Map) {
previous = _parseDistribution(Map<String, dynamic>.from(previousRaw));
} else {
previous = null;
}
final totalStatements = (json['total_statements'] as num?)?.toInt();
return FramingDistribution(
figureId: figureId,
period: period,
current: current,
previous: previous,
totalStatements: totalStatements,
);
}
/// Parses a raw { "label": proportion } map into typed enum map.
///
/// Unknown labels are skipped to tolerate backend noise.
/// Non-finite values are skipped.
///
/// Scale auto-detection: if any value > 1.0, all values are
/// divided by 100 (handles 0–100 percentage scale from A14A RPC).
///
/// Output is normalized to always include all 5 FramingCategory
/// values. Missing categories default to 0.0 so the radar chart
/// always has 5 vertices in deterministic order.
static Map<FramingCategory, double> _parseDistribution(
Map<String, dynamic> raw,
) {
// ── Step 1: Parse known categories ────────────────────────────────
final parsed = <FramingCategory, double>{};
for (final entry in raw.entries) {
final cat = FramingCategory.fromBackendLabel(entry.key);
if (cat == null) continue; // Unknown label — skip (noise tolerance)
final val = entry.value;
if (val is num && val.toDouble().isFinite) {
parsed[cat] = val.toDouble();
}
}
// ── Step 2: Auto-detect scale (0–100 vs 0.0–1.0) ─────────────────
// A14A RPC returns "percentage" (0–100). The EF should divide by 100,
// but if it doesn't, all values >1.0 would be wrong. Detect and fix.
final needsScaling = parsed.values.any((v) => v > 1.0 && v <= 100.0);
if (needsScaling) {
for (final key in parsed.keys.toList()) {
parsed[key] = parsed[key]! / 100.0;
}
}
// ── Step 3: Clamp to 0.0–1.0 ──────────────────────────────────────
for (final key in parsed.keys.toList()) {
final d = parsed[key]!;
parsed[key] = d < 0.0 ? 0.0 : (d > 1.0 ? 1.0 : d);
}
// ── Step 4: Normalize to all 5 categories ─────────────────────────
// Radar chart (F4.10) requires exactly 5 vertices in deterministic
// order. Missing categories default to 0.0.
final result = <FramingCategory, double>{};
for (final cat in FramingCategory.radarOrder) {
result[cat] = parsed[cat] ?? 0.0;
}
return result;
}
/// Serializes for local caching / debugging.
///
/// All keys are known FramingCategory enums (locked at 5).
/// Uses backend label strings as keys for round-trip compatibility.
Map<String, dynamic> toJson() => {
'figure_id': figureId,
'period': period,
'current': {
for (final e in current.entries) e.key.label: e.value,
},
if (previous != null)
'previous': {
for (final e in previous!.entries) e.key.label: e.value,
},
'total_statements': totalStatements,
};
}
