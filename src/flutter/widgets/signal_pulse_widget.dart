/// FE-3: Signal Pulse™ Widget
///
/// Ambient animated teal ring system that wraps figure avatars.
/// Pulse rhythm is driven by rhetorical activity level: faster
/// pulse = more active speaker. Dual staggered rings create
/// continuous rhythm. Core tier (free for all users).
///
/// Three operational modes:
///   Dormant (activity <= 0.05): Subtle base ring breathing
///   Active (0.05 to 0.9): Dual staggered expanding pulses
///   Peak (>0.9): Triple cascade + outer glow + interior fill
///
/// Two chrome tiers:
///   Compact (< 80px): Cardinal ticks + inner hairline.
///     Cheap to paint, safe in scroll lists.
///   Hero (>= 80px): Full classified targeting system.
///     Radar sweep, phosphor trail, sector crosshair, activity
///     arc, reticle corners, sequential dot cascade, orbital
///     satellite, signal pips, heartbeat trace, scope lens,
///     TM branding, DTG stamp, acquisition entrance.
///
/// Automatically pauses animation when offscreen via TickerMode,
/// and respects platform reduce-motion preferences.
///
/// Path: lib/widgets/signal_pulse_widget.dart
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:baseline_app/config/theme.dart';

// ═══════════════════════════════════════════════════════════
// CONSTANTS
// ═══════════════════════════════════════════════════════════

/// Maximum outward expansion of each pulse ring (pixels beyond base ring).
const double _kMaxPulseExpansion = 8.0;

/// Minimum avatar diameter.
const double _kMinDiameter = 16.0;

/// Diameter threshold for hero-scale chrome.
const double _kHeroThreshold = 80.0;

/// Minimum activity level that triggers active pulse mode.
const double _kDormantThreshold = 0.05;

/// Activity level that activates the third cascade ring + glow.
const double _kPeakThreshold = 0.90;

// ── Pulse ring opacity ──
const double _kPulseOpacityPeak = 0.6;
const double _kSecondaryPulseMultiplier = 0.7;
const double _kTertiaryPulseMultiplier = 0.45;

// ── Glow ──
const double _kGlowOpacity = 0.18;
const double _kGlowBlurSigma = 5.0;
const double _kGlowStrokeMultiplier = 4.0;

// ── Dormant breathing ──
const Duration _kBreathingDuration = Duration(milliseconds: 4000);
const double _kBreathingOpacityMin = 0.55;
const double _kBreathingOpacityMax = 1.0;

// ── Activity transition ──
const Duration _kActivityTransitionDuration = Duration(milliseconds: 800);

// ── Reduce-motion fallback ──
const Duration _kReducedMotionDuration = Duration(milliseconds: 3500);
const double _kReducedMotionOpacityMin = 0.65;
const double _kReducedMotionOpacityMax = 1.0;

// ── Phase offsets for staggered rings ──
const double _kRing2PhaseOffset = 0.5;
const double _kRing3PhaseOffset = 0.33;

// ── Stroke tapering ──
const double _kStrokeTaperStart = 1.2;
const double _kStrokeTaperEnd = 0.3;

/// Minimum opacity before a pulse ring is skipped entirely.
const double _kMinVisibleOpacity = 0.02;

// ── Compact chrome ──
const double _kCardinalTickLength = 2.0;
const double _kInnerHairlineInset = 1.0;

// ── Hero chrome ──
const double _kReticleArmLength = 6.0;
const double _kRegistrationDotRadius = 1.0;
const double _kHashmarkLength = 3.0;
const double _kMicroTextSize = 7.0;
const double _kSweepLineWidth = 0.8;
const double _kPhosphorArcDegrees = 20.0;
const double _kSectorLineWidth = 0.5;
const double _kActivityArcWidth = 3.0;
const double _kOrbitalDotRadius = 1.0;
const double _kOrbitalSpeedRatio = 0.3;
const double _kScopeLensOpacity = 0.02;
const double _kHeartbeatAmplitude = 3.0;
const int _kHeartbeatPoints = 8;
const double _kSignalPipWidth = 2.0;
const double _kSignalPipMaxHeight = 6.0;
const int _kSignalPipCount = 5;
const double _kInstrumentGapDegrees = 2.0;
const double _kAcquisitionCrosshairLength = 12.0;

// ── Peak ──
const double _kPeakFillOpacity = 0.03;
const double _kBurstOpacityMultiplier = 1.5;
const Duration _kBurstDuration = Duration(milliseconds: 200);

// ── Hero entrance ──
const Duration _kAcquisitionDuration = Duration(milliseconds: 500);
const double _kAcquisitionScaleStart = 1.08;

/// Maps activity level to pulse cycle duration.
Duration _pulseDuration(double activity) {
  if (activity <= _kDormantThreshold) return _kBreathingDuration;
  final t = activity.clamp(0.0, 1.0);
  final ms = (2800 * math.pow(0.2, t) + 500).round().clamp(500, 3000);
  return Duration(milliseconds: ms);
}

// ═══════════════════════════════════════════════════════════
// CHROME DETAIL ENUM
// ═══════════════════════════════════════════════════════════

/// Determines which chrome layers the painter draws.
enum _ChromeDetail {
  /// Feed/list avatars (< 80px): cardinal ticks + inner hairline.
  compact,

  /// Hero avatars (>= 80px): full TM targeting system.
  hero;

  factory _ChromeDetail.fromDiameter(double diameter) {
    return diameter >= _kHeroThreshold ? hero : compact;
  }
}

// ═══════════════════════════════════════════════════════════
// SIGNAL PULSE WIDGET
// ═══════════════════════════════════════════════════════════

class SignalPulseWidget extends StatefulWidget {
  /// Full manual constructor.
  const SignalPulseWidget({
    super.key,
    required this.diameter,
    required this.child,
    this.activityLevel = 0.0,
    this.ringWidth = 2.0,
    this.enabled = true,
    this.showBaseRing = true,
  }) : assert(diameter >= _kMinDiameter,
            'SignalPulseWidget: diameter must be >= $_kMinDiameter'),
       assert(
         activityLevel >= 0.0 && activityLevel <= 1.0,
         'SignalPulseWidget: activityLevel must be 0.0 to 1.0',
       ),
       assert(ringWidth > 0, 'SignalPulseWidget: ringWidth must be positive');

  /// Feed card avatar (44px diameter, 2px ring).
  const SignalPulseWidget.feedCard({
    super.key,
    required this.child,
    this.activityLevel = 0.0,
    this.enabled = true,
  }) : diameter = 44.0,
       ringWidth = 2.0,
       showBaseRing = true;

  /// Figure profile hero avatar (120px diameter, 3px ring).
  const SignalPulseWidget.profileHero({
    super.key,
    required this.child,
    this.activityLevel = 0.0,
    this.enabled = true,
  }) : diameter = 120.0,
       ringWidth = 3.0,
       showBaseRing = true;

  /// List row avatar (40px diameter, 2px ring).
  const SignalPulseWidget.listRow({
    super.key,
    required this.child,
    this.activityLevel = 0.0,
    this.enabled = true,
  }) : diameter = 40.0,
       ringWidth = 2.0,
       showBaseRing = true;

  final double diameter;
  final Widget child;
  final double activityLevel;
  final double ringWidth;
  final bool enabled;
  final bool showBaseRing;

  @override
  State<SignalPulseWidget> createState() => _SignalPulseWidgetState();
}

class _SignalPulseWidgetState extends State<SignalPulseWidget>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;

  /// Hero entrance controller. Only created at hero size.
  AnimationController? _heroEntranceController;
  CurvedAnimation? _heroEntranceCurve;

  bool _reduceMotion = false;
  bool _tickerEnabled = true;
  late final _ChromeDetail _chromeDetail;
  bool _wasPeak = false;
  double _burstProgress = 0.0;
  final List<Timer> _pendingTimers = [];

  /// Cached DTG string for paint. Updated on activity change, not per frame.
  String _cachedDtg = '';
  String _cachedStatusLabel = 'IDLE';

  // ── Lifecycle ──────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _wasPeak = widget.activityLevel >= _kPeakThreshold;
    _chromeDetail = _ChromeDetail.fromDiameter(widget.diameter);
    _refreshDtg(widget.activityLevel);

    _pulseController = AnimationController(
      vsync: this,
      duration: _pulseDuration(widget.activityLevel),
    );

    // Hero acquisition entrance: one-shot scale + crosshair.
    if (_chromeDetail == _ChromeDetail.hero) {
      _heroEntranceController = AnimationController(
        vsync: this,
        duration: _kAcquisitionDuration,
      );
      _heroEntranceCurve = CurvedAnimation(
        parent: _heroEntranceController!,
        curve: Curves.easeOutBack,
      );
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final wasReduceMotion = _reduceMotion;
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    _tickerEnabled = TickerMode.valuesOf(context).enabled;

    // I-9: Mid-flight reduceMotion snap.
    if (_reduceMotion && !wasReduceMotion && _pulseController.isAnimating) {
      // Cancel pending burst timers (I-11).
      for (final timer in _pendingTimers) {
        timer.cancel();
      }
      _pendingTimers.clear();
      _burstProgress = 0.0;

      _pulseController.stop();
      _pulseController.value = 0.0;
    }

    _syncController();

    // Trigger hero entrance after first frame.
    if (_heroEntranceController != null &&
        !_heroEntranceController!.isCompleted &&
        !_heroEntranceController!.isAnimating &&
        !_reduceMotion) {
      _heroEntranceController!.forward();
    }
  }

  @override
  void didUpdateWidget(covariant SignalPulseWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activityLevel != widget.activityLevel ||
        oldWidget.enabled != widget.enabled) {
      _syncController();
    }
  }

  @override
  void dispose() {
    for (final timer in _pendingTimers) {
      timer.cancel();
    }
    _pendingTimers.clear();

    // I-15: CurvedAnimation before parent controller.
    _heroEntranceCurve?.dispose();
    _heroEntranceController?.stop();
    _heroEntranceController?.dispose();

    _pulseController.stop();
    _pulseController.dispose();
    super.dispose();
  }

  // ── DTG Cache ──────────────────────────────────────────

  void _refreshDtg(double activity) {
    final now = DateTime.now().toUtc();
    _cachedDtg = '${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}Z';
    _cachedStatusLabel = activity > _kPeakThreshold
        ? 'PEAK'
        : activity > _kDormantThreshold
            ? 'ACTIVE'
            : 'IDLE';
  }

  // ── Controller Sync ────────────────────────────────────

  void _syncController() {
    if (!widget.enabled || !_tickerEnabled) {
      _pulseController.stop();
      _pulseController.value = 0.0;
      return;
    }

    if (_reduceMotion) {
      _pulseController.duration = _kReducedMotionDuration;
      if (!_pulseController.isAnimating) _pulseController.repeat();
      return;
    }

    if (!_pulseController.isAnimating) _pulseController.repeat();
  }

  // ── Peak Burst ─────────────────────────────────────────

  void _checkPeakBurst(double smoothActivity) {
    final isPeak = smoothActivity >= _kPeakThreshold;
    if (isPeak && !_wasPeak && !_reduceMotion) {
      _burstProgress = 1.0;
      final timer = Timer(_kBurstDuration, () {
        if (mounted) setState(() => _burstProgress = 0.0);
      });
      _pendingTimers.add(timer);
    }
    _wasPeak = isPeak;
  }

  // ── Build ──────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final totalDiameter = widget.diameter + _kMaxPulseExpansion * 2;
    final textScaler = MediaQuery.textScalerOf(context);

    // Hero entrance scale wrapper.
    Widget buildPaintStack(double smoothActivity, Widget? child) {
      return CustomPaint(
        painter: _SignalPulsePainter(
          progress: _pulseController.value,
          activityLevel: smoothActivity,
          ringWidth: widget.ringWidth,
          avatarDiameter: widget.diameter,
          isDormant: smoothActivity <= _kDormantThreshold,
          isPeak: smoothActivity >= _kPeakThreshold,
          reduceMotion: _reduceMotion,
          showBaseRing: widget.showBaseRing,
          enabled: widget.enabled && _tickerEnabled,
          chromeDetail: _chromeDetail,
          burstProgress: _burstProgress,
          entranceProgress: _heroEntranceCurve?.value ?? 1.0,
          textScaler: textScaler,
          cachedDtg: _cachedDtg,
          cachedStatusLabel: _cachedStatusLabel,
        ),
        child: Center(child: child),
      );
    }

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: widget.activityLevel),
      duration: _kActivityTransitionDuration,
      curve: Curves.easeInOut,
      builder: (context, smoothActivity, child) {
        _checkPeakBurst(smoothActivity);
        _refreshDtg(smoothActivity);

        final targetDuration = _pulseDuration(smoothActivity);
        if (_pulseController.duration != targetDuration && !_reduceMotion) {
          _pulseController.duration = targetDuration;
        }

        Widget paintLayer;

        // If hero, merge both animations into one builder.
        if (_heroEntranceController != null) {
          paintLayer = AnimatedBuilder(
            animation: Listenable.merge([
              _pulseController,
              _heroEntranceController!,
            ]),
            builder: (context, child) {
              // Acquisition scale: starts at 1.08, settles to 1.0.
              final entranceT = _heroEntranceCurve?.value ?? 1.0;
              final scale = _reduceMotion
                  ? 1.0
                  : _kAcquisitionScaleStart +
                      (1.0 - _kAcquisitionScaleStart) * entranceT;

              return Transform.scale(
                scale: scale,
                child: buildPaintStack(smoothActivity, child),
              );
            },
            child: child,
          );
        } else {
          paintLayer = AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) =>
                buildPaintStack(smoothActivity, child),
            child: child,
          );
        }

        return Semantics(
          label: _semanticLabel(smoothActivity),
          excludeSemantics: true,
          child: SizedBox(
            width: totalDiameter,
            height: totalDiameter,
            child: RepaintBoundary(child: paintLayer),
          ),
        );
      },
      child: SizedBox(
        width: widget.diameter,
        height: widget.diameter,
        child: widget.child,
      ),
    );
  }

  String _semanticLabel(double activity) {
    if (activity <= _kDormantThreshold) return 'No recent activity';
    if (activity < 0.3) return 'Low recent activity';
    if (activity < 0.7) return 'Moderate recent activity';
    if (activity < _kPeakThreshold) return 'High recent activity';
    return 'Peak recent activity';
  }
}

// ═══════════════════════════════════════════════════════════
// CUSTOM PAINTER
// ═══════════════════════════════════════════════════════════

class _SignalPulsePainter extends CustomPainter {
  _SignalPulsePainter({
    required this.progress,
    required this.activityLevel,
    required this.ringWidth,
    required this.avatarDiameter,
    required this.isDormant,
    required this.isPeak,
    required this.reduceMotion,
    required this.showBaseRing,
    required this.enabled,
    required this.chromeDetail,
    required this.burstProgress,
    required this.entranceProgress,
    required this.textScaler,
    required this.cachedDtg,
    required this.cachedStatusLabel,
  });

  final double progress;
  final double activityLevel;
  final double ringWidth;
  final double avatarDiameter;
  final bool isDormant;
  final bool isPeak;
  final bool reduceMotion;
  final bool showBaseRing;
  final bool enabled;
  final _ChromeDetail chromeDetail;
  final double burstProgress;
  final double entranceProgress;
  final TextScaler textScaler;
  final String cachedDtg;
  final String cachedStatusLabel;

  // ── Reusable Paint objects (avoid 21+ allocations per frame) ──
  static final Paint _strokePaint = Paint()..style = PaintingStyle.stroke;
  static final Paint _fillPaint = Paint();

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final baseRadius = avatarDiameter / 2;
    final isHero = chromeDetail == _ChromeDetail.hero;

    // ── Layer 0: Scope lens gradient (hero, always on) ──
    if (isHero) {
      _paintScopeLens(canvas, center, baseRadius);
    }

    // ── Layer 1: Peak interior radial gradient ──
    if (isPeak && enabled && !reduceMotion) {
      _paintPeakFill(canvas, center, baseRadius);
    }

    // ── Layer 2: Hero sector crosshair ──
    if (isHero) {
      _paintSectorCrosshair(canvas, center, baseRadius);
    }

    // ── Layer 3: Hero heartbeat trace ──
    if (isHero && enabled) {
      _paintHeartbeatTrace(canvas, center, baseRadius);
    }

    // ── Layer 4: Inner concentric hairline ──
    _paintInnerHairline(canvas, center, baseRadius);

    // ── Layer 5: Base ring ──
    if (showBaseRing) {
      if (isHero) {
        _paintBaseRingWithGap(canvas, center, baseRadius);
      } else {
        _paintBaseRing(canvas, center, baseRadius);
      }
    }

    // ── Layer 6: Cardinal tick marks ──
    _paintCardinalTicks(canvas, center, baseRadius);

    if (!enabled) {
      // Still paint static hero chrome when disabled.
      if (isHero) _paintStaticHeroChrome(canvas, center, baseRadius, size);
      return;
    }

    if (reduceMotion) {
      if (isHero) _paintStaticHeroChrome(canvas, center, baseRadius, size);
      return;
    }

    if (isDormant) {
      if (isHero) {
        _paintHeroAnimatedChrome(canvas, center, baseRadius, size);
      }
      return;
    }

    // ── Layer 7: Primary pulse ring ──
    _paintPulseRing(
      canvas, center, baseRadius,
      progress, _kPulseOpacityPeak,
    );

    // ── Layer 8: Secondary pulse ring (50% offset) ──
    _paintPulseRing(
      canvas, center, baseRadius,
      (progress + _kRing2PhaseOffset) % 1.0,
      _kPulseOpacityPeak * _kSecondaryPulseMultiplier,
    );

    // ── Layer 9: Tertiary pulse ring (peak only) ──
    if (isPeak) {
      _paintPulseRing(
        canvas, center, baseRadius,
        (progress + _kRing3PhaseOffset) % 1.0,
        _kPulseOpacityPeak * _kTertiaryPulseMultiplier,
      );
    }

    // ── Layer 10: Peak entry burst ──
    if (burstProgress > 0.0) {
      _paintBurstRing(canvas, center, baseRadius);
    }

    // ── Layer 11: Outer glow (peak only) ──
    if (isPeak) {
      _paintGlow(canvas, center, baseRadius);
    }

    // ── Layer 12: Hero animated chrome ──
    if (isHero) {
      _paintHeroAnimatedChrome(canvas, center, baseRadius, size);
    }
  }

  // ═════════════════════════════════════════════════════════
  // CORE RING PAINTING
  // ═════════════════════════════════════════════════════════

  void _paintInnerHairline(Canvas canvas, Offset center, double baseRadius) {
    final innerRadius = baseRadius - _kInnerHairlineInset;
    if (innerRadius <= 0) return;
    canvas.drawCircle(
      center,
      innerRadius,
      _strokePaint
        ..strokeWidth = 0.5
        ..color = BaselineColors.teal.atOpacity(0.08),
    );
  }

  double get _baseRingOpacity {
    if (reduceMotion) {
      final wave = (math.sin(progress * 2 * math.pi) + 1) / 2;
      return _kReducedMotionOpacityMin +
          wave * (_kReducedMotionOpacityMax - _kReducedMotionOpacityMin);
    }
    if (isDormant && enabled) {
      final wave = (math.sin(progress * 2 * math.pi) + 1) / 2;
      return _kBreathingOpacityMin +
          wave * (_kBreathingOpacityMax - _kBreathingOpacityMin);
    }
    return 1.0;
  }

  void _paintBaseRing(Canvas canvas, Offset center, double baseRadius) {
    canvas.drawCircle(
      center,
      baseRadius + ringWidth / 2,
      _strokePaint
        ..strokeWidth = ringWidth
        ..strokeCap = StrokeCap.butt
        ..maskFilter = null
        ..color = BaselineColors.teal.atOpacity(_baseRingOpacity),
    );
  }

  /// Hero base ring with 2-degree instrument gap at 12 o'clock.
  void _paintBaseRingWithGap(
    Canvas canvas,
    Offset center,
    double baseRadius,
  ) {
    final opacity = _baseRingOpacity;
    final gapRad = _kInstrumentGapDegrees * math.pi / 180;
    // Start just past the gap (clockwise from 12 o'clock).
    // In Flutter canvas, 0 radians = 3 o'clock. 12 o'clock = -pi/2.
    final startAngle = -math.pi / 2 + gapRad / 2;
    final sweepAngle = 2 * math.pi - gapRad;
    final radius = baseRadius + ringWidth / 2;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      _strokePaint
        ..strokeWidth = ringWidth
        ..strokeCap = StrokeCap.round
        ..maskFilter = null
        ..color = BaselineColors.teal.atOpacity(opacity),
    );
  }

  void _paintCardinalTicks(
    Canvas canvas,
    Offset center,
    double baseRadius,
  ) {
    final tickRadius = baseRadius + ringWidth;
    _strokePaint
      ..strokeWidth = 0.8
      ..strokeCap = StrokeCap.round
      ..maskFilter = null
      ..color = BaselineColors.teal.atOpacity(0.12);
    final paint = _strokePaint;

    for (var i = 0; i < 4; i++) {
      final angle = i * math.pi / 2;
      final cos = math.cos(angle);
      final sin = math.sin(angle);
      canvas.drawLine(
        Offset(center.dx + tickRadius * sin, center.dy - tickRadius * cos),
        Offset(
          center.dx + (tickRadius + _kCardinalTickLength) * sin,
          center.dy - (tickRadius + _kCardinalTickLength) * cos,
        ),
        paint,
      );
    }
  }

  // ═════════════════════════════════════════════════════════
  // PULSE RINGS
  // ═════════════════════════════════════════════════════════

  void _paintPulseRing(
    Canvas canvas,
    Offset center,
    double baseRadius,
    double ringProgress,
    double peakOpacity,
  ) {
    final eased = Curves.easeOut.transform(ringProgress);
    final radius = baseRadius + ringWidth + (eased * _kMaxPulseExpansion);
    final opacity = peakOpacity *
        (1.0 - eased) *
        activityLevel.clamp(_kMinVisibleOpacity, 1.0);
    if (opacity < 0.01) return;

    final strokeWidth = ringWidth *
        (_kStrokeTaperStart -
            (_kStrokeTaperStart - _kStrokeTaperEnd) * eased);
    canvas.drawCircle(
      center,
      radius,
      _strokePaint
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.butt
        ..maskFilter = null
        ..color = BaselineColors.teal.atOpacity(opacity),
    );
  }

  void _paintBurstRing(Canvas canvas, Offset center, double baseRadius) {
    final expansion = (1.0 - burstProgress) * _kMaxPulseExpansion * 1.5;
    final radius = baseRadius + ringWidth + expansion;
    final opacity = _kPulseOpacityPeak *
        _kBurstOpacityMultiplier *
        burstProgress *
        activityLevel.clamp(_kMinVisibleOpacity, 1.0);
    if (opacity < 0.01) return;
    canvas.drawCircle(
      center,
      radius,
      _strokePaint
        ..strokeWidth = ringWidth * _kStrokeTaperStart
        ..maskFilter = null
        ..color = BaselineColors.teal.atOpacity(opacity),
    );
  }

  void _paintGlow(Canvas canvas, Offset center, double baseRadius) {
    final breathe = (math.sin(progress * 2 * math.pi) + 1) / 2;
    final intensity = _kGlowOpacity * breathe;
    if (intensity < 0.01) return;
    canvas.drawCircle(
      center,
      baseRadius + ringWidth + _kMaxPulseExpansion,
      _strokePaint
        ..strokeWidth = ringWidth * _kGlowStrokeMultiplier
        ..maskFilter =
            const MaskFilter.blur(BlurStyle.normal, _kGlowBlurSigma)
        ..color = BaselineColors.teal.atOpacity(intensity),
    );
  }

  void _paintPeakFill(Canvas canvas, Offset center, double baseRadius) {
    final breathe = (math.sin(progress * 2 * math.pi) + 1) / 2;
    final fillOpacity = _kPeakFillOpacity * (0.5 + 0.5 * breathe);
    canvas.drawCircle(
      center,
      baseRadius,
      _fillPaint
        ..shader = ui.Gradient.radial(center, baseRadius, [
          BaselineColors.teal.atOpacity(fillOpacity),
          BaselineColors.teal.atOpacity(0.0),
        ]),
    );
  }

  // ═════════════════════════════════════════════════════════
  // HERO: STATIC CHROME (painted when disabled/reduceMotion)
  // ═════════════════════════════════════════════════════════

  void _paintStaticHeroChrome(
    Canvas canvas,
    Offset center,
    double baseRadius,
    Size size,
  ) {
    _paintReticleCorners(canvas, size);
    _paintRegistrationDotsStatic(canvas, center, baseRadius);
    _paintOuterHashmarks(canvas, center, baseRadius);
    _paintSignalPips(canvas, center, size);
    _paintMicroText(canvas, center, baseRadius, size);
  }

  // ═════════════════════════════════════════════════════════
  // HERO: ANIMATED CHROME
  // ═════════════════════════════════════════════════════════

  void _paintHeroAnimatedChrome(
    Canvas canvas,
    Offset center,
    double baseRadius,
    Size size,
  ) {
    _paintRadarSweep(canvas, center, baseRadius);
    _paintActivityArc(canvas, center, baseRadius);
    _paintReticleCorners(canvas, size);
    _paintRegistrationDotsCascade(canvas, center, baseRadius);
    _paintOuterHashmarks(canvas, center, baseRadius);
    _paintOrbitalDot(canvas, center, baseRadius);
    _paintSignalPips(canvas, center, size);
    _paintMicroText(canvas, center, baseRadius, size);
    _paintAcquisitionCrosshair(canvas, center);
  }

  // ── Scope Lens ─────────────────────────────────────────

  void _paintScopeLens(Canvas canvas, Offset center, double baseRadius) {
    canvas.drawCircle(
      center,
      baseRadius * 0.9,
      _fillPaint
        ..shader = ui.Gradient.radial(center, baseRadius * 0.9, [
          BaselineColors.teal.atOpacity(_kScopeLensOpacity),
          BaselineColors.teal.atOpacity(0.0),
        ]),
    );
  }

  // ── Sector Crosshair ───────────────────────────────────

  void _paintSectorCrosshair(
    Canvas canvas,
    Offset center,
    double baseRadius,
  ) {
    final r = baseRadius * 0.85;
    _strokePaint
      ..strokeWidth = _kSectorLineWidth
      ..strokeCap = StrokeCap.butt
      ..maskFilter = null
      ..color = BaselineColors.teal.atOpacity(0.04);
    final paint = _strokePaint;

    // Horizontal.
    canvas.drawLine(
      Offset(center.dx - r, center.dy),
      Offset(center.dx + r, center.dy),
      paint,
    );
    // Vertical.
    canvas.drawLine(
      Offset(center.dx, center.dy - r),
      Offset(center.dx, center.dy + r),
      paint,
    );
  }

  // ── Heartbeat Trace ────────────────────────────────────

  void _paintHeartbeatTrace(
    Canvas canvas,
    Offset center,
    double baseRadius,
  ) {
    final traceRadius = baseRadius - 3.0;
    if (traceRadius <= 0) return;

    final breathe = (math.sin(progress * 2 * math.pi) + 1) / 2;
    final amplitude =
        _kHeartbeatAmplitude * activityLevel * (0.5 + 0.5 * breathe);

    // Arc spans from ~150 deg to ~210 deg (bottom of circle).
    const startAngle = math.pi * 0.65;
    const endAngle = math.pi * 1.35;
    final step = (endAngle - startAngle) / (_kHeartbeatPoints - 1);

    final path = Path();
    for (var i = 0; i < _kHeartbeatPoints; i++) {
      final angle = startAngle + step * i;
      // EKG-style: flat baseline, then sharp QRS complex at center.
      double radialOffset = 0;
      final normalizedI = i / (_kHeartbeatPoints - 1);
      if (normalizedI > 0.3 && normalizedI < 0.45) {
        radialOffset = amplitude * 1.5; // R-wave up
      } else if (normalizedI > 0.45 && normalizedI < 0.55) {
        radialOffset = -amplitude * 2.0; // S-wave down
      } else if (normalizedI > 0.55 && normalizedI < 0.7) {
        radialOffset = amplitude * 0.8; // T-wave recovery
      }

      final r = traceRadius + radialOffset;
      final x = center.dx + r * math.cos(angle);
      final y = center.dy + r * math.sin(angle);

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(
      path,
      _strokePaint
        ..strokeWidth = 0.8
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round
        ..maskFilter = null
        ..color = BaselineColors.teal.atOpacity(0.06 + 0.04 * breathe),
    );
  }

  // ── Radar Sweep ────────────────────────────────────────

  void _paintRadarSweep(
    Canvas canvas,
    Offset center,
    double baseRadius,
  ) {
    final sweepAngle = progress * 2 * math.pi;
    final sweepRadius = baseRadius - 2.0;
    if (sweepRadius <= 0) return;

    // ── Sweep line ──
    final endX = center.dx + sweepRadius * math.sin(sweepAngle);
    final endY = center.dy - sweepRadius * math.cos(sweepAngle);
    canvas.drawLine(
      center,
      Offset(endX, endY),
      _strokePaint
        ..strokeWidth = _kSweepLineWidth
        ..strokeCap = StrokeCap.butt
        ..maskFilter = null
        ..color = BaselineColors.teal.atOpacity(0.06),
    );

    // ── Phosphor trail ──
    final trailArc = _kPhosphorArcDegrees * math.pi / 180;
    // Trail: arc behind the sweep line.
    // Canvas drawArc 0 = 3 o'clock. Our sweep 0 = 12 o'clock.
    final arcStart = sweepAngle - math.pi / 2 - trailArc;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: sweepRadius * 0.7),
      arcStart,
      trailArc,
      false,
      _strokePaint
        ..strokeWidth = sweepRadius * 0.4
        ..color = BaselineColors.teal.atOpacity(0.03),
    );
  }

  // ── Activity Zone Arc ──────────────────────────────────

  void _paintActivityArc(
    Canvas canvas,
    Offset center,
    double baseRadius,
  ) {
    if (activityLevel <= _kDormantThreshold) return;

    final arcRadius = baseRadius + ringWidth + _kMaxPulseExpansion + 4.0;
    final sweepAngle = activityLevel * 2 * math.pi;
    // Start at 12 o'clock, sweep clockwise.
    final startAngle = -math.pi / 2;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: arcRadius),
      startAngle,
      sweepAngle,
      false,
      _strokePaint
        ..strokeWidth = _kActivityArcWidth
        ..strokeCap = StrokeCap.round
        ..maskFilter = null
        ..color = BaselineColors.teal.atOpacity(0.20),
    );
  }

  // ── Reticle Corners ────────────────────────────────────

  void _paintReticleCorners(Canvas canvas, Size size) {
    _strokePaint
      ..strokeWidth = 1.0
      ..strokeCap = StrokeCap.square
      ..maskFilter = null
      ..color = BaselineColors.teal.atOpacity(0.15);
    final paint = _strokePaint;

    final arm = _kReticleArmLength;
    final w = size.width;
    final h = size.height;
    const inset = 2.0;

    // Top-left.
    canvas.drawLine(Offset(inset, inset), Offset(inset + arm, inset), paint);
    canvas.drawLine(Offset(inset, inset), Offset(inset, inset + arm), paint);
    // Top-right.
    canvas.drawLine(
      Offset(w - inset, inset), Offset(w - inset - arm, inset), paint);
    canvas.drawLine(
      Offset(w - inset, inset), Offset(w - inset, inset + arm), paint);
    // Bottom-left.
    canvas.drawLine(
      Offset(inset, h - inset), Offset(inset + arm, h - inset), paint);
    canvas.drawLine(
      Offset(inset, h - inset), Offset(inset, h - inset - arm), paint);
    // Bottom-right.
    canvas.drawLine(
      Offset(w - inset, h - inset),
      Offset(w - inset - arm, h - inset),
      paint,
    );
    canvas.drawLine(
      Offset(w - inset, h - inset),
      Offset(w - inset, h - inset - arm),
      paint,
    );
  }

  // ── Registration Dots (static) ─────────────────────────

  void _paintRegistrationDotsStatic(
    Canvas canvas,
    Offset center,
    double baseRadius,
  ) {
    final dotR = baseRadius + ringWidth + _kMaxPulseExpansion + 2.0;
    _fillPaint
      ..color = BaselineColors.teal.atOpacity(0.10)
      ..maskFilter = null;

    for (var i = 0; i < 8; i++) {
      final angle = i * math.pi / 4;
      canvas.drawCircle(
        Offset(
          center.dx + dotR * math.sin(angle),
          center.dy - dotR * math.cos(angle),
        ),
        _kRegistrationDotRadius,
        _fillPaint,
      );
    }
  }

  // ── Registration Dots (cascade) ────────────────────────

  void _paintRegistrationDotsCascade(
    Canvas canvas,
    Offset center,
    double baseRadius,
  ) {
    final dotR = baseRadius + ringWidth + _kMaxPulseExpansion + 2.0;
    // Active dot index sweeps around with progress.
    final activeDotIndex = (progress * 8).floor() % 8;

    for (var i = 0; i < 8; i++) {
      final angle = i * math.pi / 4;
      // Cascade: active dot is brightest, neighbors dim outward.
      final distance = ((i - activeDotIndex + 8) % 8).toDouble();
      final dimFactor = (1.0 - distance / 8).clamp(0.3, 1.0);
      final opacity = 0.10 + 0.15 * dimFactor;
      final radius = _kRegistrationDotRadius * (0.8 + 0.4 * dimFactor);

      canvas.drawCircle(
        Offset(
          center.dx + dotR * math.sin(angle),
          center.dy - dotR * math.cos(angle),
        ),
        radius,
        _fillPaint
          ..maskFilter = null
          ..color = BaselineColors.teal.atOpacity(opacity),
      );
    }
  }

  // ── Outer Hashmarks ────────────────────────────────────

  void _paintOuterHashmarks(
    Canvas canvas,
    Offset center,
    double baseRadius,
  ) {
    final innerR = baseRadius + ringWidth + _kMaxPulseExpansion + 0.5;
    final outerR = innerR + _kHashmarkLength;
    _strokePaint
      ..strokeWidth = 0.5
      ..strokeCap = StrokeCap.round
      ..maskFilter = null
      ..color = BaselineColors.teal.atOpacity(0.08);

    for (var i = 0; i < 12; i++) {
      if (i % 3 == 0) continue; // Skip cardinal positions.
      final angle = i * math.pi / 6;
      final cos = math.cos(angle);
      final sin = math.sin(angle);
      canvas.drawLine(
        Offset(center.dx + innerR * sin, center.dy - innerR * cos),
        Offset(center.dx + outerR * sin, center.dy - outerR * cos),
        _strokePaint,
      );
    }
  }

  // ── Orbital Satellite Dot ──────────────────────────────

  void _paintOrbitalDot(
    Canvas canvas,
    Offset center,
    double baseRadius,
  ) {
    final orbitRadius = baseRadius + ringWidth + _kMaxPulseExpansion + 5.0;
    // Orbits at 0.3x the main cycle speed for visual variety.
    final orbitAngle = progress * 2 * math.pi * _kOrbitalSpeedRatio;
    final x = center.dx + orbitRadius * math.sin(orbitAngle);
    final y = center.dy - orbitRadius * math.cos(orbitAngle);

    // Dot pulses slightly.
    final pulse = (math.sin(progress * 4 * math.pi) + 1) / 2;
    final opacity = 0.12 + 0.08 * pulse;

    canvas.drawCircle(
      Offset(x, y),
      _kOrbitalDotRadius + 0.3 * pulse,
      _fillPaint
        ..maskFilter = null
        ..color = BaselineColors.teal.atOpacity(opacity),
    );
  }

  // ── Signal Strength Pips ───────────────────────────────

  void _paintSignalPips(Canvas canvas, Offset center, Size size) {
    // Position: top-right area, offset from activity readout.
    final startX = center.dx + 14.0;
    const startY = 2.0;
    final filledCount = (activityLevel * _kSignalPipCount).ceil();

    for (var i = 0; i < _kSignalPipCount; i++) {
      final height = _kSignalPipMaxHeight * (i + 1) / _kSignalPipCount;
      final isFilled = i < filledCount;
      final x = startX + i * (_kSignalPipWidth + 1.5);
      final y = startY + (_kSignalPipMaxHeight - height);

      final pipPaint = isFilled ? _fillPaint : _strokePaint;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, _kSignalPipWidth, height),
          const Radius.circular(0.5),
        ),
        pipPaint
          ..strokeWidth = 0.5
          ..maskFilter = null
          ..color = BaselineColors.teal.atOpacity(isFilled ? 0.18 : 0.06),
      );
    }
  }

  // ── Acquisition Crosshair Flash ────────────────────────

  void _paintAcquisitionCrosshair(Canvas canvas, Offset center) {
    // Only visible during entrance (entranceProgress 0 to 1).
    // Crosshair fades OUT as entrance completes.
    if (entranceProgress >= 1.0) return;
    final opacity = 0.25 * (1.0 - entranceProgress);
    if (opacity < 0.01) return;

    final halfLen = _kAcquisitionCrosshairLength / 2;
    _strokePaint
      ..strokeWidth = 0.8
      ..strokeCap = StrokeCap.butt
      ..maskFilter = null
      ..color = BaselineColors.teal.atOpacity(opacity);

    canvas.drawLine(
      Offset(center.dx - halfLen, center.dy),
      Offset(center.dx + halfLen, center.dy),
      _strokePaint,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy - halfLen),
      Offset(center.dx, center.dy + halfLen),
      _strokePaint,
    );
  }

  // ── Micro Text ─────────────────────────────────────────

  void _paintMicroText(
    Canvas canvas,
    Offset center,
    double baseRadius,
    Size size,
  ) {
    // ── Bottom-left: TM branding ──
    final brandPainter = TextPainter(
      text: TextSpan(
        text: 'SIGNAL PULSE\u2122',
        style: TextStyle(
          fontFamily: BaselineTypography.monoFontFamily,
          fontSize: textScaler.scale(_kMicroTextSize),
          letterSpacing: 1.2,
          color: BaselineColors.teal.atOpacity(0.12),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    brandPainter.paint(
      canvas,
      Offset(
        center.dx - brandPainter.width / 2 - 16.0,
        size.height - brandPainter.height - 1.0,
      ),
    );
    brandPainter.dispose();

    // ── Bottom-right: DTG stamp (cached) ──
    final dtgPainter = TextPainter(
      text: TextSpan(
        text: '$cachedStatusLabel // $cachedDtg',
        style: TextStyle(
          fontFamily: BaselineTypography.monoFontFamily,
          fontSize: textScaler.scale(_kMicroTextSize - 1),
          letterSpacing: 0.6,
          color: BaselineColors.teal.atOpacity(0.08),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    dtgPainter.paint(
      canvas,
      Offset(
        center.dx - dtgPainter.width / 2 + 18.0,
        size.height - dtgPainter.height - 1.0,
      ),
    );
    dtgPainter.dispose();

    // ── Top-center: Activity readout ──
    if (activityLevel > _kDormantThreshold) {
      final readoutPainter = TextPainter(
        text: TextSpan(
          text: activityLevel.toStringAsFixed(2),
          style: TextStyle(
            fontFamily: BaselineTypography.monoFontFamily,
            fontSize: textScaler.scale(_kMicroTextSize),
            letterSpacing: 0.8,
            color: BaselineColors.teal.atOpacity(0.15),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      readoutPainter.paint(
        canvas,
        Offset(center.dx - readoutPainter.width / 2 - 8.0, 1.0),
      );
      readoutPainter.dispose();
    }
  }

  // ── Repaint ────────────────────────────────────────────

  @override
  bool shouldRepaint(covariant _SignalPulsePainter oldDelegate) =>
      progress != oldDelegate.progress ||
      activityLevel != oldDelegate.activityLevel ||
      isDormant != oldDelegate.isDormant ||
      isPeak != oldDelegate.isPeak ||
      reduceMotion != oldDelegate.reduceMotion ||
      showBaseRing != oldDelegate.showBaseRing ||
      enabled != oldDelegate.enabled ||
      ringWidth != oldDelegate.ringWidth ||
      burstProgress != oldDelegate.burstProgress ||
      entranceProgress != oldDelegate.entranceProgress ||
      textScaler != oldDelegate.textScaler ||
      cachedDtg != oldDelegate.cachedDtg;
}

// ═══════════════════════════════════════════════════════════
// ACTIVITY LEVEL DERIVATION
// ═══════════════════════════════════════════════════════════

/// Derives a 0.0 to 1.0 activity level from a rolling 7-day
/// statement count.
///
/// Uses a logarithmic curve (base-2) for natural transitions.
/// A figure going from 3 to 6 statements feels like a bigger
/// jump than 15 to 18, matching human perception.
///
/// Scale (tuned for 44 tracked figures, 7-day window):
///   0 statements: 0.00 (dormant)
///   1 statement:  0.12
///   3 statements: 0.25
///   7 statements: 0.40
///  12 statements: 0.55
///  20 statements: 0.70
///  35 statements: 0.85
///  50+ statements: 0.95 (capped for headroom)
double activityLevelFromStatementCount(int count) {
  if (count <= 0) return 0.0;
  final normalized = math.log(count + 1) / math.log(51);
  return (normalized * 0.95).clamp(0.0, 0.95);
}

/// Maps a pre-computed backend activity score (0 to 100)
/// to the 0.0 to 1.0 range expected by [SignalPulseWidget].
double activityLevelFromScore(int score) {
  return (score / 100).clamp(0.0, 1.0);
}
