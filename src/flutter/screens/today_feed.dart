/// F4.6 — Today Feed (Intelligence Stream Terminal) — LOCKED
///
/// THE SCREEN USERS LIVE IN. Primary home screen, first screen after
/// onboarding/auth. Mixed-content intelligence feed with nine distinct
/// content types:
///
/// 1. TRENDING TOPICS STRIP — horizontal topic chips from P5 RPC
/// 2. DAILY DIGEST CARD — activity summary intel briefing
/// 3. BASELINE™ SPIKE CARDS — figure score volatility alerts (Core)
/// 4. PROVISION DRIFT™ ALERTS — high-drift bill cards (Pro only)
/// 5. MUTATION TIMELINE™ ALERTS — bill version change cards (Pro+)
/// 6. SPENDING SCOPE™ ALERTS — fiscal impact cards (Pro+)
/// 7. STATEMENT CARDS — individual statement briefings (F2.9)
/// 8. CROSSFIRE™ TEASERS — figure comparison entry points (Pro)
/// 9. VOTE ALERT CARDS — roll call vote notifications (Core)
///
/// Visual story: Live intelligence stream terminal. Incoming briefings
/// decoded in real-time. The header is a command center status bar
/// with connection indicator. The sort/filter bar is frequency
/// selection. Cards stagger in like intercepted transmissions being
/// decoded. The "new statements" banner is an incoming alert.
/// Crossfire teasers are intercept correlation flags. The trending
/// strip is a live signal scanner. The digest card is a shift summary.
///
/// Path: lib/screens/today_feed.dart
library;

// 1. Dart SDK
import 'dart:async';
import 'dart:math' as math;

// 2. Flutter
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

// 3. Third-party
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:baseline_app/config/tier_feature_map.dart';

// 4. Config
import 'package:baseline_app/config/theme.dart';
import 'package:baseline_app/config/constants.dart';
import 'package:baseline_app/config/routes.dart';

// 5. Models
import 'package:baseline_app/models/feed_statement.dart';

// 6. State
import 'package:baseline_app/state/feed_session_state.dart';

// 7. Services
import 'package:baseline_app/services/search_service.dart';
import 'package:baseline_app/services/feed_service.dart';
import 'package:baseline_app/services/bill_summary_service.dart';
import 'package:baseline_app/services/supabase_client.dart';

// 8. Providers
import 'package:baseline_app/providers/feed_provider.dart';
import 'package:baseline_app/providers/tier_provider.dart';
import 'package:baseline_app/widgets/empty_state_widget.dart';
import 'package:baseline_app/services/figures_service.dart';

// 9. Widgets
import 'package:baseline_app/widgets/statement_card.dart';
import 'package:baseline_app/widgets/shimmer_loading.dart';
import 'package:baseline_app/widgets/partial_failure_banner.dart';
import 'package:baseline_app/widgets/ad_banner.dart';
import 'package:baseline_app/widgets/feature_gate.dart';
import 'package:baseline_app/widgets/preview_overlay_trigger.dart';
import 'package:baseline_app/widgets/baseline_icons.dart';
import 'package:baseline_app/widgets/feature_ribbon.dart';
import 'package:baseline_app/widgets/feed_mutation_card.dart';
import 'package:baseline_app/widgets/feed_spending_card.dart';
import 'package:baseline_app/widgets/feed_drift_card.dart';
import 'package:baseline_app/widgets/feed_baseline_spike_card.dart';
import 'package:baseline_app/widgets/feed_vote_alert_card.dart';

// 10. Utils
import 'package:baseline_app/utils/haptic_util.dart';
import 'package:baseline_app/models/feed_types.dart';

// ═══════════════════════════════════════════════════════════
// CONSTANTS
// ═══════════════════════════════════════════════════════════

/// Scroll threshold in pixels from bottom to trigger next page load.
const double _kLoadMoreThreshold = 300.0;

/// Number of shimmer skeleton cards shown during initial load.
const int _kShimmerCount = 3;

/// Maximum stagger index (prevents absurd delays on huge feeds).
const int _kMaxStaggerIndex = 20;

/// New-statements poll interval (fallback when FCM unavailable).
const Duration _kNewStatementsPollInterval = Duration(minutes: 5);

/// Duration before "Updated X ago" refreshes its display.
const Duration _kTimestampRefreshInterval = Duration(seconds: 30);

/// Header scan line animation duration.
const Duration _kHeaderScanDuration = Duration(milliseconds: 1200);

/// Banner slide animation duration.
const Duration _kBannerSlideDuration = Duration(milliseconds: 400);

/// Interval (in statement card count) between Crossfire™ teasers.
const int _kCrossfireInterval = 8;

/// Maximum Crossfire™ teaser cards to show in feed.
const int _kMaxCrossfireTeasers = 3;

/// Maximum trending topics to display.
const int _kMaxTrendingTopics = 8;

/// Maximum Provision Drift™ alert cards in feed.
const int _kMaxDriftAlerts = 2;

/// Interval (in statement card count) between vote alert cards.
const int _kVoteAlertInterval = 12;

/// Minimum avg_drift_score to surface in feed.
const double _kDriftAlertThreshold = 0.25;

/// Maximum Baseline™ spike cards in feed.
const int _kMaxBaselineSpikes = 2;

/// Maximum Mutation Timeline™ alert cards in feed.
const int _kMaxMutationAlerts = 2;

/// Maximum Spending Scope™ alert cards in feed.
const int _kMaxSpendingAlerts = 2;

/// Maximum vote alert cards in feed.
const int _kMaxVoteAlerts = 5;

/// Minimum baseline_score (24h rolling AVG signal_rank) to surface as spike.
const double _kBaselineSpikeThreshold = 40.0;

/// Sort pill labels mapped to FeedSort enum values.
const Map<FeedSort, String> _kSortLabels = {
  FeedSort.recency: 'RECENT',
  FeedSort.signal: 'SIGNAL',
  FeedSort.novelty: 'NOVEL',
  FeedSort.divergence: 'DIVERGENT',
};

// ═══════════════════════════════════════════════════════════
// FEED ITEM TYPE SYSTEM
// ═══════════════════════════════════════════════════════════

enum _FeedItemKind {
  trendingStrip,
  dailyDigest,
  statement,
  crossfireTeaser,
  driftAlert,
  mutationAlert,
  spendingAlert,
  baselineSpike,
  voteAlert,
  loadMore,
  partialFailure,
}

class _FeedItem {
  const _FeedItem({
    required this.kind,
    this.statement,
    this.crossfirePair,
    this.driftAlert,
    this.mutationAlert,
    this.spendingAlert,
    this.baselineSpike,
    this.voteAlert,
    this.staggerIndex = 0,
  });

  final _FeedItemKind kind;
  final FeedStatement? statement;
  final CrossfirePair? crossfirePair;
  final DriftAlertData? driftAlert;
  final MutationAlertData? mutationAlert;
  final SpendingAlertData? spendingAlert;
  final BaselineSpikeData? baselineSpike;
  final VoteAlertData? voteAlert;
  final int staggerIndex;
}

/// Minimal Crossfire pair data for the feed teaser.
class CrossfirePair {
  const CrossfirePair({
    required this.id,
    required this.figureNameA,
    required this.figureNameB,
    required this.sharedTopic,
    required this.consensusDelta,
  });

  final String id;
  final String figureNameA;
  final String figureNameB;
  final String sharedTopic;
  final double consensusDelta;

  String get deltaDisplay {
    final pct = (consensusDelta.abs() * 100).round();
    return '$pct%';
  }
}

/// Minimal trending topic data from P5 RPC.
class _TrendingTopicData {
  const _TrendingTopicData({
    required this.topic,
    required this.statementCount,
    required this.trend,
  });

  final String topic;
  final int statementCount;
  final String trend;

  String get trendArrow {
    switch (trend) {
      case 'rising':
        return '↑';
      case 'falling':
        return '↓';
      default:
        return '·';
    }
  }
}

/// Computed daily digest from feed data.
class _DailyDigest {
  const _DailyDigest({
    required this.figureCount,
    required this.statementCount,
    this.topDivergenceFigure,
    this.topDivergenceTopic,
    this.topDivergenceScore,
  });

  final int figureCount;
  final int statementCount;
  final String? topDivergenceFigure;
  final String? topDivergenceTopic;
  final double? topDivergenceScore;

  bool get hasHighlight =>
      topDivergenceFigure != null && topDivergenceTopic != null;
}

// ═══════════════════════════════════════════════════════════
// HELPERS
// ═══════════════════════════════════════════════════════════

String _extractSourceName(String? url) {
  if (url == null || url.isEmpty) return 'Source';
  try {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return 'Source';
    final host = uri.host;
    final stripped = host.startsWith('www.') ? host.substring(4) : host;
    final parts = stripped.split('.');
    if (parts.isEmpty || parts.first.isEmpty) return 'Source';
    final name = parts.first;
    return '${name[0].toUpperCase()}${name.substring(1)}';
  } catch (_) {
    return 'Source';
  }
}

String _formatTimestamp(DateTime? lastUpdated) {
  if (lastUpdated == null) return '';
  final diff = DateTime.now().difference(lastUpdated);
  if (diff.inSeconds < 60) return 'Updated just now';
  if (diff.inMinutes < 60) {
    final m = diff.inMinutes;
    return 'Updated $m min${m == 1 ? '' : 's'} ago';
  }
  if (diff.inHours < 24) {
    final h = diff.inHours;
    return 'Updated $h hr${h == 1 ? '' : 's'} ago';
  }
  return 'Updated ${diff.inDays}d ago';
}

/// Maps P5 topic enum (UPPER_SNAKE) to display name.
/// Uses kTopicDisplayNames from constants.dart (canonical, matches A1 DB enum).
String _topicDisplayName(String raw) {
  return kTopicDisplayNames[raw] ??
      raw
          .split('_')
          .map((w) => w.isEmpty
              ? ''
              : '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}')
          .join(' ');
}

// ═══════════════════════════════════════════════════════════
// TODAY FEED SCREEN
// ═══════════════════════════════════════════════════════════

class TodayFeed extends ConsumerStatefulWidget {
  const TodayFeed({super.key});

  @override
  ConsumerState<TodayFeed> createState() => _TodayFeedState();
}

class _TodayFeedState extends ConsumerState<TodayFeed>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  // ── Controllers ──────────────────────────────────────────

  late final AnimationController _headerScanController;
  late final AnimationController _bannerController;
  late final AnimationController _ambientController;
  final ScrollController _scrollController = ScrollController();

  /// Pending timers for lifecycle cleanup (I-11).
  final List<Timer> _pendingTimers = [];
  Timer? _timestampTimer;
  Timer? _newStatementsTimer;

  // ── Local State ──────────────────────────────────────────

  DateTime? _lastUpdated;
  bool _showNewBanner = false;
  String _timestampText = '';
  bool _hasPlayedEntrance = false;
  bool _reduceMotion = false;

  // ── Sort/Filter ─────────────────────────────────────────

  FeedSort _activeSort = FeedSort.recency;
  bool _followedOnly = false;

  // ── V2: Mixed Content State ─────────────────────────────

  List<_TrendingTopicData> _trendingTopics = const [];
  List<CrossfirePair> _crossfirePairs = const [];
  _DailyDigest? _dailyDigest;
  int _statementCount = 0;
  List<DriftAlertData> _driftAlerts = const [];
  List<MutationAlertData> _mutationAlerts = const [];
  List<SpendingAlertData> _spendingAlerts = const [];
  List<BaselineSpikeData> _baselineSpikes = const [];
  List<VoteAlertData> _voteAlerts = const [];

  // ── Lifecycle ────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _headerScanController = AnimationController(
      vsync: this,
      duration: _kHeaderScanDuration,
    );

    _bannerController = AnimationController(
      vsync: this,
      duration: _kBannerSlideDuration,
    );

    _ambientController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    );
    // repeat() deferred to didChangeDependencies after _reduceMotion is set.

    _scrollController.addListener(_onScroll);

    _timestampTimer = Timer.periodic(
      _kTimestampRefreshInterval,
      (_) => _refreshTimestamp(),
    );
    _pendingTimers.add(_timestampTimer!);

    _newStatementsTimer = Timer.periodic(
      _kNewStatementsPollInterval,
      (_) => _checkForNewStatements(),
    );
    _pendingTimers.add(_newStatementsTimer!);

    // AUDIT FIX A1-W1: Moved data computation from build() whenData()
    // to ref.listen. No side effects in build.
    ref.listenManual(feedProvider, (previous, next) {
      next.whenData((data) {
        final newCount = data.statements.length;
        if (newCount != _statementCount) {
          _statementCount = newCount;
        }
        if (_lastUpdated == null) {
          _computeCrossfirePairs(data.statements);
          _computeDailyDigest(data.statements);
          if (mounted) {
            setState(() {
              _lastUpdated = DateTime.now();
              _timestampText = _formatTimestamp(_lastUpdated);
            });
          }
        }
      });
    });

    // Load supplementary data (fire-and-forget, non-blocking).
    _loadTrendingTopics();
    _loadDriftAlerts();
    _loadMutationAlerts();
    _loadSpendingAlerts();
    _loadBaselineSpikes();
    _loadVoteAlerts();

    SchedulerBinding.instance.addPostFrameCallback((_) {
      _restoreSessionState();
      if (!_reduceMotion) {
        _headerScanController.forward();
      }
      _hasPlayedEntrance = true;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // AUDIT FIX A2-MS1: Mid-flight reduceMotion snap (I-9).
    final wasReduced = _reduceMotion;
    _reduceMotion = MediaQuery.disableAnimationsOf(context);

    if (_reduceMotion && !wasReduced) {
      // Snap all active controllers + cancel pending timers.
      for (final t in _pendingTimers) {
        t.cancel();
      }
      _pendingTimers.clear();
      _headerScanController
        ..stop()
        ..value = 1.0;
      _bannerController.stop();
      _ambientController.stop();
    }

    final tickerActive = TickerMode.valuesOf(context).enabled;
    if (!_reduceMotion) {
      if (tickerActive && !_ambientController.isAnimating) {
        _ambientController.repeat(reverse: true);
      } else if (!tickerActive && _ambientController.isAnimating) {
        _ambientController.stop();
      }
    }
  }

  @override
  void dispose() {
    // 1. Cancel pending timers (I-11).
    for (final t in _pendingTimers) {
      t.cancel();
    }
    _pendingTimers.clear();
    _timestampTimer?.cancel();
    _newStatementsTimer?.cancel();

    // 2. Remove listeners.
    _scrollController.removeListener(_onScroll);

    // 3. Stop all controllers (I-29).
    _headerScanController.stop();
    _bannerController.stop();
    _ambientController.stop();

    // 4. Dispose controllers + scroll.
    _scrollController.dispose();
    _headerScanController.dispose();
    _bannerController.dispose();
    _ambientController.dispose();

    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _ambientController.stop();
    } else if (state == AppLifecycleState.resumed) {
      if (!_reduceMotion && !_ambientController.isAnimating) {
        _ambientController.repeat(reverse: true);
      }
    }
  }

  // ── Session Memory (FE-2) ────────────────────────────────

  void _restoreSessionState() {
    final sessionState = ref.read(feedSessionStateProvider);
    final offset = sessionState.getRestorableOffset(
      SessionKeyBuilder.feed(
        sort: _activeSort.name,
        followedOnly: _followedOnly,
      ),
    );
    if (offset != null && offset > 0 && _scrollController.hasClients) {
      _scrollController.jumpTo(offset);
    }
  }

  void _saveScrollPosition() {
    if (!_scrollController.hasClients) return;
    ref.read(feedSessionStateProvider.notifier).saveOffset(
      SessionKeyBuilder.feed(
        sort: _activeSort.name,
        followedOnly: _followedOnly,
      ),
      _scrollController.offset,
      itemCount: ref.read(feedProvider).valueOrNull?.statements.length ?? 0,
    );
  }

  // ── V2: Mixed Content Data Loading ──────────────────────

  Future<void> _loadTrendingTopics() async {
    try {
      final searchService = SearchService(
        figuresService: ref.read(figuresServiceProvider),
      );
      final topics = await searchService.getTrendingTopics(
        days: 7,
        limit: _kMaxTrendingTopics,
      );
      if (!mounted) return;
      setState(() {
        _trendingTopics = topics
            .map((t) => _TrendingTopicData(
                  topic: t.topic,
                  statementCount: t.statementCount,
                  trend: t.trend,
                ))
            .toList();
      });
    } catch (_) {
      if (!mounted) return;
    }
  }

  Future<void> _loadDriftAlerts() async {
    try {
      final billService = BillSummaryService();
      final summaries = await billService.getRecentDriftAlerts(
        minDrift: _kDriftAlertThreshold,
        days: 7,
        limit: _kMaxDriftAlerts,
      );
      if (!mounted) return;
      setState(() {
        _driftAlerts = summaries
            .map((s) => DriftAlertData(
                  billId: s.billId,
                  billTitle: s.billTitle,
                  avgDriftScore: s.avgDriftScore ?? 0.0,
                  provisionCount: s.provisionCount,
                  detectedAt: s.createdAt,
                  topDriftProvision: s.provisionsByDrift.isNotEmpty
                      ? s.provisionsByDrift.first.title
                      : null,
                  topDriftMagnitude: s.provisionsByDrift.isNotEmpty
                      ? s.provisionsByDrift.first.driftScore
                      : null,
                  provisionDrifts: s.provisionsByDrift
                      .take(8)
                      .map((p) => p.driftScore ?? 0.0)
                      .toList(),
                ))
            .toList();
      });
    } catch (_) {
      // Silent fail. Feed works without drift alerts.
    }
  }

  Future<void> _loadMutationAlerts() async {
    try {
      final response = await supabase
          .from('version_comparisons')
          .select('comparison_id, bill_id, aggregate_mutation, '
              'provisions_added, provisions_removed, provisions_modified, '
              'total_provisions, computed_at, '
              'to_version:bill_versions!version_comparisons_to_version_id_fkey('
              'bill_title, chamber)')
          .gt('aggregate_mutation', 0.0)
          .order('computed_at', ascending: false)
          .limit(_kMaxMutationAlerts);

      if (!mounted) return;

      // Batch-fetch all mutation_diffs in a single query (avoids N+1).
      final allCompIds = response
          .map((r) => r['comparison_id'] as String?)
          .where((id) => id != null)
          .cast<String>()
          .toList();
      final diffsByComparison = <String, List<Map<String, dynamic>>>{};
      if (allCompIds.isNotEmpty) {
        final allDiffs = await supabase
            .from('mutation_diffs')
            .select('comparison_id, provision_title, magnitude, diff_type, '
                'spending_delta, category')
            .inFilter('comparison_id', allCompIds)
            .order('magnitude', ascending: false);
        for (final diff in allDiffs) {
          final cid = diff['comparison_id'] as String;
          diffsByComparison.putIfAbsent(cid, () => []).add(diff);
        }
      }

      if (!mounted) return;
      final alerts = <MutationAlertData>[];
      for (final row in response) {
        final toVersion = row['to_version'] as Map<String, dynamic>?;
        final billTitle = toVersion?['bill_title'] as String? ??
            row['bill_id'] as String? ??
            '';
        final chamber =
            (toVersion?['chamber'] as String? ?? 'HOUSE').toUpperCase();
        final aggMutation =
            (row['aggregate_mutation'] as num?)?.toDouble() ?? 0.0;
        final added = row['provisions_added'] as int? ?? 0;
        final removed = row['provisions_removed'] as int? ?? 0;
        final modified = row['provisions_modified'] as int? ?? 0;
        final computedAt =
            DateTime.tryParse(row['computed_at'] as String? ?? '') ??
                DateTime.now();

        final comparisonId = row['comparison_id'] as String?;
        if (comparisonId == null) continue;

        // Use batch-fetched diffs (top 6 by magnitude per comparison).
        final diffsResp = (diffsByComparison[comparisonId] ?? []).take(6).toList();

        String topTitle = '';
        double topMag = 0.0;
        MutationFeedDiffType topType = MutationFeedDiffType.modified;
        int anomalyCount = 0;
        bool hasSpendingCrossover = false;
        double? spendingDelta;
        final segments = <GeneSegmentStatus>[];

        for (final d in diffsResp) {
          final mag = (d['magnitude'] as num?)?.toDouble() ?? 0.0;
          final typeStr = d['diff_type'] as String? ?? 'modified';
          final sDelta = (d['spending_delta'] as num?)?.toDouble();

          if (topTitle.isEmpty) {
            topTitle = d['provision_title'] as String? ?? '';
            topMag = mag;
            topType = MutationFeedDiffType.values.firstWhere(
              (e) => e.name == typeStr,
              orElse: () => MutationFeedDiffType.modified,
            );
            if (sDelta != null) {
              hasSpendingCrossover = true;
              spendingDelta = sDelta;
            }
          }

          if (mag >= 0.6) {
            anomalyCount++;
            segments.add(GeneSegmentStatus.anomaly);
          } else if (mag > 0.0) {
            segments.add(GeneSegmentStatus.modified);
          } else {
            segments.add(GeneSegmentStatus.unchanged);
          }
        }

        // Pad segments to 6
        while (segments.length < 6) {
          segments.add(GeneSegmentStatus.unchanged);
        }

        alerts.add(MutationAlertData(
          billId: row['bill_id'] as String? ?? '',
          billTitle: billTitle,
          chamber: chamber,
          aggregateMutation: aggMutation,
          topProvisionTitle: topTitle,
          topProvisionMagnitude: topMag,
          topProvisionType: topType,
          addedCount: added,
          removedCount: removed,
          modifiedCount: modified,
          anomalyCount: anomalyCount,
          detectedAt: computedAt,
          geneSegments: segments.take(6).toList(),
          hasSpendingCrossover: hasSpendingCrossover,
          spendingDelta: spendingDelta,
        ));
      }

      if (!mounted) return;
      setState(() {
        _mutationAlerts = alerts;
      });
    } catch (_) {
      // Silent fail. Feed works without mutation alerts.
    }
  }

  Future<void> _loadSpendingAlerts() async {
    try {
      final response = await supabase
          .from('bill_spending_summary')
          .select('summary_id, bill_id, bill_title, total_cbo, '
              'total_extracted, source_type, chamber, latest_delta, '
              'anomaly_count, crossover_count, created_at')
          .order('created_at', ascending: false)
          .limit(_kMaxSpendingAlerts);

      if (!mounted) return;

      // Batch-fetch all spending_data in a single query (avoids N+1).
      final allBillIds = response
          .map((r) => r['bill_id'] as String? ?? '')
          .where((id) => id.isNotEmpty)
          .toList();
      final spendingByBill = <String, List<Map<String, dynamic>>>{};
      if (allBillIds.isNotEmpty) {
        final allSpending = await supabase
            .from('spending_data')
            .select('bill_id, provision_title, amount, percent_of_total')
            .inFilter('bill_id', allBillIds)
            .order('amount', ascending: false);
        for (final row in allSpending) {
          final bid = row['bill_id'] as String;
          spendingByBill.putIfAbsent(bid, () => []).add(row);
        }
      }

      if (!mounted) return;
      final alerts = <SpendingAlertData>[];
      for (final row in response) {
        final billId = row['bill_id'] as String? ?? '';
        final totalCbo = (row['total_cbo'] as num?)?.toDouble() ?? 0.0;
        final totalExtracted =
            (row['total_extracted'] as num?)?.toDouble() ?? 0.0;
        final sourceStr = row['source_type'] as String? ?? 'extracted';
        final heroAmount = totalCbo > 0 ? totalCbo : totalExtracted;
        final chamber = (row['chamber'] as String? ?? '').toUpperCase();
        final createdAt =
            DateTime.tryParse(row['created_at'] as String? ?? '') ??
                DateTime.now();

        // Determine source enum
        final source = sourceStr == 'cbo'
            ? SpendingSource.cbo
            : sourceStr == 'both'
                ? SpendingSource.both
                : SpendingSource.extracted;

        // Use batch-fetched spending data (top 5 by amount per bill).
        final provsResp = (spendingByBill[billId] ?? []).take(5).toList();

        String topProvTitle = '';
        double topProvAmount = 0.0;
        final ratios = <double>[];
        for (final p in provsResp) {
          final amount = (p['amount'] as num?)?.toDouble() ?? 0.0;
          final pct = (p['percent_of_total'] as num?)?.toDouble() ?? 0.0;
          ratios.add(pct);
          if (topProvTitle.isEmpty) {
            topProvTitle = p['provision_title'] as String? ?? '';
            topProvAmount = amount;
          }
        }

        // Normalize hero amount to 0-1 magnitude (scale: $1T = 1.0)
        final magnitude = heroAmount > 0
            ? (heroAmount / 1e12).clamp(0.0, 1.0)
            : 0.0;

        alerts.add(SpendingAlertData(
          billId: billId,
          billTitle: row['bill_title'] as String? ?? billId,
          chamber: chamber,
          heroAmount: heroAmount,
          source: source,
          topProvisionTitle: topProvTitle,
          topProvisionAmount: topProvAmount,
          detectedAt: createdAt,
          spendingMagnitude: magnitude,
          deltaAmount: (row['latest_delta'] as num?)?.toDouble(),
          hasMutationCrossover: (row['crossover_count'] as int? ?? 0) > 0,
          allocationRatios: ratios,
        ));
      }

      if (!mounted) return;
      setState(() {
        _spendingAlerts = alerts;
      });
    } catch (_) {
      // Silent fail. Feed works without spending alerts.
    }
  }

  Future<void> _loadBaselineSpikes() async {
    try {
      final figuresService = const FiguresService();
      final figuresResp = await figuresService.getActiveFigures();
      final figures = figuresResp.figures;
      if (figures.isEmpty) return;

      // Batch call get-baseline-score EF (max 50 per call)
      final figureIds = figures.map((f) => f.figureId).toList();
      final response = await supabase.functions.invoke(
        'get-baseline-score',
        body: {'figure_ids': figureIds.take(50).toList()},
      );
      if (response.status != 200) return;
      final data = response.data as Map<String, dynamic>?;
      if (data == null) return;
      final scores = (data['scores'] as List<dynamic>?) ?? [];

      // Build figure lookup for metadata
      final figureMap = {for (final f in figures) f.figureId: f};

      // Find spikes: figures with baseline_score above threshold
      final spikes = <BaselineSpikeData>[];
      for (final row in scores) {
        final fid = row['figure_id'] as String?;
        final score = (row['baseline_score'] as num?)?.toDouble();
        if (fid == null || score == null || score < _kBaselineSpikeThreshold) {
          continue;
        }
        final figure = figureMap[fid];
        if (figure == null) continue;

        spikes.add(BaselineSpikeData(
          figureId: fid,
          figureName: figure.name,
          party: figure.party ?? '',
          score: score.round(),
          delta: score - 50.0,
          spikePercent: '${((score / 50.0 - 1.0).abs() * 100).round()}%',
          trend: const [],
          timestamp: DateTime.now(),
          photoUrl: figure.photoUrl,
          role: figure.role,
        ));
      }

      // Sort by score descending, take top N
      spikes.sort((a, b) => b.score.compareTo(a.score));

      if (!mounted) return;
      setState(() {
        _baselineSpikes = spikes.take(_kMaxBaselineSpikes).toList();
      });
    } catch (_) {
      // Silent fail. Feed works without baseline spikes.
    }
  }

  Future<void> _loadVoteAlerts() async {
    try {
      final cutoff = DateTime.now()
          .subtract(const Duration(days: 7))
          .toIso8601String()
          .split('T')
          .first;
      final response = await supabase
          .from('votes')
          .select('vote_id, figure_id, bill_id, bill_title, vote, vote_date, '
              'chamber, congress_session, source_url, created_at, '
              'figures!inner(name, metadata)')
          .gte('vote_date', cutoff)
          .order('vote_date', ascending: false)
          .limit(_kMaxVoteAlerts);

      if (!mounted) return;
      final alerts = <VoteAlertData>[];
      for (final row in response) {
        final figureData = row['figures'] as Map<String, dynamic>?;
        final figureName = figureData?['name'] as String? ?? 'Unknown';
        final rawMeta = figureData?['metadata'];
        final metadata = rawMeta is Map
            ? Map<String, dynamic>.from(rawMeta)
            : <String, dynamic>{};
        final party = metadata['party'] as String? ?? '';
        final photoUrl = metadata['photo_url'] as String?;
        final voteStr = row['vote'] as String? ?? '';
        final chamberStr = row['chamber'] as String? ?? '';
        final voteDateStr = row['vote_date'] as String? ?? '';

        alerts.add(VoteAlertData(
          figureId: row['figure_id'] as String? ?? '',
          figureName: figureName,
          party: party,
          billId: row['bill_id'] as String? ?? '',
          billTitle: row['bill_title'] as String? ?? '',
          voteResult: (voteStr == 'YEA' || voteStr == 'NAY')
              ? VoteResult.recorded
              : VoteResult.notRecorded,
          voteDate: DateTime.tryParse(voteDateStr) ?? DateTime.now(),
          chamber: chamberStr == 'SENATE'
              ? VoteChamber.senate
              : VoteChamber.house,
          photoUrl: photoUrl,
        ));
      }

      if (!mounted) return;
      setState(() {
        _voteAlerts = alerts;
      });
    } catch (_) {
      // Silent fail. Feed works without vote alerts.
    }
  }

  void _computeCrossfirePairs(List<FeedStatement> statements) {
    if (statements.length < 4) {
      _crossfirePairs = const [];
      return;
    }

    final pairs = <CrossfirePair>[];
    final seen = <String>{};
    final byTopic = <String, List<FeedStatement>>{};

    for (final stmt in statements) {
      final topics = stmt.topics;
      if (topics == null || topics.isEmpty) continue;
      for (final topic in topics) {
        byTopic.putIfAbsent(topic, () => []).add(stmt);
      }
    }

    for (final entry in byTopic.entries) {
      final topic = entry.key;
      final candidates = entry.value;

      for (var i = 0; i < candidates.length; i++) {
        for (var j = i + 1; j < candidates.length; j++) {
          final a = candidates[i];
          final b = candidates[j];

          if (a.figureId == b.figureId) continue;

          final gap = a.statedAt.difference(b.statedAt).abs();
          if (gap > const Duration(hours: 72)) continue;

          final dedupeKey = _dedupeKey(a.figureId, b.figureId, topic);
          if (seen.contains(dedupeKey)) continue;
          seen.add(dedupeKey);

          final scoreA = a.signalRank ?? 0.0;
          final scoreB = b.signalRank ?? 0.0;
          final delta = (scoreA - scoreB);

          pairs.add(CrossfirePair(
            id: '${a.statementId.substring(0, math.min(8, a.statementId.length))}_'
                '${b.statementId.substring(0, math.min(8, b.statementId.length))}',
            figureNameA: a.figureName,
            figureNameB: b.figureName,
            sharedTopic: topic,
            consensusDelta: delta,
          ));
        }
      }
    }

    pairs.sort((a, b) =>
        b.consensusDelta.abs().compareTo(a.consensusDelta.abs()));

    _crossfirePairs = pairs.take(_kMaxCrossfireTeasers).toList();
  }

  static String _dedupeKey(String a, String b, String topic) {
    final sorted = [a, b]..sort();
    return '${sorted[0]}:${sorted[1]}:$topic';
  }

  void _computeDailyDigest(List<FeedStatement> statements) {
    if (statements.isEmpty) {
      _dailyDigest = null;
      return;
    }

    final figures = <String>{};
    String? topFigure;
    String? topTopic;
    double? topScore;

    for (final stmt in statements) {
      figures.add(stmt.figureId);
      final signal = stmt.signalRank;
      if (signal != null && (topScore == null || signal > topScore)) {
        topScore = signal;
        topFigure = stmt.figureName;
        topTopic = (stmt.topics != null && stmt.topics!.isNotEmpty)
            ? _topicDisplayName(stmt.topics!.first)
            : null;
      }
    }

    _dailyDigest = _DailyDigest(
      figureCount: figures.length,
      statementCount: statements.length,
      topDivergenceFigure: topFigure,
      topDivergenceTopic: topTopic,
      topDivergenceScore: topScore,
    );
  }

  /// Assembles the mixed-content feed item list.
  List<_FeedItem> _buildFeedItems({
    required List<FeedStatement> statements,
    required bool hasPartial,
    required bool isLoadingMore,
  }) {
    final items = <_FeedItem>[];

    if (hasPartial) {
      items.add(const _FeedItem(kind: _FeedItemKind.partialFailure));
    }

    if (_trendingTopics.isNotEmpty) {
      items.add(const _FeedItem(kind: _FeedItemKind.trendingStrip));
    }

    if (_dailyDigest != null) {
      items.add(const _FeedItem(kind: _FeedItemKind.dailyDigest));
    }

    // Collect alert cards for interleaving (not dumped at top).
    // Tier-gate: only include cards the user's tier can access.
    final tier = ref.read(tierProvider).tier;
    final canDrift = canAccessFeature(tier, GatedFeature.provisionDrift);
    final canMutation = canAccessFeature(tier, GatedFeature.billMutation);
    final canSpending = canAccessFeature(tier, GatedFeature.spendingTracker);

    final gatedAlerts = <_FeedItem>[
      for (final spike in _baselineSpikes)
        _FeedItem(kind: _FeedItemKind.baselineSpike, baselineSpike: spike),
      if (canDrift)
        for (final alert in _driftAlerts)
          _FeedItem(kind: _FeedItemKind.driftAlert, driftAlert: alert),
      if (canMutation)
        for (final alert in _mutationAlerts)
          _FeedItem(kind: _FeedItemKind.mutationAlert, mutationAlert: alert),
      if (canSpending)
        for (final alert in _spendingAlerts)
          _FeedItem(kind: _FeedItemKind.spendingAlert, spendingAlert: alert),
    ];

    var statementIndex = 0;
    var crossfireIndex = 0;
    var voteAlertIndex = 0;
    var gatedAlertIndex = 0;

    for (final statement in statements) {
      items.add(_FeedItem(
        kind: _FeedItemKind.statement,
        statement: statement,
        staggerIndex: _hasPlayedEntrance
            ? 0
            : math.min(statementIndex, _kMaxStaggerIndex),
      ));
      statementIndex++;

      // Interleave one gated alert card every 6 statements (after stmt 3).
      if (statementIndex >= 3 &&
          (statementIndex - 3) % 6 == 0 &&
          gatedAlertIndex < gatedAlerts.length) {
        items.add(gatedAlerts[gatedAlertIndex]);
        gatedAlertIndex++;
      }

      if (statementIndex % _kCrossfireInterval == 0 &&
          crossfireIndex < _crossfirePairs.length &&
          canAccessFeature(tier, GatedFeature.crossfire)) {
        items.add(_FeedItem(
          kind: _FeedItemKind.crossfireTeaser,
          crossfirePair: _crossfirePairs[crossfireIndex],
        ));
        crossfireIndex++;
      }

      if (statementIndex % _kVoteAlertInterval == 0 &&
          voteAlertIndex < _voteAlerts.length) {
        items.add(_FeedItem(
          kind: _FeedItemKind.voteAlert,
          voteAlert: _voteAlerts[voteAlertIndex],
        ));
        voteAlertIndex++;
      }
    }

    if (isLoadingMore) {
      items.add(const _FeedItem(kind: _FeedItemKind.loadMore));
    }

    return items;
  }

  // ── Data Operations ──────────────────────────────────────

  Future<void> _onRefresh() async {
    HapticUtil.light();

    // Invalidate the provider to force a fresh fetch from the backend,
    // then await the new data so RefreshIndicator stays visible until
    // the network round-trip completes.
    ref.invalidate(feedProvider);
    await ref.read(feedProvider.future);
    if (!mounted) return;
    HapticUtil.refreshComplete();

    final state = ref.read(feedProvider);
    final stmts = state.valueOrNull?.statements ?? const [];
    _computeCrossfirePairs(stmts);
    _computeDailyDigest(stmts);

    _loadTrendingTopics();
    _loadDriftAlerts();
    _loadMutationAlerts();
    _loadSpendingAlerts();
    _loadBaselineSpikes();
    _loadVoteAlerts();

    setState(() {
      _lastUpdated = DateTime.now();
      _timestampText = _formatTimestamp(_lastUpdated);
      _showNewBanner = false;
    });
    if (!_reduceMotion) {
      _bannerController.reverse();
    }
  }

  /// AUDIT FIX A1-W3: Guard loadMore against isLoadingMore + hasMore.
  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - _kLoadMoreThreshold) {
      final state = ref.read(feedProvider);
      if (state.valueOrNull?.isLoadingMore == true) return;
      ref.read(feedProvider.notifier).loadMore();
    }
    _saveScrollPosition();
  }

  void _checkForNewStatements() {
    final notifier = ref.read(feedProvider.notifier);
    if (_activeSort != FeedSort.recency) return;
    notifier.checkForNew().then((_) {
      if (!mounted) return;
      final state = ref.read(feedProvider);
      final hasNew = state.valueOrNull?.hasNewStatements ?? false;
      if (hasNew && !_showNewBanner) {
        setState(() => _showNewBanner = true);
        if (!_reduceMotion) {
          _bannerController.forward();
        }
      }
    });
  }

  void _refreshTimestamp() {
    if (!mounted) return;
    setState(() {
      _timestampText = _formatTimestamp(_lastUpdated);
    });
  }

  // ── Sort / Filter ────────────────────────────────────────

  void _onSortChanged(FeedSort sort) {
    if (sort == _activeSort) return;
    HapticUtil.selection();
    _saveScrollPosition();
    setState(() => _activeSort = sort);
    ref.read(feedProvider.notifier).setSort(sort);
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: BaselineAnimation.medium,
        curve: BaselineMotion.curveEnter,
      );
    }
  }

  void _onFollowedToggle() {
    HapticUtil.selection();
    _saveScrollPosition();
    setState(() => _followedOnly = !_followedOnly);
    ref.read(feedProvider.notifier).setFilter(
      FeedFilter(followedOnly: _followedOnly),
    );
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: BaselineAnimation.medium,
        curve: BaselineMotion.curveEnter,
      );
    }
  }

  void _onNewBannerTap() {
    HapticUtil.light();
    setState(() => _showNewBanner = false);
    _onRefresh();
  }

  // ── Navigation ───────────────────────────────────────────

  void _onStatementTap(String statementId) {
    HapticUtil.medium();
    context.push(AppRoutes.statementPath(statementId));
  }

  void _onSearchTap() {
    HapticUtil.light();
    context.go(AppRoutes.explore);
  }

  void _onWordmarkTap() {
    if (!_scrollController.hasClients) return;
    HapticUtil.light();
    _scrollController.animateTo(
      0,
      duration: BaselineMotion.slow,
      curve: BaselineMotion.curveEnter,
    );
  }

  void _onStatementLongPress(FeedStatement statement) {
    HapticUtil.medium();
    PreviewOverlayTrigger.show(
      context: context,
      statementId: statement.statementId,
    );
  }

  void _onTrendingTopicTap(String topic) {
    HapticUtil.light();
    _saveScrollPosition();
    ref.read(feedProvider.notifier).setTopic(topic);
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: BaselineAnimation.medium,
        curve: BaselineMotion.curveEnter,
      );
    }
  }

  void _onCrossfireTeaserTap(CrossfirePair pair) {
    HapticUtil.medium();
    context.push(AppRoutes.crossfirePath(pair.id));
  }

  void _onDigestTap() {
    HapticUtil.light();
    context.go(AppRoutes.explore);
  }

  // ── Build ────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final feedState = ref.watch(feedProvider);

    return Scaffold(
      backgroundColor: BaselineColors.scaffoldBackground,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ──────────────────────────────
            _FeedHeader(
              onSearchTap: _onSearchTap,
              onWordmarkTap: _onWordmarkTap,
              timestampText: _timestampText,
              scanProgress: _headerScanController,
              ambientValue: _ambientController,
              reduceMotion: _reduceMotion,
            ),

            // ── Sort / Filter Bar ───────────────────
            _SortFilterBar(
              activeSort: _activeSort,
              followedOnly: _followedOnly,
              onSortChanged: _onSortChanged,
              onFollowedToggle: _onFollowedToggle,
              reduceMotion: _reduceMotion,
              totalCount: _statementCount,
            ),

            // ── Feature Ribbon ──────────────────────
            const FeatureRibbon(),

            // ── New Statements Banner ───────────────
            _NewStatementsBanner(
              visible: _showNewBanner,
              controller: _bannerController,
              onTap: _onNewBannerTap,
              reduceMotion: _reduceMotion,
            ),

            // ── Content ─────────────────────────────
            Expanded(
              child: Semantics(
                liveRegion: true,
                child: AnimatedSwitcher(
                  duration: BaselineAnimation.medium,
                  switchInCurve: BaselineMotion.curveEnter,
                  switchOutCurve: BaselineMotion.curveSettle,
                  child: _buildContent(feedState),
                ),
              ),
            ),

            // ── Ad Banner (Core tier only) ──────────
            const FeatureGate(
              feature: GatedFeature.adFree,
              invertGate: true,
              child: AdBanner(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(AsyncValue<FeedState> feedState) {
    return feedState.when(
      loading: () => Semantics(
        label: 'Loading feed',
        child: const _ShimmerFeed(key: ValueKey('shimmer')),
      ),
      error: (error, _) => _FeedError(
        key: const ValueKey('error'),
        message: error is FeedServiceException
            ? error.message
            : 'Unable to load feed. Please try again.',
        onRetry: () => ref.invalidate(feedProvider),
      ),
      data: (data) {
        if (data.statements.isEmpty) {
          return _buildEmptyStateWidget();
        }
        return _buildMixedFeedList(data);
      },
    );
  }

  Widget _buildEmptyStateWidget() {
    final message = _followedOnly ? kEmptyFollowed : kEmptyFeed;
    return RefreshIndicator(
      key: const ValueKey('empty'),
      onRefresh: _onRefresh,
      color: BaselineColors.teal,
      backgroundColor: BaselineColors.card,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          if (_trendingTopics.isNotEmpty)
            _TrendingTopicsStrip(
              topics: _trendingTopics,
              onTopicTap: _onTrendingTopicTap,
            ),
          const SizedBox(height: 120),
          EmptyStateWidget(message: message),
        ],
      ),
    );
  }

  Widget _buildMixedFeedList(FeedState data) {
    final items = _buildFeedItems(
      statements: data.statements,
      hasPartial: data.hasPartialFailure,
      isLoadingMore: data.isLoadingMore,
    );

    return RefreshIndicator(
      key: ValueKey('feed_${_activeSort.name}_$_followedOnly'),
      onRefresh: _onRefresh,
      color: BaselineColors.teal,
      backgroundColor: BaselineColors.card,
      child: ListView.builder(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: BaselineInsets.listPadding,
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          return _buildFeedItem(item);
        },
      ),
    );
  }

  /// Dispatches a feed item to its appropriate widget.
  /// AUDIT FIX A2-I2: Deterministic ValueKeys on all card widgets.
  Widget _buildFeedItem(_FeedItem item) {
    switch (item.kind) {
      case _FeedItemKind.partialFailure:
        return const Padding(
          key: ValueKey('partial_failure'),
          padding: EdgeInsets.only(bottom: BaselineSpacing.sm),
          child: PartialFailureBanner(),
        );

      case _FeedItemKind.trendingStrip:
        return _TrendingTopicsStrip(
          key: const ValueKey('trending_strip'),
          topics: _trendingTopics,
          onTopicTap: _onTrendingTopicTap,
        );

      case _FeedItemKind.dailyDigest:
        return _DailyDigestCard(
          key: const ValueKey('daily_digest'),
          digest: _dailyDigest!,
          onTap: _onDigestTap,
        );

      case _FeedItemKind.statement:
        final statement = item.statement!;
        return Padding(
          key: ValueKey('stmt_${statement.statementId}'),
          padding: const EdgeInsets.only(bottom: BaselineSpacing.sm),
          child: StatementCard(
            figureName: statement.figureName,
            figurePhotoUrl: statement.figurePhotoUrl,
            statementText: statement.statementText,
            sourceName: _extractSourceName(statement.sourceUrl),
            sourceUrl: statement.sourceUrl ?? '',
            statedAt: statement.statedAt,
            topics: statement.topics ?? const [],
            signalRank: statement.signalRank,
            isRevoked: false,
            staggerIndex: item.staggerIndex,
            statementIdShort: statement.statementId.length >= 8
                ? statement.statementId.substring(0, math.min(8, statement.statementId.length)).toUpperCase()
                : null,
            figureActivityLevel:
                statement.signalRank?.clamp(0.0, 1.0) ?? 0.0,
            onTap: () => _onStatementTap(statement.statementId),
            onLongPress: () => _onStatementLongPress(statement),
          ),
        );

      case _FeedItemKind.crossfireTeaser:
        final pair = item.crossfirePair!;
        return _CrossfireTeaserCard(
          key: ValueKey('xfire_${pair.id}'),
          pair: pair,
          onTap: () => _onCrossfireTeaserTap(pair),
        );

      case _FeedItemKind.driftAlert:
        final alert = item.driftAlert;
        if (alert == null) return const SizedBox.shrink();
        return FeedDriftCard(
          key: ValueKey('drift_${alert.billId}'),
          data: alert,
        );

      case _FeedItemKind.mutationAlert:
        final alert = item.mutationAlert;
        if (alert == null) return const SizedBox.shrink();
        return FeedMutationCard(
          key: ValueKey('mutation_${alert.billId}'),
          data: alert,
        );

      case _FeedItemKind.spendingAlert:
        final alert = item.spendingAlert;
        if (alert == null) return const SizedBox.shrink();
        return FeedSpendingCard(
          key: ValueKey('spending_${alert.billId}'),
          data: alert,
        );

      case _FeedItemKind.baselineSpike:
        final spike = item.baselineSpike;
        if (spike == null) return const SizedBox.shrink();
        return FeedBaselineSpikeCard(
          key: ValueKey('spike_${spike.figureId}'),
          data: spike,
        );

      case _FeedItemKind.voteAlert:
        final vote = item.voteAlert;
        if (vote == null) return const SizedBox.shrink();
        return FeedVoteAlertCard(
          key: ValueKey('vote_${vote.figureId}_${vote.billId}'),
          data: vote,
        );

      case _FeedItemKind.loadMore:
        return const _LoadMoreIndicator(
          key: ValueKey('load_more'),
        );
    }
  }
}

// ═══════════════════════════════════════════════════════════
// FEED HEADER (Intelligence Stream Command Bar)
// ═══════════════════════════════════════════════════════════

class _FeedHeader extends StatelessWidget {
  const _FeedHeader({
    required this.onSearchTap,
    required this.onWordmarkTap,
    required this.timestampText,
    required this.scanProgress,
    required this.ambientValue,
    required this.reduceMotion,
  });

  final VoidCallback onSearchTap;
  final VoidCallback onWordmarkTap;
  final String timestampText;
  final AnimationController scanProgress;
  final AnimationController ambientValue;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      // Static chrome: corners + ticks. Never repaints (I-20/I-73).
      painter: _HeaderStaticPainter(),
      child: AnimatedBuilder(
        animation: scanProgress,
        builder: (context, child) {
          final scanVal = reduceMotion ? 1.0 : scanProgress.value;
          return CustomPaint(
            painter: scanVal > 0.0 && scanVal < 1.0
                ? _HeaderDynamicPainter(scanProgress: scanVal)
                : null,
            child: child,
          );
        },
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(
            BaselineSpacing.xl,
            BaselineSpacing.sm,
            BaselineSpacing.md,
            BaselineSpacing.xs,
          ),
          color: BaselineColors.scaffoldBackground,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Semantics(
                      button: true,
                      label: 'Scroll to top',
                      child: GestureDetector(
                        onTap: onWordmarkTap,
                        behavior: HitTestBehavior.opaque,
                        child: SizedBox(
                          height: 22,
                          child: Image.asset(
                            'assets/images/baseline_wordmark.png',
                            fit: BoxFit.contain,
                            alignment: Alignment.centerLeft,
                          ),
                        ),
                      ),
                    ),
                  ),
                  AnimatedBuilder(
                    animation: ambientValue,
                    builder: (context, _) {
                      final opacity = reduceMotion
                          ? 0.5
                          : 0.3 + (ambientValue.value * 0.4);
                      return ExcludeSemantics(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 4,
                              height: 4,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: BaselineColors.teal
                                    .atOpacity(opacity),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'LIVE',
                              style: BaselineTypography.dataSmall.copyWith(
                                color: BaselineColors.teal
                                    .atOpacity(0.35),
                                letterSpacing: 1.5,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: BaselineSpacing.md),
                  Semantics(
                    button: true,
                    label: 'Search statements',
                    child: GestureDetector(
                      onTap: onSearchTap,
                      behavior: HitTestBehavior.opaque,
                      child: const SizedBox(
                        width: 44,
                        height: 44,
                        child: Center(
                          child: BaselineIcon(
                            BaselineIconType.search,
                            size: 24,
                            color: BaselineColors.teal,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (timestampText.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: ExcludeSemantics(
                    child: Text(
                      timestampText,
                      style: BaselineTypography.dataSmall.copyWith(
                        color: BaselineColors.textSecondary
                            .atOpacity(0.4),
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: BaselineSpacing.xs),
              ExcludeSemantics(
                child: Container(
                  height: 1,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        BaselineColors.teal
                            .atOpacity(BaselineOpacity.subtle),
                        BaselineColors.teal.atOpacity(0.0),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// FEED HEADER PAINTERS (static/dynamic split — I-20/I-73)
// ═══════════════════════════════════════════════════════════

/// Static chrome: corner dots + measurement ticks. Never repaints.
class _HeaderStaticPainter extends CustomPainter {
  _HeaderStaticPainter()
      : _tealPaint = Paint()
          ..color = BaselineColors.teal.atOpacity(0.06),
        _tickPaint = Paint()
          ..color = BaselineColors.teal.atOpacity(0.04)
          ..strokeWidth = 0.5;

  final Paint _tealPaint;
  final Paint _tickPaint;

  @override
  void paint(Canvas canvas, Size size) {
    const dotRadius = 1.0;
    const inset = 8.0;
    final corners = [
      Offset(inset, inset),
      Offset(size.width - inset, inset),
      Offset(inset, size.height - inset),
      Offset(size.width - inset, size.height - inset),
    ];
    for (final corner in corners) {
      canvas.drawCircle(corner, dotRadius, _tealPaint);
    }

    const tickSpacing = 24.0;
    const tickHeight = 3.0;
    for (var x = inset; x < size.width - inset; x += tickSpacing) {
      canvas.drawLine(
        Offset(x, size.height - 2),
        Offset(x, size.height - 2 - tickHeight),
        _tickPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

/// Dynamic chrome: entrance scan line only. Paint finals (I-71).
/// AUDIT FIX A2-I1: Math-based alpha fade replaces per-frame
/// ui.Gradient.linear allocation. Nulled from widget layer after
/// scan completes (progress >= 1.0), so zero post-entrance overhead.
class _HeaderDynamicPainter extends CustomPainter {
  _HeaderDynamicPainter({required this.scanProgress})
      : _scanPaint = Paint()..strokeWidth = 1.5;

  final double scanProgress;
  final Paint _scanPaint;

  @override
  void paint(Canvas canvas, Size size) {
    final scanX = size.width * scanProgress;
    const halfGlow = 40.0;

    // Draw glow bands with decreasing alpha (no shader allocation).
    // Core bright band.
    _scanPaint.color = BaselineColors.teal.atOpacity(0.15);
    canvas.drawRect(
      Rect.fromCenter(
        center: Offset(scanX, size.height / 2),
        width: 6,
        height: size.height,
      ),
      _scanPaint,
    );

    // Mid glow.
    _scanPaint.color = BaselineColors.teal.atOpacity(0.06);
    canvas.drawRect(
      Rect.fromCenter(
        center: Offset(scanX, size.height / 2),
        width: halfGlow,
        height: size.height,
      ),
      _scanPaint,
    );

    // Outer haze.
    _scanPaint.color = BaselineColors.teal.atOpacity(0.02);
    canvas.drawRect(
      Rect.fromCenter(
        center: Offset(scanX, size.height / 2),
        width: halfGlow * 2,
        height: size.height,
      ),
      _scanPaint,
    );
  }

  @override
  bool shouldRepaint(_HeaderDynamicPainter old) =>
      scanProgress != old.scanProgress;
}

// ═══════════════════════════════════════════════════════════
// SORT / FILTER BAR
// ═══════════════════════════════════════════════════════════

class _SortFilterBar extends StatelessWidget {
  const _SortFilterBar({
    required this.activeSort,
    required this.followedOnly,
    required this.onSortChanged,
    required this.onFollowedToggle,
    required this.reduceMotion,
    this.totalCount = 0,
  });

  final FeedSort activeSort;
  final bool followedOnly;
  final ValueChanged<FeedSort> onSortChanged;
  final VoidCallback onFollowedToggle;
  final bool reduceMotion;
  final int totalCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 44,
      padding: const EdgeInsets.symmetric(
        horizontal: BaselineSpacing.xl,
      ),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                children: [
                  for (final entry in _kSortLabels.entries) ...[
                    if (entry.key != _kSortLabels.keys.first)
                      _HashSeparator(),
                    _SortPill(
                      label: entry.value,
                      isActive: activeSort == entry.key,
                      onTap: () => onSortChanged(entry.key),
                      reduceMotion: reduceMotion,
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(width: BaselineSpacing.sm),
          Container(
            width: 1,
            height: 16,
            color: BaselineColors.teal.atOpacity(
              BaselineOpacity.faint,
            ),
          ),
          const SizedBox(width: BaselineSpacing.sm),
          _FilterPill(
            label: 'FOLLOWED',
            isActive: followedOnly,
            onTap: onFollowedToggle,
            reduceMotion: reduceMotion,
          ),
          // Cherry: feed depth counter mono readout.
          if (totalCount > 0) ...[
            const SizedBox(width: BaselineSpacing.sm),
            ExcludeSemantics(
              child: Text(
                '$totalCount',
                style: BaselineTypography.dataSmall.copyWith(
                  color: BaselineColors.textSecondary
                      .atOpacity(0.25),
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SortPill extends StatefulWidget {
  const _SortPill({
    required this.label,
    required this.isActive,
    required this.onTap,
    required this.reduceMotion,
  });

  final String label;
  final bool isActive;
  final VoidCallback onTap;
  final bool reduceMotion;

  @override
  State<_SortPill> createState() => _SortPillState();
}

class _SortPillState extends State<_SortPill> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final scale = _pressed && !widget.reduceMotion
        ? BaselineMotion.pressScaleChip
        : 1.0;

    // AUDIT FIX A2-C3: excludeSemantics prevents double-read (I-64).
    return Semantics(
      button: true,
      excludeSemantics: true,
      label: '${widget.label} sort${widget.isActive ? ', active' : ''}',
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        child: AnimatedScale(
          scale: scale,
          duration: BaselineAnimation.fast,
          curve: BaselineMotion.curveSettle,
          child: AnimatedContainer(
            duration: BaselineAnimation.fast,
            curve: BaselineMotion.curveSettle,
            padding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 6,
            ),
            decoration: BoxDecoration(
              border: Border.all(
                color: widget.isActive
                    ? BaselineColors.teal
                        .atOpacity(BaselineOpacity.moderate)
                    : BaselineColors.teal
                        .atOpacity(BaselineOpacity.ghost),
                width: widget.isActive ? 1.5 : 1.0,
              ),
              borderRadius: BorderRadius.circular(BaselineRadius.sm),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.label,
                  style: BaselineTypography.dataSmall.copyWith(
                    color: widget.isActive
                        ? BaselineColors.teal
                        : BaselineColors.textSecondary
                            .atOpacity(0.5),
                    letterSpacing: 1.2,
                    fontWeight: widget.isActive
                        ? FontWeight.w600
                        : FontWeight.w400,
                  ),
                ),
                // Signal strength dots: 3 ascending dots on active pill.
                if (widget.isActive) ...[
                  const SizedBox(width: 6),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: List.generate(3, (i) {
                      final dotSize = 2.0 + i * 0.5;
                      return Padding(
                        padding: const EdgeInsets.only(left: 1.5),
                        child: Container(
                          width: dotSize,
                          height: dotSize,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: BaselineColors.teal
                                .atOpacity(0.3 + (i * 0.15)),
                          ),
                        ),
                      );
                    }),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FilterPill extends StatefulWidget {
  const _FilterPill({
    required this.label,
    required this.isActive,
    required this.onTap,
    required this.reduceMotion,
  });

  final String label;
  final bool isActive;
  final VoidCallback onTap;
  final bool reduceMotion;

  @override
  State<_FilterPill> createState() => _FilterPillState();
}

class _FilterPillState extends State<_FilterPill> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final scale = _pressed && !widget.reduceMotion
        ? BaselineMotion.pressScaleChip
        : 1.0;

    // AUDIT FIX A2-C3: excludeSemantics prevents double-read (I-64).
    return Semantics(
      button: true,
      excludeSemantics: true,
      toggled: widget.isActive,
      label: 'Filter by followed figures',
      child: GestureDetector(
        onTap: widget.onTap,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        behavior: HitTestBehavior.opaque,
        child: AnimatedScale(
          scale: scale,
          duration: BaselineAnimation.fast,
          curve: BaselineMotion.curveSettle,
          child: AnimatedContainer(
            duration: BaselineAnimation.fast,
            curve: BaselineMotion.curveSettle,
            padding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 6,
            ),
            decoration: BoxDecoration(
              color: widget.isActive
                  ? BaselineColors.teal
                      .atOpacity(BaselineOpacity.ghost)
                  : Colors.transparent,
              border: Border.all(
                color: widget.isActive
                    ? BaselineColors.teal
                        .atOpacity(BaselineOpacity.muted)
                    : BaselineColors.teal
                        .atOpacity(BaselineOpacity.ghost),
                width: widget.isActive ? 1.5 : 1.0,
              ),
              borderRadius: BorderRadius.circular(BaselineRadius.sm),
            ),
            child: Text(
              widget.label,
              style: BaselineTypography.dataSmall.copyWith(
                color: widget.isActive
                    ? BaselineColors.teal
                    : BaselineColors.textSecondary
                        .atOpacity(0.4),
                letterSpacing: 1.2,
                fontWeight: widget.isActive
                    ? FontWeight.w600
                    : FontWeight.w400,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HashSeparator extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Container(
        width: 1,
        height: 8,
        color: BaselineColors.teal.atOpacity(
          BaselineOpacity.ghost,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// NEW STATEMENTS BANNER (150.19)
// ═══════════════════════════════════════════════════════════

class _NewStatementsBanner extends StatelessWidget {
  const _NewStatementsBanner({
    required this.visible,
    required this.controller,
    required this.onTap,
    required this.reduceMotion,
  });

  final bool visible;
  final AnimationController controller;
  final VoidCallback onTap;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    if (!visible && (reduceMotion || controller.isDismissed)) {
      return const SizedBox.shrink();
    }

    return SizeTransition(
      sizeFactor: reduceMotion
          ? AlwaysStoppedAnimation(visible ? 1.0 : 0.0)
          : CurvedAnimation(
              parent: controller,
              curve: BaselineMotion.curveEnter,
            ),
      axisAlignment: -1.0,
      // AUDIT FIX A2-C3: excludeSemantics prevents double-read (I-64).
      child: Semantics(
        button: true,
        excludeSemantics: true,
        label: 'New statements available. Tap to refresh.',
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
              horizontal: BaselineSpacing.xl,
              vertical: BaselineSpacing.xs,
            ),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: BaselineColors.teal
                      .atOpacity(BaselineOpacity.subtle),
                  width: 1,
                ),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: BaselineColors.teal
                        .atOpacity(BaselineOpacity.prominent),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'NEW SIGNALS INCOMING',
                  style: BaselineTypography.dataSmall.copyWith(
                    color: BaselineColors.teal
                        .atOpacity(BaselineOpacity.moderate),
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(width: 8),
                BaselineIcon(
                  BaselineIconType.arrowUpward,
                  size: 16,
                  color: BaselineColors.teal
                      .atOpacity(BaselineOpacity.muted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// V2: TRENDING TOPICS STRIP (P5 RPC)
// ═══════════════════════════════════════════════════════════

class _TrendingTopicsStrip extends StatelessWidget {
  const _TrendingTopicsStrip({
    super.key,
    required this.topics,
    required this.onTopicTap,
  });

  final List<_TrendingTopicData> topics;
  final ValueChanged<String> onTopicTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: BaselineSpacing.md),
      child: CustomPaint(
        painter: _TrendingStripPainter(),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: BaselineSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(
                  left: BaselineSpacing.xl,
                  bottom: BaselineSpacing.xs,
                ),
                child: Row(
                  children: [
                    ExcludeSemantics(
                      child: CustomPaint(
                        size: const Size(8, 10),
                        painter: _ReticleBracketPainter(openEnd: true),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'ACTIVE TOPICS',
                      style: BaselineTypography.dataSmall.copyWith(
                        color: BaselineColors.teal
                            .atOpacity(0.35),
                        letterSpacing: 1.8,
                      ),
                    ),
                    const SizedBox(width: 6),
                    ExcludeSemantics(
                      child: CustomPaint(
                        size: const Size(8, 10),
                        painter: _ReticleBracketPainter(openEnd: false),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 36,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(
                    horizontal: BaselineSpacing.xl,
                  ),
                  itemCount: topics.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(width: BaselineSpacing.xs),
                  itemBuilder: (context, index) {
                    final topic = topics[index];
                    return _TrendingChip(
                      topic: topic,
                      onTap: () => onTopicTap(topic.topic),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrendingChip extends StatefulWidget {
  const _TrendingChip({
    required this.topic,
    required this.onTap,
  });

  final _TrendingTopicData topic;
  final VoidCallback onTap;

  @override
  State<_TrendingChip> createState() => _TrendingChipState();
}

class _TrendingChipState extends State<_TrendingChip> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    // AUDIT FIX A2-C3: excludeSemantics prevents double-read (I-64).
    return Semantics(
      button: true,
      excludeSemantics: true,
      label: '${_topicDisplayName(widget.topic.topic)}, '
          '${widget.topic.statementCount} statements, '
          'trend ${widget.topic.trend}',
      child: GestureDetector(
        onTap: () {
          HapticUtil.light();
          widget.onTap();
        },
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        behavior: HitTestBehavior.opaque,
        child: AnimatedScale(
          scale: _pressed ? BaselineMotion.pressScaleChip : 1.0,
          duration: BaselineAnimation.fast,
          curve: BaselineMotion.curveSettle,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 6,
            ),
            decoration: BoxDecoration(
              border: Border.all(
                color: BaselineColors.teal
                    .atOpacity(BaselineOpacity.ghost),
                width: 1,
              ),
              borderRadius: BorderRadius.circular(BaselineRadius.sm),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Cherry: faint teal pulse dot for rising topics.
                if (widget.topic.trend == 'rising') ...[
                  Container(
                    width: 4,
                    height: 4,
                    margin: const EdgeInsets.only(right: 6),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: BaselineColors.teal
                          .atOpacity(0.35),
                    ),
                  ),
                ],
                Text(
                  _topicDisplayName(widget.topic.topic),
                  style: BaselineTypography.dataSmall.copyWith(
                    color: BaselineColors.textSecondary
                        .atOpacity(0.6),
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  widget.topic.trendArrow,
                  style: BaselineTypography.dataSmall.copyWith(
                    color: widget.topic.trend == 'rising'
                        ? BaselineColors.teal
                            .atOpacity(0.6)
                        : BaselineColors.textSecondary
                            .atOpacity(0.3),
                    fontSize: 10,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  '${widget.topic.statementCount}',
                  style: BaselineTypography.dataSmall.copyWith(
                    color: BaselineColors.textSecondary
                        .atOpacity(0.3),
                    fontSize: 8,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Faint horizontal scan lines behind the trending strip.
class _TrendingStripPainter extends CustomPainter {
  _TrendingStripPainter()
      : _linePaint = Paint()
          ..color = BaselineColors.teal.atOpacity(0.02)
          ..strokeWidth = 0.5;

  final Paint _linePaint;

  @override
  void paint(Canvas canvas, Size size) {
    for (var y = 0.0; y < size.height; y += 4) {
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        _linePaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

/// Reticle bracket [ or ] for label framing.
class _ReticleBracketPainter extends CustomPainter {
  _ReticleBracketPainter({required this.openEnd})
      : _paint = Paint()
          ..color = BaselineColors.teal.atOpacity(0.15)
          ..strokeWidth = 1.0
          ..style = PaintingStyle.stroke;

  final bool openEnd;
  final Paint _paint;

  @override
  void paint(Canvas canvas, Size size) {
    if (openEnd) {
      canvas.drawLine(
        Offset(size.width, 0),
        const Offset(0, 0),
        _paint,
      );
      canvas.drawLine(
        const Offset(0, 0),
        Offset(0, size.height),
        _paint,
      );
      canvas.drawLine(
        Offset(0, size.height),
        Offset(size.width, size.height),
        _paint,
      );
    } else {
      canvas.drawLine(
        const Offset(0, 0),
        Offset(size.width, 0),
        _paint,
      );
      canvas.drawLine(
        Offset(size.width, 0),
        Offset(size.width, size.height),
        _paint,
      );
      canvas.drawLine(
        Offset(size.width, size.height),
        Offset(0, size.height),
        _paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

// ═══════════════════════════════════════════════════════════
// V2: DAILY DIGEST CARD (Intel Briefing)
// ═══════════════════════════════════════════════════════════

class _DailyDigestCard extends StatefulWidget {
  const _DailyDigestCard({
    super.key,
    required this.digest,
    required this.onTap,
  });

  final _DailyDigest digest;
  final VoidCallback onTap;

  @override
  State<_DailyDigestCard> createState() => _DailyDigestCardState();
}

class _DailyDigestCardState extends State<_DailyDigestCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: BaselineSpacing.md),
      // AUDIT FIX A2-C3: excludeSemantics prevents double-read (I-64).
      child: Semantics(
        button: true,
        excludeSemantics: true,
        label: 'Daily briefing: ${widget.digest.figureCount} figures '
            'measured, ${widget.digest.statementCount} statements analyzed',
        child: GestureDetector(
          onTap: widget.onTap,
          onTapDown: (_) => setState(() => _pressed = true),
          onTapUp: (_) => setState(() => _pressed = false),
          onTapCancel: () => setState(() => _pressed = false),
          behavior: HitTestBehavior.opaque,
          child: AnimatedScale(
            scale: _pressed ? BaselineMotion.pressScaleCard : 1.0,
            duration: BaselineAnimation.fast,
            curve: BaselineMotion.curveSettle,
            child: CustomPaint(
              painter: _DigestCardPainter(),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(BaselineSpacing.md),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: BaselineColors.teal
                        .atOpacity(BaselineOpacity.ghost),
                    width: 1,
                  ),
                  borderRadius: BorderRadius.circular(BaselineRadius.md),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 4,
                          height: 4,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: BaselineColors.teal
                                .atOpacity(0.4),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'DAILY BRIEFING',
                          style: BaselineTypography.dataSmall.copyWith(
                            color: BaselineColors.teal
                                .atOpacity(0.4),
                            letterSpacing: 2.0,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          _todayLabel(),
                          style: BaselineTypography.dataSmall.copyWith(
                            color: BaselineColors.textSecondary
                                .atOpacity(0.25),
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: BaselineSpacing.sm),
                    Row(
                      children: [
                        _DigestMetric(
                          value: '${widget.digest.figureCount}',
                          label: 'FIGURES',
                        ),
                        const SizedBox(width: BaselineSpacing.lg),
                        _DigestMetric(
                          value: '${widget.digest.statementCount}',
                          label: 'STATEMENTS',
                        ),
                      ],
                    ),
                    if (widget.digest.hasHighlight) ...[
                      const SizedBox(height: BaselineSpacing.sm),
                      Container(
                        height: 1,
                        color: BaselineColors.teal
                            .atOpacity(0.04),
                      ),
                      const SizedBox(height: BaselineSpacing.sm),
                      Row(
                        children: [
                          Text(
                            'HIGHEST SIGNAL',
                            style: BaselineTypography.dataSmall.copyWith(
                              color: BaselineColors.teal
                                  .atOpacity(0.3),
                              letterSpacing: 1.2,
                              fontSize: 8,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${widget.digest.topDivergenceFigure}'
                              ' on ${widget.digest.topDivergenceTopic}',
                              style: BaselineTypography.body2.copyWith(
                                color: BaselineColors.textPrimary
                                    .atOpacity(0.7),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _todayLabel() {
    final now = DateTime.now();
    final months = [
      'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
      'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC',
    ];
    return '${now.day} ${months[now.month - 1]} ${now.year}';
  }
}

class _DigestMetric extends StatelessWidget {
  const _DigestMetric({
    required this.value,
    required this.label,
  });

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: BaselineTypography.h2.copyWith(
            color: BaselineColors.teal,
            fontFamily: BaselineTypography.monoFontFamily,
            fontSize: 20,
          ),
        ),
        Text(
          label,
          style: BaselineTypography.dataSmall.copyWith(
            color: BaselineColors.textSecondary
                .atOpacity(0.3),
            letterSpacing: 1.5,
            fontSize: 8,
          ),
        ),
      ],
    );
  }
}

/// Intel dot grid background + circuit trace cherry.
class _DigestCardPainter extends CustomPainter {
  _DigestCardPainter()
      : _dotPaint = Paint()
          ..color = BaselineColors.teal.atOpacity(0.02),
        _tracePaint = Paint()
          ..color = BaselineColors.teal.atOpacity(0.03)
          ..strokeWidth = 0.5
          ..style = PaintingStyle.stroke;

  final Paint _dotPaint;
  final Paint _tracePaint;

  @override
  void paint(Canvas canvas, Size size) {
    const spacing = 12.0;
    const radius = 0.5;
    for (var x = spacing; x < size.width; x += spacing) {
      for (var y = spacing; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), radius, _dotPaint);
      }
    }

    // Cherry: circuit trace connecting metric column positions.
    final busY = size.height * 0.6;
    canvas.drawLine(
      Offset(size.width * 0.15, busY),
      Offset(size.width * 0.85, busY),
      _tracePaint,
    );
    for (final pct in [0.25, 0.5, 0.75]) {
      final x = size.width * pct;
      canvas.drawLine(
        Offset(x, busY - 6),
        Offset(x, busY + 6),
        _tracePaint,
      );
      canvas.drawCircle(Offset(x, busY - 6), 1, _dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

// ═══════════════════════════════════════════════════════════
// V2: CROSSFIRE™ TEASER CARD (Inline Feed)
// ═══════════════════════════════════════════════════════════

class _CrossfireTeaserCard extends StatefulWidget {
  const _CrossfireTeaserCard({
    super.key,
    required this.pair,
    required this.onTap,
  });

  final CrossfirePair pair;
  final VoidCallback onTap;

  @override
  State<_CrossfireTeaserCard> createState() => _CrossfireTeaserCardState();
}

class _CrossfireTeaserCardState extends State<_CrossfireTeaserCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: BaselineSpacing.sm),
      child: FeatureGate(
        feature: GatedFeature.crossfire,
        fallback: _buildBlurredTeaser(),
        // AUDIT FIX A2-C3: excludeSemantics prevents double-read (I-64).
        child: Semantics(
          button: true,
          excludeSemantics: true,
          label: 'Crossfire comparison: '
              '${widget.pair.figureNameA} vs '
              '${widget.pair.figureNameB} on '
              '${_topicDisplayName(widget.pair.sharedTopic)}',
          child: GestureDetector(
            onTap: () {
              HapticUtil.medium();
              widget.onTap();
            },
            onTapDown: (_) => setState(() => _pressed = true),
            onTapUp: (_) => setState(() => _pressed = false),
            onTapCancel: () => setState(() => _pressed = false),
            behavior: HitTestBehavior.opaque,
            child: AnimatedScale(
              scale: _pressed ? BaselineMotion.pressScaleCard : 1.0,
              duration: BaselineAnimation.fast,
              curve: BaselineMotion.curveSettle,
              child: CustomPaint(
                painter: _CrossfireTeaserPainter(),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: BaselineSpacing.md,
                    vertical: BaselineSpacing.sm,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: BaselineColors.teal
                          .atOpacity(BaselineOpacity.ghost),
                      width: 1,
                    ),
                    borderRadius:
                        BorderRadius.circular(BaselineRadius.md),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Text(
                            'CROSSFIRE\u2122',
                            style:
                                BaselineTypography.dataSmall.copyWith(
                              color: BaselineColors.teal
                                  .atOpacity(0.35),
                              letterSpacing: 2.0,
                              fontSize: 8,
                            ),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: BaselineColors.teal
                                    .atOpacity(0.08),
                              ),
                              borderRadius: BorderRadius.circular(
                                BaselineRadius.sm,
                              ),
                            ),
                            child: Text(
                              _topicDisplayName(
                                  widget.pair.sharedTopic),
                              style: BaselineTypography.dataSmall
                                  .copyWith(
                                color: BaselineColors.textSecondary
                                    .atOpacity(0.4),
                                fontSize: 8,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: BaselineSpacing.sm),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              widget.pair.figureNameA,
                              style: BaselineTypography.body2.copyWith(
                                color: BaselineColors.textPrimary
                                    .atOpacity(0.8),
                                fontWeight: FontWeight.w500,
                              ),
                              textAlign: TextAlign.right,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: BaselineSpacing.sm,
                            ),
                            child: Column(
                              children: [
                                Container(
                                  width: 1,
                                  height: 8,
                                  color: BaselineColors.teal
                                      .atOpacity(0.15),
                                ),
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: BaselineColors.teal
                                          .atOpacity(0.3),
                                      width: 1,
                                    ),
                                  ),
                                ),
                                Container(
                                  width: 1,
                                  height: 8,
                                  color: BaselineColors.teal
                                      .atOpacity(0.15),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: Text(
                              widget.pair.figureNameB,
                              style: BaselineTypography.body2.copyWith(
                                color: BaselineColors.textPrimary
                                    .atOpacity(0.8),
                                fontWeight: FontWeight.w500,
                              ),
                              textAlign: TextAlign.left,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: BaselineSpacing.xs),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'DELTA',
                            style:
                                BaselineTypography.dataSmall.copyWith(
                              color: BaselineColors.textSecondary
                                  .atOpacity(0.25),
                              letterSpacing: 1.5,
                              fontSize: 7,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            widget.pair.deltaDisplay,
                            style: BaselineTypography.data.copyWith(
                              color: widget.pair
                                          .consensusDelta.abs() >
                                      0.15
                                  ? BaselineColors.amber
                                  : BaselineColors.teal
                                      .atOpacity(0.6),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 8),
                          BaselineIcon(
                            BaselineIconType.arrowForward,
                            size: 16,
                            color: BaselineColors.teal
                                .atOpacity(0.25),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBlurredTeaser() {
    return Container(
      width: double.infinity,
      height: 80,
      margin: const EdgeInsets.only(bottom: BaselineSpacing.sm),
      decoration: BoxDecoration(
        border: Border.all(
          color: BaselineColors.teal
              .atOpacity(BaselineOpacity.ghost),
          width: 1,
        ),
        borderRadius: BorderRadius.circular(BaselineRadius.md),
      ),
      child: Center(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            BaselineIcon(
              BaselineIconType.lock,
              size: 16,
              color: BaselineColors.textSecondary
                  .atOpacity(0.25),
            ),
            const SizedBox(width: 8),
            Text(
              'CROSSFIRE\u2122 COMPARISON',
              style: BaselineTypography.dataSmall.copyWith(
                color: BaselineColors.textSecondary
                    .atOpacity(0.25),
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Reticle corner brackets on Crossfire teaser.
class _CrossfireTeaserPainter extends CustomPainter {
  _CrossfireTeaserPainter()
      : _paint = Paint()
          ..color = BaselineColors.teal.atOpacity(0.06)
          ..strokeWidth = 1.0
          ..style = PaintingStyle.stroke;

  final Paint _paint;

  @override
  void paint(Canvas canvas, Size size) {
    const arm = 10.0;
    const inset = 4.0;

    canvas.drawLine(
      Offset(inset, inset + arm),
      Offset(inset, inset),
      _paint,
    );
    canvas.drawLine(
      Offset(inset, inset),
      Offset(inset + arm, inset),
      _paint,
    );

    canvas.drawLine(
      Offset(size.width - inset - arm, inset),
      Offset(size.width - inset, inset),
      _paint,
    );
    canvas.drawLine(
      Offset(size.width - inset, inset),
      Offset(size.width - inset, inset + arm),
      _paint,
    );

    canvas.drawLine(
      Offset(inset, size.height - inset - arm),
      Offset(inset, size.height - inset),
      _paint,
    );
    canvas.drawLine(
      Offset(inset, size.height - inset),
      Offset(inset + arm, size.height - inset),
      _paint,
    );

    canvas.drawLine(
      Offset(size.width - inset - arm, size.height - inset),
      Offset(size.width - inset, size.height - inset),
      _paint,
    );
    canvas.drawLine(
      Offset(size.width - inset, size.height - inset),
      Offset(size.width - inset, size.height - inset - arm),
      _paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

// ═══════════════════════════════════════════════════════════
// SHIMMER FEED (initial loading state)
// ═══════════════════════════════════════════════════════════

class _ShimmerFeed extends StatelessWidget {
  const _ShimmerFeed({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: BaselineInsets.listPadding,
      child: ShimmerFeedList(count: _kShimmerCount),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// ERROR STATE
// ═══════════════════════════════════════════════════════════

class _FeedError extends StatelessWidget {
  const _FeedError({
    super.key,
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: BaselineInsets.screenH,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            BaselineIcon(
              BaselineIconType.cloudOff,
              size: 48,
              color: BaselineColors.textSecondary
                  .atOpacity(BaselineOpacity.prominent),
            ),
            const SizedBox(height: BaselineSpacing.md),
            Text(
              message,
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: BaselineTypography.body1.copyWith(
                color: BaselineColors.textSecondary,
              ),
            ),
            const SizedBox(height: BaselineSpacing.lg),
            _RetryButton(onTap: onRetry),
          ],
        ),
      ),
    );
  }
}

class _RetryButton extends StatefulWidget {
  const _RetryButton({required this.onTap});
  final VoidCallback onTap;

  @override
  State<_RetryButton> createState() => _RetryButtonState();
}

class _RetryButtonState extends State<_RetryButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Retry loading feed',
      child: GestureDetector(
        onTap: () {
          HapticUtil.light();
          widget.onTap();
        },
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        behavior: HitTestBehavior.opaque,
        child: AnimatedScale(
          scale: _pressed
              ? BaselineMotion.pressScaleButton
              : 1.0,
          duration: BaselineAnimation.fast,
          curve: BaselineMotion.curveSettle,
          child: Container(
            height: 48,
            padding: const EdgeInsets.symmetric(
              horizontal: BaselineSpacing.xl,
            ),
            decoration: BoxDecoration(
              border: Border.all(
                color: BaselineColors.teal,
                width: 2,
              ),
              borderRadius: BorderRadius.circular(24),
            ),
            alignment: Alignment.center,
            child: Text(
              'TRY AGAIN',
              style: BaselineTypography.dataSmall.copyWith(
                color: BaselineColors.teal,
                letterSpacing: 1.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// LOAD MORE INDICATOR
// ═══════════════════════════════════════════════════════════

class _LoadMoreIndicator extends StatefulWidget {
  const _LoadMoreIndicator({super.key});

  @override
  State<_LoadMoreIndicator> createState() => _LoadMoreIndicatorState();
}

class _LoadMoreIndicatorState extends State<_LoadMoreIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.stop();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (reduceMotion) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: BaselineSpacing.lg),
        child: Center(
          child: Text(
            'LOADING',
            style: TextStyle(
              fontFamily: BaselineTypography.monoFontFamily,
              fontSize: 9,
              color: BaselineColors.teal,
              letterSpacing: 2.0,
            ),
          ),
        ),
      );
    }

    return Semantics(
      label: 'Loading more items',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: BaselineSpacing.lg),
        child: ExcludeSemantics(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              return CustomPaint(
                size: const Size(double.infinity, 3),
                painter: _ScanBeamPainter(
                  progress: _controller.value,
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// AUDIT FIX A2-I1: Math-based alpha bands replace per-frame
/// ui.Gradient.linear allocation. Eliminates shader GC pressure
/// during indefinite load-more animation.
class _ScanBeamPainter extends CustomPainter {
  _ScanBeamPainter({required this.progress})
      : _trackPaint = Paint()
          ..color = BaselineColors.teal.atOpacity(0.04)
          ..strokeWidth = 1,
        _dotPaint = Paint()
          ..color = BaselineColors.teal.atOpacity(0.4),
        _beamPaint = Paint()..strokeWidth = 2;

  final double progress;
  final Paint _trackPaint;
  final Paint _dotPaint;
  final Paint _beamPaint;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;

    // Track line.
    canvas.drawLine(Offset(0, y), Offset(size.width, y), _trackPaint);

    // Beam glow: 3 concentric alpha bands (no shader).
    final beamX = size.width * progress;

    // Outer haze.
    _beamPaint.color = BaselineColors.teal.atOpacity(0.04);
    canvas.drawLine(
      Offset(beamX - 60, y),
      Offset(beamX + 60, y),
      _beamPaint,
    );

    // Mid glow.
    _beamPaint.color = BaselineColors.teal.atOpacity(0.12);
    canvas.drawLine(
      Offset(beamX - 20, y),
      Offset(beamX + 20, y),
      _beamPaint,
    );

    // Core bright.
    _beamPaint.color = BaselineColors.teal.atOpacity(0.25);
    canvas.drawLine(
      Offset(beamX - 4, y),
      Offset(beamX + 4, y),
      _beamPaint,
    );

    // Dot.
    canvas.drawCircle(Offset(beamX, y), 1.5, _dotPaint);
  }

  @override
  bool shouldRepaint(_ScanBeamPainter old) => progress != old.progress;
}
