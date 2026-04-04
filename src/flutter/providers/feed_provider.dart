import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:baseline_app/models/feed_statement.dart';
import 'package:baseline_app/models/feed_types.dart';
import 'package:baseline_app/services/feed_service.dart';
import 'package:flutter/foundation.dart';

import 'package:baseline_app/utils/haptic_util.dart';
import 'package:baseline_app/config/constants.dart';

const Duration _kNewCheckThrottle = Duration(seconds: 30);
const Duration _kFeedTimeout = Duration(seconds: 15);
const int _kMaxRetries = 2;
const Duration _kRetryBaseDelay = Duration(seconds: 1);


final feedProvider =
AsyncNotifierProvider<FeedNotifier, FeedState>(FeedNotifier.new);
/// Notifier managing paginated feed data from [FeedService].
///
/// Lifecycle:
/// 1. build() → initial load with default filter
/// 2. loadMore() → appends next page (infinite scroll)
/// 3. refresh() → resets to page 0, replaces all data
/// 4. setFilter() → changes filter, reloads from scratch
/// 5. checkForNew() → polls for new statements (150.19 banner)
///
/// Concurrency: All operations are epoch-guarded. Stale responses
/// (from requests started before the most recent refresh/setFilter)
/// are silently discarded.
class FeedNotifier extends AsyncNotifier<FeedState> {
final FeedService _feedService = const FeedService();
/// Maps [FeedSort] enum to the string the get-feed EF accepts.
static String? _sortByString(FeedSort sort) => switch (sort) {
FeedSort.recency => 'recency',
FeedSort.signal => 'signal',
FeedSort.novelty => 'novelty',
FeedSort.divergence => 'divergence',
};
/// Monotonically increasing epoch for stale-request detection.
/// Incremented on every refresh() and setFilter() call.
int _epoch = 0;
/// Debounce guard for loadMore.
bool _isLoadMoreInFlight = false;
/// Bumps the epoch and returns the new value.
int _bumpEpoch() => ++_epoch;
/// Returns true if [epoch] is still current (not stale).
bool _isCurrent(int epoch) => epoch == _epoch;
@override
Future<FeedState> build() async {
// Keep alive across tab switches (FE-2 session memory).
// State persists for ProviderContainer lifetime (until app process
// killed or explicit invalidation). Tab widget state preserved
// separately by StatefulShellRoute.
ref.keepAlive();
return _fetchInitial(FeedFilter.defaults);
}
// ── Core Fetch ───────────────────────────────────────────
/// Fetches the initial page for a given filter.
/// Returns a fresh [FeedState] with page 0 results.
///
/// If [filter.sort] is [FeedSort.divergence], applies client-side
/// sort on the returned page (interim until P-series backend sort).
Future<FeedState> _fetchInitial(FeedFilter filter) async {
Object? lastError;
StackTrace? lastStack;
for (var attempt = 0; attempt <= _kMaxRetries; attempt++) {
if (attempt > 0) {
await Future<void>.delayed(_kRetryBaseDelay * attempt);
}
try {
final response = await _feedService
.getFeed(
figureId: filter.figureId,
topic: filter.topic,
rankedOnly: filter.rankedOnly,
sortBy: _sortByString(filter.sort),
limit: kFeedPageSize,
offset: 0,
)
.timeout(_kFeedTimeout);
final statements = _applySortIfNeeded(response.statements, filter.sort);
return FeedState(
statements: statements,
offset: response.statements.length,
hasMore: response.hasMore,
hasPartialFailure: response.hasPartialFailure,
filter: filter,
lastRefreshTime: DateTime.now(),
);
} on TimeoutException {
lastError = TimeoutException('Feed request timed out');
lastStack = StackTrace.current;
if (kDebugMode) debugPrint('FeedProvider: timeout (attempt ${attempt + 1}/${_kMaxRetries + 1})');
} on FeedServiceException catch (e, st) {
lastError = e;
lastStack = st;
if (kDebugMode) debugPrint('FeedProvider: $e (attempt ${attempt + 1}/${_kMaxRetries + 1})');
}
}
Error.throwWithStackTrace(lastError!, lastStack!);
}
/// Applies client-side sort for divergence mode (interim).
///
/// Sorts by [baselineDelta] descending (highest divergence first).
/// Statements with null baselineDelta sort to the bottom.
/// No-op for [FeedSort.recency] (backend already sorts by time).
///
/// INTERIM: This sorts only the loaded page. P-series backend
/// will provide global divergence ordering across all statements.
List<FeedStatement> _applySortIfNeeded(
List<FeedStatement> statements,
FeedSort sort,
) {
if (sort != FeedSort.divergence) return statements;
if (statements.length <= 1) return statements;
final sorted = List<FeedStatement>.from(statements);
sorted.sort((a, b) {
final aVal = a.baselineDelta ?? -1.0;
final bVal = b.baselineDelta ?? -1.0;
return bVal.compareTo(aVal); // Descending — highest divergence first.
});
return sorted;
}
// ── Infinite Scroll ──────────────────────────────────────
/// Loads the next page of statements.
///
/// No-op if: already loading more, no more pages, or initial
/// load hasn't completed. Errors are non-fatal — existing data
/// stays visible, user can retry by scrolling again.
///
/// Epoch-guarded: if a refresh or filter change occurs while
/// this request is in flight, the response is silently discarded.
Future<void> loadMore() async {
final current = state.valueOrNull;
if (current == null) return;
if (!current.hasMore) return;
if (_isLoadMoreInFlight) return;
_isLoadMoreInFlight = true;
final epoch = _epoch; // Capture current epoch.
state = AsyncData(current.copyWith(isLoadingMore: true));
try {
final response = await _feedService
.getFeed(
figureId: current.filter.figureId,
topic: current.filter.topic,
rankedOnly: current.filter.rankedOnly,
sortBy: _sortByString(current.filter.sort),
limit: kFeedPageSize,
offset: current.offset,
)
.timeout(_kFeedTimeout);
// Discard if stale (refresh/setFilter happened during flight).
if (!_isCurrent(epoch)) return;
final newStatements =
_applySortIfNeeded(response.statements, current.filter.sort);
// Dedup: filter out statements already in the current list.
final existingIds = <String>{
for (final s in current.statements) s.statementId,
};
final deduped = newStatements
.where((s) => existingIds.add(s.statementId))
.toList();
final updated = current.copyWith(
statements: [...current.statements, ...deduped],
offset: current.offset + response.statements.length,
hasMore: response.hasMore,
isLoadingMore: false,
hasPartialFailure:
current.hasPartialFailure || response.hasPartialFailure,
);
state = AsyncData(updated);
} on FeedServiceException catch (e) {
if (kDebugMode) debugPrint('FeedProvider.loadMore: $e');
if (!_isCurrent(epoch)) return;
state = AsyncData(current.copyWith(isLoadingMore: false));
} on TimeoutException {
if (kDebugMode) debugPrint('FeedProvider.loadMore: timeout');
if (!_isCurrent(epoch)) return;
state = AsyncData(current.copyWith(isLoadingMore: false));
} catch (e) {
if (kDebugMode) debugPrint('FeedProvider.loadMore: $e');
if (!_isCurrent(epoch)) return;
state = AsyncData(current.copyWith(isLoadingMore: false));
} finally {
_isLoadMoreInFlight = false;
}
}
// ── Pull-to-Refresh ──────────────────────────────────────
/// Reloads the feed from offset 0 (150.18).
///
/// Existing data stays visible during refresh (isRefreshing flag).
/// On success, replaces all data and resets partial failure.
/// On failure, existing data stays; error is swallowed.
/// Clears the new-statements banner (150.19).
Future<void> refresh() async {
final current = state.valueOrNull;
if (current == null) {
ref.invalidateSelf();
return;
}
if (current.isRefreshing) return;
final epoch = _bumpEpoch(); // Invalidate any in-flight loadMore.
state = AsyncData(current.copyWith(
isRefreshing: true,
hasNewStatements: false,
));
HapticUtil.light();
try {
final fresh = await _fetchInitial(current.filter);
if (!_isCurrent(epoch)) return;
state = AsyncData(fresh);
} on FeedServiceException catch (e) {
if (kDebugMode) debugPrint('FeedProvider.refresh: $e');
if (!_isCurrent(epoch)) return;
state = AsyncData(current.copyWith(
isRefreshing: false,
hasNewStatements: false,
));
} on TimeoutException {
if (kDebugMode) debugPrint('FeedProvider.refresh: timeout');
if (!_isCurrent(epoch)) return;
state = AsyncData(current.copyWith(
isRefreshing: false,
hasNewStatements: false,
));
} catch (e) {
if (kDebugMode) debugPrint('FeedProvider.refresh: $e');
if (!_isCurrent(epoch)) return;
state = AsyncData(current.copyWith(
isRefreshing: false,
hasNewStatements: false,
));
}
}
// ── Filter & Sort ────────────────────────────────────────
/// Applies a new filter and reloads from scratch.
///
/// If the new filter equals the current filter, this is a no-op.
/// Otherwise triggers a full reload with AsyncLoading state
/// (shimmer skeleton shows). Resets partial failure tracking.
Future<void> setFilter(FeedFilter filter) async {
final current = state.valueOrNull;
if (current != null && current.filter == filter) return;
final epoch = _bumpEpoch();
HapticUtil.light();
state = const AsyncLoading();
try {
final fresh = await _fetchInitial(filter);
if (!_isCurrent(epoch)) return;
state = AsyncData(fresh);
} on FeedServiceException catch (e, st) {
if (!_isCurrent(epoch)) return;
state = AsyncError(e, st);
} on TimeoutException catch (e, st) {
if (!_isCurrent(epoch)) return;
state = AsyncError(e, st);
} catch (e, st) {
if (!_isCurrent(epoch)) return;
state = AsyncError(e, st);
}
}
/// Convenience: update sort mode only.
Future<void> setSort(FeedSort sort) async {
final current = state.valueOrNull;
if (current == null) return;
if (current.filter.sort == sort) return;
await setFilter(current.filter.copyWith(sort: sort));
}
/// Convenience: update topic filter only.
Future<void> setTopic(String? topic) async {
final current = state.valueOrNull;
if (current == null) return;
await setFilter(
topic == null
? current.filter.copyWith(clearTopic: true)
: current.filter.copyWith(topic: topic),
);
}
/// Convenience: toggle followed-only filter (150.26).
///
/// PENDING: No backend effect until P-series ships. Screen must
/// NOT expose this toggle until backend supports followed_only.
Future<void> toggleFollowedOnly() async {
final current = state.valueOrNull;
if (current == null) return;
await setFilter(
current.filter.copyWith(followedOnly: !current.filter.followedOnly),
);
}
// ── New Statements Banner (150.19) ───────────────────────
/// Checks if new statements exist since last refresh.
///
/// Fetches page 0 with limit=1 and compares the top statement ID.
/// If different, sets [hasNewStatements] = true. Tapping the banner
/// in the UI calls [refresh].
///
/// Only runs when sort is [FeedSort.recency] — divergence sort has
/// no meaningful "newest on top" contract, so banner would be
/// misleading. Skips if feed is empty, refreshing, already showing
/// banner, or throttled (60s min interval).
///
/// Silent failure — banner check is non-critical.
Future<void> checkForNew() async {
final current = state.valueOrNull;
if (current == null || current.hasNoStatements) return;
if (current.isRefreshing) return;
if (current.hasNewStatements) return;
// Only meaningful for chronological sort.
if (current.filter.sort != FeedSort.recency) return;
final lastRefresh = current.lastRefreshTime;
if (lastRefresh != null &&
DateTime.now().difference(lastRefresh) < _kNewCheckThrottle) {
return;
}
final epoch = _epoch; // Don't bump — this is read-only.
try {
final probe = await _feedService
.getFeed(
figureId: current.filter.figureId,
topic: current.filter.topic,
rankedOnly: current.filter.rankedOnly,
limit: 1,
offset: 0,
)
.timeout(_kFeedTimeout);
if (!_isCurrent(epoch)) return;
if (probe.statements.isNotEmpty &&
current.statements.isNotEmpty &&
probe.statements.first.statementId !=
current.statements.first.statementId) {
state = AsyncData(current.copyWith(hasNewStatements: true));
}
} catch (_) {
// Silent — banner check is non-critical.
}
}
}
// ══════════════════════════════════════════════════════════
// FIGURE-SCOPED PROVIDER (FAMILY)
// ══════════════════════════════════════════════════════════
/// Feed provider scoped to a single figure (for F4.8 Figure Profile).
///
/// Usage:
///

