/// FE-4a: Crossfire™ Screen (Adversarial Comparison Chamber)
///
/// Full analysis screen for Crossfire™ side-by-side figure comparisons.
/// Two political figures who spoke on the same topic within 72 hours,
/// each independently scored by multiple AI systems, placed into a
/// classified intelligence comparison format.
///
/// VISUAL STORY: Adversarial Comparison Chamber
/// Two subjects face-to-face. Central convergence spine = arbitration axis.
/// Reticle brackets frame the confrontation. Divergence bridge =
/// cross-examination table. Delta orb = the verdict.
///
/// WHAT MAKES THIS UNIQUE: Only TM screen built around CONFRONTATION.
/// Opposing force-field gradients, collision sparks, verdict seals,
/// evidence exhibit stamps. Every visual reinforces adversarial tension.
///
/// CONTROLLERS: 5 (entrance, scanline, barGrow, ambient, particle)
/// PAINTERS: 10 (_ScreenChrome, _HeaderChrome, _TemporalTimeline,
///   _ComparisonFrame, _ConvergenceSpine, _DeltaOrb, _BridgeBars,
///   _CrossExamRuler, _VerdictFlash, _VerdictSeal)
///
/// Pro-gated via FeatureGate(feature: GatedFeature.crossfire).
///
/// Path: lib/screens/crossfire_screen.dart
library;

// 1. Dart SDK
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

// 2. Flutter
import 'package:flutter/material.dart';

// 3. Third-party
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

// 4. Config
import 'package:baseline_app/config/constants.dart';
import 'package:baseline_app/config/theme.dart';
import 'package:baseline_app/config/tier_feature_map.dart';
import 'package:baseline_app/config/routes.dart';

// 5. Models / Services / Providers
import 'package:baseline_app/models/feed_statement.dart';
import 'package:baseline_app/services/feed_service.dart';
import 'package:baseline_app/utils/haptic_util.dart';
import 'package:baseline_app/utils/export_util.dart';
import 'package:baseline_app/utils/baseline_system_ui.dart';

// 6. Widgets
import 'package:baseline_app/widgets/baseline_icons.dart';
import 'package:baseline_app/widgets/crossfire_round_card.dart';
import 'package:baseline_app/widgets/empty_state.dart';
import 'package:baseline_app/widgets/shimmer_loading.dart';
import 'package:baseline_app/widgets/feature_gate.dart';
import 'package:baseline_app/widgets/info_bottom_sheet.dart';
import 'package:baseline_app/widgets/rate_app_popup.dart';
import 'package:baseline_app/widgets/soft_paywall_popup.dart';
import 'package:baseline_app/utils/rate_app_trigger.dart';

// ═══════════════════════════════════════════════════════════
// CONSTANTS
// ═══════════════════════════════════════════════════════════

/// 72-hour pairing window.
const Duration _kPairingWindow = Duration(hours: 72);

/// Central spine width.
const double _kSpineWidth = 1.0;

/// Spine junction node radius.
const double _kSpineJunctionRadius = 3.0;

/// Spine data-flow particle count.
const int _kSpineParticleCount = 5;

/// Divergence threshold: metric gap > 15 points = amber bridge line.
/// Values are 0-100 scale (from consensus table NUMERIC(5,2) CHECK 0..100).
const double _kDivergenceThreshold = 15;

/// Card gap (between the two round cards: spine lives here).
const double _kCardGap = 12.0;

/// Reticle bracket arm length (comparison frame).
const double _kReticleArm = 14.0;

/// Reticle inset from frame edge.
const double _kReticleInset = 4.0;

/// Film sprocket dimensions.
const double _kSprocketWidth = 5.0;
const double _kSprocketHeight = 3.0;
const double _kSprocketSpacing = 12.0;

/// Intel dot grid.
const double _kDotGridSpacing = 16.0;
const double _kDotGridRadius = 0.5;

/// Delta orb size.
const double _kDeltaOrbSize = 56.0;
const double _kDeltaRingStroke = 3.0;

/// Verdict seal outer ring.
const double _kVerdictSealRadius = 36.0;
const double _kVerdictSealStroke = 1.0;

/// Temporal timeline marker radius.
const double _kTimelineMarkerRadius = 4.0;
const double _kTimelinePulseRadius = 7.0;

/// Temporal pulse traveler radius.
const double _kTravelerRadius = 2.0;

/// Proximity wire dash length.
const double _kProximityDashLength = 4.0;
const double _kProximityDashGap = 3.0;

/// Entrance master duration.
const Duration _kEntranceDuration = Duration(milliseconds: 1200);

/// Scanline duration.
const Duration _kScanlineDuration = Duration(milliseconds: 800);

/// Bar growth duration (bridge rows cascade).
const Duration _kBarGrowDuration = Duration(milliseconds: 600);

/// Ambient breathing cycle.
const Duration _kAmbientDuration = Duration(milliseconds: 4000);

/// Spine particle travel duration.
const Duration _kParticleDuration = Duration(milliseconds: 2400);

/// 5-phase entrance stagger intervals.
const double _kPhase1Start = 0.10;  // Header + classification
const double _kPhase1End = 0.35;
const double _kPhase2Start = 0.25;  // Cards materialize
const double _kPhase2End = 0.55;
const double _kPhase3Start = 0.45;  // Bridge rows
const double _kPhase3End = 0.75;
const double _kPhase4Start = 0.65;  // Delta orb + verdict
const double _kPhase4End = 0.90;
const double _kPhase5Start = 0.80;  // Nav dots + footer
const double _kPhase5End = 1.0;

/// Bridge row stagger offset per row (ms).
const int _kBridgeRowStaggerMs = 30;

/// Classification dot size.
const double _kClassDotSize = 4.0;

/// Max pairs to show.
const int _kMaxDisplayPairs = 20;

/// Mirror axis opacity.
const double _kMirrorAxisOpacity = 0.03;

/// Force-field gradient extent (px from card outer edge).
const double _kForceFieldExtent = 40.0;

/// Delta severity thresholds (0-100 scale).
const double _kSeverityNotable = 10;
const double _kSeveritySevere = 25;

/// Crosshatch grid spacing.
const double _kCrosshatchSpacing = 20.0;

/// Header height.
const double _kHeaderHeight = 56.0;

/// WB: Comet trail dot count (#81).
const int _kCometTrailCount = 3;

/// WB: Orb measurement tick count (#117).
const int _kOrbTickCount = 24;

/// WB: Arbitration stamp opacity (#113).
const double _kArbStampOpacity = 0.06;

/// WB: Compass tick count on verdict seal (#115).
const int _kCompassTickCount = 8;

// ═══════════════════════════════════════════════════════════
// DATA MODEL
// ═══════════════════════════════════════════════════════════

/// A paired Crossfire™ comparison: two figures, one topic, within 72h.
class CrossfirePair {
  const CrossfirePair({
    required this.id,
    required this.roundA,
    required this.roundB,
    required this.sharedTopic,
    required this.windowStart,
    required this.windowEnd,
  });

  final String id;
  final CrossfireRound roundA;
  final CrossfireRound roundB;
  final String sharedTopic;
  final DateTime windowStart;
  final DateTime windowEnd;

  int get hourSpan => windowEnd.difference(windowStart).inHours.abs();

  String get proximityLabel {
    final h = hourSpan;
    if (h <= 24) return 'WITHIN 24H';
    if (h <= 48) return 'WITHIN 48H';
    return 'WITHIN 72H';
  }

  /// Whether proximity is <=24h (amber-eligible).
  bool get isUrgentProximity => hourSpan <= 24;

  /// Raw delta (0-100 scale). Positive means A scored higher.
  double get consensusDelta =>
      roundA.consensusScore - roundB.consensusScore;

  /// Absolute delta clamped to 200 as a sanity guard.
  double get consensusDeltaAbs => consensusDelta.abs().clamp(0.0, 200.0);

  /// Whether either side has zero score (unscored / data pending).
  bool get hasDataPending =>
      roundA.consensusScore == 0 || roundB.consensusScore == 0;

  String get consensusDeltaDisplay {
    if (hasDataPending) return 'N/A';
    final d = consensusDelta.round();
    if (d == 0) return '0%';
    return d > 0 ? '+$d%' : '${d.abs()}%';
  }

  /// #112: Raw integer for count-up animation.
  int get consensusDeltaInt =>
      hasDataPending ? 0 : consensusDelta.round().abs().clamp(0, 200);

  String get severityLabel {
    final d = consensusDeltaAbs;
    if (d >= _kSeveritySevere) return 'SIGNIFICANT DIVERGENCE';
    if (d >= _kSeverityNotable) return 'NOTABLE DIVERGENCE';
    return 'WITHIN TOLERANCE';
  }

  bool get isSevere => consensusDeltaAbs >= _kSeverityNotable;

  List<MetricDelta> get metricDeltas {
    return [
      MetricDelta('REP', roundA.repetition, roundB.repetition),
      MetricDelta('NOV', roundA.novelty, roundB.novelty),
      MetricDelta('AFF', roundA.affect, roundB.affect),
      MetricDelta('ENT', roundA.entropy, roundB.entropy),
    ];
  }

  bool get hasVariance =>
      roundA.varianceDetected || roundB.varianceDetected;

  bool get categoryMatch =>
      roundA.framingLabel != null &&
      roundB.framingLabel != null &&
      roundA.framingLabel == roundB.framingLabel;

  static String buildId(String stmtIdA, String stmtIdB) {
    final sorted = [stmtIdA, stmtIdB]..sort();
    return '${sorted[0].substring(0, math.min(8, sorted[0].length))}_${sorted[1].substring(0, math.min(8, sorted[1].length))}'
        .toUpperCase();
  }
}

/// Per-metric delta calculation.
///
/// All values are 0-100 scale (from consensus table NUMERIC(5,2)).
class MetricDelta {
  MetricDelta(this.key, this.valueA, this.valueB);

  final String key;
  final double? valueA;
  final double? valueB;

  /// Whether either side is unscored (null or zero).
  bool get hasDataPending =>
      valueA == null || valueB == null || valueA == 0 || valueB == 0;

  /// Raw delta in 0-100 scale. Clamped to ±200 as sanity guard.
  double? get delta {
    if (valueA == null || valueB == null) return null;
    return (valueA! - valueB!).clamp(-200.0, 200.0);
  }

  String get display {
    final d = delta;
    if (d == null) return 'N/A';
    if (hasDataPending) return 'N/A';
    final pts = d.round();
    if (pts == 0) return '0';
    return pts > 0 ? '+$pts' : '${pts.abs()}';
  }

  bool get isDivergent {
    final d = delta;
    return d != null && d.abs() > _kDivergenceThreshold;
  }

  /// Normalized to 0-1 for bar painters. 50-point gap = full bar.
  double get normalizedDelta {
    final d = delta;
    if (d == null) return 0.0;
    return (d.abs() / 50).clamp(0.0, 1.0);
  }

  /// Normalize a single 0-100 value to 0-1 for painters.
  double get normalizedA => ((valueA ?? 0) / 100).clamp(0.0, 1.0);
  double get normalizedB => ((valueB ?? 0) / 100).clamp(0.0, 1.0);

  String get semanticLabel {
    final d = delta;
    if (d == null) return '$key: data unavailable';
    final pts = d.round().abs();
    return '$key difference: $pts points${isDivergent ? ', divergent' : ''}';
  }
}

// ═══════════════════════════════════════════════════════════
// SERVICE
// ═══════════════════════════════════════════════════════════

/// Module-level provider. Moves to F7.x at integration.
final crossfireServiceProvider = Provider<CrossfireService>((ref) {
  return CrossfireService(
    feedService: ref.read(feedServiceProvider),
  );
});

/// Client-side Crossfire pairing engine.
class CrossfireService {
  CrossfireService({required this.feedService});

  final FeedService feedService;

  Future<List<CrossfirePair>> getPairs({int limit = 20}) async {
    final response = await feedService.getFeed(
      limit: 200,
      offset: 0,
      rankedOnly: true,
    );

    final statements = response.statements;
    if (statements.isEmpty) return [];

    // BUG 1C: Filter out unscored statements before pairing.
    final scored = statements.where((s) =>
      s.consensusScore != null && s.consensusScore! > 0
    ).toList();

    final pairs = <CrossfirePair>[];
    final seen = <String>{};
    final usedStatements = <String>{};

    final byTopic = <String, List<_PairCandidate>>{};
    for (final stmt in scored) {
      final topics = stmt.topics;
      if (topics == null || topics.isEmpty) continue;
      for (final topic in topics) {
        byTopic.putIfAbsent(topic, () => []).add(
          _PairCandidate.fromStatement(stmt, topic),
        );
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

          // BUG 1A: Skip if either statement already used in a pair.
          if (usedStatements.contains(a.statementId) ||
              usedStatements.contains(b.statementId)) {
            continue;
          }

          final gap = a.statedAt.difference(b.statedAt).abs();
          if (gap > _kPairingWindow) continue;

          final dedupeKey = _dedupeKey(a.figureId, b.figureId, topic);
          if (seen.contains(dedupeKey)) continue;
          seen.add(dedupeKey);

          final earlier = a.statedAt.isBefore(b.statedAt) ? a : b;
          final later = a.statedAt.isBefore(b.statedAt) ? b : a;

          // BUG 1A: Mark both statements as used.
          usedStatements.add(a.statementId);
          usedStatements.add(b.statementId);

          pairs.add(CrossfirePair(
            id: CrossfirePair.buildId(
                earlier.statementId, later.statementId),
            roundA: earlier.toRound(),
            roundB: later.toRound(),
            sharedTopic: topic,
            windowStart: earlier.statedAt,
            windowEnd: later.statedAt,
          ));
        }
      }
    }

    pairs.sort((a, b) =>
        b.consensusDeltaAbs.compareTo(a.consensusDeltaAbs));

    return pairs.take(limit).toList();
  }

  Future<CrossfirePair?> getPairById(String pairId) async {
    final all = await getPairs(limit: 50);
    try {
      return all.firstWhere((p) => p.id == pairId);
    } catch (_) {
      return null;
    }
  }

  static String _dedupeKey(String figA, String figB, String topic) {
    final sorted = [figA, figB]..sort();
    return '${sorted[0]}:${sorted[1]}:$topic';
  }
}

/// Maps FeedStatement to CrossfireRound. Typed.
class _PairCandidate {
  const _PairCandidate({
    required this.figureId,
    required this.figureName,
    required this.statementId,
    required this.excerpt,
    required this.statedAt,
    required this.consensusScore,
    this.photoUrl,
    this.repetition,
    this.novelty,
    this.affect,
    this.entropy,
    this.framingLabel,
    this.topicLabel,
    this.varianceDetected = false,
  });

  factory _PairCandidate.fromStatement(FeedStatement stmt, String topic) {
    return _PairCandidate(
      figureId: stmt.figureId,
      figureName: stmt.figureName,
      statementId: stmt.id,
      excerpt: _truncate(stmt.text, 120),
      statedAt: stmt.statedAt,
      photoUrl: stmt.figurePhotoUrl,
      consensusScore: stmt.consensusScore ?? 0.0,
      repetition: stmt.repetition,
      novelty: stmt.novelty,
      affect: stmt.affect,
      entropy: stmt.entropy,
      framingLabel: stmt.dominantFraming,
      topicLabel: topic,
      varianceDetected: stmt.varianceDetected ?? false,
    );
  }

  final String figureId;
  final String figureName;
  final String statementId;
  final String excerpt;
  final DateTime statedAt;
  final double consensusScore;
  final String? photoUrl;
  final double? repetition;
  final double? novelty;
  final double? affect;
  final double? entropy;
  final String? framingLabel;
  final String? topicLabel;
  final bool varianceDetected;

  CrossfireRound toRound() => CrossfireRound(
        figureId: figureId,
        figureName: figureName,
        statementId: statementId,
        statementExcerpt: excerpt,
        statedAt: statedAt,
        consensusScore: consensusScore,
        photoUrl: photoUrl,
        repetition: repetition,
        novelty: novelty,
        affect: affect,
        entropy: entropy,
        framingLabel: framingLabel,
        topicLabel: topicLabel,
        varianceDetected: varianceDetected,
      );

  static String _truncate(String text, int max) {
    if (text.length <= max) return text;
    return '${text.substring(0, max - 1)}\u2026';
  }
}

// ═══════════════════════════════════════════════════════════
// TOPIC DISPLAY HELPER
// ═══════════════════════════════════════════════════════════

/// Converts raw topic enum (FOREIGN_POLICY) to display name (Foreign Policy).
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
// DTG HELPER
// ═══════════════════════════════════════════════════════════

String _formatDtg(DateTime dt) {
  final d = dt.toUtc();
  final day = d.day.toString().padLeft(2, '0');
  final hour = d.hour.toString().padLeft(2, '0');
  final min = d.minute.toString().padLeft(2, '0');
  const months = [
    '', 'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
    'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC',
  ];
  return '$day$hour${min}Z${months[d.month]}${d.year.toString().substring(2)}';
}

// ═══════════════════════════════════════════════════════════
// SCREEN
// ═══════════════════════════════════════════════════════════

class CrossfireScreen extends ConsumerStatefulWidget {
  const CrossfireScreen({super.key, this.pairId});

  final String? pairId;

  @override
  ConsumerState<CrossfireScreen> createState() => _CrossfireScreenState();
}

class _CrossfireScreenState extends ConsumerState<CrossfireScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  // ── State ──────────────────────────────────────────────
  List<CrossfirePair> _pairs = [];
  bool _loading = true;
  String? _error;
  int _currentPage = 0;
  bool _entranceComplete = false;

  // #112: Delta count-up state.
  int _deltaCountValue = 0;
  int _deltaCountTarget = 0;

  // ── Reduce motion (I-2/I-12: MediaQuery for persistent screens) ──
  bool _reduceMotion = false;
  bool _wasReduced = false;

  // ── Cached values (I-28, I-45) ─────────────────────────
  TextScaler _cachedTextScaler = TextScaler.noScaling;
  String _cachedDtg = '';

  // ── Timers (I-11) ─────────────────────────────────────
  final List<Timer> _pendingTimers = [];

  // ── Controllers (5) ────────────────────────────────────
  late final AnimationController _entranceCtrl;
  late final AnimationController _scanlineCtrl;
  late final AnimationController _barGrowCtrl;
  late final AnimationController _ambientCtrl;
  late final AnimationController _particleCtrl;
  late final PageController _pageCtrl;

  // ── CurvedAnimations ──────────────────────────────────
  late final CurvedAnimation _entranceCurve;
  late final CurvedAnimation _scanlineCurve;
  late final CurvedAnimation _barGrowCurve;

  // ── Pre-computed TextPainters (I-44/I-84) ─────────────
  late TextPainter _watermarkTP;
  late TextPainter _dtgTP;
  late TextPainter _handlingTP;
  late TextPainter _protocolTP;

  // C2 fix: Pre-computed pair-level TPs (no ParagraphBuilder in paint).
  late TextPainter _dateATP;
  late TextPainter _dateBTP;
  late TextPainter _exhibitTP;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Controllers.
    _entranceCtrl = AnimationController(
      vsync: this,
      duration: _kEntranceDuration,
    );
    _scanlineCtrl = AnimationController(
      vsync: this,
      duration: _kScanlineDuration,
    );
    _barGrowCtrl = AnimationController(
      vsync: this,
      duration: _kBarGrowDuration,
    );
    _ambientCtrl = AnimationController(
      vsync: this,
      duration: _kAmbientDuration,
    );
    _particleCtrl = AnimationController(
      vsync: this,
      duration: _kParticleDuration,
    );
    _pageCtrl = PageController();

    // CurvedAnimations.
    _entranceCurve = CurvedAnimation(
      parent: _entranceCtrl,
      curve: Curves.easeOutCubic,
    );
    _scanlineCurve = CurvedAnimation(
      parent: _scanlineCtrl,
      curve: Curves.easeInOut,
    );
    _barGrowCurve = CurvedAnimation(
      parent: _barGrowCtrl,
      curve: Curves.easeOutCubic,
    );

    // Entrance chain: scanline starts, entrance follows.
    _scanlineCtrl.addStatusListener(_onScanComplete);

    // Pre-init TPs (will be rebuilt in didChangeDependencies).
    _watermarkTP = TextPainter(textDirection: TextDirection.ltr);
    _dtgTP = TextPainter(textDirection: TextDirection.ltr);
    _handlingTP = TextPainter(textDirection: TextDirection.ltr);
    _protocolTP = TextPainter(textDirection: TextDirection.ltr);
    _dateATP = TextPainter(textDirection: TextDirection.ltr);
    _dateBTP = TextPainter(textDirection: TextDirection.ltr);
    _exhibitTP = TextPainter(textDirection: TextDirection.ltr);

    _cachedDtg = _formatDtg(DateTime.now());

    _loadPairs();
  }

  void _onScanComplete(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _scanlineCtrl.removeStatusListener(_onScanComplete);
      if (mounted && !_reduceMotion) {
        _entranceCtrl.forward();
      }
    }
  }

  void _onEntranceDone(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _entranceCtrl.removeStatusListener(_onEntranceDone);
      if (mounted) {
        setState(() => _entranceComplete = true);
        if (!_reduceMotion) {
          _ambientCtrl.repeat(reverse: true);
          _particleCtrl.repeat();
          _barGrowCtrl.forward();
        }
        HapticUtil.measurementComplete();

        // #112: Start delta count-up.
        _startDeltaCountUp();

        // I-78: Sequential popup gate.
        _pendingTimers.add(Timer(const Duration(milliseconds: 600), () {
          if (!mounted) return;
          RateAppPopup.maybeShow(context).then((_) {
            if (mounted) {
              SoftPaywallPopup.maybeShow(context);
            }
          });
        }));
      }
    }
  }

  /// #112: Animated delta count-up from 0 to target integer.
  void _startDeltaCountUp() {
    if (_pairs.isEmpty) return;
    _deltaCountTarget = _currentPair.consensusDeltaInt;
    if (_deltaCountTarget == 0 || _reduceMotion) {
      setState(() => _deltaCountValue = _deltaCountTarget);
      return;
    }
    _deltaCountValue = 0;
    final steps = _deltaCountTarget.clamp(1, 30);
    final intervalMs = (400 / steps).round().clamp(12, 50);
    final increment = (_deltaCountTarget / steps).ceil().clamp(1, 99);
    _pendingTimers.add(
      Timer.periodic(Duration(milliseconds: intervalMs), (timer) {
        if (!mounted) { timer.cancel(); return; }
        final next = _deltaCountValue + increment;
        if (next >= _deltaCountTarget) {
          timer.cancel();
          setState(() => _deltaCountValue = _deltaCountTarget);
          // #148: Micro-haptic on count-up landing.
          HapticUtil.light();
        } else {
          setState(() => _deltaCountValue = next);
        }
      }),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // I-2/I-12: MediaQuery for persistent screens.
    final reduced = MediaQuery.disableAnimationsOf(context);
    if (reduced && !_wasReduced) {
      // I-9: Mid-flight snap.
      for (final t in _pendingTimers) { t.cancel(); }
      _pendingTimers.clear();
      _entranceCtrl.value = 1.0;
      _scanlineCtrl.value = 1.0;
      _barGrowCtrl.value = 1.0;
      _ambientCtrl.stop();
      _particleCtrl.stop();
      setState(() {
        _entranceComplete = true;
        _deltaCountValue = _deltaCountTarget;
      });
    }
    _reduceMotion = reduced;
    _wasReduced = reduced;

    // I-28: Cache text scaler.
    final ts = MediaQuery.textScalerOf(context);
    if (ts != _cachedTextScaler) {
      _cachedTextScaler = ts;
      _rebuildTextPainters(ts);
      _rebuildPairTextPainters();
    }
  }

  /// I-81/3N: WidgetsBindingObserver for mid-flight a11y changes.
  @override
  void didChangeAccessibilityFeatures() {
    final reduced = ui.PlatformDispatcher.instance
        .accessibilityFeatures.reduceMotion;
    if (reduced && !_wasReduced) {
      for (final t in _pendingTimers) { t.cancel(); }
      _pendingTimers.clear();
      _entranceCtrl.value = 1.0;
      _scanlineCtrl.value = 1.0;
      _barGrowCtrl.value = 1.0;
      _ambientCtrl.stop();
      _particleCtrl.stop();
      setState(() {
        _entranceComplete = true;
        _deltaCountValue = _deltaCountTarget;
      });
    }
    _reduceMotion = reduced;
    _wasReduced = reduced;
  }

  /// I-44/I-84: Pre-compute all TextPainters used in painters.
  void _rebuildTextPainters(TextScaler ts) {
    _watermarkTP.dispose();
    _dtgTP.dispose();
    _handlingTP.dispose();
    _protocolTP.dispose();

    final teal = BaselineColors.teal;
    final secondary = BaselineColors.textSecondary;

    _watermarkTP = TextPainter(
      text: TextSpan(
        text: 'DECLASSIFIED',
        style: TextStyle(
          fontFamily: BaselineTypography.monoFontFamily,
          fontSize: 48,
          letterSpacing: 12,
          color: secondary.atOpacity(0.018),
        ),
      ),
      textDirection: TextDirection.ltr,
      textScaler: ts,
    )..layout(maxWidth: 600);

    _dtgTP = TextPainter(
      text: TextSpan(
        text: _cachedDtg,
        style: TextStyle(
          fontFamily: BaselineTypography.monoFontFamily,
          fontSize: 7,
          letterSpacing: 0.5,
          color: teal.atOpacity(0.06),
        ),
      ),
      textDirection: TextDirection.ltr,
      textScaler: ts,
    )..layout();

    _handlingTP = TextPainter(
      text: TextSpan(
        text: 'HANDLE VIA CROSSFIRE\u2122 CHANNELS ONLY',
        style: TextStyle(
          fontFamily: BaselineTypography.monoFontFamily,
          fontSize: 6,
          letterSpacing: 1.0,
          color: secondary.atOpacity(0.03),
        ),
      ),
      textDirection: TextDirection.ltr,
      textScaler: ts,
    )..layout();

    _protocolTP = TextPainter(
      text: TextSpan(
        text: 'COMPARISON PROTOCOL',
        style: TextStyle(
          fontFamily: BaselineTypography.monoFontFamily,
          fontSize: 7,
          letterSpacing: 1.5,
          color: secondary.atOpacity(0.04),
        ),
      ),
      textDirection: TextDirection.ltr,
      textScaler: ts,
    )..layout();
  }

  /// C2 fix: Pre-compute pair-dependent TPs (dates + exhibit stamp).
  /// Called on data load, page change, and text scaler change.
  void _rebuildPairTextPainters() {
    _dateATP.dispose();
    _dateBTP.dispose();
    _exhibitTP.dispose();

    if (_pairs.isEmpty) {
      _dateATP = TextPainter(textDirection: TextDirection.ltr);
      _dateBTP = TextPainter(textDirection: TextDirection.ltr);
      _exhibitTP = TextPainter(textDirection: TextDirection.ltr);
      return;
    }

    final pair = _currentPair;
    final secondary = BaselineColors.textSecondary;
    final ts = _cachedTextScaler;

    _dateATP = TextPainter(
      text: TextSpan(
        text: pair.roundA.dateShort,
        style: TextStyle(
          fontFamily: BaselineTypography.monoFontFamily,
          fontSize: 8,
          letterSpacing: 0.5,
          color: secondary.atOpacity(0.5),
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      textScaler: ts,
    )..layout();

    _dateBTP = TextPainter(
      text: TextSpan(
        text: pair.roundB.dateShort,
        style: TextStyle(
          fontFamily: BaselineTypography.monoFontFamily,
          fontSize: 8,
          letterSpacing: 0.5,
          color: secondary.atOpacity(0.5),
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      textScaler: ts,
    )..layout();

    _exhibitTP = TextPainter(
      text: TextSpan(
        text: 'EXHIBIT ${_currentPage + 1}',
        style: TextStyle(
          fontFamily: BaselineTypography.monoFontFamily,
          fontSize: 8,
          letterSpacing: 2.0,
          color: secondary.atOpacity(0.06),
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      textScaler: ts,
    )..layout();
  }

  @override
  void dispose() {
    // 1. Remove observer (I-81).
    WidgetsBinding.instance.removeObserver(this);

    // 2. Cancel pending timers (I-11).
    for (final t in _pendingTimers) { t.cancel(); }
    _pendingTimers.clear();

    // 3. CurvedAnimations first, reverse creation order (I-15).
    _barGrowCurve.dispose();
    _scanlineCurve.dispose();
    _entranceCurve.dispose();

    // 4. Stop + dispose controllers (I-29).
    _particleCtrl.stop();
    _particleCtrl.dispose();
    _ambientCtrl.stop();
    _ambientCtrl.dispose();
    _barGrowCtrl.stop();
    _barGrowCtrl.dispose();
    _scanlineCtrl.stop();
    _scanlineCtrl.dispose();
    _entranceCtrl.stop();
    _entranceCtrl.dispose();
    _pageCtrl.dispose();

    // 5. Dispose pre-computed TextPainters (I-44).
    _watermarkTP.dispose();
    _dtgTP.dispose();
    _handlingTP.dispose();
    _protocolTP.dispose();
    _dateATP.dispose();
    _dateBTP.dispose();
    _exhibitTP.dispose();

    super.dispose();
  }

  // ── Data Loading ──────────────────────────────────────

  Future<void> _loadPairs() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final service = ref.read(crossfireServiceProvider);

      // Retry with backoff for EF cold starts.
      const maxAttempts = 3;
      Object? lastError;
      for (var attempt = 1; attempt <= maxAttempts; attempt++) {
        try {
          if (widget.pairId != null) {
            final pair = await service.getPairById(widget.pairId!);
            _pairs = pair != null ? [pair] : [];
          } else {
            _pairs = await service.getPairs(limit: _kMaxDisplayPairs);
          }
          lastError = null;
          break; // Success
        } catch (e) {
          lastError = e;
          if (attempt < maxAttempts) {
            await Future.delayed(Duration(milliseconds: 500 * attempt));
            if (!mounted) return;
          }
        }
      }
      if (lastError != null) throw lastError;

      if (mounted) {
        setState(() => _loading = false);
        _cachedDtg = _formatDtg(DateTime.now());
        _rebuildTextPainters(_cachedTextScaler);
        _rebuildPairTextPainters();
        _deltaCountTarget = _pairs.isNotEmpty
            ? _currentPair.consensusDeltaInt
            : 0;

        if (_reduceMotion) {
          _entranceCtrl.value = 1.0;
          _scanlineCtrl.value = 1.0;
          _barGrowCtrl.value = 1.0;
          setState(() {
            _entranceComplete = true;
            _deltaCountValue = _deltaCountTarget;
          });
        } else {
          _entranceCtrl.addStatusListener(_onEntranceDone);
          _scanlineCtrl.forward();
        }

        RateAppTrigger.recordInteraction(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  void _onPageChanged(int index) {
    if ((_currentPage - index).abs() > 1) {
      HapticUtil.medium();
    } else {
      HapticUtil.selection();
    }
    setState(() => _currentPage = index);

    // C2: Rebuild pair-dependent TPs for new pair.
    _rebuildPairTextPainters();

    // #145: Scanline re-sweep on pair navigation.
    if (!_reduceMotion && _entranceComplete) {
      _scanlineCtrl.reset();
      _scanlineCtrl.forward();
    }

    // #112: Re-trigger delta count-up for new pair.
    if (_pairs.isNotEmpty) {
      _deltaCountTarget = _currentPair.consensusDeltaInt;
      if (_reduceMotion) {
        setState(() => _deltaCountValue = _deltaCountTarget);
      } else {
        _startDeltaCountUp();
      }
    }
  }

  /// I-82: Export guarded behind _entranceComplete.
  void _onExport() {
    if (!_entranceComplete) return;
    HapticUtil.light();
    final pair = _currentPair;
    ExportUtil.composeCrossfire(
      context: context,
      pair: pair,
      topic: _topicDisplayName(pair.sharedTopic),
      figureA: pair.roundA.figureName,
      figureB: pair.roundB.figureName,
      delta: pair.consensusDeltaDisplay,
    );
  }

  Future<void> _onRefresh() async {
    HapticUtil.light();
    if (!_reduceMotion) {
      _entranceCtrl.reset();
      _scanlineCtrl.reset();
      _barGrowCtrl.reset();
      _particleCtrl.stop();
      _ambientCtrl.stop();
    }
    _entranceComplete = false;
    _deltaCountValue = 0;
    await _loadPairs();
    HapticUtil.refreshComplete();
  }

  CrossfirePair get _currentPair =>
      _pairs[_currentPage.clamp(0, math.max(0, _pairs.length - 1))];

  /// Ambient sine wave (0.0-1.0).
  double get _ambientSine => _reduceMotion
      ? 0.0
      : math.sin(_ambientCtrl.value * math.pi * 2) * 0.5 + 0.5;

  /// 5-phase stagger helper.
  double _phase(double start, double end) {
    if (_reduceMotion) return 1.0;
    return ((_entranceCurve.value - start) / (end - start)).clamp(0.0, 1.0);
  }

  // ── Build ──────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return BaselineSystemUI(
      child: Scaffold(
        backgroundColor: BaselineColors.scaffoldBackground,
        body: FeatureGate(
          feature: GatedFeature.crossfire,
          child: Column(
            children: [
              // Custom header (replaces stock AppBar).
              _buildHeader(),
              // Body content.
              Expanded(child: _buildBody()),
            ],
          ),
        ),
      ),
    );
  }

  // ── Custom Header (64-75) ─────────────────────────────

  Widget _buildHeader() {
    final p1 = _phase(_kPhase1Start, _kPhase1End);

    return ExcludeSemantics(
      excluding: false,
      child: Container(
        height: _kHeaderHeight + MediaQuery.paddingOf(context).top,
        padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top),
        color: BaselineColors.black,
        child: CustomPaint(
          painter: _HeaderChromePainter(
            accent: BaselineColors.teal,
            progress: p1,
            dtgTP: _dtgTP,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                // Back button with _TapScale.
                Semantics(
                  button: true,
                  label: 'Back',
                  child: _TapScale(
                    scale: 0.95,
                    onTap: () {
                      HapticUtil.light();
                      context.pop();
                    },
                    child: SizedBox(
                      width: 44,
                      height: 44,
                      child: Center(
                        child: BaselineIcon(
                          BaselineIconType.backArrow,
                          size: 22,
                          color: BaselineColors.textPrimary,
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(width: 4),

                // Title row: (U) + pulse dot + CROSSFIRE + info tap.
                Expanded(
                  child: Opacity(
                    opacity: p1,
                    child: Transform.translate(
                      offset: Offset((1 - p1) * 6, 0),
                      child: GestureDetector(
                        onTap: () {
                          HapticUtil.light();
                          InfoBottomSheet.show(context, infoKey: 'crossfire');
                        },
                        behavior: HitTestBehavior.opaque,
                        child: Semantics(
                          button: true,
                          excludeSemantics: true,
                          label: 'How Crossfire works',
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // (U) classification marking.
                              Text(
                                '(U)',
                                style: BaselineTypography.dataSmall.copyWith(
                                  color: BaselineColors.textSecondary
                                      .atOpacity(0.25),
                                  fontSize: 7,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(width: 6),
                              // Teal micro-pulse dot.
                              Container(
                                width: 5,
                                height: 5,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: BaselineColors.teal.atOpacity(0.6),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  'CROSSFIRE\u2122',
                                  style: BaselineTypography.data.copyWith(
                                    color: BaselineColors.teal,
                                    letterSpacing: 3.0,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.visible,
                                ),
                              ),
                              const SizedBox(width: 6),
                              BaselineIcon(
                                BaselineIconType.info,
                                size: 16,
                                color: BaselineColors.textSecondary
                                    .atOpacity(0.3),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                ),

                const SizedBox(width: 4),

                // Export button (I-82: gated by _entranceComplete).
                Semantics(
                  button: true,
                  label: 'Export comparison',
                  child: _TapScale(
                    scale: 0.95,
                    onTap: _onExport,
                    child: Opacity(
                      opacity: _entranceComplete ? 1.0 : 0.3,
                      child: SizedBox(
                        width: 44,
                        height: 44,
                        child: Center(
                          child: BaselineIcon(
                            BaselineIconType.export,
                            size: 18,
                            color: BaselineColors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Body ──────────────────────────────────────────────

  Widget _buildBody() {
    if (_loading) return _buildLoading();
    if (_error != null) return _buildError();
    if (_pairs.isEmpty) return _buildEmpty();
    return _buildContent();
  }

  Widget _buildLoading() {
    return Padding(
      padding: BaselineInsets.screen,
      child: Column(
        children: [
          const SizedBox(height: BaselineSpacing.xl),
          ShimmerLoading(
            width: double.infinity,
            height: 80,
            borderRadius: BorderRadius.circular(BaselineRadius.card),
          ),
          const SizedBox(height: BaselineSpacing.lg),
          Row(
            children: [
              Expanded(
                child: ShimmerLoading(
                  width: double.infinity,
                  height: 300,
                  borderRadius: BaselineRadius.buttonBorderRadius,
                ),
              ),
              const SizedBox(width: _kCardGap),
              Expanded(
                child: ShimmerLoading(
                  width: double.infinity,
                  height: 300,
                  borderRadius: BaselineRadius.buttonBorderRadius,
                ),
              ),
            ],
          ),
          const SizedBox(height: BaselineSpacing.lg),
          ShimmerLoading(
            width: double.infinity,
            height: 100,
            borderRadius: BorderRadius.circular(BaselineRadius.sm),
          ),
          const SizedBox(height: BaselineSpacing.md),
          Center(
            child: ShimmerLoading(
              width: _kDeltaOrbSize,
              height: _kDeltaOrbSize,
              borderRadius: _kDeltaOrbSize / 2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: BaselineInsets.screen,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            BaselineIcon(
              BaselineIconType.warning,
              size: 40,
              color: BaselineColors.textSecondary,
            ),
            const SizedBox(height: BaselineSpacing.md),
            Text(
              'Unable to load comparisons',
              style: BaselineTypography.body.copyWith(
                color: BaselineColors.textSecondary,
              ),
            ),
            const SizedBox(height: BaselineSpacing.lg),
            GestureDetector(
              onTap: _onRefresh,
              child: Semantics(
                button: true,
                excludeSemantics: true,
                label: 'Retry',
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: BaselineSpacing.lg,
                    vertical: BaselineSpacing.sm,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(BaselineRadius.sm),
                    border: Border.all(
                      color: BaselineColors.borderInactive,
                      width: BaselineBorder.standard.width,
                    ),
                  ),
                  child: Text(
                    'RETRY',
                    style: BaselineTypography.data.copyWith(
                      color: BaselineColors.teal,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return const Center(
      child: EmptyState(variant: EmptyStateVariant.noCrossfire),
    );
  }

  // ── Content (AnimatedBuilder split: I-79/I-83) ────────

  Widget _buildContent() {
    return Stack(
      children: [
        // Chrome layer: isolated, never rebuilds with content (I-79).
        Positioned.fill(
          child: RepaintBoundary(
            child: ExcludeSemantics(
              child: AnimatedBuilder(
                animation: Listenable.merge([
                  _entranceCurve,
                  _scanlineCurve,
                ]),
                builder: (_, _) => CustomPaint(
                  painter: _ScreenChromePainter(
                    accent: BaselineColors.teal,
                    secondary: BaselineColors.textSecondary,
                    entranceProgress: _entranceCurve.value,
                    scanlineProgress: _scanlineCurve.value,
                    watermarkTP: _watermarkTP,
                    dtgTP: _dtgTP,
                    handlingTP: _handlingTP,
                    protocolTP: _protocolTP,
                  ),
                ),
              ),
            ),
          ),
        ),

        // Content layer: entrance AnimatedBuilder settles after entrance.
        AnimatedBuilder(
          animation: _entranceCurve,
          builder: (_, _) => RefreshIndicator(
            onRefresh: () async => _onRefresh(),
            color: BaselineColors.teal,
            backgroundColor: BaselineColors.card,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              slivers: [
                // Classification header.
                SliverToBoxAdapter(child: _buildClassificationHeader()),

                // #82: Wire connector from classification to timeline.
                SliverToBoxAdapter(child: _buildWireConnector()),

                // Temporal timeline.
                SliverToBoxAdapter(child: _buildTemporalTimeline()),

                // Confrontation zone label.
                SliverToBoxAdapter(child: _buildZoneLabel()),

                // Paired cards + central spine + force-field gradients.
                SliverToBoxAdapter(child: _buildPairViewer()),

                // Detail hint.
                SliverToBoxAdapter(child: _buildDetailHint()),

                // #95: Wire connector from cards to bridge.
                SliverToBoxAdapter(child: _buildWireConnector()),

                // Divergence bridge (leaf AnimatedBuilder for bars).
                SliverToBoxAdapter(child: _buildDivergenceBridge()),

                // Delta orb (leaf AnimatedBuilder for verdict).
                SliverToBoxAdapter(child: _buildDeltaOrb()),

                // #113: Arbitration complete stamp.
                if (_entranceComplete)
                  SliverToBoxAdapter(child: _buildArbitrationStamp()),

                // Severity classification.
                SliverToBoxAdapter(child: _buildSeverityLabel()),

                // Pair navigation dots.
                if (_pairs.length > 1)
                  SliverToBoxAdapter(child: _buildPairDots()),

                // Variance banner.
                if (_currentPair.hasVariance)
                  SliverToBoxAdapter(child: _buildVarianceBanner()),

                // Methodology link.
                SliverToBoxAdapter(child: _buildMethodologyLink()),

                // Bottom safe area.
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: MediaQuery.paddingOf(context).bottom +
                        BaselineSpacing.xl,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── Classification Header (#76-83 upgrades) ───────────

  Widget _buildClassificationHeader() {
    final pair = _currentPair;
    final p1 = _phase(_kPhase1Start, _kPhase1End);

    return Opacity(
      opacity: p1,
      child: Transform.translate(
        offset: Offset(0, (1 - p1) * 6),
        child: Container(
          margin: BaselineInsets.screen.copyWith(
            top: BaselineSpacing.md,
            bottom: 0,
          ),
          padding: const EdgeInsets.fromLTRB(
            BaselineSpacing.md,
            BaselineSpacing.sm,
            BaselineSpacing.md,
            BaselineSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: BaselineColors.card,
            borderRadius: BorderRadius.circular(BaselineRadius.card),
            border: Border.all(
              color: BaselineColors.borderInactive,
              width: BaselineBorder.standard.width,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Classification line.
              Row(
                children: [
                  _ClassDot(color: BaselineColors.teal.atOpacity(0.6)),
                  const SizedBox(width: BaselineSpacing.xs),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: 'COMPARATIVE ANALYSIS',
                            style: BaselineTypography.dataSmall.copyWith(
                              color: BaselineColors.textSecondary,
                              letterSpacing: 1.5,
                            ),
                          ),
                          TextSpan(
                            text: ' // ',
                            style: BaselineTypography.dataSmall.copyWith(
                              color: BaselineColors.borderInactive,
                            ),
                          ),
                          TextSpan(
                            text: 'CROSSFIRE\u2122',
                            style: BaselineTypography.dataSmall.copyWith(
                              color: BaselineColors.teal,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (_pairs.length > 1) ...[
                    const SizedBox(width: BaselineSpacing.xs),
                    Text(
                      'PAIR ${_currentPage + 1} OF ${_pairs.length}',
                      style: BaselineTypography.dataSmall.copyWith(
                        color: BaselineColors.textSecondary
                            .atOpacity(0.4),
                        letterSpacing: 1.0,
                        fontSize: 7,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 6),

              // Topic name.
              Text(
                _topicDisplayName(pair.sharedTopic).toUpperCase(),
                style: BaselineTypography.h2.copyWith(
                  color: BaselineColors.textPrimary,
                  letterSpacing: 1.0,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),

              // #76: Framing sub-label when both subjects share a framing category.
              if (pair.categoryMatch) ...[
                const SizedBox(height: 2),
                Text(
                  'FRAMING: ${pair.roundA.framingLabel?.toUpperCase() ?? ""}',
                  style: BaselineTypography.dataSmall.copyWith(
                    color: BaselineColors.teal.atOpacity(0.35),
                    fontSize: 7,
                    letterSpacing: 1.0,
                  ),
                ),
              ],
              const SizedBox(height: 4),

              // Subjects + proximity badge.
              Row(
                children: [
                  // #85: Document subject IDs.
                  ExcludeSemantics(
                    child: Text(
                      'SUBJ\u2009',
                      style: BaselineTypography.dataSmall.copyWith(
                        color: BaselineColors.textSecondary.atOpacity(0.2),
                        fontSize: 7,
                      ),
                    ),
                  ),
                  Flexible(
                    child: Text(
                      '${pair.roundA.figureName.split(' ').last.toUpperCase()} vs ${pair.roundB.figureName.split(' ').last.toUpperCase()}',
                      style: BaselineTypography.dataSmall.copyWith(
                        color: BaselineColors.textSecondary,
                        letterSpacing: 0.5,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: BaselineSpacing.sm),
                  _ProximityBadge(
                    label: pair.proximityLabel,
                    isUrgent: pair.isUrgentProximity,
                    ambientSine: _ambientSine,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Wire Connector (#82, #95) ─────────────────────────

  Widget _buildWireConnector() {
    final p = _phase(_kPhase1Start, _kPhase2End);
    return ExcludeSemantics(
      child: Opacity(
        opacity: p * 0.3,
        child: SizedBox(
          height: 10,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: List.generate(3, (_) => Container(
                width: 1,
                height: 1.5,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: BaselineColors.teal.atOpacity(0.15),
                ),
              )),
            ),
          ),
        ),
      ),
    );
  }

  // ── Temporal Timeline (#80-81 upgrades) ───────────────

  Widget _buildTemporalTimeline() {
    final p1 = _phase(_kPhase1Start, _kPhase1End);

    return ExcludeSemantics(
      child: Opacity(
        opacity: p1,
        child: Container(
          margin: BaselineInsets.screen.copyWith(
            top: BaselineSpacing.xs,
            bottom: BaselineSpacing.sm,
          ),
          height: 36,
          child: AnimatedBuilder(
            animation: _ambientCtrl,
            builder: (_, _) => CustomPaint(
              painter: _TemporalTimelinePainter(
                accent: BaselineColors.teal,
                secondary: BaselineColors.textSecondary,
                progress: p1,
                dateATP: _dateATP,
                dateBTP: _dateBTP,
                positionA: 0.15,
                positionB: 0.85,
                ambientPhase: _reduceMotion ? 0.0 : _ambientCtrl.value,
              ),
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
  }

  // ── Confrontation Zone Label (#84 upgrade) ────────────

  Widget _buildZoneLabel() {
    final p2 = _phase(_kPhase2Start, _kPhase2End);
    return ExcludeSemantics(
      child: Opacity(
        opacity: p2 * 0.35,
        child: Padding(
          padding: const EdgeInsets.only(
            bottom: BaselineSpacing.xs,
            top: 2,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // #84: Flanking calibration marks.
              ...List.generate(3, (i) => Padding(
                padding: const EdgeInsets.only(right: 2),
                child: Container(
                  width: 3 + (i == 1 ? 2 : 0).toDouble(),
                  height: 0.5,
                  color: BaselineColors.teal.atOpacity(0.12),
                ),
              )),
              const SizedBox(width: 6),
              // #84: Breathing micro-dot.
              Container(
                width: 3,
                height: 3,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: BaselineColors.teal
                      .atOpacity(0.15 + (_ambientSine * 0.10)),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'ANALYSIS ZONE',
                style: BaselineTypography.dataSmall.copyWith(
                  color: BaselineColors.textSecondary,
                  letterSpacing: 2.5,
                  fontSize: 7,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                width: 3,
                height: 3,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: BaselineColors.teal
                      .atOpacity(0.15 + (_ambientSine * 0.10)),
                ),
              ),
              const SizedBox(width: 6),
              ...List.generate(3, (i) => Padding(
                padding: const EdgeInsets.only(left: 2),
                child: Container(
                  width: 3 + (i == 1 ? 2 : 0).toDouble(),
                  height: 0.5,
                  color: BaselineColors.teal.atOpacity(0.12),
                ),
              )),
            ],
          ),
        ),
      ),
    );
  }

  // ── Pair Viewer (Cards + Spine + Force Fields) ────────

  Widget _buildPairViewer() {
    if (_pairs.length == 1) {
      return _buildCardRow(_currentPair);
    }

    return SizedBox(
      height: 360,
      child: PageView.builder(
        controller: _pageCtrl,
        itemCount: _pairs.length,
        onPageChanged: _onPageChanged,
        itemBuilder: (context, index) => _buildCardRow(_pairs[index]),
      ),
    );
  }

  Widget _buildCardRow(CrossfirePair pair) {
    final p2 = _phase(_kPhase2Start, _kPhase2End);

    return Padding(
      padding: BaselineInsets.screen.copyWith(
        top: 0,
        bottom: BaselineSpacing.xs,
      ),
      child: AnimatedBuilder(
        animation: Listenable.merge([_ambientCtrl, _scanlineCurve]),
        builder: (_, _) => CustomPaint(
          painter: _ComparisonFramePainter(
            accent: BaselineColors.teal,
            secondary: BaselineColors.textSecondary,
            cornerGlowProgress: p2,
            scanlineProgress: _scanlineCurve.value,
            ambientPhase: _ambientSine,
            pairIndex: _currentPage + 1,
            exhibitTP: _exhibitTP,
          ),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Subject A: slides from left.
                Expanded(
                  child: Transform.translate(
                    offset: Offset((1 - p2) * -8, 0),
                    child: Opacity(
                      opacity: p2,
                      child: Column(
                        children: [
                          _SubjectDesignation(
                            label: 'A',
                            glowIntensity: _ambientSine,
                            // #85: Subject document ID.
                            subjectId: pair.roundA.subjectId,
                          ),
                          const SizedBox(height: 4),
                          _ForceFieldGradient(
                            side: CrossfirePosition.left,
                            intensity: p2,
                            child: CrossfireRoundCard(
                              round: pair.roundA,
                              designation: 'A',
                              position: CrossfirePosition.left,
                              onTap: () => context.push(
                                AppRoutes.statementPath(pair.roundA.statementId),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // Central convergence spine.
                SizedBox(
                  width: _kCardGap,
                  child: AnimatedBuilder(
                    animation: _particleCtrl,
                    builder: (_, _) => CustomPaint(
                      painter: _ConvergenceSpinePainter(
                        accent: BaselineColors.teal,
                        particleColor: BaselineColors.textSecondary,
                        progress: p2,
                        particlePhase: _reduceMotion
                            ? 1.0
                            : _particleCtrl.value,
                        ambientSine: _ambientSine,
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),

                // Subject B: slides from right.
                Expanded(
                  child: Transform.translate(
                    offset: Offset((1 - p2) * 8, 0),
                    child: Opacity(
                      opacity: p2,
                      child: Column(
                        children: [
                          _SubjectDesignation(
                            label: 'B',
                            glowIntensity: _ambientSine,
                            subjectId: pair.roundB.subjectId,
                          ),
                          const SizedBox(height: 4),
                          _ForceFieldGradient(
                            side: CrossfirePosition.right,
                            intensity: p2,
                            child: CrossfireRoundCard(
                              round: pair.roundB,
                              designation: 'B',
                              position: CrossfirePosition.right,
                              onTap: () => context.push(
                                AppRoutes.statementPath(pair.roundB.statementId),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Detail Hint ───────────────────────────────────────

  Widget _buildDetailHint() {
    final p3 = _phase(_kPhase3Start, _kPhase3End);
    return ExcludeSemantics(
      child: Opacity(
        opacity: p3 * 0.4,
        child: Padding(
          padding: const EdgeInsets.only(bottom: BaselineSpacing.xs),
          child: Center(
            child: Text(
              'TAP CARDS FOR FULL DETAIL',
              style: BaselineTypography.dataSmall.copyWith(
                color: BaselineColors.textSecondary,
                letterSpacing: 1.5,
                fontSize: 7,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Divergence Bridge (#98-102 upgrades) ──────────────

  Widget _buildDivergenceBridge() {
    final pair = _currentPair;
    final p3 = _phase(_kPhase3Start, _kPhase3End);

    return Opacity(
      opacity: p3,
      child: Container(
        margin: BaselineInsets.screen.copyWith(
          top: 0,
          bottom: BaselineSpacing.xs,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: BaselineSpacing.md,
          vertical: BaselineSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: BaselineColors.card,
          borderRadius: BorderRadius.circular(BaselineRadius.sm),
          border: Border.all(
            color: BaselineColors.borderInactive,
            width: BaselineBorder.standard.width,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Section label + cross-examination ruler + #98 stamp.
            ExcludeSemantics(
              child: CustomPaint(
                painter: _CrossExamRulerPainter(
                  accent: BaselineColors.teal,
                  progress: p3,
                ),
                child: Row(
                  children: [
                    _ClassDot(
                        color: BaselineColors.textSecondary.atOpacity(0.3)),
                    const SizedBox(width: BaselineSpacing.xs),
                    Text(
                      'DIVERGENCE MAP',
                      style: BaselineTypography.dataSmall.copyWith(
                        color: BaselineColors.textSecondary,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const Spacer(),
                    // #98: CROSS-EXAMINATION header stamp.
                    Text(
                      'CROSS\u2010EXAM',
                      style: BaselineTypography.dataSmall.copyWith(
                        color: BaselineColors.textSecondary.atOpacity(0.15),
                        fontSize: 6,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: BaselineSpacing.sm),

            // Subject labels.
            ExcludeSemantics(
              child: Row(
                children: [
                  const SizedBox(width: 28),
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          pair.roundA.figureName
                              .split(' ')
                              .last
                              .toUpperCase(),
                          style: BaselineTypography.dataSmall.copyWith(
                            color: BaselineColors.teal.atOpacity(0.5),
                            fontSize: 7,
                            letterSpacing: 1.0,
                          ),
                        ),
                        Text(
                          pair.roundB.figureName
                              .split(' ')
                              .last
                              .toUpperCase(),
                          style: BaselineTypography.dataSmall.copyWith(
                            color: BaselineColors.teal.atOpacity(0.5),
                            fontSize: 7,
                            letterSpacing: 1.0,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 36),
                ],
              ),
            ),

            // #99: Ruler tick labels at quartile marks.
            ExcludeSemantics(
              child: Padding(
                padding: const EdgeInsets.only(left: 28, right: 36),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (final label in ['25', '50', '75'])
                      Text(
                        label,
                        style: BaselineTypography.dataSmall.copyWith(
                          color: BaselineColors.textSecondary.atOpacity(0.10),
                          fontSize: 6,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 4),

            // Bridge rows with leaf AnimatedBuilder for collision sparks.
            AnimatedBuilder(
              animation: Listenable.merge([_barGrowCurve, _ambientCtrl]),
              builder: (_, _) => Column(
                children: List.generate(pair.metricDeltas.length, (i) {
                  final rowDelay = _kBridgeRowStaggerMs * i;
                  final rowProgress = _reduceMotion
                      ? 1.0
                      : ((_barGrowCurve.value -
                                  (rowDelay /
                                      _kBarGrowDuration.inMilliseconds))
                              .clamp(0.0, 1.0));
                  return Semantics(
                    excludeSemantics: true,
                    label: pair.metricDeltas[i].semanticLabel,
                    child: _BridgeRow(
                      delta: pair.metricDeltas[i],
                      progress: rowProgress,
                      ambientSine: _ambientSine,
                    ),
                  );
                }),
              ),
            ),

            // #102: Category match with reticle accents.
            if (pair.categoryMatch) ...[
              const SizedBox(height: BaselineSpacing.sm),
              ExcludeSemantics(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Reticle accent left.
                    _MiniReticle(color: BaselineColors.teal.atOpacity(0.12)),
                    const SizedBox(width: 6),
                    Container(
                      width: 16,
                      height: 1,
                      color: BaselineColors.teal.atOpacity(0.10),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'MATCHED: ${pair.roundA.framingLabel?.toUpperCase() ?? ""}',
                      style: BaselineTypography.dataSmall.copyWith(
                        color: BaselineColors.teal.atOpacity(0.4),
                        fontSize: 7,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      width: 16,
                      height: 1,
                      color: BaselineColors.teal.atOpacity(0.10),
                    ),
                    const SizedBox(width: 6),
                    _MiniReticle(color: BaselineColors.teal.atOpacity(0.12)),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Delta Orb (#112-117 upgrades) ─────────────────────

  Widget _buildDeltaOrb() {
    final pair = _currentPair;
    final p4 = _phase(_kPhase4Start, _kPhase4End);
    final p5 = _phase(_kPhase5Start, _kPhase5End);
    final isDivergent = pair.consensusDeltaAbs > _kDivergenceThreshold;
    final orbColor =
        isDivergent ? BaselineColors.amber : BaselineColors.teal;

    // #114: Ambient breathing scale.
    final breathScale = 1.0 + (_ambientSine * 0.015);

    return Opacity(
      opacity: p4,
      child: Transform.scale(
        scale: (0.8 + (0.2 * p4)) * (_entranceComplete ? breathScale : 1.0),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: BaselineSpacing.md),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // A consensus.
                  Column(
                    children: [
                      ExcludeSemantics(
                        child: Text(
                          'A',
                          style: BaselineTypography.dataSmall.copyWith(
                            color: BaselineColors.textSecondary
                                .atOpacity(0.4),
                            letterSpacing: 1.0,
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        pair.roundA.consensusDisplay,
                        style: BaselineTypography.dataLarge.copyWith(
                          color: BaselineColors.textPrimary,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(width: BaselineSpacing.lg),

                  // Delta orb + verdict flash + seal.
                  SizedBox(
                    width: _kVerdictSealRadius * 2,
                    height: _kVerdictSealRadius * 2,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Verdict seal ring (outer).
                        if (p5 > 0.01)
                          CustomPaint(
                            painter: _VerdictSealPainter(
                              color: orbColor,
                              progress: p5,
                              ambientSine: _entranceComplete
                                  ? _ambientSine
                                  : 0.0,
                            ),
                            size: Size(
                              _kVerdictSealRadius * 2,
                              _kVerdictSealRadius * 2,
                            ),
                          ),

                        // Verdict flash (radial pulse).
                        if (p4 > 0.95 && p5 < 0.5)
                          CustomPaint(
                            painter: _VerdictFlashPainter(
                              color: orbColor,
                              progress:
                                  (p5 / 0.5).clamp(0.0, 1.0),
                            ),
                            size: Size(
                              _kVerdictSealRadius * 2,
                              _kVerdictSealRadius * 2,
                            ),
                          ),

                        // Core delta orb ring gauge.
                        SizedBox(
                          width: _kDeltaOrbSize,
                          height: _kDeltaOrbSize,
                          child: CustomPaint(
                            painter: _DeltaOrbPainter(
                              fillRatio: (pair.consensusDeltaAbs / 50)
                                  .clamp(0.0, 1.0),
                              color: orbColor,
                              progress: p4,
                              trackColor: BaselineColors.borderInactive,
                            ),
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '\u0394',
                                    style: BaselineTypography.dataSmall
                                        .copyWith(
                                      color: orbColor.atOpacity(0.6),
                                      fontSize: 9,
                                    ),
                                  ),
                                  // #112: Count-up display.
                                  Text(
                                    _entranceComplete
                                        ? pair.consensusDeltaDisplay
                                        : '$_deltaCountValue%',
                                    style:
                                        BaselineTypography.data.copyWith(
                                      color: orbColor,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(width: BaselineSpacing.lg),

                  // B consensus.
                  Column(
                    children: [
                      ExcludeSemantics(
                        child: Text(
                          'B',
                          style: BaselineTypography.dataSmall.copyWith(
                            color: BaselineColors.textSecondary
                                .atOpacity(0.4),
                            letterSpacing: 1.0,
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        pair.roundB.consensusDisplay,
                        style: BaselineTypography.dataLarge.copyWith(
                          color: BaselineColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Arbitration Complete Stamp (#113) ─────────────────

  Widget _buildArbitrationStamp() {
    final p5 = _phase(_kPhase5Start, _kPhase5End);
    return ExcludeSemantics(
      child: Opacity(
        opacity: p5 * _kArbStampOpacity * 8,
        child: Padding(
          padding: const EdgeInsets.only(bottom: BaselineSpacing.xs),
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 0.5,
                  color: BaselineColors.teal.atOpacity(0.10),
                ),
                const SizedBox(width: 6),
                Text(
                  'ARBITRATION COMPLETE',
                  style: BaselineTypography.dataSmall.copyWith(
                    color: BaselineColors.textSecondary.atOpacity(0.12),
                    fontSize: 6,
                    letterSpacing: 2.0,
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  width: 8,
                  height: 0.5,
                  color: BaselineColors.teal.atOpacity(0.10),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Severity Classification (#117 upgrade) ────────────

  Widget _buildSeverityLabel() {
    final pair = _currentPair;
    final p4 = _phase(_kPhase4Start, _kPhase4End);
    final color = pair.isSevere
        ? BaselineColors.amber.atOpacity(0.5)
        : BaselineColors.teal.atOpacity(0.35);

    return Opacity(
      opacity: p4 * 0.7,
      child: Padding(
        padding: const EdgeInsets.only(bottom: BaselineSpacing.sm),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Severity hashlines (amber) flanking label on SIGNIFICANT.
              if (pair.consensusDeltaAbs >= _kSeveritySevere) ...[
                Container(
                  width: 12,
                  height: 1,
                  color: BaselineColors.amber.atOpacity(0.3),
                ),
                const SizedBox(width: 4),
                // #117: Micro-tick between hashline and label.
                Container(
                  width: 1,
                  height: 4,
                  color: BaselineColors.amber.atOpacity(0.15),
                ),
                const SizedBox(width: 4),
              ],
              Text(
                pair.severityLabel,
                style: BaselineTypography.dataSmall.copyWith(
                  color: color,
                  letterSpacing: 2.0,
                  fontSize: 8,
                ),
              ),
              if (pair.consensusDeltaAbs >= _kSeveritySevere) ...[
                const SizedBox(width: 4),
                Container(
                  width: 1,
                  height: 4,
                  color: BaselineColors.amber.atOpacity(0.15),
                ),
                const SizedBox(width: 4),
                Container(
                  width: 12,
                  height: 1,
                  color: BaselineColors.amber.atOpacity(0.3),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ── Pair Navigation Dots (#124 upgrade) ───────────────

  Widget _buildPairDots() {
    final p5 = _phase(_kPhase5Start, _kPhase5End);

    // Compact text indicator when too many dots would overflow.
    if (_pairs.length > 10) {
      return Opacity(
        opacity: p5,
        child: SizedBox(
          height: 44,
          child: Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: () {
                    if (_currentPage > 0) {
                      HapticUtil.selection();
                      _pageCtrl.animateToPage(
                        _currentPage - 1,
                        duration: BaselineAnimation.normal,
                        curve: BaselineAnimation.curve,
                      );
                    }
                  },
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: BaselineIcon(
                      BaselineIconType.backArrow,
                      size: 16,
                      color: _currentPage > 0
                          ? BaselineColors.textSecondary
                          : BaselineColors.textSecondary.atOpacity(0.15),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  '${_currentPage + 1}/${_pairs.length}',
                  style: BaselineTypography.dataSmall.copyWith(
                    color: BaselineColors.teal,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: () {
                    if (_currentPage < _pairs.length - 1) {
                      HapticUtil.selection();
                      _pageCtrl.animateToPage(
                        _currentPage + 1,
                        duration: BaselineAnimation.normal,
                        curve: BaselineAnimation.curve,
                      );
                    }
                  },
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: RotatedBox(
                      quarterTurns: 2,
                      child: BaselineIcon(
                        BaselineIconType.backArrow,
                        size: 16,
                        color: _currentPage < _pairs.length - 1
                            ? BaselineColors.textSecondary
                            : BaselineColors.textSecondary.atOpacity(0.15),
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

    return Opacity(
      opacity: p5,
      child: SizedBox(
        height: 44,
        child: Center(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(_pairs.length, (i) {
              final isActive = i == _currentPage;
              return Semantics(
                button: true,
                label: 'Pair ${i + 1} of ${_pairs.length}',
                child: _TapScale(
                  scale: 0.90,
                  onTap: () {
                    HapticUtil.selection();
                    _pageCtrl.animateToPage(
                      i,
                      duration: BaselineAnimation.normal,
                      curve: BaselineAnimation.curve,
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 3,
                      vertical: 8,
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // #124: Active dot ring glow.
                        if (isActive)
                          AnimatedContainer(
                            duration: BaselineAnimation.fast,
                            width: 22,
                            height: 12,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(6),
                              color: BaselineColors.teal.atOpacity(0.06),
                            ),
                          ),
                        AnimatedContainer(
                          duration: BaselineAnimation.fast,
                          curve: BaselineAnimation.curve,
                          width: isActive ? 16 : 6,
                          height: 6,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(3),
                            color: isActive
                                ? BaselineColors.teal
                                : BaselineColors.textSecondary
                                    .atOpacity(0.15),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }

  // ── Variance Banner (#129-131 upgrades) ───────────────

  Widget _buildVarianceBanner() {
    final pair = _currentPair;
    final both =
        pair.roundA.varianceDetected && pair.roundB.varianceDetected;
    final subject = both
        ? 'both subjects'
        : pair.roundA.varianceDetected
            ? 'Subject A'
            : 'Subject B';

    return Container(
      margin: BaselineInsets.screen.copyWith(bottom: BaselineSpacing.sm),
      padding: const EdgeInsets.symmetric(
        horizontal: BaselineSpacing.md,
        vertical: BaselineSpacing.xs + 2,
      ),
      decoration: BoxDecoration(
        color: BaselineColors.amber.atOpacity(0.05),
        borderRadius: BorderRadius.circular(BaselineRadius.sm),
        border: Border(
          left: BorderSide(
            color: BaselineColors.amber.atOpacity(0.5),
            width: 2,
          ),
        ),
      ),
      child: Row(
        children: [
          // #130: Breathing pulse dot.
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: BaselineColors.amber
                  .atOpacity(0.6 + (_ambientSine * 0.25)),
            ),
          ),
          const SizedBox(width: BaselineSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Model variance detected on $subject',
                  style: BaselineTypography.dataSmall.copyWith(
                    color: BaselineColors.amber.atOpacity(0.7),
                    letterSpacing: 0.5,
                  ),
                ),
                // #131: Model attribution hint.
                const SizedBox(height: 2),
                Text(
                  'GP/CL/GR analysis diverged beyond threshold',
                  style: BaselineTypography.dataSmall.copyWith(
                    color: BaselineColors.amber.atOpacity(0.3),
                    fontSize: 7,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
          // #129: Micro-ticks on right edge.
          Column(
            children: List.generate(3, (_) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: Container(
                width: 4,
                height: 1,
                color: BaselineColors.amber.atOpacity(0.15),
              ),
            )),
          ),
        ],
      ),
    );
  }

  // ── Methodology Link (#132-134 upgrades) ──────────────

  Widget _buildMethodologyLink() {
    final p5 = _phase(_kPhase5Start, _kPhase5End);

    return Opacity(
      opacity: p5,
      child: Padding(
        padding: BaselineInsets.screen.copyWith(
          top: BaselineSpacing.sm,
          bottom: BaselineSpacing.md,
        ),
        child: Center(
          child: Semantics(
            button: true,
            excludeSemantics: true,
            label: 'How Crossfire works',
            child: _TapScale(
              scale: 0.98,
              onTap: () {
                HapticUtil.light();
                InfoBottomSheet.show(context, infoKey: 'crossfire');
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: BaselineSpacing.md,
                  vertical: BaselineSpacing.xs,
                ),
                // #133: Terminal border.
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(BaselineRadius.sm),
                  border: Border.all(
                    color: BaselineColors.borderInactive.atOpacity(0.3),
                    width: 0.5,
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Calibration marks left.
                        ...List.generate(3, (i) => Padding(
                          padding: const EdgeInsets.only(right: 2),
                          child: Container(
                            width: 4,
                            height: 1,
                            color: BaselineColors.teal.atOpacity(0.15),
                          ),
                        )),
                        const SizedBox(width: 6),
                        Text(
                          'HOW CROSSFIRE\u2122 WORKS \u2192',
                          style: BaselineTypography.dataSmall.copyWith(
                            color: BaselineColors.textSecondary
                                .atOpacity(0.35),
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(width: 6),
                        // Calibration marks right.
                        ...List.generate(3, (i) => Padding(
                          padding: const EdgeInsets.only(left: 2),
                          child: Container(
                            width: 4,
                            height: 1,
                            color: BaselineColors.teal.atOpacity(0.15),
                          ),
                        )),
                      ],
                    ),
                    // #134: Bottom registration dots.
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: List.generate(3, (_) => Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: Container(
                          width: 2,
                          height: 2,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: BaselineColors.teal.atOpacity(0.08),
                          ),
                        ),
                      )),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// SMALL HELPER WIDGETS
// ═══════════════════════════════════════════════════════════

/// Press-scale feedback widget (replaces AnimatedScale + GestureDetector combo).
class _TapScale extends StatefulWidget {
  const _TapScale({
    required this.child,
    required this.onTap,
    this.scale = 0.98,
  });
  final Widget child;
  final VoidCallback onTap;
  final double scale;

  @override
  State<_TapScale> createState() => _TapScaleState();
}

class _TapScaleState extends State<_TapScale> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      behavior: HitTestBehavior.opaque,
      child: AnimatedScale(
        scale: _pressed ? widget.scale : 1.0,
        duration: const Duration(milliseconds: 100),
        child: widget.child,
      ),
    );
  }
}

/// Classification dot.
class _ClassDot extends StatelessWidget {
  const _ClassDot({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _kClassDotSize,
      height: _kClassDotSize,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }
}

/// #102: Mini reticle corner accent for inline use.
class _MiniReticle extends StatelessWidget {
  const _MiniReticle({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 6,
      height: 6,
      child: CustomPaint(
        painter: _MiniReticlePainter(color: color),
      ),
    );
  }
}

/// Temporal proximity badge with amber for <=24h + #77 breathing.
class _ProximityBadge extends StatelessWidget {
  const _ProximityBadge({
    required this.label,
    this.isUrgent = false,
    this.ambientSine = 0.0,
  });
  final String label;
  final bool isUrgent;
  final double ambientSine;

  @override
  Widget build(BuildContext context) {
    final badgeColor =
        isUrgent ? BaselineColors.amber : BaselineColors.teal;
    // #77: Breathing border opacity on urgent badges.
    final borderOpacity = isUrgent
        ? 0.15 + (ambientSine * 0.10)
        : 0.15;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(BaselineRadius.sm),
        border: Border.all(
          color: badgeColor.atOpacity(borderOpacity),
          width: 1,
        ),
      ),
      child: Text(
        label,
        style: BaselineTypography.dataSmall.copyWith(
          color: badgeColor.atOpacity(0.7),
          fontSize: 7,
          letterSpacing: 1.0,
        ),
      ),
    );
  }
}

/// Subject designation with #85 document ID + #86 border accent.
class _SubjectDesignation extends StatelessWidget {
  const _SubjectDesignation({
    required this.label,
    this.glowIntensity = 0.0,
    this.subjectId,
  });
  final String label;
  final double glowIntensity;
  final String? subjectId;

  @override
  Widget build(BuildContext context) {
    final bgOpacity = 0.06 + (glowIntensity * 0.08);
    // #86: Border accent on ambient peak.
    final borderOpacity = glowIntensity > 0.7
        ? 0.12 * ((glowIntensity - 0.7) / 0.3)
        : 0.0;

    return ExcludeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 20,
            height: 16,
            decoration: BoxDecoration(
              color: BaselineColors.teal.atOpacity(bgOpacity),
              borderRadius: BorderRadius.circular(3),
              border: borderOpacity > 0.001
                  ? Border.all(
                      color: BaselineColors.teal.atOpacity(borderOpacity),
                      width: 0.5,
                    )
                  : null,
            ),
            child: Center(
              child: Text(
                label,
                style: BaselineTypography.dataSmall.copyWith(
                  color: BaselineColors.teal
                      .atOpacity(0.5 + (glowIntensity * 0.2)),
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.0,
                ),
              ),
            ),
          ),
          // #85: Subject document ID sub-label.
          if (subjectId != null) ...[
            const SizedBox(width: 4),
            Text(
              subjectId!.substring(0, math.min(4, subjectId!.length)),
              style: BaselineTypography.dataSmall.copyWith(
                color: BaselineColors.textSecondary.atOpacity(0.15),
                fontSize: 6,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Force-field gradient: teal edge glow pressing inward.
class _ForceFieldGradient extends StatelessWidget {
  const _ForceFieldGradient({
    required this.side,
    required this.intensity,
    required this.child,
  });
  final CrossfirePosition side;
  final double intensity;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isLeft = side == CrossfirePosition.left;
    return CustomPaint(
      foregroundPainter: _ForceFieldPainter(
        isLeft: isLeft,
        intensity: intensity,
        accent: BaselineColors.teal,
      ),
      child: child,
    );
  }
}

/// Single divergence bridge row + collision spark + #100 micro-slide.
class _BridgeRow extends StatelessWidget {
  const _BridgeRow({
    required this.delta,
    required this.progress,
    this.ambientSine = 0.0,
  });
  final MetricDelta delta;
  final double progress;
  final double ambientSine;

  @override
  Widget build(BuildContext context) {
    final isDivergent = delta.isDivergent;

    return Opacity(
      opacity: progress,
      child: Transform.translate(
        // #100: Micro-slide from center outward.
        offset: Offset(0, (1 - progress) * 4),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              // Metric key.
              SizedBox(
                width: 28,
                child: Text(
                  delta.key,
                  style: BaselineTypography.dataSmall.copyWith(
                    color: isDivergent
                        ? BaselineColors.amber.atOpacity(0.7)
                        : BaselineColors.textSecondary,
                    letterSpacing: 0.5,
                  ),
                ),
              ),

              // Dual-facing bar + collision spark.
              Expanded(
                child: SizedBox(
                  height: 18,
                  child: CustomPaint(
                    painter: _BridgeBarPainter(
                      valueA: delta.normalizedA,
                      valueB: delta.normalizedB,
                      accent: BaselineColors.teal,
                      progress: progress,
                      isDivergent: isDivergent,
                      amber: BaselineColors.amber,
                      collisionGlow: isDivergent ? ambientSine : 0.0,
                    ),
                  ),
                ),
              ),

              // Delta label.
              SizedBox(
                width: 36,
                child: Text(
                  '\u0394${delta.display}',
                  textAlign: TextAlign.right,
                  style: BaselineTypography.dataSmall.copyWith(
                    color: isDivergent
                        ? BaselineColors.amber
                        : BaselineColors.textSecondary.atOpacity(0.6),
                    fontWeight:
                        isDivergent ? FontWeight.w600 : FontWeight.w400,
                    fontSize: 8,
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
// CUSTOM PAINTERS
// ═══════════════════════════════════════════════════════════

/// Screen-level chrome: dot grid + mirror axis + sprockets + watermark +
/// DTG stamp + handling marks + protocol stamp + crosshatch +
/// classification hairlines + registration dots + scanline sweep.
class _ScreenChromePainter extends CustomPainter {
  _ScreenChromePainter({
    required this.accent,
    required this.secondary,
    required this.entranceProgress,
    required this.scanlineProgress,
    required this.watermarkTP,
    required this.dtgTP,
    required this.handlingTP,
    required this.protocolTP,
  }) : _dotPaint = Paint()..color = accent.atOpacity(0.025),
       _axisPaint = Paint()
         ..color = accent.atOpacity(_kMirrorAxisOpacity)
         ..strokeWidth = 0.5,
       _sprocketPaint = Paint()..color = secondary.atOpacity(0.04),
       _hairlinePaint = Paint()
         ..color = accent.atOpacity(0.04)
         ..strokeWidth = 1.0,
       _regDotPaint = Paint()..color = accent.atOpacity(0.06),
       _crosshatchPaint = Paint()
         ..color = accent.atOpacity(0.02)
         ..strokeWidth = 0.3,
       _scanBeamPaint = Paint()
         ..color = accent.atOpacity(0.15)
         ..strokeWidth = 1.5;

  final Color accent;
  final Color secondary;
  final double entranceProgress;
  final double scanlineProgress;
  final TextPainter watermarkTP;
  final TextPainter dtgTP;
  final TextPainter handlingTP;
  final TextPainter protocolTP;

  // I-71: Constructor-initialized Paint finals.
  final Paint _dotPaint;
  final Paint _axisPaint;
  final Paint _sprocketPaint;
  final Paint _hairlinePaint;
  final Paint _regDotPaint;
  final Paint _crosshatchPaint;
  final Paint _scanBeamPaint;

  @override
  void paint(Canvas canvas, Size size) {
    // #60 Crosshatch grid.
    for (var x = _kCrosshatchSpacing; x < size.width; x += _kCrosshatchSpacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), _crosshatchPaint);
    }
    for (var y = _kCrosshatchSpacing; y < size.height; y += _kCrosshatchSpacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), _crosshatchPaint);
    }

    // Intel dot grid.
    for (var x = _kDotGridSpacing; x < size.width; x += _kDotGridSpacing) {
      for (var y = _kDotGridSpacing; y < size.height; y += _kDotGridSpacing) {
        canvas.drawCircle(Offset(x, y), _kDotGridRadius, _dotPaint);
      }
    }

    // #58 Mirror axis: dashed center line.
    final cx = size.width / 2;
    for (var y = 0.0; y < size.height; y += 8.0) {
      canvas.drawLine(Offset(cx, y), Offset(cx, y + 4), _axisPaint);
    }

    // #59 Film sprockets: both edges.
    for (var y = _kSprocketSpacing; y < size.height; y += _kSprocketSpacing) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(2, y, _kSprocketWidth, _kSprocketHeight),
          const Radius.circular(1),
        ),
        _sprocketPaint,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
              size.width - _kSprocketWidth - 2, y,
              _kSprocketWidth, _kSprocketHeight),
          const Radius.circular(1),
        ),
        _sprocketPaint,
      );
    }

    // #54 Classification hairlines top + bottom.
    canvas.drawLine(Offset(0, 0), Offset(size.width, 0), _hairlinePaint);
    canvas.drawLine(
      Offset(0, size.height), Offset(size.width, size.height), _hairlinePaint);

    // #55 Registration dots at 4 corners.
    const rInset = 8.0;
    for (final c in [
      Offset(rInset, rInset),
      Offset(size.width - rInset, rInset),
      Offset(rInset, size.height - rInset),
      Offset(size.width - rInset, size.height - rInset),
    ]) {
      canvas.drawCircle(c, 2, _regDotPaint);
    }

    // "DECLASSIFIED" watermark (pre-computed TP).
    canvas.save();
    canvas.translate(size.width / 2, size.height * 0.4);
    canvas.rotate(-0.15);
    watermarkTP.paint(canvas, Offset(-watermarkTP.width / 2, -watermarkTP.height / 2));
    canvas.restore();

    // #57 DTG stamp top-left.
    dtgTP.paint(canvas, const Offset(12, 4));

    // #56 Handling marks bottom-right.
    handlingTP.paint(canvas, Offset(
      size.width - handlingTP.width - 12,
      size.height - handlingTP.height - 8,
    ));

    // #61 COMPARISON PROTOCOL rotated -90 left margin.
    canvas.save();
    canvas.translate(6, size.height * 0.5);
    canvas.rotate(-math.pi / 2);
    protocolTP.paint(canvas, Offset(-protocolTP.width / 2, 0));
    canvas.restore();

    // #62 Scanline sweep on entrance.
    if (scanlineProgress > 0.0 && scanlineProgress < 1.0) {
      final y = scanlineProgress * size.height;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), _scanBeamPaint);
      // Wake trail.
      final wakeH = size.height * 0.08;
      final wakePaint = Paint()
        ..color = accent.atOpacity(0.03);
      canvas.drawRect(
        Rect.fromLTWH(0, y - wakeH, size.width, wakeH),
        wakePaint,
      );
    }
  }

  @override
  bool shouldRepaint(_ScreenChromePainter old) =>
      old.scanlineProgress != scanlineProgress ||
      old.entranceProgress != entranceProgress;
}

/// Header bottom-edge hashmark ruler + top film strip + compound reticle corners.
class _HeaderChromePainter extends CustomPainter {
  _HeaderChromePainter({
    required this.accent,
    required this.progress,
    required this.dtgTP,
  }) : _tickPaint = Paint()
         ..color = accent.atOpacity(0.10)
         ..strokeWidth = 0.5,
       _perfPaint = Paint()..color = accent.atOpacity(0.04),
       _outerPaint = Paint()
         ..color = accent.atOpacity(0.15)
         ..strokeWidth = 1.5
         ..style = PaintingStyle.stroke
         ..strokeCap = StrokeCap.round,
       _innerPaint = Paint()
         ..color = accent.atOpacity(0.08)
         ..strokeWidth = 0.8
         ..style = PaintingStyle.stroke
         ..strokeCap = StrokeCap.round,
       _dotPaint = Paint()..color = accent.atOpacity(0.12);

  final Color accent;
  final double progress;
  final TextPainter dtgTP;

  final Paint _tickPaint;
  final Paint _perfPaint;
  final Paint _outerPaint;
  final Paint _innerPaint;
  final Paint _dotPaint;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress < 0.01) return;

    // #71 Bottom hashmark ruler.
    final tickCount = (size.width / 8).floor();
    for (var i = 0; i <= tickCount; i++) {
      final x = (i / tickCount) * size.width;
      final isMajor = i % 5 == 0;
      final h = isMajor ? 5.0 : 2.0;
      canvas.drawLine(
        Offset(x, size.height),
        Offset(x, size.height - h * progress),
        _tickPaint,
      );
    }

    // #72 Top film perforations.
    for (var x = 12.0; x < size.width - 12; x += 16) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, 0, 6, 2),
          const Radius.circular(1),
        ),
        _perfPaint,
      );
    }

    // #75 Compound reticle corners (I-51).
    _paintCompoundCorner(canvas, Offset(4, 4), 10, 6, false, false);
    _paintCompoundCorner(canvas, Offset(size.width - 4, 4), 10, 6, true, false);
    _paintCompoundCorner(canvas, Offset(4, size.height - 4), 10, 6, false, true);
    _paintCompoundCorner(canvas, Offset(size.width - 4, size.height - 4), 10, 6, true, true);
  }

  void _paintCompoundCorner(Canvas canvas, Offset corner,
      double outerLen, double innerLen, bool flipX, bool flipY) {
    final dx = flipX ? -1.0 : 1.0;
    final dy = flipY ? -1.0 : 1.0;
    canvas.drawLine(corner, corner + Offset(outerLen * dx, 0), _outerPaint);
    canvas.drawLine(corner, corner + Offset(0, outerLen * dy), _outerPaint);
    final inset = Offset(4 * dx, 4 * dy);
    canvas.drawLine(
        corner + inset, corner + inset + Offset(innerLen * dx, 0), _innerPaint);
    canvas.drawLine(
        corner + inset, corner + inset + Offset(0, innerLen * dy), _innerPaint);
    canvas.drawCircle(corner + Offset(2 * dx, 2 * dy), 1.0, _dotPaint);
  }

  @override
  bool shouldRepaint(_HeaderChromePainter old) => old.progress != progress;
}

/// Temporal timeline with #80 compound markers + #81 comet trail.
/// C2 fix: Uses pre-computed TextPainters (no ParagraphBuilder in paint).
class _TemporalTimelinePainter extends CustomPainter {
  _TemporalTimelinePainter({
    required this.accent,
    required this.secondary,
    required this.progress,
    required this.dateATP,
    required this.dateBTP,
    required this.positionA,
    required this.positionB,
    this.ambientPhase = 0.0,
  }) : _trackPaint = Paint()
         ..color = secondary.atOpacity(0.08)
         ..strokeWidth = 1.0,
       _activePaint = Paint()
         ..color = accent.atOpacity(0.4)
         ..strokeWidth = 1.5
         ..style = PaintingStyle.stroke
         ..strokeCap = StrokeCap.round,
       _dashPaint = Paint()
         ..color = accent.atOpacity(0.12)
         ..strokeWidth = 1.0
         ..style = PaintingStyle.stroke,
       _travelerPaint = Paint()..color = accent.atOpacity(0.45),
       _trailPaint = Paint()..color = accent.atOpacity(0.10);

  final Color accent;
  final Color secondary;
  final double progress;
  final TextPainter dateATP;
  final TextPainter dateBTP;
  final double positionA;
  final double positionB;
  final double ambientPhase;

  final Paint _trackPaint;
  final Paint _activePaint;
  final Paint _dashPaint;
  final Paint _travelerPaint;
  final Paint _trailPaint;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress < 0.01) return;

    final midY = size.height / 2;
    final axStart = size.width * positionA;
    final axEnd = size.width * positionB;

    // Track line.
    canvas.drawLine(Offset(0, midY), Offset(size.width, midY), _trackPaint);

    // Proximity wire: animated dashes.
    if (progress > 0.5) {
      final dashOffset =
          ambientPhase * (_kProximityDashLength + _kProximityDashGap);
      var x = axStart + dashOffset;
      while (x < axEnd) {
        final end = (x + _kProximityDashLength).clamp(axStart, axEnd);
        canvas.drawLine(Offset(x, midY), Offset(end, midY), _dashPaint);
        x += _kProximityDashLength + _kProximityDashGap;
      }
    }

    // Active segment.
    final visibleEnd = axStart + (axEnd - axStart) * progress;
    canvas.drawLine(Offset(axStart, midY), Offset(visibleEnd, midY), _activePaint);

    // #80: Compound marker A: ring + inner dot + pulse halo.
    final pulseA = Paint()..color = accent.atOpacity(0.06 * progress);
    canvas.drawCircle(Offset(axStart, midY), _kTimelinePulseRadius + 2, pulseA);
    canvas.drawCircle(Offset(axStart, midY), _kTimelinePulseRadius,
        Paint()..color = accent.atOpacity(0.08 * progress));
    // Ring.
    canvas.drawCircle(Offset(axStart, midY), _kTimelineMarkerRadius + 1,
        Paint()
          ..color = accent.atOpacity(0.3 * progress)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8);
    // Core dot.
    canvas.drawCircle(Offset(axStart, midY), _kTimelineMarkerRadius,
        Paint()..color = accent.atOpacity(0.7 * progress));

    // #80: Compound marker B.
    if (progress > 0.5) {
      final bProgress = ((progress - 0.5) * 2).clamp(0.0, 1.0);
      canvas.drawCircle(Offset(axEnd, midY), _kTimelinePulseRadius + 2,
          Paint()..color = accent.atOpacity(0.06 * bProgress));
      canvas.drawCircle(Offset(axEnd, midY), _kTimelinePulseRadius,
          Paint()..color = accent.atOpacity(0.08 * bProgress));
      canvas.drawCircle(Offset(axEnd, midY), _kTimelineMarkerRadius + 1,
          Paint()
            ..color = accent.atOpacity(0.3 * bProgress)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.8);
      canvas.drawCircle(Offset(axEnd, midY), _kTimelineMarkerRadius,
          Paint()..color = accent.atOpacity(0.7 * bProgress));
    }

    // #81: Pulse traveler with comet trail.
    if (progress >= 1.0) {
      final travelX = axStart + (axEnd - axStart) * ambientPhase;
      // Comet trail: 3 trailing dots with decreasing opacity.
      final span = axEnd - axStart;
      for (var i = _kCometTrailCount; i >= 1; i--) {
        final trailPhase = (ambientPhase - (i * 0.04)).clamp(0.0, 1.0);
        final trailX = axStart + span * trailPhase;
        final trailOpacity = 0.08 * (1.0 - (i / (_kCometTrailCount + 1)));
        canvas.drawCircle(Offset(trailX, midY), _kTravelerRadius * 0.7,
            Paint()..color = accent.atOpacity(trailOpacity));
      }
      // Main traveler.
      canvas.drawCircle(Offset(travelX, midY), _kTravelerRadius, _travelerPaint);
      // Soft glow (solid alpha layers, no MaskFilter).
      canvas.drawCircle(Offset(travelX, midY), _kTravelerRadius + 4, _trailPaint);
      canvas.drawCircle(Offset(travelX, midY), _kTravelerRadius + 2,
          Paint()..color = accent.atOpacity(0.15));
    }

    // Date labels (pre-computed TPs, C2 fix).
    if (dateATP.text != null) {
      canvas.save();
      canvas.translate(axStart - dateATP.width / 2, midY + 10);
      final alphaPaint = Paint()..color = Color.fromRGBO(0, 0, 0, progress);
      canvas.saveLayer(Rect.fromLTWH(0, 0, dateATP.width, dateATP.height), alphaPaint);
      dateATP.paint(canvas, Offset.zero);
      canvas.restore();
      canvas.restore();
    }
    if (progress > 0.5 && dateBTP.text != null) {
      final bOp = ((progress - 0.5) * 2).clamp(0.0, 1.0);
      canvas.save();
      canvas.translate(axEnd - dateBTP.width / 2, midY + 10);
      final alphaPaint = Paint()..color = Color.fromRGBO(0, 0, 0, bOp);
      canvas.saveLayer(Rect.fromLTWH(0, 0, dateBTP.width, dateBTP.height), alphaPaint);
      dateBTP.paint(canvas, Offset.zero);
      canvas.restore();
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_TemporalTimelinePainter old) =>
      old.progress != progress || old.ambientPhase != ambientPhase;
}

/// Comparison frame: compound reticles + corner glow + scanline + exhibit stamp.
class _ComparisonFramePainter extends CustomPainter {
  _ComparisonFramePainter({
    required this.accent,
    required this.secondary,
    required this.cornerGlowProgress,
    required this.scanlineProgress,
    required this.ambientPhase,
    required this.pairIndex,
    required this.exhibitTP,
  }) : _outerPaint = Paint()
         ..color = accent.atOpacity(0.15)
         ..strokeWidth = 1.5
         ..style = PaintingStyle.stroke
         ..strokeCap = StrokeCap.round,
       _innerPaint = Paint()
         ..color = accent.atOpacity(0.08)
         ..strokeWidth = 0.8
         ..style = PaintingStyle.stroke
         ..strokeCap = StrokeCap.round,
       _cornerDotPaint = Paint()..color = accent.atOpacity(0.12);

  final Color accent;
  final Color secondary;
  final double cornerGlowProgress;
  final double scanlineProgress;
  final double ambientPhase;
  final int pairIndex;
  final TextPainter exhibitTP;
  final Paint _outerPaint;
  final Paint _innerPaint;
  final Paint _cornerDotPaint;

  @override
  void paint(Canvas canvas, Size size) {
    // Compound reticle corners (I-51 upgrade).
    _paintCompoundCorner(canvas, Offset(_kReticleInset, _kReticleInset),
        _kReticleArm, 8, false, false);
    _paintCompoundCorner(canvas,
        Offset(size.width - _kReticleInset, _kReticleInset),
        _kReticleArm, 8, true, false);
    _paintCompoundCorner(canvas,
        Offset(_kReticleInset, size.height - _kReticleInset),
        _kReticleArm, 8, false, true);
    _paintCompoundCorner(canvas,
        Offset(size.width - _kReticleInset, size.height - _kReticleInset),
        _kReticleArm, 8, true, true);

    // Corner glow: layered solid alpha (no MaskFilter).
    if (cornerGlowProgress > 0.01) {
      final i = _kReticleInset;
      for (final c in [
        Offset(i, i),
        Offset(size.width - i, i),
        Offset(i, size.height - i),
        Offset(size.width - i, size.height - i),
      ]) {
        canvas.drawCircle(c, 6,
            Paint()..color = accent.atOpacity(0.04 * cornerGlowProgress));
        canvas.drawCircle(c, 4,
            Paint()..color = accent.atOpacity(0.08 * cornerGlowProgress));
        canvas.drawCircle(c, 2.5,
            Paint()..color = accent.atOpacity(0.15 * cornerGlowProgress));
      }
    }

    // Scanline sweep.
    if (scanlineProgress > 0.0 && scanlineProgress < 1.0) {
      final y = scanlineProgress * size.height;
      final beam = Paint()
        ..color = accent.atOpacity(0.15)
        ..strokeWidth = 1.5;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), beam);
    }

    // Exhibit stamp (C2 fix: pre-computed TP).
    if (cornerGlowProgress > 0.5 && exhibitTP.text != null) {
      canvas.save();
      canvas.translate(size.width - 10, size.height * 0.5);
      canvas.rotate(-math.pi / 2);
      final alphaPaint = Paint()
        ..color = Color.fromRGBO(0, 0, 0, cornerGlowProgress);
      canvas.saveLayer(
        Rect.fromLTWH(-exhibitTP.width / 2, 0,
            exhibitTP.width, exhibitTP.height),
        alphaPaint,
      );
      exhibitTP.paint(canvas, Offset(-exhibitTP.width / 2, 0));
      canvas.restore();
      canvas.restore();
    }
  }

  void _paintCompoundCorner(Canvas canvas, Offset corner,
      double outerLen, double innerLen, bool flipX, bool flipY) {
    final dx = flipX ? -1.0 : 1.0;
    final dy = flipY ? -1.0 : 1.0;
    canvas.drawLine(corner, corner + Offset(outerLen * dx, 0), _outerPaint);
    canvas.drawLine(corner, corner + Offset(0, outerLen * dy), _outerPaint);
    final inset = Offset(4 * dx, 4 * dy);
    canvas.drawLine(
        corner + inset, corner + inset + Offset(innerLen * dx, 0), _innerPaint);
    canvas.drawLine(
        corner + inset, corner + inset + Offset(0, innerLen * dy), _innerPaint);
    canvas.drawCircle(corner + Offset(2 * dx, 2 * dy), 1.0, _cornerDotPaint);
  }

  @override
  bool shouldRepaint(_ComparisonFramePainter old) =>
      old.cornerGlowProgress != cornerGlowProgress ||
      old.scanlineProgress != scanlineProgress ||
      old.ambientPhase != ambientPhase ||
      old.pairIndex != pairIndex;
}

/// Convergence spine with #88 enhanced halos + #89 breathing opacity.
class _ConvergenceSpinePainter extends CustomPainter {
  _ConvergenceSpinePainter({
    required this.accent,
    required this.particleColor,
    required this.progress,
    required this.particlePhase,
    this.ambientSine = 0.0,
  });

  final Color accent;
  final Color particleColor;
  final double progress;
  final double particlePhase;
  final double ambientSine;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress < 0.01) return;

    final cx = size.width / 2;
    final visibleH = size.height * progress;

    // #89: Spine line with breathing opacity.
    final spineOpacity = 0.10 + (ambientSine * 0.04);
    canvas.drawLine(Offset(cx, 0), Offset(cx, visibleH),
        Paint()
          ..color = accent.atOpacity(spineOpacity)
          ..strokeWidth = _kSpineWidth);

    // #88: Enhanced junction nodes at 20%, 40%, 60%, 80%.
    final baseOpacity = 0.25 + (ambientSine * 0.15);
    final junctionPaint = Paint()
      ..color = accent.atOpacity(baseOpacity * progress);
    final haloPaint = Paint()
      ..color = accent.atOpacity(0.06 * progress);

    for (final frac in [0.2, 0.4, 0.6, 0.8]) {
      final y = size.height * frac;
      if (y > visibleH) break;
      // #88: Extended halo layers on ambient peak.
      if (ambientSine > 0.7) {
        final flashOpacity = 0.08 * (ambientSine - 0.7) / 0.3 * progress;
        canvas.drawCircle(Offset(cx, y), _kSpineJunctionRadius + 10,
            Paint()..color = accent.atOpacity(flashOpacity * 0.15));
        canvas.drawCircle(Offset(cx, y), _kSpineJunctionRadius + 8,
            Paint()..color = accent.atOpacity(flashOpacity * 0.3));
        canvas.drawCircle(Offset(cx, y), _kSpineJunctionRadius + 6,
            Paint()..color = accent.atOpacity(flashOpacity));
      }
      canvas.drawCircle(
          Offset(cx, y), _kSpineJunctionRadius + 4, haloPaint);
      canvas.drawCircle(
          Offset(cx, y), _kSpineJunctionRadius + 1.5, haloPaint);
      canvas.drawCircle(
          Offset(cx, y), _kSpineJunctionRadius, junctionPaint);
    }

    // Data-flow particles.
    if (progress >= 1.0) {
      final particlePaint = Paint()
        ..color = particleColor.atOpacity(0.25);
      for (var i = 0; i < _kSpineParticleCount; i++) {
        final phase =
            (particlePhase + (i / _kSpineParticleCount)) % 1.0;
        final y = size.height * (1.0 - phase);
        final r = 1.0 + (0.5 * math.sin(phase * math.pi));
        canvas.drawCircle(Offset(cx, y), r, particlePaint);
      }
    }
  }

  @override
  bool shouldRepaint(_ConvergenceSpinePainter old) =>
      old.progress != progress ||
      old.particlePhase != particlePhase ||
      old.ambientSine != ambientSine;
}

/// Force-field gradient: 3-segment solid Paint (I-86 compliant, no shader).
class _ForceFieldPainter extends CustomPainter {
  _ForceFieldPainter({
    required this.isLeft,
    required this.intensity,
    required this.accent,
  }) : _seg1 = Paint()..color = accent.atOpacity(0.04),
       _seg2 = Paint()..color = accent.atOpacity(0.025),
       _seg3 = Paint()..color = accent.atOpacity(0.01);

  final bool isLeft;
  final double intensity;
  final Color accent;

  final Paint _seg1;
  final Paint _seg2;
  final Paint _seg3;

  @override
  void paint(Canvas canvas, Size size) {
    if (intensity < 0.01) return;

    final segW = _kForceFieldExtent / 3;
    for (var i = 0; i < 3; i++) {
      final paint = i == 0 ? _seg1 : (i == 1 ? _seg2 : _seg3);
      final x = isLeft
          ? segW * i
          : size.width - _kForceFieldExtent + segW * i;
      canvas.drawRect(
        Rect.fromLTWH(x, 0, segW, size.height),
        Paint()..color = paint.color.atOpacity(
            paint.color.a * intensity),
      );
    }

    // #87: Force-field inner-edge micro-dots (data bus).
    final edgeX = isLeft ? _kForceFieldExtent : size.width - _kForceFieldExtent;
    for (var y = 8.0; y < size.height; y += 12.0) {
      canvas.drawCircle(Offset(edgeX, y), 0.5,
          Paint()..color = accent.atOpacity(0.06 * intensity));
    }
  }

  @override
  bool shouldRepaint(_ForceFieldPainter old) => old.intensity != intensity;
}

/// Cross-examination ruler ticks + #99 quartile labels.
class _CrossExamRulerPainter extends CustomPainter {
  _CrossExamRulerPainter({
    required this.accent,
    required this.progress,
  }) : _tickPaint = Paint()
         ..color = accent.atOpacity(0.06)
         ..strokeWidth = 0.5;

  final Color accent;
  final double progress;

  final Paint _tickPaint;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress < 0.01) return;

    final tickCount = (size.width / 6).floor();
    for (var i = 0; i <= tickCount; i++) {
      final x = (i / tickCount) * size.width;
      final isMajor = i % 8 == 0;
      final h = isMajor ? 4.0 : 1.5;
      canvas.drawLine(
        Offset(x, size.height),
        Offset(x, size.height - h * progress),
        _tickPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_CrossExamRulerPainter old) => old.progress != progress;
}

/// Delta orb ring gauge + #117 measurement ticks.
class _DeltaOrbPainter extends CustomPainter {
  _DeltaOrbPainter({
    required this.fillRatio,
    required this.color,
    required this.progress,
    required this.trackColor,
  }) : _trackPaint = Paint()
         ..color = trackColor.atOpacity(0.3)
         ..strokeWidth = _kDeltaRingStroke
         ..style = PaintingStyle.stroke;

  final double fillRatio;
  final Color color;
  final double progress;
  final Color trackColor;

  final Paint _trackPaint;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - _kDeltaRingStroke) / 2;

    canvas.drawCircle(center, radius, _trackPaint);

    // #117: Measurement ticks around ring outer edge.
    final tickPaint = Paint()
      ..color = trackColor.atOpacity(0.15 * progress)
      ..strokeWidth = 0.5;
    for (var i = 0; i < _kOrbTickCount; i++) {
      final angle = (i / _kOrbTickCount) * 2 * math.pi - math.pi / 2;
      final isMajor = i % 6 == 0;
      final innerR = radius + (_kDeltaRingStroke / 2) + 1;
      final outerR = innerR + (isMajor ? 3.0 : 1.5);
      canvas.drawLine(
        Offset(center.dx + innerR * math.cos(angle),
               center.dy + innerR * math.sin(angle)),
        Offset(center.dx + outerR * math.cos(angle),
               center.dy + outerR * math.sin(angle)),
        tickPaint,
      );
    }

    final sweep = fillRatio * progress * 2 * math.pi;
    if (sweep > 0.01) {
      final fillPaint = Paint()
        ..color = color.atOpacity(0.7 * progress)
        ..strokeWidth = _kDeltaRingStroke
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        sweep,
        false,
        fillPaint,
      );

      // Glow behind fill (layered solid alpha, no MaskFilter).
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        sweep,
        false,
        Paint()
          ..color = color.atOpacity(0.08 * progress)
          ..strokeWidth = _kDeltaRingStroke + 8
          ..style = PaintingStyle.stroke,
      );
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        sweep,
        false,
        Paint()
          ..color = color.atOpacity(0.12 * progress)
          ..strokeWidth = _kDeltaRingStroke + 4
          ..style = PaintingStyle.stroke,
      );
    }
  }

  @override
  bool shouldRepaint(_DeltaOrbPainter old) =>
      old.fillRatio != fillRatio || old.progress != progress;
}

/// Verdict flash: radial pulse ring outward.
class _VerdictFlashPainter extends CustomPainter {
  _VerdictFlashPainter({
    required this.color,
    required this.progress,
  }) : _ringPaint = Paint()
         ..strokeWidth = 2.0
         ..style = PaintingStyle.stroke;

  final Color color;
  final double progress;

  final Paint _ringPaint;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress < 0.01 || progress > 0.99) return;

    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2;
    final currentRadius =
        _kDeltaOrbSize / 2 + (maxRadius - _kDeltaOrbSize / 2) * progress;

    _ringPaint.color = color.atOpacity(0.20 * (1.0 - progress));
    canvas.drawCircle(center, currentRadius, _ringPaint);

    // Soft glow (solid alpha layers, no MaskFilter).
    canvas.drawCircle(center, currentRadius + 2,
        Paint()..color = color.atOpacity(0.04 * (1.0 - progress)));
    canvas.drawCircle(center, currentRadius + 4,
        Paint()..color = color.atOpacity(0.02 * (1.0 - progress)));
  }

  @override
  bool shouldRepaint(_VerdictFlashPainter old) => old.progress != progress;
}

/// Verdict seal: concentric outer ring + #115 compass ticks + #116 8-point dots.
class _VerdictSealPainter extends CustomPainter {
  _VerdictSealPainter({
    required this.color,
    required this.progress,
    this.ambientSine = 0.0,
  }) : _sealPaint = Paint()
         ..strokeWidth = _kVerdictSealStroke
         ..style = PaintingStyle.stroke;

  final Color color;
  final double progress;
  final double ambientSine;

  final Paint _sealPaint;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress < 0.01) return;

    final center = Offset(size.width / 2, size.height / 2);

    _sealPaint.color = color.atOpacity(0.12 * progress);
    canvas.drawCircle(center, _kVerdictSealRadius - 2, _sealPaint);

    // #115: Compass tick marks at 8 points.
    if (progress > 0.3) {
      final tickOpacity = ((progress - 0.3) / 0.7).clamp(0.0, 1.0);
      final tickPaint = Paint()
        ..color = color.atOpacity(0.10 * tickOpacity)
        ..strokeWidth = 0.5;
      final r = _kVerdictSealRadius - 2;
      for (var i = 0; i < _kCompassTickCount; i++) {
        final angle = (i / _kCompassTickCount) * 2 * math.pi;
        final innerR = r - 3;
        canvas.drawLine(
          Offset(center.dx + innerR * math.cos(angle),
                 center.dy + innerR * math.sin(angle)),
          Offset(center.dx + r * math.cos(angle),
                 center.dy + r * math.sin(angle)),
          tickPaint,
        );
      }
    }

    // #116: Registration dots at 8 compass points (upgraded from 4).
    if (progress > 0.5) {
      final dotOpacity = ((progress - 0.5) * 2).clamp(0.0, 1.0);
      // Subtle ambient breathing on dots.
      final breathOpacity = 0.20 + (ambientSine * 0.08);
      final dotPaint = Paint()
        ..color = color.atOpacity(breathOpacity * dotOpacity);
      final r = _kVerdictSealRadius - 2;
      for (var i = 0; i < 8; i++) {
        final angle = (i / 8) * 2 * math.pi;
        canvas.drawCircle(
          Offset(
            center.dx + r * math.cos(angle),
            center.dy + r * math.sin(angle),
          ),
          i % 2 == 0 ? 1.5 : 1.0,
          dotPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_VerdictSealPainter old) =>
      old.progress != progress || old.ambientSine != ambientSine;
}

/// Dual-facing bridge bar + collision spark.
class _BridgeBarPainter extends CustomPainter {
  _BridgeBarPainter({
    required this.valueA,
    required this.valueB,
    required this.accent,
    required this.progress,
    required this.isDivergent,
    required this.amber,
    this.collisionGlow = 0.0,
  }) : _trackPaint = Paint()..color = accent.atOpacity(0.06);

  final double valueA;
  final double valueB;
  final Color accent;
  final double progress;
  final bool isDivergent;
  final Color amber;
  final double collisionGlow;

  final Paint _trackPaint;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress < 0.01) return;

    final mid = size.width / 2;
    const barH = 3.0;
    final barY = (size.height - barH) / 2;

    // Track.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, barY, size.width, barH),
        const Radius.circular(1.5),
      ),
      _trackPaint,
    );

    // A-side: 3-segment solid Paint (I-86, no gradient shader).
    final aWidth = (mid * valueA * progress).clamp(0.0, mid);
    if (aWidth > 0.5) {
      final segW = aWidth / 3;
      for (var i = 0; i < 3; i++) {
        final opacity = (0.65 - (i * 0.12)) * progress;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(mid - aWidth + segW * i, barY, segW, barH),
            const Radius.circular(1.5),
          ),
          Paint()..color = accent.atOpacity(opacity),
        );
      }
    }

    // B-side: 3-segment solid Paint.
    final bWidth = (mid * valueB * progress).clamp(0.0, mid);
    if (bWidth > 0.5) {
      final segW = bWidth / 3;
      for (var i = 0; i < 3; i++) {
        final opacity = (0.65 - (i * 0.12)) * progress;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(mid + segW * (2 - i), barY, segW, barH),
            const Radius.circular(1.5),
          ),
          Paint()..color = accent.atOpacity(opacity),
        );
      }
    }

    // Center divider.
    canvas.drawLine(
      Offset(mid, barY - 2),
      Offset(mid, barY + barH + 2),
      Paint()
        ..color = accent.atOpacity(0.25 * progress)
        ..strokeWidth = 0.5,
    );

    // Collision spark (solid alpha, no MaskFilter).
    if (isDivergent && progress > 0.5) {
      final cy = size.height / 2;
      // Static glow layers.
      canvas.drawCircle(Offset(mid, cy), 8,
          Paint()..color = amber.atOpacity(0.04 * progress));
      canvas.drawCircle(Offset(mid, cy), 6,
          Paint()..color = amber.atOpacity(0.08 * progress));
      canvas.drawCircle(Offset(mid, cy), 4,
          Paint()..color = amber.atOpacity(0.15 * progress));

      // Breathing pulse.
      if (collisionGlow > 0.01) {
        final pulseR = 5.0 + (collisionGlow * 4.0);
        canvas.drawCircle(Offset(mid, cy), pulseR + 3,
            Paint()..color = amber.atOpacity(0.03 * collisionGlow));
        canvas.drawCircle(Offset(mid, cy), pulseR,
            Paint()..color = amber.atOpacity(0.10 * collisionGlow));

        // Micro spark dot at peak.
        if (collisionGlow > 0.85) {
          canvas.drawCircle(Offset(mid, cy), 1.5,
              Paint()..color = amber.atOpacity(
                  0.45 * (collisionGlow - 0.85) / 0.15));
        }
      }
    }
  }

  @override
  bool shouldRepaint(_BridgeBarPainter old) =>
      old.valueA != valueA ||
      old.valueB != valueB ||
      old.progress != progress ||
      old.collisionGlow != collisionGlow;
}

/// #102: Mini reticle painter for inline use.
class _MiniReticlePainter extends CustomPainter {
  _MiniReticlePainter({required this.color})
      : _paint = Paint()
          ..color = color
          ..strokeWidth = 0.8
          ..style = PaintingStyle.stroke;

  final Color color;
  final Paint _paint;

  @override
  void paint(Canvas canvas, Size size) {
    // Top-left corner only, scaled to 6x6.
    canvas.drawLine(Offset(0, 0), Offset(size.width * 0.5, 0), _paint);
    canvas.drawLine(Offset(0, 0), Offset(0, size.height * 0.5), _paint);
    // Bottom-right corner.
    canvas.drawLine(Offset(size.width, size.height),
        Offset(size.width * 0.5, size.height), _paint);
    canvas.drawLine(Offset(size.width, size.height),
        Offset(size.width, size.height * 0.5), _paint);
  }

  @override
  bool shouldRepaint(_MiniReticlePainter old) => old.color != color;
}
