/// Cross-model consensus for Baseline.
///
/// Represents the consensus object from v_statement_consensus (A9A).
/// Computed by A7B after 2+ model analyses complete.
///
/// May be null in the A9C response — statements with < 2 analyses
/// or newly ingested statements won't have consensus yet.
///
/// Framing labels (locked — matches A7A):
/// - Adversarial / Oppositional
/// - Problem Identification
/// - Commitment / Forward-Looking
/// - Justification / Reactive
/// - Imperative / Directive
///
/// All parsed DateTimes are normalized to UTC via .toUtc().
///
/// JSONB fields (signalComponents, modelVersions, framingSplit) are
/// parsed defensively via `Map<String, dynamic>.from()` to handle
/// Supabase decoder variance between `Map<String, dynamic>` and
/// `Map<String, Object?>` / `Map<dynamic, dynamic>`.
///
/// Path: lib/models/consensus.dart
class Consensus {
const Consensus({
required this.consensusId,
required this.statementId,
required this.repetitionAvg,
required this.repetitionStddev,
required this.noveltyAvg,
required this.noveltyStddev,
required this.affectiveLanguageRateAvg,
required this.affectiveLanguageRateStddev,
required this.topicEntropyAvg,
required this.topicEntropyStddev,
required this.baselineDeltaAvg,
required this.signalRank,
required this.varianceDetected,
this.framingConsensus,
required this.framingAgreementCount,
this.framingSplit,
required this.signalComponents,
required this.modelVersions,
required this.modelsIncluded,
required this.modelCount,
required this.computedAt,
});
final String consensusId;
final String statementId;
// ── Metric averages (0–100 scale) ──────────────────────────────────
final double repetitionAvg;
final double repetitionStddev;
final double noveltyAvg;
final double noveltyStddev;
final double affectiveLanguageRateAvg;
final double affectiveLanguageRateStddev;
final double topicEntropyAvg;
final double topicEntropyStddev;
final double baselineDeltaAvg;
// ── Signal rank
// ────────────────────────────────────────────────────
/// Composite signal rank (0–100). Higher = more signal value.
/// Formula: 40% baseline_delta + 35% novelty + 25% (100 - repetition).
final double signalRank;
// ── Variance
// ───────────────────────────────────────────────────────
/// True when models meaningfully disagree (stddev > threshold or
/// framing split). Triggers "Variance Detected" banner in UI.
final bool varianceDetected;
// ── Framing consensus
// ──────────────────────────────────────────────
/// Majority framing label across models. Null if no majority.
final String? framingConsensus;
/// How many models agreed on the majority framing (1–3).
final int framingAgreementCount;
/// When models disagree on framing, contains the vote breakdown.
/// Expected shape: {"Adversarial / Oppositional": 2, "Problem Identification": 1}
/// Values are ints. Null when all models agree (no split).
final Map<String, dynamic>? framingSplit;
// ── Model metadata
// ─────────────────────────────────────────────────
/// Breakdown of signal components.
/// Expected shape: {"repetition": num, "novelty": num, "baseline_delta": num}
final Map<String, dynamic> signalComponents;
/// Model version strings keyed by provider.
/// Expected shape: {"OPENAI": "gpt-4o-...", "ANTHROPIC": "claude-..."}
final Map<String, dynamic> modelVersions;
/// List of model providers included (e.g. ['OPENAI', 'ANTHROPIC']).
final List<String> modelsIncluded;
/// Number of models that contributed (2 or 3).
final int modelCount;
/// When this consensus was computed.
final DateTime computedAt;
/// Whether this is a full 3-model consensus.
bool get isFullConsensus => modelCount >= 3;
/// Agreement ratio for the consensus badge (e.g. 2/3, 3/3).
String get agreementLabel => '$framingAgreementCount/$modelCount';
/// Parses a consensus JSON object from A9C response.
///
/// Throws [FormatException] if required fields are missing.
/// All timestamps are normalized to UTC.
/// JSONB maps are parsed defensively via Map.from().
factory Consensus.fromJson(Map<String, dynamic> json) {
final id = json['consensus_id'];
if (id is! String || id.isEmpty) {
throw FormatException(
'Consensus.fromJson: consensus_id missing or invalid',
json,
);
}
final statementId = json['statement_id'];
if (statementId is! String || statementId.isEmpty) {
throw FormatException(
'Consensus.fromJson: statement_id missing or invalid',
json,
);
}
final computedAtRaw = json['computed_at'];
if (computedAtRaw is! String) {
throw FormatException(
'Consensus.fromJson: computed_at missing or invalid',
json,
);
}
final computedAt = DateTime.tryParse(computedAtRaw);
if (computedAt == null) {
throw FormatException(
'Consensus.fromJson: computed_at unparseable: $computedAtRaw',
);
}
// Parse models_included — could be List<String> or List<dynamic>.
final rawModels = json['models_included'];
final modelsIncluded = rawModels is List
? rawModels.whereType<String>().toList()
: <String>[];
// Parse JSONB fields defensively — Supabase decoder may return
// Map<String, Object?> or Map<dynamic, dynamic> instead of
// Map<String, dynamic>. Use Map.from() to normalize.
final rawSignalComponents = json['signal_components'];
final signalComponents = rawSignalComponents is Map
? Map<String, dynamic>.from(rawSignalComponents)
: <String, dynamic>{};
final rawModelVersions = json['model_versions'];
final modelVersions = rawModelVersions is Map
? Map<String, dynamic>.from(rawModelVersions)
: <String, dynamic>{};
final rawFramingSplit = json['framing_split'];
final framingSplit = rawFramingSplit is Map
? Map<String, dynamic>.from(rawFramingSplit)
: null;
return Consensus(
consensusId: id,
statementId: statementId,
repetitionAvg: _safeDoubleOrZero(json['repetition_avg']),
repetitionStddev: _safeDoubleOrZero(json['repetition_stddev']),
noveltyAvg: _safeDoubleOrZero(json['novelty_avg']),
noveltyStddev: _safeDoubleOrZero(json['novelty_stddev']),
affectiveLanguageRateAvg:
_safeDoubleOrZero(json['affective_language_rate_avg']),
affectiveLanguageRateStddev:
_safeDoubleOrZero(json['affective_language_rate_stddev']),
topicEntropyAvg: _safeDoubleOrZero(json['topic_entropy_avg']),
topicEntropyStddev: _safeDoubleOrZero(json['topic_entropy_stddev']),
baselineDeltaAvg: _safeDoubleOrZero(json['baseline_delta_avg']),
signalRank: _safeDoubleOrZero(json['signal_rank']),
varianceDetected: json['variance_detected'] as bool? ?? false,
framingConsensus: json['framing_consensus'] as String?,
framingAgreementCount:
(json['framing_agreement_count'] as num?)?.toInt() ?? 0,
framingSplit: framingSplit,
signalComponents: signalComponents,
modelVersions: modelVersions,
modelsIncluded: modelsIncluded,
modelCount: (json['model_count'] as num?)?.toInt() ?? 0,
computedAt: computedAt.toUtc(),
);
}
/// Serializes for local caching / debugging.
Map<String, dynamic> toJson() => {
'consensus_id': consensusId,
'statement_id': statementId,
'repetition_avg': repetitionAvg,
'repetition_stddev': repetitionStddev,
'novelty_avg': noveltyAvg,
'novelty_stddev': noveltyStddev,
'affective_language_rate_avg': affectiveLanguageRateAvg,
'affective_language_rate_stddev': affectiveLanguageRateStddev,
'topic_entropy_avg': topicEntropyAvg,
'topic_entropy_stddev': topicEntropyStddev,
'baseline_delta_avg': baselineDeltaAvg,
'signal_rank': signalRank,
'variance_detected': varianceDetected,
'framing_consensus': framingConsensus,
'framing_agreement_count': framingAgreementCount,
'framing_split': framingSplit,
'signal_components': signalComponents,
'model_versions': modelVersions,
'models_included': modelsIncluded,
'model_count': modelCount,
'computed_at': computedAt.toIso8601String(),
};
/// Safely converts a JSON numeric to double, defaulting to 0.0.
/// Consensus metrics are NOT NULL in the DB (default 0), so zero
/// fallback is correct here — unlike nullable metrics elsewhere.
static double _safeDoubleOrZero(dynamic value) {
if (value == null) return 0.0;
if (value is num) {
final d = value.toDouble();
return d.isFinite ? d : 0.0;
}
return 0.0;
}
}
