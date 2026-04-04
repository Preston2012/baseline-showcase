/// Vote service for Baseline (Congressional Vote Tracker).
///
/// Calls the get-votes Edge Function (A16C V1.0.1) for congressional
/// vote data. Three query routes, all via GET:
///
/// 1. getVotesForFigure — paginated vote list for a figure
/// 2. getVoteSummary — aggregated counts (YEA/NAY/etc.)
/// 3. getVotesForBill — cross-figure lookup by bill_id
///
/// CRITICAL: get-votes is a GET endpoint.
/// Uses invoke('get-votes', method: HttpMethod.get, queryParameters: {...}).
/// Do NOT pass params in body or headers.
///
/// Auth: Anon (no JWT required). Feature-flag gated (503 if disabled).
///
/// Path: lib/services/vote_service.dart
library;
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:baseline_app/models/vote.dart';
import 'package:baseline_app/services/supabase_client.dart';
//
// ════════════════════════════════════════════════════════════
// ═══════════
// EXCEPTION
//
// ════════════════════════════════════════════════════════════
// ═══════════
/// Typed exception for vote operations.
///
/// Special codes:
/// 'feature_disabled' — vote tracking feature flag is off (503)
/// 'not_found' — figure or bill not found (404)
/// 'bad_request' — invalid query params (400)
/// 'auth_required' — JWT invalid or expired (401)
/// 'access_denied' — insufficient permissions (403)
/// 'rate_limited' — rate limit exceeded (429)
/// 'timeout' — request timed out
class VoteServiceException implements Exception {
const VoteServiceException(this.message, {this.code});
final String message;
final String? code;
@override
String toString() => 'VoteServiceException($code): $message';
}
//
// ════════════════════════════════════════════════════════════
// ═══════════
// SERVICE
//
// ════════════════════════════════════════════════════════════
// ═══════════
class VoteService {
const VoteService();
/// Request timeout.
static const _requestTimeout = Duration(seconds: 15);
// ── Helpers
// ──────────────────────────────────────────────────────────
/// Maps exceptions to UI-safe [VoteServiceException].
static VoteServiceException _mapException(Object e) {
if (kDebugMode) {
debugPrint('VoteService: ${e.runtimeType}');
}
if (e is TimeoutException) {
return const VoteServiceException(
'Request timed out. Please try again.',
code: 'timeout',
);
}
if (e is FunctionException) {
return const VoteServiceException(
'Unable to load vote data. Please try again.',
code: 'edge_function_error',
);
}
if (e is FormatException) {
return const VoteServiceException(
'Vote data could not be read.',
code: 'parse_error',
);
}
return const VoteServiceException(
'Something went wrong. Please try again.',
code: 'unexpected_error',
);
}
/// Extracts error code and message from a response body, if present.
static ({String? message, String? code}) _extractError(dynamic data) {
if (data is Map<String, dynamic>) {
final message = data['error'] as String?;
final code =
data['error_code'] as String? ?? data['code'] as String?;
return (message: message, code: code);
}
return (message: null, code: null);
}
/// Handles HTTP status codes from get-votes response.
///
/// Throws [VoteServiceException] for non-200 responses.
static void _checkStatus(int status, dynamic data) {
if (status == 200) return;
final err = _extractError(data);
if (status == 400) {
throw VoteServiceException(
err.message ?? 'Invalid request.',
code: err.code ?? 'bad_request',
);
}
if (status == 401) {
throw VoteServiceException(
err.message ?? 'Authentication required.',
code: err.code ?? 'auth_required',
);
}
if (status == 403) {
throw VoteServiceException(
err.message ?? 'Access denied.',
code: err.code ?? 'access_denied',
);
}
if (status == 404) {
throw VoteServiceException(
err.message ?? 'Not found.',
code: err.code ?? 'not_found',
);
}
if (status == 429) {
throw const VoteServiceException(
'Rate limit exceeded. Please try again later.',
code: 'rate_limited',
);
}
// 503 — feature flag disabled
if (status == 503) {
throw VoteServiceException(
err.message ?? 'Vote tracking is temporarily unavailable.',
code: err.code ?? 'feature_disabled',
);
}
throw VoteServiceException(
err.message ?? 'Server error ($status).',
code: err.code,
);
}
// ── Route 1: Paginated votes for a figure ───────────────────────────
/// Fetches paginated votes for a specific figure.
///
/// [figureId] — UUID of the figure.
/// [chamber] — optional chamber filter (Chamber.house or Chamber.senate).
/// [congressSession] — optional congress session number filter.
/// [fromDate] — optional start date filter (YYYY-MM-DD).
/// [toDate] — optional end date filter (YYYY-MM-DD).
/// [limit] — page size (default 50, max 500 per A16C).
/// [offset] — pagination offset (default 0).
///
/// Returns a [VotePage] with vote records and pagination metadata.
///
/// Throws [VoteServiceException] on any failure.
Future<VotePage> getVotesForFigure({
required String figureId,
Chamber? chamber,
int? congressSession,
String? fromDate,
String? toDate,
int limit = 50,
int offset = 0,
}) async {
try {
// Clamp to A16C bounds (MAX_LIMIT=500, MAX_OFFSET=10000)
final safeLimit = limit.clamp(1, 500);
final safeOffset = offset.clamp(0, 10000);
final qp = <String, dynamic>{
'figure_id': figureId,
'limit': safeLimit,
'offset': safeOffset,
};
if (chamber != null) qp['chamber'] = chamber.value;
if (congressSession != null) {
qp['congress_session'] = congressSession;
}
if (fromDate != null && fromDate.isNotEmpty) {
qp['from_date'] = fromDate;
}
if (toDate != null && toDate.isNotEmpty) {
qp['to_date'] = toDate;
}
final response = await supabase.functions
.invoke(
'get-votes',
method: HttpMethod.get,
queryParameters: qp,
)
.timeout(_requestTimeout);
_checkStatus(response.status, response.data);
final data = response.data;
if (data is! Map<String, dynamic>) {
throw const FormatException(
'get-votes: response is not a JSON object',
);
}
// A16C returns 'votes' array for figure route
final votesRaw = data['votes'] ?? data['data'];
if (votesRaw is! List) {
throw const FormatException(
'get-votes: votes array missing from response',
);
}
final votes = <Vote>[];
for (final item in votesRaw) {
if (item is Map<String, dynamic>) {
try {
votes.add(Vote.fromJson(item));
} on FormatException catch (e) {
if (kDebugMode) debugPrint('VoteService: skipping vote: $e');
}
}
}
// Parse pagination from response
final pagination = data['pagination'];
final responseLimit = (pagination is Map
? (pagination['limit'] as num?)?.toInt()
: null) ??
safeLimit;
final responseOffset = (pagination is Map
? (pagination['offset'] as num?)?.toInt()
: null) ??
safeOffset;
// Safe filters extraction
final filtersRaw = data['filters'];
final filters = filtersRaw is Map
? Map<String, dynamic>.from(filtersRaw)
: null;
return VotePage(
votes: votes,
count: (data['count'] as num?)?.toInt() ?? votes.length,
limit: responseLimit,
offset: responseOffset,
figureId: figureId,
filters: filters,
);
} on VoteServiceException {
rethrow;
} catch (e) {
throw _mapException(e);
}
}
// ── Route 2: Vote summary for a figure ──────────────────────────────
/// Fetches aggregated vote counts for a figure.
///
/// Returns summary rows: each with a vote type and count.
/// Used for the header bar: "Total: 47 YEA: 32 NAY: 12"
///
/// [figureId] — UUID of the figure.
/// [chamber] — optional chamber filter.
/// [congressSession] — optional congress session filter.
///
/// Returns a list of [VoteSummary] objects.
///
/// Throws [VoteServiceException] on any failure.
Future<List<VoteSummary>> getVoteSummary({
required String figureId,
Chamber? chamber,
int? congressSession,
}) async {
try {
final qp = <String, dynamic>{
'figure_id': figureId,
'summary': true,
};
if (chamber != null) qp['chamber'] = chamber.value;
if (congressSession != null) {
qp['congress_session'] = congressSession;
}
final response = await supabase.functions
.invoke(
'get-votes',
method: HttpMethod.get,
queryParameters: qp,
)
.timeout(_requestTimeout);
_checkStatus(response.status, response.data);
final data = response.data;
if (data is! Map<String, dynamic>) {
throw const FormatException(
'get-votes summary: response is not a JSON object',
);
}
// A16C returns 'summary' array for summary route
final summaryRaw = data['summary'] ?? data['data'];
if (summaryRaw is! List) {
throw const FormatException(
'get-votes summary: summary array missing from response',
);
}
return summaryRaw
.whereType<Map<String, dynamic>>()
.map(VoteSummary.fromJson)
.toList();
} on VoteServiceException {
rethrow;
} catch (e) {
throw _mapException(e);
}
}
// ── Route 3: Votes for a bill (cross-figure) ───────────────────────
/// Fetches all votes for a specific bill across figures.
///
/// Used when navigating to a bill from a vote card to see how
/// all tracked figures voted on the same legislation.
///
/// [billId] — bill identifier (e.g., "H.R. 1234").
///
/// Returns a list of [Vote] objects (all figures who voted).
/// With 44 tracked figures max, result set is inherently bounded.
///
/// Throws [VoteServiceException] on any failure.
Future<List<Vote>> getVotesForBill({
required String billId,
}) async {
try {
final qp = <String, dynamic>{
'bill_id': billId,
};
final response = await supabase.functions
.invoke(
'get-votes',
method: HttpMethod.get,
queryParameters: qp,
)
.timeout(_requestTimeout);
_checkStatus(response.status, response.data);
final data = response.data;
if (data is! Map<String, dynamic>) {
throw const FormatException(
'get-votes bill: response is not a JSON object',
);
}
// A16C bill route returns 'votes' array
final votesRaw = data['votes'] ?? data['data'];
if (votesRaw is! List) {
throw const FormatException(
'get-votes bill: votes array missing from response',
);
}
final votes = <Vote>[];
for (final item in votesRaw) {
if (item is Map<String, dynamic>) {
try {
votes.add(Vote.fromJson(item));
} on FormatException catch (e) {
if (kDebugMode) debugPrint('VoteService: skipping vote: $e');
}
}
}
return votes;
} on VoteServiceException {
rethrow;
} catch (e) {
throw _mapException(e);
}
}
}
