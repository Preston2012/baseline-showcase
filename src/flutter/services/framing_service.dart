/// Framing service for Baseline (Framing Radar™).
///
/// Stateless service calling the get-trends Edge Function (via A14C)
/// for framing distribution data. Returns 5-axis pentagon data for
/// the Framing Radar™ visualization.
///
/// ENTITLEMENT-GATED:
/// The Framing Radar is a PRO feature. Before calling getFramingRadar(),
/// the provider MUST call check-entitlement (F3.12) to obtain an
/// entitlement token. This service accepts the token and passes it
/// via X-Entitlement-Token header.
///
/// 5-AXIS PENTAGON (LOCKED):
/// Axes: Adversarial, Problem, Commitment, Justification, Imperative.
/// Mockup shows 6 axes — KNOWN MOCKUP ERROR. Do NOT add a 6th axis.
///
/// Path: lib/services/framing_service.dart
library;
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:baseline_app/models/framing.dart';
import 'package:baseline_app/services/supabase_client.dart';
//
// ════════════════════════════════════════════════════════════
// ═══════════
// EXCEPTION
//
// ════════════════════════════════════════════════════════════
// ═══════════
/// Typed exception for framing operations.
///
/// Special codes:
/// 'not_found' — figure doesn't exist or has no analyzed statements
/// 'auth_required' — JWT invalid or expired (401) — prompt re-login
/// 'feature_gated' — tier insufficient for Framing Radar (403) — show paywall
/// 'rate_limited' — rate limit exceeded (429)
/// 'bad_request' — invalid input (400)
/// 'insufficient_data' — too few statements for meaningful distribution
/// 'timeout' — request timed out
class FramingServiceException implements Exception {
const FramingServiceException(this.message, {this.code});
final String message;
final String? code;
@override
String toString() => 'FramingServiceException($code): $message';
}
//
// ════════════════════════════════════════════════════════════
// ═══════════
// SERVICE
//
// ════════════════════════════════════════════════════════════
// ═══════════
class FramingService {
const FramingService();
/// Request timeout for the get-trends Edge Function.
static const _requestTimeout = Duration(seconds: 15);
/// Valid period values. Validated at runtime before sending to backend.
static const _validPeriods = {'30d', '90d', '1y'};
// ── Helpers
// ──────────────────────────────────────────────────────────
/// Maps exceptions to UI-safe [FramingServiceException].
static FramingServiceException _mapException(Object e) {
if (kDebugMode) {
debugPrint('FramingService: ${e.runtimeType}');
}
if (e is TimeoutException) {
return const FramingServiceException(
'Request timed out. Please try again.',
code: 'timeout',
);
}
if (e is FunctionException) {
return const FramingServiceException(
'Unable to load framing data. Please try again.',
code: 'edge_function_error',
);
}
if (e is FormatException) {
return const FramingServiceException(
'Framing data could not be read.',
code: 'parse_error',
);
}
return const FramingServiceException(
'Something went wrong. Please try again.',
code: 'unexpected_error',
);
}
/// Extracts error code and message from a response body, if present.
static ({String? message, String? code}) _extractError(dynamic data) {
if (data is Map<String, dynamic>) {
final message = data['error'] as String?;
final code = data['error_code'] as String? ??
data['code'] as String?;
return (message: message, code: code);
}
return (message: null, code: null);
}
// ── Get Framing Radar
// ───────────────────────────────────────────────
/// Fetches the framing distribution for a figure's statements.
///
/// Returns a 5-axis distribution (current period + optional previous
/// period comparison) for the Framing Radar™ pentagon visualization.
///
/// [figureId] — UUID of the figure.
/// [entitlementToken] — signed token from check-entitlement (F3.12).
/// [period] — time window: '30d', '90d', or '1y'.
///
/// The backend will:
/// 1. Verify the entitlement token
/// 2. Call get_framing_distribution RPC (A14A) for current period
/// 3. Call the same RPC for the equivalent previous period
/// 4. Return percentage distribution for each period
///
/// Throws [FramingServiceException] on any failure.
Future<FramingDistribution> getFramingRadar({
required String figureId,
required String entitlementToken,
String period = '90d',
}) async {
// ── Runtime period validation (asserts are no-ops in release) ─────
if (!_validPeriods.contains(period)) {
throw FramingServiceException(
'Invalid period "$period". Must be one of: $_validPeriods',
code: 'bad_request',
);
}
try {
final response = await supabase.functions
.invoke(
'get-trends',
body: {
'figure_id': figureId,
'period': period,
'type': 'framing_radar',
},
headers: {
'X-Entitlement-Token': entitlementToken,
},
)
.timeout(_requestTimeout);
// ── Check HTTP status
// ──────────────────────────────────────────
if (response.status == 400) {
final err = _extractError(response.data);
throw FramingServiceException(
err.message ?? 'Invalid request.',
code: err.code ?? 'bad_request',
);
}
if (response.status == 401) {
final err = _extractError(response.data);
throw FramingServiceException(
err.message ?? 'Authentication required.',
code: err.code ?? 'auth_required',
);
}
if (response.status == 403) {
final err = _extractError(response.data);
throw FramingServiceException(
err.message ?? 'Feature not available for your current plan.',
code: err.code ?? 'feature_gated',
);
}
if (response.status == 429) {
throw const FramingServiceException(
'Rate limit exceeded. Please try again later.',
code: 'rate_limited',
);
}
if (response.status == 404) {
throw const FramingServiceException(
'Figure not found.',
code: 'not_found',
);
}
if (response.status != 200) {
final err = _extractError(response.data);
throw FramingServiceException(
err.message ?? 'Server error (${response.status}).',
code: err.code,
);
}
// ── Parse response
// ─────────────────────────────────────────────
final data = response.data;
if (data is! Map<String, dynamic>) {
throw const FormatException(
'get-trends (framing): response is not a JSON object',
);
}
final distribution = FramingDistribution.fromJson(data);
// Warn if current period has all-zero values (no analyzed data)
if (kDebugMode && distribution.dominantCategory == null) {
debugPrint(
'FramingService: current period has no non-zero framing data',
);
}
return distribution;
} on FramingServiceException {
rethrow;
} catch (e) {
throw _mapException(e);
}
}
}
