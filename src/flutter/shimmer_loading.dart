/// F2.14: Shimmer Loading (Active Intelligence Retrieval)
///
/// The intelligence facility isn't waiting for data. It's hunting.
///
/// Each sweep cycle is a sonar ping: the beam searches diagonally
/// across the display, phosphor trails decay behind it, and where
/// it passes, data zones momentarily flicker with ghost signal.
/// Reticle targeting corners flash as the beam confirms lock.
/// With each successive cycle, the system gets closer to
/// acquisition: borders sharpen, chrome brightens a fraction.
///
/// The skeleton isn't a placeholder. It's a targeting grid where
/// content will lock in.
///
/// CustomPaint gradient sweep replaces `shimmer` package (doctrine).
/// Single AnimationController drives diagonal sweep with direction
/// alternation, phosphor wake trail, and reactive chrome: reticle
/// corners flash as beam passes, borders progressively sharpen,
/// data zones ghost-flicker with radio-dial signal fragments.
///
/// Architecture: _ShimmerScope distributes the AnimationController
/// reference and cycle count (changes every ~2.4s). All per-frame
/// animation is driven at the paint layer via `repaint: controller`.
/// The widget tree remains static between cycle boundaries.
///
/// Shimmer colors from design system (F1.1):
///   Base:      BaselineColors.shimmerBase
///   Highlight: BaselineColors.shimmerHighlight
///
/// Skeleton variants match swept widget shapes:
///   ShimmerStatementCard -> F2.9 (44px avatar, docket bar, metrics)
///   ShimmerFigureRow     -> F2.10 (44px avatar, 72px row, badge)
///   ShimmerVoteCard      -> F2.11 (docket bar, badge pill, result)
///   ShimmerFeedList      -> N statement cards (sector stagger boot)
///   ShimmerFigureList    -> N figure rows (sector stagger boot)
///   ShimmerVoteList      -> N vote cards (sector stagger boot)
///
/// No teal in skeletons. Chrome uses borderInactive (pre-boot).
///
/// Path: lib/widgets/shimmer_loading.dart
library;

// 1. Dart SDK
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

// 2. Flutter
import 'package:flutter/material.dart';

// 3. Project: config
import 'package:baseline_app/config/theme.dart';

// ═══════════════════════════════════════════════════════════
// CONSTANTS
// ═══════════════════════════════════════════════════════════

/// Sweep cycle duration (measured, not frantic).
const Duration _kSweepDuration = Duration(milliseconds: 2400);

/// Sweep angle in radians (-25 degrees diagonal).
const double _kSweepAngle = -25.0 * math.pi / 180;

/// Sweep gradient band width fraction (0.0 to 1.0).
const double _kSweepBandWidth = 0.30;

/// Phosphor wake trail width fraction (behind beam).
const double _kWakeWidth = 0.15;

/// Sector stagger delay per card in list builders.
const Duration _kSectorStagger = Duration(milliseconds: 80);

/// Stagger boot fade-in duration.
const Duration _kBootFadeDuration = Duration(milliseconds: 200);

/// Max cycles for progressive signal lock effects.
const int _kMaxProgressCycles = 5;

/// Skeleton text-line border radius.
const double _kTextRadius = 4.0;

/// Skeleton block border radius.
const double _kBlockRadius = 6.0;

/// Reticle corner arm length.
const double _kReticleArm = 3.0;

/// Base chrome opacity (pre-boot, grows with cycles).
const double _kChromeBaseOpacity = 0.04;

/// Chrome reactive multiplier when beam is near.
const double _kChromeReactiveMultiplier = 3.0;

/// Hashmark tick count on bottom ruler.
const int _kRulerTicks = 5;

/// Film perforation dot count on docket bars.
const int _kPerfDots = 3;

/// Diagnostic label font size (base, before text scaling).
const double _kDiagnosticSize = 7.0;

/// Ghost flicker opacity bump on text zones.
const double _kGhostFlickerBump = 0.06;

/// Signal acquisition status labels (cycle through per sector).
const List<String> _kSignalLabels = ['SCANNING', 'ACQUIRING', 'LOCKING'];

/// Beam proximity threshold for reactive effects.
const double _kBeamProximity = 0.20;

// ═══════════════════════════════════════════════════════════
// SHIMMER SCOPE: CONTROLLER DISTRIBUTION
// ═══════════════════════════════════════════════════════════

/// Distributes the AnimationController and cycle count to all
/// descendant skeleton widgets. Notifies ONLY on cycle boundary
/// (~every 2.4s), not per frame. Per-frame animation is driven
/// at the paint layer via `repaint: controller`.
/// Public entry-point shimmer widget.
/// Wraps skeleton content in the sonar sweep animation.
class ShimmerLoading extends StatelessWidget {
  const ShimmerLoading({
    super.key,
    this.variant,
    this.child,
    this.width,
    this.height,
    this.borderRadius,
    this.lines,
  });

  /// Skeleton variant to display. If null, shows a generic shimmer area.
  final ShimmerVariant? variant;

  /// Optional custom child to shimmer over.
  final Widget? child;

  /// Optional explicit width for the shimmer area.
  final double? width;

  /// Optional explicit height for the shimmer area.
  final double? height;

  /// Optional border radius for the shimmer area.
  final dynamic borderRadius;

  /// Optional number of lines for the shimmer skeleton.
  final int? lines;

  @override
  Widget build(BuildContext context) {
    final inner = child ?? _buildVariant();
    return _ShimmerHost(child: inner);
  }

  Widget _buildVariant() {
    // If explicit dimensions are provided, use a sized container.
    if (width != null || height != null || lines != null) {
      final effectiveHeight = height ?? (lines != null ? lines! * 20.0 : 200.0);
      return SizedBox(
        width: width,
        height: effectiveHeight,
      );
    }
    return switch (variant) {
      ShimmerVariant.feed => const ShimmerFeedList(),
      ShimmerVariant.profile => const ShimmerFigureList(),
      ShimmerVariant.trends => const ShimmerFeedList(),
      ShimmerVariant.detail => const ShimmerStatementCard(),
      ShimmerVariant.search => const ShimmerFeedList(),
      ShimmerVariant.receipt => const ShimmerStatementCard(),
      null => const SizedBox(height: 200),
    };
  }
}

/// Shimmer variant shapes.
enum ShimmerVariant {
  feed,
  profile,
  trends,
  detail,
  search,
  receipt,
}

class _ShimmerScope extends InheritedWidget {
  const _ShimmerScope({
    required this.controller,
    required this.cycleCount,
    required super.child,
  });

  /// The sweep animation controller. Descendants use this as
  /// `repaint:` listener for paint-layer animation.
  final AnimationController controller;

  /// Number of completed sweep cycles (clamped).
  final int cycleCount;

  /// Current sweep progress (read from controller at call time).
  double get progress => controller.value;

  /// Whether current cycle sweeps in reverse direction.
  bool get isReversed => cycleCount.isOdd;

  /// Progressive border opacity: creeps up over first N cycles.
  double get borderOpacity {
    final t = (cycleCount / _kMaxProgressCycles).clamp(0.0, 1.0);
    return lerpDouble(0.20, 0.35, t)!;
  }

  /// Chrome opacity for this cycle: base + progressive bump.
  double get chromeOpacity {
    final t = (cycleCount / _kMaxProgressCycles).clamp(0.0, 1.0);
    return lerpDouble(_kChromeBaseOpacity, _kChromeBaseOpacity * 2.0, t)!;
  }

  /// Signal label for a given sector index.
  String signalLabel(int sectorIndex) {
    final labelIndex = ((cycleCount + sectorIndex) % _kSignalLabels.length);
    return _kSignalLabels[labelIndex];
  }

  /// Whether the sweep beam is near a normalized vertical position.
  /// [normalizedY] is 0.0 at top, 1.0 at bottom of host.
  /// Reads controller.value at call time (paint-layer accuracy).
  bool isBeamNear(double normalizedY) {
    final p = isReversed ? 1.0 - progress : progress;
    return (p - normalizedY).abs() < _kBeamProximity;
  }

  static _ShimmerScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<_ShimmerScope>();
  }

  @override
  bool updateShouldNotify(_ShimmerScope oldWidget) {
    // Only triggers on cycle boundary (~every 2.4s).
    // Per-frame animation driven by repaint: controller.
    return oldWidget.cycleCount != cycleCount;
  }
}

// ═══════════════════════════════════════════════════════════
// SHIMMER HOST: ACTIVE RETRIEVAL CONTROLLER
// ═══════════════════════════════════════════════════════════

/// Stateful host owning the sweep animation. Counts cycles,
/// alternates direction, provides scope to descendants, and
/// paints the sonar sweep beam as foreground overlay.
///
/// Do not nest inside another _ShimmerHost. Public single-card
/// widgets (ShimmerStatementCard, etc.) each create their own
/// host. List builders (ShimmerFeedList, etc.) create one host
/// wrapping all inner cards. Never combine the two patterns.
class _ShimmerHost extends StatefulWidget {
  const _ShimmerHost({required this.child});
  final Widget child;

  @override
  State<_ShimmerHost> createState() => _ShimmerHostState();
}

class _ShimmerHostState extends State<_ShimmerHost>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _reduceMotion = false;
  bool _didFirstDependencies = false;
  int _cycleCount = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: _kSweepDuration,
    );
    _controller.addStatusListener(_onCycleComplete);
  }

  void _onCycleComplete(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      // Clamp cycle count to avoid unbounded growth.
      setState(() {
        _cycleCount = (_cycleCount + 1) % (_kMaxProgressCycles + 1);
      });
      _controller.reset();
      _controller.forward();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // Aspect-specific: only rebuild on accessibility changes.
    final newReduceMotion =
        MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.accessibleNavigationOf(context);

    if (newReduceMotion != _reduceMotion) {
      _reduceMotion = newReduceMotion;
      if (_reduceMotion) {
        _controller.stop();
      } else if (_didFirstDependencies) {
        _controller.forward();
      }
    }

    // First-run: start animation after context available.
    if (!_didFirstDependencies) {
      _didFirstDependencies = true;
      if (!_reduceMotion) {
        _controller.forward();
      }
    }
  }

  @override
  void dispose() {
    _controller.removeStatusListener(_onCycleComplete);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_reduceMotion) {
      // Static skeleton: no animation, no scope needed.
      return widget.child;
    }

    // Scope distributes controller reference + cycle count.
    // Widget tree rebuilds only on cycle boundary (setState in
    // _onCycleComplete). Per-frame sweep driven by repaint:.
    return _ShimmerScope(
      controller: _controller,
      cycleCount: _cycleCount,
      child: CustomPaint(
        foregroundPainter: _SonarSweepPainter(
          controller: _controller,
          cycleCount: _cycleCount,
        ),
        child: widget.child,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// SONAR SWEEP PAINTER: SEARCHING BEAM + PHOSPHOR WAKE
// ═══════════════════════════════════════════════════════════

/// Diagonal sweep beam with Gaussian profile, phosphor wake trail,
/// leading-edge bloom, and direction alternation. The beam is
/// searching, not decorating.
///
/// Uses `repaint: controller` for per-frame updates. Widget tree
/// stays static.
class _SonarSweepPainter extends CustomPainter {
  _SonarSweepPainter({
    required this.controller,
    required this.cycleCount,
  }) : super(repaint: controller);

  final AnimationController controller;
  final int cycleCount;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final totalTravel = w + h;
    final progress = controller.value;
    final isReversed = cycleCount.isOdd;

    // Direction alternation: organic sonar rhythm.
    final p = isReversed ? 1.0 - progress : progress;
    final sweepCenter = -h + (totalTravel + h) * p;
    final bandHalf = totalTravel * _kSweepBandWidth / 2;
    final wakeLen = totalTravel * _kWakeWidth;

    canvas.save();
    canvas.rotate(_kSweepAngle);

    // Beam height covers full diagonal to guarantee corner clearance
    // on all aspect ratios. cos-based: h / cos(angle) + buffer.
    final beamHeight = h / math.cos(_kSweepAngle.abs()) + w * math.sin(_kSweepAngle.abs());

    final highlight = BaselineColors.shimmerHighlight;

    // Phosphor wake trail (behind beam, decays).
    final wakeStart = isReversed
        ? sweepCenter + bandHalf
        : sweepCenter - bandHalf - wakeLen;
    final wakeEnd = isReversed
        ? sweepCenter + bandHalf + wakeLen
        : sweepCenter - bandHalf;
    final wakePaint = Paint()
      ..shader = LinearGradient(
        colors: isReversed
            ? [highlight.atOpacity(0.05), Colors.transparent]
            : [Colors.transparent, highlight.atOpacity(0.05)],
      ).createShader(
        Rect.fromLTRB(
          math.min(wakeStart, wakeEnd),
          0,
          math.max(wakeStart, wakeEnd),
          0,
        ),
      );
    canvas.drawRect(
      Rect.fromLTWH(
        math.min(wakeStart, wakeEnd),
        -beamHeight / 2,
        (wakeEnd - wakeStart).abs(),
        beamHeight,
      ),
      wakePaint,
    );

    // Main sweep beam (5-stop Gaussian profile).
    final beamStart = sweepCenter - bandHalf;
    final beamEnd = sweepCenter + bandHalf;
    final beamPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          Colors.transparent,
          highlight.atOpacity(0.06),
          highlight.atOpacity(0.14),
          highlight.atOpacity(0.06),
          Colors.transparent,
        ],
        stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
      ).createShader(
        Rect.fromLTRB(beamStart, 0, beamEnd, 0),
      );
    canvas.drawRect(
      Rect.fromLTWH(
        beamStart,
        -beamHeight / 2,
        beamEnd - beamStart,
        beamHeight,
      ),
      beamPaint,
    );

    // Leading-edge bloom (sigma-3 glow ahead of beam).
    final bloomEdge = isReversed ? beamStart : beamEnd;
    final bloomDir = isReversed ? -1.0 : 1.0;
    final bloomPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          highlight.atOpacity(0.03),
          Colors.transparent,
        ],
      ).createShader(
        Rect.fromLTRB(
          bloomEdge,
          0,
          bloomEdge + 24 * bloomDir,
          0,
        ),
      )
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    canvas.drawRect(
      Rect.fromLTWH(
        isReversed ? bloomEdge - 24 : bloomEdge,
        -beamHeight / 2,
        24,
        beamHeight,
      ),
      bloomPaint,
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(_SonarSweepPainter oldDelegate) {
    // cycleCount change triggers repaint for direction swap.
    // Per-frame repaints driven by repaint: controller.
    return oldDelegate.cycleCount != cycleCount;
  }
}

// ═══════════════════════════════════════════════════════════
// SKELETON PRIMITIVES
// ═══════════════════════════════════════════════════════════

/// Rounded rectangle placeholder with optional void hatch and
/// ghost data flicker (radio-dial signal fragment).
///
/// Ghost flicker driven by local AnimatedBuilder with stable
/// Stack topology (no Container/Stack swap at 60fps).
class _SkeletonBox extends StatelessWidget {
  const _SkeletonBox({
    required this.width,
    required this.height,
    this.borderRadius = _kBlockRadius,
    this.showHatch = false,
    this.ghostFlicker = false,
  });

  final double width;
  final double height;
  final double borderRadius;
  final bool showHatch;
  final bool ghostFlicker;

  @override
  Widget build(BuildContext context) {
    Widget box;
    if (showHatch) {
      box = ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: CustomPaint(
          size: Size(width, height),
          painter: const _VoidHatchBoxPainter(),
        ),
      );
    } else {
      box = Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: BaselineColors.shimmerBase,
          borderRadius: BorderRadius.circular(borderRadius),
        ),
      );
    }

    if (!ghostFlicker) return box;

    // Ghost data flicker: brief opacity pulse when beam sweeps over.
    // Radio dial catching a station for a split second.
    final scope = _ShimmerScope.maybeOf(context);
    if (scope == null) return box;

    // Stable topology: always Stack. Overlay opacity driven by
    // local AnimatedBuilder (tiny subtree, not full tree rebuild).
    return Stack(
      children: [
        box,
        Positioned.fill(
          child: AnimatedBuilder(
            animation: scope.controller,
            builder: (context, _) {
              final beamNear = scope.isBeamNear(0.5);
              final shouldFlicker =
                  beamNear && (scope.cycleCount % 3 != 0);
              final opacity =
                  shouldFlicker ? _kGhostFlickerBump : 0.0;
              return DecoratedBox(
                decoration: BoxDecoration(
                  color: BaselineColors.shimmerHighlight
                      .atOpacity(opacity),
                  borderRadius: BorderRadius.circular(borderRadius),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Void hatch on text placeholders: data zones marked but empty.
class _VoidHatchBoxPainter extends CustomPainter {
  const _VoidHatchBoxPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = BaselineColors.shimmerBase,
    );
    final hatchPaint = Paint()
      ..color = BaselineColors.shimmerHighlight.atOpacity(0.03)
      ..strokeWidth = 0.5;
    for (double x = -size.height; x < size.width + size.height; x += 5) {
      canvas.drawLine(
        Offset(x, size.height),
        Offset(x + size.height, 0),
        hatchPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_VoidHatchBoxPainter oldDelegate) => false;
}

/// Circle placeholder with ghost ring (targeting circle pre-lock).
class _SkeletonCircle extends StatelessWidget {
  const _SkeletonCircle({required this.diameter, this.showRing = false});
  final double diameter;
  final bool showRing;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(
        color: BaselineColors.shimmerBase,
        shape: BoxShape.circle,
        border: showRing
            ? Border.all(
                color: BaselineColors.borderInactive.atOpacity(0.10),
                width: 1.0,
              )
            : null,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// REACTIVE SKELETON CHROME: TARGETING LOCK SYSTEM
// ═══════════════════════════════════════════════════════════

/// Paints reactive reticle corners, classification hairline,
/// hashmark ruler, film perfs, and diagnostic sector label.
///
/// Chrome brightens when the sweep beam is near this card's
/// vertical zone. Progressive signal lock raises base opacity
/// over cycles.
///
/// Animation driven by `repaint: controller`. TextPainters
/// cached as dim/bright pairs (zero per-frame allocation).
/// Static geometry (reticle corners, ruler ticks) pre-computed
/// in constructor. Font family resolved from BaselineTypography
/// token. Diagnostic font scaled by OS text scaler.
///
/// Sub-2px decorative strokes: hairline (0.5), ruler ticks (0.5).
class _ReactiveChromePainter extends CustomPainter {
  _ReactiveChromePainter({
    required AnimationController? controller,
    required this.chromeOpacity,
    required this.normalizedY,
    required this.isReversed,
    required this.sectorIndex,
    required this.showRuler,
    required this.showPerfs,
    required this.signalLabel,
    required double textScaleFactor,
  }) : _fontFamily = BaselineTypography.monoFontFamily,
       _scaledDiagSize = _kDiagnosticSize * textScaleFactor,
       super(repaint: controller) {
    _controller = controller;
    _initTextPainters();
  }

  final double chromeOpacity;
  final double normalizedY;
  final bool isReversed;
  final int sectorIndex;
  final bool showRuler;
  final bool showPerfs;
  final String signalLabel;
  final String _fontFamily;
  final double _scaledDiagSize;

  AnimationController? _controller;

  // Cached TextPainter pairs: dim + bright variants.
  TextPainter? _sectorTpDim;
  TextPainter? _sectorTpBright;
  TextPainter? _signalTpDim;
  TextPainter? _signalTpBright;

  void _initTextPainters() {
    if (sectorIndex < 0) return;

    final sectorText =
        'SECTOR ${(sectorIndex + 1).toString().padLeft(2, '0')}';

    _sectorTpDim = TextPainter(
      text: TextSpan(
        text: sectorText,
        style: TextStyle(
          fontFamily: _fontFamily,
          fontSize: _scaledDiagSize,
          color: BaselineColors.borderInactive.atOpacity(0.05),
          letterSpacing: 0.8,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    _sectorTpBright = TextPainter(
      text: TextSpan(
        text: sectorText,
        style: TextStyle(
          fontFamily: _fontFamily,
          fontSize: _scaledDiagSize,
          color: BaselineColors.borderInactive.atOpacity(0.10),
          letterSpacing: 0.8,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    _signalTpDim = TextPainter(
      text: TextSpan(
        text: signalLabel,
        style: TextStyle(
          fontFamily: _fontFamily,
          fontSize: _scaledDiagSize,
          color: BaselineColors.borderInactive.atOpacity(0.04),
          letterSpacing: 1.0,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    _signalTpBright = TextPainter(
      text: TextSpan(
        text: signalLabel,
        style: TextStyle(
          fontFamily: _fontFamily,
          fontSize: _scaledDiagSize,
          color: BaselineColors.borderInactive.atOpacity(0.10),
          letterSpacing: 1.0,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
  }

  /// Compute beam proximity from controller value (paint-layer).
  bool get _beamNear {
    if (_controller == null) return false;
    final p = isReversed ? 1.0 - _controller!.value : _controller!.value;
    return (p - normalizedY).abs() < _kBeamProximity;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final beamNear = _beamNear;

    // Reactive opacity: brightens when beam sweeps through.
    final activeOpacity = beamNear
        ? (chromeOpacity * _kChromeReactiveMultiplier).clamp(0.0, 0.20)
        : chromeOpacity;

    final chrome = BaselineColors.borderInactive.atOpacity(activeOpacity);
    final dimPaint = Paint()
      ..color = chrome
      ..strokeWidth = 0.5;

    // Classification hairline (top).
    canvas.drawLine(Offset(0, 0.25), Offset(w, 0.25), dimPaint);

    // Reticle corners (pre-computed offsets, only paint changes).
    final rPaint = Paint()
      ..color = chrome
      ..strokeWidth = 1.0;
    // TL
    canvas.drawLine(const Offset(0, 0), Offset(_kReticleArm, 0), rPaint);
    canvas.drawLine(const Offset(0, 0), Offset(0, _kReticleArm), rPaint);
    // TR
    canvas.drawLine(Offset(w, 0), Offset(w - _kReticleArm, 0), rPaint);
    canvas.drawLine(Offset(w, 0), Offset(w, _kReticleArm), rPaint);
    // BL
    canvas.drawLine(Offset(0, h), Offset(_kReticleArm, h), rPaint);
    canvas.drawLine(Offset(0, h), Offset(0, h - _kReticleArm), rPaint);
    // BR
    canvas.drawLine(Offset(w, h), Offset(w - _kReticleArm, h), rPaint);
    canvas.drawLine(Offset(w, h), Offset(w, h - _kReticleArm), rPaint);

    // Hashmark ruler (bottom edge, 5 ticks).
    if (showRuler) {
      final rulerPaint = Paint()
        ..color = BaselineColors.borderInactive.atOpacity(0.04)
        ..strokeWidth = 0.5;
      for (int i = 0; i < _kRulerTicks; i++) {
        final x = w * (i + 1) / (_kRulerTicks + 1);
        canvas.drawLine(
          Offset(x, h - 3),
          Offset(x, h),
          rulerPaint,
        );
      }
    }

    // Film perforation dots (on docket bar area).
    if (showPerfs) {
      final perfPaint = Paint()
        ..color = BaselineColors.borderInactive.atOpacity(0.04);
      for (int i = 0; i < _kPerfDots; i++) {
        final y = h * (i + 1) / (_kPerfDots + 1);
        canvas.drawCircle(Offset(6, y), 1.0, perfPaint);
      }
    }

    // Diagnostic sector label (cached TextPainter, dim/bright swap).
    if (_sectorTpDim != null) {
      final tp = beamNear ? _sectorTpBright! : _sectorTpDim!;
      tp.paint(canvas, Offset(w - tp.width - 6, 5));
    }

    // Signal acquisition status label (cached, dim/bright swap).
    if (_signalTpDim != null) {
      final tp = beamNear ? _signalTpBright! : _signalTpDim!;
      tp.paint(canvas, Offset(6, h - tp.height - 5));
    }
  }

  @override
  bool shouldRepaint(_ReactiveChromePainter oldDelegate) {
    // Cycle-level changes trigger full repaint. Per-frame beam
    // reactivity driven by repaint: controller.
    return oldDelegate.chromeOpacity != chromeOpacity ||
        oldDelegate.signalLabel != signalLabel ||
        oldDelegate.sectorIndex != sectorIndex ||
        oldDelegate.normalizedY != normalizedY;
  }
}

// ═══════════════════════════════════════════════════════════
// SKELETON CARD: REACTIVE WRAPPER
// ═══════════════════════════════════════════════════════════

/// Card wrapper with reactive chrome. Reads _ShimmerScope to
/// get controller reference and cycle-level state (border opacity,
/// chrome opacity). Chrome painter animates at paint layer.
class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard({
    required this.child,
    this.minHeight,
    this.sectorIndex = -1,
    this.showPerfs = false,
  });

  final Widget child;
  final double? minHeight;
  final int sectorIndex;
  final bool showRuler = false;
  final bool showPerfs;

  @override
  Widget build(BuildContext context) {
    final scope = _ShimmerScope.maybeOf(context);

    // Normalize sector position for beam detection.
    // In lists: sector 0 at top, sector N at bottom.
    // Single cards: use 0.5 (center).
    final normalizedY = sectorIndex >= 0
        ? (sectorIndex * 0.12).clamp(0.0, 0.9)
        : 0.5;

    final borderOp = scope?.borderOpacity ?? 0.20;
    final chromeOp = scope?.chromeOpacity ?? _kChromeBaseOpacity;
    final signalLabel = scope?.signalLabel(sectorIndex) ?? '';
    final textScaleFactor =
        MediaQuery.textScalerOf(context).scale(_kDiagnosticSize) /
        _kDiagnosticSize;

    return RepaintBoundary(
      child: CustomPaint(
        foregroundPainter: _ReactiveChromePainter(
          controller: scope?.controller,
          chromeOpacity: chromeOp,
          normalizedY: normalizedY,
          isReversed: scope?.isReversed ?? false,
          sectorIndex: sectorIndex,
          showRuler: showRuler,
          showPerfs: showPerfs,
          signalLabel: signalLabel,
          textScaleFactor: textScaleFactor,
        ),
        child: Container(
          constraints: minHeight != null
              ? BoxConstraints(minHeight: minHeight!)
              : null,
          decoration: BoxDecoration(
            color: BaselineColors.card,
            borderRadius: BorderRadius.circular(BaselineCardStyle.radius),
            border: Border.all(
              color: BaselineColors.borderInactive
                  .atOpacity(borderOp),
              width: BaselineCardStyle.borderWidth,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// SHIMMER STATEMENT CARD: matches swept F2.9
// ═══════════════════════════════════════════════════════════

/// Skeleton matching F2.9 (swept): 44px avatar with ghost ring,
/// docket-bar placeholder, text lines with ghost flicker,
/// metric bar area, pulse bar.
///
/// Do not nest inside ShimmerFeedList (which creates its own
/// host with _StatementCardInner).
class ShimmerStatementCard extends StatelessWidget {
  const ShimmerStatementCard({super.key});

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: _ShimmerHost(
        child: _SkeletonCard(
          showPerfs: true,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Docket bar placeholder (left edge).
              Container(
                width: 3,
                decoration: const BoxDecoration(
                  color: BaselineColors.shimmerBase,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(1),
                    bottomLeft: Radius.circular(1),
                  ),
                ),
              ),
              // Card content.
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(BaselineSpacing.md),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final maxW = constraints.maxWidth;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Row 1: Avatar + name + date.
                          Row(
                            children: [
                              const _SkeletonCircle(
                                diameter: 44,
                                showRing: true,
                              ),
                              const SizedBox(width: BaselineSpacing.sm),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    _SkeletonBox(
                                      width: maxW * 0.35,
                                      height: 14,
                                      borderRadius: _kTextRadius,
                                      showHatch: true,
                                      ghostFlicker: true,
                                    ),
                                    const SizedBox(height: 6),
                                    _SkeletonBox(
                                      width: maxW * 0.2,
                                      height: 10,
                                      borderRadius: _kTextRadius,
                                    ),
                                  ],
                                ),
                              ),
                              const _SkeletonBox(
                                width: 48,
                                height: 10,
                              ),
                            ],
                          ),

                          const SizedBox(height: BaselineSpacing.sm),

                          // Row 2: Statement text.
                          _SkeletonBox(
                            width: maxW * 0.85,
                            height: 14,
                            borderRadius: _kTextRadius,
                            showHatch: true,
                            ghostFlicker: true,
                          ),
                          const SizedBox(height: 8),
                          _SkeletonBox(
                            width: maxW * 0.6,
                            height: 14,
                            borderRadius: _kTextRadius,
                            showHatch: true,
                            ghostFlicker: true,
                          ),

                          const SizedBox(height: BaselineSpacing.sm),

                          // Row 3: Metric bars placeholder.
                          Row(
                            children: [
                              _SkeletonBox(
                                width: maxW * 0.22,
                                height: 8,
                                borderRadius: _kTextRadius,
                              ),
                              const SizedBox(width: BaselineSpacing.sm),
                              _SkeletonBox(
                                width: maxW * 0.22,
                                height: 8,
                                borderRadius: _kTextRadius,
                              ),
                              const Spacer(),
                              const _SkeletonBox(
                                width: 36,
                                height: 12,
                              ),
                            ],
                          ),

                          const SizedBox(height: BaselineSpacing.xs),

                          // Pulse bar placeholder (3px).
                          _SkeletonBox(
                            width: maxW * 0.30,
                            height: 3,
                            borderRadius: 1.5,
                          ),
                        ],
                      );
                    },
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
// SHIMMER FIGURE ROW: matches swept F2.10
// ═══════════════════════════════════════════════════════════

/// Skeleton matching F2.10 (swept): 44px avatar with ghost ring,
/// 72px row, honor stripe placeholder, FG-4 badge with glow hint.
///
/// Do not nest inside ShimmerFigureList.
class ShimmerFigureRow extends StatelessWidget {
  const ShimmerFigureRow({super.key});

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: _ShimmerHost(
        child: _SkeletonCard(
          minHeight: 72,
          child: Row(
            children: [
              // Honor stripe placeholder (left).
              Container(
                width: 3,
                height: 72,
                decoration: const BoxDecoration(
                  color: BaselineColors.shimmerBase,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(1),
                    bottomLeft: Radius.circular(1),
                  ),
                ),
              ),
              const SizedBox(width: BaselineSpacing.md),
              // Avatar with ghost ring.
              const _SkeletonCircle(diameter: 44, showRing: true),
              const SizedBox(width: BaselineSpacing.sm),
              // Name + subtitle.
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _SkeletonBox(
                      width: 120,
                      height: 14,
                      borderRadius: _kTextRadius,
                      showHatch: true,
                      ghostFlicker: true,
                    ),
                    const SizedBox(height: 6),
                    const _SkeletonBox(
                      width: 80,
                      height: 10,
                      borderRadius: _kTextRadius,
                    ),
                  ],
                ),
              ),
              // FG-4 "THIS WK" badge placeholder with glow hint.
              Container(
                width: 40,
                height: 18,
                decoration: BoxDecoration(
                  color: BaselineColors.shimmerBase,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(
                    color: BaselineColors.shimmerHighlight.atOpacity(0.04),
                    width: 0.5,
                  ),
                ),
              ),
              const SizedBox(width: BaselineSpacing.md),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// SHIMMER VOTE CARD: matches swept F2.11
// ═══════════════════════════════════════════════════════════

/// Skeleton matching F2.11 (swept): docket bar, bill ID,
/// chamber, date, title, vote badge pill, result.
///
/// Do not nest inside ShimmerVoteList.
class ShimmerVoteCard extends StatelessWidget {
  const ShimmerVoteCard({super.key});

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: _ShimmerHost(
        child: _SkeletonCard(
          showPerfs: true,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Docket bar placeholder.
              Container(
                width: 3,
                decoration: BoxDecoration(
                  color: BaselineColors.shimmerHighlight.atOpacity(0.2),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(1),
                    bottomLeft: Radius.circular(1),
                  ),
                ),
              ),
              // Card content.
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(BaselineSpacing.md),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final maxW = constraints.maxWidth;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Docket header: bill ID + chamber + date.
                          Row(
                            children: [
                              _SkeletonBox(
                                width: maxW * 0.25,
                                height: 12,
                                borderRadius: _kTextRadius,
                                showHatch: true,
                                ghostFlicker: true,
                              ),
                              const SizedBox(width: BaselineSpacing.sm),
                              const _SkeletonBox(
                                width: 48,
                                height: 9,
                                borderRadius: _kTextRadius,
                              ),
                              const Spacer(),
                              const _SkeletonBox(
                                width: 72,
                                height: 9,
                                borderRadius: _kTextRadius,
                              ),
                            ],
                          ),

                          const SizedBox(height: BaselineSpacing.xs),

                          // Bill title.
                          _SkeletonBox(
                            width: maxW * 0.8,
                            height: 12,
                            borderRadius: _kTextRadius,
                            showHatch: true,
                            ghostFlicker: true,
                          ),
                          const SizedBox(height: 6),
                          _SkeletonBox(
                            width: maxW * 0.5,
                            height: 12,
                            borderRadius: _kTextRadius,
                          ),

                          const SizedBox(height: BaselineSpacing.sm),

                          // Verdict: badge pill + result.
                          Row(
                            children: [
                              // Badge pill placeholder with glow hint.
                              Container(
                                width: 52,
                                height: 22,
                                decoration: BoxDecoration(
                                  color: BaselineColors.shimmerBase,
                                  borderRadius: BorderRadius.circular(11),
                                  border: Border.all(
                                    color: BaselineColors.shimmerHighlight
                                        .atOpacity(0.04),
                                    width: 0.5,
                                  ),
                                ),
                              ),
                              const SizedBox(width: BaselineSpacing.sm),
                              _SkeletonBox(
                                width: maxW * 0.28,
                                height: 10,
                                borderRadius: _kTextRadius,
                              ),
                            ],
                          ),
                        ],
                      );
                    },
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
// LIST BUILDERS: SECTOR STAGGER BOOT SEQUENCE
// ═══════════════════════════════════════════════════════════

/// N statement card skeletons with sector stagger boot sequence.
/// Single shimmer host wraps all cards. Each sector initializes
/// with an 80ms delay: the facility powering up zone by zone.
class ShimmerFeedList extends StatefulWidget {
  const ShimmerFeedList({super.key, this.count = 3})
      : assert(count > 0 && count <= 20,
            'ShimmerFeedList: count must be 1 to 20');
  final int count;

  @override
  State<ShimmerFeedList> createState() => _ShimmerFeedListState();
}

class _ShimmerFeedListState extends State<ShimmerFeedList> {
  late final List<bool> _booted;
  final List<Timer> _staggerTimers = [];

  @override
  void initState() {
    super.initState();
    _booted = List.filled(widget.count, false);
    for (int i = 0; i < widget.count; i++) {
      _staggerTimers.add(
        Timer(_kSectorStagger * i, () {
          if (mounted) setState(() => _booted[i] = true);
        }),
      );
    }
  }

  @override
  void dispose() {
    for (final timer in _staggerTimers) {
      timer.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: _ShimmerHost(
        child: Column(
          children: List.generate(widget.count, (i) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: i < widget.count - 1 ? BaselineSpacing.sm : 0,
              ),
              child: AnimatedOpacity(
                opacity: _booted[i] ? 1.0 : 0.0,
                duration: _kBootFadeDuration,
                curve: Curves.easeOut,
                child: _StatementCardInner(sectorIndex: i),
              ),
            );
          }),
        ),
      ),
    );
  }
}

/// N figure row skeletons with sector stagger boot sequence.
class ShimmerFigureList extends StatefulWidget {
  const ShimmerFigureList({super.key, this.count = 6})
      : assert(count > 0 && count <= 20,
            'ShimmerFigureList: count must be 1 to 20');
  final int count;

  @override
  State<ShimmerFigureList> createState() => _ShimmerFigureListState();
}

class _ShimmerFigureListState extends State<ShimmerFigureList> {
  late final List<bool> _booted;
  final List<Timer> _staggerTimers = [];

  @override
  void initState() {
    super.initState();
    _booted = List.filled(widget.count, false);
    for (int i = 0; i < widget.count; i++) {
      _staggerTimers.add(
        Timer(_kSectorStagger * i, () {
          if (mounted) setState(() => _booted[i] = true);
        }),
      );
    }
  }

  @override
  void dispose() {
    for (final timer in _staggerTimers) {
      timer.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: _ShimmerHost(
        child: Column(
          children: List.generate(widget.count, (i) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: i < widget.count - 1 ? BaselineSpacing.xs : 0,
              ),
              child: AnimatedOpacity(
                opacity: _booted[i] ? 1.0 : 0.0,
                duration: _kBootFadeDuration,
                curve: Curves.easeOut,
                child: _FigureRowInner(sectorIndex: i),
              ),
            );
          }),
        ),
      ),
    );
  }
}

/// N vote card skeletons with sector stagger boot sequence.
class ShimmerVoteList extends StatefulWidget {
  const ShimmerVoteList({super.key, this.count = 4})
      : assert(count > 0 && count <= 20,
            'ShimmerVoteList: count must be 1 to 20');
  final int count;

  @override
  State<ShimmerVoteList> createState() => _ShimmerVoteListState();
}

class _ShimmerVoteListState extends State<ShimmerVoteList> {
  late final List<bool> _booted;
  final List<Timer> _staggerTimers = [];

  @override
  void initState() {
    super.initState();
    _booted = List.filled(widget.count, false);
    for (int i = 0; i < widget.count; i++) {
      _staggerTimers.add(
        Timer(_kSectorStagger * i, () {
          if (mounted) setState(() => _booted[i] = true);
        }),
      );
    }
  }

  @override
  void dispose() {
    for (final timer in _staggerTimers) {
      timer.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: _ShimmerHost(
        child: Column(
          children: List.generate(widget.count, (i) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: i < widget.count - 1 ? BaselineSpacing.sm : 0,
              ),
              child: AnimatedOpacity(
                opacity: _booted[i] ? 1.0 : 0.0,
                duration: _kBootFadeDuration,
                curve: Curves.easeOut,
                child: _VoteCardInner(sectorIndex: i),
              ),
            );
          }),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// INNER SKELETONS (no shimmer host, used by list builders)
// ═══════════════════════════════════════════════════════════

/// Statement card skeleton without shimmer host wrapper.
class _StatementCardInner extends StatelessWidget {
  const _StatementCardInner({this.sectorIndex = -1});
  final int sectorIndex;

  @override
  Widget build(BuildContext context) {
    return _SkeletonCard(
      sectorIndex: sectorIndex,
      showPerfs: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(width: 3, color: BaselineColors.shimmerBase),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(BaselineSpacing.md),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final maxW = constraints.maxWidth;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const _SkeletonCircle(
                            diameter: 44,
                            showRing: true,
                          ),
                          const SizedBox(width: BaselineSpacing.sm),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _SkeletonBox(
                                  width: maxW * 0.35,
                                  height: 14,
                                  borderRadius: _kTextRadius,
                                  showHatch: true,
                                  ghostFlicker: true,
                                ),
                                const SizedBox(height: 6),
                                _SkeletonBox(
                                  width: maxW * 0.2,
                                  height: 10,
                                  borderRadius: _kTextRadius,
                                ),
                              ],
                            ),
                          ),
                          const _SkeletonBox(width: 48, height: 10),
                        ],
                      ),
                      const SizedBox(height: BaselineSpacing.sm),
                      _SkeletonBox(
                        width: maxW * 0.85,
                        height: 14,
                        borderRadius: _kTextRadius,
                        showHatch: true,
                        ghostFlicker: true,
                      ),
                      const SizedBox(height: 8),
                      _SkeletonBox(
                        width: maxW * 0.6,
                        height: 14,
                        borderRadius: _kTextRadius,
                        showHatch: true,
                        ghostFlicker: true,
                      ),
                      const SizedBox(height: BaselineSpacing.sm),
                      Row(
                        children: [
                          _SkeletonBox(
                            width: maxW * 0.22,
                            height: 8,
                            borderRadius: _kTextRadius,
                          ),
                          const SizedBox(width: BaselineSpacing.sm),
                          _SkeletonBox(
                            width: maxW * 0.22,
                            height: 8,
                            borderRadius: _kTextRadius,
                          ),
                          const Spacer(),
                          const _SkeletonBox(width: 36, height: 12),
                        ],
                      ),
                      const SizedBox(height: BaselineSpacing.xs),
                      _SkeletonBox(
                        width: maxW * 0.30,
                        height: 3,
                        borderRadius: 1.5,
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Figure row skeleton without shimmer host wrapper.
class _FigureRowInner extends StatelessWidget {
  const _FigureRowInner({this.sectorIndex = -1});
  final int sectorIndex;

  @override
  Widget build(BuildContext context) {
    return _SkeletonCard(
      sectorIndex: sectorIndex,
      minHeight: 72,
      child: Row(
        children: [
          Container(
            width: 3,
            height: 72,
            color: BaselineColors.shimmerBase,
          ),
          const SizedBox(width: BaselineSpacing.md),
          const _SkeletonCircle(diameter: 44, showRing: true),
          const SizedBox(width: BaselineSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _SkeletonBox(
                  width: 120,
                  height: 14,
                  borderRadius: _kTextRadius,
                  showHatch: true,
                  ghostFlicker: true,
                ),
                const SizedBox(height: 6),
                const _SkeletonBox(
                  width: 80,
                  height: 10,
                  borderRadius: _kTextRadius,
                ),
              ],
            ),
          ),
          // Badge with glow hint.
          Container(
            width: 40,
            height: 18,
            decoration: BoxDecoration(
              color: BaselineColors.shimmerBase,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(
                color: BaselineColors.shimmerHighlight.atOpacity(0.04),
                width: 0.5,
              ),
            ),
          ),
          const SizedBox(width: BaselineSpacing.md),
        ],
      ),
    );
  }
}

/// Vote card skeleton without shimmer host wrapper.
class _VoteCardInner extends StatelessWidget {
  const _VoteCardInner({this.sectorIndex = -1});
  final int sectorIndex;

  @override
  Widget build(BuildContext context) {
    return _SkeletonCard(
      sectorIndex: sectorIndex,
      showPerfs: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 3,
            color: BaselineColors.shimmerHighlight.atOpacity(0.2),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(BaselineSpacing.md),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final maxW = constraints.maxWidth;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          _SkeletonBox(
                            width: maxW * 0.25,
                            height: 12,
                            borderRadius: _kTextRadius,
                            showHatch: true,
                            ghostFlicker: true,
                          ),
                          const SizedBox(width: BaselineSpacing.sm),
                          const _SkeletonBox(
                            width: 48,
                            height: 9,
                            borderRadius: _kTextRadius,
                          ),
                          const Spacer(),
                          const _SkeletonBox(
                            width: 72,
                            height: 9,
                            borderRadius: _kTextRadius,
                          ),
                        ],
                      ),
                      const SizedBox(height: BaselineSpacing.xs),
                      _SkeletonBox(
                        width: maxW * 0.8,
                        height: 12,
                        borderRadius: _kTextRadius,
                        showHatch: true,
                        ghostFlicker: true,
                      ),
                      const SizedBox(height: 6),
                      _SkeletonBox(
                        width: maxW * 0.5,
                        height: 12,
                        borderRadius: _kTextRadius,
                      ),
                      const SizedBox(height: BaselineSpacing.sm),
                      Row(
                        children: [
                          Container(
                            width: 52,
                            height: 22,
                            decoration: BoxDecoration(
                              color: BaselineColors.shimmerBase,
                              borderRadius: BorderRadius.circular(11),
                              border: Border.all(
                                color: BaselineColors.shimmerHighlight
                                    .atOpacity(0.04),
                                width: 0.5,
                              ),
                            ),
                          ),
                          const SizedBox(width: BaselineSpacing.sm),
                          _SkeletonBox(
                            width: maxW * 0.28,
                            height: 10,
                            borderRadius: _kTextRadius,
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
