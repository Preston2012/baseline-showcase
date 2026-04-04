/// F2.4 -- Lens Toggle (ALL/GP/CL/GR) -- LOCKED
///
/// 4-segment classified filter wheel for switching between
/// consensus (ALL) and individual model wavelengths (GP/CL/GR).
///
/// Concept: rotating between analytical wavelengths on an optical
/// bench. The indicator slides like a filter selector with mechanical
/// detent notches at each position. Ticks along the bottom are a
/// wavelength ruler with calibration endpoint dots. Disabled lenses
/// show void hatch (classified redaction). Inside the active filter:
/// concentric lens element rings, 6 aperture iris blade lines, and
/// an etched wavelength designation. During slide, a spectral
/// dispersion trail follows the indicator.
///
/// 35 visual treatments. Filter wheel for the Spectral Analysis Bench.
///
/// CRITICAL: Always 4 segments. ALL is UI-only, never sent to backend.
///
/// Usage:
///   LensToggle(
///     selected: kLensAll,
///     onChanged: (lens) => ref.read(lensProvider.notifier).set(lens),
///   )
///   LensToggle(
///     selected: kLensGP,
///     availableLenses: {'GP', 'CL'}, // GR missing from analysis
///     onChanged: (lens) => ...,
///   )
///
/// Path: lib/widgets/lens_toggle.dart
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:baseline_app/config/theme.dart';
import 'package:baseline_app/config/constants.dart';
import 'package:baseline_app/utils/haptic_util.dart';

// ═══════════════════════════════════════════════════════════
// CONSTANTS
// ═══════════════════════════════════════════════════════════

// ── Geometry ─────────────────────────────────────────────

/// Fixed height: 44px touch target.
const double _kHeight = 44.0;

/// Fixed pill width: equal for all 4 segments.
const double _kPillWidth = 60.0;

/// Number of lens segments (ALL, GP, CL, GR).
const int _kPillCount = 4;

/// Inset of the sliding indicator from outer border.
const double _kIndicatorInset = 3.0;

// ── Border & bezel ──────────────────────────────────────

/// Outer bezel stroke width.
const double _kBorderWidth = 1.5;

/// Vertical inset of separator lines from edges.
const double _kSepInsetV = 10.0;

// ── Micro-ticks (wavelength ruler) ──────────────────────

/// Ticks per pill segment.
const int _kTicksPerPill = 5;

/// Normal tick stroke width.
const double _kTickStroke = 0.5;

/// Normal tick height.
const double _kTickHeight = 3.0;

/// Cardinal tick height (at pill boundaries).
const double _kTickHeightCardinal = 5.0;

/// Distance from bottom edge to tick base.
const double _kTickBottomOffset = 4.0;

// ── Calibration endpoint dots ───────────────────────────

/// Endpoint dot radius at ruler origin + terminus.
const double _kEndpointDotRadius = 1.0;

/// Endpoint dot opacity.
const double _kEndpointDotOpacity = 0.25;

// ── Indicator glow ──────────────────────────────────────

/// Glow blur sigma behind sliding indicator.
const double _kGlowSigma = 4.0;

/// Glow opacity.
const double _kGlowOpacity = 0.35;

// ── Lens element rings ─────────────────────────────────

/// Number of concentric lens rings inside active indicator.
const int _kLensRingCount = 3;

/// Outermost lens ring radius (ratio of indicator half-height).
const double _kLensRingMaxRatio = 0.85;

/// Lens ring stroke width.
const double _kLensRingStroke = 0.3;

/// Lens ring base opacity (faint, behind text).
const double _kLensRingOpacity = 0.04;

// ── Aperture iris blades ────────────────────────────────

/// Number of iris blade lines radiating from center.
const int _kIrisBladeCount = 6;

/// Iris blade length (ratio of indicator half-height).
const double _kIrisBladeRatio = 0.65;

/// Iris blade stroke width.
const double _kIrisBladeStroke = 0.3;

/// Iris blade opacity.
const double _kIrisBladeOpacity = 0.03;

// ── Etched wavelength glyph ─────────────────────────────

/// Etched glyph font size.
const double _kEtchedLambdaSize = 10.0;

/// Etched glyph opacity (super faint, etched in glass).
const double _kEtchedLambdaOpacity = 0.035;

// ── Filter wheel detent notches ─────────────────────────

/// Detent notch radius (semicircular cutout).
const double _kDetentRadius = 1.5;

/// Detent notch opacity.
const double _kDetentOpacity = 0.08;

// ── Spectral dispersion trail ───────────────────────────

/// Dispersion trail extra width beyond indicator.
const double _kDispersionExtraWidth = 6.0;

/// Dispersion trail peak opacity.
const double _kDispersionOpacity = 0.06;

/// Dispersion trail blur sigma.
const double _kDispersionSigma = 3.0;

// ── Scanline ────────────────────────────────────────────

/// Scanline beam height during slide.
const double _kScanlineHeight = 1.0;

// ── Void hatch (disabled pills) ─────────────────────────

/// Diagonal hatch line spacing.
const double _kHatchSpacing = 3.5;

/// Hatch line stroke width.
const double _kHatchStroke = 0.3;

// ── Classification dot ──────────────────────────────────

/// Dot diameter next to active label.
const double _kDotSize = 3.0;

/// Gap between dot and label text.
const double _kDotGap = 5.0;

// ── Timing ──────────────────────────────────────────────

/// Indicator slide duration.
const Duration _kSlideDuration = Duration(milliseconds: 280);

/// Slide easing: easeOutBack gives a physical detent snap.
const Curve _kSlideCurve = Curves.easeOutBack;

/// Entry animation duration.
const Duration _kEntryDuration = Duration(milliseconds: 450);

/// Press-scale animation duration.
const Duration _kPressDuration = Duration(milliseconds: 80);

// ── Press scale ─────────────────────────────────────────

/// Scale factor when pill is pressed.
const double _kPressScale = 0.95;

// ── Tuning lock flash ───────────────────────────────────

/// Duration of the "wavelength locked" bloom after slide lands.
const Duration _kLockFlashDuration = Duration(milliseconds: 300);

/// Lock flash peak opacity.
const double _kLockFlashOpacity = 0.5;

// ── Corner registration marks ───────────────────────────

/// Arm length of each corner registration mark.
const double _kCornerArmLength = 4.0;

/// Stroke width for corner marks.
const double _kCornerStroke = 0.6;

/// Inset from outer edge.
const double _kCornerInset = 5.0;

// ── Indicator highlight ─────────────────────────────────

/// Hair-thin top-edge highlight opacity.
const double _kHighlightOpacity = 0.3;

// ── Wavelength labels ───────────────────────────────────

/// Wavelength marker labels at pill boundaries.
const List<String> _kWavelengthLabels = ['λ₁', 'λ₂', 'λ₃'];

/// Wavelength label font size.
const double _kWavelengthFontSize = 5.0;

/// Wavelength label opacity.
const double _kWavelengthOpacity = 0.10;

// ═══════════════════════════════════════════════════════════
// LENS TOGGLE WIDGET
// ═══════════════════════════════════════════════════════════

class LensToggle extends StatefulWidget {
  const LensToggle({
    super.key,
    required this.selected,
    required this.onChanged,
    this.availableLenses,
  }) : assert(
          selected == kLensAll ||
              selected == kLensGP ||
              selected == kLensCL ||
              selected == kLensGR,
        );

  /// Currently selected lens code.
  final String selected;

  /// Callback when user taps a different lens.
  final ValueChanged<String> onChanged;

  /// If provided, only these lenses + ALL are enabled.
  /// Others shown disabled with void hatch.
  final Set<String>? availableLenses;

  /// Ordered lens codes: canonical.
  static const lenses = [kLensAll, kLensGP, kLensCL, kLensGR];

  @override
  State<LensToggle> createState() => _LensToggleState();
}

class _LensToggleState extends State<LensToggle>
    with TickerProviderStateMixin {
  late final AnimationController _slideCtrl;
  late final AnimationController _entryCtrl;
  late final AnimationController _lockCtrl;
  late Animation<double> _slideAnim;
  late final bool _reduceMotion;

  @override
  void initState() {
    super.initState();
    _reduceMotion = ui.PlatformDispatcher.instance
        .accessibilityFeatures.reduceMotion;

    final idx = _indexFor(widget.selected);

    _slideCtrl = AnimationController(
      vsync: this,
      duration: _kSlideDuration,
    );
    _slideCtrl.addStatusListener(_onSlideStatus);
    _slideAnim = AlwaysStoppedAnimation(idx.toDouble());

    _entryCtrl = AnimationController(
      vsync: this,
      duration: _kEntryDuration,
    );

    _lockCtrl = AnimationController(
      vsync: this,
      duration: _kLockFlashDuration,
    );

    if (_reduceMotion) {
      _entryCtrl.value = 1.0;
    } else {
      _entryCtrl.forward();
    }
  }

  void _onSlideStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && !_reduceMotion) {
      _lockCtrl.forward(from: 0.0);
    }
  }

  @override
  void didUpdateWidget(LensToggle old) {
    super.didUpdateWidget(old);
    if (old.selected != widget.selected) {
      _slideTo(_indexFor(widget.selected));
    }
  }

  @override
  void dispose() {
    _slideCtrl.removeStatusListener(_onSlideStatus);
    _slideCtrl.dispose();
    _entryCtrl.dispose();
    _lockCtrl.dispose();
    super.dispose();
  }

  // ── Animation ─────────────────────────────────────────

  void _slideTo(int newIndex) {
    if (_reduceMotion) {
      _slideAnim = AlwaysStoppedAnimation(newIndex.toDouble());
      if (mounted) setState(() {});
      return;
    }
    _slideAnim = Tween<double>(
      begin: _slideAnim.value,
      end: newIndex.toDouble(),
    ).animate(CurvedAnimation(
      parent: _slideCtrl,
      curve: _kSlideCurve,
    ));
    _slideCtrl.forward(from: 0.0);
  }

  // ── Helpers ───────────────────────────────────────────

  int _indexFor(String lens) =>
      LensToggle.lenses.indexOf(lens).clamp(0, _kPillCount - 1);

  bool _isEnabled(String lens) {
    if (lens == kLensAll) return true;
    return widget.availableLenses?.contains(lens) ?? true;
  }

  void _onTap(String lens) {
    if (lens == widget.selected || !_isEnabled(lens)) return;
    HapticUtil.selection();
    widget.onChanged(lens);
  }

  Set<int> get _disabledIndices {
    if (widget.availableLenses == null) return {};
    final d = <int>{};
    for (int i = 1; i < LensToggle.lenses.length; i++) {
      if (!widget.availableLenses!.contains(LensToggle.lenses[i])) {
        d.add(i);
      }
    }
    return d;
  }

  // ── Build ─────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Semantics(
        label: 'Lens selector, ${_semanticFor(widget.selected)} selected',
        child: AnimatedBuilder(
          animation: Listenable.merge([_slideCtrl, _entryCtrl, _lockCtrl]),
          builder: (context, _) {
            final entry = _entryCtrl.value;

            return Opacity(
              opacity: entry,
              child: Transform.scale(
                scale: 0.92 + 0.08 * entry,
                child: SizedBox(
                  width: _kPillWidth * _kPillCount,
                  height: _kHeight,
                  child: Stack(
                    children: [
                      // Layer 0: CustomPaint chrome
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _TogglePainter(
                            position: _slideAnim.value,
                            isSliding: _slideCtrl.isAnimating,
                            slideProgress: _slideCtrl.isAnimating
                                ? _slideCtrl.value
                                : 1.0,
                            entry: entry,
                            disabled: _disabledIndices,
                            lockFlash: _lockCtrl.value,
                          ),
                        ),
                      ),
                      // Layer 1: Touch targets + labels
                      Positioned.fill(
                        child: Row(
                          children: List.generate(_kPillCount, (i) {
                            final lens = LensToggle.lenses[i];
                            return SizedBox(
                              width: _kPillWidth,
                              height: _kHeight,
                              child: _PillTarget(
                                code: lens,
                                isSelected: i == _indexFor(widget.selected),
                                isEnabled: _isEnabled(lens),
                                onTap: () => _onTap(lens),
                              ),
                            );
                          }),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  static String _semanticFor(String code) => switch (code) {
        kLensAll => 'All lenses',
        kLensGP => 'GP lens',
        kLensCL => 'CL lens',
        kLensGR => 'GR lens',
        _ => code,
      };
}

// ═══════════════════════════════════════════════════════════
// PILL TOUCH TARGET (press-scale + label)
// ═══════════════════════════════════════════════════════════

class _PillTarget extends StatefulWidget {
  const _PillTarget({
    required this.code,
    required this.isSelected,
    required this.isEnabled,
    required this.onTap,
  });

  final String code;
  final bool isSelected;
  final bool isEnabled;
  final VoidCallback onTap;

  @override
  State<_PillTarget> createState() => _PillTargetState();
}

class _PillTargetState extends State<_PillTarget> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: _semanticLabel,
      selected: widget.isSelected,
      enabled: widget.isEnabled,
      button: true,
      child: GestureDetector(
        onTapDown: widget.isEnabled
            ? (_) => setState(() => _pressed = true)
            : null,
        onTapUp: widget.isEnabled
            ? (_) => setState(() => _pressed = false)
            : null,
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.isEnabled ? widget.onTap : null,
        behavior: HitTestBehavior.opaque,
        child: AnimatedScale(
          scale: _pressed ? _kPressScale : 1.0,
          duration: _kPressDuration,
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Classification dot: active lens only.
                if (widget.isSelected) ...[
                  Container(
                    width: _kDotSize,
                    height: _kDotSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: BaselineColors.background.atOpacity(0.7),
                    ),
                  ),
                  const SizedBox(width: _kDotGap),
                ],
                Text(
                  widget.code,
                  style: BaselineTypography.data.copyWith(
                    color: _textColor,
                    fontSize: 12,
                    fontWeight: widget.isSelected
                        ? FontWeight.w600
                        : FontWeight.w400,
                    letterSpacing: 1.0,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color get _textColor {
    if (!widget.isEnabled) {
      return BaselineColors.textSecondary.atOpacity(0.3);
    }
    if (widget.isSelected) return BaselineColors.background;
    return BaselineColors.textSecondary;
  }

  String get _semanticLabel {
    final base = switch (widget.code) {
      kLensAll => 'All lenses',
      kLensGP => 'GP lens',
      kLensCL => 'CL lens',
      kLensGR => 'GR lens',
      _ => widget.code,
    };
    if (!widget.isEnabled) return '$base, not available';
    return base;
  }
}

// ═══════════════════════════════════════════════════════════
// CUSTOM PAINTER: ALL VISUAL CHROME
// ═══════════════════════════════════════════════════════════

class _TogglePainter extends CustomPainter {
  _TogglePainter({
    required this.position,
    required this.isSliding,
    required this.slideProgress,
    required this.entry,
    required this.disabled,
    required this.lockFlash,
  });

  /// Current indicator position (0.0 = ALL, 3.0 = GR).
  final double position;

  /// Whether the indicator is currently animating.
  final bool isSliding;

  /// 0-1 progress of the current slide animation.
  final double slideProgress;

  /// Entry animation progress (0-1).
  final double entry;

  /// Set of disabled pill indices.
  final Set<int> disabled;

  /// Lock flash progress (0-1, fades out). Fires when slide lands.
  final double lockFlash;

  @override
  void paint(Canvas canvas, Size size) {
    final pw = size.width / _kPillCount;
    final radius = Radius.circular(size.height / 2);
    final outer = RRect.fromRectAndRadius(Offset.zero & size, radius);

    // ── Clip to capsule ──────────────────────────────────
    canvas.save();
    canvas.clipRRect(outer);

    // 1. Background fill
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = BaselineColors.card,
    );

    // 2. Spectral dispersion trail (during slide, behind indicator)
    if (isSliding) {
      _paintDispersionTrail(canvas, size, pw);
    }

    // 3. Sliding indicator + glow + lens rings + iris + glyph
    _paintIndicator(canvas, size, pw);

    // 3b. Lock flash bloom (after indicator, before hatch)
    if (lockFlash > 0.0) {
      _paintLockFlash(canvas, size, pw);
    }

    // 4. Void hatch on disabled pills
    for (final i in disabled) {
      _paintHatch(canvas, i * pw, pw, size.height);
    }

    // 5. Separator lines
    _paintSeparators(canvas, size, pw);

    // 6. Filter wheel detent notches at pill boundaries
    _paintDetentNotches(canvas, size, pw);

    // 7. Wavelength tick ruler + calibration endpoint dots
    _paintTicks(canvas, size, pw);
    _paintEndpointDots(canvas, size);

    // 7b. Wavelength markers at pill boundaries
    _paintWavelengthMarkers(canvas, size, pw);

    // 8. Scanline during slide
    if (isSliding) {
      _paintScanline(canvas, size, pw);
    }

    canvas.restore();

    // 9. Outer bezel (after clip restore: draws on border)
    canvas.drawRRect(
      outer.deflate(_kBorderWidth / 2),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _kBorderWidth
        ..color = BaselineColors.teal.atOpacity(0.12 + 0.08 * entry),
    );

    // 10. Corner registration marks (outside clip, on top of bezel)
    _paintCornerMarks(canvas, size);
  }

  // ── Indicator (glow + fill + lens rings + iris + glyph + highlight) ──

  void _paintIndicator(Canvas canvas, Size size, double pw) {
    final inset = _kIndicatorInset;
    final left = position * pw + inset;
    final w = pw - inset * 2;
    final h = size.height - inset * 2;
    final centerX = left + w / 2;
    final centerY = size.height / 2;

    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(left, inset, w, h),
      Radius.circular(h / 2),
    );

    // Glow bloom
    canvas.drawRRect(
      rrect.inflate(2),
      Paint()
        ..color = BaselineColors.teal.atOpacity(_kGlowOpacity)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, _kGlowSigma),
    );

    // Solid teal fill
    canvas.drawRRect(rrect, Paint()..color = BaselineColors.teal);

    // Concentric lens element rings (behind text, optical bench DNA)
    final maxR = (h / 2) * _kLensRingMaxRatio;
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _kLensRingStroke
      ..color = BaselineColors.white.atOpacity(_kLensRingOpacity);

    for (int i = 0; i < _kLensRingCount; i++) {
      final ratio = (i + 1) / _kLensRingCount;
      canvas.drawCircle(
        Offset(centerX, centerY),
        maxR * ratio,
        ringPaint,
      );
    }

    // Aperture iris blades: 6 radial lines from center
    final irisR = (h / 2) * _kIrisBladeRatio;
    final irisPaint = Paint()
      ..strokeWidth = _kIrisBladeStroke
      ..color = BaselineColors.white.atOpacity(_kIrisBladeOpacity)
      ..strokeCap = StrokeCap.round;

    for (int i = 0; i < _kIrisBladeCount; i++) {
      final angle = (2 * math.pi * i / _kIrisBladeCount);
      canvas.drawLine(
        Offset(centerX, centerY),
        Offset(
          centerX + irisR * math.cos(angle),
          centerY + irisR * math.sin(angle),
        ),
        irisPaint,
      );
    }

    // Etched wavelength glyph (super faint, etched in lens glass)
    final lambdaTp = TextPainter(
      text: TextSpan(
        text: 'λ',
        style: TextStyle(
          fontFamily: BaselineTypography.monoFontFamily,
          fontSize: _kEtchedLambdaSize,
          color: BaselineColors.white.atOpacity(_kEtchedLambdaOpacity),
          fontWeight: FontWeight.w300,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    lambdaTp.paint(
      canvas,
      Offset(centerX - lambdaTp.width / 2, centerY - lambdaTp.height / 2),
    );
    lambdaTp.dispose();

    // Leading-edge bright cap (subtle white bloom at right edge)
    final capX = left + w - 2;
    canvas.drawCircle(
      Offset(capX, centerY),
      2.0,
      Paint()
        ..color = BaselineColors.white.atOpacity(0.25)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );

    // Top-edge highlight: hair-thin machined aluminum feel
    final highlightPath = Path()
      ..addArc(
        Rect.fromLTWH(left, inset, w, h),
        math.pi + 0.4,
        math.pi - 0.8,
      );
    canvas.drawPath(
      highlightPath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5
        ..color = BaselineColors.white.atOpacity(_kHighlightOpacity),
    );
  }

  // ── Spectral dispersion trail ─────────────────────────

  void _paintDispersionTrail(Canvas canvas, Size size, double pw) {
    final intensity = (1.0 - slideProgress).clamp(0.0, 1.0);
    if (intensity < 0.01) return;

    final inset = _kIndicatorInset;
    final left = position * pw + inset;
    final w = pw - inset * 2 + _kDispersionExtraWidth;
    final h = size.height - inset * 2;

    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(left - _kDispersionExtraWidth / 2, inset, w, h),
      Radius.circular(h / 2),
    );

    canvas.drawRRect(
      rrect,
      Paint()
        ..color = BaselineColors.teal.atOpacity(
          _kDispersionOpacity * intensity,
        )
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, _kDispersionSigma),
    );
  }

  // ── Separators ────────────────────────────────────────

  void _paintSeparators(Canvas canvas, Size size, double pw) {
    final paint = Paint()..strokeWidth = 0.5;

    for (int i = 1; i < _kPillCount; i++) {
      final x = i * pw;

      // Fade separator when indicator overlaps it.
      final indicatorLeft = position;
      final indicatorRight = position + 1.0;
      final sepPos = i.toDouble();

      double opacity;
      if (sepPos >= indicatorLeft && sepPos <= indicatorRight) {
        opacity = 0.0;
      } else {
        final dist = math.min(
          (sepPos - indicatorLeft).abs(),
          (sepPos - indicatorRight).abs(),
        );
        opacity = (dist * 2.0).clamp(0.0, 1.0);
      }

      paint.color = BaselineColors.borderInactive.atOpacity(0.5 * opacity);

      canvas.drawLine(
        Offset(x, _kSepInsetV),
        Offset(x, size.height - _kSepInsetV),
        paint,
      );
    }
  }

  // ── Filter wheel detent notches ───────────────────────

  void _paintDetentNotches(Canvas canvas, Size size, double pw) {
    if (entry < 0.01) return;

    final paint = Paint()
      ..color = BaselineColors.teal.atOpacity(_kDetentOpacity * entry);

    for (int i = 1; i < _kPillCount; i++) {
      final x = i * pw;

      // Tiny semicircular cutout at top edge.
      canvas.drawArc(
        Rect.fromCenter(
          center: Offset(x, 0),
          width: _kDetentRadius * 2,
          height: _kDetentRadius * 2,
        ),
        0,
        math.pi,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.5
          ..color = BaselineColors.teal.atOpacity(_kDetentOpacity * entry),
      );

      // Tiny filled dot at detent center.
      canvas.drawCircle(
        Offset(x, _kDetentRadius * 0.5),
        0.5,
        paint,
      );
    }
  }

  // ── Wavelength tick ruler ─────────────────────────────

  void _paintTicks(Canvas canvas, Size size, double pw) {
    final totalTicks = _kTicksPerPill * _kPillCount;
    final tickSpacing = size.width / totalTicks;
    final bottom = size.height - _kTickBottomOffset;
    final paint = Paint()..strokeWidth = _kTickStroke;

    for (int i = 0; i <= totalTicks; i++) {
      final x = i * tickSpacing;
      final isCardinal = i % _kTicksPerPill == 0;
      final h = isCardinal ? _kTickHeightCardinal : _kTickHeight;

      // Brightness ramps near indicator center.
      final indicatorCenter = (position + 0.5) * pw;
      final distFromCenter = (x - indicatorCenter).abs() / pw;
      final brightness = distFromCenter < 1.0
          ? 0.35 + 0.15 * (1.0 - distFromCenter)
          : 0.15;

      paint.color = BaselineColors.teal.atOpacity(brightness * entry);

      canvas.drawLine(
        Offset(x, bottom),
        Offset(x, bottom - h),
        paint,
      );
    }
  }

  // ── Calibration endpoint dots ─────────────────────────

  void _paintEndpointDots(Canvas canvas, Size size) {
    if (entry < 0.01) return;

    final bottom = size.height - _kTickBottomOffset;
    final paint = Paint()
      ..color = BaselineColors.teal.atOpacity(_kEndpointDotOpacity * entry);

    // Origin dot (left edge).
    canvas.drawCircle(
      Offset(0, bottom - _kTickHeightCardinal / 2),
      _kEndpointDotRadius,
      paint,
    );

    // Terminus dot (right edge).
    canvas.drawCircle(
      Offset(size.width, bottom - _kTickHeightCardinal / 2),
      _kEndpointDotRadius,
      paint,
    );
  }

  // ── Wavelength markers at pill boundaries ──────────────

  void _paintWavelengthMarkers(Canvas canvas, Size size, double pw) {
    if (entry < 0.01) return;

    for (int i = 0; i < _kWavelengthLabels.length; i++) {
      final x = (i + 1) * pw;
      final y = size.height - _kTickBottomOffset + 1;

      final tp = TextPainter(
        text: TextSpan(
          text: _kWavelengthLabels[i],
          style: TextStyle(
            fontFamily: BaselineTypography.monoFontFamily,
            fontSize: _kWavelengthFontSize,
            color: BaselineColors.teal.atOpacity(_kWavelengthOpacity * entry),
            letterSpacing: 0.5,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      tp.paint(canvas, Offset(x - tp.width / 2, y));
      tp.dispose();
    }
  }

  // ── Void hatch (disabled) ─────────────────────────────

  void _paintHatch(Canvas canvas, double left, double w, double h) {
    final paint = Paint()
      ..strokeWidth = _kHatchStroke
      ..color = BaselineColors.textSecondary.atOpacity(0.06);

    for (double offset = -h; offset < w; offset += _kHatchSpacing) {
      canvas.drawLine(
        Offset(left + offset, h),
        Offset(left + offset + h, 0),
        paint,
      );
    }
  }

  // ── Scanline ──────────────────────────────────────────

  void _paintScanline(Canvas canvas, Size size, double pw) {
    final y = size.height / 2;
    final indicatorCenter = (position + 0.5) * pw;
    final halfWidth = pw * 0.7;

    final intensity = (1.0 - slideProgress).clamp(0.0, 1.0);
    if (intensity < 0.01) return;

    final gradient = ui.Gradient.linear(
      Offset(indicatorCenter - halfWidth, y),
      Offset(indicatorCenter + halfWidth, y),
      [
        Colors.transparent,
        BaselineColors.teal.atOpacity(0.3 * intensity),
        Colors.transparent,
      ],
      [0.0, 0.5, 1.0],
    );

    canvas.drawRect(
      Rect.fromCenter(
        center: Offset(indicatorCenter, y),
        width: halfWidth * 2,
        height: _kScanlineHeight,
      ),
      Paint()..shader = gradient,
    );
  }

  // ── Lock flash (wavelength locked bloom) ──────────────

  void _paintLockFlash(Canvas canvas, Size size, double pw) {
    final fade = 1.0 - lockFlash;
    if (fade < 0.01) return;

    final inset = _kIndicatorInset;
    final left = position * pw + inset;
    final w = pw - inset * 2;
    final h = size.height - inset * 2;

    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(left, inset, w, h),
      Radius.circular(h / 2),
    );

    canvas.drawRRect(
      rrect.inflate(4),
      Paint()
        ..color = BaselineColors.teal.atOpacity(
          _kLockFlashOpacity * fade,
        )
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
  }

  // ── Corner registration marks ─────────────────────────

  void _paintCornerMarks(Canvas canvas, Size size) {
    final opacity = 0.2 * entry;
    if (opacity < 0.01) return;

    final paint = Paint()
      ..strokeWidth = _kCornerStroke
      ..color = BaselineColors.teal.atOpacity(opacity)
      ..strokeCap = StrokeCap.round;

    final i = _kCornerInset;
    final a = _kCornerArmLength;

    // Top-left
    canvas.drawLine(Offset(i, i), Offset(i + a, i), paint);
    canvas.drawLine(Offset(i, i), Offset(i, i + a), paint);

    // Top-right
    canvas.drawLine(Offset(size.width - i, i), Offset(size.width - i - a, i), paint);
    canvas.drawLine(Offset(size.width - i, i), Offset(size.width - i, i + a), paint);

    // Bottom-left
    canvas.drawLine(Offset(i, size.height - i), Offset(i + a, size.height - i), paint);
    canvas.drawLine(Offset(i, size.height - i), Offset(i, size.height - i - a), paint);

    // Bottom-right
    canvas.drawLine(
      Offset(size.width - i, size.height - i),
      Offset(size.width - i - a, size.height - i),
      paint,
    );
    canvas.drawLine(
      Offset(size.width - i, size.height - i),
      Offset(size.width - i, size.height - i - a),
      paint,
    );
  }

  // ── Repaint optimization ──────────────────────────────

  @override
  bool shouldRepaint(_TogglePainter old) =>
      position != old.position ||
      isSliding != old.isSliding ||
      slideProgress != old.slideProgress ||
      entry != old.entry ||
      disabled != old.disabled ||
      lockFlash != old.lockFlash;
}
