/// F7.3 -- Figures Provider
///
/// Riverpod providers for figure data:
///
/// 1. [figuresProvider] - All active figures for the Figures Tab (F4.15).
/// Fetches once, caches across tab switches. Supports in-tab search
/// (150.1) via client-side name/role/category filter, favorites
/// (150.11), and one-tap follow (150.44).
///
/// 2. [figureProvider] - Single figure by ID for Figure Profile (F4.8).
/// Family provider keyed by figureId. Cache-first from figuresProvider.
///
/// 3. [statementCountProvider] - Statement count for a figure (F4.8
/// count badge, 150.20). Family provider keyed by figureId.
///
/// DATA SOURCE: PostgREST via FiguresService (F3.5) - the ONLY
/// PostgREST exception in the app. Public-read, RLS-gated, zero-compute.
///
/// FOLLOWS PERSISTENCE:
/// Followed figure IDs are persisted to SharedPreferences immediately
/// on toggle. Loaded on provider build. Backend sync (user_follows
/// table for 150.26 feed filter) deferred to P-series.
///
/// EXPANSION FEATURES INCORPORATED:
/// - 150.1: In-tab search → client-side filter (name + role + category)
/// - 150.9: Request figure → no provider impact (UI + service call)
/// - 150.11: Favorites → persisted followedIds + filtered view
/// - 150.20: Count badge → statementCountProvider
/// - 150.44: One-tap follow → toggleFollow() with persistence
///
/// Path: lib/providers/figures_provider.dart
library;
// 1. Dart SDK
import 'dart:async';
// 2. Flutter
import 'package:flutter/foundation.dart';
// 3. Third-party
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
// 4. Project -- models
import 'package:baseline_app/models/figure.dart';
import 'package:baseline_app/models/feed_statement.dart';
// 5. Project -- services
import 'package:baseline_app/services/figures_service.dart';
import 'package:baseline_app/services/feed_service.dart';
// 6. Project -- config
import 'package:baseline_app/config/tier_feature_map.dart';
// 7. Project -- providers
import 'package:baseline_app/providers/tier_provider.dart';
// 8. Project -- utils
import 'package:baseline_app/utils/haptic_util.dart';
// ══════════════════════════════════════════════════════════
// CONSTANTS
// ══════════════════════════════════════════════════════════
/// Timeout for figures fetch requests.
const Duration _kFiguresTimeout = Duration(seconds: 10);
/// SharedPreferences key for persisted followed figure IDs.
const String _kFollowedIdsKey = 'baseline_followed_figure_ids';
// ══════════════════════════════════════════════════════════
// FOLLOW CAP EXCEPTION
// ══════════════════════════════════════════════════════════
/// Thrown when a Core-tier user attempts to follow more figures
/// than [TierLimits.followedFiguresCap] allows.
class FollowCapException implements Exception {
  const FollowCapException({
    required this.message,
    required this.currentCount,
    required this.cap,
  });
  final String message;
  final int currentCount;
  final int cap;
  @override
  String toString() => 'FollowCapException: $message '
      '(current: $currentCount, cap: $cap)';
}
// ══════════════════════════════════════════════════════════
// STATE -- FIGURES LIST
// ══════════════════════════════════════════════════════════
/// Complete figures list state for the Figures Tab.
///
/// Wrapped in AsyncValue by the AsyncNotifier:
/// - AsyncLoading = initial fetch in progress
/// - AsyncData(FiguresState) = figures loaded
/// - AsyncError = fetch failed
///
/// [filteredFigures] is cached and recomputed only when filters or
/// source data change (via [_recomputeFiltered]). This avoids
/// redundant allocation during widget rebuilds.
class FiguresState {
const FiguresState({
this.allFigures = const [],
this.filteredFigures = const [],
this.isRefreshing = false,
this.hasPartialFailure = false,
this.searchQuery = '',
this.followedIds = const {},
this.showFavoritesOnly = false,
});
/// All active figures from the backend (sorted by category +
/// activation_order - FiguresService handles the sort).
final List<Figure> allFigures;
/// Cached filtered view of [allFigures]. Recomputed by
/// [_recomputeFiltered] when search, favorites, or source changes.
/// This is what the Figures Tab actually renders.
final List<Figure> filteredFigures;
/// Whether a pull-to-refresh is in progress.
final bool isRefreshing;
/// Whether some figures failed to parse.
/// Reset on successful refresh.
final bool hasPartialFailure;
/// Current in-tab search query (150.1). Empty = show all.
/// Matches against name, role, and category (case-insensitive).
final String searchQuery;
/// Set of followed figure IDs (150.11 / 150.44).
/// Persisted to SharedPreferences.
final Set<String> followedIds;
/// Whether to show only followed/favorited figures.
final bool showFavoritesOnly;
// ── Derived Accessors ────────────────────────────────────
/// Total count of active figures (unfiltered).
int get totalCount => allFigures.length;
/// Count of figures matching current filters.
int get filteredCount => filteredFigures.length;
/// Whether search is active.
bool get isSearching => searchQuery.isNotEmpty;
/// Whether a figure is followed.
bool isFollowed(String figureId) => followedIds.contains(figureId);
FiguresState copyWith({
List<Figure>? allFigures,
List<Figure>? filteredFigures,
bool? isRefreshing,
bool? hasPartialFailure,
String? searchQuery,
Set<String>? followedIds,
bool? showFavoritesOnly,
}) {
return FiguresState(
allFigures: allFigures ?? this.allFigures,
filteredFigures: filteredFigures ?? this.filteredFigures,
isRefreshing: isRefreshing ?? this.isRefreshing,
hasPartialFailure: hasPartialFailure ?? this.hasPartialFailure,
searchQuery: searchQuery ?? this.searchQuery,
followedIds: followedIds ?? this.followedIds,
showFavoritesOnly: showFavoritesOnly ?? this.showFavoritesOnly,
);
}
}
// ══════════════════════════════════════════════════════════
// FILTER HELPER
// ══════════════════════════════════════════════════════════
/// Recomputes the filtered figures list from source data + filters.
/// Pure function - no side effects.
List<Figure> _recomputeFiltered({
required List<Figure> allFigures,
required String searchQuery,
required Set<String> followedIds,
required bool showFavoritesOnly,
}) {
var result = allFigures;
// Favorites filter.
if (showFavoritesOnly && followedIds.isNotEmpty) {
result = result
.where((f) => followedIds.contains(f.figureId))
.toList();
}
// Search filter (150.1) - case-insensitive on name, role, category.
if (searchQuery.isNotEmpty) {
final query = searchQuery.toLowerCase();
result = result.where((f) {
if (f.name.toLowerCase().contains(query)) return true;
if (f.role?.toLowerCase().contains(query) ?? false) return true;
if (f.category.toLowerCase().contains(query)) return true;
return false;
}).toList();
}
return result;
}
// ══════════════════════════════════════════════════════════
// PROVIDER -- FIGURES LIST
// ══════════════════════════════════════════════════════════
/// All active figures for the Figures Tab.
///
/// Usage:
/// ```dart
/// final figuresAsync = ref.watch(figuresProvider);
/// figuresAsync.when(
/// data: (state) => _buildGroupedList(state.filteredFigures),
/// loading: () => ShimmerLoading(),
/// error: (e, _) => ErrorState(onRetry: () => ref.invalidate(figuresProvider)),
/// );
///
/// // In-tab search (150.1)
/// ref.read(figuresProvider.notifier).setSearch('senator');
///
/// // Toggle follow (150.44)
/// ref.read(figuresProvider.notifier).toggleFollow(figureId);
/// ```
final figuresProvider =
AsyncNotifierProvider<FiguresNotifier, FiguresState>(
FiguresNotifier.new,
);
/// Notifier managing the full list of active figures.
class FiguresNotifier extends AsyncNotifier<FiguresState> {
final FiguresService _figuresService = const FiguresService();
int _epoch = 0;
int _bumpEpoch() => ++_epoch;
bool _isCurrent(int epoch) => epoch == _epoch;
@override
Future<FiguresState> build() async {
ref.keepAlive();
final epoch = _bumpEpoch();
// Load persisted follows.
final followedIds = await _loadFollowedIds();
// Fetch figures.
final response = await _figuresService
.getActiveFigures()
.timeout(_kFiguresTimeout);
if (!_isCurrent(epoch)) {
// Stale build - newer build/refresh started. Return empty
// state; the newer call will set the real state.
return const FiguresState();
}
final filtered = _recomputeFiltered(
allFigures: response.figures,
searchQuery: '',
followedIds: followedIds,
showFavoritesOnly: false,
);
return FiguresState(
allFigures: response.figures,
filteredFigures: filtered,
hasPartialFailure: response.hasPartialFailure,
followedIds: followedIds,
);
}
// ── Persistence ──────────────────────────────────────────
/// Loads followed IDs from SharedPreferences.
Future<Set<String>> _loadFollowedIds() async {
try {
final prefs = await SharedPreferences.getInstance();
final ids = prefs.getStringList(_kFollowedIdsKey);
return ids?.toSet() ?? {};
} catch (_) {
return {};
}
}
/// Persists followed IDs to SharedPreferences.
Future<void> _saveFollowedIds(Set<String> ids) async {
try {
final prefs = await SharedPreferences.getInstance();
await prefs.setStringList(_kFollowedIdsKey, ids.toList());
} catch (e) {
if (kDebugMode) debugPrint('FiguresProvider: failed to save follows: $e');
}
}
// ── Refresh ──────────────────────────────────────────────
/// Pull-to-refresh. Preserves search query, follows, favorites toggle.
/// Resets partial failure on success.
Future<void> refresh() async {
final current = state.valueOrNull;
if (current == null) {
ref.invalidateSelf();
return;
}
if (current.isRefreshing) return;
final epoch = _bumpEpoch();
state = AsyncData(current.copyWith(isRefreshing: true));
HapticUtil.light();
try {
final response = await _figuresService
.getActiveFigures()
.timeout(_kFiguresTimeout);
if (!_isCurrent(epoch)) return;
final filtered = _recomputeFiltered(
allFigures: response.figures,
searchQuery: current.searchQuery,
followedIds: current.followedIds,
showFavoritesOnly: current.showFavoritesOnly,
);
// Preserve user state, reset partial failure.
state = AsyncData(current.copyWith(
allFigures: response.figures,
filteredFigures: filtered,
isRefreshing: false,
hasPartialFailure: response.hasPartialFailure,
));
} on FiguresServiceException catch (e) {
if (kDebugMode) debugPrint('FiguresProvider.refresh: $e');
if (!_isCurrent(epoch)) return;
state = AsyncData(current.copyWith(isRefreshing: false));
rethrow;
} on TimeoutException {
if (kDebugMode) debugPrint('FiguresProvider.refresh: timeout');
if (!_isCurrent(epoch)) return;
state = AsyncData(current.copyWith(isRefreshing: false));
rethrow;
} catch (e) {
if (kDebugMode) debugPrint('FiguresProvider.refresh: $e');
if (!_isCurrent(epoch)) return;
state = AsyncData(current.copyWith(isRefreshing: false));
rethrow;
}
}
// ── In-Tab Search (150.1) ────────────────────────────────
/// Sets the search query for client-side filtering.
/// Matches name, role, and category (case-insensitive).
/// Empty string clears the filter. Instant - no network call.
void setSearch(String query) {
final current = state.valueOrNull;
if (current == null) return;
if (current.searchQuery == query) return;
final filtered = _recomputeFiltered(
allFigures: current.allFigures,
searchQuery: query,
followedIds: current.followedIds,
showFavoritesOnly: current.showFavoritesOnly,
);
state = AsyncData(current.copyWith(
searchQuery: query,
filteredFigures: filtered,
));
}
/// Alias for [setSearch] - used by some screens.
void updateSearch(String query) => setSearch(query);
/// Clears the search query.
void clearSearch() => setSearch('');
// ── Favorites / Follow (150.11, 150.44) ──────────────────
/// Toggles follow state for a figure.
/// Persisted to SharedPreferences immediately.
/// Backend sync (user_follows table) deferred to P-series.
///
/// Throws [FollowCapException] if a Core-tier user tries to exceed
/// the followed figures cap (10). Unfollows are always allowed.
void toggleFollow(String figureId) {
final current = state.valueOrNull;
if (current == null) return;
final updated = Set<String>.from(current.followedIds);
if (updated.contains(figureId)) {
updated.remove(figureId);
} else {
// Enforce followed figures cap for Core tier
final tier = ref.read(tierProvider).tier;
final cap = TierLimits.followedFiguresLimit(tier);
if (cap != null && updated.length >= cap) {
  throw FollowCapException(
    message: 'You can follow up to $cap figures on your current plan. '
        'Upgrade to Pro for unlimited follows.',
    currentCount: updated.length,
    cap: cap,
  );
}
updated.add(figureId);
}
HapticUtil.light();
final filtered = _recomputeFiltered(
allFigures: current.allFigures,
searchQuery: current.searchQuery,
followedIds: updated,
showFavoritesOnly: current.showFavoritesOnly,
);
state = AsyncData(current.copyWith(
followedIds: updated,
filteredFigures: filtered,
));
// Fire-and-forget persistence.
_saveFollowedIds(updated);
}
/// Toggles favorites-only view mode.
void toggleFavoritesOnly() {
final current = state.valueOrNull;
if (current == null) return;
final newValue = !current.showFavoritesOnly;
HapticUtil.light();
final filtered = _recomputeFiltered(
allFigures: current.allFigures,
searchQuery: current.searchQuery,
followedIds: current.followedIds,
showFavoritesOnly: newValue,
);
state = AsyncData(current.copyWith(
showFavoritesOnly: newValue,
filteredFigures: filtered,
));
}
}
// ══════════════════════════════════════════════════════════
// PROVIDER -- SINGLE FIGURE (FAMILY)
// ══════════════════════════════════════════════════════════
/// Single figure provider keyed by figureId.
///
/// Used by Figure Profile (F4.8) for the header data.
/// Cache-first from [figuresProvider], fallback to direct fetch.
///
/// Usage:
/// ```dart
/// final figureAsync = ref.watch(figureProvider(figureId));
/// figureAsync.when(
/// data: (figure) => _buildHeader(figure),
/// loading: () => ShimmerLoading(),
/// error: (e, _) => isFigureNotFound(e)
/// ? _buildNotFound()
/// : _buildError(e),
/// );
/// ```
final figureProvider =
AsyncNotifierProvider.family<FigureNotifier, Figure, String>(
FigureNotifier.new,
);
/// Single figure notifier.
///
/// Resolution strategy:
/// 1. Check [figuresProvider] cache (already loaded for Figures Tab)
/// 2. If not found, fetch directly via [FiguresService.getFigure]
///
/// Avoids duplicate network calls on the common
/// Figures Tab → Figure Profile navigation path.
class FigureNotifier extends FamilyAsyncNotifier<Figure, String> {
final FiguresService _figuresService = const FiguresService();
int _epoch = 0;
int _bumpEpoch() => ++_epoch;
bool _isCurrent(int epoch) => epoch == _epoch;
@override
Future<Figure> build(String arg) async {
ref.keepAlive();
// Try cache-first from the figures list (no async, no epoch needed).
final figuresState = ref.read(figuresProvider).valueOrNull;
if (figuresState != null) {
Figure? cached;
for (final f in figuresState.allFigures) {
if (f.figureId == arg) {
cached = f;
break;
}
}
if (cached != null) return cached;
}
// Cache miss - direct fetch (deep link, deactivated figure, etc.)
// Epoch-guarded for invalidateSelf safety.
final epoch = _bumpEpoch();
final figure = await _figuresService
.getFigure(arg)
.timeout(_kFiguresTimeout);
if (!_isCurrent(epoch)) {
throw StateError('FigureProvider: stale build discarded');
}
return figure;
}
/// Re-fetches the figure (bypasses cache).
Future<void> refresh() async {
final epoch = _bumpEpoch();
HapticUtil.light();
try {
final figure = await _figuresService
.getFigure(arg)
.timeout(_kFiguresTimeout);
if (!_isCurrent(epoch)) return;
state = AsyncData(figure);
} on FiguresServiceException catch (e) {
if (kDebugMode) debugPrint('FigureProvider.refresh: $e');
if (!_isCurrent(epoch)) return;
// Keep stale data if available.
} on TimeoutException {
if (kDebugMode) debugPrint('FigureProvider.refresh: timeout');
if (!_isCurrent(epoch)) return;
} catch (e) {
if (kDebugMode) debugPrint('FigureProvider.refresh: $e');
if (!_isCurrent(epoch)) return;
}
}
}
// ══════════════════════════════════════════════════════════
// PROVIDER -- STATEMENT COUNT (FAMILY)
// ══════════════════════════════════════════════════════════
/// Statement count for a figure (F4.8 count badge, 150.20).
///
/// Usage:
/// ```dart
/// final countAsync = ref.watch(statementCountProvider(figureId));
/// countAsync.when(
/// data: (count) => Text('$count statements'),
/// loading: () => Text('...'),
/// error: (_, __) => Text('--'),
/// );
/// ```
final statementCountProvider =
AsyncNotifierProvider.family<StatementCountNotifier, int, String>(
StatementCountNotifier.new,
);
/// Statement count notifier. Epoch-guarded, keeps stale on failure.
class StatementCountNotifier extends FamilyAsyncNotifier<int, String> {
final FiguresService _figuresService = const FiguresService();
int _epoch = 0;
int _bumpEpoch() => ++_epoch;
bool _isCurrent(int epoch) => epoch == _epoch;
@override
Future<int> build(String arg) async {
ref.keepAlive();
final epoch = _bumpEpoch();
final count = await _figuresService
.getStatementCount(arg)
.timeout(_kFiguresTimeout);
if (!_isCurrent(epoch)) {
throw StateError('StatementCountProvider: stale build discarded');
}
return count;
}
/// Re-fetches the count. Keeps stale value on failure.
Future<void> refresh() async {
final epoch = _bumpEpoch();
try {
final count = await _figuresService
.getStatementCount(arg)
.timeout(_kFiguresTimeout);
if (!_isCurrent(epoch)) return;
state = AsyncData(count);
} catch (e) {
if (kDebugMode) debugPrint('StatementCountProvider.refresh: $e');
if (!_isCurrent(epoch)) return;
// Keep stale count on failure - do not overwrite.
}
}
}
// ══════════════════════════════════════════════════════════
// HELPER: 404 DETECTION
// ══════════════════════════════════════════════════════════
/// Whether an AsyncError from [figureProvider] is a 404.
///
/// Usage in screens:
/// ```dart
/// figureAsync.when(
/// data: (figure) => _buildHeader(figure),
/// loading: () => ShimmerLoading(),
/// error: (e, _) => isFigureNotFound(e)
/// ? _buildNotFound()
/// : _buildError(e),
/// );
/// ```
bool isFigureNotFound(Object error) {
return error is FiguresServiceException && error.code == 'not_found';
}
// ══════════════════════════════════════════════════════════
// PROVIDER -- FIGURE PROFILE DATA (FAMILY)
// ══════════════════════════════════════════════════════════
/// Aggregated profile analytics from get-figure-profile EF.
///
/// Returns framing distribution, avg signal pulse, top topic,
/// last statement timestamp, and total statement count.
/// Used by Figure Profile for intel summary + framing fingerprint.
final figureProfileDataProvider =
    FutureProvider.family<FigureProfileData, String>((ref, figureId) async {
  const service = FiguresService();
  return service
      .getFigureProfile(figureId)
      .timeout(_kFiguresTimeout);
});
// ══════════════════════════════════════════════════════════
// PROVIDER -- RECENT STATEMENTS (FAMILY)
// ══════════════════════════════════════════════════════════
/// Recent statements for a figure's profile timeline.
///
/// Fetches the 5 most recent statements via get-feed EF (same as Today Feed).
/// Returns [FeedStatement] objects compatible with StatementCard.compact().
final figureRecentStatementsProvider =
    FutureProvider.family<List<FeedStatement>, String>((ref, figureId) async {
  const feedService = FeedService();
  final response = await feedService
      .getFeed(figureId: figureId, limit: 5, sortBy: 'recency')
      .timeout(_kFiguresTimeout);
  return response.statements;
});
