/// P4 — BillSummary model for Baseline.
///
/// Represents a bill summary + provisions as stored in bill_summaries (PD1)
/// and returned by summarize-bill (P2) or PD1 RPCs.
///
/// Provision Drift™ scores are per-provision (computed by P2). Drift labels
/// are computed CLIENT-SIDE from quartile thresholds — never stored in DB.
///
/// This model is READ-ONLY on the client. P2 owns persistence.
///
/// P3 (bill_summary_service) should always call [BillSummary.fromEnvelopeOrRow]
/// which handles both the P2 response envelope and direct RPC row shapes.
///
/// Path: lib/models/bill_summary.dart
//
// ════════════════════════════════════════════════════════════
// ═══════════
// PROVISION CATEGORY ENUM
//
// ════════════════════════════════════════════════════════════
// ═══════════
/// Category classification for bill provisions.
///
/// Values match P1 extraction enum exactly. Decision tree (first match wins):
/// AMENDMENT → EARMARK → RIDER → STANDALONE_PROVISION.
library;
enum ProvisionCategory {
amendment,
earmark,
rider,
standaloneProvision;
/// Parse from P1/P2 JSON string (e.g., "EARMARK", "STANDALONE_PROVISION").
/// Returns [standaloneProvision] as fallback for unknown values.
static ProvisionCategory fromString(String? value) {
switch (value?.toUpperCase()) {
case 'AMENDMENT':
return ProvisionCategory.amendment;
case 'EARMARK':
return ProvisionCategory.earmark;
case 'RIDER':
return ProvisionCategory.rider;
case 'STANDALONE_PROVISION':
return ProvisionCategory.standaloneProvision;
default:
return ProvisionCategory.standaloneProvision;
}
}
/// Serialization value matching P1/P2 JSON enum.
String get jsonValue {
switch (this) {
case ProvisionCategory.amendment:
return 'AMENDMENT';
case ProvisionCategory.earmark:
return 'EARMARK';
case ProvisionCategory.rider:
return 'RIDER';
case ProvisionCategory.standaloneProvision:
return 'STANDALONE_PROVISION';
}
}
/// Human-readable label for UI display.
String get label {
switch (this) {
case ProvisionCategory.amendment:
return 'Amendment';
case ProvisionCategory.earmark:
return 'Earmark';
case ProvisionCategory.rider:
return 'Rider';
case ProvisionCategory.standaloneProvision:
return 'Standalone Provision';
}
}
}
//
// ════════════════════════════════════════════════════════════
// ═══════════
// PROVISION
//
// ════════════════════════════════════════════════════════════
// ═══════════
/// A single provision extracted from a bill by P2.
///
/// JSONB element shape (from PD1 `provisions` array):
/// ```json
/// {
/// "title": "Section 203 — Rural Broadband Expansion",
/// "description": "Allocates $2.1B for broadband infrastructure...",
/// "category": "STANDALONE_PROVISION",
/// "provision_note": "Sunsets after 5 years.",
/// "drift_score": 0.23
/// }
/// ```
///
/// [driftScore] is null when P2 could not compute embeddings
/// (drift_computed = false on parent BillSummary).
///
/// [driftLabel] is computed CLIENT-SIDE from quartile thresholds.
/// NEVER stored in DB. This is a locked decision.
class Provision {
const Provision({
required this.title,
required this.description,
required this.category,
this.provisionNote = '',
this.driftScore,
});
/// Short descriptive name (max 200 chars, enforced by P1/P2).
final String title;
/// What this provision does. Neutral, observational (max 500 chars).
final String description;
/// Structural classification per P1 decision tree.
final ProvisionCategory category;
/// Optional structural context — funding amounts, dates, sunset clauses.
/// Empty string if nothing notable (P2 guarantees non-null).
final String provisionNote;
/// Cosine distance between this provision's embedding and the bill's
/// stated_purpose embedding. 0.0–1.0. Null if drift was not computed.
/// Computed by P2, stored in PD1 provisions JSONB.
final double? driftScore;
// ── Drift Label (client-side, locked thresholds) ──────────────────
/// Human-readable drift label computed from quartile thresholds.
///
/// - 0.00–0.25 → Low
/// - 0.26–0.50 → Moderate
/// - 0.51–0.75 → High
/// - 0.76–1.00 → Very High
/// - null → null (drift not computed)
///
/// LOCKED DECISION: Frontend-only. Never stored in DB.
String? get driftLabel {
final score = driftScore;
if (score == null) return null;
if (score <= 0.25) return 'Low';
if (score <= 0.50) return 'Moderate';
if (score <= 0.75) return 'High';
return 'Very High';
}
// ── Serialization
// ─────────────────────────────────────────────────
/// Parse a single provision from the JSONB element.
///
/// Handles Supabase decoder variance where elements may arrive as
/// `Map<dynamic, dynamic>` — caller coerces via `Map<String, dynamic>.from()`.
factory Provision.fromJson(Map<String, dynamic> json) {
return Provision(
title: json['title'] as String? ?? '',
description: json['description'] as String? ?? '',
category: ProvisionCategory.fromString(json['category'] as String?),
provisionNote: json['provision_note'] as String? ?? '',
driftScore: (json['drift_score'] as num?)?.toDouble(),
);
}
/// Serialize back to JSON (local cache, debugging).
Map<String, dynamic> toJson() => {
'title': title,
'description': description,
'category': category.jsonValue,
'provision_note': provisionNote,
if (driftScore != null) 'drift_score': driftScore,
};
}
//
// ════════════════════════════════════════════════════════════
// ═══════════
// BILL SUMMARY
//
// ════════════════════════════════════════════════════════════
// ═══════════
/// Complete bill summary as stored in `bill_summaries` (PD1).
///
/// Returned by:
/// - P2 Edge Function (`summarize-bill`) inside `{ source, bill_summary: {...} }` envelope
/// - PD1 RPCs (`get_bill_summary`, `get_bill_summaries_batch`) as direct rows
///
/// Use [fromEnvelopeOrRow] in P3 — it handles both shapes automatically.
/// Use [fromJson] only when you already have a pure PD1 row (e.g., from local cache).
///
/// Immutable after creation. Bills are public records — cache forever.
///
/// Provision Drift™:
/// - [driftComputed]: Whether P2 successfully computed embeddings + distances.
/// - [avgDriftScore]: Mean drift across all provisions. Null if not computed.
/// - Per-provision [Provision.driftScore]: Individual cosine distance.
/// - Drift labels: CLIENT-SIDE only (see [Provision.driftLabel]).
class BillSummary {
const BillSummary({
required this.billSummaryId,
required this.billId,
required this.billTitle,
required this.summary,
required this.statedPurpose,
required this.provisions,
required this.driftComputed,
this.avgDriftScore,
required this.provisionCount,
required this.sourceBillUrl,
required this.congressSession,
required this.createdAt,
this.source,
});
/// UUID primary key (PD1).
final String billSummaryId;
/// Bill identifier (e.g., "hr-1234-118"). Matches votes table bill_id.
/// UNIQUE in PD1 — one summary per bill.
final String billId;
/// Bill title as extracted from bill text or provided at ingestion.
final String billTitle;
/// Plain-language summary of the bill (2–4 sentences, max 2000 chars).
/// Neutral, observational language only.
final String summary;
/// The bill's own stated purpose as declared in its text.
/// Used as the Provision Drift™ anchor embedding. Max 500 chars.
final String statedPurpose;
/// Extracted provisions with category + optional drift scores.
/// Stored in DB insertion order; UI may display sorted via [provisionsByDrift].
final List<Provision> provisions;
/// Whether P2 successfully computed Provision Drift™ embeddings.
/// False when OpenAI embedding call fails (non-blocking in P2).
final bool driftComputed;
/// Mean drift score across all provisions. Null if [driftComputed] is false.
/// Useful for sorting/filtering bills by overall drift.
final double? avgDriftScore;
/// Number of provisions. Matches `provisions.length`.
/// Stored separately in PD1 for query performance (no JSONB parse needed).
final int provisionCount;
/// URL to original bill text. Always present (required by P2).
final String sourceBillUrl;
/// Congressional session number extracted from bill_id (e.g., 118).
/// PD1 enforces > 0 via CHECK constraint. Default 0 used as parse fallback
/// only — check [hasValidCongressSession] before display.
final int congressSession;
/// Row creation timestamp (UTC).
/// Falls back to epoch (1970-01-01) if unparseable — detectable sentinel,
/// never looks like a real timestamp.
final DateTime createdAt;
/// Response source: "cache", "fresh", or "cache_race".
/// Only present when returned via P2 Edge Function envelope.
/// Null when returned via PD1 RPCs.
final String? source;
// ── Computed Helpers
// ───────────────────────────────────────────────
/// Average drift label computed client-side from [avgDriftScore].
/// Same quartile thresholds as [Provision.driftLabel].
String? get avgDriftLabel {
final score = avgDriftScore;
if (score == null) return null;
if (score <= 0.25) return 'Low';
if (score <= 0.50) return 'Moderate';
if (score <= 0.75) return 'High';
return 'Very High';
}
/// Whether [congressSession] is valid per PD1 invariant (> 0).
/// False indicates a parse fallback — do not display session number.
bool get hasValidCongressSession => congressSession > 0;
/// Provisions sorted by drift score descending (highest drift first).
/// Non-scored provisions sort to the end.
/// Used by F4.12 for Provision Drift™ display order.
List<Provision> get provisionsByDrift {
if (!driftComputed) return provisions;
return List<Provision>.from(provisions)
..sort((a, b) {
final aScore = a.driftScore ?? -1;
final bScore = b.driftScore ?? -1;
return bScore.compareTo(aScore);
});
}
/// Whether this summary has any provisions with drift scores.
bool get hasDriftData => driftComputed && provisions.any((p) => p.driftScore != null);
// ── Serialization
// ─────────────────────────────────────────────────
/// Parse from P2 response envelope OR direct PD1 RPC row.
///
/// P2 envelope shape: `{ "source": "fresh", "bill_summary": { ...row }, "duration_ms": 123 }`
/// RPC shape: `{ "bill_summary_id": "...", "bill_id": "...", ... }` (direct row)
///
/// P3 (bill_summary_service) should always call this factory.
/// It detects the envelope by checking for a `bill_summary` key containing a Map,
/// unwraps it, and attaches `source` to the row for unified parsing.
factory BillSummary.fromEnvelopeOrRow(Map<String, dynamic> json) {
final inner = json['bill_summary'];
if (inner is Map) {
final row = Map<String, dynamic>.from(inner);
// Attach source from envelope so fromJson can parse it.
if (json['source'] != null) {
row['source'] = json['source'];
}
return BillSummary.fromJson(row);
}
// Direct RPC row — parse as-is.
return BillSummary.fromJson(json);
}
/// Parse from a pure PD1 row shape (no envelope).
///
/// Handles:
/// - JSONB provisions: parsed defensively (empty list on null/invalid).
/// - Supabase decoder variance: `Map<dynamic, dynamic>` coerced safely.
/// - Timestamps: always UTC, epoch sentinel on parse failure.
factory BillSummary.fromJson(Map<String, dynamic> json) {
// Parse provisions from JSONB array defensively.
// Supabase JSON decoder may return Map<dynamic, dynamic> elements —
// use whereType<Map> (not Map<String, dynamic>) then coerce each.
final rawProvisions = json['provisions'];
final List<Provision> provisions = (rawProvisions is List)
? rawProvisions
.whereType<Map>()
.map((m) => Provision.fromJson(Map<String, dynamic>.from(m)))
.toList(growable: false)
: const [];
// Timestamp: epoch sentinel if unparseable (detectable, never looks real).
final parsedCreatedAt = DateTime.tryParse(
json['created_at'] as String? ?? '',
);
return BillSummary(
billSummaryId: json['bill_summary_id'] as String? ?? '',
billId: json['bill_id'] as String? ?? '',
billTitle: json['bill_title'] as String? ?? '',
summary: json['summary'] as String? ?? '',
statedPurpose: json['stated_purpose'] as String? ?? '',
provisions: provisions,
driftComputed: json['drift_computed'] as bool? ?? false,
avgDriftScore: (json['avg_drift_score'] as num?)?.toDouble(),
provisionCount: (json['provision_count'] as num?)?.toInt() ?? 0,
sourceBillUrl: json['source_bill_url'] as String? ?? '',
congressSession: (json['congress_session'] as num?)?.toInt() ?? 0,
createdAt: (parsedCreatedAt ?? DateTime.utc(1970)).toUtc(),
source: json['source'] as String?,
);
}
/// Serialize to JSON (local cache, debugging, provider state).
Map<String, dynamic> toJson() => {
'bill_summary_id': billSummaryId,
'bill_id': billId,
'bill_title': billTitle,
'summary': summary,
'stated_purpose': statedPurpose,
'provisions': provisions.map((p) => p.toJson()).toList(),
'drift_computed': driftComputed,
'avg_drift_score': avgDriftScore,
'provision_count': provisionCount,
'source_bill_url': sourceBillUrl,
'congress_session': congressSession,
'created_at': createdAt.toUtc().toIso8601String(),
if (source != null) 'source': source,
};
}
