import 'package:flutter_riverpod/flutter_riverpod.dart';
/// Figures service for Baseline.
///
/// Stateless service reading directly from PostgREST - NOT via Edge
/// Functions. This is the ONLY PostgREST exception in the entire app.
/// `figures` and `v_statements_public` are public-read, RLS-gated,
/// zero-compute. This design is locked.
///
/// Provides:
/// - getActiveFigures(): All active figures for the Figures Tab
/// - getFigure(figureId): Single figure for Figure Profile header
/// - getStatementCount(figureId): Count for Figure Profile badge
/// - searchFigures(query): Name search for Search Tab (F3.14)
///
/// v_statements_public (A9A) pre-filters: is_revoked = false AND
/// is_active = true. The service does not add redundant filters.
///
/// Categories are used for grouping in the Figures Tab (F4.15).
/// The UI groups by category and sorts by activation_order within
/// each group. Sorting is done client-side to guarantee null
/// activation_order sorts last (PostgREST null ordering is
/// config-dependent).
///
/// Path: lib/services/figures_service.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:baseline_app/models/figure.dart';
import 'package:baseline_app/services/supabase_client.dart';
//
// ════════════════════════════════════════════════════════════
// ═══════════
// EXCEPTION
//
// ════════════════════════════════════════════════════════════
// ═══════════
/// Typed exception for figure operations.
class FiguresServiceException implements Exception {
const FiguresServiceException(this.message, {this.code});
final String message;
final String? code;
@override
String toString() => 'FiguresServiceException($code): $message';
}
//
// ════════════════════════════════════════════════════════════
// ═══════════
// RESPONSE
//
// ════════════════════════════════════════════════════════════
// ═══════════
/// Response from getActiveFigures().
///
/// [figures] is the parsed list (may be empty).
/// [skippedCount] tracks items that failed to parse. If > 0, the UI
/// can show the partial failure banner (F2.17).
class FiguresListResponse {
const FiguresListResponse({
required this.figures,
this.skippedCount = 0,
});
final List<Figure> figures;
final int skippedCount;
/// Whether some items failed to parse (for partial failure banner).
bool get hasPartialFailure => skippedCount > 0;
}
//
// ════════════════════════════════════════════════════════════
// ═══════════
// CONSTANTS
//
// ════════════════════════════════════════════════════════════
// ═══════════
/// Explicit column list for figures table reads.
/// Excludes: allowlist_id (internal pipeline key, not needed client-side).
const _kFigureColumns = 'figure_id, name, category, is_active, '
'activation_order, metadata, photo_url, created_at';
//
// ════════════════════════════════════════════════════════════
// ═══════════
// SERVICE
//
// ════════════════════════════════════════════════════════════
// ═══════════
class FiguresService {
const FiguresService();
/// Request timeout for PostgREST queries.
/// 10s (shorter than 15s Edge Function timeout - PostgREST is faster).
static const _requestTimeout = Duration(seconds: 10);
// ── Helpers
// ──────────────────────────────────────────────────────────
/// Maps exceptions to UI-safe [FiguresServiceException].
static FiguresServiceException _mapException(Object e) {
if (kDebugMode) {
debugPrint('FiguresService: ${e.runtimeType}');
}
if (e is TimeoutException) {
return const FiguresServiceException(
'Request timed out. Please try again.',
code: 'timeout',
);
}
if (e is PostgrestException) {
return FiguresServiceException(
'Unable to load figures. Please try again.',
code: e.code,
);
}
if (e is FormatException) {
return const FiguresServiceException(
'Figure data could not be read.',
code: 'parse_error',
);
}
return const FiguresServiceException(
'Something went wrong. Please try again.',
code: 'unexpected_error',
);
}
/// Escapes SQL LIKE wildcards in a search query string.
/// PostgREST's `ilike` uses SQL LIKE syntax where `%` and `_`
/// are wildcards. User-typed `%` or `_` must be escaped to match
/// literally.
static String _escapeLikeQuery(String input) {
return input.replaceAll('%', r'\%').replaceAll('_', r'\_');
}
// ── Get Active Figures
// ──────────────────────────────────────────────
/// Fetches all active figures for the Figures Tab (F4.15).
///
/// Returns only active figures (is_active = true), sorted by
/// category then activation_order. Sorting is done client-side
/// to guarantee null activation_order sorts last regardless of
/// PostgREST/Postgres null ordering config.
///
/// Throws [FiguresServiceException] on failure.
Future<FiguresListResponse> getActiveFigures() async {
try {
final response = await supabase
.from('figures')
.select(_kFigureColumns)
.eq('is_active', true)
.timeout(_requestTimeout);
final figures = <Figure>[];
int skippedCount = 0;
for (final raw in response) {
try {
figures.add(Figure.fromJson(raw));
} catch (_) {
skippedCount++;
}
}
if (kDebugMode && skippedCount > 0) {
debugPrint(
'FiguresService: skipped $skippedCount malformed figures',
);
}
// Client-side sort: category alphabetical, then name ascending
// within each group. This gives a consistent A-Z listing per category.
figures.sort((a, b) {
final catCmp = a.category.compareTo(b.category);
if (catCmp != 0) return catCmp;
return a.name.compareTo(b.name);
});
return FiguresListResponse(
figures: figures,
skippedCount: skippedCount,
);
} on FiguresServiceException {
rethrow;
} catch (e) {
throw _mapException(e);
}
}
// ── Get Single Figure
// ───────────────────────────────────────────────
/// Fetches a single figure by ID.
///
/// Used by the Figure Profile screen (F4.8) header.
/// Returns active and inactive figures (inactive may still be viewable
/// if a user navigated to the profile before deactivation).
///
/// Throws [FiguresServiceException] with code 'not_found' if the
/// figure doesn't exist.
Future<Figure> getFigure(String figureId) async {
try {
final response = await supabase
.from('figures')
.select(_kFigureColumns)
.eq('figure_id', figureId)
.maybeSingle()
.timeout(_requestTimeout);
if (response == null) {
throw const FiguresServiceException(
'Figure not found.',
code: 'not_found',
);
}
return Figure.fromJson(response);
} on FiguresServiceException {
rethrow;
} catch (e) {
throw _mapException(e);
}
}
// ── Get Statement Count
// ─────────────────────────────────────────────
/// Returns the total number of public statements for a figure.
///
/// Reads from v_statements_public (A9A) which already filters
/// is_revoked = false and is_active = true. Uses PostgREST count
/// for efficiency - minimal data transferred.
///
/// Used by the Figure Profile "Recent Statements (N)" badge.
///
/// supabase_flutter ^2.12.0 count pattern:
/// .select() returns PostgrestResponse with .count when
/// CountOption.exact is specified.
Future<int> getStatementCount(String figureId) async {
try {
final response = await supabase
.from('v_statements_public')
.select('statement_id')
.eq('figure_id', figureId)
.count(CountOption.exact)
.timeout(_requestTimeout);
// .count(CountOption.exact) returns PostgrestResponse with .count.
return response.count;
} on FiguresServiceException {
rethrow;
} catch (e) {
throw _mapException(e);
}
}
// ── Search Figures
// ──────────────────────────────────────────────────
/// Searches active figures by name (case-insensitive match).
///
/// Used by the Search Tab (F4.14 / F3.14) for the "FIGURES" section.
/// Returns up to [limit] results, default 10.
///
/// Uses PostgREST's `ilike` for case-insensitive matching.
/// Matches anywhere in the name (not just prefix) for better UX.
/// SQL LIKE wildcards (% and _) in user input are escaped to
/// prevent unexpected matches.
Future<List<Figure>> searchFigures(String query, {int limit = 10}) async {
try {
if (query.trim().isEmpty) return [];
final escaped = _escapeLikeQuery(query.trim());
final response = await supabase
.from('figures')
.select(_kFigureColumns)
.eq('is_active', true)
.ilike('name', '%$escaped%')
.order('name')
.limit(limit)
.timeout(_requestTimeout);
final figures = <Figure>[];
int skippedCount = 0;
for (final raw in response) {
try {
figures.add(Figure.fromJson(raw));
} catch (_) {
skippedCount++;
}
}
if (kDebugMode && skippedCount > 0) {
debugPrint(
'FiguresService.searchFigures: skipped $skippedCount malformed results',
);
}
return figures;
} on FiguresServiceException {
rethrow;
} catch (e) {
throw _mapException(e);
}
}

// ── Get Figure Profile Analytics
// ────────────────────────────────
/// Fetches aggregated profile data for a single figure from
/// the get-figure-profile Edge Function.
///
/// Returns framing distribution, avg signal pulse, top topic,
/// last statement timestamp, and statement count.
///
/// Used by Figure Profile screen for intel summary and framing
/// fingerprint sections.
Future<FigureProfileData> getFigureProfile(String figureId) async {
try {
final response = await supabase.functions.invoke(
'get-figure-profile',
body: {'figure_id': figureId},
);
if (response.status != 200) {
final errData = response.data;
final msg = errData is Map ? errData['error'] as String? : null;
throw FiguresServiceException(
msg ?? 'Failed to load profile data',
code: 'profile_error',
);
}
final data = response.data;
if (data is! Map<String, dynamic>) {
throw const FormatException('get-figure-profile: invalid response');
}
return FigureProfileData.fromJson(data);
} on FiguresServiceException {
rethrow;
} catch (e) {
throw _mapException(e);
}
}
}

/// Aggregated profile analytics returned by get-figure-profile EF.
class FigureProfileData {
const FigureProfileData({
required this.figureId,
required this.statementCount,
this.lastStatementAt,
this.avgSignalPulse,
this.topTopic,
this.framingDistribution,
});

final String figureId;
final int statementCount;
final DateTime? lastStatementAt;
final double? avgSignalPulse;
final String? topTopic;
final Map<String, double>? framingDistribution;

factory FigureProfileData.fromJson(Map<String, dynamic> json) {
// Parse framing distribution
Map<String, double>? framing;
final rawFraming = json['framing_distribution'];
if (rawFraming is Map<String, dynamic>) {
framing = {};
for (final entry in rawFraming.entries) {
if (entry.value is num) {
framing[entry.key] = (entry.value as num).toDouble();
}
}
if (framing.isEmpty) framing = null;
}

// Parse last_statement_at
DateTime? lastAt;
final rawLast = json['last_statement_at'];
if (rawLast is String) {
lastAt = DateTime.tryParse(rawLast);
}

return FigureProfileData(
figureId: json['figure_id'] as String? ?? '',
statementCount: (json['statement_count'] as num?)?.toInt() ?? 0,
lastStatementAt: lastAt,
avgSignalPulse: (json['avg_signal_pulse'] as num?)?.toDouble(),
topTopic: json['top_topic'] as String?,
framingDistribution: framing,
);
}
}

final figuresServiceProvider = Provider<FiguresService>((ref) => FiguresService());
