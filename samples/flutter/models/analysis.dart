// Baseline Data Model: Per-model AI Analysis
// github.com/Preston2012/baseline-showcase

/// Per-model analysis for Baseline.
///
/// Represents a single analysis row from v_statement_analysis (A9A).
/// Each statement may have 2–3 analyses (OPENAI, ANTHROPIC, optional XAI).
///
/// Metrics are 0–100 scale. Framing is one of 5 canonical labels.
///
/// Framing labels (locked — matches A7A VALID_FRAMING):
/// - Adversarial / Oppositional
/// - Problem Identification
/// - Commitment / Forward-Looking
/// - Justification / Reactive
/// - Imperative / Directive
///
/// All parsed DateTimes are normalized to UTC via .toUtc().
///
/// Path: lib/models/analysis.dart
class Analysis {
const Analysis({
required this.analysisId,
required this.statementId,
required this.modelProvider,
required this.modelVersion,
required this.promptVersion,
required this.repetition,
required this.novelty,
required this.affectiveLanguageRate,
required this.topicEntropy,
required this.framing,
required this.analyzedAt,
});
final String analysisId;
final String statementId;
/// Model provider: 'OPENAI', 'ANTHROPIC', or 'XAI'.
final String modelProvider;
/// Specific model version string (e.g. 'gpt-4o-2024-05-13').
final String modelVersion;
/// Prompt version used for this analysis (e.g. 'analysis_v1.3.1').
final String promptVersion;
/// Repetition score (0–100). Higher = more repetitive language.
final double repetition;
/// Novelty score (0–100). Higher = more novel semantic content.
final double novelty;
/// Affective language rate (0–100). Higher = more emotional language.
final double affectiveLanguageRate;
/// Topic entropy (0–100). Higher = more diverse topic coverage.
final double topicEntropy;
/// Framing classification. One of 5 canonical labels.
final String framing;
/// When this analysis was computed.
final DateTime analyzedAt;
/// Short display label for the model provider.
///
/// Maps backend provider strings to Lens Lab pill labels:
/// OPENAI → GP
/// ANTHROPIC → CL
/// XAI → GR
///
/// NOTE: Keep in sync with LensToggle (F2.4) pill labels.
/// If a 4th provider is added, this defaults to the raw provider
/// string (forward-compatible, not a crash).
String get providerLabel {
switch (modelProvider) {
case 'OPENAI':
return 'GP';
case 'ANTHROPIC':
return 'CL';
case 'XAI':
return 'GR';
default:
return modelProvider;
}
}
/// Parses an analysis JSON object from A9C response.
///
/// Throws [FormatException] if required fields are missing or invalid.
/// All timestamps are normalized to UTC.
factory Analysis.fromJson(Map<String, dynamic> json) {
final id = json['analysis_id'];
if (id is! String || id.isEmpty) {
throw FormatException(
'Analysis.fromJson: analysis_id missing or invalid',
json,
);
}
final statementId = json['statement_id'];
if (statementId is! String || statementId.isEmpty) {
throw FormatException(
'Analysis.fromJson: statement_id missing or invalid',
json,
);
}
final provider = json['model_provider'];
if (provider is! String || provider.isEmpty) {
throw FormatException(
'Analysis.fromJson: model_provider missing or invalid',
json,
);
}
final framing = json['framing'];
if (framing is! String || framing.isEmpty) {
throw FormatException(
'Analysis.fromJson: framing missing or invalid',
json,
);
}
final analyzedAtRaw = json['analyzed_at'];
if (analyzedAtRaw is! String) {
throw FormatException(
'Analysis.fromJson: analyzed_at missing or invalid',
json,
);
}
final analyzedAt = DateTime.tryParse(analyzedAtRaw);
if (analyzedAt == null) {
throw FormatException(
'Analysis.fromJson: analyzed_at unparseable: $analyzedAtRaw',
);
}
return Analysis(
analysisId: id,
statementId: statementId,
modelProvider: provider,
modelVersion: json['model_version'] as String? ?? '',
promptVersion: json['prompt_version'] as String? ?? '',
repetition: _requireDouble(json['repetition'], 'repetition'),
novelty: _requireDouble(json['novelty'], 'novelty'),
affectiveLanguageRate: _requireDouble(
json['affective_language_rate'],
'affective_language_rate',
),
topicEntropy: _requireDouble(json['topic_entropy'], 'topic_entropy'),
framing: framing,
analyzedAt: analyzedAt.toUtc(),
);
}
/// Serializes for local caching / debugging.
Map<String, dynamic> toJson() => {
'analysis_id': analysisId,
'statement_id': statementId,
'model_provider': modelProvider,
'model_version': modelVersion,
'prompt_version': promptVersion,
'repetition': repetition,
'novelty': novelty,
'affective_language_rate': affectiveLanguageRate,
'topic_entropy': topicEntropy,
'framing': framing,
'analyzed_at': analyzedAt.toIso8601String(),
};
/// Requires a finite double from JSON. Throws [FormatException] if
/// null, non-numeric, NaN, or Infinity.
static double _requireDouble(dynamic value, String field) {
if (value == null) {
throw FormatException('Analysis: $field is required');
}
if (value is! num) {
throw FormatException('Analysis: $field must be a number');
}
final d = value.toDouble();
if (!d.isFinite) {
throw FormatException('Analysis: $field must be finite');
}
return d;
}
}
