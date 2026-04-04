/// F4.11 — Lens Lab™ Screen (Spectral Analysis Bench)
///
/// Three independent measurement instruments (GP, CL, GR) each pass
/// different analytical wavelengths through the same speech specimen.
/// Convergent readings = clean signal. Divergent readings = chromatic
/// splitting visible in real time.
///
/// INTERNAL NOTE: Backend flag is ENABLE_WAR_ROOM and SQL view is
/// war_room. UI-facing name is "Lens Lab™". Never diverge.
///
/// LAYOUT (top to bottom):
/// 1. Header: back + "Lens Lab™" centered (tappable) + status pill
/// 2. Teal accent glow line (pulsing, own AnimatedBuilder)
/// 3. Instrument label + figure name
/// 4. Filter Wheel label + LensToggle
/// 5. Specimen card (statement text + source + date)
/// 6. Metric sections x4 (own AnimatedBuilder for bar grow):
///    ALL view: 3 bars + consensus mu divider
///    Individual view: single bar, focused
/// 7. Framing section with SPLIT/CONVERGENT indicator
/// 8. Variance banner + A-4 Split Microscope™ (Pro+, ALL view)
/// 9. Count-up (own AnimatedBuilder) + A-7 MeasuredByRow
/// 10. Action bar (150.5 export, guarded by _entranceComplete)
/// 11. Disclaimer footer
/// 12. "CALIBRATION COMPLETE" stamp
///
/// DATA FLOW:
/// 1. StatementService.getStatement() → analyses[] + consensus
/// 2. LensLabService.buildComparison() → LensComparison
/// 3. LensLabService.filterByLens() → filtered view
///
/// ENTITLEMENT: PRO-gated screen access.
///
/// Path: lib/screens/lens_lab.dart
library;

// ── 1. Dart SDK ──────────────────────────────────────────
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:baseline_app/config/tier_feature_map.dart';

// ── 2. Flutter ───────────────────────────────────────────
import 'package:flutter/material.dart';

// ── 3. Third-party ───────────────────────────────────────
import 'package:go_router/go_router.dart';
// ── 4. Project: config ───────────────────────────────────
import 'package:baseline_app/config/theme.dart';
import 'package:baseline_app/config/constants.dart';
import 'package:baseline_app/config/routes.dart';

// ── 5. Project: models / services ────────────────────────
import 'package:baseline_app/models/statement_detail.dart' as models;
import 'package:baseline_app/models/lens_lab.dart';
import 'package:baseline_app/services/statement_service.dart';
import 'package:baseline_app/services/lens_lab_service.dart';
import 'package:baseline_app/services/figures_service.dart';
import 'package:baseline_app/widgets/empty_state_widget.dart';

// ── 6. Project: widgets / utils ──────────────────────────
import 'package:baseline_app/widgets/baseline_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:baseline_app/providers/tier_provider.dart';
import 'package:baseline_app/widgets/baseline_system_ui.dart';
import 'package:baseline_app/widgets/lens_toggle.dart';
import 'package:baseline_app/widgets/source_badge.dart';
import 'package:baseline_app/widgets/empty_state.dart';
import 'package:baseline_app/widgets/shimmer_loading.dart';
import 'package:baseline_app/widgets/disclaimer_footer.dart';
import 'package:baseline_app/widgets/info_bottom_sheet.dart';
import 'package:baseline_app/widgets/error_state.dart';
import 'package:baseline_app/widgets/measured_by_row.dart';
import 'package:baseline_app/widgets/variance_strip.dart';
import 'package:baseline_app/widgets/rate_app_popup.dart';
import 'package:baseline_app/widgets/soft_paywall_popup.dart';
import 'package:baseline_app/utils/export_util.dart';
import 'package:baseline_app/utils/haptic_util.dart';
import 'package:baseline_app/widgets/feature_gate.dart';

// ═══════════════════════════════════════════════════════════
// DATE HELPERS (replaces package:intl)
// ═══════════════════════════════════════════════════════════
const _kMonths = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
String _fmtDateMDY(DateTime d) => '${_kMonths[d.month - 1]} ${d.day}, ${d.year}';

// ═══════════════════════════════════════════════════════════
// CONSTANTS
// ═══════════════════════════════════════════════════════════

// Layout.
const double _kIconTouchTarget = 44.0;
const double _kAccentLineHeight = 2.0;
const double _kBorderWidth = 2.0;
const double _kBorderOpacity = 0.30;
const int _kStatementTextMaxLines = 4;
const double _kFramingPillHeight = 28.0;

// Wavelength hues (matching A-4 Split Microscope™).
const Color _kGPHue = BaselineColors.spectralTeal; // Pure teal: λ₁
const Color _kCLHue = BaselineColors.spectralCyan; // Cyan shift: λ₂
const Color _kGRHue = BaselineColors.spectralGreen; // Green shift: λ₃

/// Maps model code to wavelength hue for ALL view.
const Map<String, Color> _kModelHues = {
  'GP': _kGPHue,
  'CL': _kCLHue,
  'GR': _kGRHue,
};

/// Maps model code to wavelength opacity for ALL view.
const Map<String, double> _kModelHueOps = {
  'GP': 0.80,
  'CL': 0.70,
  'GR': 0.60,
};

// Entrance timing.
const Duration _kEntranceDuration = Duration(milliseconds: 1200);
const Duration _kBarGrowDuration = Duration(milliseconds: 300);
const Duration _kCountUpDuration = Duration(milliseconds: 400);
const Duration _kPulseDuration = Duration(milliseconds: 4000);
const Duration _kAmbientDuration = Duration(milliseconds: 3000);
const Duration _kBarShimmerDuration = Duration(milliseconds: 600);
const Duration _kPressDuration = Duration(milliseconds: 80);

// Press scales.
const double _kScaleCard = 0.98;

// Entitlement error routing.
const Set<String> _kPaywallErrorCodes = {'not_entitled', 'feature_gated'};
const Set<String> _kTemporaryErrorCodes = {'rate_limited', 'feature_disabled'};

// Chrome constants.
const double _kChromeSt = 0.5;
const double _kChromeOp = 0.03;
const double _kReticleLen = 10.0;
const double _kReticleInner = 4.0;
const double _kRegDotR = 1.5;
const double _kRegDotOp = 0.06;
const double _kTickSp = 8.0;
const int _kTickCount = 40;
const double _kTickH = 4.0;
const double _kTickHMajor = 7.0;
const double _kPerfDotR = 1.5;
const double _kPerfDotOp = 0.04;
const int _kPerfDotCount = 6;
const double _kPerfDotSp = 14.0;
const double _kStampFont = 5.0;
const double _kStampOp = 0.08;
const int _kAmbientCycles = 5;

// Font family for dart:ui TextStyle (I-10: raw string required).
const String _kMonoFontFamily = 'JetBrainsMono';

// ═══════════════════════════════════════════════════════════
// LENS LAB SCREEN
// ═══════════════════════════════════════════════════════════

class LensLabScreen extends StatefulWidget {
  const LensLabScreen({
    super.key,
    required this.statementId,
  });

  final String statementId;

  @override
  State<LensLabScreen> createState() => _LensLabScreenState();
}

class _LensLabScreenState extends State<LensLabScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  // ── State ──────────────────────────────────────────────
  bool _isLoading = true;
  String? _errorMessage;
  String? _errorCode;
  bool _didRouteToPaywall = false;
  bool _dataLoaded = false;
  bool _entranceFired = false;
  bool _entranceComplete = false;

  models.StatementDetail? _currentStatement;
  LensComparison? _fullComparison;
  LensComparison? _activeComparison;
  String _selectedLens = kLensAll;
  int _figureStatementCount = 0;

  final _lensLabService = const LensLabService();
  final _exportKey = GlobalKey();

  // ── Animation controllers ─────────────────────────────
  late final AnimationController _entranceCtrl;
  late final AnimationController _barGrowCtrl;
  late final AnimationController _countUpCtrl;
  late final AnimationController _pulseCtrl;
  late final AnimationController _ambientCtrl;
  late final AnimationController _scanCtrl;
  late final AnimationController _barShimmerCtrl;

  // Curved animations.
  late final CurvedAnimation _entranceCurve;
  late final CurvedAnimation _barGrowCurve;
  late final CurvedAnimation _countUpCurve;
  late final CurvedAnimation _scanCurve;

  // ── Timers (I-11) ─────────────────────────────────────
  final List<Timer> _pendingTimers = [];
  void Function(AnimationStatus)? _ambientStatusListener;

  // ── Accessibility ─────────────────────────────────────
  bool _reduceMotion = false;
  bool _wasReduced = false;

  // ── Cached layout ─────────────────────────────────────
  TextScaler _cachedTextScaler = TextScaler.noScaling;

  // ── Pre-computed TextPainters (I-84) ──────────────────
  TextPainter? _stampPainter;
  TextPainter? _waveLabelPainter;
  TextPainter? _watermarkPainter;

  // ── Lifecycle ─────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _entranceCtrl = AnimationController(
      vsync: this,
      duration: _kEntranceDuration,
    );
    _entranceCurve = CurvedAnimation(
      parent: _entranceCtrl,
      curve: Curves.easeOutCubic,
    );

    _barGrowCtrl = AnimationController(
      vsync: this,
      duration: _kBarGrowDuration,
    );
    _barGrowCurve = CurvedAnimation(
      parent: _barGrowCtrl,
      curve: Curves.easeOutCubic,
    );

    _countUpCtrl = AnimationController(
      vsync: this,
      duration: _kCountUpDuration,
    );
    _countUpCurve = CurvedAnimation(
      parent: _countUpCtrl,
      curve: Curves.easeOut,
    );

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: _kPulseDuration,
    );

    _scanCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _scanCurve = CurvedAnimation(
      parent: _scanCtrl,
      curve: Curves.easeOutCubic,
    );

    _barShimmerCtrl = AnimationController(
      vsync: this,
      duration: _kBarShimmerDuration,
    );

    // I-77: Create ambient in initState (not deferred).
    _ambientCtrl = AnimationController(
      vsync: this,
      duration: _kAmbientDuration,
    );

    _loadData();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // I-2/I-12: MediaQuery for persistent screens.
    final reduced = MediaQuery.disableAnimationsOf(context);
    // I-9: Mid-flight snap on false→true transition.
    if (reduced && !_wasReduced) {
      _snapAllAnimations();
    }
    _reduceMotion = reduced;
    _wasReduced = reduced;

    final mq = MediaQuery.of(context);
    final newScaler = mq.textScaler;
    if (newScaler != _cachedTextScaler) {
      _cachedTextScaler = newScaler;
      _rebuildChromeTextPainters();
    }
  }

  // 3N: PlatformDispatcher in observer (no context needed).
  @override
  void didChangeAccessibilityFeatures() {
    final reduced = ui.PlatformDispatcher.instance
        .accessibilityFeatures.reduceMotion;
    if (reduced && !_wasReduced) {
      _snapAllAnimations();
    }
    _reduceMotion = reduced;
    _wasReduced = reduced;
  }

  void _snapAllAnimations() {
    for (final t in _pendingTimers) {
      t.cancel();
    }
    _pendingTimers.clear();
    _entranceCtrl.value = 1.0;
    _barGrowCtrl.value = 1.0;
    _countUpCtrl.value = 1.0;
    _scanCtrl.value = 1.0;
    _barShimmerCtrl.value = 1.0;
    _pulseCtrl.stop();
    _ambientCtrl.stop();
    setState(() => _entranceComplete = true);
  }

  // ── Pre-computed TextPainters (I-84) ──────────────────

  void _rebuildChromeTextPainters() {
    _stampPainter?.dispose();
    _waveLabelPainter?.dispose();
    _watermarkPainter?.dispose();

    final scaledStampSize =
        _cachedTextScaler.scale(_kStampFont);

    _stampPainter = TextPainter(
      text: TextSpan(
        text: 'SPECTRAL ANALYSIS',
        style: TextStyle(
          fontFamily: _kMonoFontFamily,
          fontSize: scaledStampSize,
          color: BaselineColors.teal.atOpacity(_kStampOp),
          letterSpacing: 1.5,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
    )..layout();

    _waveLabelPainter = TextPainter(
      text: TextSpan(
        text: 'λ₁ · λ₂ · λ₃',
        style: TextStyle(
          fontFamily: _kMonoFontFamily,
          fontSize: scaledStampSize,
          color: BaselineColors.teal.atOpacity(0.06),
          letterSpacing: 1.0,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
    )..layout();

    _watermarkPainter = TextPainter(
      text: TextSpan(
        text: 'λ₁·λ₂·λ₃ ANALYZED',
        style: TextStyle(
          fontFamily: _kMonoFontFamily,
          fontSize: scaledStampSize,
          color: BaselineColors.teal.atOpacity(0.06),
          letterSpacing: 1.5,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
    )..layout();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final t in _pendingTimers) {
      t.cancel();
    }
    _pendingTimers.clear();

    // Curves before controllers (I-15).
    _scanCurve.dispose();
    _countUpCurve.dispose();
    _barGrowCurve.dispose();
    _entranceCurve.dispose();

    // Stop before dispose on all controllers (I-29).
    _barShimmerCtrl
      ..stop()
      ..dispose();
    if (_ambientStatusListener != null) {
      _ambientCtrl.removeStatusListener(_ambientStatusListener!);
    }
    _ambientCtrl
      ..stop()
      ..dispose();
    _scanCtrl
      ..stop()
      ..dispose();
    _pulseCtrl
      ..stop()
      ..dispose();
    _countUpCtrl
      ..stop()
      ..dispose();
    _barGrowCtrl
      ..stop()
      ..dispose();
    _entranceCtrl
      ..stop()
      ..dispose();

    // Pre-computed TPs.
    _stampPainter?.dispose();
    _waveLabelPainter?.dispose();
    _watermarkPainter?.dispose();

    super.dispose();
  }

  // ── Data loading ──────────────────────────────────────

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _errorCode = null;
    });

    try {
      final statementService = StatementService();
      final response = await statementService.getStatement(
        widget.statementId,
      );
      if (!mounted) return;

      final comparison = _lensLabService.buildComparison(
        analyses: response.analyses,
        consensus: response.consensus,
      );

      // Fetch figure statement count (non-blocking for UI)
      int stmtCount = 0;
      try {
        stmtCount = await FiguresService()
            .getStatementCount(response.statement.figureId);
      } catch (_) {
        // Non-critical — fall back to 0 (hides count-up)
      }

      setState(() {
        _currentStatement = response.statement;
        _fullComparison = comparison;
        _activeComparison = comparison;
        _selectedLens = kLensAll;
        _figureStatementCount = stmtCount;
        _isLoading = false;
        _dataLoaded = true;
      });

      _runEntrance();
      _firePostLoadTriggers();
    } catch (e) {
      if (!mounted) return;
      _handleError(e);
    }
  }

  void _handleError(Object e) {
    final code =
        e is StatementServiceException ? e.code : null;

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
      setState(() {
        _isLoading = false;
        _errorMessage = code == 'rate_limited'
            ? 'Too many requests. Try again shortly.'
            : 'Lens Lab™ is temporarily unavailable.';
        _errorCode = code;
      });
      return;
    }

    setState(() {
      _isLoading = false;
      _errorMessage = e is StatementServiceException
          ? e.message
          : 'Unable to load Lens Lab™. Pull to retry.';
      _errorCode = code;
    });
  }

  Future<void> _onRefresh() async {
    _didRouteToPaywall = false;
    try {
      final statementService = StatementService();
      final response = await statementService.getStatement(
        widget.statementId,
      );
      if (!mounted) return;

      final comparison = _lensLabService.buildComparison(
        analyses: response.analyses,
        consensus: response.consensus,
      );

      setState(() {
        _currentStatement = response.statement;
        _fullComparison = comparison;
        if (_selectedLens == kLensAll) {
          _activeComparison = comparison;
        } else {
          _activeComparison = _lensLabService.filterByLens(
            full: comparison,
            lensCode: _selectedLens,
          );
        }
        _errorMessage = null;
        _errorCode = null;
      });

      HapticUtil.refreshComplete();
    } catch (e) {
      if (!mounted) return;
      _handleError(e);
    }
  }

  // ── Entrance choreography ─────────────────────────────

  void _runEntrance() {
    if (_entranceFired) return;
    _entranceFired = true;

    if (_reduceMotion) {
      _entranceCtrl.value = 1.0;
      _barGrowCtrl.value = 1.0;
      _countUpCtrl.value = 1.0;
      _scanCtrl.value = 1.0;
      _barShimmerCtrl.value = 1.0;
      _entranceComplete = true;
      return;
    }

    _entranceCtrl.forward();
    _scanCtrl.forward();

    // Bars grow mid-entrance (I-4: Timer, not Future.delayed).
    _pendingTimers.add(Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      _barGrowCtrl.forward();
    }));

    // Bar shimmer highlight sweep.
    _pendingTimers.add(Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      _barShimmerCtrl.forward();
    }));

    // Count-up near end.
    _pendingTimers.add(Timer(const Duration(milliseconds: 700), () {
      if (!mounted) return;
      _countUpCtrl.forward();
    }));

    // Pulse accent line.
    _pulseCtrl.repeat(reverse: true);

    // measurementComplete haptic + entranceComplete flag at Phase 9.
    _pendingTimers.add(Timer(const Duration(milliseconds: 1000), () {
      if (!mounted) return;
      HapticUtil.measurementComplete();
      setState(() => _entranceComplete = true);
    }));

    // Start ambient glow (finite cycles, I-18: status listener).
    _pendingTimers.add(Timer(const Duration(milliseconds: 1200), () {
      if (!mounted) return;
      _startAmbient();
    }));
  }

  void _startAmbient() {
    // Remove previous listener if any (prevents accumulation).
    if (_ambientStatusListener != null) {
      _ambientCtrl.removeStatusListener(_ambientStatusListener!);
    }
    var cycles = 0;
    _ambientStatusListener = (status) {
      if (status == AnimationStatus.completed) {
        cycles++;
        if (cycles < _kAmbientCycles && mounted) {
          _ambientCtrl.reverse();
        }
      } else if (status == AnimationStatus.dismissed &&
          cycles < _kAmbientCycles) {
        if (mounted) _ambientCtrl.forward();
      }
    };
    _ambientCtrl.addStatusListener(_ambientStatusListener!);
    _ambientCtrl.forward();
  }

  // I-78: Sequential popup gate.
  void _firePostLoadTriggers() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      RateAppPopup.maybeShow(context).then((_) {
        if (mounted) {
          final currentTier = ProviderScope.containerOf(context).read(tierProvider).tier;
          SoftPaywallPopup.maybeShow(context, tier: currentTier.isEmpty ? 'free' : currentTier);
        }
      });
    });
  }

  // ── Lens toggle ───────────────────────────────────────

  void _onLensChanged(String lens) {
    if (lens == _selectedLens) return;
    if (_fullComparison == null) return;
    HapticUtil.selection();

    // 🍒128: Calibration flash on filter change.
    if (!_reduceMotion) {
      _scanCtrl.reset();
      _scanCtrl.forward();
    }

    setState(() {
      _selectedLens = lens;
      if (lens == kLensAll) {
        _activeComparison = _fullComparison;
      } else {
        _activeComparison = _lensLabService.filterByLens(
          full: _fullComparison!,
          lensCode: lens,
        );
      }
    });
  }

  // ── Export (I-82: guarded behind entrance) ────────────

  Future<void> _onExport() async {
    if (!_entranceComplete) return;
    HapticUtil.medium();
    final name = _currentStatement?.figureName ?? 'Analysis';
    final success = await ExportUtil.captureAndShare(
      _exportKey,
      subject: 'Lens Lab™: $name',
    );
    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Export failed. Please try again.'),
        ),
      );
    }
  }

  // ── Stagger helper ────────────────────────────────────

  double _stagger(double offset) {
    if (_reduceMotion) return 1.0;
    final t = _entranceCurve.value;
    const window = 0.15;
    return ((t - offset) / window).clamp(0.0, 1.0);
  }

  // ── Build ─────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return BaselineSystemUI(
      child: Scaffold(
        backgroundColor: BaselineColors.scaffoldBackground,
        body: SafeArea(
          child: _isLoading
              ? _buildLoading()
              : _errorMessage != null
                  ? _buildError()
                  : _fullComparison != null
                      ? _buildContent()
                      : _buildLoading(),
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════
  // LOADING STATE
  // ════════════════════════════════════════════════════════

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

  // ════════════════════════════════════════════════════════
  // ERROR STATE
  // ════════════════════════════════════════════════════════

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

  // ════════════════════════════════════════════════════════
  // CONTENT (I-79: animations pushed to leaf nodes)
  // ════════════════════════════════════════════════════════

  Widget _buildContent() {
    final full = _fullComparison!;

    return Stack(
      children: [
        // Layer 0: Screen chrome (own AnimatedBuilder, isolated).
        if (!_reduceMotion)
          Positioned.fill(
            child: RepaintBoundary(
              child: AnimatedBuilder(
                animation: Listenable.merge([
                  _entranceCurve,
                  _scanCurve,
                  _ambientCtrl,
                ]),
                builder: (context, _) {
                  return CustomPaint(
                    painter: _BenchChromePainter(
                      entrance: _entranceCurve.value,
                      scanProgress: _scanCurve.value,
                      ambient: _ambientCtrl.value,
                      stampPainter: _stampPainter,
                      waveLabelPainter: _waveLabelPainter,
                    ),
                  );
                },
              ),
            ),
          ),

        // Layer 1: Content (entrance stagger only).
        AnimatedBuilder(
          animation: _entranceCurve,
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
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // §1 Header.
                    _buildHeader(),

                    // §2 Accent glow line (own AnimatedBuilder).
                    _buildAccentLine(),
                    const SizedBox(height: BaselineSpacing.sm),

                    // §3 Instrument label + figure name.
                    Opacity(
                      opacity: _stagger(0.15),
                      child: _buildInstrumentLabel(),
                    ),
                    const SizedBox(height: BaselineSpacing.lg),

                    // §4 Filter wheel + toggle.
                    Opacity(
                      opacity: _stagger(0.20),
                      child: _buildFilterWheel(full),
                    ),
                    const SizedBox(height: BaselineSpacing.lg),

                    // §5 Specimen card.
                    if (_currentStatement != null)
                      Opacity(
                        opacity: _stagger(0.25),
                        child: Transform.translate(
                          offset: Offset(
                            0,
                            (1 - _stagger(0.25)) * 6,
                          ),
                          child: RepaintBoundary(
                            key: _exportKey,
                            child: _buildSpecimenCard(
                              _currentStatement!,
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: BaselineSpacing.lg),

                    // §6 Metrics + Framing.
                    if (_activeComparison == null &&
                        _selectedLens != kLensAll)
                      _buildLensUnavailable(_selectedLens)
                    else if (!full.hasData)
                      const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: BaselineSpacing.lg,
                        ),
                        child: EmptyStateWidget(
                          variant: EmptyStateVariant.analysis,
                        ),
                      )
                    else ...[
                      for (var i = 0;
                          i < LensMetric.values.length;
                          i++)
                        Opacity(
                          opacity: _stagger(0.35 + (i * 0.05)),
                          child: Transform.translate(
                            offset: Offset(
                              0,
                              (1 - _stagger(0.35 + (i * 0.05))) *
                                  6,
                            ),
                            child: RepaintBoundary(
                              child: _buildMetricSection(
                                (_activeComparison ?? full)
                                    .metricFor(
                                  LensMetric.values[i],
                                ),
                                isAllView:
                                    _selectedLens == kLensAll,
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(height: BaselineSpacing.md),

                      // 🍒138: Connector dots between metrics.
                      ExcludeSemantics(
                        child: Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: List.generate(3, (i) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 3,
                                ),
                                child: Container(
                                  width: 2,
                                  height: 2,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: BaselineColors.teal
                                        .atOpacity(0.08),
                                  ),
                                ),
                              );
                            }),
                          ),
                        ),
                      ),
                      const SizedBox(height: BaselineSpacing.md),

                      // Framing.
                      Opacity(
                        opacity: _stagger(0.55),
                        child: Transform.translate(
                          offset: Offset(
                            0,
                            (1 - _stagger(0.55)) * 6,
                          ),
                          child: _buildFramingSection(
                            (_activeComparison ?? full).framing,
                          ),
                        ),
                      ),

                      // Variance banner.
                      if (full.varianceDetected)
                        Opacity(
                          opacity: _stagger(0.60),
                          child: Transform.translate(
                            offset: Offset(
                              0,
                              (1 - _stagger(0.60)) * 6,
                            ),
                            child: _buildVarianceBanner(),
                          ),
                        ),

                      // A-4 Split Microscope™ (Pro+, ALL view).
                      if (_selectedLens == kLensAll &&
                          full.varianceDetected)
                        Opacity(
                          opacity: _stagger(0.65),
                          child: FeatureGate(
                            feature: GatedFeature.splitMicroscope,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: BaselineSpacing.lg,
                                vertical: BaselineSpacing.xs,
                              ),
                              child: VarianceStrip(
                                comparison: full,
                              ),
                            ),
                          ),
                        ),
                    ],

                    const SizedBox(height: BaselineSpacing.lg),

                    // §9 Count-up (own AnimatedBuilder).
                    if (full.hasData) ...[
                      _buildCountUp(),
                      const SizedBox(height: BaselineSpacing.sm),

                      // MeasuredByRow.
                      Opacity(
                        opacity: _stagger(0.72),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: BaselineSpacing.lg,
                          ),
                          child: MeasuredByRow(
                            modelProviders: const [
                              'gpt',
                              'claude',
                              'grok',
                            ],
                            analyzedAt: null,
                          ),
                        ),
                      ),

                      // 🍒132: Wavelength legend dots.
                      Opacity(
                        opacity: _stagger(0.73),
                        child: ExcludeSemantics(
                          child: Center(
                            child: Padding(
                              padding: const EdgeInsets.only(
                                top: BaselineSpacing.xs,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _buildWavelengthDot(_kGPHue),
                                  const SizedBox(width: 6),
                                  _buildWavelengthDot(_kCLHue),
                                  const SizedBox(width: 6),
                                  _buildWavelengthDot(_kGRHue),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(height: BaselineSpacing.lg),

                    // §10 Action bar.
                    Opacity(
                      opacity: _stagger(0.75),
                      child: _buildActionBar(),
                    ),

                    const SizedBox(height: BaselineSpacing.lg),

                    // §11 Disclaimer footer.
                    Opacity(
                      opacity: _stagger(0.80),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: BaselineSpacing.lg,
                        ),
                        child: DisclaimerFooter(),
                      ),
                    ),

                    const SizedBox(height: BaselineSpacing.md),

                    // §12 Calibration stamp.
                    Opacity(
                      opacity: _stagger(0.85),
                      child: _buildCalibrationStamp(),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  // ════════════════════════════════════════════════════════
  // §1 HEADER
  // ════════════════════════════════════════════════════════

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: BaselineSpacing.lg,
        vertical: BaselineSpacing.sm,
      ),
      child: Row(
        children: [
          // Back button.
          Semantics(
            button: true,
            label: 'Go back',
            excludeSemantics: true,
            child: _TapScale(
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

          // Title with info.
          Semantics(
            button: true,
            label: 'Lens Lab info',
            excludeSemantics: true,
            child: GestureDetector(
              onTap: () {
                HapticUtil.light();
                InfoBottomSheet.show(
                  context,
                  key: 'lens_lab',
                  surface: 'Lens Lab™',
                );
              },
              behavior: HitTestBehavior.opaque,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // (U) classification.
                  ExcludeSemantics(
                    child: Text(
                      '(U) ',
                      style: BaselineTypography.dataSmall.copyWith(
                        color: BaselineColors.teal.atOpacity(0.20),
                      ),
                    ),
                  ),
                  Text(
                    'Lens Lab™',
                    style: BaselineTypography.h2.copyWith(
                      color: BaselineColors.textPrimary,
                    ),
                  ),
                  const SizedBox(width: BaselineSpacing.xs),
                  BaselineIcon(
                    BaselineIconType.info,
                    size: 16,
                    color: BaselineColors.textSecondary
                        .atOpacity(0.7),
                  ),
                ],
              ),
            ),
          ),
          const Spacer(),

          // Status pill + 🍒135 acquisition lock dots.
          if (_dataLoaded) ...[
            ExcludeSemantics(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(3, (i) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 3),
                    child: Container(
                      width: 3,
                      height: 3,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: BaselineColors.teal.atOpacity(0.25),
                      ),
                    ),
                  );
                }),
              ),
            ),
            const SizedBox(width: 4),
            _StatusPill(label: 'SPECTRUM\nACQUIRED'),
          ] else if (_isLoading)
            _StatusPill(label: 'ACTIVE\nCALIBRATION'),
          if (!_dataLoaded && !_isLoading)
            const SizedBox(width: _kIconTouchTarget),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════
  // §2 ACCENT GLOW LINE (own AnimatedBuilder, I-83)
  // ════════════════════════════════════════════════════════

  Widget _buildAccentLine() {
    return AnimatedBuilder(
      animation: _pulseCtrl,
      builder: (context, _) {
        final pulseOp = _reduceMotion
            ? 0.6
            : 0.4 + (_pulseCtrl.value * 0.3);
        return ExcludeSemantics(
          child: Container(
            height: _kAccentLineHeight,
            margin: const EdgeInsets.symmetric(
              horizontal: BaselineSpacing.xl,
            ),
            decoration: BoxDecoration(
              color: BaselineColors.teal.atOpacity(pulseOp),
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        );
      },
    );
  }

  // ════════════════════════════════════════════════════════
  // §3 INSTRUMENT LABEL + FIGURE NAME
  // ════════════════════════════════════════════════════════

  Widget _buildInstrumentLabel() {
    final name = _currentStatement?.figureName;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: BaselineSpacing.lg,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ExcludeSemantics(
            child: Text(
              'INSTRUMENT:',
              style: BaselineTypography.dataSmall.copyWith(
                color: BaselineColors.teal.atOpacity(0.20),
                letterSpacing: 1.0,
              ),
            ),
          ),
          const SizedBox(width: BaselineSpacing.xs),
          // Micro-dot separator (🍒24).
          ExcludeSemantics(
            child: Container(
              width: 2,
              height: 2,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: BaselineColors.teal.atOpacity(0.15),
              ),
            ),
          ),
          const SizedBox(width: BaselineSpacing.xs),
          if (name != null)
            Flexible(
              child: Text(
                name.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: BaselineTypography.dataSmall.copyWith(
                  color: BaselineColors.textSecondary,
                  letterSpacing: 1.0,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════
  // §4 FILTER WHEEL + TOGGLE
  // ════════════════════════════════════════════════════════

  Widget _buildFilterWheel(LensComparison full) {
    return Column(
      children: [
        // Filter wheel label (🍒31).
        ExcludeSemantics(
          child: Text(
            'FILTER WHEEL',
            style: BaselineTypography.dataSmall.copyWith(
              color: BaselineColors.teal.atOpacity(0.10),
              letterSpacing: 2.0,
            ),
          ),
        ),
        const SizedBox(height: BaselineSpacing.sm),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: BaselineSpacing.lg,
          ),
          child: Center(
            child: LensToggle(
              selected: _selectedLens,
              onChanged: _onLensChanged,
              availableLenses: full.availableLenses,
            ),
          ),
        ),
      ],
    );
  }

  // ════════════════════════════════════════════════════════
  // §5 SPECIMEN CARD
  // ════════════════════════════════════════════════════════

  Widget _buildSpecimenCard(models.StatementDetail statement) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: BaselineSpacing.lg,
      ),
      child: _TapScale(
        scale: _kScaleCard,
        onTap: () => HapticUtil.light(),
        child: CustomPaint(
          foregroundPainter: _SpecimenChromePainter(
            opacity: _stagger(0.25),
            watermarkPainter: _watermarkPainter,
          ),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(BaselineSpacing.lg),
            decoration: BoxDecoration(
              color: BaselineColors.card,
              border: Border.all(
                color: BaselineColors.borderInactive
                    .atOpacity(_kBorderOpacity),
                width: _kBorderWidth,
              ),
              borderRadius:
                  BorderRadius.circular(BaselineRadius.md),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Classification label.
                ExcludeSemantics(
                  child: Text(
                    'RECORDED SPECIMEN',
                    style: BaselineTypography.dataSmall.copyWith(
                      color: BaselineColors.teal.atOpacity(0.10),
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
                const SizedBox(height: BaselineSpacing.sm),

                // Statement text.
                Text(
                  statement.statementText,
                  maxLines: _kStatementTextMaxLines,
                  overflow: TextOverflow.ellipsis,
                  style: BaselineTypography.body2.copyWith(
                    color: BaselineColors.textSecondary,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: BaselineSpacing.md),

                // Source + date row.
                Row(
                  children: [
                    Flexible(
                      child: statement.sourceUrl != null
                          ? SourceBadge(
                              sourceUrl: statement.sourceUrl!,
                            )
                          : Text(
                              'Source',
                              style: BaselineTypography.caption
                                  .copyWith(
                                color:
                                    BaselineColors.textSecondary,
                              ),
                            ),
                    ),
                    const Spacer(),
                    Text(
                      _fmtDateMDY(
                        statement.statedAt.toLocal(),
                      ),
                      style:
                          BaselineTypography.dataSmall.copyWith(
                        color: BaselineColors.textSecondary,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: BaselineSpacing.xs),

                // 🍒137: Specimen serial number.
                ExcludeSemantics(
                  child: Text(
                    'SPEC-${statement.id.substring(0, math.min(8, statement.id.length))}',
                    style: BaselineTypography.dataSmall.copyWith(
                      color: BaselineColors.teal.atOpacity(0.03),
                      letterSpacing: 1.0,
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

  // ════════════════════════════════════════════════════════
  // LENS UNAVAILABLE
  // ════════════════════════════════════════════════════════

  Widget _buildLensUnavailable(String lens) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: BaselineSpacing.lg,
        vertical: BaselineSpacing.xl,
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            BaselineIcon(
              BaselineIconType.noResults,
              size: 48,
              color: BaselineColors.textSecondary.atOpacity(0.5),
            ),
            const SizedBox(height: BaselineSpacing.md),
            Text(
              'No $lens analysis available',
              style: BaselineTypography.body1.copyWith(
                color: BaselineColors.textSecondary,
              ),
            ),
            const SizedBox(height: BaselineSpacing.xs),
            Text(
              'This instrument has not yet analyzed this specimen.',
              style: BaselineTypography.caption.copyWith(
                color: BaselineColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════
  // §6 METRIC SECTION (own AnimatedBuilder for bars)
  // ════════════════════════════════════════════════════════

  Widget _buildMetricSection(
    MetricComparison metric, {
    required bool isAllView,
  }) {
    final semanticParts = <String>[
      '${metric.metric.label}:',
      ...metric.values.map(
        (v) =>
            '${v.providerLabel} ${v.value.toStringAsFixed(1)}',
      ),
      if (metric.consensusAvg != null && isAllView)
        'Consensus average ${metric.consensusAvg!.toStringAsFixed(1)}',
    ];

    return Semantics(
      container: true,
      label: semanticParts.join('. '),
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: BaselineSpacing.lg,
            vertical: BaselineSpacing.xs,
          ),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(BaselineSpacing.md),
            decoration: BoxDecoration(
              color: BaselineColors.card,
              border: Border.all(
                color: BaselineColors.borderInactive
                    .atOpacity(_kBorderOpacity),
                width: _kBorderWidth,
              ),
              borderRadius:
                  BorderRadius.circular(BaselineRadius.md),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Instrument readout hairline (🍒60-61).
                Container(
                  height: 0.5,
                  color: BaselineColors.white.atOpacity(0.03),
                ),
                const SizedBox(height: BaselineSpacing.sm),

                // Section header.
                GestureDetector(
                  onTap: () {
                    HapticUtil.light();
                    InfoBottomSheet.show(
                      context,
                      key: metric.metric.infoKey,
                      surface: 'Lens Lab™',
                    );
                  },
                  behavior: HitTestBehavior.opaque,
                  child: Row(
                    children: [
                      // Registration dot (🍒62).
                      Container(
                        width: 3,
                        height: 3,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: BaselineColors.teal
                              .atOpacity(0.06),
                        ),
                      ),
                      const SizedBox(width: BaselineSpacing.xs),
                      Text(
                        metric.metric.label,
                        style: BaselineTypography.h3.copyWith(
                          color: BaselineColors.textPrimary,
                        ),
                      ),
                      const SizedBox(width: BaselineSpacing.xs),
                      BaselineIcon(
                        BaselineIconType.info,
                        size: 16,
                        color: BaselineColors.textSecondary
                            .atOpacity(0.7),
                      ),
                      const Spacer(),
                      // Sub-label.
                      Text(
                        isAllView
                            ? 'EMISSION SPECTRUM'
                            : 'WAVELENGTH ${_wavelengthLabel(_selectedLens)}',
                        style: BaselineTypography.dataSmall
                            .copyWith(
                          color: BaselineColors.teal
                              .atOpacity(0.08),
                          letterSpacing: 1.0,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: BaselineSpacing.sm),

                // Model bars (A1-C2: LayoutBuilder outside AnimatedBuilder).
                LayoutBuilder(
                  builder: (context, constraints) {
                    // Resolve bar track width once (static).
                    final barTrackWidth = constraints.maxWidth
                        - 28 // model label
                        - BaselineSpacing.sm // gap
                        - BaselineSpacing.sm // gap
                        - 40; // value label
                    return AnimatedBuilder(
                      animation: Listenable.merge([
                        _barGrowCurve,
                        _barShimmerCtrl,
                      ]),
                      builder: (context, _) {
                        return Column(
                          children: [
                            ...metric.values.map((value) {
                              return Padding(
                                padding: const EdgeInsets.only(
                                  bottom: BaselineSpacing.xs,
                                ),
                                child: _buildModelBar(
                                  value,
                                  isAllView: isAllView,
                                  allValues: isAllView
                                      ? metric.values
                                      : null,
                                  trackWidth: barTrackWidth,
                                ),
                              );
                            }),
                          ],
                        );
                      },
                    );
                  },
                ),

                // Consensus mu divider (ALL view, >=2 models).
                if (isAllView && metric.consensusAvg != null)
                  Padding(
                    padding: const EdgeInsets.only(
                      top: BaselineSpacing.xs,
                    ),
                    child: Row(
                      children: [
                        Text(
                          'μ',
                          style: BaselineTypography.data.copyWith(
                            color: BaselineColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(
                          width: BaselineSpacing.sm,
                        ),
                        Expanded(
                          child: Container(
                            height: 1,
                            color: BaselineColors.textSecondary
                                .atOpacity(0.5),
                          ),
                        ),
                        const SizedBox(
                          width: BaselineSpacing.sm,
                        ),
                        Text(
                          metric.consensusAvg!
                              .toStringAsFixed(1),
                          style: BaselineTypography.data.copyWith(
                            color: BaselineColors.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _wavelengthLabel(String lens) {
    return switch (lens) {
      'GP' => 'λ₁',
      'CL' => 'λ₂',
      'GR' => 'λ₃',
      _ => '',
    };
  }

  Widget _buildModelBar(
    LensMetricValue value, {
    required bool isAllView,
    List<LensMetricValue>? allValues,
    required double trackWidth,
  }) {
    final hue = isAllView
        ? (_kModelHues[value.providerLabel] ?? BaselineColors.teal)
        : BaselineColors.teal;
    final hueOp = isAllView
        ? (_kModelHueOps[value.providerLabel] ?? 0.80)
        : 0.90;
    final barFraction =
        (_barGrowCurve.value * value.value / 100.0)
            .clamp(0.0, 1.0);

    // 🍒140: Emission peak marker (highest bar in ALL view).
    final isPeak = isAllView &&
        allValues != null &&
        allValues.isNotEmpty &&
        value.value ==
            allValues
                .map((v) => v.value)
                .reduce((a, b) => a > b ? a : b);

    final barW = trackWidth * barFraction;

    return Row(
      children: [
        // Model label.
        SizedBox(
          width: 28,
          child: Text(
            value.providerLabel,
            style: BaselineTypography.data.copyWith(
              color: isAllView
                  ? hue.atOpacity(hueOp)
                  : BaselineColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: BaselineSpacing.sm),

        // Bar (A1-C2: no LayoutBuilder, uses pre-resolved trackWidth).
        Expanded(
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Track.
              Container(
                height: 6,
                decoration: BoxDecoration(
                  color: BaselineColors.borderInactive
                      .atOpacity(0.15),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              // Fill.
              Container(
                height: 6,
                width: barW,
                decoration: BoxDecoration(
                  color: hue.atOpacity(hueOp),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              // Emission glow (ALL view only, 🍒69).
              if (isAllView && barW > 2)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: 1,
                  child: Container(
                    decoration: BoxDecoration(
                      color: hue.atOpacity(0.40),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              // Bar shimmer (🍒130).
              if (barW > 4 && _barShimmerCtrl.value < 1.0)
                Positioned(
                  left: barW * _barShimmerCtrl.value - 16,
                  top: 0,
                  bottom: 0,
                  width: 24,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(3),
                      color: BaselineColors.white.atOpacity(
                        0.15 *
                            (1.0 - _barShimmerCtrl.value),
                      ),
                    ),
                  ),
                ),
              // 🍒140: Peak marker triangle.
              if (isPeak && barW > 8)
                Positioned(
                  left: barW - 4,
                  top: -5,
                  child: CustomPaint(
                    size: const Size(8, 4),
                    painter: _PeakMarkerPainter(
                      color: hue.atOpacity(0.25),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: BaselineSpacing.sm),

        // Value.
        SizedBox(
          width: 40,
          child: Text(
            value.value.toStringAsFixed(1),
            textAlign: TextAlign.end,
            style: BaselineTypography.data.copyWith(
              color: BaselineColors.teal,
              fontSize: 12,
            ),
          ),
        ),
      ],
    );
  }

  // ════════════════════════════════════════════════════════
  // §7 FRAMING SECTION
  // ════════════════════════════════════════════════════════

  Widget _buildFramingSection(FramingComparison framing) {
    if (framing.values.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: BaselineSpacing.lg,
        vertical: BaselineSpacing.xs,
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(BaselineSpacing.md),
        decoration: BoxDecoration(
          color: BaselineColors.card,
          border: Border.all(
            color: BaselineColors.borderInactive
                .atOpacity(_kBorderOpacity),
            width: _kBorderWidth,
          ),
          borderRadius: BorderRadius.circular(BaselineRadius.md),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header.
            GestureDetector(
              onTap: () {
                HapticUtil.light();
                InfoBottomSheet.show(
                  context,
                  key: 'framing_radar',
                  surface: 'Lens Lab™',
                );
              },
              behavior: HitTestBehavior.opaque,
              child: Row(
                children: [
                  Text(
                    'Framing',
                    style: BaselineTypography.h3.copyWith(
                      color: BaselineColors.textPrimary,
                    ),
                  ),
                  const SizedBox(width: BaselineSpacing.xs),
                  BaselineIcon(
                    BaselineIconType.info,
                    size: 16,
                    color: BaselineColors.textSecondary
                        .atOpacity(0.7),
                  ),
                  const Spacer(),

                  // SPLIT or CONVERGENT indicator.
                  if (framing.hasSplit)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: BaselineSpacing.sm,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: BaselineColors.amber
                            .atOpacity(0.1),
                        border: Border.all(
                          color: BaselineColors.amber
                              .atOpacity(0.3),
                          width: 1,
                        ),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          BaselineIcon(
                            BaselineIconType.warning,
                            size: 16,
                            color: BaselineColors.amber,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'SPLIT',
                            style: BaselineTypography.data
                                .copyWith(
                              color: BaselineColors.amber,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    Text(
                      'CONVERGENT',
                      style:
                          BaselineTypography.dataSmall.copyWith(
                        color: BaselineColors.teal
                            .atOpacity(0.30),
                        letterSpacing: 1.0,
                      ),
                    ),
                ],
              ),
            ),

            // Sub-label.
            const SizedBox(height: 2),
            ExcludeSemantics(
              child: Text(
                'OPTICAL CLASSIFICATION',
                style: BaselineTypography.dataSmall.copyWith(
                  color: BaselineColors.teal.atOpacity(0.08),
                  letterSpacing: 1.0,
                ),
              ),
            ),

            const SizedBox(height: BaselineSpacing.sm),

            // Per-model framing pills.
            ...framing.values.map((value) {
              return Padding(
                padding: const EdgeInsets.only(
                  bottom: BaselineSpacing.xs,
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 28,
                      child: Text(
                        value.providerLabel,
                        style: BaselineTypography.data.copyWith(
                          color: BaselineColors.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: BaselineSpacing.sm),
                    Flexible(
                      child: Container(
                        height: _kFramingPillHeight,
                        padding: const EdgeInsets.symmetric(
                          horizontal: BaselineSpacing.sm,
                        ),
                        decoration: BoxDecoration(
                          color: BaselineColors.teal
                              .atOpacity(0.08),
                          border: Border.all(
                            color: BaselineColors.teal
                                .atOpacity(0.15),
                            width: 1,
                          ),
                          borderRadius:
                              BorderRadius.circular(6),
                        ),
                        alignment: Alignment.centerLeft,
                        child: Text(
                          value.framing,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: BaselineTypography.caption
                              .copyWith(
                            color: BaselineColors.teal,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════
  // §8 VARIANCE BANNER
  // ════════════════════════════════════════════════════════

  Widget _buildVarianceBanner() {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: BaselineSpacing.lg,
        vertical: BaselineSpacing.sm,
      ),
      child: _TapScale(
        scale: _kScaleCard,
        onTap: () {
          HapticUtil.light();
          InfoBottomSheet.show(
            context,
            key: 'variance_detected',
            surface: 'Lens Lab™',
          );
        },
        child: Semantics(
          button: true,
          label: 'Variance Detected. Tap for explanation.',
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(BaselineSpacing.md),
            decoration: BoxDecoration(
              color: BaselineColors.amber.atOpacity(0.05),
              border: Border.all(
                color: BaselineColors.amber.atOpacity(0.4),
                width: _kBorderWidth,
              ),
              borderRadius:
                  BorderRadius.circular(BaselineRadius.md),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    BaselineIcon(
                      BaselineIconType.warning,
                      size: 20,
                      color: BaselineColors.amber,
                    ),
                    const SizedBox(width: BaselineSpacing.sm),
                    Expanded(
                      child: Text(
                        'Variance Detected',
                        style: BaselineTypography.body2.copyWith(
                          color: BaselineColors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    BaselineIcon(
                      BaselineIconType.info,
                      size: 16,
                      color: BaselineColors.textSecondary
                          .atOpacity(0.7),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                ExcludeSemantics(
                  child: Text(
                    'CHROMATIC ABERRATION',
                    style: BaselineTypography.dataSmall.copyWith(
                      color: BaselineColors.amber.atOpacity(0.30),
                      letterSpacing: 1.0,
                    ),
                  ),
                ),
                const SizedBox(height: BaselineSpacing.xxs),
                Text(
                  'Instruments diverge on framing classification for this specimen.',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: BaselineTypography.caption.copyWith(
                    color: BaselineColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════
  // §9 COUNT-UP (own AnimatedBuilder)
  // ════════════════════════════════════════════════════════

  Widget _buildCountUp() {
    final totalCount = _figureStatementCount;
    if (totalCount <= 0) return const SizedBox.shrink();

    return Opacity(
      opacity: _stagger(0.70),
      child: AnimatedBuilder(
        animation: _countUpCurve,
        builder: (context, _) {
          final displayCount =
              (_countUpCurve.value * totalCount).round();
          return Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: BaselineSpacing.lg,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ExcludeSemantics(
                  child: Text(
                    'ANALYZED',
                    style:
                        BaselineTypography.dataSmall.copyWith(
                      color:
                          BaselineColors.teal.atOpacity(0.20),
                      letterSpacing: 1.0,
                    ),
                  ),
                ),
                const SizedBox(width: BaselineSpacing.xs),
                Text(
                  '$displayCount',
                  style: BaselineTypography.data.copyWith(
                    color: BaselineColors.teal,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  'statements',
                  style:
                      BaselineTypography.dataSmall.copyWith(
                    color: BaselineColors.textSecondary,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ════════════════════════════════════════════════════════
  // §10 ACTION BAR (uses F_ICONS, I-82: entrance guard)
  // ════════════════════════════════════════════════════════

  Widget _buildActionBar() {
    final canExport = _entranceComplete;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Semantics(
          button: true,
          label: 'Export analysis as image',
          excludeSemantics: true,
          child: _ActionButton(
            icon: BaselineIconType.export,
            onTap: canExport ? _onExport : null,
            label: 'EXPORT',
          ),
        ),
        const SizedBox(width: BaselineSpacing.xl),
        Semantics(
          button: true,
          label: 'Share analysis',
          excludeSemantics: true,
          child: _ActionButton(
            icon: BaselineIconType.share,
            onTap: canExport ? _onExport : null,
            label: 'SHARE',
          ),
        ),
      ],
    );
  }

  // ════════════════════════════════════════════════════════
  // §12 CALIBRATION STAMP
  // ════════════════════════════════════════════════════════

  Widget _buildCalibrationStamp() {
    return ExcludeSemantics(
      child: Center(
        child: Text(
          'CALIBRATION COMPLETE',
          style: BaselineTypography.dataSmall.copyWith(
            color: BaselineColors.teal.atOpacity(0.08),
            letterSpacing: 2.0,
          ),
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════
  // 🍒132: WAVELENGTH LEGEND DOT
  // ════════════════════════════════════════════════════════

  Widget _buildWavelengthDot(Color hue) {
    return Container(
      width: 4,
      height: 4,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: hue.atOpacity(0.35),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// STATUS PILL
// ═══════════════════════════════════════════════════════════

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 6,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: BaselineColors.teal.atOpacity(0.08),
        border: Border.all(
          color: BaselineColors.teal.atOpacity(0.15),
          width: 1,
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: BaselineTypography.dataSmall.copyWith(
          color: BaselineColors.teal.atOpacity(0.40),
          fontSize: 5,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// TAP SCALE (press-scale wrapper, matches F4.10 LOCKED)
// ═══════════════════════════════════════════════════════════

class _TapScale extends StatefulWidget {
  const _TapScale({
    required this.onTap,
    required this.child,
    this.scale = 0.98,
  });

  final VoidCallback onTap;
  final Widget child;
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
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedScale(
        scale: _pressed ? widget.scale : 1.0,
        duration: _kPressDuration,
        child: widget.child,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// ACTION BUTTON (uses F_ICONS, matches F4.10 pattern)
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
              width: _kIconTouchTarget,
              height: _kIconTouchTarget,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: BaselineColors.teal.atOpacity(0.15),
                  width: 1,
                ),
              ),
              child: Center(
                child: BaselineIcon(
                  icon,
                  size: 24,
                  color: BaselineColors.teal.atOpacity(0.6),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: BaselineTypography.dataSmall.copyWith(
                color: BaselineColors.textSecondary,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// 🍒140: PEAK MARKER PAINTER
// ═══════════════════════════════════════════════════════════

class _PeakMarkerPainter extends CustomPainter {
  _PeakMarkerPainter({required Color color})
      : _paint = Paint()..color = color;

  final Paint _paint;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width / 2, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path, _paint);
  }

  @override
  bool shouldRepaint(_PeakMarkerPainter old) =>
      _paint.color != old._paint.color;
}

// ═══════════════════════════════════════════════════════════
// SPECIMEN CHROME PAINTER
// ═══════════════════════════════════════════════════════════

/// Draws classified specimen chrome: reticle corner brackets,
/// handling marks, and rotated spectral watermark.
class _SpecimenChromePainter extends CustomPainter {
  _SpecimenChromePainter({
    required this.opacity,
    required this.watermarkPainter,
  })  : _chromePaint = Paint()
          ..color = BaselineColors.white.atOpacity(0.04)
          ..strokeWidth = 0.5
          ..style = PaintingStyle.stroke,
        _hashPaint = Paint()
          ..color = BaselineColors.teal.atOpacity(0.05)
          ..strokeWidth = 0.5;

  final double opacity;
  final TextPainter? watermarkPainter;

  // I-71: constructor-initialized paint finals.
  final Paint _chromePaint;
  final Paint _hashPaint;

  static const double _reticleLen = 8.0;
  static const double _reticleInner = 3.0;
  static const double _inset = 6.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (opacity <= 0) return;

    final w = size.width;
    final h = size.height;

    // Modulate paint alpha by entrance opacity.
    final cp = Paint()
      ..color = _chromePaint.color.atOpacity(0.04 * opacity)
      ..strokeWidth = _chromePaint.strokeWidth
      ..style = PaintingStyle.stroke;

    // Reticle corners (4 corners).
    _drawCorner(canvas, _inset, _inset, 1, 1, cp, opacity);
    _drawCorner(canvas, w - _inset, _inset, -1, 1, cp, opacity);
    _drawCorner(
        canvas, _inset, h - _inset, 1, -1, cp, opacity);
    _drawCorner(
        canvas, w - _inset, h - _inset, -1, -1, cp, opacity);

    // Handling marks: 3 hashmarks bottom-right (🍒36).
    final hp = Paint()
      ..color = _hashPaint.color.atOpacity(0.05 * opacity)
      ..strokeWidth = _hashPaint.strokeWidth;
    for (var i = 0; i < 3; i++) {
      final x = w - _inset - 16 + (i * 5.0);
      final y = h - _inset - 4;
      canvas.drawLine(Offset(x, y), Offset(x, y + 3), hp);
    }

    // 🍒131: Focal crosshair at center.
    final focalP = Paint()
      ..color = BaselineColors.teal.atOpacity(0.04 * opacity)
      ..strokeWidth = 0.5;
    final cx = w / 2;
    final cy = h / 2;
    canvas.drawLine(
        Offset(cx - 4, cy), Offset(cx + 4, cy), focalP);
    canvas.drawLine(
        Offset(cx, cy - 4), Offset(cx, cy + 4), focalP);

    // Spectral watermark (I-84: pre-computed TP).
    if (watermarkPainter != null) {
      canvas.save();
      canvas.translate(w - _inset + 1, h * 0.65);
      canvas.rotate(-1.5708);
      final wPaint = Paint()
        ..colorFilter = ColorFilter.mode(
          BaselineColors.teal.atOpacity(0.06 * opacity),
          BlendMode.srcIn,
        );
      canvas.saveLayer(null, wPaint);
      watermarkPainter!.paint(canvas, Offset.zero);
      canvas.restore();
      canvas.restore();
    }
  }

  void _drawCorner(Canvas canvas, double x, double y, double dx,
      double dy, Paint paint, double opacity) {
    canvas.drawLine(
      Offset(x, y),
      Offset(x + (_reticleLen * dx), y),
      paint,
    );
    canvas.drawLine(
      Offset(x, y),
      Offset(x, y + (_reticleLen * dy)),
      paint,
    );
    // Inner tick.
    final tickP = Paint()
      ..color = BaselineColors.white.atOpacity(0.02 * opacity)
      ..strokeWidth = 0.5;
    canvas.drawLine(
      Offset(x + (_reticleInner * dx), y),
      Offset(x + (_reticleInner * dx), y + (2 * dy)),
      tickP,
    );
    // Corner dot.
    canvas.drawCircle(
      Offset(x, y),
      0.8,
      Paint()
        ..color = BaselineColors.teal.atOpacity(0.04 * opacity),
    );
  }

  @override
  bool shouldRepaint(_SpecimenChromePainter old) =>
      opacity != old.opacity;
}

// ═══════════════════════════════════════════════════════════
// BENCH CHROME PAINTER
// ═══════════════════════════════════════════════════════════

class _BenchChromePainter extends CustomPainter {
  _BenchChromePainter({
    required this.entrance,
    required this.scanProgress,
    required this.ambient,
    required this.stampPainter,
    required this.waveLabelPainter,
  })  : _chromePaint = Paint()
          ..color = BaselineColors.white.atOpacity(_kChromeOp)
          ..strokeWidth = _kChromeSt
          ..style = PaintingStyle.stroke,
        _rulerPaint = Paint()
          ..color = BaselineColors.white.atOpacity(0.02)
          ..strokeWidth = 0.5,
        _perfPaint = Paint()
          ..color = BaselineColors.teal.atOpacity(_kPerfDotOp),
        _regPaint = Paint()
          ..color = BaselineColors.teal.atOpacity(_kRegDotOp),
        _hairPaint = Paint()
          ..color = BaselineColors.white.atOpacity(0.03)
          ..strokeWidth = 0.5;

  final double entrance;
  final double scanProgress;
  final double ambient;
  final TextPainter? stampPainter;
  final TextPainter? waveLabelPainter;

  // I-71: constructor-initialized paint finals.
  final Paint _chromePaint;
  final Paint _rulerPaint;
  final Paint _perfPaint;
  final Paint _regPaint;
  final Paint _hairPaint;

  @override
  void paint(Canvas canvas, Size size) {
    if (entrance < 0.01) return;
    final w = size.width;
    final h = size.height;
    final op = entrance;

    // Modulate base paints by entrance.
    final cp = Paint()
      ..color = _chromePaint.color.atOpacity(_kChromeOp * op)
      ..strokeWidth = _chromePaint.strokeWidth
      ..style = PaintingStyle.stroke;
    final rp = Paint()
      ..color = _rulerPaint.color.atOpacity(0.02 * op)
      ..strokeWidth = _rulerPaint.strokeWidth;
    final pp = Paint()
      ..color = _perfPaint.color.atOpacity(_kPerfDotOp * op);
    final gp = Paint()
      ..color = _regPaint.color.atOpacity(_kRegDotOp * op);
    final hp = Paint()
      ..color = _hairPaint.color.atOpacity(0.03 * op)
      ..strokeWidth = _hairPaint.strokeWidth;

    // Reticle corners (4 brackets).
    _drawReticle(canvas, 16, 16, 1, 1, cp, op);
    _drawReticle(canvas, w - 16, 16, -1, 1, cp, op);
    _drawReticle(canvas, 16, h - 16, 1, -1, cp, op);
    _drawReticle(canvas, w - 16, h - 16, -1, -1, cp, op);

    // Top calibration ruler (🍒133: sequential reveal with entrance).
    final visibleTicks =
        (_kTickCount * entrance).round().clamp(0, _kTickCount);
    for (var i = 0; i < visibleTicks; i++) {
      final x = 30 + (i * _kTickSp);
      if (x > w - 30) break;
      final isMajor = i % 5 == 0;
      canvas.drawLine(
        Offset(x, 8),
        Offset(x, 8 + (isMajor ? _kTickHMajor : _kTickH)),
        rp,
      );
    }

    // Film perforation dots (left edge).
    for (var i = 0; i < _kPerfDotCount; i++) {
      canvas.drawCircle(
        Offset(8, 60 + (i * _kPerfDotSp)),
        _kPerfDotR,
        pp,
      );
    }

    // Registration dots (4 corners).
    canvas.drawCircle(Offset(10, 10), _kRegDotR, gp);
    canvas.drawCircle(Offset(w - 10, 10), _kRegDotR, gp);
    canvas.drawCircle(Offset(10, h - 10), _kRegDotR, gp);
    canvas.drawCircle(Offset(w - 10, h - 10), _kRegDotR, gp);

    // Classification hairlines.
    canvas.drawLine(Offset(20, 6), Offset(w - 20, 6), hp);
    canvas.drawLine(
        Offset(20, h - 6), Offset(w - 20, h - 6), hp);

    // 🍒134: Spectral noise floor (faint random dots).
    final rng = math.Random(42); // Deterministic seed.
    final noisePaint = Paint()
      ..color = BaselineColors.white.atOpacity(0.008 * op);
    for (var i = 0; i < 30; i++) {
      final nx = 30 + rng.nextDouble() * (w - 60);
      final ny = 80 + rng.nextDouble() * (h * 0.5);
      canvas.drawCircle(Offset(nx, ny), 0.5, noisePaint);
    }

    // 🍒139: Bench vibration isolation marks (bottom corners).
    final vibPaint = Paint()
      ..color = BaselineColors.white.atOpacity(0.02 * op)
      ..strokeWidth = 0.5;
    for (var i = 0; i < 3; i++) {
      final offset = i * 4.0;
      canvas.drawLine(
        Offset(20 + offset, h - 14),
        Offset(24 + offset, h - 14),
        vibPaint,
      );
      canvas.drawLine(
        Offset(w - 24 - offset, h - 14),
        Offset(w - 20 - offset, h - 14),
        vibPaint,
      );
    }

    // Scan line (entrance only).
    if (scanProgress > 0 && scanProgress < 1.0) {
      final scanY = h * scanProgress;
      canvas.drawLine(
        Offset(0, scanY),
        Offset(w, scanY),
        Paint()
          ..color = BaselineColors.teal
              .atOpacity(0.08 * (1 - scanProgress))
          ..strokeWidth = 1.0,
      );
    }

    // Ambient glow (left border).
    if (ambient > 0) {
      canvas.drawLine(
        Offset(2, h * 0.1),
        Offset(2, h * 0.9),
        Paint()
          ..color = BaselineColors.teal.atOpacity(0.03 * ambient)
          ..strokeWidth = 1.0,
      );
    }

    // "SPECTRAL ANALYSIS" stamp top-right (I-84: pre-computed TP).
    if (stampPainter != null) {
      stampPainter!.paint(
        canvas,
        Offset(w - stampPainter!.width - 20, 12),
      );
    }

    // Wavelength label bottom-left (I-84: pre-computed TP).
    if (waveLabelPainter != null) {
      waveLabelPainter!.paint(canvas, Offset(20, h - 20));
    }
  }

  void _drawReticle(Canvas canvas, double x, double y, double dx,
      double dy, Paint paint, double opacity) {
    canvas.drawLine(
      Offset(x, y),
      Offset(x + (_kReticleLen * dx), y),
      paint,
    );
    canvas.drawLine(
      Offset(x, y),
      Offset(x, y + (_kReticleLen * dy)),
      paint,
    );
    final tickP = Paint()
      ..color = BaselineColors.white.atOpacity(0.02 * opacity)
      ..strokeWidth = 0.5;
    canvas.drawLine(
      Offset(x + (_kReticleInner * dx), y),
      Offset(x + (_kReticleInner * dx), y + (3 * dy)),
      tickP,
    );
    canvas.drawCircle(
      Offset(x, y),
      1,
      Paint()
        ..color = BaselineColors.teal.atOpacity(0.04 * opacity),
    );
  }

  @override
  bool shouldRepaint(_BenchChromePainter old) =>
      entrance != old.entrance ||
      scanProgress != old.scanProgress ||
      ambient != old.ambient;
}
