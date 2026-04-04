import 'package:baseline_app/config/tier_feature_map.dart';
import 'package:flutter/foundation.dart';
/// F4.9 — The Receipt™ Screen (SIGINT Intercept Log)
///
/// BASELINE's signature semantic similarity feature. Reimagined as
/// a signals intelligence intercept station. The current statement
/// is the primary intercept signal. Past matches are detected return
/// signals. The visual language is oscilloscope waveforms, signal
/// strength meters, and correlation traces. Completely distinct
/// from F4.7's intelligence brief and F4.8's personnel file.
///
/// VISUAL IDENTITY:
/// Signals intelligence intercept log. Waveform visualizations
/// (multi-harmonic sine compositions per statement), signal strength
/// meters (horizontal fill bars with threshold ticks), correlation
/// traces with sinusoidal modulation (not plain beziers), noise floor
/// background, frequency axis spine with time-period labels.
///
/// Three screens, three worlds:
/// F4.7 = You're READING a classified document (paper, stamps)
/// F4.8 = You're REVIEWING a subject (dossier, gauge, monitoring)
/// F4.9 = You're DETECTING signal matches (waveforms, oscilloscope)
///
/// PRE_AUDIT FIXES (20):
/// I-1 atOpacity, I-2/I-12 PlatformDispatcher+_wasReduced,
/// I-11 _pendingTimers, I-15 CurvedAnimation dispose, I-23 TP dispose,
/// I-28 TextScaler, I-29 stop before dispose, I-44 pre-computed TPs,
/// I-68 dart:async, I-71 Paint finals, I-24 RepaintBoundary chrome,
/// F8.10 BaselineSystemUI, icon system (4 replacements),
/// 25s idle timeout, status listener entrance, SoftPaywall bug fix,
/// ShimmerVariant.receipt.
///
/// LOCKED FIXES (5):
/// R1: Split root AnimatedBuilder (painters use super(repaint:),
///     card stagger uses finite AnimatedBuilder).
/// R2: Pre-compute ALL TextPainters (zero construction in paint()).
/// R3: Pre-compute trace geometry (zero computeMetrics in paint()).
/// R4: WidgetsBindingObserver for mid-flight reduceMotion.
/// R5: Export disabled until entrance completes.
///
/// Path: lib/screens/receipt_screen.dart

// 1. Dart SDK
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

// 2. Flutter
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

// 3. Third-party
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
// 4. Config
import 'package:baseline_app/config/constants.dart';
import 'package:baseline_app/config/theme.dart';
import 'package:baseline_app/config/routes.dart';
import 'package:baseline_app/widgets/empty_state_widget.dart';

// 5. Models
import 'package:baseline_app/models/receipt_match.dart';
import 'package:baseline_app/models/statement_detail.dart' as models;

// 6. Services
import 'package:baseline_app/services/entitlement_service.dart';
import 'package:baseline_app/services/receipt_service.dart';
import 'package:baseline_app/services/statement_service.dart';

// 7. Widgets
import 'package:baseline_app/widgets/baseline_icons.dart';
import 'package:baseline_app/widgets/feature_gate.dart';
import 'package:baseline_app/widgets/source_badge.dart';
import 'package:baseline_app/widgets/empty_state.dart';
import 'package:baseline_app/widgets/shimmer_loading.dart';
import 'package:baseline_app/widgets/disclaimer_footer.dart';
import 'package:baseline_app/widgets/partial_failure_banner.dart';
import 'package:baseline_app/widgets/info_bottom_sheet.dart';
import 'package:baseline_app/widgets/rate_app_popup.dart';
import 'package:baseline_app/widgets/soft_paywall_popup.dart';
import 'package:baseline_app/widgets/error_state.dart';
import 'package:baseline_app/widgets/receipt_comparison_overlay.dart';

// 8. Utils
import 'package:baseline_app/utils/export_util.dart';
import 'package:baseline_app/utils/haptic_util.dart';
import 'package:baseline_app/utils/system_ui_utils.dart';

// ═══════════════════════════════════════════════════════════
// DATE HELPERS (replaces package:intl)
// ═══════════════════════════════════════════════════════════
const _kMonths = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
String _fmtDateMDY(DateTime d) => '${_kMonths[d.month - 1]} ${d.day}, ${d.year}';
String _fmtDateMY(DateTime d) => '${_kMonths[d.month - 1]} ${d.year}';
String _fmtDateMyy(DateTime d) => '${_kMonths[d.month - 1]} ${(d.year % 100).toString().padLeft(2, '0')}';
String _fmtMonth(DateTime d) => _kMonths[d.month - 1];

// ═══════════════════════════════════════════════════════════
// LAYOUT CONSTANTS
// ═══════════════════════════════════════════════════════════

/// Match card width as fraction of screen width.
const double _kCardWidthFraction = 0.72;

/// Vertical gap between match cards.
const double _kCardVerticalGap = 56.0;

/// Primary intercept card border width.
const double _kPrimaryBorderWidth = 2.0;

/// Match card border width.
const double _kMatchCardBorder = 1.5;

/// Icon touch target.
const double _kIconTouchTarget = 44.0;

/// Border opacity for match cards.
const double _kBorderOpacity = 0.5;

/// Max lines for match card text.
const int _kMatchTextMaxLines = 3;

/// Max lines for current statement text.
const int _kCurrentTextMaxLines = 5;

/// Intercept badge size (primary).
const double _kPrimaryBadgeSize = 28.0;

/// Intercept badge size (match).
const double _kMatchBadgeSize = 24.0;

/// Signal strength meter dimensions.
const double _kMeterWidth = 60.0;
const double _kMeterHeight = 4.0;

/// Waveform heights.
const double _kPrimaryWaveformHeight = 40.0;
const double _kMatchWaveformHeight = 24.0;

/// Signal bar width (left edge of cards).
const double _kSignalBarWidth = 2.0;

/// Spine stroke width.
const double _kSpineWidth = 2.0;

/// Junction node sizes.
const double _kJunctionOuter = 5.0;
const double _kJunctionInner = 2.0;

/// Stagger delay per card (ms).
const int _kCardStaggerMs = 50;

/// Animation durations.
const Duration _kSweepDuration = Duration(milliseconds: 600);
const Duration _kWaveformDrawDuration = Duration(milliseconds: 800);
const Duration _kTraceDrawDuration = Duration(milliseconds: 700);
const Duration _kCountUpDuration = Duration(milliseconds: 300);
const Duration _kAmbientCycle = Duration(milliseconds: 6000);

/// Idle timeout before pausing ambient animations (I-F4.8 pattern).
const Duration _kIdleTimeout = Duration(seconds: 25);

/// Estimated card height for painter math.
const double _kEstimatedCardHeight = 200.0;


// ═══════════════════════════════════════════════════════════
// RECEIPT SCREEN
// ═══════════════════════════════════════════════════════════

class ReceiptScreen extends ConsumerStatefulWidget {
  const ReceiptScreen({
    super.key,
    required this.statementId,
  });

  final String statementId;

  @override
  ConsumerState<ReceiptScreen> createState() => _ReceiptScreenState();
}

class _ReceiptScreenState extends ConsumerState<ReceiptScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  // ── State ──────────────────────────────────────────────────
  bool _isLoading = true;
  String? _errorMessage;
  models.StatementDetail? _currentStatement;
  ReceiptResponse? _receiptResponse;

  double _screenWidth = 375.0;

  late final ScrollController _scrollController;
  double _lastHapticScrollY = 0;

  final _exportKey = GlobalKey();

  // ── Timers (I-11) ─────────────────────────────────────────
  final List<Timer> _pendingTimers = [];
  Timer? _idleTimer;

  // ── Animation Controllers ──────────────────────────────────

  /// Entrance sweep beam.
  late final AnimationController _sweepController;
  late final CurvedAnimation _sweepCurve;

  /// Waveform draw-on.
  late final AnimationController _waveformController;

  /// Correlation trace draw-on.
  late final AnimationController _traceController;

  /// Count-up on percentages.
  late final AnimationController _countUpController;

  /// Ambient: noise shimmer + waveform breathing + signal sweep.
  late final AnimationController _ambientController;

  /// ReduceMotion state (I-2: PlatformDispatcher).
  bool _reduceMotion = false;
  bool _wasReduced = false;

  /// Signal acquisition flash for primary card (C4).
  bool _showAcquisitionFlash = false;

  /// R5: Entrance complete flag for export guard.
  bool _entranceComplete = false;

  // ── Pre-computed TextPainters (I-44 + R2) ─────────────────
  TextPainter? _chromeStationTp;
  TextPainter? _chromeHandlingTp;
  TextPainter? _chromeSerialTp;
  TextPainter? _chromeCountTp;
  TextPainter? _chromeCallsignTp;
  List<TextPainter> _chromeBandTps = [];
  List<TextPainter> _correlationDateTps = [];
  List<TextPainter> _correlationRTps = [];
  List<TextPainter> _correlationGapTps = [];
  TextScaler _textScaler = TextScaler.noScaling;

  // ── Pre-computed trace geometry (R3) ───────────────────────
  List<List<Offset>> _traceGeometries = [];

  // ── Lifecycle ──────────────────────────────────────────────

  @override
  void initState() {
    super.initState();

    // R4: Observer for mid-flight accessibility changes.
    WidgetsBinding.instance.addObserver(this);

    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);

    // I-2: PlatformDispatcher for reduceMotion.
    _reduceMotion = ui.PlatformDispatcher
        .instance.accessibilityFeatures.reduceMotion;
    _wasReduced = _reduceMotion;

    _sweepController = AnimationController(
      vsync: this,
      duration: _kSweepDuration,
    );
    _sweepCurve = CurvedAnimation(
      parent: _sweepController,
      curve: Curves.easeOutCubic,
    );

    _waveformController = AnimationController(
      vsync: this,
      duration: _kWaveformDrawDuration,
    );

    _traceController = AnimationController(
      vsync: this,
      duration: _kTraceDrawDuration,
    );

    _countUpController = AnimationController(
      vsync: this,
      duration: _kCountUpDuration,
    );

    _ambientController = AnimationController(
      vsync: this,
      duration: _kAmbientCycle,
    );

    _loadReceipt();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _screenWidth = MediaQuery.sizeOf(context).width;
    _textScaler = MediaQuery.textScalerOf(context);

    // I-44: Pre-compute chrome TextPainters.
    _rebuildChromeTextPainters();
  }

  // R4: Mid-flight reduceMotion interception via observer.
  @override
  void didChangeAccessibilityFeatures() {
    final reduced = ui.PlatformDispatcher
        .instance.accessibilityFeatures.reduceMotion;
    if (reduced && !_wasReduced) {
      // false → true: cancel pending timers, snap all controllers.
      for (final timer in _pendingTimers) {
        timer.cancel();
      }
      _pendingTimers.clear();
      _idleTimer?.cancel();

      _sweepController.value = 1.0;
      _waveformController.value = 1.0;
      _traceController.value = 1.0;
      _countUpController.value = 1.0;
      _ambientController.stop();

      if (mounted) setState(() => _entranceComplete = true);
    }
    _reduceMotion = reduced;
    _wasReduced = reduced;
  }

  void _rebuildChromeTextPainters() {
    final teal = BaselineColors.teal;

    _chromeStationTp?.dispose();
    _chromeStationTp = TextPainter(
      text: TextSpan(
        text: 'INTERCEPT STATION',
        style: TextStyle(
          color: teal.atOpacity(0.2),
          fontSize: 9,
          fontFamily: BaselineTypography.monoFontFamily,
          letterSpacing: 1.5,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
      textScaler: _textScaler,
    )..layout();

    final uuid8 = _uuid8();

    _chromeSerialTp?.dispose();
    _chromeSerialTp = TextPainter(
      text: TextSpan(
        text: 'SIG-$uuid8',
        style: TextStyle(
          color: teal.atOpacity(0.03),
          fontSize: 8,
          fontFamily: BaselineTypography.monoFontFamily,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
      textScaler: _textScaler,
    )..layout();

    _chromeHandlingTp?.dispose();
    _chromeHandlingTp = TextPainter(
      text: TextSpan(
        text: 'HANDLE VIA BASELINE CHANNELS ONLY',
        style: TextStyle(
          color: teal.atOpacity(0.03),
          fontSize: 8,
          fontFamily: BaselineTypography.monoFontFamily,
          letterSpacing: 1.0,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
      textScaler: _textScaler,
    )..layout();

    final matchCount = _receiptResponse?.matches.length ?? 0;
    _chromeCountTp?.dispose();
    _chromeCountTp = TextPainter(
      text: TextSpan(
        text: '$matchCount SIGNALS DETECTED',
        style: TextStyle(
          color: teal.atOpacity(0.03),
          fontSize: 7,
          fontFamily: BaselineTypography.monoFontFamily,
          letterSpacing: 0.5,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
      textScaler: _textScaler,
    )..layout();

    // R2: Callsign watermark TP (was inline in paint).
    _chromeCallsignTp?.dispose();
    _chromeCallsignTp = TextPainter(
      text: TextSpan(
        text: 'BASELINE SIGINT',
        style: TextStyle(
          color: teal.atOpacity(0.02),
          fontSize: 7,
          fontFamily: BaselineTypography.monoFontFamily,
          letterSpacing: 1.0,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
      textScaler: _textScaler,
    )..layout();

    // R2: Frequency band label TPs (were inline in paint).
    for (final tp in _chromeBandTps) {
      tp.dispose();
    }
    _chromeBandTps = ['HF', 'MF', 'LF'].map((label) {
      return TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            color: teal.atOpacity(0.04),
            fontSize: 7,
            fontFamily: BaselineTypography.monoFontFamily,
          ),
        ),
        textDirection: ui.TextDirection.ltr,
        textScaler: _textScaler,
      )..layout();
    }).toList();
  }

  /// R2: Pre-compute correlation label TPs after data loads.
  void _rebuildCorrelationLabels() {
    final teal = BaselineColors.teal;
    final matches = _receiptResponse?.matches ?? [];

    for (final tp in _correlationDateTps) {
      tp.dispose();
    }
    for (final tp in _correlationRTps) {
      tp.dispose();
    }
    for (final tp in _correlationGapTps) {
      tp.dispose();
    }

    _correlationDateTps = matches.map((m) {
      return TextPainter(
        text: TextSpan(
          text: _fmtDateMyy(m.statedAt.toLocal()).toUpperCase(),
          style: TextStyle(
            color: teal.atOpacity(0.08),
            fontSize: 7,
            fontFamily: BaselineTypography.monoFontFamily,
          ),
        ),
        textDirection: ui.TextDirection.ltr,
        textScaler: _textScaler,
      )..layout();
    }).toList();

    _correlationRTps = matches.map((m) {
      return TextPainter(
        text: TextSpan(
          text: 'r=${m.similarity.toStringAsFixed(2)}',
          style: TextStyle(
            color: teal.atOpacity(0.06),
            fontSize: 7,
            fontFamily: BaselineTypography.monoFontFamily,
          ),
        ),
        textDirection: ui.TextDirection.ltr,
        textScaler: _textScaler,
      )..layout();
    }).toList();

    // C8 gap labels.
    _correlationGapTps = [];
    for (int i = 1; i < matches.length; i++) {
      final gap =
          matches[i].statedAt.difference(matches[i - 1].statedAt).inDays.abs();
      if (gap > 180) {
        final tp = TextPainter(
          text: TextSpan(
            text: 'SIGNAL GAP',
            style: TextStyle(
              color: teal.atOpacity(0.04),
              fontSize: 6,
              fontFamily: BaselineTypography.monoFontFamily,
            ),
          ),
          textDirection: ui.TextDirection.ltr,
          textScaler: _textScaler,
        )..layout();
        _correlationGapTps.add(tp);
      } else {
        // Placeholder: no gap label for this pair.
        _correlationGapTps.add(TextPainter(
          text: const TextSpan(text: ''),
          textDirection: ui.TextDirection.ltr,
        )..layout());
      }
    }
  }

  /// R3: Pre-compute sinusoidal trace geometry.
  void _precomputeTraceGeometry() {
    final matches = _receiptResponse?.matches ?? [];
    if (matches.length < 2) {
      _traceGeometries = [];
      return;
    }

    final horizontalPadding = BaselineSpacing.lg * 2;
    final availableWidth = _screenWidth - horizontalPadding;
    final spineX = availableWidth / 2;

    _traceGeometries = [];

    for (int i = 0; i < matches.length - 1; i++) {
      final isCurrentLeft = i.isEven;
      final currentY = i * (_kEstimatedCardHeight + _kCardVerticalGap);
      final nextY = (i + 1) * (_kEstimatedCardHeight + _kCardVerticalGap);
      final startY = currentY + _kEstimatedCardHeight / 2;
      final endY = nextY + _kEstimatedCardHeight / 2;

      final similarity =
          i + 1 < matches.length ? matches[i + 1].similarity : 0.5;
      double waveAmplitude;
      double waveFreq;

      if (similarity >= 0.90) {
        waveAmplitude = 2.0;
        waveFreq = 0.3;
      } else if (similarity >= 0.75) {
        waveAmplitude = 3.0;
        waveFreq = 0.2;
      } else if (similarity >= 0.60) {
        waveAmplitude = 4.5;
        waveFreq = 0.15;
      } else {
        waveAmplitude = 6.0;
        waveFreq = 0.1;
      }

      final basePath = Path()
        ..moveTo(spineX, startY)
        ..cubicTo(
          spineX + (isCurrentLeft ? 30 : -30),
          startY + (endY - startY) * 0.3,
          spineX + (isCurrentLeft ? -30 : 30),
          startY + (endY - startY) * 0.7,
          spineX,
          endY,
        );

      final metrics = basePath.computeMetrics().toList();
      if (metrics.isEmpty) {
        _traceGeometries.add([]);
        continue;
      }
      final metric = metrics.first;
      final totalLen = metric.length;

      final points = <Offset>[];
      for (double d = 0; d <= totalLen; d += 2) {
        final tangent = metric.getTangentForOffset(d);
        if (tangent == null) continue;

        final pos = tangent.position;
        final angle = tangent.angle;
        final uniqueSeed = i * 7.3 + similarity * 13.1;
        final sineDisp =
            math.sin(d * waveFreq + uniqueSeed) * waveAmplitude;
        final nx = -math.sin(angle) * sineDisp;
        final ny = math.cos(angle) * sineDisp;
        points.add(Offset(pos.dx + nx, pos.dy + ny));
      }

      _traceGeometries.add(points);
    }
  }

  @override
  void dispose() {
    // R4: Remove observer.
    WidgetsBinding.instance.removeObserver(this);

    // I-11: Cancel all pending timers.
    for (final timer in _pendingTimers) {
      timer.cancel();
    }
    _pendingTimers.clear();
    _idleTimer?.cancel();

    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();

    // I-23: Dispose pre-computed TextPainters.
    _chromeStationTp?.dispose();
    _chromeHandlingTp?.dispose();
    _chromeSerialTp?.dispose();
    _chromeCountTp?.dispose();
    _chromeCallsignTp?.dispose();
    for (final tp in _chromeBandTps) {
      tp.dispose();
    }
    for (final tp in _correlationDateTps) {
      tp.dispose();
    }
    for (final tp in _correlationRTps) {
      tp.dispose();
    }
    for (final tp in _correlationGapTps) {
      tp.dispose();
    }

    // I-15: CurvedAnimation before parent.
    _sweepCurve.dispose();

    // I-29: stop() before dispose(), reverse init order.
    _ambientController.stop();
    _ambientController.dispose();
    _countUpController.stop();
    _countUpController.dispose();
    _traceController.stop();
    _traceController.dispose();
    _waveformController.stop();
    _waveformController.dispose();
    _sweepController.stop();
    _sweepController.dispose();

    super.dispose();
  }

  // ── Data Loading ────────────────────────────────────────────

  Future<void> _loadReceipt() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // BUG-3.4: The Receipt is a CORE feature — never gated.
      // If the entitlement check fails (network error, timeout, etc.),
      // proceed without a token rather than showing "Unable to check access".
      String? entitlementToken;
      try {
        final entitlementService = const EntitlementService();
        final entitlement = await entitlementService.checkEntitlement(
          endpoint: 'get-receipt',
          featureFlag: 'ENABLE_RECEIPT',
        );
        entitlementToken = entitlement.token;
      } on FeatureGatedException {
        // Receipt is core — should never be gated. Proceed without token.
        if (kDebugMode) {
          debugPrint('Receipt: FeatureGatedException ignored (core feature)');
        }
      } on EntitlementServiceException catch (e) {
        // Network/timeout/parse error — proceed without token.
        if (kDebugMode) {
          debugPrint('Receipt: entitlement check failed (${e.code}), proceeding without token');
        }
      }

      if (!mounted) return;

      final statementService = StatementService();
      final receiptService = ReceiptService();

      final results = await Future.wait([
        statementService.getStatement(widget.statementId),
        receiptService.getReceipt(
          statementId: widget.statementId,
          entitlementToken: entitlementToken ?? '',
        ),
      ]);

      if (!mounted) return;

      final statementResponse = results[0] as StatementDetailResponse;
      final receiptResponse = results[1] as ReceiptResponse;

      setState(() {
        _currentStatement = statementResponse.statement;
        _receiptResponse = receiptResponse;
        _isLoading = false;
      });

      // I-44 + R2 + R3: Rebuild TPs and trace geometry with actual data.
      _rebuildChromeTextPainters();
      _rebuildCorrelationLabels();
      _precomputeTraceGeometry();

      _startEntranceSequence();

      // C4: Signal acquisition flash.
      if (!_reduceMotion) {
        setState(() => _showAcquisitionFlash = true);
        _scheduleTimer(const Duration(milliseconds: 400), () {
          if (mounted) setState(() => _showAcquisitionFlash = false);
        });
      }

      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        RateAppPopup.maybeShow(
          context,
          figureId: _currentStatement?.figureId,
        );
        // BUG FIX: SoftPaywallPopup removed from initial load.
        // Only triggers on COMPARE gate decline (T#31).
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _errorMessage = e is ReceiptServiceException
            ? e.message
            : e is StatementServiceException
                ? e.message
                : 'Unable to load The Receipt\u2122. Pull to retry.';
      });
    }
  }

  Future<void> _onRefresh() async {
    try {
      // BUG-3.4: Same pattern as _loadReceipt — Receipt is core, never gated.
      String? entitlementToken;
      try {
        final entitlementService = const EntitlementService();
        final entitlement = await entitlementService.checkEntitlement(
          endpoint: 'get-receipt',
          featureFlag: 'ENABLE_RECEIPT',
        );
        entitlementToken = entitlement.token;
      } on FeatureGatedException {
        // Receipt is core — proceed without token.
      } on EntitlementServiceException catch (e) {
        if (kDebugMode) {
          debugPrint('Receipt refresh: entitlement check failed (${e.code})');
        }
      }

      if (!mounted) return;

      final statementService = StatementService();
      final receiptService = ReceiptService();

      final results = await Future.wait([
        statementService.getStatement(widget.statementId),
        receiptService.getReceipt(
          statementId: widget.statementId,
          entitlementToken: entitlementToken ?? '',
        ),
      ]);

      if (!mounted) return;

      final statementResponse = results[0] as StatementDetailResponse;
      final receiptResponse = results[1] as ReceiptResponse;

      setState(() {
        _currentStatement = statementResponse.statement;
        _receiptResponse = receiptResponse;
        _errorMessage = null;
        });

      _rebuildChromeTextPainters();
      _rebuildCorrelationLabels();
      _precomputeTraceGeometry();
      _startEntranceSequence();
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _errorMessage = e is ReceiptServiceException
            ? e.message
            : 'Unable to refresh. Try again.';
      });
    }
  }

  // ── Timer Utility (I-11) ──────────────────────────────────

  void _scheduleTimer(Duration delay, VoidCallback callback) {
    final timer = Timer(delay, () {
      if (mounted) callback();
    });
    _pendingTimers.add(timer);
  }

  // ── Idle Timeout (F4.8 pattern) ───────────────────────────

  void _resetIdleTimer() {
    _idleTimer?.cancel();
    if (_reduceMotion) return;

    // Wake ambient if stopped.
    if (!_ambientController.isAnimating &&
        _sweepController.isCompleted) {
      _ambientController.repeat();
    }

    _idleTimer = Timer(_kIdleTimeout, () {
      if (mounted && _ambientController.isAnimating) {
        _ambientController.stop();
      }
    });
  }

  // ── Animation Sequences ─────────────────────────────────────

  void _startEntranceSequence() {
    if (_reduceMotion) {
      _sweepController.value = 1.0;
      _waveformController.value = 1.0;
      _traceController.value = 1.0;
      _countUpController.value = 1.0;
      _ambientController.value = 0.0;
      setState(() => _entranceComplete = true);
      return;
    }

    HapticUtil.medium();

    // I-18: Status listener cascade instead of raw Future.delayed.
    _sweepController.forward(from: 0.0);

    void onSweepTick(AnimationStatus status) {
      if (status == AnimationStatus.completed) {
        _sweepController.removeStatusListener(onSweepTick);
        if (!mounted) return;
        _traceController.forward(from: 0.0);
        _countUpController.forward(from: 0.0);

        // R5: Mark entrance complete for export guard.
        setState(() => _entranceComplete = true);

        // Phase 4: Ambient loop after traces start.
        _scheduleTimer(const Duration(milliseconds: 300), () {
          if (!mounted) return;
          _ambientController.repeat();
          _resetIdleTimer();
        });
      }
    }

    _sweepController.addStatusListener(onSweepTick);

    // Phase 2: Waveform draws on at 50% sweep.
    _scheduleTimer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      _waveformController.forward(from: 0.0);
    });
  }

  // ── Scroll Haptic ───────────────────────────────────────────

  void _onScroll() {
    _resetIdleTimer(); // Wake ambient on scroll.
    final pos = _scrollController.position.pixels;
    if ((pos - _lastHapticScrollY).abs() > 80) {
      _lastHapticScrollY = pos;
      HapticUtil.selection();
    }
  }

  // ── Actions ─────────────────────────────────────────────────

  void _onExport() {
    HapticUtil.light();
    ExportUtil.captureAndShare(
      _exportKey,
      filename: 'receipt_${widget.statementId.substring(0, math.min(8, widget.statementId.length))}',
    );
    HapticUtil.success();
  }

  void _onCompare() {
    if (_receiptResponse == null || _currentStatement == null) return;
    HapticUtil.light();
    ReceiptComparisonOverlay.show(
      context,
      response: _receiptResponse!,
      primaryFigureId: _currentStatement!.figureId,
    );
  }

  // ── Helpers ─────────────────────────────────────────────────

  String _formatDtg(DateTime dt) {
    final local = dt.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final min = local.minute.toString().padLeft(2, '0');
    final month = _fmtMonth(local).toUpperCase();
    final year = (local.year % 100).toString().padLeft(2, '0');
    return '$day$hour${min}Z$month$year';
  }

  String _uuid8() {
    return widget.statementId.length >= 8
        ? widget.statementId.substring(0, 8).toUpperCase()
        : widget.statementId.toUpperCase();
  }

  /// Generates a deterministic waveform seed from text.
  static List<double> _waveformSeed(String text) {
    if (text.isEmpty) return [3.0, 5.7, 9.1];
    final hash = text.codeUnits.fold<int>(0, (a, b) => a + b);
    return [
      2.0 + (hash % 7) * 0.5,
      4.0 + (hash % 5) * 0.8,
      7.0 + (hash % 11) * 0.4,
    ];
  }

  // ── Build ──────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // F8.10: BaselineSystemUI wrap.
    // R1: No root AnimatedBuilder. Painters use super(repaint:).
    //     Card stagger uses finite AnimatedBuilder(_sweepController).
    return BaselineSystemUI(
      child: Scaffold(
        backgroundColor: BaselineColors.scaffoldBackground,
        body: SafeArea(
          child: _isLoading
              ? _buildLoading()
              : _errorMessage != null && _receiptResponse == null
                  ? _buildError()
                  : _receiptResponse != null
                      ? _buildContent()
                      : _buildLoading(),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════
  // LOADING STATE
  // ══════════════════════════════════════════════════════════

  Widget _buildLoading() {
    return Column(
      children: [
        _buildHeader(),
        const Expanded(
          child: ShimmerLoading(variant: ShimmerVariant.receipt),
        ),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════
  // ERROR STATE (C6: dead-channel hiss)
  // ══════════════════════════════════════════════════════════

  Widget _buildError() {
    return Column(
      children: [
        _buildHeader(),
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: BaselineSpacing.xl,
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // C6: Dead-channel hiss lines behind error.
                  ExcludeSemantics(
                    child: CustomPaint(
                      size: const Size(200, 120),
                      painter: _DeadChannelPainter(),
                    ),
                  ),
                  ErrorState.custom(
                    icon: BaselineIconType.error,
                    message: 'Unable to load The Receipt\u2122.',
                    detail: 'Please try again.',
                    onRetry: () => _loadReceipt(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════
  // CONTENT
  // ══════════════════════════════════════════════════════════

  Widget _buildContent() {
    final receipt = _receiptResponse!;
    final horizontalPadding = BaselineSpacing.lg * 2;
    final availableWidth = _screenWidth - horizontalPadding;
    final cardWidth = availableWidth * _kCardWidthFraction;

    return GestureDetector(
      // Wake ambient on touch.
      onTapDown: (_) => _resetIdleTimer(),
      behavior: HitTestBehavior.translucent,
      child: Stack(
        children: [
          // ── Screen-level intercept chrome (R1: isolated AnimatedBuilder) ──
          Positioned.fill(
            child: ExcludeSemantics(
              child: RepaintBoundary(
                child: AnimatedBuilder(
                  animation: _ambientController,
                  builder: (context, _) {
                    return CustomPaint(
                      painter: _InterceptChromePainter(
                        sweepProgress: _sweepCurve.value,
                        ambientPhase: _ambientController.value,
                        statementId: widget.statementId,
                        matchCount: receipt.matches.length,
                        reduceMotion: _reduceMotion,
                        stationTp: _chromeStationTp,
                        serialTp: _chromeSerialTp,
                        handlingTp: _chromeHandlingTp,
                        countTp: _chromeCountTp,
                        callsignTp: _chromeCallsignTp,
                        bandTps: _chromeBandTps,
                        textScaler: _textScaler,
                      ),
                    );
                  },
                ),
              ),
            ),
          ),

          // ── Scrollable content ──
          RefreshIndicator(
            onRefresh: _onRefresh,
            color: BaselineColors.teal,
            backgroundColor: BaselineColors.card,
            child: ListView(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(
                bottom: BaselineSpacing.xxl,
              ),
              children: [
                _buildHeader(),
                _buildClassificationOverline(),
                _buildWaveformAccentLine(),
                const SizedBox(height: BaselineSpacing.lg),

                // C1: Reception quality indicator dots.
                _buildReceptionQuality(receipt.matches.length),

                // Export boundary wraps the visual content.
                RepaintBoundary(
                  key: _exportKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_currentStatement != null)
                        _buildPrimaryIntercept(_currentStatement!),
                      const SizedBox(height: BaselineSpacing.lg),

                      if (receipt.hasMatches) ...[
                        _buildTapeReelDivider(),
                        const SizedBox(height: BaselineSpacing.sm),
                        _buildSectionLabel('MATCHED SIGNALS'),
                        const SizedBox(height: BaselineSpacing.md),
                        _buildSignalTimeline(
                          receipt.matches,
                          cardWidth,
                          availableWidth,
                        ),
                      ] else
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: BaselineSpacing.lg,
                          ),
                          child: _buildEmptySignal(),
                        ),
                    ],
                  ),
                ),

                const SizedBox(height: BaselineSpacing.lg),
                if (receipt.hasMatches) _buildFooterCount(receipt),
                const SizedBox(height: BaselineSpacing.md),
                _buildTapeReelDivider(),
                const SizedBox(height: BaselineSpacing.md),

                if (receipt.hasPartialFailure)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: BaselineSpacing.lg,
                    ),
                    child: PartialFailureBanner(
                      message:
                          'Some signals could not be resolved. Pull to retry.',
                    ),
                  ),
                if (receipt.hasPartialFailure)
                  const SizedBox(height: BaselineSpacing.md),

                _buildObservationCaveat(),
                const SizedBox(height: BaselineSpacing.sm),
                const Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: BaselineSpacing.lg,
                  ),
                  child: DisclaimerFooter(),
                ),
                const SizedBox(height: BaselineSpacing.sm),
                // C7: Page indicator.
                _buildPageIndicator(),
                const SizedBox(height: BaselineSpacing.md),
                _buildStationSignOff(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════
  // HEADER
  // ══════════════════════════════════════════════════════════

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: BaselineSpacing.lg,
        vertical: BaselineSpacing.sm,
      ),
      child: Row(
        children: [
          // Back (F_ICONS library).
          _PressScaleButton(
            onTap: () {
              HapticUtil.light();
              if (context.canPop()) {
                context.pop();
              } else {
                context.go(AppRoutes.today);
              }
            },
            child: Semantics(
              button: true,
              label: 'Go back',
              excludeSemantics: true,
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

          // Title.
          _PressScaleButton(
            onTap: () {
              HapticUtil.light();
              InfoBottomSheet.show(context, key: 'receipt');
            },
            child: Semantics(
              button: true,
              label: 'About The Receipt',
              excludeSemantics: true,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'The Receipt\u2122',
                    style: BaselineTypography.h2.copyWith(
                      color: BaselineColors.textPrimary,
                    ),
                  ),
                  const SizedBox(width: BaselineSpacing.xs),
                  BaselineIcon.muted(
                    BaselineIconType.info,
                    size: 16,
                  ),
                ],
              ),
            ),
          ),

          const Spacer(),

          // Actions.
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_receiptResponse != null &&
                  _receiptResponse!.hasMatches)
                FeatureGate(
                  feature: GatedFeature.receiptComparison,
                  onGateDeclined: () {
                    SoftPaywallPopup.maybeShow(
                      context,
                      tier: 'free',
                    );
                  },
                  child: _PressScaleButton(
                    scale: 0.95,
                    onTap: _onCompare,
                    child: Semantics(
                      button: true,
                      label: 'Compare with another figure',
                      excludeSemantics: true,
                      child: SizedBox(
                        height: _kIconTouchTarget,
                        width: _kIconTouchTarget,
                        child: Center(
                          child: Text(
                            'CMP',
                            style:
                                BaselineTypography.dataSmall.copyWith(
                              color: BaselineColors.teal
                                  .atOpacity(0.6),
                              letterSpacing: 0.8,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              // R5: Export disabled until entrance completes.
              _PressScaleButton(
                scale: 0.95,
                onTap: _entranceComplete ? _onExport : () {},
                child: Semantics(
                  button: true,
                  label: 'Export as image',
                  excludeSemantics: true,
                  child: SizedBox(
                    height: _kIconTouchTarget,
                    width: _kIconTouchTarget,
                    child: Center(
                      child: Opacity(
                        opacity: _entranceComplete ? 1.0 : 0.3,
                        child: BaselineIcon.muted(
                          BaselineIconType.export,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════
  // CLASSIFICATION OVERLINE
  // ══════════════════════════════════════════════════════════

  Widget _buildClassificationOverline() {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: BaselineSpacing.lg,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'SIGNAL ANALYSIS \u00b7 SEMANTIC INTERCEPT',
              style: BaselineTypography.dataSmall.copyWith(
                color: BaselineColors.teal.atOpacity(0.15),
                letterSpacing: 0.8,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: BaselineSpacing.sm),
          Text(
            'SID-${_uuid8()}',
            style: BaselineTypography.dataSmall.copyWith(
              color: BaselineColors.textSecondary.atOpacity(0.2),
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════
  // RECEPTION QUALITY INDICATOR (C1)
  // ══════════════════════════════════════════════════════════

  Widget _buildReceptionQuality(int matchCount) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: BaselineSpacing.lg,
        vertical: BaselineSpacing.xs,
      ),
      child: ExcludeSemantics(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: List.generate(4, (i) {
            final active = i < matchCount.clamp(0, 4);
            return Padding(
              padding: const EdgeInsets.only(left: 3),
              child: Container(
                width: 4,
                height: 4,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: BaselineColors.teal
                      .atOpacity(active ? 0.3 : 0.06),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════
  // WAVEFORM ACCENT LINE
  // ══════════════════════════════════════════════════════════

  Widget _buildWaveformAccentLine() {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: BaselineSpacing.xl,
        vertical: BaselineSpacing.xs,
      ),
      child: SizedBox(
        height: 12,
        width: double.infinity,
        child: CustomPaint(
          painter: _WaveformAccentPainter(
            drawProgress: _waveformController.value,
            ambientPhase: _ambientController.value,
            reduceMotion: _reduceMotion,
          ),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════
  // PRIMARY INTERCEPT
  // ══════════════════════════════════════════════════════════

  Widget _buildPrimaryIntercept(models.StatementDetail statement) {
    final staggerAlpha = _reduceMotion
        ? 1.0
        : (_sweepCurve.value > 0.15
            ? ((_sweepCurve.value - 0.15) / 0.3).clamp(0.0, 1.0)
            : 0.0);

    final waveformSeed = _waveformSeed(statement.statementText);

    // C4: Signal acquisition flash on border.
    final borderOpacity = _showAcquisitionFlash ? 0.15 : 0.08;

    return Opacity(
      opacity: staggerAlpha,
      child: Transform.translate(
        offset: Offset(0, _reduceMotion ? 0 : (1 - staggerAlpha) * 8),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: BaselineSpacing.lg,
          ),
          child: _PressScaleButton(
            onTap: () {
              HapticUtil.light();
              context.push(
                AppRoutes.statementPath(statement.statementId),
              );
            },
            child: Semantics(
              button: true,
              label: 'Primary intercept: current statement',
              excludeSemantics: true,
              child: CustomPaint(
                foregroundPainter: _SignalBracketPainter(
                  opacity: 0.06,
                  armLength: 5.0,
                ),
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: BaselineColors.card,
                    border: Border.all(
                      color: BaselineColors.teal
                          .atOpacity(borderOpacity),
                      width: _kPrimaryBorderWidth,
                    ),
                    borderRadius: BorderRadius.circular(
                      BaselineRadius.md,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Signal strength bar: full (source).
                      Container(
                        height: _kSignalBarWidth,
                        decoration: BoxDecoration(
                          color: BaselineColors.teal.atOpacity(0.3),
                          borderRadius: const BorderRadius.only(
                            topLeft:
                                Radius.circular(BaselineRadius.md),
                            topRight:
                                Radius.circular(BaselineRadius.md),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          BaselineSpacing.lg,
                          BaselineSpacing.md,
                          BaselineSpacing.lg,
                          BaselineSpacing.lg,
                        ),
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            // Designation row.
                            Row(
                              children: [
                                _buildInterceptBadge(
                                    '01', _kPrimaryBadgeSize),
                                const SizedBox(
                                    width: BaselineSpacing.sm),
                                Expanded(
                                  child: Text(
                                    'PRIMARY INTERCEPT',
                                    style: BaselineTypography
                                        .dataSmall
                                        .copyWith(
                                      color: BaselineColors.teal
                                          .atOpacity(0.25),
                                      letterSpacing: 1.5,
                                    ),
                                  ),
                                ),
                                Text(
                                  '\u25c9 LOCKED',
                                  style: BaselineTypography.dataSmall
                                      .copyWith(
                                    color: BaselineColors.teal
                                        .atOpacity(0.1),
                                    fontSize: 7,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(
                                height: BaselineSpacing.sm),

                            // Waveform visualization.
                            SizedBox(
                              height: _kPrimaryWaveformHeight,
                              width: double.infinity,
                              child: CustomPaint(
                                painter: _WaveformPainter(
                                  seed: waveformSeed,
                                  drawProgress:
                                      _waveformController.value,
                                  ambientPhase:
                                      _ambientController.value,
                                  opacity: 0.12,
                                  reduceMotion: _reduceMotion,
                                ),
                              ),
                            ),
                            const SizedBox(
                                height: BaselineSpacing.sm),

                            // Figure name.
                            Text(
                              statement.figureName,
                              style:
                                  BaselineTypography.data.copyWith(
                                color: BaselineColors.teal
                                    .atOpacity(0.4),
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(
                                height: BaselineSpacing.sm),

                            // Statement text.
                            Text(
                              statement.statementText,
                              maxLines: _kCurrentTextMaxLines,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  BaselineTypography.body1.copyWith(
                                color:
                                    BaselineColors.textSecondary,
                                height: 1.6,
                              ),
                            ),
                            const SizedBox(
                                height: BaselineSpacing.md),

                            // Source + date row.
                            Row(
                              children: [
                                Flexible(
                                  child: statement.sourceUrl !=
                                          null
                                      ? SourceBadge(
                                          sourceUrl:
                                              statement.sourceUrl!)
                                      : Text(
                                          'Source',
                                          style: BaselineTypography
                                              .caption
                                              .copyWith(
                                            color: BaselineColors
                                                .textSecondary,
                                          ),
                                        ),
                                ),
                                const Spacer(),
                                Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      _fmtDateMDY(
                                          statement.statedAt
                                              .toLocal()),
                                      style: BaselineTypography
                                          .caption
                                          .copyWith(
                                        color: BaselineColors
                                            .textSecondary,
                                      ),
                                    ),
                                    Text(
                                      _formatDtg(
                                          statement.statedAt),
                                      style: BaselineTypography
                                          .dataSmall
                                          .copyWith(
                                        color: BaselineColors.teal
                                            .atOpacity(0.08),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),

                            // Signal metadata flavor.
                            if (statement.topics.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(
                                    top: BaselineSpacing.sm),
                                child: Text(
                                  'FREQ: ${(kTopicDisplayNames[statement.topics.first] ?? statement.topics.first).toUpperCase()} \u00b7 BAND: ${(statement.sourceType ?? "OPEN").toUpperCase()}',
                                  style: BaselineTypography
                                      .dataSmall
                                      .copyWith(
                                    color: BaselineColors.teal
                                        .atOpacity(0.06),
                                    letterSpacing: 0.5,
                                  ),
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
          ),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════
  // TAPE REEL DIVIDER (C3: sprocket holes)
  // ══════════════════════════════════════════════════════════

  Widget _buildTapeReelDivider() {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: BaselineSpacing.lg,
      ),
      child: SizedBox(
        height: 4,
        width: double.infinity,
        child: CustomPaint(
          painter: _TapeReelDividerPainter(),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════
  // SECTION LABEL
  // ══════════════════════════════════════════════════════════

  Widget _buildSectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: BaselineSpacing.lg,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 20,
            height: 10,
            child: CustomPaint(
              painter: _WaveformPrefixPainter(),
            ),
          ),
          const SizedBox(width: BaselineSpacing.xs),
          Text(
            text,
            style: BaselineTypography.dataSmall.copyWith(
              color:
                  BaselineColors.textSecondary.atOpacity(0.4),
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════
  // SIGNAL TIMELINE
  // ══════════════════════════════════════════════════════════

  Widget _buildSignalTimeline(
    List<ReceiptMatch> matches,
    double cardWidth,
    double availableWidth,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: BaselineSpacing.lg,
      ),
      child: AnimatedBuilder(
        animation: Listenable.merge([
          _traceController,
          _countUpController,
        ]),
        builder: (context, _) {
          return CustomPaint(
            painter: _CorrelationTracePainter(
              matchCount: matches.length,
              cardHeight: _kEstimatedCardHeight,
              availableWidth: availableWidth,
              cardWidth: cardWidth,
              similarities:
                  matches.map((m) => m.similarity).toList(),
              matchDates:
                  matches.map((m) => m.statedAt).toList(),
              drawProgress: _traceController.value,
              ambientPhase: _ambientController.value,
              reduceMotion: _reduceMotion,
              dateTps: _correlationDateTps,
              rTps: _correlationRTps,
              gapTps: _correlationGapTps,
              traceGeometries: _traceGeometries,
              textScaler: _textScaler,
            ),
            child: Column(
              children: List.generate(matches.length, (index) {
                final match = matches[index];
                final isLeft = index.isEven;

                final cardDelay = _reduceMotion
                    ? 0.0
                    : (index * _kCardStaggerMs / 1000.0);
                final scanThreshold = 0.35 + cardDelay;
                final cardAlpha = _reduceMotion
                    ? 1.0
                    : (_sweepCurve.value > scanThreshold
                        ? ((_sweepCurve.value - scanThreshold) /
                                0.15)
                            .clamp(0.0, 1.0)
                        : 0.0);

                return Opacity(
                  opacity: cardAlpha,
                  child: Transform.translate(
                    offset: Offset(
                      0,
                      _reduceMotion ? 0 : (1 - cardAlpha) * 8,
                    ),
                    child: Padding(
                      padding: EdgeInsets.only(
                        top: index == 0 ? 0 : _kCardVerticalGap,
                      ),
                      child: Align(
                        alignment: isLeft
                            ? Alignment.centerLeft
                            : Alignment.centerRight,
                        child: SizedBox(
                          width: cardWidth,
                          child: _buildInterceptEntry(
                              match, index),
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          );
        },
      ),
    );
  }

  // ══════════════════════════════════════════════════════════
  // INTERCEPT LOG ENTRY (Match Card)
  // ══════════════════════════════════════════════════════════

  Widget _buildInterceptEntry(ReceiptMatch match, int index) {
    final seqNum = (index + 2).toString().padLeft(2, '0');
    final waveformSeed = _waveformSeed(match.statementText);

    final animatedSimilarity = _reduceMotion
        ? match.similarity
        : _countUpController.value * match.similarity;
    final percentage =
        (animatedSimilarity * 100).toStringAsFixed(0);

    final barOpacity = match.similarity >= 0.90
        ? 0.35
        : match.similarity >= 0.75
            ? 0.25
            : match.similarity >= 0.60
                ? 0.15
                : 0.08;

    return _PressScaleButton(
      onTap: () {
        HapticUtil.light();
        context.push(
          AppRoutes.statementPath(match.matchStatementId),
        );
      },
      child: Semantics(
        button: true,
        label: 'Intercept $seqNum: '
            '${_fmtDateMY(match.statedAt.toLocal())}, '
            'confidence ${(match.similarity * 100).toStringAsFixed(0)} percent',
        excludeSemantics: true,
        child: CustomPaint(
          foregroundPainter: _SignalBracketPainter(
            opacity: 0.03,
            armLength: 3.5,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: BaselineColors.card,
              border: Border.all(
                color: BaselineColors.borderInactive
                    .atOpacity(_kBorderOpacity),
                width: _kMatchCardBorder,
              ),
              borderRadius:
                  BorderRadius.circular(BaselineRadius.md),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Signal strength bar (top edge).
                Container(
                  height: _kSignalBarWidth,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        BaselineColors.teal
                            .atOpacity(barOpacity),
                        BaselineColors.teal
                            .atOpacity(barOpacity * 0.3),
                        Colors.transparent,
                      ],
                      stops: [
                        0.0,
                        match.similarity.clamp(0.0, 1.0),
                        1.0,
                      ],
                    ),
                    borderRadius: const BorderRadius.only(
                      topLeft:
                          Radius.circular(BaselineRadius.md),
                      topRight:
                          Radius.circular(BaselineRadius.md),
                    ),
                  ),
                ),
                Padding(
                  padding:
                      const EdgeInsets.all(BaselineSpacing.md),
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      // Designation + signal meter.
                      Row(
                        children: [
                          _buildInterceptBadge(
                              seqNum, _kMatchBadgeSize),
                          const SizedBox(
                              width: BaselineSpacing.sm),
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'INTERCEPT #$seqNum',
                                  style: BaselineTypography
                                      .dataSmall
                                      .copyWith(
                                    color: BaselineColors.teal
                                        .atOpacity(0.2),
                                    letterSpacing: 0.8,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                _buildSignalMeter(
                                    match.similarity),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.end,
                            children: [
                              Text(
                                'MATCH',
                                style: BaselineTypography
                                    .dataSmall
                                    .copyWith(
                                  color: BaselineColors.teal
                                      .atOpacity(0.08),
                                  fontSize: 7,
                                ),
                              ),
                              Text(
                                '$percentage%',
                                style: BaselineTypography.data
                                    .copyWith(
                                  color: BaselineColors.teal
                                      .atOpacity(0.5),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: BaselineSpacing.sm),

                      // Mini waveform.
                      SizedBox(
                        height: _kMatchWaveformHeight,
                        width: double.infinity,
                        child: CustomPaint(
                          painter: _WaveformPainter(
                            seed: waveformSeed,
                            drawProgress:
                                _waveformController.value,
                            ambientPhase:
                                _ambientController.value,
                            opacity: 0.08,
                            reduceMotion: _reduceMotion,
                          ),
                        ),
                      ),
                      const SizedBox(height: BaselineSpacing.sm),

                      // Date.
                      Row(
                        children: [
                          Text(
                            _fmtDateMY(
                                match.statedAt.toLocal()),
                            style:
                                BaselineTypography.data.copyWith(
                              color: BaselineColors.teal,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(
                              width: BaselineSpacing.sm),
                          Text(
                            _formatDtg(match.statedAt),
                            style: BaselineTypography.dataSmall
                                .copyWith(
                              color: BaselineColors.teal
                                  .atOpacity(0.08),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: BaselineSpacing.sm),

                      // Text preview.
                      Text(
                        match.statementText,
                        maxLines: _kMatchTextMaxLines,
                        overflow: TextOverflow.ellipsis,
                        style:
                            BaselineTypography.body2.copyWith(
                          color: BaselineColors.textSecondary,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: BaselineSpacing.sm),

                      // Source.
                      SourceBadge(
                        sourceUrl: match.sourceUrl,
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

  // ══════════════════════════════════════════════════════════
  // SIGNAL STRENGTH METER
  // ══════════════════════════════════════════════════════════

  Widget _buildSignalMeter(double similarity) {
    return SizedBox(
      width: _kMeterWidth,
      height: 10,
      child: CustomPaint(
        painter: _SignalMeterPainter(
          similarity: similarity,
          fillProgress: _countUpController.value,
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════
  // INTERCEPT BADGE
  // ══════════════════════════════════════════════════════════

  Widget _buildInterceptBadge(String label, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: BaselineColors.teal.atOpacity(0.2),
          width: 1.5,
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: BaselineTypography.dataSmall.copyWith(
          color: BaselineColors.teal.atOpacity(0.4),
          fontWeight: FontWeight.w700,
          fontSize: size > 26 ? 10 : 8,
          letterSpacing: 0,
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════
  // EMPTY SIGNAL STATE
  // ══════════════════════════════════════════════════════════

  Widget _buildEmptySignal() {
    return CustomPaint(
      foregroundPainter: _SignalBracketPainter(
        opacity: 0.03,
        armLength: 3.5,
      ),
      child: Container(
        padding: const EdgeInsets.all(BaselineSpacing.xl),
        decoration: BoxDecoration(
          color: BaselineColors.card,
          border: Border.all(
            color: BaselineColors.borderInactive.atOpacity(0.2),
            width: 1,
          ),
          borderRadius: BorderRadius.circular(BaselineRadius.md),
        ),
        child: Column(
          children: [
            const EmptyStateWidget(variant: EmptyStateVariant.receipt),
            const SizedBox(height: BaselineSpacing.sm),
            Text(
              'NO MATCHING SIGNALS IN ARCHIVE',
              style: BaselineTypography.dataSmall.copyWith(
                color: BaselineColors.textSecondary
                    .atOpacity(0.3),
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: BaselineSpacing.sm),
            // Flat-line waveform: signal is dead.
            Container(
              height: 1,
              width: 120,
              color: BaselineColors.teal.atOpacity(0.06),
            ),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════
  // FOOTER COUNT
  // ══════════════════════════════════════════════════════════

  Widget _buildFooterCount(ReceiptResponse receipt) {
    final showing = receipt.matches.length;
    final total = receipt.totalMatches ?? showing;
    final hasMore = total > showing;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: BaselineSpacing.lg,
        vertical: BaselineSpacing.md,
      ),
      child: Center(
        child: hasMore
            ? _PressScaleButton(
                scale: 0.95,
                onTap: () {
                  HapticUtil.light();
                  context.push(AppRoutes.paywall);
                },
                child: Semantics(
                  button: true,
                  label: 'See full history. Upgrade required.',
                  excludeSemantics: true,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: BaselineSpacing.xs,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'SIGNALS $showing of $total DETECTED',
                          style:
                              BaselineTypography.data.copyWith(
                            color: BaselineColors.textSecondary,
                          ),
                        ),
                        const SizedBox(
                            width: BaselineSpacing.sm),
                        Text(
                          '\u00b7',
                          style:
                              BaselineTypography.data.copyWith(
                            color: BaselineColors.textSecondary,
                          ),
                        ),
                        const SizedBox(
                            width: BaselineSpacing.sm),
                        Text(
                          'See full history',
                          style:
                              BaselineTypography.data.copyWith(
                            color: BaselineColors.teal,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            : Text(
                'SIGNALS $showing of $total DETECTED',
                style: BaselineTypography.data.copyWith(
                  color: BaselineColors.textSecondary,
                ),
              ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════
  // OBSERVATION CAVEAT
  // ══════════════════════════════════════════════════════════

  Widget _buildObservationCaveat() {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: BaselineSpacing.lg,
      ),
      child: Center(
        child: Text(
          'OBSERVATIONAL ANALYSIS \u00b7 NOT EDITORIAL',
          style: BaselineTypography.dataSmall.copyWith(
            color: BaselineColors.textSecondary.atOpacity(0.15),
            letterSpacing: 1.0,
          ),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════
  // PAGE INDICATOR (C7)
  // ══════════════════════════════════════════════════════════

  Widget _buildPageIndicator() {
    return Center(
      child: ExcludeSemantics(
        child: Text(
          'PAGE 1 OF 1',
          style: BaselineTypography.dataSmall.copyWith(
            color: BaselineColors.teal.atOpacity(0.03),
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════
  // STATION SIGN-OFF
  // ══════════════════════════════════════════════════════════

  Widget _buildStationSignOff() {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: BaselineSpacing.lg,
      ),
      child: Center(
        child: Text(
          '// END INTERCEPT LOG \u00b7 SIG-${_uuid8()}',
          style: BaselineTypography.dataSmall.copyWith(
            color: BaselineColors.teal.atOpacity(0.03),
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// PRESS SCALE BUTTON
// ═══════════════════════════════════════════════════════════

class _PressScaleButton extends StatefulWidget {
  const _PressScaleButton({
    required this.child,
    required this.onTap,
    this.scale = 0.98,
  });

  final Widget child;
  final VoidCallback onTap;
  final double scale;

  @override
  State<_PressScaleButton> createState() => _PressScaleButtonState();
}

class _PressScaleButtonState extends State<_PressScaleButton> {
  bool _pressing = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressing = true),
      onTapUp: (_) {
        setState(() => _pressing = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressing = false),
      behavior: HitTestBehavior.opaque,
      child: AnimatedScale(
        scale: _pressing ? widget.scale : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// INTERCEPT CHROME PAINTER (screen-level)
// ═══════════════════════════════════════════════════════════

/// Screen-level chrome for the SIGINT intercept station.
/// I-44 + R2: Receives ALL pre-computed TextPainters from state layer.
/// I-71: Static paints as constructor-initialized finals.
class _InterceptChromePainter extends CustomPainter {
  _InterceptChromePainter({
    required this.sweepProgress,
    required this.ambientPhase,
    required this.statementId,
    required this.matchCount,
    required this.reduceMotion,
    this.stationTp,
    this.serialTp,
    this.handlingTp,
    this.countTp,
    this.callsignTp,
    this.bandTps = const [],
    this.textScaler = TextScaler.noScaling,
  })  : _noisePaint = Paint()
          ..color = BaselineColors.teal.atOpacity(0.015),
        _scanPaint = Paint()
          ..color = BaselineColors.teal.atOpacity(0.02)
          ..strokeWidth = 0.5,
        _bracketPaint = Paint()
          ..color = BaselineColors.teal.atOpacity(0.06)
          ..strokeWidth = 1
          ..style = PaintingStyle.stroke,
        _crossPaint = Paint()
          ..color = BaselineColors.teal.atOpacity(0.06)
          ..strokeWidth = 0.5,
        _ghostPaint = Paint()
          ..color = BaselineColors.teal.atOpacity(0.015)
          ..strokeWidth = 0.5
          ..style = PaintingStyle.stroke,
        _hairlinePaint = Paint()
          ..color = BaselineColors.teal.atOpacity(0.04)
          ..strokeWidth = 0.5;

  final double sweepProgress;
  final double ambientPhase;
  final String statementId;
  final int matchCount;
  final bool reduceMotion;
  final TextPainter? stationTp;
  final TextPainter? serialTp;
  final TextPainter? handlingTp;
  final TextPainter? countTp;
  final TextPainter? callsignTp;
  final List<TextPainter> bandTps;
  final TextScaler textScaler;

  // I-71: Pre-initialized paints.
  final Paint _noisePaint;
  final Paint _scanPaint;
  final Paint _bracketPaint;
  final Paint _crossPaint;
  final Paint _ghostPaint;
  final Paint _hairlinePaint;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final teal = BaselineColors.teal;

    // 1. Noise floor: deterministic micro-dots.
    final rng = math.Random(statementId.hashCode);
    for (int i = 0; i < 200; i++) {
      canvas.drawCircle(
        Offset(rng.nextDouble() * w, rng.nextDouble() * h),
        0.8,
        _noisePaint,
      );
    }

    // C5: Ambient noise crackle: 3 dots reposition per cycle.
    if (!reduceMotion) {
      final crackleRng = math.Random(
          statementId.hashCode + (ambientPhase * 10).floor());
      for (int i = 0; i < 3; i++) {
        canvas.drawCircle(
          Offset(crackleRng.nextDouble() * w,
              crackleRng.nextDouble() * h),
          0.6,
          Paint()..color = teal.atOpacity(0.025),
        );
      }
    }

    // 2. Horizontal scan lines.
    for (final yFrac in [0.2, 0.4, 0.6, 0.8]) {
      canvas.drawLine(
          Offset(0, h * yFrac), Offset(w, h * yFrac), _scanPaint);
    }

    // 3. Frequency band indicators: right edge (R2: pre-computed TPs).
    final bandStrokePaint = Paint()
      ..color = teal.atOpacity(0.04)
      ..strokeWidth = 0.5
      ..style = PaintingStyle.stroke;
    final bandFracs = [0.2, 0.5, 0.8];
    for (int i = 0; i < bandFracs.length && i < bandTps.length; i++) {
      final y = h * bandFracs[i];

      canvas.drawLine(
          Offset(w - 10, y - 8), Offset(w - 6, y - 8), bandStrokePaint);
      canvas.drawLine(
          Offset(w - 6, y - 8), Offset(w - 6, y + 8), bandStrokePaint);
      canvas.drawLine(
          Offset(w - 10, y + 8), Offset(w - 6, y + 8), bandStrokePaint);

      // R2: Pre-computed, just paint.
      bandTps[i].paint(
        canvas,
        Offset(w - 10 - bandTps[i].width - 2, y - bandTps[i].height / 2),
      );
    }

    // 4. Station designation tab.
    final tabW = 160.0;
    final tabH = 28.0;
    final tabX = (w - tabW) / 2;
    final tabRect = RRect.fromRectAndCorners(
      Rect.fromLTWH(tabX, 0, tabW, tabH),
      bottomLeft: const Radius.circular(4),
      bottomRight: const Radius.circular(4),
    );
    canvas.drawRRect(
        tabRect, Paint()..color = teal.atOpacity(0.03));
    canvas.drawRRect(
      tabRect,
      Paint()
        ..color = teal.atOpacity(0.06)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5,
    );

    // I-44: Pre-computed station TP.
    if (stationTp != null) {
      stationTp!.paint(
        canvas,
        Offset((w - stationTp!.width) / 2,
            (tabH - stationTp!.height) / 2),
      );

      // Classification dot.
      canvas.drawCircle(
        Offset((w - stationTp!.width) / 2 - 6, tabH / 2),
        1.5,
        Paint()
          ..color = BaselineColors.textSecondary.atOpacity(0.3),
      );

      // Active monitoring dot (pulsing).
      if (!reduceMotion) {
        final pulse =
            0.3 + 0.7 * math.sin(ambientPhase * 2 * math.pi).abs();
        canvas.drawCircle(
          Offset((w + stationTp!.width) / 2 + 8, tabH / 2),
          1.5,
          Paint()..color = teal.atOpacity(0.15 * pulse),
        );
      }
    }

    // 5. Signal brackets at corners.
    _drawSignalBracket(canvas, 10, 10, 1, 1, teal);
    _drawSignalBracket(canvas, w - 10, 10, -1, 1, teal);
    _drawSignalBracket(canvas, 10, h - 10, 1, -1, teal);
    _drawSignalBracket(canvas, w - 10, h - 10, -1, -1, teal);

    // 6. Registration crosshairs.
    for (final pt in [
      Offset(10, 10),
      Offset(w - 10, 10),
      Offset(10, h - 10),
      Offset(w - 10, h - 10),
    ]) {
      canvas.drawLine(
          Offset(pt.dx - 3, pt.dy), Offset(pt.dx + 3, pt.dy), _crossPaint);
      canvas.drawLine(
          Offset(pt.dx, pt.dy - 3), Offset(pt.dx, pt.dy + 3), _crossPaint);
    }

    // 7. Classification hairline.
    canvas.drawLine(
        Offset(18, tabH + 4), Offset(w - 18, tabH + 4), _hairlinePaint);

    // 8. Station serial (I-44: pre-computed).
    if (serialTp != null) {
      serialTp!.paint(
          canvas, Offset(w - serialTp!.width - 14, tabH + 8));
    }

    // 9. Handling mark (I-44: pre-computed).
    if (handlingTp != null) {
      handlingTp!.paint(
        canvas,
        Offset((w - handlingTp!.width) / 2, h - 16),
      );
    }

    // C2: Station callsign watermark: left edge, rotated 90° (R2: pre-computed).
    if (callsignTp != null) {
      canvas.save();
      canvas.translate(12, h * 0.5 + callsignTp!.width / 2);
      canvas.rotate(-math.pi / 2);
      callsignTp!.paint(canvas, Offset.zero);
      canvas.restore();
    }

    // 10. Intercept count (I-44: pre-computed).
    if (countTp != null) {
      countTp!.paint(canvas, Offset(14, h - 28));
    }

    // 11. Entry sweep beam (wavy).
    if (sweepProgress > 0 && sweepProgress < 1) {
      final beamY = sweepProgress * h;
      final beamPath = Path();
      beamPath.moveTo(0, beamY);
      for (double x = 0; x <= w; x += 2) {
        final wave = math.sin(x * 0.08) * 1.5;
        beamPath.lineTo(x, beamY + wave);
      }
      canvas.drawPath(
        beamPath,
        Paint()
          ..color = teal.atOpacity(0.12)
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke,
      );
      canvas.drawRect(
        Rect.fromLTWH(0, beamY - 3, w, 6),
        Paint()
          ..color = teal.atOpacity(0.04)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
    }

    // 12. Ambient signal wave: right edge.
    if (!reduceMotion && sweepProgress >= 1.0) {
      final waveY = ambientPhase * h;
      final wavePath = Path();
      for (double dy = -20; dy <= 20; dy += 1) {
        final x = w - 2 + math.sin((waveY + dy) * 0.15) * 3;
        if (dy == -20) {
          wavePath.moveTo(x, waveY + dy);
        } else {
          wavePath.lineTo(x, waveY + dy);
        }
      }
      canvas.drawPath(
        wavePath,
        Paint()
          ..color = teal.atOpacity(0.06)
          ..strokeWidth = 1
          ..style = PaintingStyle.stroke,
      );
    }

    // 13. Waveform watermark: ghost sine.
    final ghostY = h * 0.3;
    final ghostPath = Path();
    for (double x = 0; x <= w; x += 2) {
      final y = ghostY + math.sin(x * 0.02) * 15;
      if (x == 0) {
        ghostPath.moveTo(x, y);
      } else {
        ghostPath.lineTo(x, y);
      }
    }
    canvas.drawPath(ghostPath, _ghostPaint);
  }

  void _drawSignalBracket(
    Canvas canvas, double cx, double cy,
    double hDir, double vDir, Color teal,
  ) {
    canvas.drawLine(
        Offset(cx, cy), Offset(cx + 6 * hDir, cy), _bracketPaint);
    canvas.drawLine(
        Offset(cx, cy), Offset(cx, cy + 6 * vDir), _bracketPaint);

    final notchPath = Path();
    notchPath.moveTo(cx + 2 * hDir, cy + 2 * vDir);
    notchPath.quadraticBezierTo(
      cx + 3 * hDir, cy + 3.5 * vDir,
      cx + 4 * hDir, cy + 2 * vDir,
    );
    canvas.drawPath(
      notchPath,
      Paint()
        ..color = teal.atOpacity(0.04)
        ..strokeWidth = 0.5
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _InterceptChromePainter old) =>
      old.sweepProgress != sweepProgress ||
      old.ambientPhase != ambientPhase;
}

// ═══════════════════════════════════════════════════════════
// WAVEFORM PAINTER
// ═══════════════════════════════════════════════════════════

class _WaveformPainter extends CustomPainter {
  _WaveformPainter({
    required this.seed,
    required this.drawProgress,
    required this.ambientPhase,
    required this.opacity,
    required this.reduceMotion,
  })  : _refPaint = Paint()
          ..color = BaselineColors.teal.atOpacity(opacity * 0.3)
          ..strokeWidth = 0.5;

  final List<double> seed;
  final double drawProgress;
  final double ambientPhase;
  final double opacity;
  final bool reduceMotion;
  final Paint _refPaint;

  @override
  void paint(Canvas canvas, Size size) {
    final teal = BaselineColors.teal;
    final w = size.width;
    final h = size.height;
    final midY = h / 2;
    final amplitude = h * 0.35;
    final progress = reduceMotion ? 1.0 : drawProgress;

    // Zero-crossing reference line.
    canvas.drawLine(Offset(0, midY), Offset(w, midY), _refPaint);

    if (progress <= 0) return;

    final visibleWidth = w * progress;
    final breathe = reduceMotion
        ? 1.0
        : (1.0 + 0.02 * math.sin(ambientPhase * 2 * math.pi));

    final path = Path();
    bool started = false;

    for (double x = 0; x <= visibleWidth; x += 1.5) {
      final norm = x / w;
      final y = midY +
          amplitude *
              breathe *
              (math.sin(norm * seed[0] * 2 * math.pi) * 0.6 +
                  math.sin(norm * seed[1] * 2 * math.pi) * 0.3 +
                  math.sin(norm * seed[2] * 2 * math.pi) * 0.1);

      if (!started) {
        path.moveTo(x, y);
        started = true;
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = teal.atOpacity(opacity)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );

    canvas.drawPath(
      path,
      Paint()
        ..color = teal.atOpacity(opacity * 0.3)
        ..strokeWidth = 4
        ..style = PaintingStyle.stroke
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter old) =>
      old.drawProgress != drawProgress ||
      old.ambientPhase != ambientPhase;
}

// ═══════════════════════════════════════════════════════════
// WAVEFORM ACCENT PAINTER (header line)
// ═══════════════════════════════════════════════════════════

class _WaveformAccentPainter extends CustomPainter {
  const _WaveformAccentPainter({
    required this.drawProgress,
    required this.ambientPhase,
    required this.reduceMotion,
  });

  final double drawProgress;
  final double ambientPhase;
  final bool reduceMotion;

  @override
  void paint(Canvas canvas, Size size) {
    final teal = BaselineColors.teal;
    final w = size.width;
    final midY = size.height / 2;
    final progress = reduceMotion ? 1.0 : drawProgress;
    final visibleWidth = w * progress;
    final phase = reduceMotion ? 0.0 : ambientPhase * 2 * math.pi;

    final path = Path();
    for (double x = 0; x <= visibleWidth; x += 1) {
      final y = midY + math.sin(x * 0.05 + phase) * 3;
      if (x == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = teal.atOpacity(0.25)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );

    canvas.drawPath(
      path,
      Paint()
        ..color = teal.atOpacity(0.08)
        ..strokeWidth = 6
        ..style = PaintingStyle.stroke
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
  }

  @override
  bool shouldRepaint(covariant _WaveformAccentPainter old) =>
      old.drawProgress != drawProgress ||
      old.ambientPhase != ambientPhase;
}

// ═══════════════════════════════════════════════════════════
// CORRELATION TRACE PAINTER
// ═══════════════════════════════════════════════════════════

class _CorrelationTracePainter extends CustomPainter {
  _CorrelationTracePainter({
    required this.matchCount,
    required this.cardHeight,
    required this.availableWidth,
    required this.cardWidth,
    required this.similarities,
    required this.matchDates,
    required this.drawProgress,
    required this.ambientPhase,
    required this.reduceMotion,
    this.dateTps = const [],
    this.rTps = const [],
    this.gapTps = const [],
    this.traceGeometries = const [],
    this.textScaler = TextScaler.noScaling,
  })  : _spinePaint = Paint()
          ..color = BaselineColors.teal.atOpacity(0.06)
          ..strokeWidth = _kSpineWidth
          ..strokeCap = StrokeCap.round,
        _routingPaint = Paint()
          ..color = BaselineColors.teal.atOpacity(0.02)
          ..strokeWidth = 0.5;

  final int matchCount;
  final double cardHeight;
  final double availableWidth;
  final double cardWidth;
  final List<double> similarities;
  final List<DateTime> matchDates;
  final double drawProgress;
  final double ambientPhase;
  final bool reduceMotion;
  final List<TextPainter> dateTps;
  final List<TextPainter> rTps;
  final List<TextPainter> gapTps;
  final List<List<Offset>> traceGeometries;
  final TextScaler textScaler;
  final Paint _spinePaint;
  final Paint _routingPaint;

  @override
  void paint(Canvas canvas, Size size) {
    if (matchCount < 1) return;

    final teal = BaselineColors.teal;
    final progress = reduceMotion ? 1.0 : drawProgress;
    final spineX = availableWidth / 2;

    // Frequency axis spine.
    if (matchCount > 1) {
      final spineTop = cardHeight / 2;
      final spineBottom =
          (matchCount - 1) * (cardHeight + _kCardVerticalGap) +
              cardHeight / 2;

      canvas.drawLine(
        Offset(spineX, spineTop),
        Offset(spineX, spineBottom),
        _spinePaint,
      );

      // R2: Date labels + r= coefficients (pre-computed TPs, just paint).
      for (int i = 0; i < matchCount; i++) {
        final cardY = i * (cardHeight + _kCardVerticalGap);
        final centerY = cardY + cardHeight / 2;

        // Date label (rotated).
        if (i < dateTps.length) {
          canvas.save();
          canvas.translate(spineX + 8, centerY + dateTps[i].width / 2);
          canvas.rotate(-math.pi / 2);
          dateTps[i].paint(canvas, Offset.zero);
          canvas.restore();
        }

        // Correlation coefficient.
        if (i < rTps.length) {
          rTps[i].paint(
            canvas,
            Offset(spineX - 8 - rTps[i].width, centerY - rTps[i].height / 2),
          );
        }

        // C8: Frequency drift sine between distant matches (>180 days).
        if (i > 0 && i < matchDates.length) {
          final prevDate = matchDates[i - 1];
          final currDate = matchDates[i];
          final gap = currDate.difference(prevDate).inDays.abs();
          if (gap > 180) {
            final prevY = (i - 1) * (cardHeight + _kCardVerticalGap) +
                cardHeight / 2;
            final midGapY = (prevY + centerY) / 2;
            final driftPath = Path();
            for (double dy = prevY; dy <= centerY; dy += 2) {
              final dx = math.sin((dy - prevY) * 0.08) * 4;
              if (dy == prevY) {
                driftPath.moveTo(spineX + dx, dy);
              } else {
                driftPath.lineTo(spineX + dx, dy);
              }
            }
            canvas.drawPath(
              driftPath,
              Paint()
                ..color = teal.atOpacity(0.04)
                ..strokeWidth = 0.5
                ..style = PaintingStyle.stroke,
            );

            // R2: Pre-computed gap label.
            final gapIndex = i - 1;
            if (gapIndex < gapTps.length) {
              final gapTp = gapTps[gapIndex];
              if (gapTp.text?.toPlainText().isNotEmpty == true) {
                gapTp.paint(
                  canvas,
                  Offset(
                    spineX - gapTp.width / 2,
                    midGapY - gapTp.height / 2,
                  ),
                );
              }
            }
          }
        }
      }
    }

    // Junction nodes.
    for (int i = 0; i < matchCount; i++) {
      final cardY = i * (cardHeight + _kCardVerticalGap);
      final centerY = cardY + cardHeight / 2;

      canvas.drawCircle(
        Offset(spineX, centerY),
        _kJunctionOuter,
        Paint()
          ..color = teal.atOpacity(0.15)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
      canvas.drawCircle(
        Offset(spineX, centerY),
        _kJunctionInner,
        Paint()..color = teal.atOpacity(0.3),
      );

      if (progress > (i / matchCount.toDouble()).clamp(0.0, 0.9)) {
        canvas.drawCircle(
          Offset(spineX, centerY),
          8,
          Paint()
            ..color = teal.atOpacity(0.06)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
        );
      }

      final isLeft = i.isEven;
      final cardEdgeX = isLeft
          ? cardWidth + 4
          : availableWidth - cardWidth - 4;
      canvas.drawLine(
        Offset(spineX, centerY),
        Offset(cardEdgeX, centerY),
        _routingPaint,
      );
    }

    // R3: Sinusoidal correlation traces from pre-computed geometry.
    if (matchCount < 2) return;

    for (int i = 0; i < matchCount - 1 && i < traceGeometries.length; i++) {
      final points = traceGeometries[i];
      if (points.isEmpty) continue;

      final similarity =
          i + 1 < similarities.length ? similarities[i + 1] : 0.5;
      double traceOpacity;

      if (similarity >= 0.90) {
        traceOpacity = 0.45;
      } else if (similarity >= 0.75) {
        traceOpacity = 0.30;
      } else if (similarity >= 0.60) {
        traceOpacity = 0.18;
      } else {
        traceOpacity = 0.10;
      }

      // R3: Draw from pre-computed offsets, clipped by progress.
      final visibleCount = (points.length * progress).round();
      if (visibleCount < 2) continue;

      final modPath = Path()..moveTo(points[0].dx, points[0].dy);
      for (int p = 1; p < visibleCount; p++) {
        modPath.lineTo(points[p].dx, points[p].dy);
      }

      canvas.drawPath(
        modPath,
        Paint()
          ..color = teal.atOpacity(traceOpacity)
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round,
      );

      canvas.drawPath(
        modPath,
        Paint()
          ..color = teal.atOpacity(traceOpacity * 0.25)
          ..strokeWidth = 5
          ..style = PaintingStyle.stroke
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CorrelationTracePainter old) =>
      old.matchCount != matchCount ||
      old.cardHeight != cardHeight ||
      old.availableWidth != availableWidth ||
      old.cardWidth != cardWidth ||
      old.similarities != similarities ||
      old.drawProgress != drawProgress;
}

// ═══════════════════════════════════════════════════════════
// SIGNAL METER PAINTER
// ═══════════════════════════════════════════════════════════

class _SignalMeterPainter extends CustomPainter {
  _SignalMeterPainter({
    required this.similarity,
    required this.fillProgress,
  })  : _trackPaint = Paint()
          ..color = BaselineColors.teal.atOpacity(0.06),
        _fillPaint = Paint()
          ..color = BaselineColors.teal.atOpacity(0.25),
        _tickPaint = Paint()
          ..color = BaselineColors.teal.atOpacity(0.15)
          ..strokeWidth = 0.5;

  final double similarity;
  final double fillProgress;
  final Paint _trackPaint;
  final Paint _fillPaint;
  final Paint _tickPaint;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final barY = size.height / 2;
    final barH = _kMeterHeight;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
            center: Offset(w / 2, barY), width: w, height: barH),
        const Radius.circular(2),
      ),
      _trackPaint,
    );

    final fillW = w * similarity * fillProgress;
    if (fillW > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, barY - barH / 2, fillW, barH),
          const Radius.circular(2),
        ),
        _fillPaint,
      );
    }

    for (final thresh in [0.60, 0.75, 0.90]) {
      final x = w * thresh;
      canvas.drawLine(
          Offset(x, barY - barH), Offset(x, barY + barH), _tickPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _SignalMeterPainter old) =>
      old.similarity != similarity ||
      old.fillProgress != fillProgress;
}

// ═══════════════════════════════════════════════════════════
// SIGNAL BRACKET PAINTER (card-level chrome)
// ═══════════════════════════════════════════════════════════

class _SignalBracketPainter extends CustomPainter {
  _SignalBracketPainter({
    required this.opacity,
    required this.armLength,
  })  : _armPaint = Paint()
          ..color = BaselineColors.teal.atOpacity(opacity)
          ..strokeWidth = 0.8
          ..style = PaintingStyle.stroke;

  final double opacity;
  final double armLength;
  final Paint _armPaint;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final teal = BaselineColors.teal;

    for (final corner in [
      [0.0, 0.0, 1.0, 1.0],
      [w, 0.0, -1.0, 1.0],
      [0.0, h, 1.0, -1.0],
      [w, h, -1.0, -1.0],
    ]) {
      final cx = corner[0];
      final cy = corner[1];
      final hd = corner[2];
      final vd = corner[3];

      canvas.drawLine(
          Offset(cx, cy), Offset(cx + armLength * hd, cy), _armPaint);
      canvas.drawLine(
          Offset(cx, cy), Offset(cx, cy + armLength * vd), _armPaint);

      final notch = Path();
      notch.moveTo(cx + 1.5 * hd, cy + 1.5 * vd);
      notch.quadraticBezierTo(
        cx + 2.5 * hd, cy + 3 * vd,
        cx + 3.5 * hd, cy + 1.5 * vd,
      );
      canvas.drawPath(
        notch,
        Paint()
          ..color = teal.atOpacity(opacity * 0.6)
          ..strokeWidth = 0.5
          ..style = PaintingStyle.stroke,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SignalBracketPainter old) =>
      old.opacity != opacity || old.armLength != armLength;
}

// ═══════════════════════════════════════════════════════════
// TAPE REEL DIVIDER PAINTER (C3: sprocket holes)
// ═══════════════════════════════════════════════════════════

class _TapeReelDividerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final teal = BaselineColors.teal;
    final paint = Paint()
      ..color = teal.atOpacity(0.05)
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round;

    double x = 0;
    bool isLong = true;
    while (x < size.width) {
      final dashLen = isLong ? 12.0 : 4.0;
      final gap = isLong ? 4.0 : 6.0;
      canvas.drawLine(
        Offset(x, size.height / 2),
        Offset((x + dashLen).clamp(0, size.width), size.height / 2),
        paint,
      );
      x += dashLen + gap;
      isLong = !isLong;
    }

    // C3: Sprocket holes at each end.
    final holePaint = Paint()..color = teal.atOpacity(0.04);
    for (final hx in [2.0, 6.0, 10.0]) {
      canvas.drawCircle(Offset(hx, size.height / 2), 1.0, holePaint);
      canvas.drawCircle(
          Offset(size.width - hx, size.height / 2), 1.0, holePaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ═══════════════════════════════════════════════════════════
// WAVEFORM PREFIX PAINTER (section label icon)
// ═══════════════════════════════════════════════════════════

class _WaveformPrefixPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    final midY = size.height / 2;

    for (double x = 0; x <= size.width; x += 1) {
      final y = midY + math.sin(x * 0.9) * 3;
      if (x == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = BaselineColors.teal.atOpacity(0.15)
        ..strokeWidth = 1
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ═══════════════════════════════════════════════════════════
// DEAD CHANNEL PAINTER (C6: error state background)
// ═══════════════════════════════════════════════════════════

class _DeadChannelPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = BaselineColors.teal.atOpacity(0.03)
      ..strokeWidth = 0.3;

    // 3 horizontal noise lines.
    for (final yFrac in [0.3, 0.5, 0.7]) {
      canvas.drawLine(
        Offset(0, size.height * yFrac),
        Offset(size.width, size.height * yFrac),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
