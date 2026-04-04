/// F2.8 — Metric Bar (Precision Gauge) — LOCKED
///
/// Horizontal precision measurement gauge displaying a 0-100 metric
/// reading with graduated hashmark ruler, animated teal fill with
/// leading edge glow, and classified void hatch for unavailable data.
///
/// Concept: multimeter readout / oscilloscope level indicator.
/// Not a progress bar. A measurement instrument. Every tick mark
/// is a graduation. The fill is a calibrated reading. The channel
/// is milled, the datum brackets anchor the scale, and the vernier
/// mark resolves the reading to sub-pixel precision.
///
/// 42 visual treatments. Rendered N times per screen: performance
/// critical. Single CustomPainter, efficient shouldRepaint, all
/// static colors pre-computed.
///
/// Usage:
///   MetricBar(label: 'Repetition', value: 42)
///   MetricBar(label: 'Novelty', value: 78, animate: false)
///   MetricBar(label: 'Affect', value: null)  // void hatch
///
/// Data source: consensus.*_avg or analysis.* fields (0-100 scale).
///
/// Path: lib/widgets/metric_bar.dart
library;

// 1. Dart SDK
import 'dart:math' as math;
import 'dart:ui' as ui;

// 2. Flutter
import 'package:flutter/material.dart';

// 3. Config
import 'package:baseline_app/config/theme.dart';

// ═══════════════════════════════════════════════════════════
// CONSTANTS
// ═══════════════════════════════════════════════════════════

// ── Gauge track ─────────────────────────────────────────

/// Total height of the gauge area (track + tick overhang).
const double _kGaugeHeight = 14.0;

/// Track bar height.
const double _kTrackHeight = 6.0;

/// Track corner radius.
const double _kTrackRadius = 3.0;

// ── Hashmark ticks ──────────────────────────────────────

/// Major tick height (extends above and below track center).
const double _kMajorTickH = 3.0;

/// Minor tick height.
const double _kMinorTickH = 1.5;

/// Decorative graduation stroke (not structural border).
const double _kTickStroke = 0.5;

/// Major tick positions (fractions 0-1).
const List<double> _kMajorTicks = [0.0, 0.25, 0.5, 0.75, 1.0];

/// Minor tick positions (fractions 0-1).
const List<double> _kMinorTicks = [0.125, 0.375, 0.625, 0.875];

/// Witness tick positions: every 10%, excluding major/minor.
const List<double> _kWitnessTicks = [0.1, 0.2, 0.3, 0.4, 0.6, 0.7, 0.8, 0.9];

/// Witness tick height (ultra-fine).
const double _kWitnessTickH = 1.0;

/// Witness tick stroke (decorative graduation).
const double _kWitnessTickStroke = 0.3;

// ── Leading edge ────────────────────────────────────────

/// Cap dot radius at fill terminus.
const double _kCapDotRadius = 2.5;

/// Bloom halo blur sigma.
const double _kBloomSigma = 3.0;

/// Bloom halo opacity.
const double _kBloomOpacity = 0.25;

// ── End-cap dots ────────────────────────────────────────

/// Endpoint dot radius (0% and 100% markers).
const double _kEndDotRadius = 1.0;

// ── Scanline ────────────────────────────────────────────

/// Scanline beam half-width.
const double _kScanlineHalfW = 20.0;

// ── Phosphor wake ───────────────────────────────────────

/// Wake trail length behind leading edge (fraction of fill).
const double _kWakeLength = 0.15;

/// Wake peak opacity.
const double _kWakeOpacity = 0.12;

// ── Center notch ────────────────────────────────────────

/// Extra height for the 50% center notch above major ticks.
const double _kCenterNotchExtra = 1.5;

/// Center notch stroke width (slightly bolder).
const double _kCenterNotchStroke = 0.8;

// ── Tick brightness ramp ────────────────────────────────

/// Radius around fill edge where ticks brighten (fraction of width).
const double _kTickRampRadius = 0.08;

// ── Void hatch ──────────────────────────────────────────

/// Hatch line spacing.
const double _kHatchSpacing = 4.0;

/// Hatch stroke width.
const double _kHatchStroke = 0.3;

// ── Classification dot ──────────────────────────────────

/// Dot diameter between label and value.
const double _kDotSize = 2.0;

// ── Animation timing ────────────────────────────────────

/// Fill animation duration.
const Duration _kFillDuration = Duration(milliseconds: 400);

/// Entry fade completes at this fraction of the controller.
const double _kEntryEnd = 0.4;

/// Fill begins at this fraction of the controller.
const double _kFillStart = 0.2;

// ── Vernier precision mark ──────────────────────────────

/// Vernier line extension above/below track.
const double _kVernierExtension = 2.0;

/// Vernier line stroke.
const double _kVernierStroke = 0.8;

/// Vernier line opacity.
const double _kVernierOpacity = 0.60;

// ── Channel lip scores ──────────────────────────────────

/// Lip score hairline stroke (decorative, not structural).
const double _kLipStroke = 0.3;

/// Lip score opacity.
const double _kLipOpacity = 0.06;

// ── Datum brackets ──────────────────────────────────────

/// Datum bracket arm length.
const double _kDatumArm = 2.5;

/// Datum bracket stroke.
const double _kDatumStroke = 0.4;

/// Datum bracket opacity.
const double _kDatumOpacity = 0.10;

// ── Substrate micro-dots ────────────────────────────────

/// Dot spacing in unfilled track area.
const double _kSubstrateSpacing = 4.0;

/// Substrate dot radius.
const double _kSubstrateDotRadius = 0.2;

/// Substrate dot opacity.
const double _kSubstrateDotOpacity = 0.015;

// ── Reading acquisition flash ───────────────────────────

/// Flash ring max expansion radius.
const double _kFlashMaxRadius = 5.0;

/// Flash ring stroke.
const double _kFlashStroke = 0.5;

/// Flash begins at this controller fraction.
const double _kFlashStart = 0.90;

// ── Fill luminance ridge ────────────────────────────────

/// Ridge additional brightness above fill.
const double _kRidgeBoost = 0.08;

/// Ridge vertical position (fraction of track height from top).
const double _kRidgeFraction = 0.45;

/// Ridge stroke.
const double _kRidgeStroke = 0.3;

// ── Fill edge diffusion ─────────────────────────────────

/// Number of pixels at leading edge to diffuse.
const double _kDiffusionWidth = 3.0;

// ── Instrument designation ──────────────────────────────

/// Designation text.
const String _kDesignation = 'MTR';

/// Designation font size.
const double _kDesignationSize = 4.0;

/// Designation opacity.
const double _kDesignationOpacity = 0.05;

// ═══════════════════════════════════════════════════════════
// WIDGET
// ═══════════════════════════════════════════════════════════

class MetricBar extends StatefulWidget {
  const MetricBar({
    super.key,
    required this.label,
    required this.value,
    this.animate = true,
  }) : assert(value == null || (value >= 0 && value <= 100));

  /// Metric name (e.g., "Repetition", "Novelty", "Affect").
  final String label;

  /// Value 0-100. Null = not available (shows void hatch).
  final double? value;

  /// Whether to animate on mount / value change.
  final bool animate;

  @override
  State<MetricBar> createState() => _MetricBarState();
}

class _MetricBarState extends State<MetricBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late Animation<double> _fillCurve;

  /// Target fraction after animation completes.
  double _targetFraction = 0;

  /// Whether we're in the initial mount animation.
  bool _isEntry = true;

  /// Cached reduceMotion flag.
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _reduceMotion = ui.PlatformDispatcher.instance.accessibilityFeatures.reduceMotion;
    _targetFraction = _safeValue(widget.value);

    _controller = AnimationController(
      vsync: this,
      duration: _kFillDuration,
    );

    // Clear entry flag once first animation completes.
    _controller.addStatusListener(_onAnimStatus);

    _buildFillAnimation(0, _targetFraction);

    if (widget.animate && widget.value != null && !_reduceMotion) {
      _controller.forward();
    } else {
      _controller.value = 1.0;
      _isEntry = false;
    }
  }

  void _onAnimStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && _isEntry) {
      setState(() {
        _isEntry = false;
      });
    }
  }

  @override
  void didUpdateWidget(MetricBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      final double oldFrac = _safeValue(oldWidget.value);
      final double newFrac = _safeValue(widget.value);
      _targetFraction = newFrac;
      _isEntry = false;

      if (oldWidget.value == null && widget.value != null) {
        // Null -> known: snap to target, just fade in.
        _buildFillAnimation(newFrac, newFrac);
      } else {
        // Known -> known, or known -> null: animate between.
        _buildFillAnimation(oldFrac, newFrac);
      }

      if (widget.animate && !_reduceMotion) {
        _controller.forward(from: 0);
      } else {
        _controller.value = 1.0;
      }
    }
  }

  /// Clamps to 0-100 and normalises to 0-1. Guards NaN/Infinity.
  double _safeValue(double? v) {
    if (v == null || v.isNaN || v.isInfinite) return 0;
    return v.clamp(0, 100) / 100;
  }

  void _buildFillAnimation(double from, double to) {
    _fillCurve = Tween<double>(begin: from, end: to).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(_kFillStart, 1.0, curve: Curves.easeOutCubic),
      ),
    );
  }

  @override
  void dispose() {
    _controller.removeStatusListener(_onAnimStatus);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool hasValue = widget.value != null &&
        !widget.value!.isNaN &&
        !widget.value!.isInfinite;

    final int displayInt =
        hasValue ? widget.value!.clamp(0, 100).round() : 0;

    // Teal intensity scales with value (low = dim, high = vivid).
    final double tealIntensity =
        hasValue ? 0.35 + (_targetFraction * 0.65) : 0.0;

    // Value text color: lerp toward teal at high values.
    final Color valueColor = hasValue
        ? Color.lerp(
            BaselineColors.textPrimary,
            BaselineColors.teal,
            (_targetFraction * 0.3).clamp(0.0, 0.3),
          )!
        : BaselineColors.textSecondary;

    return Semantics(
      label: hasValue
          ? '${widget.label}: $displayInt out of 100'
          : '${widget.label}: not available',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Label · dot · value row ──
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.label.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: BaselineTypography.dataSmall.copyWith(
                    color: BaselineColors.textSecondary,
                    letterSpacing: 1.0,
                    fontSize: 9,
                  ),
                ),
              ),
              // Classification micro-dot.
              Container(
                width: _kDotSize,
                height: _kDotSize,
                margin: const EdgeInsets.symmetric(
                  horizontal: BaselineSpacing.xs,
                ),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: BaselineColors.textSecondary
                      .atOpacity(BaselineOpacity.muted),
                ),
              ),
              hasValue
                  ? AnimatedSwitcher(
                      duration: BaselineAnimation.fast,
                      transitionBuilder: (child, anim) =>
                          FadeTransition(opacity: anim, child: child),
                      child: Text(
                        displayInt.toString(),
                        key: ValueKey<int>(displayInt),
                        style: BaselineTypography.data.copyWith(
                          color: valueColor,
                          letterSpacing: 0.8,
                          fontSize: 13,
                        ),
                      ),
                    )
                  : Text(
                      '\u2013',
                      style: BaselineTypography.data.copyWith(
                        color: BaselineColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
            ],
          ),
          const SizedBox(height: BaselineSpacing.xxs),

          // ── Gauge (AnimatedBuilder isolates repaint to canvas) ──
          AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              // Entry fade: opacity ramps 0->1 over first 40%.
              final double entryOpacity = _isEntry
                  ? (_controller.value / _kEntryEnd).clamp(0.0, 1.0)
                  : 1.0;

              // Fill fraction for the painter.
              final double fillFraction =
                  _controller.isAnimating || _controller.value < 1.0
                      ? _fillCurve.value
                      : _targetFraction;

              return Opacity(
                opacity: entryOpacity,
                child: RepaintBoundary(
                  child: SizedBox(
                    height: _kGaugeHeight,
                    child: CustomPaint(
                      size: const Size(double.maxFinite, _kGaugeHeight),
                      painter: _GaugePainter(
                        fillFraction: hasValue ? fillFraction : 0,
                        hasValue: hasValue,
                        tealIntensity: tealIntensity,
                        animProgress: _controller.value,
                        isEntry: _isEntry,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// GAUGE PAINTER: track + ticks + fill + edge glow + void
// ═══════════════════════════════════════════════════════════

class _GaugePainter extends CustomPainter {
  _GaugePainter({
    required this.fillFraction,
    required this.hasValue,
    required this.tealIntensity,
    required this.animProgress,
    required this.isEntry,
  });

  final double fillFraction;
  final bool hasValue;
  final double tealIntensity;
  final double animProgress;
  final bool isEntry;

  // ── Pre-computed static colors (zero allocation in paint) ──

  static final Color _hatchColor =
      BaselineColors.textSecondary.atOpacity(0.04);
  static final Color _endDotColor =
      BaselineColors.textSecondary.atOpacity(0.15);
  static final Color _lipColor =
      BaselineColors.textSecondary.atOpacity(_kLipOpacity);
  static final Color _datumColor =
      BaselineColors.textSecondary.atOpacity(_kDatumOpacity);
  static final Color _substrateDotColor =
      BaselineColors.textPrimary.atOpacity(_kSubstrateDotOpacity);
  static final Color _witnessTickColor =
      BaselineColors.textSecondary.atOpacity(0.04);

  // ── Pre-cached "MTR" designation painter ──

  static TextPainter? _designationPainter;

  static TextPainter _getDesignationPainter() {
    if (_designationPainter != null) return _designationPainter!;
    _designationPainter = TextPainter(
      text: TextSpan(
        text: _kDesignation,
        style: TextStyle(
          fontFamily: BaselineTypography.monoFontFamily,
          fontSize: _kDesignationSize,
          color: BaselineColors.teal.atOpacity(_kDesignationOpacity),
          letterSpacing: 0.5,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    return _designationPainter!;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final trackY = (_kGaugeHeight - _kTrackHeight) / 2;
    final trackW = size.width;

    // Guard: unconstrained width = no painting.
    if (trackW.isInfinite || trackW <= 0) return;

    // 1. Instrument designation "MTR" (behind everything).
    _paintDesignation(canvas, trackW, trackY);

    // 2. Hashmark graduation ticks (behind track).
    _paintTicks(canvas, trackW, trackY);

    // 3. Witness graduation ticks (ultra-fine 10% marks).
    _paintWitnessTicks(canvas, trackW, trackY);

    // 4. Track background with channel depth.
    _paintTrack(canvas, trackW, trackY);

    // 5. Channel lip scores (machined edge detail).
    _paintChannelLips(canvas, trackW, trackY);

    // 6. Substrate micro-dots in unfilled area.
    if (hasValue && fillFraction < 0.98) {
      _paintSubstrate(canvas, trackW, trackY);
    } else if (!hasValue) {
      _paintSubstrate(canvas, trackW, trackY);
    }

    // 7. Fill gradient (only when data present).
    if (hasValue && fillFraction > 0) {
      _paintFill(canvas, trackW, trackY);
    }

    // 8. Fill luminance ridge (mercury column center-line).
    if (hasValue && fillFraction > 0.02) {
      _paintLuminanceRidge(canvas, trackW, trackY);
    }

    // 9. Phosphor wake (oscilloscope trail behind leading edge).
    if (hasValue && fillFraction > 0.02 &&
        isEntry && animProgress < 0.95) {
      _paintPhosphorWake(canvas, trackW, trackY);
    }

    // 10. Void hatch (no data = classified redaction).
    if (!hasValue) {
      _paintVoidHatch(canvas, trackW, trackY);
    }

    // 11. Datum brackets (origin + terminus anchors).
    _paintDatumBrackets(canvas, trackW, trackY);

    // 12. End-cap dots (0% and 100% ruler endpoints).
    _paintEndCaps(canvas, trackW, trackY);

    // 13. Vernier precision mark (extends above/below track).
    if (hasValue && fillFraction > 0.01) {
      _paintVernierMark(canvas, trackW, trackY);
    }

    // 14. Leading edge cap + bloom (when filling).
    if (hasValue && fillFraction > 0.01) {
      _paintLeadingEdge(canvas, trackW, trackY);
    }

    // 15. Reading acquisition flash (single ring at anim end).
    if (hasValue && isEntry && animProgress > _kFlashStart) {
      _paintAcquisitionFlash(canvas, trackW, trackY);
    }

    // 16. Scanline sweep during entry (fades out at 95%).
    if (isEntry && animProgress > 0.05 && animProgress < 0.95) {
      _paintScanline(canvas, trackW, trackY);
    }
  }

  // ── Hashmark ticks ──────────────────────────────────────

  void _paintTicks(Canvas canvas, double trackW, double trackY) {
    final centerY = trackY + _kTrackHeight / 2;

    // Major ticks: 0%, 25%, 50%, 75%, 100%.
    for (final frac in _kMajorTicks) {
      final x = trackW * frac;

      // Center notch: 50% tick is taller + bolder.
      final isCenterNotch = frac == 0.5;
      final tickH =
          isCenterNotch ? _kMajorTickH + _kCenterNotchExtra : _kMajorTickH;
      final stroke =
          isCenterNotch ? _kCenterNotchStroke : _kTickStroke;

      // Brightness ramp: ticks near fill edge glow brighter.
      final proximity = hasValue && fillFraction > 0
          ? (1.0 - ((frac - fillFraction).abs() / _kTickRampRadius)
              .clamp(0.0, 1.0))
          : 0.0;
      final baseAlpha = isCenterNotch ? 0.18 : 0.12;
      final rampedAlpha = baseAlpha + (proximity * 0.15);

      final paint = Paint()
        ..color = BaselineColors.textSecondary.atOpacity(rampedAlpha)
        ..strokeWidth = stroke;

      canvas.drawLine(
        Offset(x, centerY - tickH),
        Offset(x, centerY + tickH),
        paint,
      );
    }

    // Minor ticks: 12.5%, 37.5%, 62.5%, 87.5%.
    for (final frac in _kMinorTicks) {
      final x = trackW * frac;

      // Brightness ramp on minor ticks too.
      final proximity = hasValue && fillFraction > 0
          ? (1.0 - ((frac - fillFraction).abs() / _kTickRampRadius)
              .clamp(0.0, 1.0))
          : 0.0;
      final rampedAlpha = 0.06 + (proximity * 0.08);

      canvas.drawLine(
        Offset(x, centerY - _kMinorTickH),
        Offset(x, centerY + _kMinorTickH),
        Paint()
          ..color = BaselineColors.textSecondary.atOpacity(rampedAlpha)
          ..strokeWidth = _kTickStroke,
      );
    }
  }

  // ── Witness graduation ticks (10% finest scale) ───────

  void _paintWitnessTicks(Canvas canvas, double trackW, double trackY) {
    final centerY = trackY + _kTrackHeight / 2;
    final paint = Paint()
      ..color = _witnessTickColor
      ..strokeWidth = _kWitnessTickStroke;

    for (final frac in _kWitnessTicks) {
      final x = trackW * frac;
      canvas.drawLine(
        Offset(x, centerY - _kWitnessTickH),
        Offset(x, centerY + _kWitnessTickH),
        paint,
      );
    }
  }

  // ── Track (with channel depth) ──────────────────────────

  void _paintTrack(Canvas canvas, double trackW, double trackY) {
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, trackY, trackW, _kTrackHeight),
      const Radius.circular(_kTrackRadius),
    );

    // Channel depth: subtle vertical gradient (darker edges,
    // slightly lighter center): machined instrument channel.
    final edgeAlpha = hasValue ? 0.08 : 0.03;
    final centerAlpha = hasValue ? 0.12 : 0.05;
    final edgeColor =
        BaselineColors.textSecondary.atOpacity(edgeAlpha);
    final centerColor =
        BaselineColors.textSecondary.atOpacity(centerAlpha);

    canvas.save();
    canvas.clipRRect(rrect);
    canvas.drawRect(
      Rect.fromLTWH(0, trackY, trackW, _kTrackHeight),
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, trackY),
          Offset(0, trackY + _kTrackHeight),
          [edgeColor, centerColor, edgeColor],
          [0.0, 0.5, 1.0],
        ),
    );
    canvas.restore();
  }

  // ── Channel lip scores ────────────────────────────────

  void _paintChannelLips(Canvas canvas, double trackW, double trackY) {
    final lipPaint = Paint()
      ..color = _lipColor
      ..strokeWidth = _kLipStroke;

    // Top lip.
    canvas.drawLine(
      Offset(0, trackY),
      Offset(trackW, trackY),
      lipPaint,
    );

    // Bottom lip.
    canvas.drawLine(
      Offset(0, trackY + _kTrackHeight),
      Offset(trackW, trackY + _kTrackHeight),
      lipPaint,
    );
  }

  // ── Substrate micro-dots (unfilled area) ──────────────

  void _paintSubstrate(Canvas canvas, double trackW, double trackY) {
    final startX = hasValue
        ? (trackW * fillFraction).clamp(0.0, trackW)
        : 0.0;
    final dotPaint = Paint()..color = _substrateDotColor;

    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(
      Rect.fromLTWH(0, trackY, trackW, _kTrackHeight),
      const Radius.circular(_kTrackRadius),
    ));

    final centerY = trackY + _kTrackHeight / 2;
    // Two rows of dots: offset from center by 1px.
    for (double x = startX; x < trackW; x += _kSubstrateSpacing) {
      canvas.drawCircle(
        Offset(x, centerY - 1),
        _kSubstrateDotRadius,
        dotPaint,
      );
      canvas.drawCircle(
        Offset(x, centerY + 1),
        _kSubstrateDotRadius,
        dotPaint,
      );
    }
    canvas.restore();
  }

  // ── Fill gradient ─────────────────────────────────────

  void _paintFill(Canvas canvas, double trackW, double trackY) {
    final fillW = trackW * fillFraction.clamp(0.0, 1.0);
    if (fillW < 1) return;

    final fillRRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, trackY, fillW, _kTrackHeight),
      const Radius.circular(_kTrackRadius),
    );

    // Gradient: dim teal -> vivid teal toward leading edge.
    // Intensity scales with the value itself.
    final dimAlpha = (tealIntensity * 0.4).clamp(0.0, 1.0);
    final vividAlpha = tealIntensity.clamp(0.0, 1.0);

    canvas.save();
    canvas.clipRRect(fillRRect);

    // Fill edge diffusion: last _kDiffusionWidth pixels
    // taper from full opacity to 60% (analog soft-boundary).
    final diffusionStart = (fillW - _kDiffusionWidth).clamp(0.0, fillW);
    final diffusedVividAlpha = vividAlpha * 0.6;

    canvas.drawRect(
      Rect.fromLTWH(0, trackY, fillW, _kTrackHeight),
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, trackY),
          Offset(fillW, trackY),
          [
            BaselineColors.teal.atOpacity(dimAlpha),
            BaselineColors.teal.atOpacity(vividAlpha),
            BaselineColors.teal.atOpacity(diffusedVividAlpha),
          ],
          [
            0.0,
            fillW > _kDiffusionWidth
                ? diffusionStart / fillW
                : 0.0,
            1.0,
          ],
        ),
    );
    canvas.restore();
  }

  // ── Fill luminance ridge (mercury column center-line) ──

  void _paintLuminanceRidge(Canvas canvas, double trackW, double trackY) {
    final fillW = trackW * fillFraction.clamp(0.0, 1.0);
    if (fillW < 2) return;

    final ridgeY = trackY + (_kTrackHeight * _kRidgeFraction);
    final ridgeAlpha = (tealIntensity + _kRidgeBoost).clamp(0.0, 1.0);

    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(
      Rect.fromLTWH(0, trackY, fillW, _kTrackHeight),
      const Radius.circular(_kTrackRadius),
    ));

    canvas.drawLine(
      Offset(2, ridgeY),
      Offset(fillW - 1, ridgeY),
      Paint()
        ..color = BaselineColors.teal.atOpacity(ridgeAlpha)
        ..strokeWidth = _kRidgeStroke,
    );
    canvas.restore();
  }

  // ── Phosphor wake (oscilloscope trail) ───────────────

  void _paintPhosphorWake(Canvas canvas, double trackW, double trackY) {
    final edgeX = trackW * fillFraction.clamp(0.0, 1.0);
    final wakeStartX = (edgeX - trackW * _kWakeLength).clamp(0.0, edgeX);

    // Fading gradient trail behind the leading edge.
    final gradient = ui.Gradient.linear(
      Offset(wakeStartX, trackY),
      Offset(edgeX, trackY),
      [
        Colors.transparent,
        BaselineColors.teal.atOpacity(_kWakeOpacity * tealIntensity),
      ],
    );

    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(
      Rect.fromLTWH(0, trackY, trackW, _kTrackHeight),
      const Radius.circular(_kTrackRadius),
    ));
    canvas.drawRect(
      Rect.fromLTWH(wakeStartX, trackY, edgeX - wakeStartX, _kTrackHeight),
      Paint()..shader = gradient,
    );
    canvas.restore();
  }

  // ── Void hatch ────────────────────────────────────────

  void _paintVoidHatch(Canvas canvas, double trackW, double trackY) {
    final hatchPaint = Paint()
      ..color = _hatchColor
      ..strokeWidth = _kHatchStroke;

    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(
      Rect.fromLTWH(0, trackY, trackW, _kTrackHeight),
      const Radius.circular(_kTrackRadius),
    ));

    for (double x = -_kTrackHeight;
        x < trackW + _kTrackHeight;
        x += _kHatchSpacing) {
      canvas.drawLine(
        Offset(x, trackY + _kTrackHeight),
        Offset(x + _kTrackHeight, trackY),
        hatchPaint,
      );
    }
    canvas.restore();
  }

  // ── Datum brackets (origin + terminus anchors) ────────

  void _paintDatumBrackets(Canvas canvas, double trackW, double trackY) {
    final datumPaint = Paint()
      ..color = _datumColor
      ..strokeWidth = _kDatumStroke
      ..strokeCap = StrokeCap.round;

    final topY = trackY - 1;
    final botY = trackY + _kTrackHeight + 1;

    // Origin (0%): L-bracket opening right.
    canvas.drawLine(Offset(0, topY), Offset(_kDatumArm, topY), datumPaint);
    canvas.drawLine(Offset(0, topY), Offset(0, topY + _kDatumArm), datumPaint);

    // Terminus (100%): mirrored L opening left.
    canvas.drawLine(
      Offset(trackW, botY),
      Offset(trackW - _kDatumArm, botY),
      datumPaint,
    );
    canvas.drawLine(
      Offset(trackW, botY),
      Offset(trackW, botY - _kDatumArm),
      datumPaint,
    );
  }

  // ── End-cap dots ──────────────────────────────────────

  void _paintEndCaps(Canvas canvas, double trackW, double trackY) {
    final centerY = trackY + _kTrackHeight / 2;
    final dotPaint = Paint()..color = _endDotColor;

    // 0% origin.
    canvas.drawCircle(Offset(0, centerY), _kEndDotRadius, dotPaint);

    // 100% terminus.
    canvas.drawCircle(Offset(trackW, centerY), _kEndDotRadius, dotPaint);
  }

  // ── Vernier precision mark ────────────────────────────

  void _paintVernierMark(Canvas canvas, double trackW, double trackY) {
    final edgeX = trackW * fillFraction.clamp(0.0, 1.0);

    canvas.drawLine(
      Offset(edgeX, trackY - _kVernierExtension),
      Offset(edgeX, trackY + _kTrackHeight + _kVernierExtension),
      Paint()
        ..color = BaselineColors.teal.atOpacity(
          _kVernierOpacity * tealIntensity,
        )
        ..strokeWidth = _kVernierStroke,
    );
  }

  // ── Leading edge cap + bloom ──────────────────────────

  void _paintLeadingEdge(Canvas canvas, double trackW, double trackY) {
    final edgeX = trackW * fillFraction.clamp(0.0, 1.0);
    final centerY = trackY + _kTrackHeight / 2;

    // Pulse: brightness surges during entry animation.
    final pulse = isEntry
        ? 0.8 + 0.2 * math.sin(animProgress * math.pi * 2)
        : 1.0;

    // Bloom halo (behind cap dot).
    canvas.drawCircle(
      Offset(edgeX, centerY),
      _kCapDotRadius + 2,
      Paint()
        ..color = BaselineColors.teal.atOpacity(
          _kBloomOpacity * tealIntensity * pulse,
        )
        ..maskFilter =
            const MaskFilter.blur(BlurStyle.normal, _kBloomSigma),
    );

    // Cap dot: bright teal circle at fill terminus.
    canvas.drawCircle(
      Offset(edgeX, centerY),
      _kCapDotRadius,
      Paint()
        ..color = BaselineColors.teal.atOpacity(tealIntensity * pulse),
    );
  }

  // ── Reading acquisition flash ─────────────────────────

  void _paintAcquisitionFlash(Canvas canvas, double trackW, double trackY) {
    final edgeX = trackW * fillFraction.clamp(0.0, 1.0);
    final centerY = trackY + _kTrackHeight / 2;

    // Flash progress: 0->1 over the final 10% of animation.
    final flashT =
        ((animProgress - _kFlashStart) / (1.0 - _kFlashStart)).clamp(0.0, 1.0);

    // Ring expands outward, opacity fades.
    final radius = _kCapDotRadius + (_kFlashMaxRadius * flashT);
    final opacity = tealIntensity * 0.30 * (1.0 - flashT);

    if (opacity > 0.001) {
      canvas.drawCircle(
        Offset(edgeX, centerY),
        radius,
        Paint()
          ..color = BaselineColors.teal.atOpacity(opacity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = _kFlashStroke,
      );
    }
  }

  // ── Scanline sweep ────────────────────────────────────

  void _paintScanline(Canvas canvas, double trackW, double trackY) {
    final beamX = trackW * animProgress;
    final centerY = trackY + _kTrackHeight / 2;
    final intensity = (1.0 - animProgress) * 0.25;

    final gradient = ui.Gradient.linear(
      Offset(beamX - _kScanlineHalfW, centerY),
      Offset(beamX + _kScanlineHalfW, centerY),
      [
        Colors.transparent,
        BaselineColors.teal.atOpacity(intensity),
        Colors.transparent,
      ],
      [0.0, 0.5, 1.0],
    );

    canvas.drawRect(
      Rect.fromLTWH(
        beamX - _kScanlineHalfW,
        trackY - 1,
        _kScanlineHalfW * 2,
        _kTrackHeight + 2,
      ),
      Paint()..shader = gradient,
    );
  }

  // ── Instrument designation stamp ──────────────────────

  void _paintDesignation(Canvas canvas, double trackW, double trackY) {
    final tp = _getDesignationPainter();
    // Position: upper-right of gauge area, just above track.
    tp.paint(canvas, Offset(trackW - tp.width, trackY - tp.height - 0.5));
  }

  @override
  bool shouldRepaint(_GaugePainter old) =>
      old.fillFraction != fillFraction ||
      old.hasValue != hasValue ||
      old.tealIntensity != tealIntensity ||
      old.animProgress != animProgress ||
      old.isEntry != isEntry;
}
