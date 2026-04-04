/// F4.10 -- Framing Radar™ Screen (Phased Array Radar Console)
///
/// BASELINE's proprietary 5-axis framing analysis visualization.
/// Shows how a figure frames their speech across 5 rhetorical
/// categories, rendered as an animated pentagon radar chart.
///
/// Concept: CIC radar station. The pentagon IS the phased array display.
/// A sweep beam acquires each axis on entry. Range rings mark measurement
/// depth. Bearing ticks frame the scope. Signal acquisition pips show
/// detection strength per axis. Screen breathes with perpetual sweep.
///
/// 5 AXES (from A1 schema + A3 prompts, LOCKED):
/// 1. Adversarial / Oppositional (bearing 000)
/// 2. Problem Identification (bearing 072)
/// 3. Commitment / Forward-Looking (bearing 144)
/// 4. Justification / Reactive (bearing 216)
/// 5. Imperative / Directive (bearing 288)
///
/// Path: lib/screens/framing_radar.dart
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:go_router/go_router.dart';

import 'package:baseline_app/config/constants.dart';
import 'package:baseline_app/config/theme.dart';
import 'package:baseline_app/config/routes.dart';
import 'package:baseline_app/models/figure.dart';
import 'package:baseline_app/models/framing.dart';
import 'package:baseline_app/services/entitlement_service.dart';
import 'package:baseline_app/services/framing_service.dart';
import 'package:baseline_app/services/figures_service.dart';
import 'package:baseline_app/utils/export_util.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:baseline_app/providers/tier_provider.dart';
import 'package:baseline_app/utils/haptic_util.dart';
import 'package:baseline_app/widgets/baseline_icons.dart';
import 'package:baseline_app/widgets/info_bottom_sheet.dart';
import 'package:baseline_app/widgets/measured_by_row.dart';
import 'package:baseline_app/widgets/shimmer_loading.dart';
import 'package:baseline_app/widgets/disclaimer_footer.dart';
import 'package:baseline_app/widgets/rate_app_popup.dart';
import 'package:baseline_app/widgets/soft_paywall_popup.dart';
import 'package:baseline_app/widgets/error_state.dart';
import 'package:baseline_app/models/trends.dart';
import 'package:baseline_app/config/tier_feature_map.dart';

// ═══════════════════════════════════════════════════════════
// LAYOUT CONSTANTS
// ═══════════════════════════════════════════════════════════

/// Number of pentagon axes. LOCKED AT 5. NEVER 6.
const int _kAxisCount = 5;

/// Number of concentric range rings.
const int _kGridRings = 3;

/// Radar chart size (diameter) as fraction of screen width.
const double _kRadarSizeFraction = 0.78;

/// Maximum radar diameter.
const double _kRadarMaxSize = 340.0;

/// Minimum radar diameter.
const double _kRadarMinSize = 240.0;

/// Label offset distance from vertex.
const double _kLabelOffset = 32.0;

/// Accent line height.
const double _kAccentLineHeight = 2.0;

/// Icon touch target.
const double _kIconTouchTarget = 44.0;

/// Period pill height.
const double _kPillHeight = 36.0;

/// Period pill border radius.
const double _kPillRadius = 18.0;

/// Action button size.
const double _kActionButtonSize = 44.0;

/// Border width for interactive elements.
const double _kBorderWidth = 2.0;

/// Border opacity.
const double _kBorderOpacity = 0.5;

/// Signal pip bar width.
const double _kPipWidth = 2.0;

/// Signal pip bar max height.
const double _kPipMaxHeight = 10.0;

/// Number of signal pips per axis.
const int _kPipCount = 5;

/// Press-scale constants.
const double _kScaleCard = 0.98;
const double _kScaleChip = 0.95;

/// Detail pill animation duration.
const Duration _kPillSpringDuration = Duration(milliseconds: 300);

/// Pentagon polygon animation duration.
const Duration _kAnimDuration = Duration(milliseconds: 400);

/// Period toggle color transition.
const Duration _kColorTransitionDuration = Duration(milliseconds: 200);

/// Entrance master duration.
const Duration _kEntranceDuration = Duration(milliseconds: 1000);

/// Count-up animation duration.
const Duration _kCountUpDuration = Duration(milliseconds: 400);

/// Ambient sweep arm full rotation.
const Duration _kAmbientSweepDuration = Duration(milliseconds: 12000);

/// Accent glow pulse duration.
const Duration _kGlowPulseDuration = Duration(milliseconds: 4000);

/// Pentagon edge traveling dot period.
const Duration _kEdgeDotDuration = Duration(milliseconds: 3000);

/// Bearing indices for each axis.
const List<String> _kBearings = ['000', '072', '144', '216', '288'];

/// Track designations (🍒 116).
const List<String> _kTrackDesignations = [
  'T-01', 'T-02', 'T-03', 'T-04', 'T-05',
];

/// Entitlement error codes that route to PAYWALL.
const Set<String> _kPaywallErrorCodes = {'not_entitled', 'feature_gated'};

/// Entitlement error codes that show a temporary message.
const Set<String> _kTemporaryErrorCodes = {'rate_limited', 'feature_disabled'};

// ═══════════════════════════════════════════════════════════
// TAP SCALE (press-scale feedback)
// ═══════════════════════════════════════════════════════════

class _TapScale extends StatefulWidget {
  const _TapScale({
    required this.child,
    required this.onTap,
    this.scale = _kScaleCard,
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

// ═══════════════════════════════════════════════════════════
// FRAMING RADAR SCREEN
// ═══════════════════════════════════════════════════════════

class FramingRadarScreen extends StatefulWidget {
  const FramingRadarScreen({
    super.key,
    required this.figureId,
  });

  final String figureId;

  @override
  State<FramingRadarScreen> createState() => _FramingRadarScreenState();
}

class _FramingRadarScreenState extends State<FramingRadarScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  // ── State ────────────────────────────────────────────────
  bool _isLoading = true;
  String? _errorMessage;
  String? _errorCode;
  bool _didRouteToPaywall = false;
  bool _entranceComplete = false;
  bool _shiftHapticFired = false;
  String? _figureName;
  FramingDistribution? _radarData;
  TrendPeriod _selectedPeriod = TrendPeriod.ninetyDays;
  int? _selectedAxisIndex;

  // ── Timer Management (I-11) ─────────────────────────────
  final List<Timer> _pendingTimers = [];

  // ── Animation Controllers ────────────────────────────────

  /// Polygon vertex interpolation.
  late final AnimationController _animCtrl;
  late final CurvedAnimation _animCurve;

  /// Entrance orchestration.
  late final AnimationController _entranceCtrl;

  /// CIC sweep beam (entrance: one 360° rotation).
  late final AnimationController _sweepCtrl;

  /// Ambient radar sweep arm (post-entrance, infinite).
  late final AnimationController _ambientSweepCtrl;

  /// Count-up for statement count (150.10).
  late final AnimationController _countUpCtrl;
  late final CurvedAnimation _countUpCurve;

  /// Accent glow pulse.
  late final AnimationController _glowPulseCtrl;

  /// Pentagon edge traveling dot.
  late final AnimationController _edgeDotCtrl;

  /// A-3 detail pill spring.
  late final AnimationController _pillCtrl;
  late final CurvedAnimation _pillCurve;

  // ── Export ────────────────────────────────────────────────
  final GlobalKey _exportKey = GlobalKey();

  // ── Polygon Transition ───────────────────────────────────
  List<double> _fromValues = List.filled(_kAxisCount, 0.0);
  List<double> _toValues = List.filled(_kAxisCount, 0.0);
  List<double> _fromPrevValues = List.filled(_kAxisCount, 0.0);
  List<double> _toPrevValues = List.filled(_kAxisCount, 0.0);

  // ── Pre-computed geometry (I-80) ─────────────────────────
  List<List<Offset>>? _cachedDashedSegments;

  // ── Pre-computed TextPainters (I-84) ─────────────────────
  TextPainter? _fouoPainter;
  TextPainter? _serialPainter;
  TextPainter? _classHeaderPainter;
  List<TextPainter>? _ringLabelPainters;
  List<TextPainter>? _bearingPainters;
  List<TextPainter>? _trackDesignPainters;
  TextPainter? _brgReadoutPainter;

  // W1: Pre-computed axis label TPs (eliminates 5x layout() per paint frame).
  List<TextPainter>? _axisLabelPainters;

  // ── Accessibility ────────────────────────────────────────
  bool _reduceMotion = false;
  bool _wasReduced = false;

  // ── Cached layout ────────────────────────────────────────
  double _cachedScreenWidth = 0;
  TextScaler _cachedTextScaler = TextScaler.noScaling;

  // ── Lifecycle ────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _animCtrl = AnimationController(
      vsync: this, duration: _kAnimDuration,
    );
    _animCurve = CurvedAnimation(
      parent: _animCtrl, curve: Curves.easeOutCubic,
    );

    _entranceCtrl = AnimationController(
      vsync: this, duration: _kEntranceDuration,
    );

    _sweepCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 600),
    );

    _ambientSweepCtrl = AnimationController(
      vsync: this, duration: _kAmbientSweepDuration,
    );

    _countUpCtrl = AnimationController(
      vsync: this, duration: _kCountUpDuration,
    );
    _countUpCurve = CurvedAnimation(
      parent: _countUpCtrl, curve: Curves.easeOut,
    );

    _glowPulseCtrl = AnimationController(
      vsync: this, duration: _kGlowPulseDuration,
    );

    _edgeDotCtrl = AnimationController(
      vsync: this, duration: _kEdgeDotDuration,
    );

    _pillCtrl = AnimationController(
      vsync: this, duration: _kPillSpringDuration,
    );
    _pillCurve = CurvedAnimation(
      parent: _pillCtrl, curve: Curves.elasticOut,
    );

    _loadData();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    _wasReduced = _reduceMotion;

    final mq = MediaQuery.of(context);
    final newWidth = mq.size.width;
    final newScaler = mq.textScaler;

    if (newWidth != _cachedScreenWidth ||
        newScaler != _cachedTextScaler) {
      _cachedScreenWidth = newWidth;
      _cachedTextScaler = newScaler;
      _rebuildChromeTextPainters();
      _rebuildAxisLabelPainters();
      _recomputeEdgeGeometry();
    }
  }

  // C1 fix: PlatformDispatcher in observer (no context needed).
  // MediaQuery stays in didChangeDependencies (safe, in build phase).
  @override
  void didChangeAccessibilityFeatures() {
    final reduced = ui.PlatformDispatcher.instance
        .accessibilityFeatures.reduceMotion;
    if (reduced && !_wasReduced) {
      for (final t in _pendingTimers) { t.cancel(); }
      _pendingTimers.clear();
      _entranceCtrl.value = 1.0;
      _sweepCtrl.value = 1.0;
      _animCtrl.value = 1.0;
      _countUpCtrl.value = 1.0;
      _ambientSweepCtrl.stop();
      _edgeDotCtrl.stop();
      _glowPulseCtrl.value = 0.5;
      setState(() => _entranceComplete = true);
    }
    _reduceMotion = reduced;
    _wasReduced = reduced;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final t in _pendingTimers) { t.cancel(); }
    _pendingTimers.clear();

    // Curves before controllers (I-15). Stop before dispose (I-29).
    _pillCurve.dispose();
    _pillCtrl
      ..stop()
      ..dispose();
    _edgeDotCtrl
      ..stop()
      ..dispose();
    _glowPulseCtrl
      ..stop()
      ..dispose();
    _countUpCurve.dispose();
    _countUpCtrl
      ..stop()
      ..dispose();
    _ambientSweepCtrl
      ..stop()
      ..dispose();
    _sweepCtrl
      ..stop()
      ..dispose();
    _entranceCtrl
      ..stop()
      ..dispose();
    _animCurve.dispose();
    _animCtrl
      ..stop()
      ..dispose();

    _disposeChromeTextPainters();
    super.dispose();
  }

  // ── Pre-Computed TextPainters (I-84) ────────────────────

  void _rebuildChromeTextPainters() {
    _disposeChromeTextPainters();
    final teal = BaselineColors.teal;
    final ts = _cachedTextScaler;

    _fouoPainter = _buildChromeTp(
      '(U) UNCLASSIFIED', teal.atOpacity(0.06), 8.0, ts,
    );
    final now = DateTime.now();
    final fid = widget.figureId;
    final serial = 'FR-${now.year}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}-'
        '${fid.substring(0, 8.clamp(0, fid.length))}';
    _serialPainter = _buildChromeTp(
      serial, teal.atOpacity(0.05), 7.0, ts,
    );
    _classHeaderPainter = _buildChromeTp(
      'FRAMING RADAR\u2122 // RHETORICAL ANALYSIS',
      teal.atOpacity(0.12), 7.0, ts,
    );

    _ringLabelPainters = List.generate(_kGridRings, (ring) {
      final label = ((ring + 1) / _kGridRings).toStringAsFixed(2);
      return _buildChromeTp(label, teal.atOpacity(0.15), 7.0, ts);
    });

    _bearingPainters = _kBearings.map((b) {
      return _buildChromeTp(b, teal.atOpacity(0.10), 6.0, ts);
    }).toList();

    _trackDesignPainters = _kTrackDesignations.map((td) {
      return _buildChromeTp(td, teal.atOpacity(0.08), 5.5, ts);
    }).toList();

    _brgReadoutPainter = _buildChromeTp(
      'BRG 000 / RNG 1.00', teal.atOpacity(0.10), 7.0, ts,
    );
  }

  void _disposeChromeTextPainters() {
    _fouoPainter?.dispose();
    _serialPainter?.dispose();
    _classHeaderPainter?.dispose();
    if (_ringLabelPainters != null) {
      for (final tp in _ringLabelPainters!) { tp.dispose(); }
    }
    if (_bearingPainters != null) {
      for (final tp in _bearingPainters!) { tp.dispose(); }
    }
    if (_trackDesignPainters != null) {
      for (final tp in _trackDesignPainters!) { tp.dispose(); }
    }
    _brgReadoutPainter?.dispose();
    _disposeAxisLabelPainters();
  }

  // W1: Dispose axis label TPs.
  void _disposeAxisLabelPainters() {
    if (_axisLabelPainters != null) {
      for (final tp in _axisLabelPainters!) { tp.dispose(); }
      _axisLabelPainters = null;
    }
  }

  // W1: Pre-compute axis label TPs. Called on data load + dependency change.
  void _rebuildAxisLabelPainters() {
    _disposeAxisLabelPainters();
    final ts = _cachedTextScaler;
    final labels = FramingCategory.radarOrder
        .map((c) => c.shortLabel.toUpperCase())
        .toList();
    _axisLabelPainters = List.generate(_kAxisCount, (i) {
      final value = i < _toValues.length ? _toValues[i].clamp(0.0, 1.0) : 0.0;
      final labelColor = value > 0.7
          ? Color.lerp(BaselineColors.textSecondary, BaselineColors.teal, 0.25)!
          : BaselineColors.textSecondary;
      return TextPainter(
        text: TextSpan(
          text: labels[i],
          style: TextStyle(
            color: labelColor,
            fontSize: 9,
            fontFamily: BaselineTypography.monoFontFamily,
            fontWeight: FontWeight.w400,
            letterSpacing: 0.8,
          ),
        ),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
        textScaler: ts,
      )..layout();
    });
  }

  static TextPainter _buildChromeTp(
    String text, Color color, double fontSize, TextScaler scaler,
  ) {
    return TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontFamily: BaselineTypography.monoFontFamily,
          letterSpacing: 1.0,
        ),
      ),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
    )..layout();
  }

  // ── Pre-Computed Geometry (I-80) ────────────────────────

  void _recomputeEdgeGeometry() {
    if (_toValues.every((v) => v == 0)) {
      _cachedDashedSegments = null;
      return;
    }

    final screenWidth = _cachedScreenWidth;
    final radarSize = (screenWidth * _kRadarSizeFraction)
        .clamp(_kRadarMinSize, _kRadarMaxSize);
    final radius = radarSize / 2;
    final totalSize = radarSize + (_kLabelOffset * 2) + 48;
    final center = Offset(totalSize / 2, totalSize / 2);

    // Edge path points for current polygon.
    final edgePoints = <Offset>[];
    for (int i = 0; i < _kAxisCount; i++) {
      final val = _toValues[i].clamp(0.0, 1.0);
      edgePoints.add(_vertexAt(center, i, radius * val));
    }
    // Dashed segments for previous polygon.
    if (_toPrevValues.any((v) => v > 0)) {
      final prevPath = Path();
      for (int i = 0; i < _kAxisCount; i++) {
        final val = _toPrevValues[i].clamp(0.0, 1.0);
        final pt = _vertexAt(center, i, radius * val);
        if (i == 0) {
          prevPath.moveTo(pt.dx, pt.dy);
        } else {
          prevPath.lineTo(pt.dx, pt.dy);
        }
      }
      prevPath.close();
      _cachedDashedSegments = _computeDashSegments(prevPath, 6, 4);
    } else {
      _cachedDashedSegments = null;
    }
  }

  static Offset _vertexAt(Offset center, int index, double radius) {
    final angle = -math.pi / 2 + (2 * math.pi * index / _kAxisCount);
    return Offset(
      center.dx + radius * math.cos(angle),
      center.dy + radius * math.sin(angle),
    );
  }

  static List<List<Offset>> _computeDashSegments(
    Path path, double dashLen, double gapLen,
  ) {
    final segments = <List<Offset>>[];
    for (final metric in path.computeMetrics()) {
      double dist = 0;
      while (dist < metric.length) {
        final end = (dist + dashLen).clamp(0.0, metric.length);
        final startTangent = metric.getTangentForOffset(dist);
        final endTangent = metric.getTangentForOffset(end);
        if (startTangent != null && endTangent != null) {
          segments.add([startTangent.position, endTangent.position]);
        }
        dist += dashLen + gapLen;
      }
    }
    return segments;
  }

  // ── Data Loading ─────────────────────────────────────────

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _errorCode = null;
    });

    try {
      final entitlementService = const EntitlementService();
      final entitlement = await entitlementService.checkEntitlement(
        endpoint: 'get-trends',
        featureFlag: 'ENABLE_RADAR',
      );

      if (!mounted) return;

      final figuresService = const FiguresService();
      final framingService = const FramingService();
      final results = await Future.wait([
        figuresService.getFigure(widget.figureId),
        framingService.getFramingRadar(
          figureId: widget.figureId,
          entitlementToken: entitlement.token,
          period: _selectedPeriod.value,
        ),
      ]);

      if (!mounted) return;

      final figure = results[0] as Figure;
      final radar = results[1] as FramingDistribution;

      _fromValues = List<double>.from(_toValues);
      _fromPrevValues = List<double>.from(_toPrevValues);
      _toValues = _extractValues(radar.current);
      _toPrevValues = radar.hasPrevious
          ? _extractValues(radar.previous!)
          : List.filled(_kAxisCount, 0.0);

      _recomputeEdgeGeometry();
      _rebuildAxisLabelPainters();

      setState(() {
        _figureName = figure.name;
        _radarData = radar;
        _isLoading = false;
        _shiftHapticFired = false;
      });

      // ── Entrance choreography ──
      if (_reduceMotion) {
        _animCtrl.value = 1.0;
        _entranceCtrl.value = 1.0;
        _sweepCtrl.value = 1.0;
        _countUpCtrl.value = 1.0;
        _glowPulseCtrl.value = 0.5;
        _entranceComplete = true;
      } else {
        _entranceCtrl.forward();
        _sweepCtrl.forward();
        _animCtrl.forward(from: 0.0);

        // Count-up starts at entrance phase 7 (750ms).
        final countUpTimer = Timer(
          const Duration(milliseconds: 750),
          () { if (mounted) _countUpCtrl.forward(); },
        );
        _pendingTimers.add(countUpTimer);

        // Ambient loops start after entrance.
        final ambientTimer = Timer(_kEntranceDuration, () {
          if (!mounted) return;
          _ambientSweepCtrl.repeat();
          _glowPulseCtrl.repeat(reverse: true);
          _edgeDotCtrl.repeat();
          setState(() => _entranceComplete = true);
        });
        _pendingTimers.add(ambientTimer);

        // Haptic at sweep completion.
        _sweepCtrl.addStatusListener(_onSweepComplete);
      }

      // ── Popup triggers (I-78: sequential gate) ──
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        RateAppPopup.maybeShow(
          context, figureId: widget.figureId,
        ).then((_) {
          if (mounted) {
            final currentTier = ProviderScope.containerOf(context).read(tierProvider).tier;
            SoftPaywallPopup.maybeShow(context, tier: currentTier.isEmpty ? 'free' : currentTier);
          }
        });
      });
    } catch (e) {
      if (!mounted) return;
      _handleError(e);
    }
  }

  void _onSweepComplete(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      HapticUtil.measurementComplete();
      _sweepCtrl.removeStatusListener(_onSweepComplete);
    }
  }

  List<double> _extractValues(Map<FramingCategory, double> data) {
    return FramingCategory.radarOrder
        .map((cat) => data[cat] ?? 0.0)
        .toList();
  }

  void _handleError(Object e) {
    final code = e is FramingServiceException
        ? e.code
        : e is EntitlementServiceException
            ? e.code
            : null;

    if (code != null && _kPaywallErrorCodes.contains(code)) {
      setState(() {
        _isLoading = false;
        _errorMessage = null;
        _errorCode = null;
      });
      if (!_didRouteToPaywall && mounted) {
        _didRouteToPaywall = true;
        context.push(AppRoutes.paywall);
      }
      return;
    }

    if (code != null && _kTemporaryErrorCodes.contains(code)) {
      _entranceCtrl.reset();
      _sweepCtrl.reset();
      setState(() {
        _isLoading = false;
        _entranceComplete = false;
        _errorMessage = code == 'rate_limited'
            ? 'Too many requests. Try again shortly.'
            : 'Framing Radar\u2122 is temporarily unavailable.';
        _errorCode = code;
      });
      return;
    }

    _entranceCtrl.reset();
    _sweepCtrl.reset();
    setState(() {
      _isLoading = false;
      _entranceComplete = false;
      _errorMessage = e is FramingServiceException
          ? e.message
          : e is FiguresServiceException
              ? e.message
              : e is EntitlementServiceException
                  ? e.message
                  : 'Unable to load Framing Radar\u2122. Pull to retry.';
      _errorCode = code;
    });
  }

  void _onPeriodChanged(TrendPeriod period) {
    if (period == _selectedPeriod) return;
    HapticUtil.selection();
    setState(() {
      _selectedPeriod = period;
      _selectedAxisIndex = null;
    });
    _loadData();
  }

  Future<void> _onRefresh() async {
    _didRouteToPaywall = false;
    try {
      final entitlementService = const EntitlementService();
      final entitlement = await entitlementService.checkEntitlement(
        endpoint: 'get-trends',
        featureFlag: 'ENABLE_RADAR',
      );

      if (!mounted) return;

      final framingService = const FramingService();
      final radar = await framingService.getFramingRadar(
        figureId: widget.figureId,
        entitlementToken: entitlement.token,
        period: _selectedPeriod.value,
      );
      if (!mounted) return;

      _fromValues = List<double>.from(_toValues);
      _fromPrevValues = List<double>.from(_toPrevValues);
      _toValues = _extractValues(radar.current);
      _toPrevValues = radar.hasPrevious
          ? _extractValues(radar.previous!)
          : List.filled(_kAxisCount, 0.0);

      _recomputeEdgeGeometry();
      _rebuildAxisLabelPainters();

      setState(() {
        _radarData = radar;
        _errorMessage = null;
        _errorCode = null;
        _shiftHapticFired = false;
      });

      if (_reduceMotion) {
        _animCtrl.value = 1.0;
      } else {
        _animCtrl.forward(from: 0.0);
      }

      HapticUtil.refreshComplete();
    } catch (e) {
      if (!mounted) return;
      _handleError(e);
    }
  }

  // ── A-3: Axis Tap ───────────────────────────────────────

  void _onAxisTap(int index) {
    HapticUtil.light();
    setState(() {
      if (_selectedAxisIndex == index) {
        _selectedAxisIndex = null;
        _pillCtrl.reverse();
      } else {
        _selectedAxisIndex = index;
        _pillCtrl.forward(from: 0.0);
        // 🍒 115: Update bearing readout painter.
        _updateBrgReadout(index);
      }
    });
  }

  void _dismissDetailPill() {
    if (_selectedAxisIndex != null) {
      setState(() => _selectedAxisIndex = null);
      _pillCtrl.reverse();
    }
  }

  // 🍒 115: Bearing readout update.
  void _updateBrgReadout(int index) {
    final bearing = _kBearings[index];
    final value = _toValues[index].clamp(0.0, 1.0);
    _brgReadoutPainter?.dispose();
    _brgReadoutPainter = _buildChromeTp(
      'BRG $bearing / RNG ${value.toStringAsFixed(2)}',
      BaselineColors.teal.atOpacity(0.15),
      7.0, _cachedTextScaler,
    );
  }

  // ── Export (150.5) ──────────────────────────────────────

  Future<void> _onExport() async {
    if (!_entranceComplete) return; // I-82: guard behind entrance
    HapticUtil.medium();
    final success = await ExportUtil.captureAndShare(
      _exportKey,
      subject: 'Framing Radar\u2122: ${_figureName ?? 'Analysis'}',
      shareText:
          'Framing Radar\u2122 analysis for ${_figureName ?? 'figure'} via BASELINE',
    );
    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Export failed. Please try again.')),
      );
    }
  }

  // ── Stagger Helper ──────────────────────────────────────

  double _stagger(double offset) {
    if (_reduceMotion) return 1.0;
    final raw = (_entranceCtrl.value - offset) / 0.15;
    return raw.clamp(0.0, 1.0);
  }

  // ── Build ────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BaselineColors.scaffoldBackground,
      body: SafeArea(
        child: GestureDetector(
          onTap: _dismissDetailPill,
          behavior: HitTestBehavior.translucent,
          child: _isLoading
              ? _buildLoading()
              : _errorMessage != null
                  ? _buildError()
                  : _radarData != null
                      ? _buildContent()
                      : _buildLoading(),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  // LOADING STATE
  // ═══════════════════════════════════════════════════════

  Widget _buildLoading() {
    return Column(
      children: [
        _buildHeader(),
        _buildAccentLine(),
        const Expanded(
          child: ShimmerLoading(variant: ShimmerVariant.detail),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════
  // ERROR STATE
  // ═══════════════════════════════════════════════════════

  Widget _buildError() {
    return Column(
      children: [
        _buildHeader(),
        _buildAccentLine(),
        Expanded(
          child: Center(
            child: ErrorState.fromCode(
              code: _errorCode,
              onRetry: _loadData,
            ),
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════
  // CONTENT (I-79: animations pushed to leaf nodes)
  // ═══════════════════════════════════════════════════════

  Widget _buildContent() {
    final radar = _radarData!;

    return Stack(
      children: [
        // ── Screen chrome: isolated AnimatedBuilder (I-79) ──
        Positioned.fill(
          child: ExcludeSemantics(
            child: RepaintBoundary(
              child: AnimatedBuilder(
                animation: Listenable.merge([
                  _entranceCtrl,
                  _ambientSweepCtrl,
                  _glowPulseCtrl,
                ]),
                builder: (context, _) {
                  return CustomPaint(
                    painter: _RadarConsolePainter(
                      teal: BaselineColors.teal,
                      entranceProgress: _entranceCtrl.value,
                      ambientSweepAngle:
                          _ambientSweepCtrl.value * 2 * math.pi,
                      glowPulse: _glowPulseCtrl.value,
                      safePadding: MediaQuery.paddingOf(context),
                      reduceMotion: _reduceMotion,
                      fouoPainter: _fouoPainter,
                      serialPainter: _serialPainter,
                      classHeaderPainter: _classHeaderPainter,
                      brgReadoutPainter: _selectedAxisIndex != null
                          ? _brgReadoutPainter
                          : null,
                    ),
                  );
                },
              ),
            ),
          ),
        ),

        // ── Scrollable content: STATIC after entrance ──
        AnimatedBuilder(
          animation: _entranceCtrl,
          builder: (context, _) {
            return RefreshIndicator(
              onRefresh: _onRefresh,
              color: BaselineColors.teal,
              backgroundColor: BaselineColors.card,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(
                  bottom: BaselineSpacing.xxl,
                ),
                child: Column(
                  children: [
                    // 1. Header
                    Opacity(
                      opacity: _stagger(0.0),
                      child: _buildHeader(),
                    ),

                    // 2. Accent glow line
                    _buildAccentLineAnimated(),

                    const SizedBox(height: BaselineSpacing.md),

                    // 3. Subject designation
                    Opacity(
                      opacity: _stagger(0.15),
                      child: Transform.translate(
                        offset: Offset(0, (1 - _stagger(0.15)) * 6),
                        child: _buildSubjectDesignation(),
                      ),
                    ),

                    const SizedBox(height: BaselineSpacing.lg),

                    // 4. Period selector
                    Opacity(
                      opacity: _stagger(0.25),
                      child: Transform.translate(
                        offset: Offset(0, (1 - _stagger(0.25)) * 6),
                        child: _buildPeriodSelector(),
                      ),
                    ),

                    const SizedBox(height: BaselineSpacing.xl),

                    // 5. Pentagon radar chart
                    Opacity(
                      opacity: _stagger(0.35),
                      child: radar.current.isEmpty ||
                              radar.current.values
                                      .where((v) => v > 0)
                                      .length <
                                  3
                          ? _buildGhostPentagon()
                          : RepaintBoundary(
                              key: _exportKey,
                              child: _buildRadarChart(radar),
                            ),
                    ),

                    const SizedBox(height: BaselineSpacing.xl),

                    // 6. Shift insight
                    if (radar.hasShift == true)
                      Opacity(
                        opacity: _stagger(0.55),
                        child: Transform.translate(
                          offset: Offset(0, (1 - _stagger(0.55)) * 6),
                          child: _buildShiftInsight(radar),
                        ),
                      ),

                    // 7. Legend
                    Opacity(
                      opacity: _stagger(0.60),
                      child: _buildLegend(radar),
                    ),

                    const SizedBox(height: BaselineSpacing.md),

                    // 8. Count-up + A-7
                    Opacity(
                      opacity: _stagger(0.65),
                      child: _buildStatementCount(radar),
                    ),

                    const SizedBox(height: BaselineSpacing.lg),

                    // 🍒 118: Acquisition tone dots
                    Opacity(
                      opacity: _stagger(0.70),
                      child: _buildAcquisitionToneDots(),
                    ),

                    const SizedBox(height: BaselineSpacing.md),

                    // 9. Action bar (150.5)
                    Opacity(
                      opacity: _stagger(0.70),
                      child: _buildActionBar(),
                    ),

                    const SizedBox(height: BaselineSpacing.lg),

                    // 10. Disclaimer footer
                    Opacity(
                      opacity: _stagger(0.75),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: BaselineSpacing.lg,
                        ),
                        child: DisclaimerFooter(),
                      ),
                    ),

                    const SizedBox(height: BaselineSpacing.md),

                    // 11. Acquisition stamp
                    Opacity(
                      opacity: _stagger(0.85),
                      child: _buildAcquisitionStamp(),
                    ),
                  ],
                ),
              ),
            );
          },
        ),

        // ── A-3 detail pill overlay ──
        if (_selectedAxisIndex != null && radar.current.isNotEmpty)
          _buildDetailPill(radar),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════
  // HEADER
  // ═══════════════════════════════════════════════════════

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: BaselineSpacing.lg,
        vertical: BaselineSpacing.sm,
      ),
      child: Row(
        children: [
          // Back button (BaselineIcon, press-scale)
          Semantics(
            button: true,
            label: 'Go back',
            excludeSemantics: true,
            child: _TapScale(
              scale: _kScaleCard,
              onTap: () {
                HapticUtil.light();
                if (context.canPop()) {
                  context.pop();
                } else {
                  context.go(AppRoutes.today);
                }
              },
              child: SizedBox(
                height: _kIconTouchTarget,
                child: Padding(
                  padding: const EdgeInsets.only(
                    right: BaselineSpacing.md,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      BaselineIcon(
                        BaselineIconType.backArrow,
                        size: 20,
                        color: BaselineColors.textPrimary,
                      ),
                      const SizedBox(width: BaselineSpacing.xs),
                      Text(
                        'Back',
                        style: BaselineTypography.body2.copyWith(
                          color: BaselineColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const Spacer(),
          // Title with info icon
          Semantics(
            button: true,
            label: 'Learn about Framing Radar',
            excludeSemantics: true,
            child: _TapScale(
              onTap: () {
                HapticUtil.light();
                InfoBottomSheet.show(
                  context,
                  key: 'framing_radar',
                  surface: 'Framing Radar\u2122',
                );
              },
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Framing Radar\u2122',
                    style: BaselineTypography.h2.copyWith(
                      color: BaselineColors.textPrimary,
                    ),
                  ),
                  const SizedBox(width: BaselineSpacing.xs),
                  BaselineIcon(
                    BaselineIconType.info,
                    size: 16,
                    color: BaselineColors.textSecondary,
                  ),
                ],
              ),
            ),
          ),
          const Spacer(),
          const SizedBox(width: _kIconTouchTarget),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  // ACCENT GLOW LINE (isolated animation)
  // ═══════════════════════════════════════════════════════

  Widget _buildAccentLine() {
    return Container(
      height: _kAccentLineHeight,
      margin: const EdgeInsets.symmetric(horizontal: BaselineSpacing.xl),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.transparent,
            BaselineColors.teal.atOpacity(0.36),
            BaselineColors.teal.atOpacity(0.6),
            BaselineColors.teal.atOpacity(0.36),
            Colors.transparent,
          ],
          stops: const [0.0, 0.2, 0.5, 0.8, 1.0],
        ),
        borderRadius: BorderRadius.circular(1),
      ),
    );
  }

  Widget _buildAccentLineAnimated() {
    return AnimatedBuilder(
      animation: _glowPulseCtrl,
      builder: (context, _) {
        final pulseOpacity = _reduceMotion
            ? 0.6
            : 0.4 + (_glowPulseCtrl.value * 0.3);
        return Opacity(
          opacity: _stagger(0.05),
          child: Container(
            height: _kAccentLineHeight,
            margin: const EdgeInsets.symmetric(
              horizontal: BaselineSpacing.xl,
            ),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.transparent,
                  BaselineColors.teal.atOpacity(pulseOpacity * 0.6),
                  BaselineColors.teal.atOpacity(pulseOpacity),
                  BaselineColors.teal.atOpacity(pulseOpacity * 0.6),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.2, 0.5, 0.8, 1.0],
              ),
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════
  // SUBJECT DESIGNATION
  // ═══════════════════════════════════════════════════════

  Widget _buildSubjectDesignation() {
    if (_figureName == null) return const SizedBox.shrink();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'SUBJECT:',
          style: BaselineTypography.dataSmall.copyWith(
            color: BaselineColors.teal.atOpacity(0.20),
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(width: 6),
        Container(
          width: 2, height: 2,
          decoration: BoxDecoration(
            color: BaselineColors.teal.atOpacity(0.15),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            _figureName!.toUpperCase(),
            style: BaselineTypography.dataSmall.copyWith(
              color: BaselineColors.textSecondary,
              letterSpacing: 1.0,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════
  // PERIOD SELECTOR
  // ═══════════════════════════════════════════════════════

  Widget _buildPeriodSelector() {
    return Center(
      child: Container(
        height: _kPillHeight,
        decoration: BoxDecoration(
          color: BaselineColors.card,
          border: Border.all(
            color: BaselineColors.borderInactive.atOpacity(_kBorderOpacity),
            width: _kBorderWidth,
          ),
          borderRadius: BorderRadius.circular(_kPillRadius),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: TrendPeriod.values.map((period) {
            final isSelected = period == _selectedPeriod;
            return Semantics(
              button: true,
              selected: isSelected,
              label: '${period.label} period',
              child: _TapScale(
                scale: _kScaleChip,
                onTap: () => _onPeriodChanged(period),
                child: AnimatedContainer(
                  duration: _kColorTransitionDuration,
                  curve: Curves.easeInOut,
                  height: _kPillHeight - (_kBorderWidth * 2),
                  padding: const EdgeInsets.symmetric(
                    horizontal: BaselineSpacing.lg,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? BaselineColors.teal
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(
                      _kPillRadius - _kBorderWidth,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    period.label,
                    style: BaselineTypography.button.copyWith(
                      color: isSelected
                          ? BaselineColors.scaffoldBackground
                          : BaselineColors.textSecondary,
                      fontFamily: BaselineTypography.monoFontFamily,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  // GHOST PENTAGON (insufficient data placeholder)
  // ═══════════════════════════════════════════════════════

  Widget _buildGhostPentagon() {
    final radarSize = (_cachedScreenWidth * _kRadarSizeFraction)
        .clamp(_kRadarMinSize, _kRadarMaxSize);

    return AnimatedBuilder(
      animation: _glowPulseCtrl,
      builder: (context, _) {
        final pulse = _reduceMotion ? 1.0 : 1.0 + (_glowPulseCtrl.value * 0.02);
        return Transform.scale(
          scale: pulse,
          child: SizedBox(
            width: radarSize,
            height: radarSize,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: radarSize * 0.6,
                  height: radarSize * 0.6,
                  child: CustomPaint(
                    painter: _GhostPentagonPainter(
                      color: BaselineColors.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(height: BaselineSpacing.md),
                Text(
                  kRadarNotReady,
                  textAlign: TextAlign.center,
                  style: BaselineTypography.body2.copyWith(
                    color: BaselineColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════
  // RADAR CHART (own AnimatedBuilder, leaf node)
  // ═══════════════════════════════════════════════════════

  Widget _buildRadarChart(FramingDistribution radar) {
    final radarSize = (_cachedScreenWidth * _kRadarSizeFraction)
        .clamp(_kRadarMinSize, _kRadarMaxSize);
    final totalSize = radarSize + (_kLabelOffset * 2) + 48;

    return Semantics(
      label: _buildRadarSemanticLabel(radar),
      child: ExcludeSemantics(
        child: SizedBox(
          width: totalSize,
          height: totalSize,
          child: AnimatedBuilder(
            animation: Listenable.merge([
              _animCurve,
              _sweepCtrl,
              _edgeDotCtrl,
              _glowPulseCtrl,
              _entranceCtrl,
            ]),
            builder: (context, _) {
              final t = _animCurve.value;

              final currentValues = List.generate(_kAxisCount, (i) {
                return _fromValues[i] +
                    (_toValues[i] - _fromValues[i]) * t;
              });

              final previousValues = List.generate(_kAxisCount, (i) {
                return _fromPrevValues[i] +
                    (_toPrevValues[i] - _fromPrevValues[i]) * t;
              });

              return GestureDetector(
                onTapUp: (details) => _handleRadarTap(
                  details, totalSize, radarSize,
                ),
                child: CustomPaint(
                  size: Size(totalSize, totalSize),
                  painter: _PentagonRadarPainter(
                    currentValues: currentValues,
                    previousValues:
                        radar.hasPrevious ? previousValues : null,
                    radarRadius: radarSize / 2,
                    labelOffset: _kLabelOffset,
                    sweepProgress: _sweepCtrl.value,
                    edgeDotProgress: _reduceMotion
                        ? -1.0
                        : _edgeDotCtrl.value,
                    glowPulse: _reduceMotion
                        ? 0.0
                        : _glowPulseCtrl.value,
                    entranceProgress: _entranceCtrl.value,
                    selectedAxisIndex: _selectedAxisIndex,
                    teal: BaselineColors.teal,
                    reduceMotion: _reduceMotion,
                    ringLabelPainters: _ringLabelPainters,
                    bearingPainters: _bearingPainters,
                    trackDesignPainters: _trackDesignPainters,
                    cachedDashedSegments: _cachedDashedSegments,
                    axisLabelPainters: _axisLabelPainters,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  void _handleRadarTap(
    TapUpDetails details, double totalSize, double radarSize,
  ) {
    final center = Offset(totalSize / 2, totalSize / 2);
    final tapPos = details.localPosition;

    for (int i = 0; i < _kAxisCount; i++) {
      final angle = -math.pi / 2 + (2 * math.pi * i / _kAxisCount);
      final vertexPos = Offset(
        center.dx +
            (radarSize / 2 + _kLabelOffset * 0.5) * math.cos(angle),
        center.dy +
            (radarSize / 2 + _kLabelOffset * 0.5) * math.sin(angle),
      );

      if ((tapPos - vertexPos).distance < 30) {
        final tier = ProviderScope.containerOf(context)
            .read(tierProvider)
            .tier;
        if (canAccessFeature(tier, GatedFeature.radarAxisDetail)) {
          _onAxisTap(i);
        } else {
          HapticUtil.light();
          context.push(AppRoutes.paywall);
        }
        return;
      }
    }
    _dismissDetailPill();
  }

  String _buildRadarSemanticLabel(FramingDistribution radar) {
    final parts = FramingCategory.radarOrder.map((cat) {
      final val = ((radar.current[cat] ?? 0.0) * 100).round();
      final prevVal = radar.hasPrevious
          ? ((radar.previous![cat] ?? 0.0) * 100).round()
          : null;
      final delta = prevVal != null ? val - prevVal : null;
      final deltaStr = delta != null
          ? ', change ${delta >= 0 ? "plus" : "minus"} ${delta.abs()} percent'
          : '';
      return '${cat.shortLabel}: $val percent$deltaStr';
    });
    return 'Framing Radar pentagon chart. ${parts.join('. ')}';
  }

  // ═══════════════════════════════════════════════════════
  // A-3 DETAIL PILL
  // ═══════════════════════════════════════════════════════

  Widget _buildDetailPill(FramingDistribution radar) {
    final idx = _selectedAxisIndex!;
    final cat = FramingCategory.radarOrder[idx];
    final value = (radar.current[cat] ?? 0.0) * 100;
    final prevValue = radar.hasPrevious
        ? (radar.previous![cat] ?? 0.0) * 100
        : null;
    final delta = prevValue != null ? value - prevValue : null;

    final radarSize = (_cachedScreenWidth * _kRadarSizeFraction)
        .clamp(_kRadarMinSize, _kRadarMaxSize);
    final totalSize = radarSize + (_kLabelOffset * 2) + 48;
    final center = Offset(totalSize / 2, totalSize / 2);
    final angle = -math.pi / 2 + (2 * math.pi * idx / _kAxisCount);
    final pillX = center.dx +
        (radarSize / 2 + _kLabelOffset + 20) * math.cos(angle);
    final pillY = center.dy +
        (radarSize / 2 + _kLabelOffset + 20) * math.sin(angle);
    final topOffset = MediaQuery.paddingOf(context).top +
        _kIconTouchTarget + _kAccentLineHeight + 80;

    return Positioned(
      left: (pillX - 60).clamp(16.0, _cachedScreenWidth - 136.0),
      top: topOffset + pillY - 30,
      // X1: RepaintBoundary isolates spring animation repaints.
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _pillCurve,
          builder: (context, child) {
            return Transform.scale(
              scale: _pillCurve.value.clamp(0.0, 1.2),
              child: Opacity(
                opacity: _pillCurve.value.clamp(0.0, 1.0),
                child: child,
              ),
            );
          },
          child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: BaselineSpacing.md,
            vertical: BaselineSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: BaselineColors.card,
            border: Border.all(
              color: BaselineColors.teal.atOpacity(0.3),
              width: _kBorderWidth,
            ),
            borderRadius: BaselineRadius.buttonBorderRadius,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                cat.shortLabel.toUpperCase(),
                style: BaselineTypography.dataSmall.copyWith(
                  color: BaselineColors.textSecondary,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${value.round()}%',
                style: BaselineTypography.data.copyWith(
                  color: BaselineColors.teal,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (delta != null) ...[
                const SizedBox(height: 2),
                Text(
                  '${delta >= 0 ? '\u25B2' : '\u25BC'} ${delta.abs().round()}%',
                  style: BaselineTypography.dataSmall.copyWith(
                    color: delta.abs() > 5
                        ? BaselineColors.amber
                        : BaselineColors.teal.atOpacity(0.6),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  // SHIFT INSIGHT
  // ═══════════════════════════════════════════════════════

  Widget _buildShiftInsight(FramingDistribution radar) {
    final dominant = radar.dominantCategory;
    if (dominant == null) return const SizedBox.shrink();

    // One-shot shift haptic (I-11 fix: was firing every rebuild).
    if (!_shiftHapticFired && !_reduceMotion) {
      _shiftHapticFired = true;
      HapticUtil.shiftDetected();
    }

    return Padding(
      padding: const EdgeInsets.only(
        bottom: BaselineSpacing.lg,
        left: BaselineSpacing.xl,
        right: BaselineSpacing.xl,
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: BaselineSpacing.md,
          vertical: BaselineSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: BaselineColors.card,
          border: Border.all(
            color: BaselineColors.amber.atOpacity(0.4),
            width: _kBorderWidth,
          ),
          borderRadius: BaselineRadius.chipBorderRadius,
        ),
        child: Semantics(
          button: true,
          label: 'Bearing shift toward ${dominant.shortLabel} framing. Tap for info.',
          excludeSemantics: true,
          child: _TapScale(
            onTap: () {
              HapticUtil.light();
              InfoBottomSheet.show(
                context,
                key: 'framing_radar',
                surface: 'Framing Radar\u2122',
              );
            },
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'BEARING SHIFT:',
                  style: BaselineTypography.dataSmall.copyWith(
                    color: BaselineColors.amber.atOpacity(0.7),
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'Toward ${dominant.shortLabel} framing',
                    style: BaselineTypography.body2.copyWith(
                      color: BaselineColors.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 4),
                BaselineIcon(
                  BaselineIconType.info,
                  size: 16,
                  color: BaselineColors.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  // LEGEND
  // ═══════════════════════════════════════════════════════

  Widget _buildLegend(FramingDistribution radar) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: BaselineSpacing.xl),
      child: Column(
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CustomPaint(
                size: const Size(10, 10),
                painter: _LegendDotPainter(
                  color: BaselineColors.teal, filled: true,
                ),
              ),
              const SizedBox(width: BaselineSpacing.sm),
              Text(
                'CURRENT SCAN',
                style: BaselineTypography.dataSmall.copyWith(
                  color: BaselineColors.textSecondary,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '(${_selectedPeriod.label})',
                style: BaselineTypography.dataSmall.copyWith(
                  color: BaselineColors.textSecondary.atOpacity(0.5),
                ),
              ),
            ],
          ),
          if (radar.hasPrevious) ...[
            const SizedBox(height: BaselineSpacing.xs),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CustomPaint(
                  size: const Size(10, 10),
                  painter: _LegendDotPainter(
                    color: BaselineColors.teal, filled: false,
                  ),
                ),
                const SizedBox(width: BaselineSpacing.sm),
                Text(
                  'PREVIOUS SCAN',
                  style: BaselineTypography.dataSmall.copyWith(
                    color: BaselineColors.textSecondary,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(width: 4),
                // Micro-dot separator
                Container(
                  width: 2, height: 2,
                  decoration: BoxDecoration(
                    color: BaselineColors.teal.atOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  '(prev)',
                  style: BaselineTypography.dataSmall.copyWith(
                    color: BaselineColors.textSecondary.atOpacity(0.5),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  // STATEMENT COUNT (150.10)
  // ═══════════════════════════════════════════════════════

  Widget _buildStatementCount(FramingDistribution radar) {
    final total = radar.effectiveTotalStatements;
    if (total <= 0) return const SizedBox.shrink();

    return Column(
      children: [
        AnimatedBuilder(
          animation: _countUpCurve,
          builder: (context, _) {
            final displayCount = (total * _countUpCurve.value).round();
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'ANALYZED',
                  style: BaselineTypography.dataSmall.copyWith(
                    color: BaselineColors.teal.atOpacity(0.20),
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '$displayCount',
                  style: BaselineTypography.data.copyWith(
                    color: BaselineColors.teal,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  'statements',
                  style: BaselineTypography.dataSmall.copyWith(
                    color: BaselineColors.textSecondary,
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: BaselineSpacing.sm),
        MeasuredByRow(
          modelProviders: const ['gpt', 'claude', 'grok'],
          analyzedAt: null, // TODO F7.5: timestamp from provider
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════
  // 🍒 118: ACQUISITION TONE DOTS
  // ═══════════════════════════════════════════════════════

  Widget _buildAcquisitionToneDots() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (i) {
        final active = _entranceComplete || _reduceMotion;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: Container(
            width: 4, height: 4,
            decoration: BoxDecoration(
              color: active
                  ? BaselineColors.teal.atOpacity(0.3 + i * 0.1)
                  : BaselineColors.teal.atOpacity(0.06),
              shape: BoxShape.circle,
            ),
          ),
        );
      }),
    );
  }

  // ═══════════════════════════════════════════════════════
  // ACTION BAR (150.5)
  // ═══════════════════════════════════════════════════════

  Widget _buildActionBar() {
    final canExport = _entranceComplete || _reduceMotion;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          button: true,
          label: 'Export radar as image',
          child: _ActionButton(
            icon: BaselineIconType.export,
            onTap: canExport ? _onExport : null,
            label: 'EXPORT',
          ),
        ),
        const SizedBox(width: BaselineSpacing.xl),
        Semantics(
          button: true,
          label: 'Share radar analysis',
          child: _ActionButton(
            icon: BaselineIconType.share,
            onTap: canExport ? _onExport : null,
            label: 'SHARE',
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════
  // ACQUISITION STAMP
  // ═══════════════════════════════════════════════════════

  Widget _buildAcquisitionStamp() {
    return ExcludeSemantics(
      child: Text(
        'ACQUISITION COMPLETE',
        style: BaselineTypography.dataSmall.copyWith(
          color: BaselineColors.teal.atOpacity(0.08),
          letterSpacing: 2.0,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// ACTION BUTTON (uses F_ICONS)
// ═══════════════════════════════════════════════════════════

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.onTap,
    required this.label,
  });

  final BaselineIconType icon;
  final VoidCallback? onTap;
  final String label;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return _TapScale(
      scale: _kScaleCard,
      onTap: () {
        if (enabled) {
          HapticUtil.medium();
          onTap!();
        }
      },
      child: Opacity(
        opacity: enabled ? 1.0 : 0.4,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: _kActionButtonSize,
              height: _kActionButtonSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: BaselineColors.teal.atOpacity(0.15),
                  width: 1.5,
                ),
              ),
              child: Center(
                child: BaselineIcon(
                  icon,
                  size: 20,
                  color: BaselineColors.teal,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: BaselineTypography.dataSmall.copyWith(
                color: BaselineColors.textSecondary,
                letterSpacing: 0.8,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// SCREEN CHROME PAINTER (I-71: constructor Paint finals)
// ═══════════════════════════════════════════════════════════

class _RadarConsolePainter extends CustomPainter {
  _RadarConsolePainter({
    required this.teal,
    required this.entranceProgress,
    required this.ambientSweepAngle,
    required this.glowPulse,
    required this.safePadding,
    required this.reduceMotion,
    this.fouoPainter,
    this.serialPainter,
    this.classHeaderPainter,
    this.brgReadoutPainter,
  })  : _chromePaint = Paint()
          ..color = teal.atOpacity(0.06)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.5,
        _dotPaint = Paint()
          ..color = teal.atOpacity(0.10),
        _perfPaint = Paint()
          ..color = teal.atOpacity(0.05)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.5,
        _scatterPaint = Paint()
          ..color = teal.atOpacity(0.03),
        _hairPaint = Paint()
          ..color = teal.atOpacity(0.05)
          ..strokeWidth = 0.5,
        _sweepPaint = Paint()
          ..color = teal.atOpacity(0.04)
          ..strokeWidth = 0.5;

  final Color teal;
  final double entranceProgress;
  final double ambientSweepAngle;
  final double glowPulse;
  final EdgeInsets safePadding;
  final bool reduceMotion;
  final TextPainter? fouoPainter;
  final TextPainter? serialPainter;
  final TextPainter? classHeaderPainter;
  final TextPainter? brgReadoutPainter;

  final Paint _chromePaint;
  final Paint _dotPaint;
  final Paint _perfPaint;
  final Paint _scatterPaint;
  final Paint _hairPaint;
  final Paint _sweepPaint;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final inX = safePadding.left + 12;
    final inY = safePadding.top + 12;
    final inB = safePadding.bottom + 28;
    final ep = entranceProgress;

    // Fade chrome paint with entrance.
    _chromePaint.color = teal.atOpacity(0.06 * ep);
    _dotPaint.color = teal.atOpacity(0.10 * ep);
    _perfPaint.color = teal.atOpacity(0.05 * ep);
    _scatterPaint.color = teal.atOpacity(0.03 * ep);
    _hairPaint.color = teal.atOpacity(0.05 * ep);

    // ── Reticle targeting brackets ──
    final armLen = 16.0;
    final corners = [
      Offset(inX, inY), Offset(w - inX, inY),
      Offset(inX, h - inB), Offset(w - inX, h - inB),
    ];
    final dirs = [
      [Offset(armLen, 0), Offset(0, armLen)],
      [Offset(-armLen, 0), Offset(0, armLen)],
      [Offset(armLen, 0), Offset(0, -armLen)],
      [Offset(-armLen, 0), Offset(0, -armLen)],
    ];
    for (int i = 0; i < 4; i++) {
      canvas.drawLine(corners[i], corners[i] + dirs[i][0], _chromePaint);
      canvas.drawLine(corners[i], corners[i] + dirs[i][1], _chromePaint);
    }

    // ── Registration dots ──
    for (final c in corners) {
      canvas.drawCircle(c, 1.0, _dotPaint);
    }

    // ── Film perforations (top edge) ──
    final perfCount = 12;
    final perfW = (w - 2 * inX) / (perfCount + 1);
    for (int i = 1; i <= perfCount; i++) {
      final px = inX + i * perfW;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(px, inY - 2), width: 6, height: 3),
          const Radius.circular(1),
        ),
        _perfPaint,
      );
    }

    // ── 🍒 114: Scope graticule lines (every 36°) ──
    final sweepCenter = Offset(w / 2, h * 0.42);
    final gratRadius = w * 0.30;
    final gratPaint = Paint()
      ..color = teal.atOpacity(0.03 * ep)
      ..strokeWidth = 0.3;
    for (int deg = 0; deg < 360; deg += 36) {
      final a = (deg - 90) * math.pi / 180;
      canvas.drawLine(
        sweepCenter,
        Offset(sweepCenter.dx + gratRadius * math.cos(a),
               sweepCenter.dy + gratRadius * math.sin(a)),
        gratPaint,
      );
    }

    // ── 🍒 117: Noise floor dots ──
    final rng = math.Random(42);
    final noisePaint = Paint()..color = teal.atOpacity(0.02 * ep);
    for (int i = 0; i < 30; i++) {
      final nx = inX + rng.nextDouble() * (w - 2 * inX);
      final ny = h * 0.25 + rng.nextDouble() * h * 0.35;
      canvas.drawCircle(Offset(nx, ny), 0.5, noisePaint);
    }

    // ── Signal interference scatter dots ──
    for (int i = 0; i < 20; i++) {
      final sx = inX + rng.nextDouble() * (w - 2 * inX);
      final sy = inY + rng.nextDouble() * (h - inY - inB);
      canvas.drawCircle(Offset(sx, sy), 0.5, _scatterPaint);
    }

    // ── Classification hairline ──
    canvas.drawLine(
      Offset(inX, h - inB + 8),
      Offset(w - inX, h - inB + 8),
      _hairPaint,
    );

    // ── Ambient sweep arm ──
    if (ambientSweepAngle > 0) {
      final armRadius = w * 0.38;
      final trailArc = 20.0 * math.pi / 180;
      for (int s = 8; s >= 0; s--) {
        final t = s / 8;
        final segAngle = ambientSweepAngle - math.pi / 2 - t * trailArc;
        final segEnd = Offset(
          sweepCenter.dx + armRadius * math.cos(segAngle),
          sweepCenter.dy + armRadius * math.sin(segAngle),
        );
        _sweepPaint.color = teal.atOpacity(0.04 * (1.0 - t) * ep);
        canvas.drawLine(sweepCenter, segEnd, _sweepPaint);
      }

      final armAngle = ambientSweepAngle - math.pi / 2;
      final armEnd = Offset(
        sweepCenter.dx + armRadius * math.cos(armAngle),
        sweepCenter.dy + armRadius * math.sin(armAngle),
      );
      _sweepPaint.color = teal.atOpacity(0.04 * ep);
      canvas.drawLine(sweepCenter, armEnd, _sweepPaint);
    }

    // ── Pre-computed TextPainters (I-84) ──
    if (fouoPainter != null && ep > 0) {
      fouoPainter!.paint(
        canvas,
        Offset(w - inX - fouoPainter!.width, h - inB + 12),
      );
    }
    if (serialPainter != null && ep > 0) {
      serialPainter!.paint(
        canvas,
        Offset(w / 2 - serialPainter!.width / 2, h - inB + 12),
      );
    }
    if (classHeaderPainter != null && ep > 0) {
      classHeaderPainter!.paint(
        canvas,
        Offset(inX, inY + 4),
      );
    }

    // 🍒 115: Bearing readout when axis selected.
    if (brgReadoutPainter != null && ep > 0) {
      brgReadoutPainter!.paint(
        canvas,
        Offset(w - inX - brgReadoutPainter!.width, inY + 4),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RadarConsolePainter old) {
    return old.entranceProgress != entranceProgress ||
        old.ambientSweepAngle != ambientSweepAngle ||
        old.glowPulse != glowPulse ||
        old.brgReadoutPainter != brgReadoutPainter;
  }
}

// ═══════════════════════════════════════════════════════════
// PENTAGON RADAR PAINTER (I-71: constructor Paint finals)
// ═══════════════════════════════════════════════════════════

class _PentagonRadarPainter extends CustomPainter {
  _PentagonRadarPainter({
    required this.currentValues,
    required this.radarRadius,
    required this.labelOffset,
    required this.sweepProgress,
    required this.edgeDotProgress,
    required this.glowPulse,
    required this.entranceProgress,
    required this.teal,
    required this.reduceMotion,
    this.previousValues,
    this.selectedAxisIndex,
    this.ringLabelPainters,
    this.bearingPainters,
    this.trackDesignPainters,
    this.cachedDashedSegments,
    this.axisLabelPainters,
  })  : _gridPaint = Paint()
          ..color = BaselineColors.borderInactive.atOpacity(0.18)
          ..strokeWidth = 0.8
          ..style = PaintingStyle.stroke,
        _outerGridPaint = Paint()
          ..color = BaselineColors.borderInactive.atOpacity(0.25)
          ..strokeWidth = 1.0
          ..style = PaintingStyle.stroke,
        _spokePaint = Paint()
          ..color = BaselineColors.borderInactive.atOpacity(0.12)
          ..strokeWidth = 0.8
          ..style = PaintingStyle.stroke,
        _strokePaint = Paint()
          ..color = teal.atOpacity(0.70)
          ..strokeWidth = 2.5
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
        _dashPaint = Paint()
          ..color = teal.atOpacity(0.25)
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round,
        _crossPaint = Paint()
          ..color = teal.atOpacity(0.15)
          ..strokeWidth = 0.5,
        _tickPaint = Paint()
          ..color = teal.atOpacity(0.06)
          ..strokeWidth = 0.5,
        _majorTickPaint = Paint()
          ..color = teal.atOpacity(0.12)
          ..strokeWidth = 0.8;

  final List<double> currentValues;
  final List<double>? previousValues;
  final double radarRadius;
  final double labelOffset;
  final double sweepProgress;
  final double edgeDotProgress;
  final double glowPulse;
  final double entranceProgress;
  final int? selectedAxisIndex;
  final Color teal;
  final bool reduceMotion;
  final List<TextPainter>? ringLabelPainters;
  final List<TextPainter>? bearingPainters;
  final List<TextPainter>? trackDesignPainters;
  final List<List<Offset>>? cachedDashedSegments;
  final List<TextPainter>? axisLabelPainters;

  final Paint _gridPaint;
  final Paint _outerGridPaint;
  final Paint _spokePaint;
  final Paint _strokePaint;
  final Paint _dashPaint;
  final Paint _crossPaint;
  final Paint _tickPaint;
  final Paint _majorTickPaint;

  Offset _vertexAt(Offset center, int index, double radius) {
    final angle = -math.pi / 2 + (2 * math.pi * index / _kAxisCount);
    return Offset(
      center.dx + radius * math.cos(angle),
      center.dy + radius * math.sin(angle),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    // ── 1. Range ring gradient fill (I-86: use solid paint segments) ──
    final bgPaint1 = Paint()..color = teal.atOpacity(0.02);
    final bgPaint2 = Paint()..color = teal.atOpacity(0.01);
    canvas.drawCircle(center, radarRadius * 0.5, bgPaint1);
    canvas.drawCircle(center, radarRadius * 0.8, bgPaint2);

    // ── 2. Range rings ──
    for (int ring = 1; ring <= _kGridRings; ring++) {
      final ringRadius = radarRadius * ring / _kGridRings;
      final ringPath = Path();
      for (int i = 0; i < _kAxisCount; i++) {
        final point = _vertexAt(center, i, ringRadius);
        if (i == 0) {
          ringPath.moveTo(point.dx, point.dy);
        } else {
          ringPath.lineTo(point.dx, point.dy);
        }
      }
      ringPath.close();
      canvas.drawPath(
        ringPath,
        ring == _kGridRings ? _outerGridPaint : _gridPaint,
      );

      // 🍒 #111: Range ring shimmer during entrance sweep.
      if (sweepProgress > 0 && sweepProgress < 1.0 && !reduceMotion) {
        final sweepAngle = -math.pi / 2 + (sweepProgress * 2 * math.pi);
        final shimmerSpan = math.pi / 3;
        final shimmerPaint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = ring == _kGridRings ? 1.5 : 1.0;
        for (int s = 0; s < 8; s++) {
          final t = s / 8;
          final segStart = sweepAngle - shimmerSpan / 2 + t * shimmerSpan;
          final distFromCenter = (t - 0.5).abs() * 2;
          shimmerPaint.color = teal.atOpacity((1.0 - distFromCenter) * 0.12);
          final arcPath = Path()
            ..addArc(
              Rect.fromCircle(center: center, radius: ringRadius * 0.93),
              segStart,
              shimmerSpan / 8,
            );
          canvas.drawPath(arcPath, shimmerPaint);
        }
      }

      // Range ring labels (pre-computed TPs).
      if (ringLabelPainters != null && ring - 1 < ringLabelPainters!.length) {
        final labelPos = _vertexAt(center, 1, ringRadius);
        ringLabelPainters![ring - 1].paint(
          canvas, Offset(labelPos.dx + 4, labelPos.dy - 4),
        );
      }
    }

    // ── 3. Bearing spokes ──
    for (int i = 0; i < _kAxisCount; i++) {
      final outerPoint = _vertexAt(center, i, radarRadius);
      canvas.drawLine(center, outerPoint, _spokePaint);
    }

    // ── 4. CIC sweep beam WITH PHOSPHOR TRAIL ──
    if (sweepProgress > 0 && sweepProgress < 1.0 && !reduceMotion) {
      final sweepAngle = -math.pi / 2 + (sweepProgress * 2 * math.pi);
      final trailPaint = Paint()..strokeWidth = 1.0..style = PaintingStyle.stroke;
      for (int s = 12; s >= 0; s--) {
        final t = s / 12;
        final segAngle = sweepAngle - (t * 30 * math.pi / 180);
        final segEnd = Offset(
          center.dx + radarRadius * 1.05 * math.cos(segAngle),
          center.dy + radarRadius * 1.05 * math.sin(segAngle),
        );
        trailPaint.color = teal.atOpacity(0.12 * (1.0 - t));
        canvas.drawLine(center, segEnd, trailPaint);
      }

      final sweepEnd = Offset(
        center.dx + radarRadius * 1.1 * math.cos(sweepAngle),
        center.dy + radarRadius * 1.1 * math.sin(sweepAngle),
      );
      final beamPaint = Paint()
        ..color = teal.atOpacity(0.25)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;
      canvas.drawLine(center, sweepEnd, beamPaint);

      final tipGlow = Paint()
        ..color = teal.atOpacity(0.15)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
      canvas.drawCircle(sweepEnd, 4, tipGlow);
    }

    // ── 4b. Scope perimeter degree ticks (🍒 105/106) ──
    final scopeRadius = radarRadius + 4;
    for (int deg = 0; deg < 360; deg += 5) {
      final tickAngle = (-90 + deg) * math.pi / 180;
      final isMajor = (deg % 72 == 0);
      final innerR = isMajor ? scopeRadius : scopeRadius + 2;
      final outerR = isMajor ? scopeRadius + 8 : scopeRadius + 4;
      canvas.drawLine(
        Offset(center.dx + innerR * math.cos(tickAngle),
               center.dy + innerR * math.sin(tickAngle)),
        Offset(center.dx + outerR * math.cos(tickAngle),
               center.dy + outerR * math.sin(tickAngle)),
        isMajor ? _majorTickPaint : _tickPaint,
      );
    }

    // ── 4c. Scope vignette (🍒 109) ──
    final vPaint1 = Paint()..color = BaselineColors.black.atOpacity(0.04);
    final vPaint2 = Paint()..color = BaselineColors.black.atOpacity(0.08);
    // Two-band approximation (I-86: eliminates radial gradient).
    canvas.drawCircle(center, radarRadius * 1.4, vPaint1);
    canvas.drawCircle(center, radarRadius * 1.3, vPaint2);

    // ── 5. Previous polygon (dashed, pre-computed I-80) ──
    if (cachedDashedSegments != null) {
      for (final seg in cachedDashedSegments!) {
        if (seg.length == 2) {
          canvas.drawLine(seg[0], seg[1], _dashPaint);
        }
      }
    }

    // ── 6. Current polygon ──
    final currentPath = Path();
    for (int i = 0; i < _kAxisCount; i++) {
      final value = i < currentValues.length
          ? currentValues[i].clamp(0.0, 1.0)
          : 0.0;
      final point = _vertexAt(center, i, radarRadius * value);
      if (i == 0) {
        currentPath.moveTo(point.dx, point.dy);
      } else {
        currentPath.lineTo(point.dx, point.dy);
      }
    }
    currentPath.close();

    // Solid fill (I-86: replaces gradient).
    final fillPaint = Paint()
      ..color = teal.atOpacity(0.14)
      ..style = PaintingStyle.fill;
    canvas.drawPath(currentPath, fillPaint);
    canvas.drawPath(currentPath, _strokePaint);

    // 🍒 104: Polygon bloom pulse.
    if (!reduceMotion) {
      final bloomSigma = 4.0 + (glowPulse * 4.0);
      final bloomPaint = Paint()
        ..color = teal.atOpacity(0.08 + glowPulse * 0.04)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, bloomSigma);
      canvas.drawPath(currentPath, bloomPaint);
    }

    // ── 7. Vertex acquisition nodes ──
    for (int i = 0; i < _kAxisCount; i++) {
      final value = i < currentValues.length
          ? currentValues[i].clamp(0.0, 1.0)
          : 0.0;
      final point = _vertexAt(center, i, radarRadius * value);

      // Bloom.
      final bloomPaint = Paint()
        ..color = teal.atOpacity(0.20)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
      canvas.drawCircle(point, 5, bloomPaint);

      // Node.
      final isSelected = selectedAxisIndex == i;
      final nodePaint = Paint()
        ..color = teal.atOpacity(isSelected ? 1.0 : 0.8);
      canvas.drawCircle(point, isSelected ? 4.5 : 3.5, nodePaint);

      // 🍒 112: Contact blip (square, blinks once on acquisition).
      if (entranceProgress > 0.5 + i * 0.05) {
        final blipPaint = Paint()
          ..color = teal.atOpacity(0.25)
          ..style = PaintingStyle.fill;
        canvas.drawRect(
          Rect.fromCenter(center: point, width: 3, height: 3),
          blipPaint,
        );
      }

      // 🍒 113: IFF flash (amber if delta >5%).
      if (isSelected && previousValues != null && !reduceMotion) {
        final prevVal = i < previousValues!.length ? previousValues![i] : 0.0;
        if ((value - prevVal).abs() > 0.05) {
          final iffPaint = Paint()
            ..color = BaselineColors.amber.atOpacity(0.15 + glowPulse * 0.1)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
          canvas.drawCircle(point, 8, iffPaint);
        }
      }

      // 🍒 110: Active targeting lock ring on selected.
      if (isSelected && !reduceMotion) {
        final lockRadius = 8.0 + glowPulse * 3.0;
        final lockPaint = Paint()
          ..color = teal.atOpacity(0.25 + glowPulse * 0.15)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0;
        canvas.drawCircle(point, lockRadius, lockPaint);

        final crossLen = 4.0 + glowPulse * 2.0;
        final cxPaint = Paint()
          ..color = teal.atOpacity(0.15)
          ..strokeWidth = 0.5;
        for (final dir in [
          const Offset(1, 0), const Offset(-1, 0),
          const Offset(0, 1), const Offset(0, -1),
        ]) {
          canvas.drawLine(
            point + dir * (lockRadius + 1),
            point + dir * (lockRadius + 1 + crossLen),
            cxPaint,
          );
        }
      }

      // 🍒 116: Track designation near vertex.
      if (trackDesignPainters != null && i < trackDesignPainters!.length) {
        final angle = -math.pi / 2 + (2 * math.pi * i / _kAxisCount);
        final tdOffset = Offset(
          point.dx + 8 * math.cos(angle),
          point.dy + 8 * math.sin(angle) - 3,
        );
        trackDesignPainters![i].paint(canvas, tdOffset);
      }
    }

    // ── 8. Pentagon edge traveling dot (C2: math lerp, no computeMetrics) ──
    if (edgeDotProgress >= 0) {
      final vertices = List.generate(_kAxisCount, (i) {
        final value = i < currentValues.length
            ? currentValues[i].clamp(0.0, 1.0)
            : 0.0;
        return _vertexAt(center, i, radarRadius * value);
      });
      double totalPerimeter = 0;
      final edgeLengths = <double>[];
      for (int i = 0; i < _kAxisCount; i++) {
        final next = (i + 1) % _kAxisCount;
        final len = (vertices[next] - vertices[i]).distance;
        edgeLengths.add(len);
        totalPerimeter += len;
      }
      if (totalPerimeter > 0) {
        final targetDist = edgeDotProgress * totalPerimeter;
        double cumulative = 0;
        for (int i = 0; i < _kAxisCount; i++) {
          final segLen = edgeLengths[i];
          if (cumulative + segLen >= targetDist || i == _kAxisCount - 1) {
            final frac = segLen > 0
                ? ((targetDist - cumulative) / segLen).clamp(0.0, 1.0)
                : 0.0;
            final next = (i + 1) % _kAxisCount;
            final pos = Offset.lerp(vertices[i], vertices[next], frac)!;
            final dotGlow = Paint()
              ..color = teal.atOpacity(0.3)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
            canvas.drawCircle(pos, 3, dotGlow);
            final dotSolid = Paint()..color = teal.atOpacity(0.6);
            canvas.drawCircle(pos, 1.5, dotSolid);
            break;
          }
          cumulative += segLen;
        }
      }
    }

    // ── 9. Center crosshair + glow ──
    canvas.drawLine(
      Offset(center.dx - 6, center.dy),
      Offset(center.dx + 6, center.dy),
      _crossPaint,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy - 6),
      Offset(center.dx, center.dy + 6),
      _crossPaint,
    );
    final glowPaintC = Paint()
      ..color = teal.atOpacity(0.35)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6.0);
    canvas.drawCircle(center, 3.0, glowPaintC);
    canvas.drawCircle(center, 2.0, Paint()..color = teal.atOpacity(0.8));

    // ── 10. Axis labels + signal pips + bearing indices (W1: pre-computed) ──
    for (int i = 0; i < _kAxisCount; i++) {
      final labelPoint = _vertexAt(center, i, radarRadius + labelOffset);
      final angle = -math.pi / 2 + (2 * math.pi * i / _kAxisCount);
      final cosA = math.cos(angle);
      final sinA = math.sin(angle);

      final value = i < currentValues.length
          ? currentValues[i].clamp(0.0, 1.0)
          : 0.0;

      // 🍒 108: Per-axis entrance factor.
      final axisEntranceStart = 0.55 + i * 0.05;
      final axisEntranceRaw =
          ((entranceProgress - axisEntranceStart) / 0.15).clamp(0.0, 1.0);
      final axisEntrance = reduceMotion
          ? 1.0
          : Curves.easeOut.transform(axisEntranceRaw);
      final displayValue = value * axisEntrance;

      // W1: Use pre-computed TP (includes textScaler from C3).
      final tp = axisLabelPainters != null && i < axisLabelPainters!.length
          ? axisLabelPainters![i]
          : null;
      if (tp == null) continue;

      // Direction-aware anchor.
      final double hFactor;
      if (cosA.abs() < 0.35) {
        hFactor = 0.5;
      } else if (cosA > 0) {
        hFactor = 0.0;
      } else {
        hFactor = 1.0;
      }
      final double vFactor;
      if (sinA < -0.15) {
        vFactor = 1.0;
      } else if (sinA > 0.15) {
        vFactor = 0.0;
      } else {
        vFactor = 0.5;
      }

      // Bearing painter (pre-computed).
      final bp = bearingPainters != null && i < bearingPainters!.length
          ? bearingPainters![i]
          : null;
      final bpHeight = bp?.height ?? 0;

      final clusterHeight = tp.height + 3 + _kPipMaxHeight + 2 + bpHeight;
      final clusterX = labelPoint.dx - tp.width * hFactor;
      final clusterY = labelPoint.dy - clusterHeight * vFactor;

      // W1: Type-in via clipRect (zero layout() per frame).
      final typeProgress = reduceMotion || entranceProgress >= 1.0
          ? 1.0
          : ((entranceProgress - axisEntranceStart) / 0.20).clamp(0.0, 1.0);
      final revealWidth = tp.width * typeProgress;

      canvas.save();
      canvas.clipRect(
        Rect.fromLTWH(clusterX, clusterY, revealWidth, tp.height),
      );
      tp.paint(canvas, Offset(clusterX, clusterY));
      canvas.restore();

      // 🍒 107: Blinking cursor during type-in.
      if (typeProgress < 1.0 && typeProgress > 0 && !reduceMotion) {
        final cursorX = clusterX + revealWidth + 1;
        final cursorPaint = Paint()
          ..color = teal.atOpacity(
            (entranceProgress * 16).floor().isEven ? 0.5 : 0.0,
          )
          ..strokeWidth = 1.0;
        canvas.drawLine(
          Offset(cursorX, clusterY + 1),
          Offset(cursorX, clusterY + tp.height - 1),
          cursorPaint,
        );
      }

      // Signal strength pips (🍒 108).
      final pipsWidth = _kPipCount * (_kPipWidth + 1) - 1;
      final pipBaseX = clusterX + (tp.width - pipsWidth) / 2;
      final pipY = clusterY + tp.height + 3;
      final filledPips = (displayValue * _kPipCount).ceil();
      for (int p = 0; p < _kPipCount; p++) {
        final pipHeight = _kPipMaxHeight * (p + 1) / _kPipCount;
        final isFilled = p < filledPips;
        canvas.drawRect(
          Rect.fromLTWH(
            pipBaseX + p * (_kPipWidth + 1),
            pipY + (_kPipMaxHeight - pipHeight),
            _kPipWidth,
            pipHeight,
          ),
          Paint()..color = teal.atOpacity(isFilled ? 0.5 : 0.08),
        );
      }

      // Bearing index (pre-computed).
      if (bp != null) {
        bp.paint(
          canvas,
          Offset(
            clusterX + (tp.width - bp.width) / 2,
            pipY + _kPipMaxHeight + 2,
          ),
        );
      }

      // 🍒 116: Track designation near vertex.
      if (trackDesignPainters != null && i < trackDesignPainters!.length) {
        final vertAngle = -math.pi / 2 + (2 * math.pi * i / _kAxisCount);
        final vertValue = value;
        final vertPoint = _vertexAt(center, i, radarRadius * vertValue);
        final tdOffset = Offset(
          vertPoint.dx + 8 * math.cos(vertAngle),
          vertPoint.dy + 8 * math.sin(vertAngle) - 3,
        );
        trackDesignPainters![i].paint(canvas, tdOffset);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PentagonRadarPainter old) {
    return old.currentValues != currentValues ||
        old.previousValues != previousValues ||
        old.sweepProgress != sweepProgress ||
        old.edgeDotProgress != edgeDotProgress ||
        old.glowPulse != glowPulse ||
        old.entranceProgress != entranceProgress ||
        old.selectedAxisIndex != selectedAxisIndex;
  }
}

// ═══════════════════════════════════════════════════════════
// LEGEND DOT PAINTER (I-71)
// ═══════════════════════════════════════════════════════════

class _LegendDotPainter extends CustomPainter {
  _LegendDotPainter({required this.color, required this.filled})
      : _paint = filled
            ? (Paint()..color = color)
            : (Paint()
                ..color = color.atOpacity(0.5)
                ..style = PaintingStyle.stroke
                ..strokeWidth = 1.5);

  final Color color;
  final bool filled;
  final Paint _paint;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawCircle(
      Offset(size.width / 2, size.height / 2),
      size.width / 2,
      _paint,
    );
  }

  @override
  bool shouldRepaint(covariant _LegendDotPainter old) =>
      old.color != color || old.filled != filled;
}

// ═══════════════════════════════════════════════════════════
// GHOST PENTAGON PAINTER (insufficient data placeholder)
// ═══════════════════════════════════════════════════════════

class _GhostPentagonPainter extends CustomPainter {
  _GhostPentagonPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = math.min(cx, cy) - 4;

    final dashPaint = Paint()
      ..color = color.atOpacity(0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;

    final dotPaint = Paint()
      ..color = color.atOpacity(0.15);

    // Compute 5 vertices.
    final vertices = <Offset>[];
    for (int i = 0; i < 5; i++) {
      final angle = (i * 2 * math.pi / 5) - (math.pi / 2);
      vertices.add(Offset(cx + r * math.cos(angle), cy + r * math.sin(angle)));
    }

    // Draw dashed edges.
    for (int i = 0; i < 5; i++) {
      final from = vertices[i];
      final to = vertices[(i + 1) % 5];
      _drawDashedLine(canvas, from, to, dashPaint);
    }

    // Draw dashed spokes from center to each vertex.
    final center = Offset(cx, cy);
    for (final v in vertices) {
      _drawDashedLine(canvas, center, v, dashPaint);
    }

    // Center dot.
    canvas.drawCircle(center, 2.5, dotPaint);
  }

  void _drawDashedLine(Canvas canvas, Offset from, Offset to, Paint paint) {
    final dx = to.dx - from.dx;
    final dy = to.dy - from.dy;
    final dist = math.sqrt(dx * dx + dy * dy);
    const dashLen = 4.0;
    const gapLen = 3.0;
    final steps = (dist / (dashLen + gapLen)).floor();
    final ux = dx / dist;
    final uy = dy / dist;

    for (int i = 0; i < steps; i++) {
      final sx = from.dx + (dashLen + gapLen) * i * ux;
      final sy = from.dy + (dashLen + gapLen) * i * uy;
      final ex = sx + dashLen * ux;
      final ey = sy + dashLen * uy;
      canvas.drawLine(Offset(sx, sy), Offset(ex, ey), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GhostPentagonPainter old) =>
      old.color != color;
}
