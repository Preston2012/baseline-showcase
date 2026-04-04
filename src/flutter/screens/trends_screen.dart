/// F4.13 — Trends Dashboard Screen (PRE_AUDIT)
///
/// VISUAL STORY: LONGITUDINAL SIGNAL OBSERVATORY
/// Signal monitoring station locked onto a political figure's speech
/// emissions over time. Precision oscilloscope trace. Instrument-grade
/// period recalibration. Bloomberg Terminal meets classified SIGINT.
///
/// 6 METRICS (from TrendMetric enum — F3.15):
///   signalRank, repetition, novelty, affect, entropy, baselineDelta
///
/// ANIMATIONS (6 controllers):
///   _chartCtrl — chart path draw (600ms easeOutCubic)
///   _recalCtrl — A-13 recalibration sequence (600ms)
///   _entranceCtrl — phased screen entrance (1200ms)
///   _countUpCtrl — numeral count-up (800ms easeOutCubic)
///   _epicenterCtrl — tap epicenter pulse (500ms)
///   _breathCtrl — pulsing dot + value card halo (3000ms repeat)
///
/// ENTRANCE CHOREOGRAPHY (5 phases over 1200ms):
///   Phase 1 (0-200ms): Chrome draws in (brackets + rulers)
///   Phase 2 (100-400ms): Grid lines materialize
///   Phase 3 (200-800ms): Trace races across chart
///   Phase 4 (600-1000ms): Dots ping in sequence
///   Phase 5 (800-1200ms): Value card + count slide up
///
/// Path: lib/screens/trends_screen.dart
library;
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:baseline_app/config/constants.dart';
import 'package:baseline_app/config/theme.dart';
import 'package:baseline_app/config/routes.dart';
import 'package:baseline_app/models/figure.dart';
import 'package:baseline_app/models/trends.dart';
import 'package:baseline_app/services/entitlement_service.dart';
import 'package:baseline_app/services/figures_service.dart';
import 'package:baseline_app/services/trends_service.dart';
import 'package:baseline_app/utils/haptic_util.dart';
import 'package:baseline_app/widgets/baseline_icons.dart';
import 'package:baseline_app/widgets/empty_state.dart';
import 'package:baseline_app/widgets/shimmer_loading.dart';
import 'package:baseline_app/widgets/info_bottom_sheet.dart';
import 'package:baseline_app/widgets/empty_state_widget.dart';
import 'package:baseline_app/widgets/error_state.dart';

// ═══════════════════════════════════════════════════════════
// DATE HELPERS (replaces package:intl)
// ═══════════════════════════════════════════════════════════
const _kMonths = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
String _fmtDateMD(DateTime d) => '${_kMonths[d.month - 1]} ${d.day}';
String _fmtDateMDY(DateTime d) => '${_kMonths[d.month - 1]} ${d.day}, ${d.year}';

// ═══════════════════════════════════════════════════════════
// LAYOUT CONSTANTS
// ═══════════════════════════════════════════════════════════

/// Icon touch target (WCAG AA minimum).
const double _kIconTouchTarget = 44.0;

/// Accent line height (matches F4.9/F4.10/F4.11).
const double _kAccentLineHeight = 2.0;

/// Border opacity (WCAG compliant — matches F4.8+ pattern).
const double _kBorderOpacity = 0.5;

/// Interactive border width (hitlist: 2px on interactive/card elements).
const double _kInteractiveBorderWidth = 2.0;

/// Chart height as fraction of available width.
const double _kChartHeightFraction = 0.55;

/// Maximum chart height.
const double _kChartMaxHeight = 280.0;

/// Minimum chart height.
const double _kChartMinHeight = 180.0;

/// Chart left padding (for amplitude gauge).
const double _kChartPaddingLeft = 52.0;

/// Chart right padding.
const double _kChartPaddingRight = 16.0;

/// Chart top padding (for top value headroom).
const double _kChartPaddingTop = 20.0;

/// Chart bottom padding (for X-axis labels).
const double _kChartPaddingBottom = 28.0;

/// Number of target horizontal grid lines.
const int _kGridLineCount = 5;

/// Period pill height (matches F4.10).
const double _kPillHeight = 36.0;

/// Period pill border radius (matches F4.10).
const double _kPillRadius = 18.0;

/// Metric pill height.
const double _kMetricPillHeight = 32.0;

/// Metric pill border radius.
const double _kMetricPillRadius = 16.0;

/// Metric pill horizontal padding.
const double _kMetricPillHPadding = 14.0;

/// Chart animation duration.
const Duration _kChartAnimDuration = Duration(milliseconds: 600);

/// Entrance animation duration (5 phases).
const Duration _kEntranceDuration = Duration(milliseconds: 1200);

/// Count-up animation duration.
const Duration _kCountUpDuration = Duration(milliseconds: 800);

/// Recalibration animation duration (A-13).
const Duration _kRecalDuration = Duration(milliseconds: 600);

/// Breathing animation duration (pulsing dot + value card halo).
const Duration _kBreathDuration = Duration(milliseconds: 3000);

/// Color transition duration (period + metric toggles).
const Duration _kColorTransitionDuration = Duration(milliseconds: 200);

/// Metric pill stagger delay.
const Duration _kMetricStaggerDelay = Duration(milliseconds: 30);

/// Chart line stroke width.
const double _kLineStrokeWidth = 2.5;

/// Chart line glow blur sigma.
const double _kLineGlowSigma = 4.0;

/// Chart dot radius (data points).
const double _kDotRadius = 4.0;

/// Active dot radius (selected/touched).
const double _kActiveDotRadius = 6.0;

/// Grid line stroke width.
const double _kGridStrokeWidth = 0.5;

/// Crosshair line width.
const double _kCrosshairWidth = 1.0;

/// Minimum X-axis label spacing.
const double _kMinLabelSpacing = 50.0;

/// Hit test snap distance.
const double _kHitTestThreshold = 20.0;

/// Data font family — dart:ui contexts only (I-10).
const String _kDataFontFamily = 'JetBrainsMono';

/// Epicenter pulse max radius.
const double _kEpicenterMaxRadius = 28.0;

/// Epicenter pulse duration.
const Duration _kEpicenterDuration = Duration(milliseconds: 500);

/// Chrome dot grid spacing.
const double _kDotGridSpacing = 24.0;

/// Chrome corner bracket length.
const double _kBracketLength = 14.0;

/// Baseline reference line dash length.
const double _kBaselineDashLength = 4.0;

/// Baseline reference line gap length.
const double _kBaselineGapLength = 3.0;

/// Press-scale factor for metric pills.
const double _kPillPressScale = 0.95;

/// Entitlement error codes that route to paywall.
const Set<String> _kPaywallErrorCodes = {
  'not_entitled',
  'feature_gated',
};

/// Temporary error codes (not paywall).
const Set<String> _kTempErrorCodes = {
  'rate_limited',
};

// ═══════════════════════════════════════════════════════════
// TRENDS SCREEN
// ═══════════════════════════════════════════════════════════

class TrendsScreen extends StatefulWidget {
  const TrendsScreen({
    super.key,
    required this.figureId,
  });

  /// Figure UUID from route parameter.
  final String figureId;

  @override
  State<TrendsScreen> createState() => _TrendsScreenState();
}

class _TrendsScreenState extends State<TrendsScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  // ── Services (TODO F7.5: replace with Riverpod providers) ──
  final FiguresService _figuresService = FiguresService();
  final TrendsService _trendsService = TrendsService();

  // ── State ──
  bool _isLoading = true;
  bool _isChartLoading = false;
  bool _disposed = false;
  String? _errorMessage;
  String? _errorCode;
  String? _figureName;
  MetricTimeline? _timeline;
  TrendMetric _selectedMetric = TrendMetric.signalRank;
  TrendPeriod _selectedPeriod = TrendPeriod.ninetyDays;

  /// Index of currently touched/selected data point (-1 = none).
  int _selectedPointIndex = -1;

  /// Guard against double paywall push.
  bool _didRouteToPaywall = false;

  /// Whether the entrance animation has played.
  bool _didEntrance = false;

  // ── Timer tracking (I-11) ──
  final List<Timer> _pendingTimers = [];

  // ── A-13: Recalibration state ──
  int _wipeDirection = 0;
  bool _isRecalibrating = false;
  Timer? _recalTimer;
  final List<GlobalKey> _pillKeys = List.generate(
    TrendPeriod.values.length,
    (_) => GlobalKey(),
  );
  final GlobalKey _selectorKey = GlobalKey();
  double _pillIndicatorLeft = 0;
  double _pillIndicatorWidth = 0;

  // ── Epicenter pulse state ──
  Offset? _epicenterOrigin;

  // ── Tooltip state ──
  Offset? _tooltipAnchor;

  // ── Signal lock flash ──
  bool _showSignalLock = false;

  // ── Metric change mini-wipe ──
  bool _isMetricWiping = false;

  // ── Refresh narrative ──
  bool _isReacquiring = false;

  // ── Pre-computed DTG (I-45) ──
  String _dtgStamp = '';

  // ── Pre-computed scaled font sizes (A2-M1) ──
  double _scaledLabelSize = 10.0;
  double _scaledSmallSize = 9.0;
  double _scaledMicroSize = 6.0;
  double _scaledChromeDtgSize = 7.0;
  double _scaledChromeHandleSize = 6.0;
  TextScaler _textScaler = TextScaler.noScaling;

  // ── Pre-computed chrome paragraphs (A2-C3 / A2-I1) ──
  ui.Paragraph? _dtgParagraph;
  ui.Paragraph? _handleParagraph;

  // ── Pre-computed gradient (A2-I2) ──
  double _lastChartWidth = 0;
  double _lastPlotTop = 0;
  double _lastPlotBottom = 0;
  ui.Gradient? _fillGradientShader;

  // ── Pre-computed chart label paragraphs (A2-C3) ──
  /// Y-axis: list of (gridValue, paragraph) pairs.
  List<(double, ui.Paragraph)> _yLabelParagraphs = [];
  /// X-axis: list of paragraphs matching each dataPoint date.
  List<ui.Paragraph> _xLabelParagraphs = [];
  /// BASELINE ghost label.
  ui.Paragraph? _baselineLabelParagraph;
  /// Cached grid values for Y-axis positioning in painter.
  List<double> _cachedGridValues = [];

  // ── Cached metric pill CurvedAnimations (I-15 / leak fix) ──
  List<CurvedAnimation>? _metricPillAnims;

  // ── Animation Controllers ──
  late final AnimationController _chartCtrl;
  late final AnimationController _recalCtrl;
  late final AnimationController _entranceCtrl;
  late final AnimationController _countUpCtrl;
  late final AnimationController _epicenterCtrl;
  late final AnimationController _breathCtrl;

  // ── Curved Animations ──
  late final CurvedAnimation _chartAnim;
  late final CurvedAnimation _entranceAnim;
  late final CurvedAnimation _countUpAnim;

  // ── Entrance phase intervals ──
  late final CurvedAnimation _chromePhase;
  late final CurvedAnimation _gridPhase;
  late final CurvedAnimation _tracePhase;
  late final CurvedAnimation _dotsPhase;
  late final CurvedAnimation _cardsPhase;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Chart path draw.
    _chartCtrl = AnimationController(
      vsync: this,
      duration: _kChartAnimDuration,
    );
    _chartAnim = CurvedAnimation(
      parent: _chartCtrl,
      curve: Curves.easeOutCubic,
    );

    // A-13 recalibration sequence.
    _recalCtrl = AnimationController(
      vsync: this,
      duration: _kRecalDuration,
    );
    _recalCtrl.addStatusListener(_onRecalStatus);

    // Entrance choreography.
    _entranceCtrl = AnimationController(
      vsync: this,
      duration: _kEntranceDuration,
    );
    _entranceAnim = CurvedAnimation(
      parent: _entranceCtrl,
      curve: Curves.easeOut,
    );
    _chromePhase = CurvedAnimation(
      parent: _entranceCtrl,
      curve: const Interval(0.0, 0.17, curve: Curves.easeOut),
    );
    _gridPhase = CurvedAnimation(
      parent: _entranceCtrl,
      curve: const Interval(0.08, 0.33, curve: Curves.easeOut),
    );
    _tracePhase = CurvedAnimation(
      parent: _entranceCtrl,
      curve: const Interval(0.17, 0.67, curve: Curves.easeOutCubic),
    );
    _dotsPhase = CurvedAnimation(
      parent: _entranceCtrl,
      curve: const Interval(0.50, 0.83, curve: Curves.easeOut),
    );
    _cardsPhase = CurvedAnimation(
      parent: _entranceCtrl,
      curve: const Interval(0.67, 1.0, curve: Curves.easeOutCubic),
    );

    // Count-up numerals.
    _countUpCtrl = AnimationController(
      vsync: this,
      duration: _kCountUpDuration,
    );
    _countUpAnim = CurvedAnimation(
      parent: _countUpCtrl,
      curve: Curves.easeOutCubic,
    );

    // Epicenter pulse.
    _epicenterCtrl = AnimationController(
      vsync: this,
      duration: _kEpicenterDuration,
    );

    // 🍒27: Breathing controller for pulsing dot + value card halo.
    _breathCtrl = AnimationController(
      vsync: this,
      duration: _kBreathDuration,
    );

    _refreshDtg();
    _loadData();

    // I-14: Haptic on screen entry.
    HapticUtil.medium();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // A2-M1: Pre-compute scaled font sizes.
    _textScaler = MediaQuery.textScalerOf(context);
    _scaledLabelSize = _textScaler.scale(10);
    _scaledSmallSize = _textScaler.scale(9);
    _scaledMicroSize = _textScaler.scale(6);
    _scaledChromeDtgSize = _textScaler.scale(7);
    _scaledChromeHandleSize = _textScaler.scale(6);

    // A2-C3 / A2-I1: Pre-compute chrome paragraphs.
    _rebuildChromeParagraphs();

    // A2-C3: Pre-compute chart label paragraphs.
    _buildChartLabelCache();

    // A-13: Remeasure pill on layout/text scale changes.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_disposed) _measurePill();
    });
  }

  /// Pre-compute chrome paragraphs (DTG + handling mark).
  void _rebuildChromeParagraphs() {
    // DTG paragraph.
    if (_dtgStamp.isNotEmpty) {
      final dtgBuilder = ui.ParagraphBuilder(
        ui.ParagraphStyle(
          fontSize: _scaledChromeDtgSize,
          fontFamily: _kDataFontFamily,
        ),
      )
        ..pushStyle(ui.TextStyle(
          color: BaselineColors.teal.atOpacity(0.03),
          fontSize: _scaledChromeDtgSize,
          fontFamily: _kDataFontFamily,
          letterSpacing: 0.5,
        ))
        ..addText(_dtgStamp);
      _dtgParagraph = dtgBuilder.build()
        ..layout(const ui.ParagraphConstraints(width: 160));
    }

    // Handling mark paragraph.
    final handleBuilder = ui.ParagraphBuilder(
      ui.ParagraphStyle(
        fontSize: _scaledChromeHandleSize,
        fontFamily: _kDataFontFamily,
      ),
    )
      ..pushStyle(ui.TextStyle(
        color: BaselineColors.teal.atOpacity(0.03),
        fontSize: _scaledChromeHandleSize,
        fontFamily: _kDataFontFamily,
        letterSpacing: 1.0,
      ))
      ..addText('HANDLE VIA BASELINE CHANNELS ONLY');
    _handleParagraph = handleBuilder.build()
      ..layout(const ui.ParagraphConstraints(width: 250));
  }

  /// A2-C3: Pre-compute chart label paragraphs (Y-axis, X-axis, BASELINE).
  /// Called after data loads or text scale changes.
  void _buildChartLabelCache() {
    final timeline = _timeline;
    if (timeline == null || timeline.dataPoints.isEmpty) return;

    // ── Y-axis labels ──
    final dataPoints = timeline.dataPoints;
    double minVal = dataPoints.first.value;
    double maxVal = dataPoints.first.value;
    for (final dp in dataPoints) {
      if (dp.value < minVal) minVal = dp.value;
      if (dp.value > maxVal) maxVal = dp.value;
    }
    final range = math.max(maxVal - minVal, 5.0);
    final yPadding = range * 0.1;
    final yMin = math.max(0.0, minVal - yPadding);
    final yMax = math.min(100.0, maxVal + yPadding);

    _cachedGridValues = _computeNiceGridValues(yMin, yMax, 5);
    final labelColor = BaselineColors.textSecondary;

    _yLabelParagraphs = _cachedGridValues.map((gv) {
      final builder = ui.ParagraphBuilder(
        ui.ParagraphStyle(
          textAlign: TextAlign.right,
          fontSize: _scaledLabelSize,
          fontFamily: _kDataFontFamily,
        ),
      )
        ..pushStyle(ui.TextStyle(
          color: labelColor,
          fontSize: _scaledLabelSize,
          fontFamily: _kDataFontFamily,
        ))
        ..addText(gv.toStringAsFixed(0));
      final p = builder.build()
        ..layout(const ui.ParagraphConstraints(
          width: _kChartPaddingLeft - 14,
        ));
      return (gv, p);
    }).toList();

    // ── X-axis labels ──
    _xLabelParagraphs = dataPoints.map((dp) {
      final builder = ui.ParagraphBuilder(
        ui.ParagraphStyle(
          textAlign: TextAlign.center,
          fontSize: _scaledSmallSize,
          fontFamily: _kDataFontFamily,
        ),
      )
        ..pushStyle(ui.TextStyle(
          color: labelColor,
          fontSize: _scaledSmallSize,
          fontFamily: _kDataFontFamily,
        ))
        ..addText(_fmtDateMD(dp.date));
      final p = builder.build()
        ..layout(const ui.ParagraphConstraints(width: 60));
      return p;
    }).toList();

    // ── BASELINE ghost label ──
    final blBuilder = ui.ParagraphBuilder(
      ui.ParagraphStyle(
        fontSize: _scaledMicroSize,
        fontFamily: _kDataFontFamily,
      ),
    )
      ..pushStyle(ui.TextStyle(
        color: BaselineColors.teal,
        fontSize: _scaledMicroSize,
        fontFamily: _kDataFontFamily,
        letterSpacing: 1.5,
      ))
      ..addText('BASELINE');
    _baselineLabelParagraph = blBuilder.build()
      ..layout(const ui.ParagraphConstraints(width: 60));
  }

  /// Compute nice grid values (extracted for reuse).
  static List<double> _computeNiceGridValues(
    double min,
    double max,
    int targetCount,
  ) {
    final range = max - min;
    if (range <= 0) return [min];
    final rawStep = range / (targetCount - 1);
    final magnitude =
        math.pow(10, (math.log(rawStep) / math.ln10).floor());
    final residual = rawStep / magnitude;
    double niceStep;
    if (residual <= 1.5) {
      niceStep = magnitude.toDouble();
    } else if (residual <= 3.5) {
      niceStep = 2.0 * magnitude;
    } else if (residual <= 7.5) {
      niceStep = 5.0 * magnitude;
    } else {
      niceStep = 10.0 * magnitude;
    }
    final niceMin = (min / niceStep).floor() * niceStep;
    final values = <double>[];
    for (double v = niceMin; v <= max + niceStep * 0.01; v += niceStep) {
      if (v >= min - niceStep * 0.01) values.add(v);
    }
    return values;
  }

  /// I-9 / 3N: Mid-flight reduceMotion change.
  @override
  void didChangeAccessibilityFeatures() {
    super.didChangeAccessibilityFeatures();
    // A2-C1: PlatformDispatcher in observer (outside build phase).
    final reduceMotion =
        ui.PlatformDispatcher.instance.accessibilityFeatures.reduceMotion;
    if (reduceMotion) {
      // Snap all controllers to end.
      _entranceCtrl.value = 1.0;
      _chartCtrl.value = 1.0;
      _countUpCtrl.value = 1.0;
      _recalCtrl.stop();
      _epicenterCtrl.stop();
      _breathCtrl.stop();
      for (final t in _pendingTimers) {
        t.cancel();
      }
      _pendingTimers.clear();
      if (mounted) {
        setState(() {
          _isRecalibrating = false;
          _showSignalLock = false;
          _isMetricWiping = false;
          _isReacquiring = false;
        });
      }
    } else {
      // Resume breathing if stopped.
      if (!_breathCtrl.isAnimating) {
        _breathCtrl.repeat();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);

    // Cancel timers first.
    _recalTimer?.cancel();
    for (final t in _pendingTimers) {
      t.cancel();
    }
    _pendingTimers.clear();

    // Remove listeners.
    _recalCtrl.removeStatusListener(_onRecalStatus);

    // Dispose cached metric pill CurvedAnimations.
    if (_metricPillAnims != null) {
      for (final a in _metricPillAnims!) {
        a.dispose();
      }
    }

    // Dispose CurvedAnimations before parents (I-15).
    _chartAnim.dispose();
    _entranceAnim.dispose();
    _countUpAnim.dispose();
    _chromePhase.dispose();
    _gridPhase.dispose();
    _tracePhase.dispose();
    _dotsPhase.dispose();
    _cardsPhase.dispose();

    // Stop then dispose controllers (I-29).
    _chartCtrl
      ..stop()
      ..dispose();
    _recalCtrl
      ..stop()
      ..dispose();
    _entranceCtrl
      ..stop()
      ..dispose();
    _countUpCtrl
      ..stop()
      ..dispose();
    _epicenterCtrl
      ..stop()
      ..dispose();
    _breathCtrl
      ..stop()
      ..dispose();

    super.dispose();
  }

  // ── DTG caching (I-45) ──
  void _refreshDtg() {
    final now = DateTime.now().toUtc();
    final day = now.day.toString().padLeft(2, '0');
    final hour = now.hour.toString().padLeft(2, '0');
    final min = now.minute.toString().padLeft(2, '0');
    const months = [
      'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
      'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC',
    ];
    _dtgStamp = '$day$hour${min}Z ${months[now.month - 1]} ${now.year}';
    // A2-C3: Rebuild pre-computed chrome paragraphs when DTG changes.
    _rebuildChromeParagraphs();
  }

  void _onRecalStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      if (!_disposed) setState(() => _isRecalibrating = false);
    }
  }

  // ── A-13: Pill measurement ──────────────────────────────

  void _measurePill() {
    final idx = TrendPeriod.values.indexOf(_selectedPeriod);
    final key = _pillKeys[idx];
    final ro = key.currentContext?.findRenderObject() as RenderBox?;
    final selectorRO =
        _selectorKey.currentContext?.findRenderObject() as RenderBox?;
    if (ro == null || selectorRO == null) {
      // Retry once after next frame (first build race).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _disposed) return;
        final ro2 =
            key.currentContext?.findRenderObject() as RenderBox?;
        final sel2 = _selectorKey.currentContext?.findRenderObject()
            as RenderBox?;
        if (ro2 == null || sel2 == null) return;
        final pos = ro2.localToGlobal(Offset.zero, ancestor: sel2);
        setState(() {
          _pillIndicatorLeft = pos.dx;
          _pillIndicatorWidth = ro2.size.width;
        });
      });
      return;
    }
    final pos = ro.localToGlobal(Offset.zero, ancestor: selectorRO);
    setState(() {
      _pillIndicatorLeft = pos.dx;
      _pillIndicatorWidth = ro.size.width;
    });
  }

  // ── Cached metric pill anims (🍒28 / leak fix) ──────────

  List<CurvedAnimation> _getOrCreateMetricPillAnims() {
    if (_metricPillAnims != null &&
        _metricPillAnims!.length == TrendMetric.values.length) {
      return _metricPillAnims!;
    }
    // Dispose old ones if count changed.
    if (_metricPillAnims != null) {
      for (final a in _metricPillAnims!) {
        a.dispose();
      }
    }
    _metricPillAnims = List.generate(TrendMetric.values.length, (index) {
      final staggerDelay =
          index * _kMetricStaggerDelay.inMilliseconds;
      final staggerStart =
          (0.67 + staggerDelay / _kEntranceDuration.inMilliseconds)
              .clamp(0.0, 0.95);
      return CurvedAnimation(
        parent: _entranceCtrl,
        curve: Interval(
          staggerStart,
          (staggerStart + 0.15).clamp(0.0, 1.0),
          curve: Curves.easeOut,
        ),
      );
    });
    return _metricPillAnims!;
  }

  // ── Data Loading ────────────────────────────────────────

  Future<void> _loadData() async {
    _didRouteToPaywall = false;
    if (!_disposed) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
        _errorCode = null;
      });
    }

    try {
      final results = await Future.wait([
        _figuresService.getFigure(widget.figureId),
        _fetchTimeline(),
      ]);
      if (!mounted || _disposed) return;

      final figure = results[0] as Figure;
      final timeline = results[1] as MetricTimeline;

      setState(() {
        _figureName = figure.name;
        _timeline = timeline;
        _isLoading = false;
        _selectedPointIndex = -1;
      });
      _buildChartLabelCache();

      final reduceMotion = MediaQuery.disableAnimationsOf(context);

      // Entrance choreography (first load only).
      if (!_didEntrance && !reduceMotion) {
        _didEntrance = true;
        _entranceCtrl.forward(from: 0.0);
        // Chain chart animation after trace phase starts.
        final t1 = Timer(const Duration(milliseconds: 200), () {
          if (mounted && !_disposed) _chartCtrl.forward(from: 0.0);
        });
        _pendingTimers.add(t1);
        // Chain count-up after cards phase starts.
        final t2 = Timer(const Duration(milliseconds: 800), () {
          if (mounted && !_disposed) _countUpCtrl.forward(from: 0.0);
        });
        _pendingTimers.add(t2);
      } else {
        _didEntrance = true;
        _entranceCtrl.value = 1.0;
        _chartCtrl.forward(from: 0.0);
        _countUpCtrl.forward(from: 0.0);
      }

      // Start breathing loop now that data is loaded and motion is confirmed.
      if (!reduceMotion && !_breathCtrl.isAnimating) {
        _breathCtrl.repeat();
      }

      // Measure pill after layout.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_disposed) _measurePill();
      });

      // 🍒17: "SIGNAL LOCK" flash on successful acquisition.
      if (!reduceMotion) {
        setState(() => _showSignalLock = true);
        final t3 = Timer(const Duration(milliseconds: 1200), () {
          if (mounted && !_disposed) {
            setState(() => _showSignalLock = false);
          }
        });
        _pendingTimers.add(t3);
      }
    } catch (e) {
      if (!mounted || _disposed) return;
      _handleError(e);
    }
  }

  Future<MetricTimeline> _fetchTimeline() async {
    final entitlementService = const EntitlementService();
    final entitlement = await entitlementService.checkEntitlement(
      endpoint: 'get-trends',
      featureFlag: 'ENABLE_TRENDS',
    );
    return _trendsService.getMetricTimeline(
      figureId: widget.figureId,
      metric: _selectedMetric,
      period: _selectedPeriod,
      granularity: _granularityForPeriod(_selectedPeriod),
      entitlementToken: entitlement.token,
    );
  }

  TrendGranularity _granularityForPeriod(TrendPeriod period) {
    switch (period) {
      case TrendPeriod.thirtyDays:
        return TrendGranularity.day;
      case TrendPeriod.ninetyDays:
        return TrendGranularity.week;
      case TrendPeriod.oneYear:
        return TrendGranularity.month;
    }
  }

  void _handleError(Object error) {
    final message = error is TrendsServiceException
        ? error.message
        : error is EntitlementServiceException
            ? error.message
            : 'Something went wrong.';
    final code = error is TrendsServiceException
        ? error.code
        : error is EntitlementServiceException
            ? error.code
            : null;

    if (code != null && _kPaywallErrorCodes.contains(code)) {
      if (!_didRouteToPaywall) {
        _didRouteToPaywall = true;
        context.push(AppRoutes.paywall);
      }
      return;
    }

    if (code != null && _kTempErrorCodes.contains(code)) {
      if (!_disposed) {
        setState(() {
          _isLoading = false;
          _isChartLoading = false;
          _errorMessage = 'Try again shortly.';
          _errorCode = code;
        });
      }
      return;
    }

    if (code == 'feature_disabled') {
      if (!_disposed) {
        setState(() {
          _isLoading = false;
          _isChartLoading = false;
          _errorMessage = 'Temporarily unavailable.';
          _errorCode = code;
        });
      }
      return;
    }

    if (!_disposed) {
      setState(() {
        _isLoading = false;
        _isChartLoading = false;
        _errorMessage = message;
        _errorCode = code;
      });
    }
  }

  // ── Selection Handlers ──────────────────────────────────

  /// A-13: Full recalibration sequence on period change.
  void _onPeriodChanged(TrendPeriod newPeriod) {
    if (newPeriod == _selectedPeriod) return;

    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final oldIdx = TrendPeriod.values.indexOf(_selectedPeriod);
    final newIdx = TrendPeriod.values.indexOf(newPeriod);
    _wipeDirection = newIdx > oldIdx ? -1 : 1;

    HapticUtil.selection();

    // Cancel any in-flight recalibration.
    _recalTimer?.cancel();
    _recalTimer = null;

    // Update pill indicator immediately.
    setState(() {
      _selectedPeriod = newPeriod;
      _selectedPointIndex = -1;
      _tooltipAnchor = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_disposed) _measurePill();
    });

    if (reduceMotion) {
      _isChartLoading = true;
      _reloadChart();
      return;
    }

    // Start recalibration sequence.
    _isRecalibrating = true;
    _recalCtrl.forward(from: 0);

    // At midpoint: fire data fetch + confirmation haptic.
    _recalTimer = Timer(const Duration(milliseconds: 300), () {
      if (!mounted || _disposed) return;
      HapticUtil.light();
      setState(() => _isChartLoading = true);
      _reloadChart();
    });
  }

  void _onMetricChanged(TrendMetric metric) {
    if (metric == _selectedMetric) return;
    HapticUtil.selection();

    // 🍒 Treatment 46: Metric change mini-wipe.
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (!reduceMotion) {
      setState(() => _isMetricWiping = true);
      final t = Timer(const Duration(milliseconds: 100), () {
        if (mounted && !_disposed) {
          setState(() => _isMetricWiping = false);
        }
      });
      _pendingTimers.add(t);
    }

    setState(() {
      _selectedMetric = metric;
      _selectedPointIndex = -1;
      _isChartLoading = true;
      _tooltipAnchor = null;
    });
    _reloadChart();
  }

  Future<void> _reloadChart() async {
    try {
      final timeline = await _fetchTimeline();
      if (!mounted || _disposed) return;
      setState(() {
        _timeline = timeline;
        _isChartLoading = false;
        _errorMessage = null;
        _errorCode = null;
      });
      _buildChartLabelCache();
      _chartCtrl.forward(from: 0.0);
      _countUpCtrl.forward(from: 0.0);
    } catch (e) {
      if (!mounted || _disposed) return;
      _handleError(e);
    }
  }

  Future<void> _onRefresh() async {
    _didRouteToPaywall = false;

    // 🍒 Treatment 145: "REACQUIRING SIGNAL" during refresh.
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (!reduceMotion) {
      setState(() => _isReacquiring = true);
    }

    try {
      final timeline = await _fetchTimeline();
      if (!mounted || _disposed) return;
      setState(() {
        _timeline = timeline;
        _selectedPointIndex = -1;
        _errorMessage = null;
        _errorCode = null;
        _tooltipAnchor = null;
        _isReacquiring = false;
      });
      _buildChartLabelCache();
      _chartCtrl.forward(from: 0.0);
      _countUpCtrl.forward(from: 0.0);

      // Trigger signal lock flash on refresh too.
      if (!reduceMotion) {
        setState(() => _showSignalLock = true);
        final t = Timer(const Duration(milliseconds: 1200), () {
          if (mounted && !_disposed) {
            setState(() => _showSignalLock = false);
          }
        });
        _pendingTimers.add(t);
      }
    } catch (e) {
      if (!mounted || _disposed) return;
      setState(() => _isReacquiring = false);
      _handleError(e);
    }
  }

  // ═══════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BaselineColors.background,
      body: SafeArea(
        child: Stack(
          children: [
            // Layer 0: Screen chrome (always visible).
            Positioned.fill(
              child: ExcludeSemantics(
                child: RepaintBoundary(
                  child: AnimatedBuilder(
                    animation: _chromePhase,
                    builder: (context, _) {
                      return CustomPaint(
                        painter: _TrendsChromePainter(
                          progress: _chromePhase.value,
                          dotGridSpacing: _kDotGridSpacing,
                          bracketLength: _kBracketLength,
                          tealColor: BaselineColors.teal,
                          dtgParagraph: _dtgParagraph,
                          handleParagraph: _handleParagraph,
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),

            // Layer 1: Content.
            _isLoading
                ? _buildLoadingState()
                : _errorMessage != null
                    ? _buildErrorState()
                    : _buildContent(),
          ],
        ),
      ),
    );
  }

  // ── Loading State ─────────────────────────────────────────

  Widget _buildLoadingState() {
    return Column(
      children: [
        _buildHeader(),
        _buildAccentLine(),
        const SizedBox(height: BaselineSpacing.xs),
        // 🍒21: "ACQUIRING SIGNAL..." ghost text during loading.
        ExcludeSemantics(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.3, end: 0.8),
            duration: const Duration(milliseconds: 1200),
            builder: (context, value, _) {
              return Opacity(
                opacity: value * 0.12,
                child: Text(
                  'ACQUIRING SIGNAL...',
                  style: TextStyle(
                    fontFamily: _kDataFontFamily,
                    fontSize: 7,
                    color: BaselineColors.teal,
                    letterSpacing: 3.0,
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: BaselineSpacing.xl),
        const Expanded(
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: BaselineSpacing.lg,
            ),
            child: ShimmerFeedList(count: 3),
          ),
        ),
      ],
    );
  }

  // ── Error State ─────────────────────────────────────────

  Widget _buildErrorState() {
    return Column(
      children: [
        _buildHeader(),
        _buildAccentLine(),
        const SizedBox(height: BaselineSpacing.xs),
        ExcludeSemantics(
          child: Opacity(
            opacity: 0.15,
            child: Text(
              'SIGNAL LOST',
              style: TextStyle(
                fontFamily: _kDataFontFamily,
                fontSize: 7,
                color: BaselineColors.amber,
                letterSpacing: 3.0,
              ),
            ),
          ),
        ),
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

  // ── Main Content ────────────────────────────────────────

  Widget _buildContent() {
    final timeline = _timeline;

    return RefreshIndicator(
      onRefresh: _onRefresh,
      color: BaselineColors.teal,
      backgroundColor: BaselineColors.card,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // ── 1. Header ──
                _buildHeader(),

                // ── 2. Accent glow line ──
                _buildAccentLine(),
                const SizedBox(height: BaselineSpacing.xs),

                // ── 3. Ghost designation (🍒2) / Reacquiring (🍒 T145) ──
                ExcludeSemantics(
                  child: AnimatedBuilder(
                    animation: _chromePhase,
                    builder: (context, _) {
                      if (_isReacquiring) {
                        return _buildReacquiringBadge();
                      }
                      return Opacity(
                        opacity: _chromePhase.value * 0.08,
                        child: Text(
                          'LONGITUDINAL SIGNAL ANALYSIS',
                          style: TextStyle(
                            fontFamily: _kDataFontFamily,
                            fontSize: 7,
                            color: BaselineColors.teal,
                            letterSpacing: 3.0,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: BaselineSpacing.md),

                // ── 4. Figure name + signal strength (🍒4, 🍒20) ──
                if (_figureName != null)
                  FadeTransition(
                    opacity: _cardsPhase,
                    child: Column(
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Signal strength indicator.
                            if (timeline != null &&
                                timeline.dataPoints.isNotEmpty)
                              _buildSignalStrengthIndicator(
                                timeline.dataPoints.last.value,
                              ),
                            if (timeline != null &&
                                timeline.dataPoints.isNotEmpty)
                              const SizedBox(width: BaselineSpacing.sm),
                            Flexible(
                              child: Text(
                                _figureName!,
                                style: BaselineTypography.body1.copyWith(
                                  color: BaselineColors.textSecondary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        // 🍒20: Data freshness badge.
                        const SizedBox(height: 4),
                        ExcludeSemantics(
                          child: Text(
                            'LIVE · ${_selectedPeriod.label.toUpperCase()}',
                            style: TextStyle(
                              fontFamily: _kDataFontFamily,
                              fontSize: 7,
                              color: BaselineColors.teal.atOpacity(0.12),
                              letterSpacing: 1.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: BaselineSpacing.lg),

                // ── 5. Period selector (A-13: 🍒13) ──
                _buildPeriodSelector(),
                const SizedBox(height: BaselineSpacing.md),

                // ── 6. Metric selector (🍒9, 🍒15) ──
                _buildMetricSelector(),
                const SizedBox(height: BaselineSpacing.lg),

                // ── 7. Value card (🍒7, 🍒10) ──
                if (timeline != null && timeline.dataPoints.isNotEmpty)
                  _buildValueCard(timeline),
                if (timeline != null && timeline.dataPoints.isNotEmpty)
                  const SizedBox(height: BaselineSpacing.md),

                // ── 8. Chart area with recalibration stack + metric wipe ──
                AnimatedOpacity(
                  opacity: _isMetricWiping ? 0.7 : 1.0,
                  duration: const Duration(milliseconds: 200),
                  child: _buildChartArea(timeline),
                ),

                const SizedBox(height: BaselineSpacing.sm),

                // ── 9. Statement count (🍒10 count-up) ──
                if (timeline != null && !timeline.isEmpty)
                  FadeTransition(
                    opacity: _cardsPhase,
                    child: AnimatedBuilder(
                      animation: _countUpAnim,
                      builder: (context, _) {
                        final count = (timeline.totalStatements *
                                _countUpAnim.value)
                            .round();
                        return Semantics(
                          label:
                              'Based on ${timeline.totalStatements} statements',
                          child: ExcludeSemantics(
                            child: Text(
                              'Based on $count statements',
                              style: BaselineTypography.caption.copyWith(
                                color: BaselineColors.textSecondary
                                    .atOpacity(0.6),
                                fontFamily: _kDataFontFamily,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                const SizedBox(height: BaselineSpacing.md),

                // ── 10. Station ID badge (🍒12) ──
                ExcludeSemantics(
                  child: FadeTransition(
                    opacity: _cardsPhase,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Padding(
                        padding: const EdgeInsets.only(
                          right: BaselineSpacing.lg,
                        ),
                        child: Text(
                          'STN: ${widget.figureId.substring(0, math.min(8, widget.figureId.length))}',
                          style: TextStyle(
                            fontFamily: _kDataFontFamily,
                            fontSize: 8,
                            color: BaselineColors.textSecondary
                                .atOpacity(0.15),
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: BaselineSpacing.lg),

                // ── 11. "How Trends works →" methodology link ──
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: BaselineSpacing.lg,
                  ),
                  child: Semantics(
                    button: true,
                    label: 'Learn how Trends works',
                    excludeSemantics: true,
                    child: GestureDetector(
                      onTap: () {
                        HapticUtil.light();
                        InfoBottomSheet.show(
                          context,
                          key: 'trends',
                        );
                      },
                      child: Text(
                        'How Trends works →',
                        style: BaselineTypography.caption.copyWith(
                          color: BaselineColors.textSecondary
                              .atOpacity(0.5),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: BaselineSpacing.xxl),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // HEADER
  // ═══════════════════════════════════════════════════════════

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: BaselineSpacing.lg,
        vertical: BaselineSpacing.sm,
      ),
      child: Row(
        children: [
          // ── Back button ──
          Semantics(
            button: true,
            label: 'Go back',
            excludeSemantics: true,
            child: GestureDetector(
              onTap: () {
                // TODO F4.6a: _shouldShowRateApp() check.
                if (context.canPop()) {
                  context.pop();
                } else {
                  context.go(AppRoutes.today);
                }
              },
              behavior: HitTestBehavior.opaque,
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
                        size: 24,
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

          // ── Title ──
          Semantics(
            button: true,
            label: 'Trends info',
            excludeSemantics: true,
            child: GestureDetector(
              onTap: () => InfoBottomSheet.show(context, key: 'trends'),
              child: Text(
                'Trends',
                style: BaselineTypography.h2.copyWith(
                  color: BaselineColors.textPrimary,
                ),
              ),
            ),
          ),

          const Spacer(),

          // ── ⓘ Info ──
          Semantics(
            button: true,
            label: 'Learn about Trends',
            excludeSemantics: true,
            child: GestureDetector(
              onTap: () => InfoBottomSheet.show(
                context,
                key: 'trends',
              ),
              behavior: HitTestBehavior.opaque,
              child: SizedBox(
                width: _kIconTouchTarget,
                height: _kIconTouchTarget,
                child: Center(
                  child: BaselineIcon(
                    BaselineIconType.info,
                    size: 20,
                    color: BaselineColors.textSecondary,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // ACCENT LINE
  // ═══════════════════════════════════════════════════════════

  Widget _buildAccentLine() {
    return ExcludeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: BaselineSpacing.xl,
        ),
        child: Container(
          height: _kAccentLineHeight,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.transparent,
                BaselineColors.teal.atOpacity(0.6),
                BaselineColors.teal,
                BaselineColors.teal.atOpacity(0.6),
                Colors.transparent,
              ],
              stops: const [0.0, 0.2, 0.5, 0.8, 1.0],
            ),
            borderRadius: BorderRadius.circular(1),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // SIGNAL STRENGTH INDICATOR (🍒4)
  // ═══════════════════════════════════════════════════════════

  Widget _buildSignalStrengthIndicator(double latestValue) {
    // Normalize 0-100 → 0.0-1.0 for bar fill.
    final fill = (latestValue / 100.0).clamp(0.0, 1.0);
    return ExcludeSemantics(
      child: SizedBox(
        width: 32,
        height: 8,
        child: CustomPaint(
          painter: _SignalStrengthPainter(
            fill: fill,
            tealColor: BaselineColors.teal,
            trackColor:
                BaselineColors.borderInactive.atOpacity(0.3),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // PERIOD SELECTOR (A-13: 🍒13)
  // ═══════════════════════════════════════════════════════════

  Widget _buildPeriodSelector() {
    return Center(
      child: Container(
        key: _selectorKey,
        height: _kPillHeight,
        decoration: BoxDecoration(
          color: BaselineColors.card,
          border: Border.all(
            color: BaselineColors.borderInactive
                .atOpacity(_kBorderOpacity),
            width: 1,
          ),
          borderRadius: BorderRadius.circular(_kPillRadius),
        ),
        child: Stack(
          children: [
            // ── Sliding teal indicator (A-13 Treatment 1) ──
            AnimatedPositioned(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              left: _pillIndicatorLeft,
              top: 0,
              bottom: 0,
              width: _pillIndicatorWidth,
              child: Container(
                decoration: BoxDecoration(
                  color: BaselineColors.teal.atOpacity(0.15),
                  borderRadius:
                      BorderRadius.circular(_kPillRadius - 1),
                  border: Border.all(
                    color: BaselineColors.teal.atOpacity(0.25),
                    width: 0.5,
                  ),
                ),
              ),
            ),

            // ── Pill labels ──
            Row(
              mainAxisSize: MainAxisSize.min,
              children:
                  TrendPeriod.values.asMap().entries.map((entry) {
                final idx = entry.key;
                final period = entry.value;
                final isSelected = period == _selectedPeriod;
                return Semantics(
                  button: true,
                  label: '${period.label} period',
                  selected: isSelected,
                  excludeSemantics: true,
                  child: GestureDetector(
                    key: _pillKeys[idx],
                    onTap: () => _onPeriodChanged(period),
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      height: _kPillHeight,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                      ),
                      alignment: Alignment.center,
                      child: AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 150),
                        style: TextStyle(
                          fontFamily: _kDataFontFamily,
                          fontSize: 12,
                          color: isSelected
                              ? BaselineColors.teal
                              : BaselineColors.textSecondary,
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.w400,
                          letterSpacing: isSelected ? 1.0 : 0.5,
                        ),
                        child: Text(period.label),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // METRIC SELECTOR (🍒9, 🍒15, 🍒28)
  // ═══════════════════════════════════════════════════════════

  Widget _buildMetricSelector() {
    final pillAnims = _getOrCreateMetricPillAnims();

    return SizedBox(
      height: _kMetricPillHeight,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: BaselineSpacing.lg,
        ),
        itemCount: TrendMetric.values.length,
        separatorBuilder: (_, _) =>
            const SizedBox(width: BaselineSpacing.sm),
        itemBuilder: (context, index) {
          final metric = TrendMetric.values[index];
          final isSelected = metric == _selectedMetric;
          final pillEntrance = pillAnims[index];

          return AnimatedBuilder(
            animation: pillEntrance,
            builder: (context, child) {
              return Transform.translate(
                offset: Offset(0, 6 * (1 - pillEntrance.value)),
                child: Opacity(
                  opacity: pillEntrance.value,
                  child: child,
                ),
              );
            },
            child: Semantics(
              button: true,
              label: '${metric.label} metric',
              selected: isSelected,
              excludeSemantics: true,
              child: GestureDetector(
                onTap: () => _onMetricChanged(metric),
                onLongPress: () => InfoBottomSheet.show(
                  context,
                  key: metric.infoKey,
                ),
                behavior: HitTestBehavior.opaque,
                // 🍒9: Press-scale.
                child: _PressScaleWidget(
                  scale: _kPillPressScale,
                  child: AnimatedContainer(
                    duration: _kColorTransitionDuration,
                    curve: Curves.easeOut,
                    height: _kMetricPillHeight,
                    padding: const EdgeInsets.symmetric(
                      horizontal: _kMetricPillHPadding,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? BaselineColors.teal.atOpacity(0.12)
                          : Colors.transparent,
                      border: Border.all(
                        color: isSelected
                            ? BaselineColors.teal.atOpacity(0.6)
                            : BaselineColors.borderInactive
                                .atOpacity(_kBorderOpacity),
                        width: 1,
                      ),
                      borderRadius: BorderRadius.circular(
                        _kMetricPillRadius,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      metric.label,
                      style: BaselineTypography.caption.copyWith(
                        color: isSelected
                            ? BaselineColors.teal
                            : BaselineColors.textSecondary,
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.normal,
                        fontFamily: _kDataFontFamily,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // VALUE CARD (🍒7, 🍒10, 🍒27)
  // ═══════════════════════════════════════════════════════════

  Widget _buildValueCard(MetricTimeline timeline) {
    final TrendDataPoint displayPoint;
    final TrendDataPoint? previousPoint;

    if (_selectedPointIndex >= 0 &&
        _selectedPointIndex < timeline.dataPoints.length) {
      displayPoint = timeline.dataPoints[_selectedPointIndex];
      previousPoint = _selectedPointIndex > 0
          ? timeline.dataPoints[_selectedPointIndex - 1]
          : null;
    } else {
      displayPoint = timeline.dataPoints.last;
      previousPoint = timeline.dataPoints.length > 1
          ? timeline.dataPoints[timeline.dataPoints.length - 2]
          : null;
    }

    final isSelected = _selectedPointIndex >= 0;

    // Delta from previous point.
    final double? delta = previousPoint != null
        ? displayPoint.value - previousPoint.value
        : null;

    return FadeTransition(
      opacity: _cardsPhase,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.1),
          end: Offset.zero,
        ).animate(_cardsPhase),
        // 🍒27: Value card halo glow via _breathCtrl (replaces BoxShadow).
        child: AnimatedBuilder(
          animation: _breathCtrl,
          builder: (context, child) {
            final breath = _breathCtrl.value;
            final haloOpacity =
                0.04 + (math.sin(breath * math.pi * 2) * 0.04);
            return Container(
              margin: const EdgeInsets.symmetric(
                horizontal: BaselineSpacing.lg,
              ),
              decoration: BoxDecoration(
                borderRadius: BaselineRadius.buttonBorderRadius,
                border: Border.all(
                  color: BaselineColors.teal
                      .atOpacity(haloOpacity.clamp(0.0, 0.08)),
                  width: 3,
                ),
              ),
              child: child,
            );
          },
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: BaselineSpacing.lg,
              vertical: BaselineSpacing.md,
            ),
            decoration: BoxDecoration(
              color: BaselineColors.card,
              border: Border.all(
                color: BaselineColors.teal.atOpacity(0.3),
                width: _kInteractiveBorderWidth,
              ),
              borderRadius: BaselineRadius.buttonBorderRadius,
            ),
            child: Row(
              children: [
                // Left: metric value with count-up (🍒10).
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 🍒7: "LATEST READING" micro-label.
                      ExcludeSemantics(
                        child: Text(
                          isSelected
                              ? 'SELECTED READING'
                              : 'LATEST READING',
                          style: TextStyle(
                            fontFamily: _kDataFontFamily,
                            fontSize: 6,
                            color:
                                BaselineColors.teal.atOpacity(0.10),
                            letterSpacing: 1.5,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment:
                            CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          // 🍒27: Pulsing dot via _breathCtrl.
                          AnimatedBuilder(
                            animation: _breathCtrl,
                            builder: (context, _) {
                              final dotOpacity = 0.4 +
                                  (math.sin(
                                          _breathCtrl.value *
                                              math.pi *
                                              2) *
                                      0.6);
                              return Container(
                                width: 6,
                                height: 6,
                                margin:
                                    const EdgeInsets.only(right: 8),
                                decoration: BoxDecoration(
                                  color: BaselineColors.teal
                                      .atOpacity(
                                    dotOpacity.clamp(0.4, 1.0),
                                  ),
                                  shape: BoxShape.circle,
                                ),
                              );
                            },
                          ),
                          AnimatedBuilder(
                            animation: _countUpAnim,
                            builder: (context, _) {
                              final animatedValue =
                                  displayPoint.value *
                                      _countUpAnim.value;
                              return Text(
                                animatedValue.toStringAsFixed(1),
                                style:
                                    BaselineTypography.h1.copyWith(
                                  color: BaselineColors.teal,
                                  fontFamily: _kDataFontFamily,
                                  fontSize: 36,
                                  fontWeight: FontWeight.w600,
                                ),
                              );
                            },
                          ),
                          // 🍒7: Delta indicator.
                          if (delta != null)
                            Padding(
                              padding:
                                  const EdgeInsets.only(left: 6),
                              child: Text(
                                '${delta >= 0 ? '↑' : '↓'}${delta.abs().toStringAsFixed(1)}',
                                style: TextStyle(
                                  fontFamily: _kDataFontFamily,
                                  fontSize: 11,
                                  color: delta >= 0
                                      ? BaselineColors.teal
                                          .atOpacity(0.7)
                                      : BaselineColors.textSecondary
                                          .atOpacity(0.7),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _selectedMetric.label,
                        style: BaselineTypography.body2.copyWith(
                          color: BaselineColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),

                // Right: date + count.
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      isSelected
                          ? _fmtDateMDY(displayPoint.date)
                          : 'Latest',
                      style: BaselineTypography.caption.copyWith(
                        color: BaselineColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    AnimatedBuilder(
                      animation: _countUpAnim,
                      builder: (context, _) {
                        final count = (displayPoint.count *
                                _countUpAnim.value)
                            .round();
                        return Text(
                          '$count statements',
                          style: BaselineTypography.caption.copyWith(
                            color: BaselineColors.textSecondary
                                .atOpacity(0.6),
                            fontFamily: _kDataFontFamily,
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // CHART AREA (with A-13 recalibration stack)
  // ═══════════════════════════════════════════════════════════

  Widget _buildChartArea(MetricTimeline? timeline) {
    if (_isChartLoading && !_isRecalibrating) {
      return Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: BaselineSpacing.lg,
        ),
        child: SizedBox(
          height: _kChartMaxHeight,
          child: const ShimmerFeedList(count: 2),
        ),
      );
    }

    if (timeline == null || timeline.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: BaselineSpacing.lg,
          vertical: BaselineSpacing.xl,
        ),
        child: Stack(
          children: [
            // 🍒 Treatment 117: Noise floor behind empty state.
            Positioned.fill(
              child: ExcludeSemantics(
                child: CustomPaint(
                  painter: _NoiseFloorPainter(
                    color: BaselineColors.teal.atOpacity(0.03),
                  ),
                ),
              ),
            ),
            const EmptyStateWidget(
              variant: EmptyStateVariant.trends,
            ),
          ],
        ),
      );
    }

    // Insufficient data: < 3 data points — show collecting placeholder.
    if (timeline.dataPoints.length < 3) {
      return _CollectingTrendsPlaceholder(
        dataPointCount: timeline.dataPoints.length,
        reduceMotion: MediaQuery.disableAnimationsOf(context),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: BaselineSpacing.md,
      ),
      child: Stack(
        children: [
          // Layer 1: Chart with A-13 directional wipe (Treatment 2).
          AnimatedBuilder(
            animation: _recalCtrl,
            builder: (context, child) {
              if (!_isRecalibrating && _recalCtrl.value == 0) {
                return child!;
              }
              final wipeT =
                  const Interval(0.0, 0.4, curve: Curves.easeInCubic)
                      .transform(_recalCtrl.value);
              final returnT = const Interval(0.6, 1.0,
                      curve: Curves.easeOutCubic)
                  .transform(_recalCtrl.value);
              final outDx = _wipeDirection * wipeT * 0.08;
              final inDx =
                  _wipeDirection * (1.0 - returnT) * 0.08;
              final dx = _recalCtrl.value <= 0.5 ? outDx : inDx;
              final opacity = _recalCtrl.value <= 0.5
                  ? 1.0 - (wipeT * 0.5)
                  : 0.5 + (returnT * 0.5);

              return Opacity(
                opacity: opacity.clamp(0.0, 1.0),
                child: Transform.translate(
                  offset: Offset(
                    MediaQuery.sizeOf(context).width * dx,
                    0,
                  ),
                  child: child,
                ),
              );
            },
            child: _buildChartContainer(timeline),
          ),

          // Layer 2: Scanline sweep (A-13 Treatment 3).
          if (_isRecalibrating)
            Positioned.fill(
              child: ExcludeSemantics(
                child: AnimatedBuilder(
                  animation: _recalCtrl,
                  builder: (context, _) {
                    final t = const Interval(0.2, 0.8,
                            curve: Curves.easeInOutCubic)
                        .transform(_recalCtrl.value);
                    if (t <= 0 || t >= 1) {
                      return const SizedBox.shrink();
                    }
                    return CustomPaint(
                      painter: _ScanlinePainter(
                        progress:
                            _wipeDirection < 0 ? t : 1.0 - t,
                        opacity: (1.0 - (t - 0.5).abs() * 2)
                                .clamp(0.0, 1.0) *
                            0.12,
                        tealColor: BaselineColors.teal,
                      ),
                    );
                  },
                ),
              ),
            ),

          // Layer 3: "RECALIBRATING" flash (A-13 Treatment 5).
          if (_isRecalibrating)
            Positioned.fill(
              child: ExcludeSemantics(
                child: AnimatedBuilder(
                  animation: _recalCtrl,
                  builder: (context, _) {
                    final t = const Interval(0.3, 0.7,
                            curve: Curves.easeInOut)
                        .transform(_recalCtrl.value);
                    if (t <= 0 || t >= 1) {
                      return const SizedBox.shrink();
                    }
                    final opacity =
                        (1.0 - (t - 0.5).abs() * 2)
                                .clamp(0.0, 1.0) *
                            0.18;
                    return Center(
                      child: Text(
                        'RECALIBRATING · ${_selectedPeriod.label.toUpperCase()}',
                        style: TextStyle(
                          fontFamily: _kDataFontFamily,
                          fontSize: 7,
                          color: BaselineColors.teal
                              .atOpacity(opacity),
                          letterSpacing: 2.0,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),

          // Layer 4: Epicenter pulse (🍒5).
          if (_epicenterOrigin != null)
            Positioned.fill(
              child: ExcludeSemantics(
                child: AnimatedBuilder(
                  animation: _epicenterCtrl,
                  builder: (context, _) {
                    if (_epicenterCtrl.value <= 0 ||
                        _epicenterCtrl.value >= 1) {
                      return const SizedBox.shrink();
                    }
                    return CustomPaint(
                      painter: _EpicenterPulsePainter(
                        origin: _epicenterOrigin!,
                        progress: _epicenterCtrl.value,
                        maxRadius: _kEpicenterMaxRadius,
                        tealColor: BaselineColors.teal,
                      ),
                    );
                  },
                ),
              ),
            ),

          // Layer 5: Chart reticle corners (🍒19).
          Positioned.fill(
            child: IgnorePointer(
              child: ExcludeSemantics(
                child: CustomPaint(
                  painter: _ChartReticlePainter(
                    color: BaselineColors.teal.atOpacity(0.06),
                    armLength: 8,
                  ),
                ),
              ),
            ),
          ),

          // Layer 6: Floating tooltip overlay (🍒14).
          if (_tooltipAnchor != null &&
              _selectedPointIndex >= 0 &&
              _selectedPointIndex < timeline.dataPoints.length)
            _buildTooltipOverlay(timeline),

          // Layer 7: "SIGNAL LOCK" flash (🍒17).
          if (_showSignalLock)
            Positioned(
              bottom: 8,
              left: 0,
              right: 0,
              child: ExcludeSemantics(
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.0, end: 1.0),
                  duration: const Duration(milliseconds: 300),
                  builder: (context, value, _) {
                    final opacity = value < 0.5
                        ? value * 2 * 0.15
                        : (1.0 - value) * 2 * 0.15;
                    return Opacity(
                      opacity: opacity.clamp(0.0, 0.15),
                      child: Text(
                        'SIGNAL LOCK',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: _kDataFontFamily,
                          fontSize: 7,
                          color: BaselineColors.teal,
                          letterSpacing: 2.0,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildChartContainer(MetricTimeline timeline) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(
          color: BaselineColors.teal.atOpacity(0.12),
          width: _kInteractiveBorderWidth,
        ),
        borderRadius: BaselineRadius.chipBorderRadius,
      ),
      padding: const EdgeInsets.only(top: 4, bottom: 4),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final chartWidth = constraints.maxWidth;
          final chartHeight =
              (chartWidth * _kChartHeightFraction)
                  .clamp(_kChartMinHeight, _kChartMaxHeight);

          // Compute baseline reference value (average of all points).
          double? baselineRef;
          if (timeline.dataPoints.length > 1) {
            final sum = timeline.dataPoints.fold<double>(
              0.0,
              (acc, dp) => acc + dp.value,
            );
            baselineRef = sum / timeline.dataPoints.length;
          }

          // Compute volatility (standard deviation).
          double? volatility;
          if (baselineRef != null &&
              timeline.dataPoints.length > 2) {
            final varianceSum =
                timeline.dataPoints.fold<double>(
              0.0,
              (acc, dp) =>
                  acc +
                  math.pow(dp.value - baselineRef!, 2),
            );
            volatility =
                math.sqrt(varianceSum / timeline.dataPoints.length);
          }

          // A2-I2: Pre-compute gradient shader when size changes.
          final plotTop = _kChartPaddingTop.toDouble();
          final plotBottom = chartHeight - _kChartPaddingBottom;
          if (chartWidth != _lastChartWidth ||
              plotTop != _lastPlotTop ||
              plotBottom != _lastPlotBottom) {
            _lastChartWidth = chartWidth;
            _lastPlotTop = plotTop;
            _lastPlotBottom = plotBottom;
            _fillGradientShader = ui.Gradient.linear(
              Offset(0, plotTop),
              Offset(0, plotBottom),
              [
                BaselineColors.teal.atOpacity(0.15),
                BaselineColors.teal.atOpacity(0.02),
              ],
            );
          }

          return GestureDetector(
            onTapDown: (details) => _onChartTap(
              details,
              timeline,
              chartWidth,
              chartHeight,
            ),
            onHorizontalDragUpdate: (details) => _onChartDrag(
              details,
              timeline,
              chartWidth,
              chartHeight,
            ),
            onHorizontalDragEnd: (_) {},
            child: Semantics(
              label: 'Trend chart for ${_selectedMetric.label}'
                  '${_figureName != null ? '. $_figureName' : ''}. '
                  '${timeline.dataPoints.length} data points.',
              child: RepaintBoundary(
                child: AnimatedBuilder(
                  animation: Listenable.merge([
                    _chartAnim,
                    _gridPhase,
                    _tracePhase,
                    _dotsPhase,
                  ]),
                  builder: (context, _) {
                    return CustomPaint(
                      size: Size(chartWidth, chartHeight),
                      painter: _TrendChartPainter(
                        dataPoints: timeline.dataPoints,
                        chartProgress: _chartAnim.value,
                        gridProgress: _gridPhase.value,
                        traceProgress: _tracePhase.value,
                        dotsProgress: _dotsPhase.value,
                        selectedIndex: _selectedPointIndex,
                        tealColor: BaselineColors.teal,
                        gridColor: BaselineColors.borderInactive
                            .atOpacity(0.3),
                        labelColor: BaselineColors.textSecondary
                            .atOpacity(0.6),
                        backgroundColor:
                            BaselineColors.background,
                        paddingLeft: _kChartPaddingLeft,
                        paddingRight: _kChartPaddingRight,
                        paddingTop: _kChartPaddingTop,
                        paddingBottom: _kChartPaddingBottom,
                        baselineRefValue: baselineRef,
                        volatility: volatility,
                        isRecalibrating: _isRecalibrating,
                        recalProgress: _recalCtrl.value,
                        periodIndex: TrendPeriod.values
                            .indexOf(_selectedPeriod),
                        scaledLabelSize: _scaledLabelSize,
                        scaledSmallSize: _scaledSmallSize,
                        scaledMicroSize: _scaledMicroSize,
                        fillGradientShader: _fillGradientShader,
                        yLabelParagraphs: _yLabelParagraphs,
                        xLabelParagraphs: _xLabelParagraphs,
                        baselineLabelParagraph:
                            _baselineLabelParagraph,
                        cachedGridValues: _cachedGridValues,
                      ),
                    );
                  },
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Chart Interaction ───────────────────────────────────

  void _onChartTap(
    TapDownDetails details,
    MetricTimeline timeline,
    double chartWidth,
    double chartHeight,
  ) {
    final index = _hitTestDataPoint(
      details.localPosition.dx,
      timeline,
      chartWidth,
    );

    if (index != null) {
      HapticUtil.light();

      // 🍒5: Fire epicenter pulse at tap point.
      final stepX = timeline.dataPoints.length > 1
          ? (chartWidth - _kChartPaddingLeft - _kChartPaddingRight) /
              (timeline.dataPoints.length - 1)
          : 0.0;
      final pointX = _kChartPaddingLeft + (index * stepX);

      // Compute Y position for the point.
      double minVal = double.infinity;
      double maxVal = double.negativeInfinity;
      for (final dp in timeline.dataPoints) {
        if (dp.value < minVal) minVal = dp.value;
        if (dp.value > maxVal) maxVal = dp.value;
      }
      final range = math.max(maxVal - minVal, 5.0);
      final yPadding = range * 0.1;
      final yMin = math.max(0.0, minVal - yPadding);
      final yMax = math.min(100.0, maxVal + yPadding);
      final yRange = yMax - yMin;
      final plotBottom = chartHeight - _kChartPaddingBottom;
      final plotHeight = plotBottom - _kChartPaddingTop;
      final pointY = plotBottom -
          ((timeline.dataPoints[index].value - yMin) / yRange) *
              plotHeight;

      setState(() {
        _selectedPointIndex = index;
        _epicenterOrigin = Offset(pointX, pointY);
        _tooltipAnchor = Offset(pointX, pointY);
      });

      _epicenterCtrl.forward(from: 0.0);
    } else {
      setState(() {
        _selectedPointIndex = -1;
        _tooltipAnchor = null;
      });
    }
  }

  void _onChartDrag(
    DragUpdateDetails details,
    MetricTimeline timeline,
    double chartWidth,
    double chartHeight,
  ) {
    final index = _hitTestDataPoint(
      details.localPosition.dx,
      timeline,
      chartWidth,
    );
    if (index != null && index != _selectedPointIndex) {
      HapticUtil.selection();
      setState(() => _selectedPointIndex = index);
    }
  }

  int? _hitTestDataPoint(
    double dx,
    MetricTimeline timeline,
    double chartWidth,
  ) {
    if (timeline.dataPoints.isEmpty) return null;
    if (timeline.dataPoints.length == 1) {
      final pointX = _kChartPaddingLeft;
      if ((dx - pointX).abs() <= _kHitTestThreshold) return 0;
      return null;
    }

    final plotWidth =
        chartWidth - _kChartPaddingLeft - _kChartPaddingRight;
    final stepX = plotWidth / (timeline.dataPoints.length - 1);
    final adjustedX = dx - _kChartPaddingLeft;
    final rawIndex = (adjustedX / stepX).round();
    final index =
        rawIndex.clamp(0, timeline.dataPoints.length - 1);
    final pointX = _kChartPaddingLeft + (index * stepX);
    if ((dx - pointX).abs() > _kHitTestThreshold) return null;
    return index;
  }

  // ═══════════════════════════════════════════════════════════
  // FLOATING TOOLTIP OVERLAY (🍒14)
  // ═══════════════════════════════════════════════════════════

  Widget _buildTooltipOverlay(MetricTimeline timeline) {
    final dp = timeline.dataPoints[_selectedPointIndex];
    final anchor = _tooltipAnchor!;

    // Smart positioning: above if room, below if near top.
    final showAbove = anchor.dy > 80;
    final topOffset = showAbove ? anchor.dy - 72 : anchor.dy + 16;

    // Compute delta from previous point.
    String? deltaText;
    if (_selectedPointIndex > 0) {
      final prev =
          timeline.dataPoints[_selectedPointIndex - 1].value;
      final delta = dp.value - prev;
      final sign = delta >= 0 ? '↑' : '↓';
      deltaText = '$sign${delta.abs().toStringAsFixed(1)}';
    }

    final screenWidth = MediaQuery.sizeOf(context).width;
    final screenHeight = MediaQuery.sizeOf(context).height;
    final tooltipLeft = (anchor.dx - 60).clamp(8.0, screenWidth - 128.0);
    final tooltipTop = topOffset.clamp(4.0, screenHeight - 80.0);

    return Positioned(
      left: tooltipLeft,
      top: tooltipTop,
      child: RepaintBoundary(
        child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.0, end: 1.0),
        duration: const Duration(milliseconds: 150),
        builder: (context, value, child) {
          return Opacity(
            opacity: value,
            child: Transform.translate(
              offset: Offset(0, (1.0 - value) * (showAbove ? 4 : -4)),
              child: child,
            ),
          );
        },
        child: IgnorePointer(
          child: Container(
            width: 120,
            padding: const EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 6,
            ),
            decoration: BoxDecoration(
              color: BaselineColors.card,
              border: Border.all(
                color: BaselineColors.teal.atOpacity(0.08),
                width: 1,
              ),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Date.
                Text(
                  _fmtDateMDY(dp.date),
                  style: TextStyle(
                    fontFamily: _kDataFontFamily,
                    fontSize: 9,
                    color: BaselineColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 3),
                // Value + delta.
                Row(
                  children: [
                    Text(
                      dp.value.toStringAsFixed(1),
                      style: TextStyle(
                        fontFamily: _kDataFontFamily,
                        fontSize: 12,
                        color: BaselineColors.teal,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (deltaText != null) ...[
                      const SizedBox(width: 4),
                      Text(
                        deltaText,
                        style: TextStyle(
                          fontFamily: _kDataFontFamily,
                          fontSize: 9,
                          color: deltaText.startsWith('↑')
                              ? BaselineColors.teal
                              : BaselineColors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
                // Statement count.
                ...[
                const SizedBox(height: 2),
                Text(
                  '${dp.statementCount} statements',
                  style: TextStyle(
                    fontFamily: _kDataFontFamily,
                    fontSize: 8,
                    color: BaselineColors.textSecondary
                        .atOpacity(0.6),
                  ),
                ),
              ],
              ],
            ),
          ),
        ),
      ),
      ), // RepaintBoundary
    );
  }

  // ═══════════════════════════════════════════════════════════
  // REACQUIRING SIGNAL WIDGET (🍒 Treatment 145)
  // ═══════════════════════════════════════════════════════════

  Widget _buildReacquiringBadge() {
    if (!_isReacquiring) return const SizedBox.shrink();
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.3, end: 0.8),
      duration: const Duration(milliseconds: 800),
      builder: (context, value, _) {
        return Opacity(
          opacity: value * 0.10,
          child: Text(
            'REACQUIRING SIGNAL',
            style: TextStyle(
              fontFamily: _kDataFontFamily,
              fontSize: 7,
              color: BaselineColors.teal,
              letterSpacing: 2.0,
            ),
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════
// PRESS-SCALE WIDGET (🍒9)
// ═══════════════════════════════════════════════════════════

class _PressScaleWidget extends StatefulWidget {
  const _PressScaleWidget({
    required this.child,
    this.scale = 0.95,
  });

  final Widget child;
  final double scale;

  @override
  State<_PressScaleWidget> createState() => _PressScaleWidgetState();
}

class _PressScaleWidgetState extends State<_PressScaleWidget> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      child: AnimatedScale(
        scale: _isPressed ? widget.scale : 1.0,
        duration: const Duration(milliseconds: 100),
        child: widget.child,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// SCREEN CHROME PAINTER (🍒1, 🍒22-26)
// ═══════════════════════════════════════════════════════════

class _TrendsChromePainter extends CustomPainter {
  _TrendsChromePainter({
    required this.progress,
    required this.dotGridSpacing,
    required this.bracketLength,
    required this.tealColor,
    this.dtgParagraph,
    this.handleParagraph,
  });

  final double progress;
  final double dotGridSpacing;
  final double bracketLength;
  final Color tealColor;
  final ui.Paragraph? dtgParagraph;
  final ui.Paragraph? handleParagraph;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;

    // 🍒23: Classification hairline across top.
    canvas.drawLine(
      Offset(0, 0.5),
      Offset(size.width, 0.5),
      Paint()
        ..color = tealColor.atOpacity(0.04 * progress)
        ..strokeWidth = 1.0,
    );

    // ── Intel dot grid (very subtle) ──
    final dotPaint = Paint()
      ..color = tealColor.atOpacity(0.025 * progress)
      ..style = PaintingStyle.fill;

    for (double x = dotGridSpacing / 2;
        x < size.width;
        x += dotGridSpacing) {
      for (double y = dotGridSpacing / 2;
          y < size.height;
          y += dotGridSpacing) {
        canvas.drawCircle(Offset(x, y), 0.5, dotPaint);
      }
    }

    // ── 🍒22: Compound reticle corners (I-51) ──
    final bracketPaint = Paint()
      ..color = tealColor.atOpacity(0.08 * progress)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    final bl = bracketLength;
    final m = 8.0;

    // Draw compound corner at each position.
    _drawCompoundCorner(canvas, Offset(m, m), bl, bracketPaint, tl: true);
    _drawCompoundCorner(canvas, Offset(size.width - m, m), bl, bracketPaint, tr: true);
    _drawCompoundCorner(canvas, Offset(m, size.height - m), bl, bracketPaint, bl2: true);
    _drawCompoundCorner(canvas, Offset(size.width - m, size.height - m), bl, bracketPaint, br: true);

    // 🍒26: Registration dots at chrome corners.
    final regDotPaint = Paint()
      ..color = tealColor.atOpacity(0.05 * progress)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(m, m), 1.5, regDotPaint);
    canvas.drawCircle(Offset(size.width - m, m), 1.5, regDotPaint);
    canvas.drawCircle(Offset(m, size.height - m), 1.5, regDotPaint);
    canvas.drawCircle(Offset(size.width - m, size.height - m), 1.5, regDotPaint);

    // ── Edge tick rulers ──
    final tickPaint = Paint()
      ..color = tealColor.atOpacity(0.04 * progress)
      ..strokeWidth = 0.5;

    // Left edge ticks.
    for (double y = 60; y < size.height - 60; y += 20) {
      final isMajor = ((y - 60) % 100).abs() < 1;
      final tickLen = isMajor ? 6.0 : 3.0;
      canvas.drawLine(
        Offset(0, y),
        Offset(tickLen, y),
        tickPaint,
      );
    }

    // Right edge ticks.
    for (double y = 60; y < size.height - 60; y += 20) {
      final isMajor = ((y - 60) % 100).abs() < 1;
      final tickLen = isMajor ? 6.0 : 3.0;
      canvas.drawLine(
        Offset(size.width, y),
        Offset(size.width - tickLen, y),
        tickPaint,
      );
    }

    // 🍒24: DTG timestamp bottom-left (A2-C3: pre-computed).
    if (dtgParagraph != null) {
      canvas.saveLayer(
        Rect.fromLTWH(0, size.height - m - 16, 170, 20),
        Paint()..color = Color.fromRGBO(0, 0, 0, progress),
      );
      canvas.drawParagraph(dtgParagraph!, Offset(m + 4, size.height - m - 12));
      canvas.restore();
    }

    // 🍒25: Handling mark (rotated -90°, right edge, A2-C3: pre-computed).
    if (handleParagraph != null) {
      canvas.saveLayer(
        Rect.fromLTWH(size.width - 20, 0, 20, size.height),
        Paint()..color = Color.fromRGBO(0, 0, 0, progress),
      );
      canvas.translate(size.width - 4, size.height * 0.6);
      canvas.rotate(-math.pi / 2);
      canvas.drawParagraph(handleParagraph!, Offset.zero);
      canvas.restore();
    }
  }

  void _drawCompoundCorner(
    Canvas canvas,
    Offset origin,
    double len,
    Paint paint, {
    bool tl = false,
    bool tr = false,
    bool bl2 = false,
    bool br = false,
  }) {
    final dx = (tr || br) ? -1.0 : 1.0;
    final dy = (bl2 || br) ? -1.0 : 1.0;

    // Outer L.
    canvas.drawLine(
      origin,
      Offset(origin.dx + len * dx, origin.dy),
      paint,
    );
    canvas.drawLine(
      origin,
      Offset(origin.dx, origin.dy + len * dy),
      paint,
    );

    // Inner tick (4px, offset 3px from corner).
    final innerPaint = Paint()
      ..color = paint.color.atOpacity(0.6)
      ..strokeWidth = 0.5;
    canvas.drawLine(
      Offset(origin.dx + 3 * dx, origin.dy + 3 * dy),
      Offset(origin.dx + 7 * dx, origin.dy + 3 * dy),
      innerPaint,
    );
    canvas.drawLine(
      Offset(origin.dx + 3 * dx, origin.dy + 3 * dy),
      Offset(origin.dx + 3 * dx, origin.dy + 7 * dy),
      innerPaint,
    );

    // Corner dot.
    canvas.drawCircle(
      Offset(origin.dx + 3 * dx, origin.dy + 3 * dy),
      0.8,
      Paint()
        ..color = paint.color.atOpacity(0.4)
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(covariant _TrendsChromePainter old) =>
      progress != old.progress ||
      dtgParagraph != old.dtgParagraph ||
      handleParagraph != old.handleParagraph;
}

// ═══════════════════════════════════════════════════════════
// SIGNAL STRENGTH PAINTER (🍒4)
// ═══════════════════════════════════════════════════════════

class _SignalStrengthPainter extends CustomPainter {
  _SignalStrengthPainter({
    required this.fill,
    required this.tealColor,
    required this.trackColor,
  });

  final double fill;
  final Color tealColor;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    // 5 bars, increasing height.
    const barCount = 5;
    final barWidth = (size.width - (barCount - 1) * 1.5) / barCount;

    for (int i = 0; i < barCount; i++) {
      final x = i * (barWidth + 1.5);
      final barHeight =
          size.height * (0.3 + 0.7 * (i / (barCount - 1)));
      final y = size.height - barHeight;
      final isActive = fill >= (i + 0.5) / barCount;

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, barWidth, barHeight),
          const Radius.circular(1),
        ),
        Paint()
          ..color = isActive
              ? tealColor.atOpacity(0.7)
              : trackColor,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SignalStrengthPainter old) =>
      fill != old.fill;
}

// ═══════════════════════════════════════════════════════════
// TREND CHART PAINTER (🍒3, 🍒6, 🍒8, 🍒9, 🍒16)
// ═══════════════════════════════════════════════════════════

class _TrendChartPainter extends CustomPainter {
  _TrendChartPainter({
    required this.dataPoints,
    required this.chartProgress,
    required this.gridProgress,
    required this.traceProgress,
    required this.dotsProgress,
    required this.selectedIndex,
    required this.tealColor,
    required this.gridColor,
    required this.labelColor,
    required this.backgroundColor,
    required this.paddingLeft,
    required this.paddingRight,
    required this.paddingTop,
    required this.paddingBottom,
    this.baselineRefValue,
    this.volatility,
    this.isRecalibrating = false,
    this.recalProgress = 0.0,
    this.periodIndex = 0,
    required this.scaledLabelSize,
    required this.scaledSmallSize,
    required this.scaledMicroSize,
    this.fillGradientShader,
    required this.yLabelParagraphs,
    required this.xLabelParagraphs,
    this.baselineLabelParagraph,
    required this.cachedGridValues,
  });

  final List<TrendDataPoint> dataPoints;
  final double chartProgress;
  final double gridProgress;
  final double traceProgress;
  final double dotsProgress;
  final int selectedIndex;
  final Color tealColor;
  final Color gridColor;
  final Color labelColor;
  final Color backgroundColor;
  final double paddingLeft;
  final double paddingRight;
  final double paddingTop;
  final double paddingBottom;
  final double? baselineRefValue;
  final double? volatility;
  final bool isRecalibrating;
  final double recalProgress;
  final int periodIndex;
  final double scaledLabelSize;
  final double scaledSmallSize;
  final double scaledMicroSize;
  final ui.Gradient? fillGradientShader;
  final List<(double, ui.Paragraph)> yLabelParagraphs;
  final List<ui.Paragraph> xLabelParagraphs;
  final ui.Paragraph? baselineLabelParagraph;
  final List<double> cachedGridValues;

  @override
  void paint(Canvas canvas, Size size) {
    if (dataPoints.isEmpty) return;

    final plotLeft = paddingLeft;
    final plotRight = size.width - paddingRight;
    final plotTop = paddingTop;
    final plotBottom = size.height - paddingBottom;
    final plotWidth = plotRight - plotLeft;
    final plotHeight = plotBottom - plotTop;

    // ── Compute Y range ──
    double minVal = double.infinity;
    double maxVal = double.negativeInfinity;
    for (final dp in dataPoints) {
      if (dp.value < minVal) minVal = dp.value;
      if (dp.value > maxVal) maxVal = dp.value;
    }
    final range = math.max(maxVal - minVal, 5.0);
    final yPadding = range * 0.1;
    final yMin = math.max(0.0, minVal - yPadding);
    final yMax = math.min(100.0, maxVal + yPadding);
    final yRange = yMax - yMin;

    double valueToY(double value) {
      return plotBottom - ((value - yMin) / yRange) * plotHeight;
    }

    // ── A-13 Treatment 6: Signal noise burst ──
    if (isRecalibrating && recalProgress > 0 && recalProgress < 0.4) {
      final noiseOpacity =
          0.12 * (1.0 - recalProgress / 0.4);
      final noisePath = Path();
      final rng = math.Random(periodIndex * 7 + 42);
      noisePath.moveTo(plotLeft, (plotTop + plotBottom) / 2);
      for (double x = plotLeft; x < plotRight; x += 3) {
        final jitter =
            (rng.nextDouble() - 0.5) * plotHeight * 0.4;
        noisePath.lineTo(x, (plotTop + plotBottom) / 2 + jitter);
      }
      canvas.drawPath(
        noisePath,
        Paint()
          ..color = tealColor.atOpacity(noiseOpacity)
          ..strokeWidth = 0.8
          ..style = PaintingStyle.stroke,
      );
    }

    // ── Grid Lines with amplitude gauge (🍒3) ──
    final gridPaint = Paint()
      ..color = gridColor.atOpacity(gridProgress)
      ..strokeWidth = _kGridStrokeWidth
      ..style = PaintingStyle.stroke;

    // A2-C3: Use pre-computed grid values and label paragraphs.
    final gridValues = cachedGridValues.isNotEmpty
        ? cachedGridValues
        : _computeGridValues(yMin, yMax, _kGridLineCount);

    for (int gi = 0; gi < gridValues.length; gi++) {
      final gv = gridValues[gi];
      final y = valueToY(gv);
      canvas.drawLine(
        Offset(plotLeft, y),
        Offset(plotRight, y),
        gridPaint,
      );

      // Amplitude gauge: major tick.
      canvas.drawLine(
        Offset(plotLeft - 8, y),
        Offset(plotLeft - 2, y),
        Paint()
          ..color = tealColor.atOpacity(0.15 * gridProgress)
          ..strokeWidth = 1.0,
      );

      // A2-C3: Draw pre-computed Y-axis label with opacity modulation.
      if (gi < yLabelParagraphs.length && gridProgress > 0) {
        canvas.saveLayer(
          Rect.fromLTWH(0, y - 10, paddingLeft, 16),
          Paint()..color = Color.fromRGBO(0, 0, 0, gridProgress * 0.6),
        );
        canvas.drawParagraph(yLabelParagraphs[gi].$2, Offset(0, y - 6));
        canvas.restore();
      }
    }

    // Minor amplitude gauge ticks between major grid lines.
    for (int i = 0; i < gridValues.length - 1; i++) {
      final y1 = valueToY(gridValues[i]);
      final y2 = valueToY(gridValues[i + 1]);
      final midY = (y1 + y2) / 2;
      canvas.drawLine(
        Offset(plotLeft - 5, midY),
        Offset(plotLeft - 2, midY),
        Paint()
          ..color = tealColor.atOpacity(0.08 * gridProgress)
          ..strokeWidth = 0.5,
      );
    }

    // ── Baseline reference line (🍒8) ──
    if (baselineRefValue != null && gridProgress > 0) {
      final refY = valueToY(baselineRefValue!);
      if (refY >= plotTop && refY <= plotBottom) {
        final dashPaint = Paint()
          ..color = tealColor.atOpacity(0.15 * gridProgress)
          ..strokeWidth = 0.8
          ..style = PaintingStyle.stroke;

        // Dashed line.
        double x = plotLeft;
        while (x < plotRight) {
          final end = math.min(x + _kBaselineDashLength, plotRight);
          canvas.drawLine(
            Offset(x, refY),
            Offset(end, refY),
            dashPaint,
          );
          x += _kBaselineDashLength + _kBaselineGapLength;
        }

        // A2-C3: Draw pre-computed BASELINE ghost label.
        if (baselineLabelParagraph != null && gridProgress > 0) {
          canvas.saveLayer(
            Rect.fromLTWH(plotRight - 62, refY - 14, 64, 16),
            Paint()..color = Color.fromRGBO(0, 0, 0, 0.12 * gridProgress),
          );
          canvas.drawParagraph(
            baselineLabelParagraph!,
            Offset(plotRight - 58, refY - 10),
          );
          canvas.restore();
        }
      }
    }

    // ── Volatility band (🍒9) ──
    if (volatility != null &&
        baselineRefValue != null &&
        traceProgress > 0 &&
        dataPoints.length > 2) {
      final bandPaint = Paint()
        ..color = tealColor.atOpacity(0.04 * traceProgress);

      final upperPath = Path();
      final lowerPath = Path();
      final stepX = dataPoints.length > 1
          ? plotWidth / (dataPoints.length - 1)
          : 0.0;

      for (int i = 0; i < dataPoints.length; i++) {
        final x = plotLeft + (i * stepX);
        final upper = valueToY(
            (dataPoints[i].value + volatility!).clamp(yMin, yMax));
        final lower = valueToY(
            (dataPoints[i].value - volatility!).clamp(yMin, yMax));
        if (i == 0) {
          upperPath.moveTo(x, upper);
          lowerPath.moveTo(x, lower);
        } else {
          upperPath.lineTo(x, upper);
          lowerPath.lineTo(x, lower);
        }
      }

      // Close band shape.
      final bandPath = Path()..addPath(upperPath, Offset.zero);
      for (int i = dataPoints.length - 1; i >= 0; i--) {
        final x = plotLeft + (i * stepX);
        final lower = valueToY(
            (dataPoints[i].value - volatility!).clamp(yMin, yMax));
        bandPath.lineTo(x, lower);
      }
      bandPath.close();

      canvas.save();
      final clipRight = plotLeft + (plotWidth * traceProgress);
      canvas.clipRect(Rect.fromLTRB(0, 0, clipRight, size.height));
      canvas.drawPath(bandPath, bandPaint);
      canvas.restore();
    }

    // ── Compute point positions ──
    final points = <Offset>[];
    final stepX = dataPoints.length > 1
        ? plotWidth / (dataPoints.length - 1)
        : 0.0;

    for (int i = 0; i < dataPoints.length; i++) {
      final x = plotLeft + (i * stepX);
      final y = valueToY(dataPoints[i].value);
      points.add(Offset(x, y));
    }

    if (points.isEmpty) return;

    // ── Animated clip for trace ──
    canvas.save();
    final clipRight = plotLeft + (plotWidth * traceProgress);
    canvas.clipRect(Rect.fromLTRB(0, 0, clipRight, size.height));

    // ── Fill gradient under line (A2-I2: pre-computed shader) ──
    if (points.length > 1 && fillGradientShader != null) {
      final fillPath = _buildSmoothPath(points);
      fillPath.lineTo(points.last.dx, plotBottom);
      fillPath.lineTo(points.first.dx, plotBottom);
      fillPath.close();

      final fillPaint = Paint()
        ..shader = fillGradientShader;
      // Modulate opacity with traceProgress.
      if (traceProgress < 1.0) {
        fillPaint.color = Color.fromRGBO(0, 0, 0, traceProgress);
      }
      canvas.drawPath(fillPath, fillPaint);
    }

    // ── Signal trace with glow (🍒6) ──
    if (points.length == 1) {
      canvas.drawCircle(
        points.first,
        _kDotRadius,
        Paint()..color = tealColor,
      );
    } else {
      final linePath = _buildSmoothPath(points);

      // Glow layer (bloom effect).
      canvas.drawPath(
        linePath,
        Paint()
          ..color = tealColor.atOpacity(0.25 * traceProgress)
          ..strokeWidth = _kLineStrokeWidth + 3
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(
            BlurStyle.normal,
            _kLineGlowSigma,
          ),
      );

      // Main line.
      canvas.drawPath(
        linePath,
        Paint()
          ..color = tealColor.atOpacity(traceProgress)
          ..strokeWidth = _kLineStrokeWidth
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );

      // ── Data point dots (phased with dotsProgress) ──
      final dotPaint = Paint()
        ..color = tealColor
        ..style = PaintingStyle.fill;
      final dotOutlinePaint = Paint()
        ..color = backgroundColor
        ..style = PaintingStyle.fill;

      for (int i = 0; i < points.length; i++) {
        final dotT = dataPoints.length > 1
            ? i / (dataPoints.length - 1)
            : 0.0;
        if (dotsProgress < dotT) continue;

        final isActive = i == selectedIndex;
        final radius = isActive ? _kActiveDotRadius : _kDotRadius;
        canvas.drawCircle(
          points[i],
          radius + 1.5,
          dotOutlinePaint,
        );
        canvas.drawCircle(points[i], radius, dotPaint);
      }
    }

    // ── Peak/trough markers (🍒16) ──
    if (points.length > 2) {
      for (int i = 1; i < points.length - 1; i++) {
        final dotT = i / (dataPoints.length - 1);
        if (dotsProgress < dotT) continue;

        final prev = dataPoints[i - 1].value;
        final curr = dataPoints[i].value;
        final next = dataPoints[i + 1].value;
        final pt = points[i];

        if (curr > prev && curr > next) {
          // Peak: upward caret.
          final caretPath = Path()
            ..moveTo(pt.dx - 3, pt.dy - _kDotRadius - 4)
            ..lineTo(pt.dx, pt.dy - _kDotRadius - 7)
            ..lineTo(pt.dx + 3, pt.dy - _kDotRadius - 4);
          canvas.drawPath(
            caretPath,
            Paint()
              ..color = tealColor.atOpacity(0.40 * dotsProgress)
              ..strokeWidth = 1.0
              ..style = PaintingStyle.stroke
              ..strokeCap = StrokeCap.round,
          );
        } else if (curr < prev && curr < next) {
          // Trough: downward caret.
          final caretPath = Path()
            ..moveTo(pt.dx - 3, pt.dy + _kDotRadius + 4)
            ..lineTo(pt.dx, pt.dy + _kDotRadius + 7)
            ..lineTo(pt.dx + 3, pt.dy + _kDotRadius + 4);
          canvas.drawPath(
            caretPath,
            Paint()
              ..color = labelColor.atOpacity(0.30 * dotsProgress)
              ..strokeWidth = 1.0
              ..style = PaintingStyle.stroke
              ..strokeCap = StrokeCap.round,
          );
        }
      }
    }

    canvas.restore();

    // ── Crosshair for selected point ──
    if (selectedIndex >= 0 && selectedIndex < points.length) {
      final sp = points[selectedIndex];
      final crosshairPaint = Paint()
        ..color = tealColor.atOpacity(0.3)
        ..strokeWidth = _kCrosshairWidth
        ..style = PaintingStyle.stroke;

      canvas.drawLine(
        Offset(sp.dx, plotTop),
        Offset(sp.dx, plotBottom),
        crosshairPaint,
      );
      canvas.drawLine(
        Offset(plotLeft, sp.dy),
        Offset(plotRight, sp.dy),
        crosshairPaint,
      );
    }

    // ── X-axis date labels ──
    _drawXAxisLabels(canvas, size, plotLeft, plotRight, plotBottom);

    // ── A-13 Treatment 4: Hashmark ruler at bottom ──
    if (isRecalibrating && recalProgress > 0) {
      final rulerT = const Interval(0.1, 0.9,
              curve: Curves.easeInOutCubic)
          .transform(recalProgress);
      if (rulerT > 0 && rulerT < 1) {
        final peakT = 1.0 - (rulerT - 0.5).abs() * 2;
        final direction = periodIndex > 1 ? -1 : 1;
        final scale = direction < 0
            ? 1.0 - (peakT * 0.3)
            : 1.0 + (peakT * 0.3);
        final rulerPaint = Paint()
          ..color = tealColor
              .atOpacity(0.06 + peakT * 0.04)
          ..strokeWidth = 0.5;

        final spacing = 12.0 * scale;
        final center = (plotLeft + plotRight) / 2;
        final rulerY = plotBottom + 2;

        for (double x = center; x < plotRight; x += spacing) {
          final h =
              (x - center) % (spacing * 5) < spacing ? 4.0 : 2.0;
          canvas.drawLine(
            Offset(x, rulerY),
            Offset(x, rulerY + h),
            rulerPaint,
          );
          final mx = center - (x - center);
          if (mx >= plotLeft) {
            canvas.drawLine(
              Offset(mx, rulerY),
              Offset(mx, rulerY + h),
              rulerPaint,
            );
          }
        }
      }
    }
  }

  Path _buildSmoothPath(List<Offset> pts) {
    final path = Path();
    path.moveTo(pts.first.dx, pts.first.dy);
    if (pts.length == 2) {
      path.lineTo(pts[1].dx, pts[1].dy);
      return path;
    }
    for (int i = 0; i < pts.length - 1; i++) {
      final p0 = i > 0 ? pts[i - 1] : pts[i];
      final p1 = pts[i];
      final p2 = pts[i + 1];
      final p3 = i + 2 < pts.length ? pts[i + 2] : pts[i + 1];
      final cp1x = p1.dx + (p2.dx - p0.dx) / 6.0;
      final cp1y = p1.dy + (p2.dy - p0.dy) / 6.0;
      final cp2x = p2.dx - (p3.dx - p1.dx) / 6.0;
      final cp2y = p2.dy - (p3.dy - p1.dy) / 6.0;
      path.cubicTo(cp1x, cp1y, cp2x, cp2y, p2.dx, p2.dy);
    }
    return path;
  }

  void _drawXAxisLabels(
    Canvas canvas,
    Size size,
    double plotLeft,
    double plotRight,
    double plotBottom,
  ) {
    if (dataPoints.isEmpty) return;

    final count = dataPoints.length;

    final stepX =
        count > 1 ? (plotRight - plotLeft) / (count - 1) : 0.0;

    final availableWidth = plotRight - plotLeft;
    final maxLabels =
        math.max(2, (availableWidth / _kMinLabelSpacing).floor());
    final labelStep =
        count > maxLabels ? (count / maxLabels).ceil() : 1;

    // A2-C3: Draw pre-computed X-axis paragraphs with opacity modulation.
    final hasCache = xLabelParagraphs.length == count;

    final drawnIndices = <int>[];
    for (int i = 0; i < count; i += labelStep) {
      final x = plotLeft + (i * stepX);
      _drawXTick(canvas, x, plotBottom);
      if (hasCache && gridProgress > 0) {
        canvas.saveLayer(
          Rect.fromLTWH(x - 32, plotBottom + 4, 64, 16),
          Paint()..color = Color.fromRGBO(0, 0, 0, gridProgress),
        );
        canvas.drawParagraph(
          xLabelParagraphs[i],
          Offset(x - 30, plotBottom + 6),
        );
        canvas.restore();
      }
      drawnIndices.add(i);
    }

    if (!drawnIndices.contains(count - 1)) {
      final lastDrawnX =
          plotLeft + (drawnIndices.last * stepX);
      final lastX = plotRight;
      if ((lastX - lastDrawnX) >= _kMinLabelSpacing * 0.6) {
        _drawXTick(canvas, lastX, plotBottom);
        if (hasCache && gridProgress > 0) {
          canvas.saveLayer(
            Rect.fromLTWH(lastX - 32, plotBottom + 4, 64, 16),
            Paint()..color = Color.fromRGBO(0, 0, 0, gridProgress),
          );
          canvas.drawParagraph(
            xLabelParagraphs[count - 1],
            Offset(lastX - 30, plotBottom + 6),
          );
          canvas.restore();
        }
      }
    }
  }

  /// X-axis tick mark helper (🍒 Treatment 74).
  void _drawXTick(Canvas canvas, double x, double plotBottom) {
    canvas.drawLine(
      Offset(x, plotBottom),
      Offset(x, plotBottom + 3),
      Paint()
        ..color = tealColor.atOpacity(0.08)
        ..strokeWidth = 0.5,
    );
  }

  List<double> _computeGridValues(
    double min,
    double max,
    int targetCount,
  ) {
    final range = max - min;
    if (range <= 0) return [min];
    final rawStep = range / (targetCount - 1);
    final magnitude =
        math.pow(10, (math.log(rawStep) / math.ln10).floor());
    final residual = rawStep / magnitude;
    double niceStep;
    if (residual <= 1.5) {
      niceStep = 1.0 * magnitude;
    } else if (residual <= 3.0) {
      niceStep = 2.0 * magnitude;
    } else if (residual <= 7.0) {
      niceStep = 5.0 * magnitude;
    } else {
      niceStep = 10.0 * magnitude;
    }
    final niceMin = (min / niceStep).floor() * niceStep;
    final values = <double>[];
    var current = niceMin;
    while (current <= max + niceStep * 0.01) {
      if (current >= min - niceStep * 0.01) {
        values.add(current);
      }
      current += niceStep;
    }
    return values;
  }

  @override
  bool shouldRepaint(covariant _TrendChartPainter old) {
    return old.chartProgress != chartProgress ||
        old.gridProgress != gridProgress ||
        old.traceProgress != traceProgress ||
        old.dotsProgress != dotsProgress ||
        old.selectedIndex != selectedIndex ||
        old.dataPoints != dataPoints ||
        old.tealColor != tealColor ||
        old.gridColor != gridColor ||
        old.isRecalibrating != isRecalibrating ||
        old.recalProgress != recalProgress ||
        old.scaledLabelSize != scaledLabelSize ||
        old.fillGradientShader != fillGradientShader;
  }
}

// ═══════════════════════════════════════════════════════════
// SCANLINE PAINTER (A-13 Treatment 3)
// ═══════════════════════════════════════════════════════════

class _ScanlinePainter extends CustomPainter {
  _ScanlinePainter({
    required this.progress,
    required this.opacity,
    required this.tealColor,
  });

  final double progress;
  final double opacity;
  final Color tealColor;

  @override
  void paint(Canvas canvas, Size size) {
    final x = progress * size.width;

    // Main scanline.
    canvas.drawRect(
      Rect.fromLTWH(x - 0.75, 0, 1.5, size.height),
      Paint()..color = tealColor.atOpacity(opacity),
    );

    // Phosphor wake (8px trail).
    final wakeRect = Rect.fromLTWH(x - 8, 0, 8, size.height);
    canvas.drawRect(
      wakeRect,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(x - 8, 0),
          Offset(x, 0),
          [
            Colors.transparent,
            tealColor.atOpacity(opacity * 0.3),
          ],
        ),
    );
  }

  @override
  bool shouldRepaint(covariant _ScanlinePainter old) =>
      progress != old.progress || opacity != old.opacity;
}

// ═══════════════════════════════════════════════════════════
// EPICENTER PULSE PAINTER (🍒5)
// ═══════════════════════════════════════════════════════════

class _EpicenterPulsePainter extends CustomPainter {
  _EpicenterPulsePainter({
    required this.origin,
    required this.progress,
    required this.maxRadius,
    required this.tealColor,
  });

  final Offset origin;
  final double progress;
  final double maxRadius;
  final Color tealColor;

  @override
  void paint(Canvas canvas, Size size) {
    // Two concentric rings, staggered.
    for (int i = 0; i < 2; i++) {
      final ringProgress = (progress - i * 0.15).clamp(0.0, 1.0);
      if (ringProgress <= 0) continue;

      final radius = maxRadius * ringProgress;
      final opacity =
          (1.0 - ringProgress) * 0.3 * (1.0 - i * 0.3);

      canvas.drawCircle(
        origin,
        radius,
        Paint()
          ..color = tealColor.atOpacity(opacity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5 * (1.0 - ringProgress),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _EpicenterPulsePainter old) =>
      progress != old.progress || origin != old.origin;
}

// ═══════════════════════════════════════════════════════════
// CHART RETICLE PAINTER (🍒19)
// ═══════════════════════════════════════════════════════════

class _ChartReticlePainter extends CustomPainter {
  _ChartReticlePainter({
    required this.color,
    this.armLength = 8,
  });

  final Color color;
  final double armLength;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final inset = 4.0;
    final corners = [
      Offset(inset, inset),
      Offset(size.width - inset, inset),
      Offset(inset, size.height - inset),
      Offset(size.width - inset, size.height - inset),
    ];

    // Top-left.
    canvas.drawLine(
      corners[0],
      Offset(corners[0].dx + armLength, corners[0].dy),
      paint,
    );
    canvas.drawLine(
      corners[0],
      Offset(corners[0].dx, corners[0].dy + armLength),
      paint,
    );
    // Top-right.
    canvas.drawLine(
      corners[1],
      Offset(corners[1].dx - armLength, corners[1].dy),
      paint,
    );
    canvas.drawLine(
      corners[1],
      Offset(corners[1].dx, corners[1].dy + armLength),
      paint,
    );
    // Bottom-left.
    canvas.drawLine(
      corners[2],
      Offset(corners[2].dx + armLength, corners[2].dy),
      paint,
    );
    canvas.drawLine(
      corners[2],
      Offset(corners[2].dx, corners[2].dy - armLength),
      paint,
    );
    // Bottom-right.
    canvas.drawLine(
      corners[3],
      Offset(corners[3].dx - armLength, corners[3].dy),
      paint,
    );
    canvas.drawLine(
      corners[3],
      Offset(corners[3].dx, corners[3].dy - armLength),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _ChartReticlePainter old) =>
      color != old.color;
}

// ═══════════════════════════════════════════════════════════
// FLATLINE PAINTER (🍒18: Error state dead signal)
// ═══════════════════════════════════════════════════════════


// ═══════════════════════════════════════════════════════════
// NOISE FLOOR PAINTER (🍒 Treatment 117: Empty state noise)
// ═══════════════════════════════════════════════════════════

class _NoiseFloorPainter extends CustomPainter {
  _NoiseFloorPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rng = math.Random(137);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    // Scatter random dots across the area to simulate noise floor.
    final dotCount = (size.width * size.height / 400).toInt().clamp(50, 300);
    for (int i = 0; i < dotCount; i++) {
      final x = rng.nextDouble() * size.width;
      final y = rng.nextDouble() * size.height;
      canvas.drawCircle(Offset(x, y), 0.5, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _NoiseFloorPainter old) =>
      color != old.color;
}

// ═══════════════════════════════════════════════════════════
// COLLECTING TRENDS PLACEHOLDER (< 3 data points)
// ═══════════════════════════════════════════════════════════

class _CollectingTrendsPlaceholder extends StatefulWidget {
  const _CollectingTrendsPlaceholder({
    required this.dataPointCount,
    required this.reduceMotion,
  });

  final int dataPointCount;
  final bool reduceMotion;

  @override
  State<_CollectingTrendsPlaceholder> createState() =>
      _CollectingTrendsPlaceholderState();
}

class _CollectingTrendsPlaceholderState
    extends State<_CollectingTrendsPlaceholder>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );
    if (!widget.reduceMotion) _pulseCtrl.repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseCtrl
      ..stop()
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: BaselineSpacing.lg,
        vertical: BaselineSpacing.xl,
      ),
      child: Column(
        children: [
          SizedBox(
            height: _kChartMaxHeight * 0.6,
            child: AnimatedBuilder(
              animation: _pulseCtrl,
              builder: (context, _) {
                return CustomPaint(
                  size: Size(double.infinity, _kChartMaxHeight * 0.6),
                  painter: _CollectingTrendsPainter(
                    pulseValue: widget.reduceMotion ? 0.5 : _pulseCtrl.value,
                    color: BaselineColors.teal,
                    hasDataPoint: widget.dataPointCount > 0,
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: BaselineSpacing.md),
          Text(
            kTrendsNotReady,
            textAlign: TextAlign.center,
            style: BaselineTypography.body2.copyWith(
              color: BaselineColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _CollectingTrendsPainter extends CustomPainter {
  _CollectingTrendsPainter({
    required this.pulseValue,
    required this.color,
    required this.hasDataPoint,
  });

  final double pulseValue;
  final Color color;
  final bool hasDataPoint;

  @override
  void paint(Canvas canvas, Size size) {
    final cy = size.height / 2;
    final opacity = 0.12 + (pulseValue * 0.08);

    // Flat horizontal baseline line.
    final linePaint = Paint()
      ..color = color.atOpacity(opacity)
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(
      Offset(0, cy),
      Offset(size.width, cy),
      linePaint,
    );

    // Single dot at right end if exactly 1 data point.
    if (hasDataPoint) {
      canvas.drawCircle(
        Offset(size.width - 8, cy),
        3.0,
        Paint()..color = color.atOpacity(0.25),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CollectingTrendsPainter old) =>
      old.pulseValue != pulseValue ||
      old.color != color ||
      old.hasDataPoint != hasDataPoint;
}

// ═══════════════════════════════════════════════════════════
// END F4.13
// ═══════════════════════════════════════════════════════════
