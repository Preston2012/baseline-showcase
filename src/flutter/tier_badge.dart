/// F2.7 - Tier Badge (Clearance Level Pill) - LOCKED
///
/// Your building ID. Security clearance badge that appears on profiles,
/// paywalls, feature gates, popups. One of the most visible widgets in
/// the entire app. Every tier must visually sell its value.
///
/// Concept: holographic government credential.
/// CORE = standard access (circuit trace, whisper).
/// PRO = elevated clearance (inner glow, magnetic data stripe, confident).
/// PRO+ = top secret (holographic shimmer, breathing glow, embossed "+",
///         micro-credential, scanline verification). The Amex Black Card.
/// B2B = institutional authority (double-rule, stamp brackets, widest spacing).
///
/// PRO+ has holographic presence. It shimmers. It breathes. The glow
/// pulses gently like a heartbeat. When it mounts, a scanline verifies
/// the credential, then a spectral band sweeps through like tilting a
/// holographic sticker. It is unmistakably premium.
///
/// 40 visual treatments. Nobody else has this on a subscription badge.
///
/// Usage:
///   TierBadge(tier: 'pro')
///   TierBadge(tier: 'pro_plus')
///   TierBadge(tier: 'free')
///
/// Data source: kTierDisplayNames from constants.dart.
///
/// Path: lib/widgets/tier_badge.dart
library;

// 1. Dart SDK
import 'dart:math' as math;
import 'dart:ui' show PlatformDispatcher;

// 2. Flutter
import 'package:flutter/material.dart';

// 3. Project ── config
import 'package:baseline_app/config/theme.dart';
import 'package:baseline_app/config/constants.dart';

// ═══════════════════════════════════════════════════════════
// CONSTANTS
// ═══════════════════════════════════════════════════════════

// ── Pill geometry ───────────────────────────────────────

const double _kPillRadius = 11.0;
const double _kHPadding = 10.0;
const double _kVPadding = 3.0;

// ── Border widths ───────────────────────────────────────

/// CORE uses 1px borderInactive (whisper tier). Intentional design
/// hierarchy: CORE < PRO/B2B (2px teal). Not a doctrine violation.
const double _kCoreBorderWidth = 1.0;

// ── Entry + scanline + holographic timing ───────────────

/// Entry fade.
const Duration _kEntryDuration = Duration(milliseconds: 250);

/// Scanline sweep (PRO+ only).
const Duration _kScanDuration = Duration(milliseconds: 500);

/// Holographic shimmer sweep (PRO+ only, after scanline).
const Duration _kHoloDuration = Duration(milliseconds: 600);

/// Ambient breathing cycle (PRO+ only, loops).
const Duration _kBreathDuration = Duration(milliseconds: 3500);

// ── PRO+ glow ───────────────────────────────────────────

const double _kGlowBlur = 6.0;
const double _kGlowOpacityBase = 0.12;
const double _kGlowOpacityPeak = 0.22;

// ── PRO+ edge highlight ─────────────────────────────────

/// Decorative machined catch-light, not structural border.
/// Same ruling as F2.5/F2.6 inner chrome borders.
const double _kEdgeHighlightWidth = 0.5;
const double _kEdgeHighlightOpacity = 0.30;

// ── PRO+ gradient ───────────────────────────────────────

const Color _kProPlusFillStart = BaselineColors.teal;
const Color _kProPlusFillEnd = Color(0xFF3DE0CC); // teal +8% lightness

// ── PRO+ scanline beam ──────────────────────────────────

const double _kScanBeamWidth = 20.0;
const double _kScanBeamOpacity = 0.25;

// ── PRO+ holographic shimmer ────────────────────────────

/// Width of the spectral band that sweeps across.
const double _kHoloBeamWidth = 30.0;

/// Holographic band peak opacity.
const double _kHoloOpacity = 0.12;

/// Spectral hue shift: teal → blue-teal → back.
const Color _kHoloColorA = BaselineColors.spectralTeal; // teal
const Color _kHoloColorB = BaselineColors.spectralCyan; // blue-teal shift
const Color _kHoloColorC = Color(0xFF5d8dd4); // blue shift

// ── PRO+ embossed "+" ───────────────────────────────────

const double _kEmbossSize = 14.0;
const double _kEmbossOpacity = 0.03;
const double _kEmbossStroke = 1.5;

// ── PRO+ micro-credential ───────────────────────────────

const String _kProPlusCred = 'SEC\u00B7CLR:MAX';
const double _kCredFontSize = 4.0;
const double _kCredOpacity = 0.06;
const double _kCredBottomOffset = 2.5;

// ── PRO inner glow ──────────────────────────────────────

const double _kProInnerGlowOpacity = 0.08;

// ── PRO corner dots ─────────────────────────────────────

const double _kCornerDotSize = 1.0;
const double _kCornerDotOpacity = 0.50;

// ── PRO magnetic data stripe ────────────────────────────

const int _kStripeLineCount = 10;
const double _kStripeLineWidth = 0.5;
const double _kStripeMaxHeight = 4.0;
const double _kStripeMinHeight = 1.5;
const double _kStripeSpacing = 1.5;
const double _kStripeOpacity = 0.15;
const double _kStripeBottomOffset = 3.0;

// ── B2B hashmark ticks ──────────────────────────────────

const double _kHashTickWidth = 3.0;
const double _kHashTickHeight = 1.0;
const double _kHashTickSpacing = 3.0;
const int _kHashTickCount = 3;
const double _kHashTickOpacity = 0.35;

// ── B2B institutional brackets ──────────────────────────

const double _kStampBracketArm = 3.0;
const double _kStampBracketStroke = 0.5;
const double _kStampBracketOpacity = 0.20;
const double _kStampBracketInset = 3.0;

// ── B2B double-rule ─────────────────────────────────────

const double _kInnerRuleInset = 3.5;
const double _kInnerRuleStroke = 0.3;
const double _kInnerRuleOpacity = 0.10;

// ── CORE classification dot ─────────────────────────────

const double _kClassDotSize = 1.5;
const double _kClassDotOpacity = 0.40;

// ── CORE circuit trace ──────────────────────────────────

const double _kCircuitTraceStroke = 0.3;
const double _kCircuitTraceOpacity = 0.03;

// ── Letter-spacing per tier ─────────────────────────────

const double _kCoreLetterSpacing = 0.8;
const double _kProLetterSpacing = 1.0;
const double _kProPlusLetterSpacing = 1.4;
const double _kB2BLetterSpacing = 1.8;

// ═══════════════════════════════════════════════════════════
// TIER CONFIG
// ═══════════════════════════════════════════════════════════

enum _TierLevel { core, pro, proPlus, b2b }

class _TierConfig {
  const _TierConfig({
    required this.level,
    required this.textColor,
    required this.letterSpacing,
  });

  final _TierLevel level;
  final Color textColor;
  final double letterSpacing;

  static const core = _TierConfig(
    level: _TierLevel.core,
    textColor: BaselineColors.textSecondary,
    letterSpacing: _kCoreLetterSpacing,
  );

  static const pro = _TierConfig(
    level: _TierLevel.pro,
    textColor: BaselineColors.teal,
    letterSpacing: _kProLetterSpacing,
  );

  static const proPlus = _TierConfig(
    level: _TierLevel.proPlus,
    textColor: BaselineColors.background,
    letterSpacing: _kProPlusLetterSpacing,
  );

  static const b2b = _TierConfig(
    level: _TierLevel.b2b,
    textColor: BaselineColors.teal,
    letterSpacing: _kB2BLetterSpacing,
  );

  static _TierConfig fromKey(String tier) {
    switch (tier) {
      case 'free':
        return core;
      case 'pro':
        return pro;
      case 'pro_plus':
        return proPlus;
      case 'b2b':
        return b2b;
      default:
        assert(false, 'Unexpected tier: $tier');
        return core;
    }
  }
}

// ═══════════════════════════════════════════════════════════
// WIDGET
// ═══════════════════════════════════════════════════════════

class TierBadge extends StatefulWidget {
  const TierBadge({
    super.key,
    String? tier,
    String? tierKey,
  }) : tier = tier ?? tierKey ?? '';

  /// Tier key from backend: 'free', 'pro', 'pro_plus', 'b2b'.
  final String tier;

  @override
  State<TierBadge> createState() => _TierBadgeState();
}

class _TierBadgeState extends State<TierBadge>
    with TickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _entryAnim;
  late final Animation<double> _scanAnim;
  late final Animation<double> _holoAnim;

  /// Ambient breathing controller (PRO+ only, loops).
  AnimationController? _breathCtrl;

  late final bool _reduceMotion;

  @override
  void initState() {
    super.initState();
    _reduceMotion = PlatformDispatcher
        .instance.accessibilityFeatures.reduceMotion;

    final isProPlus = widget.tier == 'pro_plus';

    // ── One-shot sequence controller ──────────────────
    final totalDuration = isProPlus && !_reduceMotion
        ? _kEntryDuration + _kScanDuration + _kHoloDuration
        : _kEntryDuration;

    _ctrl = AnimationController(vsync: this, duration: totalDuration);

    final totalMs = totalDuration.inMilliseconds;

    // Entry fade.
    final entryEnd = isProPlus
        ? _kEntryDuration.inMilliseconds / totalMs
        : 1.0;
    _entryAnim = CurvedAnimation(
      parent: _ctrl,
      curve: Interval(0.0, entryEnd, curve: Curves.easeOut),
    );

    // Scanline (PRO+ only).
    if (isProPlus) {
      final scanEnd = (_kEntryDuration.inMilliseconds +
              _kScanDuration.inMilliseconds) /
          totalMs;
      _scanAnim = CurvedAnimation(
        parent: _ctrl,
        curve: Interval(entryEnd, scanEnd, curve: Curves.easeInOut),
      );

      // Holographic shimmer (after scanline).
      _holoAnim = CurvedAnimation(
        parent: _ctrl,
        curve: Interval(scanEnd, 1.0, curve: Curves.easeInOut),
      );
    } else {
      _scanAnim = const AlwaysStoppedAnimation(0.0);
      _holoAnim = const AlwaysStoppedAnimation(0.0);
    }

    // ── Ambient breathing controller (PRO+ only) ─────
    if (isProPlus && !_reduceMotion) {
      _breathCtrl = AnimationController(
        vsync: this,
        duration: _kBreathDuration,
      )..repeat(reverse: true);
    }

    if (_reduceMotion) {
      _ctrl.value = 1.0;
    } else {
      _ctrl.forward();
    }
  }

  @override
  void dispose() {
    _breathCtrl?.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final config = _TierConfig.fromKey(widget.tier);
    final label =
        kTierDisplayNames[widget.tier] ?? kTierDisplayNames['free'] ?? 'CORE';

    final listenables = <Listenable>[_ctrl];
    if (_breathCtrl != null) listenables.add(_breathCtrl!);

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: Listenable.merge(listenables),
        builder: (context, child) {
          return FadeTransition(
            opacity: _entryAnim,
            child: Semantics(
              container: true,
              label: 'Tier',
              value: label,
              child: ExcludeSemantics(
                child: CustomPaint(
                  painter: _TierBadgePainter(
                    config: config,
                    scanProgress: _scanAnim,
                    holoProgress: _holoAnim,
                    entryProgress: _entryAnim,
                    breathValue: _breathCtrl?.value ?? 0.0,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: _kHPadding,
                      vertical: _kVPadding,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // CORE classification dot prefix.
                        if (config.level == _TierLevel.core) ...[
                          Container(
                            width: _kClassDotSize,
                            height: _kClassDotSize,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: BaselineColors.textSecondary
                                  .atOpacity(_kClassDotOpacity),
                            ),
                          ),
                          const SizedBox(width: 4),
                        ],
                        Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: BaselineTypography.dataSmall.copyWith(
                            color: config.textColor,
                            fontWeight: FontWeight.w600,
                            letterSpacing: config.letterSpacing,
                          ),
                        ),
                      ],
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
}

// ═══════════════════════════════════════════════════════════
// PAINTER
// ═══════════════════════════════════════════════════════════

class _TierBadgePainter extends CustomPainter {
  _TierBadgePainter({
    required this.config,
    required this.scanProgress,
    required this.holoProgress,
    required this.entryProgress,
    required this.breathValue,
  });

  final _TierConfig config;
  final Animation<double> scanProgress;
  final Animation<double> holoProgress;
  final Animation<double> entryProgress;

  /// 0→1→0 breathing sine for PRO+ glow pulse.
  final double breathValue;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect =
        RRect.fromRectAndRadius(rect, const Radius.circular(_kPillRadius));

    switch (config.level) {
      case _TierLevel.core:
        _paintCore(canvas, size, rrect);
      case _TierLevel.pro:
        _paintPro(canvas, size, rrect);
      case _TierLevel.proPlus:
        _paintProPlus(canvas, size, rrect, rect);
      case _TierLevel.b2b:
        _paintB2B(canvas, size, rrect);
    }
  }

  // ── CORE: whisper ──────────────────────────────────────

  void _paintCore(Canvas canvas, Size size, RRect rrect) {
    // 1px borderInactive outline.
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = BaselineColors.borderInactive
        ..style = PaintingStyle.stroke
        ..strokeWidth = _kCoreBorderWidth,
    );

    // Circuit trace: standard clearance level indicator.
    canvas.drawLine(
      Offset(_kPillRadius, size.height / 2),
      Offset(size.width - _kPillRadius, size.height / 2),
      Paint()
        ..strokeWidth = _kCircuitTraceStroke
        ..color = BaselineColors.textSecondary.atOpacity(_kCircuitTraceOpacity),
    );
  }

  // ── PRO: confident outline + inner glow + data stripe ──

  void _paintPro(Canvas canvas, Size size, RRect rrect) {
    final bw = BaselineCardStyle.borderWidth; // 2px

    // Inner glow: radial gradient, lit from within.
    canvas.save();
    canvas.clipRRect(rrect);
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = RadialGradient(
          center: Alignment.center,
          radius: 1.0,
          colors: [
            BaselineColors.teal.atOpacity(_kProInnerGlowOpacity),
            BaselineColors.teal.atOpacity(0.0),
          ],
        ).createShader(Offset.zero & size),
    );

    // Magnetic data stripe: barcode lines along bottom inner edge.
    // Encoded credential strip. Like the magnetic stripe on an ID.
    final totalStripeWidth =
        _kStripeLineCount * _kStripeLineWidth +
        (_kStripeLineCount - 1) * _kStripeSpacing;
    if (size.width > totalStripeWidth) {
      final stripeY = size.height - _kStripeBottomOffset;
      final stripeStartX = (size.width - totalStripeWidth) / 2;
      final stripePaint = Paint()
        ..strokeWidth = _kStripeLineWidth
        ..color = BaselineColors.teal.atOpacity(_kStripeOpacity)
        ..strokeCap = StrokeCap.round;

      // Pseudo-random heights using golden ratio for organic barcode look.
      for (int i = 0; i < _kStripeLineCount; i++) {
        final x = stripeStartX + i * (_kStripeLineWidth + _kStripeSpacing);
        // Golden ratio hash for varying heights.
        final hash = ((i * 0.618033988749895) % 1.0);
        final h = _kStripeMinHeight + hash * (_kStripeMaxHeight - _kStripeMinHeight);
        canvas.drawLine(
          Offset(x, stripeY),
          Offset(x, stripeY - h),
          stripePaint,
        );
      }
    }

    canvas.restore();

    // Teal border.
    canvas.drawRRect(
      rrect.deflate(bw / 2),
      Paint()
        ..color = BaselineColors.teal
        ..style = PaintingStyle.stroke
        ..strokeWidth = bw,
    );

    // Corner registration dots.
    final dotPaint = Paint()
      ..color = BaselineColors.teal.atOpacity(_kCornerDotOpacity);
    final inset = _kPillRadius * 0.35;
    for (final dot in [
      Offset(inset, inset),
      Offset(size.width - inset, inset),
      Offset(inset, size.height - inset),
      Offset(size.width - inset, size.height - inset),
    ]) {
      canvas.drawCircle(dot, _kCornerDotSize, dotPaint);
    }
  }

  // ── PRO+: the hero (holographic credential) ───────────

  void _paintProPlus(Canvas canvas, Size size, RRect rrect, Rect rect) {
    // Outer glow with breathing pulse (drawn FIRST, behind pill content).
    // Base glow + sine-modulated intensity. The badge is alive.
    final glowOpacity = _kGlowOpacityBase +
        (_kGlowOpacityPeak - _kGlowOpacityBase) * breathValue;
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = BaselineColors.teal.atOpacity(glowOpacity)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, _kGlowBlur),
    );

    canvas.save();
    canvas.clipRRect(rrect);

    // 1. Gradient fill.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_kProPlusFillEnd, _kProPlusFillStart],
        ).createShader(rect),
    );

    // 2. Embossed "+" watermark: credit card embossing.
    final cx = size.width / 2;
    final cy = size.height / 2;
    final plusHalf = _kEmbossSize / 2;
    final embossPaint = Paint()
      ..strokeWidth = _kEmbossStroke
      ..color = BaselineColors.white.atOpacity(_kEmbossOpacity)
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(cx, cy - plusHalf),
      Offset(cx, cy + plusHalf),
      embossPaint,
    );
    canvas.drawLine(
      Offset(cx - plusHalf, cy),
      Offset(cx + plusHalf, cy),
      embossPaint,
    );

    // 3. Micro-credential line: "SEC·CLR:MAX" at bottom inner edge.
    final credTp = TextPainter(
      text: TextSpan(
        text: _kProPlusCred,
        style: TextStyle(
          fontFamily: BaselineTypography.monoFontFamily,
          fontSize: _kCredFontSize,
          color: BaselineColors.white.atOpacity(_kCredOpacity),
          letterSpacing: 0.8,
          fontWeight: FontWeight.w300,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    credTp.paint(
      canvas,
      Offset(
        cx - credTp.width / 2,
        size.height - _kCredBottomOffset - credTp.height,
      ),
    );
    credTp.dispose();

    // 4. Scanline sweep (single pass after entry).
    if (scanProgress.value > 0.0 && scanProgress.value < 1.0) {
      final scanX = rect.left + scanProgress.value * size.width;
      final beamRect = Rect.fromLTWH(
        scanX - _kScanBeamWidth / 2, 0, _kScanBeamWidth, size.height,
      );
      canvas.drawRect(
        beamRect,
        Paint()
          ..shader = LinearGradient(
            colors: [
              BaselineColors.white.atOpacity(0),
              BaselineColors.white.atOpacity(_kScanBeamOpacity),
              BaselineColors.white.atOpacity(0),
            ],
            stops: const [0.0, 0.5, 1.0],
          ).createShader(beamRect),
      );
    }

    // 5. Holographic shimmer: spectral band sweeps after scanline.
    //    Like tilting a holographic sticker on a government ID.
    //    Hue shifts from teal → blue-teal → blue → back.
    if (holoProgress.value > 0.0 && holoProgress.value < 1.0) {
      final holoX = holoProgress.value * (size.width + _kHoloBeamWidth) -
          _kHoloBeamWidth / 2;
      final beamRect = Rect.fromLTWH(
        holoX - _kHoloBeamWidth / 2, 0, _kHoloBeamWidth, size.height,
      );

      // Intensity peaks at center of sweep.
      final intensity = math.sin(holoProgress.value * math.pi);

      canvas.drawRect(
        beamRect,
        Paint()
          ..shader = LinearGradient(
            colors: [
              _kHoloColorA.atOpacity(0),
              _kHoloColorB.atOpacity(_kHoloOpacity * intensity),
              _kHoloColorC.atOpacity(_kHoloOpacity * intensity * 0.7),
              _kHoloColorB.atOpacity(_kHoloOpacity * intensity),
              _kHoloColorA.atOpacity(0),
            ],
            stops: const [0.0, 0.2, 0.5, 0.8, 1.0],
          ).createShader(beamRect),
      );
    }

    // 6. Top edge highlight: machined catch-light.
    canvas.drawPath(
      Path()
        ..moveTo(_kPillRadius, 0)
        ..lineTo(size.width - _kPillRadius, 0),
      Paint()
        ..color = BaselineColors.white.atOpacity(_kEdgeHighlightOpacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = _kEdgeHighlightWidth,
    );

    canvas.restore();
  }

  // ── B2B: institutional authority ──────────────────────

  void _paintB2B(Canvas canvas, Size size, RRect rrect) {
    final bw = BaselineCardStyle.borderWidth; // 2px

    // Teal border.
    canvas.drawRRect(
      rrect.deflate(bw / 2),
      Paint()
        ..color = BaselineColors.teal
        ..style = PaintingStyle.stroke
        ..strokeWidth = bw,
    );

    // Inner double-rule: second hairline inset from main border.
    // Laminated institutional weight. Distinguished from PRO.
    // Decorative inner chrome (0.3px) ≠ structural 2px borders.
    final innerRRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        _kInnerRuleInset,
        _kInnerRuleInset,
        size.width - _kInnerRuleInset * 2,
        size.height - _kInnerRuleInset * 2,
      ),
      Radius.circular(_kPillRadius - _kInnerRuleInset),
    );
    canvas.drawRRect(
      innerRRect,
      Paint()
        ..color = BaselineColors.teal.atOpacity(_kInnerRuleOpacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = _kInnerRuleStroke,
    );

    // Hashmark ticks under text.
    final tickPaint = Paint()
      ..color = BaselineColors.teal.atOpacity(_kHashTickOpacity)
      ..strokeWidth = _kHashTickHeight
      ..strokeCap = StrokeCap.round;

    final totalTicksWidth = _kHashTickCount * _kHashTickWidth +
        (_kHashTickCount - 1) * _kHashTickSpacing;
    final startX = (size.width - totalTicksWidth) / 2;
    final tickY = size.height - 3.0;

    for (var i = 0; i < _kHashTickCount; i++) {
      final x = startX + i * (_kHashTickWidth + _kHashTickSpacing);
      canvas.drawLine(
        Offset(x, tickY),
        Offset(x + _kHashTickWidth, tickY),
        tickPaint,
      );
    }

    // Institutional stamp brackets: top-left + bottom-right.
    final bracketPaint = Paint()
      ..strokeWidth = _kStampBracketStroke
      ..color = BaselineColors.teal.atOpacity(_kStampBracketOpacity)
      ..strokeCap = StrokeCap.round;

    final bi = _kStampBracketInset;
    final ba = _kStampBracketArm;

    // Top-left L.
    canvas.drawLine(Offset(bi, bi), Offset(bi + ba, bi), bracketPaint);
    canvas.drawLine(Offset(bi, bi), Offset(bi, bi + ba), bracketPaint);

    // Bottom-right L.
    canvas.drawLine(
      Offset(size.width - bi, size.height - bi),
      Offset(size.width - bi - ba, size.height - bi),
      bracketPaint,
    );
    canvas.drawLine(
      Offset(size.width - bi, size.height - bi),
      Offset(size.width - bi, size.height - bi - ba),
      bracketPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _TierBadgePainter old) =>
      config.level != old.config.level ||
      scanProgress.value != old.scanProgress.value ||
      holoProgress.value != old.holoProgress.value ||
      entryProgress.value != old.entryProgress.value ||
      breathValue != old.breathValue;
}
