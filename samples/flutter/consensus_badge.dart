/// F2.1 : W1: Consensus Badge (Ring Gauge) : LOCKED
///
/// Precision ring gauge showing lens (AI model) convergence.
/// Renders as a classified convergence array: bezel graduation
/// ticks, discrete model-segment arcs, leading-edge glow cap,
/// concentric guide ring with film perforation notches, model-slot
/// markers with micro-labels, circuit trace tendrils to center
/// crosshair, phosphor wake on fill, and a radial halo bloom that
/// intensifies with consensus score. At full convergence (3/3),
/// the ring breathes with a finite sine pulse and emits convergence
/// pulse rings outward like a radar beacon confirming lock-on.
///
/// 37 visual treatments. Classified convergence array.
///
/// Usage:
///   ConsensusBadge(modelCount: 2)           // 2/3, default 64px
///   ConsensusBadge(modelCount: 3, size: 48) // compact, full consensus
///   ConsensusBadge(modelCount: 0, showLabel: false) // empty state
///
/// Data source: consensus.model_count (from get-statement response).
/// totalModels is capped at 3 (OPENAI, ANTHROPIC, XAI). Constructor
/// asserts totalModels <= 3 to match the fixed label registry.
///
/// Path: lib/widgets/consensus_badge.dart
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:baseline_app/config/theme.dart';
import 'package:baseline_app/config/constants.dart';

// ═══════════════════════════════════════════════════════════
// CONSTANTS
// ═══════════════════════════════════════════════════════════

// Dimensions
const double _kBaseSize = 64.0;
const double _kBaseStrokeWidth = 4.0;
const double _kInnerRingRatio = 0.58;
const double _kOuterBezelOffset = 3.0;
const double _kOuterBezelStroke = 0.5;
const double _kMinSizeForTicks = 40.0;
const double _kMinSizeForSlots = 48.0;
const double _kMinSizeForCrosshair = 56.0;
const double _kMinSizeForLabels = 64.0;

// Bezel ticks
const int _kTickCount = 36;
const double _kTickLength = 2.5;
const double _kCardinalTickLength = 4.0;
const double _kTickStroke = 0.5;
const double _kCardinalTickStroke = 0.8;

// Arc segments
const double _kSegmentGapDegrees = 2.0;

// Leading edge
const double _kLeadingDotRadius = 2.5;
const double _kLeadingBloomRadius = 6.0;

// Model slot markers
const double _kSlotMarkerRadius = 2.0;
const double _kSlotMarkerRingRadius = 3.0;
const double _kSlotLabelFontSize = 5.0;
const double _kSlotLabelOffset = 8.0;
const double _kSlotLabelOpacity = 0.18;
const List<String> _kSlotLabels = ['GP', 'CL', 'GR'];

// Circuit trace tendrils
const double _kTraceStroke = 0.3;
const double _kTraceOpacity = 0.025;

// Film perforation notches
const double _kPerfWidth = 1.5;
const double _kPerfHeight = 2.5;
const double _kPerfOpacity = 0.04;

// Void hatch
const double _kHatchSpacing = 3.0;
const double _kHatchStroke = 0.3;

// Crosshair reticle (caseback detail, 56px+)
const double _kCrosshairLength = 4.0;
const double _kCrosshairStroke = 0.3;
const double _kCrosshairOpacity = 0.06;

// Halo / glow
const double _kHaloSigmaMax = 6.0;
const double _kHaloOpacity = 0.25;

// Phosphor wake
const double _kPhosphorExtraWidth = 4.0;
const double _kPhosphorOpacity = 0.035;
const double _kPhosphorLag = 0.15;

// Convergence pulse rings (3/3 only)
const int _kPulseRingCount = 2;
const double _kPulseRingExpansion = 8.0;
const double _kPulseRingStroke = 0.5;
const double _kPulseRingOpacity = 0.12;

/// Max overflow any paint element extends beyond badge size.
const double _kMaxOverflow = _kPulseRingExpansion + _kPulseRingStroke;

// Breathing
const Duration _kBreathPeriod = Duration(milliseconds: 2400);
const int _kBreathCycles = 3;
const double _kBreathAmplitude = 0.12;

// Entry animation
const Duration _kFillDuration = Duration(milliseconds: 500);
const Curve _kFillCurve = Curves.easeOutCubic;
const double _kScanlineHeight = 1.0;
const double _kScanlineFadeStart = 0.7;

// Typography
const double _kMinFontSize = 10.0;
const double _kLabelLetterSpacing = 1.2;
const double _kMeasuredLetterSpacing = 1.6;
const double _kMeasuredFontSize = 7.0;
const double _kMeasuredGap = 3.0;
const double _kClassDotSize = 3.0;
const double _kMaxTextScale = 1.5;

// Score-based teal opacity
const double _kTealOpacity0 = 0.25;
const double _kTealOpacity1 = 0.50;
const double _kTealOpacity2 = 0.75;
const double _kTealOpacity3 = 1.0;

// ═══════════════════════════════════════════════════════════
// CONSENSUS BADGE WIDGET
// ═══════════════════════════════════════════════════════════

class ConsensusBadge extends StatefulWidget {
  const ConsensusBadge({
    super.key,
    required this.modelCount,
    this.totalModels = 3,
    this.size = 64,
    this.showLabel = true,
    this.isCollecting = false,
  })  : assert(modelCount >= 0 && modelCount <= totalModels),
        assert(totalModels > 0),
        assert(totalModels <= _kSlotLabels.length,
            'Labels not defined for models beyond ${_kSlotLabels.length}'),
        assert(size > 0);

  /// Number of models that have contributed analysis (0..totalModels).
  final int modelCount;

  /// Maximum possible models. Capped at 3 (GP, CL, GR).
  final int totalModels;

  /// Outer dimension of the ring gauge (width = height = size).
  final double size;

  /// Whether to show the "LENS CONVERGENCE" label below the ring.
  final bool showLabel;

  /// When true, renders a dimmed collecting state: dashed border,
  /// "---" center text, wrapped in reduced opacity with tooltip.
  final bool isCollecting;

  @override
  State<ConsensusBadge> createState() => _ConsensusBadgeState();
}

class _ConsensusBadgeState extends State<ConsensusBadge>
    with TickerProviderStateMixin {
  // Fill animation.
  late final AnimationController _fillCtrl;
  late final Animation<double> _fillAnim;

  // Breathing (full consensus only).
  AnimationController? _breathCtrl;
  int _breathCount = 0;

  // Cached TextPainters for slot micro-labels (A1-C1).
  List<TextPainter>? _slotLabelPainters;

  // Accessibility.
  bool get _reduceMotion =>
      ui.PlatformDispatcher.instance.accessibilityFeatures.reduceMotion;

  // Derived data.
  bool get _isFullConsensus =>
      widget.totalModels > 0 && widget.modelCount == widget.totalModels;

  double get _fraction => widget.totalModels > 0
      ? widget.modelCount / widget.totalModels
      : 0.0;

  double get _tealOpacity {
    switch (widget.modelCount) {
      case 0:
        return _kTealOpacity0;
      case 1:
        return _kTealOpacity1;
      case 2:
        return _kTealOpacity2;
      default:
        return _kTealOpacity3;
    }
  }

  double get _breathValue {
    final ctrl = _breathCtrl;
    if (ctrl == null || !ctrl.isAnimating) return 0.0;
    return math.sin(ctrl.value * math.pi);
  }

  // ═════════════════════════════════════════════════════════
  // LIFECYCLE
  // ═════════════════════════════════════════════════════════

  @override
  void initState() {
    super.initState();

    _fillCtrl = AnimationController(
      vsync: this,
      duration: _kFillDuration,
    );
    _fillAnim = CurvedAnimation(parent: _fillCtrl, curve: _kFillCurve);

    if (_reduceMotion) {
      _fillCtrl.value = 1.0;
    } else {
      _fillCtrl.forward();
    }

    _maybeStartBreathing();
  }

  @override
  void didUpdateWidget(ConsensusBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.modelCount != widget.modelCount ||
        oldWidget.totalModels != widget.totalModels) {
      if (_reduceMotion) {
        _fillCtrl.value = 1.0;
      } else {
        _fillCtrl.forward(from: 0);
      }
      _stopBreathing();
      _maybeStartBreathing();
      _disposeSlotPainters(); // Rebuild on data change.
    }
  }

  @override
  void dispose() {
    _stopBreathing();
    _disposeSlotPainters();
    _fillCtrl.dispose();
    super.dispose();
  }

  // Slot label painter cache (A1-C1 + A1-C2 + A1-C3).

  List<TextPainter> _getOrBuildSlotPainters(TextScaler textScaler) {
    if (_slotLabelPainters != null) return _slotLabelPainters!;

    final fontFamily = BaselineTypography.monoFontFamily;
    final painters = <TextPainter>[];

    for (int i = 0; i < widget.totalModels && i < _kSlotLabels.length; i++) {
      final isActive = i < widget.modelCount;
      final tp = TextPainter(
        text: TextSpan(
          text: _kSlotLabels[i],
          style: TextStyle(
            fontFamily: fontFamily,
            fontSize: _kSlotLabelFontSize,
            color: (isActive ? BaselineColors.teal : BaselineColors.textSecondary)
                .atOpacity(_kSlotLabelOpacity),
            letterSpacing: 0.5,
          ),
        ),
        textDirection: TextDirection.ltr,
        textScaler: textScaler,
      )..layout();
      painters.add(tp);
    }

    _slotLabelPainters = painters;
    return painters;
  }

  void _disposeSlotPainters() {
    if (_slotLabelPainters != null) {
      for (final tp in _slotLabelPainters!) {
        tp.dispose();
      }
      _slotLabelPainters = null;
    }
  }

  // Breathing lifecycle.

  void _maybeStartBreathing() {
    if (!_isFullConsensus || _reduceMotion) return;
    _breathCount = 0;
    _breathCtrl = AnimationController(
      vsync: this,
      duration: _kBreathPeriod,
    )
      ..addStatusListener(_onBreathStatus)
      ..addListener(_onBreathTick)
      ..forward();
  }

  void _onBreathTick() {
    if (mounted) setState(() {});
  }

  void _onBreathStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _breathCount++;
      if (_breathCount >= _kBreathCycles) {
        _breathCtrl?.stop();
      } else {
        _breathCtrl?.forward(from: 0);
      }
    }
  }

  void _stopBreathing() {
    _breathCtrl?.removeStatusListener(_onBreathStatus);
    _breathCtrl?.removeListener(_onBreathTick);
    _breathCtrl?.dispose();
    _breathCtrl = null;
    _breathCount = 0;
  }

  // ═════════════════════════════════════════════════════════
  // BUILD
  // ═════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    if (widget.isCollecting) return _buildCollectingState();

    final percentage = (_fraction * 100).round();
    final sizeRatio = widget.size / _kBaseSize;
    final strokeWidth = _kBaseStrokeWidth * sizeRatio;
    final fontSize = math.max(_kMinFontSize, sizeRatio * 14);
    final breathOffset = _breathValue * _kBreathAmplitude;

    // Halo sigma ramps above 66%, max at 100%.
    final haloSigma = _fraction >= 0.66
        ? _kHaloSigmaMax * _fraction
        : 0.0;

    // Cache slot label painters with proper text scaling (A1-C1/C2).
    final textScaler = MediaQuery.textScalerOf(context);
    final slotPainters = widget.size >= _kMinSizeForLabels
        ? _getOrBuildSlotPainters(textScaler)
        : const <TextPainter>[];

    // Padding accounts for max pulse ring expansion (A1-C4).
    final overflow = _isFullConsensus ? _kMaxOverflow : _kOuterBezelOffset;

    return RepaintBoundary(
      child: Semantics(
        label: 'Lens convergence',
        value: '$percentage percent, '
            '${widget.modelCount} of ${widget.totalModels} models',
        child: MediaQuery.withClampedTextScaling(
          maxScaleFactor: _kMaxTextScale,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // "MEASURED" micro-label (full consensus only).
              if (_isFullConsensus) ...[
                ExcludeSemantics(
                  child: Text(
                    'MEASURED',
                    style: BaselineTypography.dataSmall.copyWith(
                      fontSize: _kMeasuredFontSize * sizeRatio.clamp(0.75, 1.0),
                      letterSpacing: _kMeasuredLetterSpacing,
                      color: BaselineColors.teal.atOpacity(
                        (BaselineOpacity.muted + breathOffset).clamp(0.0, 1.0),
                      ),
                    ),
                  ),
                ),
                SizedBox(height: _kMeasuredGap * sizeRatio.clamp(0.75, 1.0)),
              ],

              // Ring gauge (all chrome in one CustomPaint).
              SizedBox(
                width: widget.size + (overflow * 2),
                height: widget.size + (overflow * 2),
                child: AnimatedBuilder(
                  animation: _fillAnim,
                  builder: (context, _) {
                    return CustomPaint(
                      painter: _InstrumentPainter(
                        fraction: _fraction * _fillAnim.value,
                        totalFraction: _fraction,
                        modelCount: widget.modelCount,
                        totalModels: widget.totalModels,
                        strokeWidth: strokeWidth,
                        sizeRatio: sizeRatio,
                        ringColor: BaselineColors.teal.atOpacity(
                          (_tealOpacity + breathOffset).clamp(0.0, 1.0),
                        ),
                        trackColor: BaselineColors.borderInactive,
                        haloSigma: haloSigma * _fillAnim.value,
                        haloColor: BaselineColors.teal.atOpacity(
                          (_kHaloOpacity + breathOffset).clamp(0.0, 1.0),
                        ),
                        tealBase: BaselineColors.teal,
                        secondaryColor: BaselineColors.textSecondary,
                        fillProgress: _fillAnim.value,
                        badgeSize: widget.size,
                        breathValue: _breathValue,
                        slotLabelPainters: slotPainters,
                      ),
                      child: Center(
                        child: _FractionText(
                          modelCount: widget.modelCount,
                          totalModels: widget.totalModels,
                          fontSize: fontSize,
                          tealOpacity: _tealOpacity,
                        ),
                      ),
                    );
                  },
                ),
              ),

              // Label row.
              if (widget.showLabel) ...[
                SizedBox(height: BaselineSpacing.xxs * sizeRatio.clamp(0.75, 1.0)),
                ExcludeSemantics(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Classification micro-dot (scaled, A2-9).
                      Container(
                        width: _kClassDotSize * sizeRatio.clamp(0.75, 1.0),
                        height: _kClassDotSize * sizeRatio.clamp(0.75, 1.0),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: BaselineColors.teal.atOpacity(
                            BaselineOpacity.muted,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'LENS CONVERGENCE',
                        style: BaselineTypography.caption.copyWith(
                          letterSpacing: _kLabelLetterSpacing,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Dimmed collecting state: dashed ring, "---" center, reduced opacity.
  Widget _buildCollectingState() {
    final sizeRatio = widget.size / _kBaseSize;

    return Tooltip(
      message: kAwaitingAnalysis,
      child: Opacity(
        opacity: 0.4,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: widget.size,
              height: widget.size,
              child: CustomPaint(
                painter: _CollectingRingPainter(
                  color: BaselineColors.borderInactive,
                  strokeWidth: _kBaseStrokeWidth * sizeRatio,
                ),
                child: Center(
                  child: Text(
                    '---',
                    style: BaselineTypography.data.copyWith(
                      fontSize: math.max(_kMinFontSize, sizeRatio * 14),
                      color: BaselineColors.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
            if (widget.showLabel) ...[
              SizedBox(height: BaselineSpacing.xxs * sizeRatio.clamp(0.75, 1.0)),
              ExcludeSemantics(
                child: Text(
                  'LENS CONVERGENCE',
                  style: BaselineTypography.caption.copyWith(
                    letterSpacing: _kLabelLetterSpacing,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Dashed ring painter for the collecting state.
class _CollectingRingPainter extends CustomPainter {
  _CollectingRingPainter({required this.color, required this.strokeWidth});

  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    const dashCount = 24;
    const gapFraction = 0.35;
    const dashSweep = (2 * math.pi / dashCount) * (1 - gapFraction);
    const gapSweep = (2 * math.pi / dashCount) * gapFraction;

    for (int i = 0; i < dashCount; i++) {
      final startAngle = i * (dashSweep + gapSweep) - math.pi / 2;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        dashSweep,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CollectingRingPainter old) =>
      color != old.color || strokeWidth != old.strokeWidth;
}

// ═══════════════════════════════════════════════════════════
// FRACTION TEXT (styled hierarchy)
// ═══════════════════════════════════════════════════════════

/// Center fraction: count bright, slash dimmed, total secondary.
class _FractionText extends StatelessWidget {
  const _FractionText({
    required this.modelCount,
    required this.totalModels,
    required this.fontSize,
    required this.tealOpacity,
  });

  final int modelCount;
  final int totalModels;
  final double fontSize;
  final double tealOpacity;

  @override
  Widget build(BuildContext context) {
    return RichText(
      textScaler: MediaQuery.textScalerOf(context),
      text: TextSpan(
        children: [
          TextSpan(
            text: '$modelCount',
            style: BaselineTypography.data.copyWith(
              fontSize: fontSize,
              color: BaselineColors.textPrimary.atOpacity(
                tealOpacity.clamp(0.5, 1.0),
              ),
            ),
          ),
          TextSpan(
            text: '/',
            style: BaselineTypography.data.copyWith(
              fontSize: fontSize * 0.85,
              color: BaselineColors.textSecondary.atOpacity(
                BaselineOpacity.muted,
              ),
            ),
          ),
          TextSpan(
            text: '$totalModels',
            style: BaselineTypography.data.copyWith(
              fontSize: fontSize,
              color: BaselineColors.textSecondary.atOpacity(
                BaselineOpacity.moderate,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// INSTRUMENT PAINTER: ALL CHROME IN ONE PAINT PASS
// ═══════════════════════════════════════════════════════════

class _InstrumentPainter extends CustomPainter {
  _InstrumentPainter({
    required this.fraction,
    required this.totalFraction,
    required this.modelCount,
    required this.totalModels,
    required this.strokeWidth,
    required this.sizeRatio,
    required this.ringColor,
    required this.trackColor,
    required this.haloSigma,
    required this.haloColor,
    required this.tealBase,
    required this.secondaryColor,
    required this.fillProgress,
    required this.badgeSize,
    required this.breathValue,
    required this.slotLabelPainters,
  });

  final double fraction;
  final double totalFraction;
  final int modelCount;
  final int totalModels;
  final double strokeWidth;
  final double sizeRatio;
  final Color ringColor;
  final Color trackColor;
  final double haloSigma;
  final Color haloColor;
  final Color tealBase;
  final Color secondaryColor;
  final double fillProgress;
  final double badgeSize;
  final double breathValue;
  final List<TextPainter> slotLabelPainters;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final mainRadius = (badgeSize - strokeWidth) / 2;
    final bezelPadding = totalFraction >= 1.0
        ? _kMaxOverflow
        : _kOuterBezelOffset;

    // Layer 0: Outer bezel ring.
    _paintOuterBezel(canvas, center, mainRadius + bezelPadding);

    // Layer 1: Concentric inner guide ring.
    _paintInnerGuideRing(canvas, center, mainRadius);

    // Layer 1.25: Film perforation notches.
    _paintFilmPerforations(canvas, center, mainRadius);

    // Layer 1.5: Inner crosshair reticle (56px+).
    if (badgeSize >= _kMinSizeForCrosshair) {
      _paintCrosshair(canvas, center);
    }

    // Layer 1.75: Circuit trace tendrils (64px+).
    if (badgeSize >= _kMinSizeForLabels && modelCount > 0) {
      _paintCircuitTraces(canvas, center, mainRadius);
    }

    // Layer 2: Bezel graduation ticks.
    if (badgeSize >= _kMinSizeForTicks) {
      _paintBezelTicks(canvas, center, mainRadius);
    }

    // Layer 3: Background track.
    _paintTrack(canvas, center, mainRadius);

    // Layer 4: Void hatch on unfilled segments.
    if (modelCount > 0 && modelCount < totalModels) {
      _paintVoidHatch(canvas, center, mainRadius);
    }

    // Layer 5: Model slot markers + cached micro-labels.
    if (badgeSize >= _kMinSizeForSlots) {
      _paintSlotMarkers(canvas, center, mainRadius);
    }

    // Layer 6: Radial halo glow.
    if (fraction > 0) {
      _paintHalo(canvas, center, mainRadius);
    }

    // Layer 6.5: Phosphor wake (during fill only).
    if (fraction > 0 && fillProgress < 1.0) {
      _paintPhosphorWake(canvas, center, mainRadius);
    }

    // Layer 7: Filled arc segments.
    if (fraction > 0) {
      _paintFilledSegments(canvas, center, mainRadius);
    }

    // Layer 8: Leading edge glow cap.
    if (fraction > 0) {
      _paintLeadingEdge(canvas, center, mainRadius);
    }

    // Layer 9: Entry scanline.
    if (fillProgress < 1.0) {
      _paintScanline(canvas, size);
    }

    // Layer 10: Convergence pulse rings (3/3 only).
    if (totalFraction >= 1.0 && breathValue > 0) {
      _paintConvergencePulse(canvas, center, mainRadius);
    }
  }

  void _paintOuterBezel(Canvas canvas, Offset center, double radius) {
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = secondaryColor.atOpacity(0.06)
        ..style = PaintingStyle.stroke
        ..strokeWidth = _kOuterBezelStroke * sizeRatio,
    );
  }

  void _paintInnerGuideRing(Canvas canvas, Offset center, double radius) {
    canvas.drawCircle(
      center,
      radius * _kInnerRingRatio,
      Paint()
        ..color = secondaryColor.atOpacity(0.04)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5,
    );
  }

  void _paintFilmPerforations(Canvas canvas, Offset center, double radius) {
    final innerR = radius * _kInnerRingRatio;
    final opacity = _kPerfOpacity * fillProgress;
    if (opacity < 0.005) return;

    final paint = Paint()
      ..color = secondaryColor.atOpacity(opacity);

    for (int i = 0; i < 4; i++) {
      final angle = (math.pi / 4) + (math.pi / 2 * i) - math.pi / 2;
      final cos = math.cos(angle);
      final sin = math.sin(angle);
      final cx = center.dx + innerR * cos;
      final cy = center.dy + innerR * sin;

      canvas.save();
      canvas.translate(cx, cy);
      canvas.rotate(angle + math.pi / 2);
      canvas.drawRect(
        Rect.fromCenter(
          center: Offset.zero,
          width: _kPerfWidth,
          height: _kPerfHeight,
        ),
        paint,
      );
      canvas.restore();
    }
  }

  void _paintCrosshair(Canvas canvas, Offset center) {
    final paint = Paint()
      ..color = secondaryColor.atOpacity(_kCrosshairOpacity)
      ..strokeWidth = _kCrosshairStroke
      ..strokeCap = StrokeCap.round;

    final len = _kCrosshairLength;
    canvas.drawLine(
      Offset(center.dx, center.dy - len),
      Offset(center.dx, center.dy + len),
      paint,
    );
    canvas.drawLine(
      Offset(center.dx - len, center.dy),
      Offset(center.dx + len, center.dy),
      paint,
    );
  }

  void _paintCircuitTraces(Canvas canvas, Offset center, double radius) {
    final opacity = _kTraceOpacity * fillProgress;
    if (opacity < 0.002) return;

    final paint = Paint()
      ..color = tealBase.atOpacity(opacity)
      ..strokeWidth = _kTraceStroke
      ..strokeCap = StrokeCap.round;

    final active = modelCount.clamp(0, totalModels);
    for (int i = 0; i < active; i++) {
      final angle = -math.pi / 2 + (2 * math.pi * i / totalModels);
      final slotX = center.dx + radius * math.cos(angle);
      final slotY = center.dy + radius * math.sin(angle);
      canvas.drawLine(Offset(slotX, slotY), center, paint);
    }
  }

  void _paintBezelTicks(Canvas canvas, Offset center, double radius) {
    final outerR = radius + strokeWidth / 2 + 1;

    for (int i = 0; i < _kTickCount; i++) {
      final angle = (2 * math.pi * i / _kTickCount) - math.pi / 2;
      final isCardinal = i % 9 == 0;

      final tickProgress = ((fillProgress - (i / _kTickCount) * 0.3) / 0.7)
          .clamp(0.0, 1.0);
      if (tickProgress <= 0) continue;

      final length = isCardinal ? _kCardinalTickLength : _kTickLength;
      final stroke = isCardinal ? _kCardinalTickStroke : _kTickStroke;
      final opacity = isCardinal
          ? 0.20 * tickProgress
          : 0.08 * tickProgress;

      final outerPoint = Offset(
        center.dx + outerR * math.cos(angle),
        center.dy + outerR * math.sin(angle),
      );
      final innerPoint = Offset(
        center.dx + (outerR - length) * math.cos(angle),
        center.dy + (outerR - length) * math.sin(angle),
      );

      canvas.drawLine(
        outerPoint,
        innerPoint,
        Paint()
          ..color = secondaryColor.atOpacity(opacity)
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  void _paintTrack(Canvas canvas, Offset center, double radius) {
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = trackColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round,
    );
  }

  void _paintVoidHatch(Canvas canvas, Offset center, double radius) {
    final fillEnd = -math.pi / 2 + (2 * math.pi * totalFraction);
    final trackEnd = 1.5 * math.pi;
    final scaledStroke = _kHatchStroke * sizeRatio;
    final hatchPaint = Paint()
      ..color = secondaryColor.atOpacity(0.04)
      ..strokeWidth = scaledStroke;

    final arcLength = (trackEnd - fillEnd) * radius;
    final steps = (arcLength / _kHatchSpacing).floor();

    for (int i = 0; i < steps; i++) {
      final angle = fillEnd + (i * _kHatchSpacing / radius);
      final px = center.dx + radius * math.cos(angle);
      final py = center.dy + radius * math.sin(angle);

      canvas.drawLine(
        Offset(px - 1, py - 1),
        Offset(px + 1, py + 1),
        hatchPaint,
      );
    }
  }

  void _paintSlotMarkers(Canvas canvas, Offset center, double radius) {
    for (int i = 0; i < totalModels; i++) {
      final angle = -math.pi / 2 + (2 * math.pi * i / totalModels);
      final px = center.dx + radius * math.cos(angle);
      final py = center.dy + radius * math.sin(angle);
      final pos = Offset(px, py);
      final isActive = i < modelCount;

      if (isActive) {
        canvas.drawCircle(
          pos,
          _kSlotMarkerRadius,
          Paint()..color = tealBase.atOpacity(0.6 * fillProgress),
        );
      } else {
        canvas.drawCircle(
          pos,
          _kSlotMarkerRingRadius,
          Paint()
            ..color = secondaryColor.atOpacity(0.12 * fillProgress)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.5,
        );
      }

      // Cached micro-labels at 64px+ (A1-C1: no per-frame TextPainter alloc).
      if (badgeSize >= _kMinSizeForLabels && i < slotLabelPainters.length) {
        if (_kSlotLabelOpacity * fillProgress < 0.01) continue;

        final labelR = radius + _kSlotLabelOffset;
        final lx = center.dx + labelR * math.cos(angle);
        final ly = center.dy + labelR * math.sin(angle);

        final tp = slotLabelPainters[i];
        tp.paint(canvas, Offset(lx - tp.width / 2, ly - tp.height / 2));
      }
    }
  }

  void _paintHalo(Canvas canvas, Offset center, double radius) {
    if (haloSigma <= 0) return;

    // Scale sigma proportionally (A2-2).
    final scaledSigma = haloSigma * sizeRatio;

    final sweepAngle = 2 * math.pi * fraction;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      sweepAngle,
      false,
      Paint()
        ..color = haloColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth + scaledSigma
        ..strokeCap = StrokeCap.round
        ..maskFilter = ui.MaskFilter.blur(BlurStyle.normal, scaledSigma),
    );
  }

  void _paintPhosphorWake(Canvas canvas, Offset center, double radius) {
    final sweepAngle = 2 * math.pi * fraction;
    final trailSweep = (sweepAngle - _kPhosphorLag).clamp(0.0, sweepAngle);
    if (trailSweep <= 0.01) return;

    final fadeOut = (1.0 - fillProgress).clamp(0.2, 1.0);

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      trailSweep,
      false,
      Paint()
        ..color = tealBase.atOpacity(_kPhosphorOpacity * fadeOut)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth + _kPhosphorExtraWidth
        ..strokeCap = StrokeCap.round
        ..maskFilter = const ui.MaskFilter.blur(BlurStyle.normal, 2),
    );
  }

  void _paintFilledSegments(Canvas canvas, Offset center, double radius) {
    final arcRect = Rect.fromCircle(center: center, radius: radius);
    final totalSweep = 2 * math.pi * fraction;

    if (modelCount <= 1 || totalModels <= 1) {
      canvas.drawArc(
        arcRect,
        -math.pi / 2,
        totalSweep,
        false,
        Paint()
          ..color = ringColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round,
      );
      return;
    }

    final gapRadians = _kSegmentGapDegrees * (math.pi / 180);
    final activeModels = (fraction * totalModels).ceil().clamp(0, totalModels);
    final totalGaps = (activeModels - 1).clamp(0, totalModels - 1);

    // Clamp to prevent negative sweep during early fill (A2-1).
    final rawNetSweep = totalSweep - (gapRadians * totalGaps);
    final netSweep = rawNetSweep.clamp(0.0, totalSweep);
    final segmentSweep = activeModels > 0 ? netSweep / activeModels : 0.0;

    final arcPaint = Paint()
      ..color = ringColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    var currentAngle = -math.pi / 2;
    for (int i = 0; i < activeModels; i++) {
      canvas.drawArc(arcRect, currentAngle, segmentSweep, false, arcPaint);
      currentAngle += segmentSweep + gapRadians;
    }
  }

  void _paintLeadingEdge(Canvas canvas, Offset center, double radius) {
    final angle = -math.pi / 2 + (2 * math.pi * fraction);
    final pos = Offset(
      center.dx + radius * math.cos(angle),
      center.dy + radius * math.sin(angle),
    );

    // Bloom behind.
    canvas.drawCircle(
      pos,
      _kLeadingBloomRadius * (fraction.clamp(0.3, 1.0)),
      Paint()
        ..color = tealBase.atOpacity(0.12)
        ..maskFilter = const ui.MaskFilter.blur(BlurStyle.normal, 4),
    );

    // Bright cap dot.
    canvas.drawCircle(
      pos,
      _kLeadingDotRadius,
      Paint()..color = tealBase.atOpacity(0.7),
    );
  }

  void _paintScanline(Canvas canvas, Size size) {
    final beamY = size.height * fillProgress;

    final scanlineOpacity = fillProgress >= _kScanlineFadeStart
        ? 1.0 - ((fillProgress - _kScanlineFadeStart) /
            (1.0 - _kScanlineFadeStart))
        : 1.0;

    final peakOpacity = 0.15 * scanlineOpacity;

    canvas.drawLine(
      Offset(0, beamY),
      Offset(size.width, beamY),
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, beamY),
          Offset(size.width, beamY),
          [
            Colors.transparent,
            tealBase.atOpacity(peakOpacity),
            Colors.transparent,
          ],
          [0.0, 0.5, 1.0],
        )
        ..strokeWidth = _kScanlineHeight,
    );
  }

  void _paintConvergencePulse(Canvas canvas, Offset center, double radius) {
    for (int i = 0; i < _kPulseRingCount; i++) {
      final phase = (breathValue - (i * 0.4)).clamp(0.0, 1.0);
      if (phase <= 0.01) continue;

      final expansion = _kPulseRingExpansion * phase;
      final pulseRadius = radius + strokeWidth / 2 + expansion;
      final opacity = _kPulseRingOpacity * (1.0 - phase);
      if (opacity < 0.005) continue;

      canvas.drawCircle(
        center,
        pulseRadius,
        Paint()
          ..color = tealBase.atOpacity(opacity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = _kPulseRingStroke,
      );
    }
  }

  @override
  bool shouldRepaint(_InstrumentPainter old) {
    return old.fraction != fraction ||
        old.totalFraction != totalFraction ||
        old.modelCount != modelCount ||
        old.totalModels != totalModels ||
        old.strokeWidth != strokeWidth ||
        old.sizeRatio != sizeRatio ||
        old.ringColor != ringColor ||
        old.trackColor != trackColor ||
        old.haloSigma != haloSigma ||
        old.haloColor != haloColor ||
        old.tealBase != tealBase ||
        old.secondaryColor != secondaryColor ||
        old.fillProgress != fillProgress ||
        old.badgeSize != badgeSize ||
        old.breathValue != breathValue;
  }
}
