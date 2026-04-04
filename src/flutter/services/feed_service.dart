import 'package:flutter_riverpod/flutter_riverpod.dart';
/// F3.3 — Feed Service
///
/// Stateless service wrapping feed data access for the Today Feed (F4.6):
///
/// 1. **Statements** via get-feed Edge Function (A9B v2.0.0).
///    Paginated, filtered, sorted. The primary feed content.
///
/// 2. **Mutation alerts** via `get_recent_mutation_alerts` RPC (PM-MT.1).
///    High-mutation bill version comparisons for feed_mutation_card.
///
/// 3. **Spending alerts** via `get_recent_spending_alerts` RPC (PM-ST.1).
///    High-spend bills with anomaly/crossover data for feed_spending_card.
///
/// 4. **Bill alert convergence** via [convergeBillAlerts] utility.
///    Dedup doctrine: drift=spatial, mutation=temporal, spending=fiscal.
///    Same bill with multiple signals = ONE card, not separate entries.
///
/// Drift alerts are fetched via BillSummaryService (P3), not this service.
/// The convergence utility accepts drift bill IDs from the caller.
///
/// Access: Public (anon key). No authentication required.
///
/// Path: lib/services/feed_service.dart

import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:baseline_app/config/constants.dart';
import 'package:baseline_app/models/feed_alerts.dart';
import 'package:baseline_app/models/feed_statement.dart';
import 'package:baseline_app/services/supabase_client.dart';

// ════════════════════════════════════════════════════════════════════════
// CONSTANTS
// ════════════════════════════════════════════════════════════════════════

/// Maximum limit accepted by the get-feed backend.
const int _kMaxLimit = 200;

/// Maximum followed figure IDs the backend accepts (after dedup).
/// Matches MAX_FOLLOWED_IDS in A9B v2.0.0.
const int _kMaxFollowedIds = 50;

/// Valid sort_by values accepted by A9B v2.0.0.
const Set<String> _kValidSortBy = {
  'smart',
  'recency',
  'novelty',
  'signal',
  'divergence',
};

/// Maximum mutation alerts to request per feed load.
/// Feed shows 0-2 mutation cards max (F4.6 interleave logic).
const int _kMaxMutationAlerts = 5;

/// Maximum spending alerts to request per feed load.
/// Feed shows 0-2 spending cards max (F4.6 interleave logic).
const int _kMaxSpendingAlerts = 5;

/// Default lookback window for alert RPCs (days).
const int _kDefaultAlertLookbackDays = 7;

// ════════════════════════════════════════════════════════════════════════
// EXCEPTION
// ════════════════════════════════════════════════════════════════════════

/// Typed exception for feed operations.
class FeedServiceException implements Exception {
  const FeedServiceException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => 'FeedServiceException($code): $message';
}

// ════════════════════════════════════════════════════════════════════════
// FEED RESPONSE
// ════════════════════════════════════════════════════════════════════════

/// Structured feed response including pagination and filter metadata.
///
/// [returned] is the count of successfully parsed items in this page.
/// [rawCount] is the count of items the backend actually returned
/// (before client-side parsing). Used for accurate pagination:
/// if rawCount == limit, more pages likely exist even if some items
/// failed to parse.
///
/// [skippedCount] tracks items that failed to parse. If > 0, the UI
/// should show the partial failure banner (F2.17).
///
/// [effectiveSortBy] reflects the backend's effective sort, which may
/// differ from the requested sort (e.g. ranked_only without explicit
/// sort_by results in effective 'signal'). F7.1 uses this for session
/// cache key validation. Null when backend is pre-v2 (graceful fallback).
///
/// [followedFigureIdsCount] is the count the backend applied (0 when
/// figure_id override is active, or when no followed filter sent).
class FeedResponse {
  const FeedResponse({
    required this.statements,
    required this.limit,
    required this.offset,
    required this.returned,
    required this.rawCount,
    this.skippedCount = 0,
    this.effectiveSortBy,
    this.followedFigureIdsCount = 0,
  });

  final List<FeedStatement> statements;
  final int limit;
  final int offset;
  final int returned;
  final int rawCount;
  final int skippedCount;
  final String? effectiveSortBy;
  final int followedFigureIdsCount;

  /// Whether more pages likely exist.
  /// Based on the raw network count (before parse filtering) to avoid
  /// prematurely halting pagination when some items fail to parse.
  bool get hasMore => rawCount == limit;

  /// Whether some items failed to parse (for partial failure banner).
  bool get hasPartialFailure => skippedCount > 0;
}

// ════════════════════════════════════════════════════════════════════════
// SERVICE
// ════════════════════════════════════════════════════════════════════════

class FeedService {
  const FeedService();

  // ── Private Helpers ─────────────────────────────────────────────────

  /// Maps exceptions to UI-safe [FeedServiceException].
  static FeedServiceException _mapException(Object e) {
    if (kDebugMode) {
      debugPrint('FeedService: ${e.runtimeType}: $e');
    }

    if (e is TimeoutException) {
      return const FeedServiceException(
        'Feed request timed out. Please try again.',
        code: 'timeout',
      );
    }

    if (e is FunctionException) {
      return const FeedServiceException(
        'Unable to load feed. Please try again.',
        code: 'edge_function_error',
      );
    }

    if (e is PostgrestException) {
      return FeedServiceException(
        'Unable to load data. Please try again.',
        code: 'rpc_error_${e.code}',
      );
    }

    if (e is FormatException) {
      return const FeedServiceException(
        'Feed data could not be read.',
        code: 'parse_error',
      );
    }

    return const FeedServiceException(
      'Something went wrong. Please try again.',
      code: 'unexpected_error',
    );
  }

  /// Deduplicates, trims, and clamps followed IDs to backend max.
  /// Returns null if the result is empty (don't send empty array).
  static List<String>? _sanitizeFollowedIds(List<String>? ids) {
    if (ids == null || ids.isEmpty) return null;

    // Trim, deduplicate (preserving insertion order), drop empties.
    final unique = LinkedHashSet<String>.from(
      ids.map((id) => id.trim()).where((id) => id.isNotEmpty),
    ).toList();

    if (unique.isEmpty) return null;

    // Clamp to backend max. Take first N (most recently followed
    // are typically at the front of the caller's list).
    if (unique.length > _kMaxFollowedIds) {
      return unique.sublist(0, _kMaxFollowedIds);
    }

    return unique;
  }

  /// Parses a list of JSON objects into typed models, skipping failures.
  /// Returns parsed items and skip count. Logs first parse error in
  /// debug mode to surface schema drift early.
  static ({List<T> items, int skipped}) _parseList<T>(
    List<dynamic> rawList,
    T Function(Map<String, dynamic>) fromJson,
    String debugLabel,
  ) {
    final items = <T>[];
    int skipped = 0;
    bool firstErrorLogged = false;

    for (final raw in rawList) {
      if (raw is Map<String, dynamic>) {
        try {
          items.add(fromJson(raw));
        } catch (e) {
          skipped++;
          if (kDebugMode && !firstErrorLogged) {
            debugPrint('FeedService._parseList($debugLabel): $e');
            firstErrorLogged = true;
          }
        }
      } else {
        skipped++;
      }
    }

    return (items: items, skipped: skipped);
  }

  // ── Statements (get-feed Edge Function) ─────────────────────────────

  /// Fetches a paginated feed of statements.
  ///
  /// All parameters are optional:
  /// - [figureId]: Filter by figure UUID. Null = all figures.
  ///   When set, [followedFigureIds] is ignored (specific > group).
  /// - [topic]: Filter by topic (UPPERCASE). Null = all topics.
  ///   Must be one of the valid topics from constants.dart (kTopics).
  ///   Invalid topics are silently dropped (not sent to backend).
  /// - [rankedOnly]: If true, only return RANKED statements. Default false.
  /// - [sortBy]: Sort mode: 'smart' | 'recency' | 'novelty' | 'signal' | 'divergence'.
  ///   Null = backend default ('smart' for main feed, 'recency' for figure profile).
  ///   Case-insensitive (normalized to lowercase before validation).
  ///   When [rankedOnly] is true without [sortBy], backend uses 'signal'.
  /// - [followedFigureIds]: Client-sent list of followed figure UUIDs.
  ///   Trimmed, deduped, and clamped to 50 client-side (defense in depth).
  ///   Null or empty = no filter. Ignored when [figureId] is set.
  /// - [limit]: Page size. Clamped to 1-200. Default kFeedPageSize.
  /// - [offset]: Starting index. Clamped to >= 0. Default 0.
  ///
  /// Returns a [FeedResponse] with statements, pagination metadata,
  /// and the effective sort/filter state from the backend.
  ///
  /// If [FeedResponse.skippedCount] > 0, some items failed to parse.
  /// Caller should show partial failure banner (F2.17).
  /// Empty feed returns FeedResponse with empty list (not an error).
  Future<FeedResponse> getFeed({
    String? figureId,
    String? topic,
    bool rankedOnly = false,
    String? sortBy,
    List<String>? followedFigureIds,
    int limit = kFeedPageSize,
    int offset = 0,
  }) async {
    // Clamp parameters to valid ranges.
    final clampedLimit = math.min(math.max(1, limit), _kMaxLimit);
    final clampedOffset = math.max(0, offset);

    // Sanitize followed IDs (trim + dedup + clamp).
    final sanitizedFollowed = _sanitizeFollowedIds(followedFigureIds);

    // Validate sortBy: normalize case, only send if known value.
    final normalizedSort = sortBy?.toLowerCase();
    final validSortBy = (normalizedSort != null &&
            _kValidSortBy.contains(normalizedSort))
        ? normalizedSort
        : null;

    // Validate topic: only send if it's in kTopics.
    final validTopic = (topic != null && kTopics.contains(topic))
        ? topic
        : null;

    try {
      // ── Build request body (conditional inclusion) ─────────────────
      final body = <String, dynamic>{
        'limit': clampedLimit,
        'offset': clampedOffset,
        'figure_id': ?figureId,
        'topic': ?validTopic,
        if (rankedOnly) 'ranked_only': true,
        'sort_by': ?validSortBy,
        'followed_figure_ids': ?sanitizedFollowed,
      };

      final response = await supabase.functions.invoke(
        'get-feed',
        body: body,
      ).timeout(const Duration(seconds: 30));

      // ── Check status before parsing ────────────────────────────────
      if (response.status != 200) {
        String errorMessage = 'Unable to load feed. Please try again.';
        String? errorCode;

        final errData = response.data;
        if (errData is Map<String, dynamic>) {
          errorMessage = errData['error'] as String? ?? errorMessage;
          errorCode = errData['code'] as String?;
        }

        throw FeedServiceException(errorMessage, code: errorCode);
      }

      // ── Parse response ─────────────────────────────────────────────
      final data = response.data;
      if (data is! Map<String, dynamic>) {
        throw const FormatException('get-feed: response is not a JSON object');
      }

      // Parse statements array.
      final rawStatements = data['statements'];
      if (rawStatements is! List) {
        throw const FormatException('get-feed: statements is not an array');
      }

      final rawCount = rawStatements.length;
      final result = _parseList(
        rawStatements,
        FeedStatement.fromJson,
        'FeedStatement',
      );

      if (kDebugMode && result.skipped > 0) {
        debugPrint(
          'FeedService.getFeed: skipped ${result.skipped}/$rawCount statements',
        );
      }

      // ── Parse pagination metadata ──────────────────────────────────
      final pagination = data['pagination'];
      final int responseLimit;
      final int responseOffset;

      if (pagination is Map<String, dynamic>) {
        responseLimit = (pagination['limit'] as num?)?.toInt() ?? clampedLimit;
        responseOffset =
            (pagination['offset'] as num?)?.toInt() ?? clampedOffset;
      } else {
        responseLimit = clampedLimit;
        responseOffset = clampedOffset;
      }

      // ── Parse filters metadata (v2.0.0) ────────────────────────────
      // Gracefully absent when backend is pre-v2.
      final filters = data['filters'];
      String? effectiveSortBy;
      int followedCount = 0;

      if (filters is Map<String, dynamic>) {
        effectiveSortBy = filters['sort_by'] as String?;
        followedCount =
            (filters['followed_figure_ids_count'] as num?)?.toInt() ?? 0;
      }

      return FeedResponse(
        statements: result.items,
        limit: responseLimit,
        offset: responseOffset,
        returned: result.items.length,
        rawCount: rawCount,
        skippedCount: result.skipped,
        effectiveSortBy: effectiveSortBy,
        followedFigureIdsCount: followedCount,
      );
    } on FeedServiceException {
      rethrow;
    } catch (e) {
      throw _mapException(e);
    }
  }

  // ── Mutation Alerts (RPC) ───────────────────────────────────────────

  /// Fetches recent high-mutation bill comparisons for feed cards.
  ///
  /// Calls `get_recent_mutation_alerts` RPC (PM-MT.1). Uses dynamic
  /// thresholds with rolling average and cold-start fallback (backend).
  ///
  /// - [lookbackDays]: How far back to search. Default 7.
  /// - [limit]: Max results. Clamped to 1-[_kMaxMutationAlerts].
  ///
  /// Returns empty list on error (silent fail). Feed works without
  /// mutation cards. F4.6 interleaves 0-2 mutation cards max.
  ///
  /// Tier gating handled at app layer (F6.3: billMutation feature flag).
  Future<List<MutationAlert>> getMutationAlerts({
    int lookbackDays = _kDefaultAlertLookbackDays,
    int limit = _kMaxMutationAlerts,
  }) async {
    final safeLimit = math.min(math.max(1, limit), _kMaxMutationAlerts);

    try {
      final response = await supabase.rpc(
        'get_recent_mutation_alerts',
        params: {
          'p_lookback_days': lookbackDays,
          'p_limit': safeLimit,
        },
      );

      if (response is! List) return const [];

      final result = _parseList(
        response,
        MutationAlert.fromJson,
        'MutationAlert',
      );

      if (kDebugMode && result.skipped > 0) {
        debugPrint(
          'FeedService.getMutationAlerts: '
          'skipped ${result.skipped}/${response.length}',
        );
      }

      return result.items;
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          'FeedService.getMutationAlerts failed '
          '(lookback=$lookbackDays, limit=$safeLimit): $e',
        );
      }
      return const [];
    }
  }

  // ── Spending Alerts (RPC) ───────────────────────────────────────────

  /// Fetches recent high-spend bills for feed cards.
  ///
  /// Calls `get_recent_spending_alerts` RPC (PM-ST.1). Uses dynamic
  /// thresholds with rolling average and cold-start fallback (backend).
  ///
  /// - [lookbackDays]: How far back to search. Default 7.
  /// - [limit]: Max results. Clamped to 1-[_kMaxSpendingAlerts].
  ///
  /// Returns empty list on error (silent fail). Feed works without
  /// spending cards. F4.6 interleaves 0-2 spending cards max.
  ///
  /// Tier gating handled at app layer (F6.3: spendingTracker flag).
  Future<List<SpendingAlert>> getSpendingAlerts({
    int lookbackDays = _kDefaultAlertLookbackDays,
    int limit = _kMaxSpendingAlerts,
  }) async {
    final safeLimit = math.min(math.max(1, limit), _kMaxSpendingAlerts);

    try {
      final response = await supabase.rpc(
        'get_recent_spending_alerts',
        params: {
          'p_lookback_days': lookbackDays,
          'p_limit': safeLimit,
        },
      );

      if (response is! List) return const [];

      final result = _parseList(
        response,
        SpendingAlert.fromJson,
        'SpendingAlert',
      );

      if (kDebugMode && result.skipped > 0) {
        debugPrint(
          'FeedService.getSpendingAlerts: '
          'skipped ${result.skipped}/${response.length}',
        );
      }

      return result.items;
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          'FeedService.getSpendingAlerts failed '
          '(lookback=$lookbackDays, limit=$safeLimit): $e',
        );
      }
      return const [];
    }
  }

  // ── Bill Alert Convergence ──────────────────────────────────────────
}

final feedServiceProvider = Provider<FeedService>((ref) => const FeedService());
