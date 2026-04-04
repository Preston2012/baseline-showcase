/// Vote models for Baseline (Congressional Vote Tracker).
///
/// Contains:
/// - VoteCast enum - type-safe vote values (YEA/NAY/NOT_VOTING/PRESENT)
/// - Chamber enum - HOUSE/SENATE
/// - Vote - individual vote record
/// - VoteSummary - aggregated count per vote type
/// - VotePage - paginated response wrapper
///
/// Backend source: get-votes EF (A16C) → A16A RPCs → votes table (A1).
///
/// Brand neutrality: Vote badges use teal (recorded) / gray (not recorded).
/// NEVER red/green for YEA/NAY. "NOT_VOTING" is neutral, not negative.
///
/// Path: lib/models/vote.dart
//
// ════════════════════════════════════════════════════════════
// ═══════════
// VOTE CAST ENUM
//
// ════════════════════════════════════════════════════════════
// ═══════════
/// Type-safe vote values from A1 schema CHECK constraint.
///
/// DB stores: 'YEA', 'NAY', 'NOT_VOTING', 'PRESENT'
/// UI displays: 'YEA', 'NAY', 'NOT VOTING', 'PRESENT'
/// Badge colors: teal (YEA/NAY/PRESENT = recorded), gray (NOT_VOTING).
library;
enum VoteCast {
yea,
nay,
notVoting,
present;
/// Display label for vote badges (human-readable).
String get label {
switch (this) {
case VoteCast.yea:
return 'YEA';
case VoteCast.nay:
return 'NAY';
case VoteCast.notVoting:
return 'NOT VOTING';
case VoteCast.present:
return 'PRESENT';
}
}
/// Exact backend/DB value for serialization (round-trip safe).
String get backendValue {
switch (this) {
case VoteCast.yea:
return 'YEA';
case VoteCast.nay:
return 'NAY';
case VoteCast.notVoting:
return 'NOT_VOTING';
case VoteCast.present:
return 'PRESENT';
}
}
/// Whether this vote represents an active recorded position.
/// Used for badge color: true → teal, false → gray.
bool get isRecorded => this != VoteCast.notVoting;
/// Parses backend vote string to enum.
/// Handles both underscore and space variants.
/// Returns null for unknown values.
static VoteCast? fromString(String? value) {
if (value == null) return null;
switch (value.toUpperCase().trim()) {
case 'YEA':
return VoteCast.yea;
case 'NAY':
return VoteCast.nay;
case 'NOT_VOTING':
case 'NOT VOTING':
return VoteCast.notVoting;
case 'PRESENT':
return VoteCast.present;
default:
return null;
}
}
}
//
// ════════════════════════════════════════════════════════════
// ═══════════
// CHAMBER ENUM
//
// ════════════════════════════════════════════════════════════
// ═══════════
/// Congressional chamber.
enum Chamber {
house,
senate;
/// Display label.
String get label {
switch (this) {
case Chamber.house:
return 'House';
case Chamber.senate:
return 'Senate';
}
}
/// Backend string value (UPPERCASE).
String get value {
switch (this) {
case Chamber.house:
return 'HOUSE';
case Chamber.senate:
return 'SENATE';
}
}
/// Parses backend chamber string to enum.
/// Handles variants: 'HOUSE', 'HOUSE OF REPRESENTATIVES', 'SENATE'.
/// Returns null for unknown values.
static Chamber? fromString(String? value) {
if (value == null) return null;
switch (value.toUpperCase().trim()) {
case 'HOUSE':
case 'HOUSE OF REPRESENTATIVES':
return Chamber.house;
case 'SENATE':
return Chamber.senate;
default:
return null;
}
}
}
//
// ════════════════════════════════════════════════════════════
// ═══════════
// VOTE MODEL
//
// ════════════════════════════════════════════════════════════
// ═══════════
/// Individual congressional vote record.
///
/// Represents a single figure's vote on a specific bill.
/// Parsed from get-votes EF response (A16C → A16A RPCs).
///
/// vote_date is a date-only field stored as UTC midnight.
/// No time component - do not display time.
/// Source URL links to the official congressional record.
class Vote {
const Vote({
required this.voteId,
required this.figureId,
required this.figureName,
required this.billId,
required this.billTitle,
required this.voteCast,
required this.voteDate,
this.chamber,
this.congressSession,
this.rollCallNumber,
this.sourceUrl,
});
final String voteId;
final String figureId;
final String figureName;
/// Bill identifier (e.g., "H.R. 1234", "S. 567").
final String billId;
/// Bill title / description. May be long - UI should truncate.
/// Empty string if not provided by backend.
final String billTitle;
/// How this figure voted.
final VoteCast voteCast;
/// Date of the vote (UTC midnight, date-only - no time component).
final DateTime voteDate;
/// Congressional chamber. Null if not provided.
final Chamber? chamber;
/// Congress session number (e.g., 118, 119). Null if not provided.
final int? congressSession;
/// Roll call number for this vote. Null if not provided.
final int? rollCallNumber;
/// URL to official congressional record. Null if not available.
final String? sourceUrl;
/// Parses a vote JSON object from get-votes response.
///
/// Supports dual-key for vote field: 'vote' (A16A RPC) or
/// 'vote_cast' (schema column name) - whichever is present.
///
/// Throws [FormatException] if required fields are missing.
factory Vote.fromJson(Map<String, dynamic> json) {
final voteId = json['vote_id'];
if (voteId is! String || voteId.isEmpty) {
throw FormatException('Vote.fromJson: vote_id missing or invalid', json);
}
final figureId = json['figure_id'];
if (figureId is! String || figureId.isEmpty) {
throw FormatException(
'Vote.fromJson: figure_id missing or invalid',
json,
);
}
final figureName = json['figure_name'];
if (figureName is! String || figureName.isEmpty) {
throw FormatException(
'Vote.fromJson: figure_name missing or invalid',
json,
);
}
final billId = json['bill_id'];
if (billId is! String || billId.isEmpty) {
throw FormatException(
'Vote.fromJson: bill_id missing or invalid',
json,
);
}
final billTitle = json['bill_title'] as String? ?? '';
// Dual-key: A16A RPC returns 'vote', schema column is 'vote_cast'
final voteRaw = (json['vote'] ?? json['vote_cast']) as String?;
final voteCast = VoteCast.fromString(voteRaw);
if (voteCast == null) {
throw FormatException(
'Vote.fromJson: vote missing or invalid: "$voteRaw"',
json,
);
}
// Date-only parsing → stable UTC midnight
final voteDateRaw = json['vote_date'];
if (voteDateRaw is! String || voteDateRaw.isEmpty) {
throw FormatException(
'Vote.fromJson: vote_date missing or invalid',
json,
);
}
final parts = voteDateRaw.split('-');
if (parts.length < 3) {
throw FormatException(
'Vote.fromJson: vote_date invalid format: "$voteDateRaw"',
json,
);
}
final y = int.tryParse(parts[0]);
final m = int.tryParse(parts[1]);
final d = int.tryParse(parts[2].length > 2
? parts[2].substring(0, 2)
: parts[2]);
if (y == null || m == null || d == null) {
throw FormatException(
'Vote.fromJson: vote_date unparseable: "$voteDateRaw"',
json,
);
}
final voteDate = DateTime.utc(y, m, d);
return Vote(
voteId: voteId,
figureId: figureId,
figureName: figureName,
billId: billId,
billTitle: billTitle,
voteCast: voteCast,
voteDate: voteDate,
chamber: Chamber.fromString(json['chamber'] as String?),
congressSession: (json['congress_session'] as num?)?.toInt(),
rollCallNumber: (json['roll_call_number'] as num?)?.toInt(),
sourceUrl: json['source_url'] as String?,
);
}
/// Alias: raw vote string for backward-compat code paths.
String get vote => voteCast.backendValue;

/// Whether this vote is a silent (non-substantive) vote.
bool get isSilentVote =>
    voteCast == VoteCast.notVoting || voteCast == VoteCast.present;

/// Display-friendly vote position string.
String get votePosition => voteCast.label;

/// Vote result string (backend value).
String get result => voteCast.backendValue;

/// Serializes for local caching / debugging.
/// Uses backendValue for round-trip safe vote serialization.
Map<String, dynamic> toJson() => {
'vote_id': voteId,
'figure_id': figureId,
'figure_name': figureName,
'bill_id': billId,
'bill_title': billTitle,
'vote': voteCast.backendValue,
'vote_date': '${voteDate.year.toString().padLeft(4, '0')}-'
'${voteDate.month.toString().padLeft(2, '0')}-'
'${voteDate.day.toString().padLeft(2, '0')}',
'chamber': chamber?.value,
'congress_session': congressSession,
'roll_call_number': rollCallNumber,
'source_url': sourceUrl,
};
}
//
// ════════════════════════════════════════════════════════════
// ═══════════
// VOTE SUMMARY
//
// ════════════════════════════════════════════════════════════
// ═══════════
/// Aggregated vote count for a figure - one entry per vote type.
///
/// From get_vote_summary_for_figure RPC (A16A).
/// Used in the Vote Record screen header bar: "Total: 47 YEA: 32 NAY: 12"
///
/// vote is kept as raw String (not VoteCast enum) because the summary
/// RPC may return aggregation rows we don't recognize (e.g., future
/// vote types). The screen handles display mapping.
class VoteSummary {
const VoteSummary({
required this.vote,
required this.count,
this.chamber,
});
/// Vote type string from backend (e.g., 'YEA', 'NAY', 'NOT_VOTING').
final String vote;
/// How many times this vote was cast.
final int count;
/// Chamber filter applied (if any).
final Chamber? chamber;

/// Alias: some code accesses this as voteCast instead of vote.
String get voteCast => vote;

/// Parses a summary row from the get-votes summary response.
factory VoteSummary.fromJson(Map<String, dynamic> json) {
return VoteSummary(
vote: json['vote'] as String? ?? '',
count: (json['count'] as num?)?.toInt() ?? 0,
chamber: Chamber.fromString(json['chamber'] as String?),
);
}
}
//
// ════════════════════════════════════════════════════════════
// ═══════════
// VOTE PAGE (paginated response wrapper)
//
// ════════════════════════════════════════════════════════════
// ═══════════
/// Paginated vote response from get-votes EF.
///
/// Wraps the vote list with pagination metadata and applied filters.
class VotePage {
const VotePage({
required this.votes,
required this.count,
required this.limit,
required this.offset,
this.figureId,
this.filters,
});
/// Vote records for this page.
final List<Vote> votes;
/// Total count of votes returned in this page.
final int count;
/// Page size.
final int limit;
/// Current offset.
final int offset;
/// Figure ID these votes belong to (null for bill-based queries).
final String? figureId;
/// Applied filters (chamber, congress_session, date range).
final Map<String, dynamic>? filters;
/// Whether there are more pages after this one.
/// Heuristic: if we got a full page, there might be more.
/// Worst case is one extra empty fetch (acceptable for infinite scroll).
bool get hasMore => votes.length >= limit;
}
