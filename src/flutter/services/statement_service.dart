/// Statement service for Baseline.
///
/// Stateless service wrapping the get-statement Edge Function (A9C).
/// Returns a single statement with full analysis breakdown and consensus.
///
/// Access: Public (anon key). No authentication required.
/// Guests and authenticated users both access this endpoint.
///
/// Response shape from A9C:
/// { statement: {...}, analyses: [...], consensus: {...} | null }
///
/// Analyses array may be empty (not yet analyzed).
/// Consensus may be null (< 2 analyses or newly ingested).
///
/// Path: lib/services/statement_service.dart
library;
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:baseline_app/models/analysis.dart';
import 'package:baseline_app/models/consensus.dart';
import 'package:baseline_app/models/statement_detail.dart';
import 'package:baseline_app/services/supabase_client.dart';
//
// ════════════════════════════════════════════════════════════
// ═══════════
// EXCEPTION
//
// ════════════════════════════════════════════════════════════
// ═══════════
/// Typed exception for statement operations.
class StatementServiceException implements Exception {
const StatementServiceException(this.message, {this.code});
final String message;
final String? code;
@override
String toString() => 'StatementServiceException($code): $message';
}
//
// ════════════════════════════════════════════════════════════
// ═══════════
// RESPONSE
//
// ════════════════════════════════════════════════════════════
// ═══════════
/// Structured response from get-statement (A9C).
///
/// [statement] is always present (404 is thrown, not returned).
/// [analyses] may be empty (not yet analyzed).
/// [consensus] may be null (< 2 analyses).
/// [skippedItemCount] tracks items that failed to parse (analyses +
/// consensus). If > 0, the UI should show the partial failure banner
/// (F2.17).
/// [consensusParseFailed] distinguishes consensus parse failure from
/// analysis parse failure — different banner messaging.
class StatementDetailResponse {
const StatementDetailResponse({
required this.statement,
required this.analyses,
this.consensus,
this.skippedItemCount = 0,
this.consensusParseFailed = false,
});
final StatementDetail statement;
final List<Analysis> analyses;
final Consensus? consensus;
final int skippedItemCount;
final bool consensusParseFailed;
/// Whether analysis data is available.
bool get hasAnalyses => analyses.isNotEmpty;
/// Whether consensus has been computed.
bool get hasConsensus => consensus != null;
/// Whether some items failed to parse (for partial failure banner).
bool get hasPartialFailure => skippedItemCount > 0 || consensusParseFailed;
/// Whether variance was detected across models.
bool get varianceDetected => consensus?.varianceDetected ?? false;
/// Get analysis for a specific provider, or null.
/// Case-insensitive comparison for resilience.
Analysis? analysisForProvider(String provider) {
final upper = provider.toUpperCase();
for (final a in analyses) {
if (a.modelProvider.toUpperCase() == upper) return a;
}
return null;
}
}
//
// ════════════════════════════════════════════════════════════
// ═══════════
// SERVICE
//
// ════════════════════════════════════════════════════════════
// ═══════════
class StatementService {
const StatementService();
/// Request timeout for the get-statement Edge Function.
static const _requestTimeout = Duration(seconds: 15);
// ── Helpers
// ──────────────────────────────────────────────────────────
/// Maps exceptions to UI-safe [StatementServiceException].
static StatementServiceException _mapException(Object e) {
if (kDebugMode) {
debugPrint('StatementService: ${e.runtimeType}');
}
if (e is TimeoutException) {
return const StatementServiceException(
'Request timed out. Please try again.',
code: 'timeout',
);
}
if (e is FunctionException) {
return const StatementServiceException(
'Unable to load statement. Please try again.',
code: 'edge_function_error',
);
}
if (e is FormatException) {
return const StatementServiceException(
'Statement data could not be read.',
code: 'parse_error',
);
}
return const StatementServiceException(
'Something went wrong. Please try again.',
code: 'unexpected_error',
);
}
// ── Get Statement
// ───────────────────────────────────────────────────
/// Fetches a single statement with full analysis and consensus.
///
/// [statementId] must be a valid UUID.
///
/// Throws [StatementServiceException] on any failure.
/// Returns 404 as a specific exception (not as null) so the provider
/// can distinguish "not found" from other errors.
Future<StatementDetailResponse> getStatement(String statementId) async {
try {
final response = await supabase.functions
.invoke(
'get-statement',
body: {'statement_id': statementId},
)
.timeout(_requestTimeout);
// ── Check HTTP status
// ──────────────────────────────────────────
if (response.status == 404) {
throw const StatementServiceException(
'Statement not found.',
code: 'not_found',
);
}
if (response.status != 200) {
String errorMessage = 'Server error (${response.status}).';
String? errorCode;
final errData = response.data;
if (errData is Map<String, dynamic>) {
errorMessage =
errData['error'] as String? ?? errorMessage;
errorCode = errData['code'] as String?;
}
throw StatementServiceException(errorMessage, code: errorCode);
}
// ── Parse response
// ─────────────────────────────────────────────
final data = response.data;
if (data is! Map<String, dynamic>) {
throw const FormatException(
'get-statement: response is not a JSON object',
);
}
// Parse statement (required — should always be present on 200).
final rawStatement = data['statement'];
if (rawStatement is! Map<String, dynamic>) {
throw const FormatException(
'get-statement: statement is not a JSON object',
);
}
final statement = StatementDetail.fromJson(rawStatement);
// Parse analyses array (may be empty).
final rawAnalyses = data['analyses'];
final analyses = <Analysis>[];
int skippedItemCount = 0;
if (rawAnalyses is List) {
for (final raw in rawAnalyses) {
if (raw is Map<String, dynamic>) {
try {
analyses.add(Analysis.fromJson(raw));
} catch (_) {
skippedItemCount++;
}
} else {
skippedItemCount++;
}
}
}
if (kDebugMode && skippedItemCount > 0) {
debugPrint(
'StatementService: skipped $skippedItemCount malformed analyses',
);
}
// Parse consensus (may be null).
Consensus? consensus;
bool consensusParseFailed = false;
final rawConsensus = data['consensus'];
if (rawConsensus is Map<String, dynamic>) {
try {
consensus = Consensus.fromJson(rawConsensus);
} catch (e) {
if (kDebugMode) {
debugPrint('StatementService: consensus parse failed: $e');
}
// Consensus parse failure is a partial failure, not fatal.
// Statement + analyses are still usable.
consensusParseFailed = true;
}
}
return StatementDetailResponse(
statement: statement,
analyses: analyses,
consensus: consensus,
skippedItemCount: skippedItemCount,
consensusParseFailed: consensusParseFailed,
);
} on StatementServiceException {
rethrow;
} catch (e) {
throw _mapException(e);
}
}
}
