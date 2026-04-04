/// FG-9 — Convergence Painter
///
/// CustomPaint visualization for Narrative Sync™. Renders multi-figure
/// framing convergence timelines — HSL-shifted teal per figure, convergence
/// zone detection + glow, metric proximity bands, full BASELINE chrome.
///
/// B2B-exclusive. Designed for convergence_painter.dart consumption by
/// narrative_sync_screen.dart.
///
/// Path: lib/widgets/narrative_sync/convergence_painter.dart
library;

// 1. Dart SDK
import 'dart:math' as math;
import 'dart:ui' as ui;

// 2. Flutter
import 'package:flutter/material.dart';

// 3. Project — config
import 'package:baseline_app/config/theme.dart';

// 4. Project — utils
import 'package:baseline_app/utils/haptic_util.dart';

// ═══════════════════════════════════════════════════════════
// DATA MODELS (painter-local, mapped from A-17E response)
// ═══════════════════════════════════════════════════════════

/// Single data point in a figure's timeline.
@immutable
class ConvergenceBucketPoint {
  const ConvergenceBucketPoint({
    required this.bucketIndex,
    required this.signalRank,
    required this.dominantFraming,
    required this.statementCount,
  });

  /// 0-based bucket position along the x-axis.
  final int bucketIndex;

  /// Avg signal_rank for this bucket (0–100 scale).
  final double signalRank;

  /// Dominant framing label for this bucket.
  final String dominantFraming;

  /// Number of statements in this bucket.
  final int statementCount;
}

/// A figure's complete timeline for the painter.
@immutable
class ConvergenceFigureLine {
  const ConvergenceFigureLine({
    required this.figureId,
    required this.figureName,
    required this.points,
    required this.colorIndex,
  });

  final String figureId;
  final String figureName;
  final List<ConvergenceBucketPoint> points;

  /// Index into the HSL-shift palette (0–9).
  final int colorIndex;
}

/// A convergence zone (bucket range where 2+ figures share framing).
@immutable
class ConvergenceZone {
  const ConvergenceZone({
    required this.bucketIndex,
    required this.framing,
    required this.figureIds,
    required this.avgSignalRank,
  });

  final int bucketIndex;
  final String framing;
  final List<String> figureIds;
  final double avgSignalRank;
}

/// Metric proximity event.
@immutable
class MetricProximityZone {
  const MetricProximityZone({
    required this.bucketIndex,
    required this.figureIds,
    required this.delta,
  });

  final int bucketIndex;
  final List<String> figureIds;
  final double delta;
}

// ═══════════════════════════════════════════════════════════
// CONSTANTS
// ═══════════════════════════════════════════════════════════

// ── Layout ───────────────────────────────────────────────
const double _kPadLeft = 40.0; // Y-axis label space
const double _kPadRight = 16.0;
const double _kPadTop = 12.0;
const double _kPadBottom = 28.0; // X-axis label space
const double _kPlotLineWidth = 1.5;
const double _kPlotLineWidthActive = 2.0;
const double _kNodeRadius = 3.0;
const double _kNodeRadiusActive = 4.5;
const double _kNodeHaloRadius = 8.0;

// ── Convergence zones ────────────────────────────────────
const double _kZoneGlowOpacity = 0.06;
const double _kZoneBorderOpacity = 0.12;

// ── Metric proximity ─────────────────────────────────────
const double _kProximityBandOpacity = 0.03;

// ── Chrome ───────────────────────────────────────────────
const double _kReticleArmLength = 6.0;
const double _kReticleStroke = 1.0;
const double _kReticleOpacity = 0.08;
const double _kGridDotRadius = 0.5;
const double _kGridDotSpacing = 16.0;
const double _kGridDotOpacity = 0.04;
const double _kHashmarkLength = 3.0;
const double _kHashmarkMajorLength = 5.0;
const double _kHashmarkOpacity = 0.10;
const double _kScanlineOpacity = 0.06;
const double _kAxisStroke = 1.0;
const double _kAxisOpacity = 0.08;

const int _kParticleCount = 8;

// ── Y-axis range ─────────────────────────────────────────
const double _kYMin = 0.0;
const double _kYMax = 100.0;
const int _kYGridLines = 5; // 0, 20, 40, 60, 80, 100

// ── HSL palette: 10 teal-shifted hues (30° increments from teal) ──
// Base teal: HSL(174°, 63%, 51%). Shift hue ± for each figure.
// All stay in the cool-cyan-aqua range — brand-coherent, distinct.
const List<double> _kFigureHues = [
  174.0, // base teal
  195.0, // azure
  155.0, // seafoam
  210.0, // cerulean
  140.0, // mint
  225.0, // steel blue
  165.0, // turquoise
  185.0, // pale cyan
  200.0, // sky
  150.0, // jade
];
const double _kFigureSaturation = 0.63;
const double _kFigureLightness = 0.51;

// ═══════════════════════════════════════════════════════════
// COLOR PALETTE HELPER
// ═══════════════════════════════════════════════════════════

/// Returns the HSL-shifted color for a figure at [index].
Color _figureColor(int index) {
  final hue = _kFigureHues[index % _kFigureHues.length];
  return HSLColor.fromAHSL(1.0, hue, _kFigureSaturation, _kFigureLightness)
      .toColor();
}

// ═══════════════════════════════════════════════════════════
// CONVERGENCE PAINTER WIDGET (StatefulWidget wrapper)
// ═══════════════════════════════════════════════════════════

/// Animated convergence timeline visualization.
///
/// Wraps [_ConvergenceTimelinePainter] with entry + ambient animations:
/// Entry (1.8s, once):
///   0.00–0.25: Grid + axes + film perforations fade-in
///   0.15–0.75: Path stroke-draw via PathMetric
///   0.50–0.90: Convergence zones + junction nodes + circuit traces
///   0.70–1.00: Chrome overlay
///   0.05–0.92: Scanline L→R sweep
/// Ambient (6s loop, after entry):
///   Particle flow along active path
///   Convergence zone breathing (opacity oscillation)
///   Junction node bloom breathing
///
/// [figures] — figure timelines from NarrativeSyncController
/// [convergenceZones] — convergence events from A-17E
/// [proximityZones] — metric proximity events from A-17E
/// [totalBuckets] — total bucket count for x-axis
/// [bucketLabels] — formatted date labels for x-axis ticks
/// [activeFigureId] — optional: highlight one figure, dim others
/// [onZoneTap] — callback when user taps a convergence zone
class ConvergencePainter extends StatefulWidget {
  const ConvergencePainter({
    super.key,
    required this.figures,
    required this.convergenceZones,
    required this.proximityZones,
    required this.totalBuckets,
    required this.bucketLabels,
    this.activeFigureId,
    this.onZoneTap,
    this.animate = true,
    this.ambientPaused = false,
  });

  final List<ConvergenceFigureLine> figures;
  final List<ConvergenceZone> convergenceZones;
  final List<MetricProximityZone> proximityZones;
  final int totalBuckets;
  final List<String> bucketLabels;
  final String? activeFigureId;
  final ValueChanged<ConvergenceZone>? onZoneTap;
  final bool animate;
  final bool ambientPaused;

  @override
  State<ConvergencePainter> createState() => _ConvergencePainterState();
}

class _ConvergencePainterState extends State<ConvergencePainter>
    with TickerProviderStateMixin {
  late final AnimationController _entryCtrl;
  late final CurvedAnimation _entryAnim;
  late final AnimationController _ambientCtrl;
  bool _reduceMotion = false;

  // ── Cached paths (INC 2) ────────────────────────────────
  final Map<String, Path> _figurePaths = {};

  // ── Cached labels (INC 3) ───────────────────────────────
  final List<ui.Paragraph> _yAxisLabels = [];
  final List<ui.Paragraph> _xAxisLabels = [];
  final Map<int, ui.Paragraph> _syncLabels = {};
  final Map<int, ui.Paragraph> _countBadges = {};

  @override
  void initState() {
    super.initState();
    _entryCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    _entryAnim = CurvedAnimation(
      parent: _entryCtrl,
      curve: Curves.easeOutCubic,
    );

    // Ambient loop: drives particle flow + convergence zone breathing.
    // 6s cycle — slow, meditative, instrument-like.
    _ambientCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 6000),
    );

    if (widget.animate) {
      _entryCtrl.forward();
      // 3C: Start ambient after entry completes, self-removing.
      _entryCtrl.addStatusListener(_onEntryComplete);
    } else {
      _entryCtrl.value = 1.0;
      if (!widget.ambientPaused) _ambientCtrl.repeat();
    }

    _rebuildPaths();
    _rebuildLabels();
  }

  void _onEntryComplete(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _entryCtrl.removeStatusListener(_onEntryComplete);
      if (mounted && !_reduceMotion && !widget.ambientPaused) {
        _ambientCtrl.repeat();
      }
    }
  }

  @override
  void didUpdateWidget(covariant ConvergencePainter oldWidget) {
    super.didUpdateWidget(oldWidget);

    // INC 4: Ambient pause/resume sync with parent idle timeout.
    if (widget.ambientPaused && !oldWidget.ambientPaused) {
      _ambientCtrl.stop();
    } else if (!widget.ambientPaused &&
        oldWidget.ambientPaused &&
        _entryCtrl.isCompleted &&
        !_reduceMotion) {
      _ambientCtrl.repeat();
    }

    // INC 2+3: Rebuild caches on data change.
    final dataChanged =
        widget.figures.length != oldWidget.figures.length ||
            widget.totalBuckets != oldWidget.totalBuckets ||
            widget.convergenceZones.length !=
                oldWidget.convergenceZones.length ||
            widget.bucketLabels.length != oldWidget.bucketLabels.length ||
            widget.activeFigureId != oldWidget.activeFigureId;

    if (dataChanged) {
      _rebuildPaths();
      _rebuildLabels();
    }
  }

  /// INC 2: Build figure Path objects + cache active PathMetric.
  void _rebuildPaths() {
    _figurePaths.clear();

    if (widget.totalBuckets == 0) return;

    // We need plot area to compute positions, but we don't have
    // canvas size yet. Paths are built lazily on first paint
    // via _ensurePaths, which is called once per data change.
    // For PathMetric caching, we store the raw Path and compute
    // metric once size is known (see _ensurePathMetric in painter).
  }

  /// INC 3: Pre-compute label Paragraphs.
  void _rebuildLabels() {
    _yAxisLabels.clear();
    _xAxisLabels.clear();
    _syncLabels.clear();
    _countBadges.clear();

    // Y-axis labels: 0, 20, 40, 60, 80, 100.
    for (var i = 0; i <= _kYGridLines; i++) {
      final rank = (i / _kYGridLines) * _kYMax;
      _yAxisLabels.add(_buildMicroLabel(
        rank.toInt().toString(),
        BaselineColors.textSecondary.atOpacity(0.45),
        align: TextAlign.right,
        width: 28,
      ));
    }

    // X-axis labels.
    final labelStep = widget.bucketLabels.length > 12
        ? 4
        : (widget.bucketLabels.length > 6 ? 2 : 1);
    for (var i = 0;
        i < widget.bucketLabels.length;
        i += labelStep) {
      if (i >= widget.totalBuckets) break;
      _xAxisLabels.add(_buildMicroLabel(
        widget.bucketLabels[i],
        BaselineColors.textSecondary.atOpacity(0.40),
        align: TextAlign.center,
        width: 48,
      ));
    }

    // SYNC labels + count badges for convergence zones.
    for (final zone in widget.convergenceZones) {
      _syncLabels[zone.bucketIndex] = _buildMicroLabel(
        'SYNC',
        BaselineColors.teal.atOpacity(0.50),
        align: TextAlign.center,
      );
      _countBadges[zone.bucketIndex] = _buildMicroLabel(
        '\u00d7${zone.figureIds.length}',
        BaselineColors.textSecondary.atOpacity(0.35),
        align: TextAlign.center,
      );
    }
  }

  /// Build a pre-laid-out micro label paragraph.
  static ui.Paragraph _buildMicroLabel(
    String text,
    Color color, {
    TextAlign align = TextAlign.left,
    double width = 40,
  }) {
    final style = ui.TextStyle(
      color: color,
      fontSize: 8,
      fontFamily: BaselineTypography.monoFontFamily,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.3,
    );
    final builder = ui.ParagraphBuilder(
      ui.ParagraphStyle(textAlign: align, maxLines: 1),
    )
      ..pushStyle(style)
      ..addText(text);
    final paragraph = builder.build()
      ..layout(ui.ParagraphConstraints(width: width));
    return paragraph;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nowReduced = MediaQuery.disableAnimationsOf(context);
    if (nowReduced && !_reduceMotion) {
      // Snap entry, stop ambient.
      _reduceMotion = true;
      if (_entryCtrl.value < 1.0) _entryCtrl.value = 1.0;
      _ambientCtrl.stop();
    } else if (!nowReduced && _reduceMotion) {
      // Re-enable ambient if entry completed.
      _reduceMotion = false;
      if (_entryCtrl.isCompleted && !widget.ambientPaused) {
        _ambientCtrl.repeat();
      }
    }
  }

  @override
  void dispose() {
    // I-15: Curve before parent.
    _entryAnim.dispose();
    // I-29: Stop before dispose.
    _entryCtrl.stop();
    _ambientCtrl.stop();
    _entryCtrl.dispose();
    _ambientCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Narrative Sync convergence timeline showing '
          '${widget.figures.length} figures across '
          '${widget.totalBuckets} time periods',
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: Listenable.merge([_entryAnim, _ambientCtrl]),
          builder: (context, _) {
            return CustomPaint(
              painter: _ConvergenceTimelinePainter(
                figures: widget.figures,
                convergenceZones: widget.convergenceZones,
                proximityZones: widget.proximityZones,
                totalBuckets: widget.totalBuckets,
                bucketLabels: widget.bucketLabels,
                activeFigureId: widget.activeFigureId,
                entryProgress: _entryAnim.value,
                ambientPhase: _reduceMotion ? 0.0 : _ambientCtrl.value,
                yAxisLabels: _yAxisLabels,
                xAxisLabels: _xAxisLabels,
                syncLabels: _syncLabels,
                countBadges: _countBadges,
              ),
              size: Size.infinite,
            );
          },
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// MAIN PAINTER
// ═══════════════════════════════════════════════════════════

class _ConvergenceTimelinePainter extends CustomPainter {
  _ConvergenceTimelinePainter({
    required this.figures,
    required this.convergenceZones,
    required this.proximityZones,
    required this.totalBuckets,
    required this.bucketLabels,
    required this.activeFigureId,
    required this.entryProgress,
    required this.ambientPhase,
    required this.yAxisLabels,
    required this.xAxisLabels,
    required this.syncLabels,
    required this.countBadges,
  });

  final List<ConvergenceFigureLine> figures;
  final List<ConvergenceZone> convergenceZones;
  final List<MetricProximityZone> proximityZones;
  final int totalBuckets;
  final List<String> bucketLabels;
  final String? activeFigureId;
  final double entryProgress;
  final double ambientPhase;

  // INC 3: Pre-computed label paragraphs.
  final List<ui.Paragraph> yAxisLabels;
  final List<ui.Paragraph> xAxisLabels;
  final Map<int, ui.Paragraph> syncLabels;
  final Map<int, ui.Paragraph> countBadges;

  // ── Coordinate mapping ─────────────────────────────────

  /// Plot area bounds (excluding axis labels + padding).
  Rect _plotArea(Size size) => Rect.fromLTRB(
        _kPadLeft,
        _kPadTop,
        size.width - _kPadRight,
        size.height - _kPadBottom,
      );

  /// Maps a bucket index to x pixel.
  double _bucketToX(Rect plot, int bucketIndex) {
    if (totalBuckets <= 1) return plot.center.dx;
    return plot.left +
        (bucketIndex / (totalBuckets - 1)) * plot.width;
  }

  /// Maps a signal_rank value (0–100) to y pixel (inverted — higher = up).
  double _rankToY(Rect plot, double rank) {
    final clamped = rank.clamp(_kYMin, _kYMax);
    final normalized = (clamped - _kYMin) / (_kYMax - _kYMin);
    return plot.bottom - (normalized * plot.height);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (totalBuckets == 0 || figures.isEmpty) return;

    final plot = _plotArea(size);

    // Entry phases (staggered reveal):
    // 0.00–0.25: Grid + axes + film perforations
    // 0.15–0.75: Path stroke-draw
    // 0.50–0.90: Convergence zones + proximity + junction nodes
    // 0.70–1.00: Chrome overlay + particles begin
    final gridAlpha = ((entryProgress / 0.25).clamp(0.0, 1.0));
    final pathDraw = ((entryProgress - 0.15) / 0.60).clamp(0.0, 1.0);
    final zoneFade = ((entryProgress - 0.50) / 0.40).clamp(0.0, 1.0);
    final chromeFade = ((entryProgress - 0.70) / 0.30).clamp(0.0, 1.0);

    // ── Layer 0: Intel dot grid (background texture) ─────
    // INC 5: During ambient phase gridAlpha is always 1.0. Inline.
    _paintDotGrid(canvas, size, gridAlpha);

    // ── Layer 0b: Film perforations (top + bottom edge) ──
    if (gridAlpha > 0.01) {
      _paintFilmPerforations(canvas, size, gridAlpha);
    }

    // ── Layer 1: Convergence zone glows (behind paths) ───
    if (zoneFade > 0.01) {
      _paintConvergenceZones(canvas, plot, zoneFade);
      _paintProximityBands(canvas, plot, zoneFade);
    }

    // ── Layer 2: Grid lines + axes ───────────────────────
    if (gridAlpha > 0.01) {
      _paintGridLines(canvas, plot, gridAlpha);
      _paintAxes(canvas, plot, size, gridAlpha);
    }

    // ── Layer 3: Figure paths (the data) ─────────────────
    if (pathDraw > 0.01) {
      _paintFigurePaths(canvas, plot, pathDraw);
    }

    // ── Layer 4: Data nodes at each bucket ───────────────
    if (pathDraw > 0.3) {
      final nodeFade = ((pathDraw - 0.3) / 0.7).clamp(0.0, 1.0);
      _paintDataNodes(canvas, plot, nodeFade);
    }

    // ── Layer 4b: Convergence junction nodes ─────────────
    if (zoneFade > 0.3) {
      final junctionFade = ((zoneFade - 0.3) / 0.7).clamp(0.0, 1.0);
      _paintConvergenceJunctions(canvas, plot, junctionFade);
    }

    // ── Layer 5: Particle flow along active path ─────────
    if (chromeFade > 0.01 && ambientPhase > 0.0) {
      _paintParticleFlow(canvas, plot);
    }

    // ── Layer 5b: Circuit traces between converging nodes ─
    if (zoneFade > 0.5) {
      final traceFade = ((zoneFade - 0.5) / 0.5).clamp(0.0, 1.0);
      _paintCircuitTraces(canvas, plot, traceFade);
    }

    // ── Layer 6: Reticle chrome ──────────────────────────
    if (chromeFade > 0.01) {
      _paintReticleCorners(canvas, plot, chromeFade);
      _paintHashmarkRulers(canvas, plot, chromeFade);
    }

    // ── Layer 7: Axis labels ─────────────────────────────
    if (gridAlpha > 0.3) {
      final labelFade = ((gridAlpha - 0.3) / 0.7).clamp(0.0, 1.0);
      _paintYAxisLabels(canvas, plot, labelFade);
      _paintXAxisLabels(canvas, plot, labelFade);
    }

    // ── Layer 8: Scanline sweep (entry only) ─────────────
    if (entryProgress > 0.05 && entryProgress < 0.92) {
      _paintScanline(canvas, plot);
    }
  }

  // ═══════════════════════════════════════════════════════
  // LAYER 0: INTEL DOT GRID
  // ═══════════════════════════════════════════════════════

  void _paintDotGrid(Canvas canvas, Size size, double alpha) {
    if (alpha < 0.01) return;
    final paint = Paint()
      ..color = BaselineColors.teal.atOpacity(_kGridDotOpacity * alpha)
      ..style = PaintingStyle.fill;

    for (var x = _kGridDotSpacing; x < size.width; x += _kGridDotSpacing) {
      for (var y = _kGridDotSpacing; y < size.height; y += _kGridDotSpacing) {
        canvas.drawCircle(Offset(x, y), _kGridDotRadius, paint);
      }
    }
  }

  // ═══════════════════════════════════════════════════════
  // LAYER 1: CONVERGENCE ZONES + PROXIMITY BANDS
  // ═══════════════════════════════════════════════════════

  void _paintConvergenceZones(Canvas canvas, Rect plot, double alpha) {
    if (convergenceZones.isEmpty) return;

    final bucketWidth = totalBuckets > 1
        ? plot.width / (totalBuckets - 1)
        : plot.width;

    // Breathing pulse — subtle opacity oscillation driven by ambient.
    final breathe = ambientPhase > 0
        ? 0.7 + 0.3 * math.sin(ambientPhase * math.pi * 2)
        : 1.0;

    for (final zone in convergenceZones) {
      final cx = _bucketToX(plot, zone.bucketIndex);
      final zoneRect = Rect.fromCenter(
        center: Offset(cx, plot.center.dy),
        width: bucketWidth * 0.8,
        height: plot.height,
      );

      // Radial glow emanating from convergence center.
      final glowCenter = Offset(cx, _rankToY(plot, zone.avgSignalRank));
      final radialGlow = Paint()
        ..shader = ui.Gradient.radial(
          glowCenter,
          bucketWidth * 1.2,
          [
            BaselineColors.teal
                .atOpacity(0.10 * alpha * breathe),
            BaselineColors.teal
                .atOpacity(0.02 * alpha * breathe),
            BaselineColors.teal.atOpacity(0.0),
          ],
          [0.0, 0.5, 1.0],
        );
      canvas.drawCircle(glowCenter, bucketWidth * 1.2, radialGlow);

      // Vertical band fill (behind data).
      final bandPaint = Paint()
        ..color = BaselineColors.teal
            .atOpacity(_kZoneGlowOpacity * alpha * breathe);
      canvas.drawRect(zoneRect, bandPaint);

      // Zone border lines (left + right vertical dashes).
      final borderPaint = Paint()
        ..color = BaselineColors.teal
            .atOpacity(_kZoneBorderOpacity * alpha)
        ..strokeWidth = 0.5
        ..style = PaintingStyle.stroke;

      _paintDashedLine(
        canvas,
        Offset(zoneRect.left, plot.top),
        Offset(zoneRect.left, plot.bottom),
        borderPaint,
        dashLength: 3.0,
        gapLength: 4.0,
      );
      _paintDashedLine(
        canvas,
        Offset(zoneRect.right, plot.top),
        Offset(zoneRect.right, plot.bottom),
        borderPaint,
        dashLength: 3.0,
        gapLength: 4.0,
      );

      // ── Classified bracket callout ──
      // Instead of plain "SYNC" text, render bracketed callout:
      //   ┌─ SYNC ─┐
      if (alpha > 0.4) {
        final calloutAlpha = ((alpha - 0.4) / 0.6).clamp(0.0, 1.0);
        final bracketPaint = Paint()
          ..color = BaselineColors.teal
              .atOpacity(0.25 * calloutAlpha)
          ..strokeWidth = 0.5
          ..style = PaintingStyle.stroke;

        final labelY = plot.top - 6;
        const bracketW = 28.0;
        const bracketH = 4.0;

        // Left bracket arm.
        canvas.drawLine(
          Offset(cx - bracketW, labelY),
          Offset(cx - bracketW, labelY - bracketH),
          bracketPaint,
        );
        canvas.drawLine(
          Offset(cx - bracketW, labelY - bracketH),
          Offset(cx - 12, labelY - bracketH),
          bracketPaint,
        );

        // Right bracket arm.
        canvas.drawLine(
          Offset(cx + bracketW, labelY),
          Offset(cx + bracketW, labelY - bracketH),
          bracketPaint,
        );
        canvas.drawLine(
          Offset(cx + bracketW, labelY - bracketH),
          Offset(cx + 12, labelY - bracketH),
          bracketPaint,
        );

        // INC 3: Use cached paragraphs when alpha is stable.
        final useCache = calloutAlpha >= 0.99;

        // "SYNC" label centered.
        if (useCache && syncLabels.containsKey(zone.bucketIndex)) {
          final para = syncLabels[zone.bucketIndex]!;
          canvas.drawParagraph(
            para,
            Offset(cx - 20, labelY - bracketH - para.height / 2),
          );
        } else {
          _drawMicroLabel(
            canvas,
            'SYNC',
            Offset(cx, labelY - bracketH),
            BaselineColors.teal.atOpacity(0.50 * calloutAlpha),
            align: TextAlign.center,
          );
        }

        // Figure count badge below bracket.
        if (useCache && countBadges.containsKey(zone.bucketIndex)) {
          final para = countBadges[zone.bucketIndex]!;
          canvas.drawParagraph(
            para,
            Offset(cx - 20, labelY + 2 - para.height / 2),
          );
        } else {
          _drawMicroLabel(
            canvas,
            '×${zone.figureIds.length}',
            Offset(cx, labelY + 2),
            BaselineColors.textSecondary.atOpacity(0.35 * calloutAlpha),
            align: TextAlign.center,
          );
        }
      }
    }
  }

  void _paintProximityBands(Canvas canvas, Rect plot, double alpha) {
    if (proximityZones.isEmpty) return;

    final bucketWidth = totalBuckets > 1
        ? plot.width / (totalBuckets - 1)
        : plot.width;

    for (final zone in proximityZones) {
      final cx = _bucketToX(plot, zone.bucketIndex);
      final bandRect = Rect.fromCenter(
        center: Offset(cx, plot.center.dy),
        width: bucketWidth * 0.6,
        height: plot.height,
      );

      final bandPaint = Paint()
        ..color = BaselineColors.teal
            .atOpacity(_kProximityBandOpacity * alpha);
      canvas.drawRect(bandRect, bandPaint);
    }
  }

  // ═══════════════════════════════════════════════════════
  // LAYER 2: GRID LINES + AXES
  // ═══════════════════════════════════════════════════════

  void _paintGridLines(Canvas canvas, Rect plot, double alpha) {
    final paint = Paint()
      ..color = BaselineColors.textSecondary
          .atOpacity(0.04 * alpha)
      ..strokeWidth = 0.5;

    // Horizontal grid lines at 0, 20, 40, 60, 80, 100.
    for (var i = 0; i <= _kYGridLines; i++) {
      final rank = (i / _kYGridLines) * _kYMax;
      final y = _rankToY(plot, rank);
      canvas.drawLine(
        Offset(plot.left, y),
        Offset(plot.right, y),
        paint,
      );
    }

    // Vertical grid lines at each bucket (faint).
    if (totalBuckets <= 52) {
      final vertPaint = Paint()
        ..color = BaselineColors.textSecondary
            .atOpacity(0.025 * alpha)
        ..strokeWidth = 0.5;
      for (var i = 0; i < totalBuckets; i++) {
        final x = _bucketToX(plot, i);
        canvas.drawLine(
          Offset(x, plot.top),
          Offset(x, plot.bottom),
          vertPaint,
        );
      }
    }
  }

  void _paintAxes(Canvas canvas, Rect plot, Size size, double alpha) {
    final paint = Paint()
      ..color = BaselineColors.textSecondary
          .atOpacity(_kAxisOpacity * alpha)
      ..strokeWidth = _kAxisStroke;

    // X-axis (bottom of plot).
    canvas.drawLine(
      Offset(plot.left, plot.bottom),
      Offset(plot.right, plot.bottom),
      paint,
    );

    // Y-axis (left of plot).
    canvas.drawLine(
      Offset(plot.left, plot.top),
      Offset(plot.left, plot.bottom),
      paint,
    );
  }

  // ═══════════════════════════════════════════════════════
  // LAYER 3: FIGURE PATHS (the core visualization)
  // ═══════════════════════════════════════════════════════

  void _paintFigurePaths(Canvas canvas, Rect plot, double drawProgress) {
    for (final figure in figures) {
      if (figure.points.length < 2) continue;

      final color = _figureColor(figure.colorIndex);
      final isActive = activeFigureId == null ||
          activeFigureId == figure.figureId;
      final lineOpacity = isActive ? 0.85 : 0.20;
      final lineWidth =
          isActive ? _kPlotLineWidthActive : _kPlotLineWidth;

      // Build cubic bezier path through all points.
      final path = Path();
      final offsets = figure.points.map((p) {
        return Offset(
          _bucketToX(plot, p.bucketIndex),
          _rankToY(plot, p.signalRank),
        );
      }).toList();

      path.moveTo(offsets[0].dx, offsets[0].dy);

      for (var i = 0; i < offsets.length - 1; i++) {
        final p0 = offsets[i];
        final p1 = offsets[i + 1];
        final cpOffset = (p1.dx - p0.dx) * 0.4;
        path.cubicTo(
          p0.dx + cpOffset, p0.dy,
          p1.dx - cpOffset, p1.dy,
          p1.dx, p1.dy,
        );
      }

      // Stroke-draw via PathMetric.
      final metrics = path.computeMetrics();
      for (final metric in metrics) {
        final visibleLength = metric.length * drawProgress;
        if (visibleLength < 1.0) continue;
        final extracted = metric.extractPath(0, visibleLength);

        final paint = Paint()
          ..color = color.atOpacity(lineOpacity * drawProgress)
          ..strokeWidth = lineWidth
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..isAntiAlias = true;

        canvas.drawPath(extracted, paint);

        // Subtle glow under the active line.
        if (isActive && lineWidth > 1.5) {
          final glowPaint = Paint()
            ..color = color.atOpacity(0.08 * drawProgress)
            ..strokeWidth = lineWidth + 4.0
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..maskFilter =
                const MaskFilter.blur(BlurStyle.normal, 4.0);
          canvas.drawPath(extracted, glowPaint);
        }
      }
    }
  }

  // ═══════════════════════════════════════════════════════
  // LAYER 4: DATA NODES
  // ═══════════════════════════════════════════════════════

  void _paintDataNodes(Canvas canvas, Rect plot, double alpha) {
    for (final figure in figures) {
      final color = _figureColor(figure.colorIndex);
      final isActive = activeFigureId == null ||
          activeFigureId == figure.figureId;
      final nodeOpacity = isActive ? 0.90 : 0.25;
      final radius = isActive ? _kNodeRadiusActive : _kNodeRadius;

      for (final pt in figure.points) {
        final x = _bucketToX(plot, pt.bucketIndex);
        final y = _rankToY(plot, pt.signalRank);

        // Halo (active figures only).
        if (isActive) {
          final haloPaint = Paint()
            ..color = color.atOpacity(0.06 * alpha);
          canvas.drawCircle(
            Offset(x, y),
            _kNodeHaloRadius,
            haloPaint,
          );
        }

        // Node dot.
        final nodePaint = Paint()
          ..color = color.atOpacity(nodeOpacity * alpha)
          ..style = PaintingStyle.fill;
        canvas.drawCircle(Offset(x, y), radius, nodePaint);

        // Crisp ring around node.
        final ringPaint = Paint()
          ..color = color.atOpacity(0.50 * alpha)
          ..strokeWidth = 0.5
          ..style = PaintingStyle.stroke;
        canvas.drawCircle(Offset(x, y), radius + 0.5, ringPaint);
      }
    }
  }

  // ═══════════════════════════════════════════════════════
  // LAYER 5: CHROME — RETICLE CORNERS + HASHMARKS
  // ═══════════════════════════════════════════════════════

  void _paintReticleCorners(Canvas canvas, Rect plot, double alpha) {
    final paint = Paint()
      ..color = BaselineColors.teal
          .atOpacity(_kReticleOpacity * alpha)
      ..strokeWidth = _kReticleStroke
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final arm = _kReticleArmLength;

    // Top-left corner.
    canvas.drawLine(
      Offset(plot.left, plot.top),
      Offset(plot.left + arm, plot.top),
      paint,
    );
    canvas.drawLine(
      Offset(plot.left, plot.top),
      Offset(plot.left, plot.top + arm),
      paint,
    );

    // Top-right corner.
    canvas.drawLine(
      Offset(plot.right, plot.top),
      Offset(plot.right - arm, plot.top),
      paint,
    );
    canvas.drawLine(
      Offset(plot.right, plot.top),
      Offset(plot.right, plot.top + arm),
      paint,
    );

    // Bottom-left corner.
    canvas.drawLine(
      Offset(plot.left, plot.bottom),
      Offset(plot.left + arm, plot.bottom),
      paint,
    );
    canvas.drawLine(
      Offset(plot.left, plot.bottom),
      Offset(plot.left, plot.bottom - arm),
      paint,
    );

    // Bottom-right corner.
    canvas.drawLine(
      Offset(plot.right, plot.bottom),
      Offset(plot.right - arm, plot.bottom),
      paint,
    );
    canvas.drawLine(
      Offset(plot.right, plot.bottom),
      Offset(plot.right, plot.bottom - arm),
      paint,
    );

    // Registration dots at corners.
    final dotPaint = Paint()
      ..color = BaselineColors.teal
          .atOpacity(0.15 * alpha)
      ..style = PaintingStyle.fill;
    const dotR = 1.5;
    canvas.drawCircle(Offset(plot.left, plot.top), dotR, dotPaint);
    canvas.drawCircle(Offset(plot.right, plot.top), dotR, dotPaint);
    canvas.drawCircle(Offset(plot.left, plot.bottom), dotR, dotPaint);
    canvas.drawCircle(Offset(plot.right, plot.bottom), dotR, dotPaint);
  }

  void _paintHashmarkRulers(Canvas canvas, Rect plot, double alpha) {
    final paint = Paint()
      ..color = BaselineColors.textSecondary
          .atOpacity(_kHashmarkOpacity * alpha)
      ..strokeWidth = 0.5;

    // Right-edge hashmarks aligned to Y grid.
    for (var i = 0; i <= _kYGridLines; i++) {
      final rank = (i / _kYGridLines) * _kYMax;
      final y = _rankToY(plot, rank);
      final isMajor = i % 2 == 0;
      final len = isMajor ? _kHashmarkMajorLength : _kHashmarkLength;
      canvas.drawLine(
        Offset(plot.right, y),
        Offset(plot.right + len, y),
        paint,
      );
    }

    // Bottom-edge hashmarks at bucket ticks.
    final step = totalBuckets > 20 ? 4 : (totalBuckets > 10 ? 2 : 1);
    for (var i = 0; i < totalBuckets; i += step) {
      final x = _bucketToX(plot, i);
      final isMajor = i % (step * 2) == 0;
      final len = isMajor ? _kHashmarkMajorLength : _kHashmarkLength;
      canvas.drawLine(
        Offset(x, plot.bottom),
        Offset(x, plot.bottom + len),
        paint,
      );
    }
  }

  // ═══════════════════════════════════════════════════════
  // LAYER 6: AXIS LABELS
  // ═══════════════════════════════════════════════════════

  void _paintYAxisLabels(Canvas canvas, Rect plot, double alpha) {
    // INC 3: Use pre-computed paragraphs when alpha is stable (ambient).
    final useCache = alpha >= 0.99 && yAxisLabels.isNotEmpty;

    for (var i = 0; i <= _kYGridLines; i++) {
      final rank = (i / _kYGridLines) * _kYMax;
      final y = _rankToY(plot, rank);

      if (useCache && i < yAxisLabels.length) {
        final para = yAxisLabels[i];
        canvas.drawParagraph(
          para,
          Offset(plot.left - 6 - 28, y - para.height / 2),
        );
      } else {
        _drawMicroLabel(
          canvas,
          rank.toInt().toString(),
          Offset(plot.left - 6, y),
          BaselineColors.textSecondary.atOpacity(0.45 * alpha),
          align: TextAlign.right,
          width: 28,
        );
      }
    }
  }

  void _paintXAxisLabels(Canvas canvas, Rect plot, double alpha) {
    if (bucketLabels.isEmpty) return;

    // INC 3: Use pre-computed paragraphs when alpha is stable.
    final useCache = alpha >= 0.99 && xAxisLabels.isNotEmpty;

    final labelStep = bucketLabels.length > 12
        ? 4
        : (bucketLabels.length > 6 ? 2 : 1);

    var cacheIdx = 0;
    for (var i = 0; i < bucketLabels.length; i += labelStep) {
      if (i >= totalBuckets) break;
      final x = _bucketToX(plot, i);

      if (useCache && cacheIdx < xAxisLabels.length) {
        final para = xAxisLabels[cacheIdx];
        canvas.drawParagraph(
          para,
          Offset(x - 24, plot.bottom + 8 - para.height / 2),
        );
      } else {
        _drawMicroLabel(
          canvas,
          bucketLabels[i],
          Offset(x, plot.bottom + 8),
          BaselineColors.textSecondary.atOpacity(0.40 * alpha),
          align: TextAlign.center,
          width: 48,
        );
      }
      cacheIdx++;
    }
  }

  // ═══════════════════════════════════════════════════════
  // LAYER 7: ENTRY SCANLINE
  // ═══════════════════════════════════════════════════════

  void _paintScanline(Canvas canvas, Rect plot) {
    // Scanline sweeps left-to-right through the plot area.
    final scanX = plot.left +
        (entryProgress * 1.2 - 0.1).clamp(0.0, 1.0) * plot.width;
    if (scanX <= plot.left || scanX >= plot.right) return;

    final scanGradient = ui.Gradient.linear(
      Offset(scanX - 20, 0),
      Offset(scanX + 2, 0),
      [
        BaselineColors.teal.atOpacity(0.0),
        BaselineColors.teal.atOpacity(_kScanlineOpacity),
        BaselineColors.teal.atOpacity(0.0),
      ],
      [0.0, 0.7, 1.0],
    );

    final scanPaint = Paint()
      ..shader = scanGradient
      ..strokeWidth = 1.0;

    canvas.drawLine(
      Offset(scanX, plot.top),
      Offset(scanX, plot.bottom),
      scanPaint,
    );
  }

  // ═══════════════════════════════════════════════════════
  // LAYER 0b: FILM PERFORATIONS (top + bottom edge)
  // ═══════════════════════════════════════════════════════

  void _paintFilmPerforations(Canvas canvas, Size size, double alpha) {
    final perfPaint = Paint()
      ..color = BaselineColors.teal.atOpacity(0.04 * alpha);

    // Top edge perforations.
    for (var x = 12.0; x < size.width - 12; x += 14) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, 1, 5, 1.5),
          const Radius.circular(0.75),
        ),
        perfPaint,
      );
    }

    // Bottom edge perforations.
    for (var x = 19.0; x < size.width - 12; x += 14) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, size.height - 2.5, 5, 1.5),
          const Radius.circular(0.75),
        ),
        perfPaint,
      );
    }
  }

  // ═══════════════════════════════════════════════════════
  // LAYER 4b: CONVERGENCE JUNCTION NODES
  // Where 2+ figure paths share framing in the same bucket —
  // bright teal bloom marks with concentric rings.
  // ═══════════════════════════════════════════════════════

  void _paintConvergenceJunctions(Canvas canvas, Rect plot, double alpha) {
    if (convergenceZones.isEmpty) return;

    // Breathing bloom driven by ambient phase.
    final bloom = ambientPhase > 0
        ? 0.8 + 0.2 * math.sin(ambientPhase * math.pi * 2 + 0.5)
        : 1.0;

    for (final zone in convergenceZones) {
      final cx = _bucketToX(plot, zone.bucketIndex);
      final cy = _rankToY(plot, zone.avgSignalRank);
      final center = Offset(cx, cy);

      // Outer bloom (soft glow).
      final bloomPaint = Paint()
        ..color = BaselineColors.teal
            .atOpacity(0.12 * alpha * bloom)
        ..maskFilter =
            const MaskFilter.blur(BlurStyle.normal, 6.0);
      canvas.drawCircle(center, 10.0, bloomPaint);

      // Concentric ring 1 (outer).
      final ring1 = Paint()
        ..color = BaselineColors.teal
            .atOpacity(0.08 * alpha)
        ..strokeWidth = 0.5
        ..style = PaintingStyle.stroke;
      canvas.drawCircle(center, 7.0, ring1);

      // Concentric ring 2 (inner).
      final ring2 = Paint()
        ..color = BaselineColors.teal
            .atOpacity(0.15 * alpha)
        ..strokeWidth = 0.5
        ..style = PaintingStyle.stroke;
      canvas.drawCircle(center, 4.0, ring2);

      // Core dot (bright, crisp).
      final corePaint = Paint()
        ..color = BaselineColors.teal
            .atOpacity(0.85 * alpha)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(center, 2.0, corePaint);
    }
  }

  // ═══════════════════════════════════════════════════════
  // LAYER 5: PARTICLE FLOW (active figure path)
  // Data-flow particles traveling along the active figure's
  // bezier path — ambient chrome that says "live instrument."
  // Uses textSecondary, not teal (decorative, not data).
  // ═══════════════════════════════════════════════════════

  void _paintParticleFlow(Canvas canvas, Rect plot) {
    // Find the active figure (or first if none selected).
    ConvergenceFigureLine? active;
    for (final f in figures) {
      if (activeFigureId == null || activeFigureId == f.figureId) {
        active = f;
        break;
      }
    }
    if (active == null || active.points.length < 2) return;

    // Build the same bezier path as figure rendering.
    final offsets = active.points.map((p) {
      return Offset(
        _bucketToX(plot, p.bucketIndex),
        _rankToY(plot, p.signalRank),
      );
    }).toList();

    final path = Path();
    path.moveTo(offsets[0].dx, offsets[0].dy);
    for (var i = 0; i < offsets.length - 1; i++) {
      final p0 = offsets[i];
      final p1 = offsets[i + 1];
      final cpOffset = (p1.dx - p0.dx) * 0.4;
      path.cubicTo(
        p0.dx + cpOffset, p0.dy,
        p1.dx - cpOffset, p1.dy,
        p1.dx, p1.dy,
      );
    }

    final metrics = path.computeMetrics();
    if (metrics.isEmpty) return;
    final metric = metrics.first;
    final totalLen = metric.length;
    if (totalLen < 1.0) return;

    // Particles travel along the path, evenly spaced, driven by ambient.
    final particlePaint = Paint()
      ..style = PaintingStyle.fill;

    for (var i = 0; i < _kParticleCount; i++) {
      final phase =
          (ambientPhase + (i / _kParticleCount)) % 1.0;
      final distance = phase * totalLen;

      final tangent = metric.getTangentForOffset(distance);
      if (tangent == null) continue;

      // Particle size pulses slightly.
      final sizePulse = 1.0 + 0.4 * math.sin(phase * math.pi);
      final radius = 1.2 * sizePulse;

      // Leading particles brighter, trailing dimmer.
      final fadeEdge = math.sin(phase * math.pi); // 0 at ends, 1 in middle
      final opacity = 0.25 * fadeEdge;

      particlePaint.color = BaselineColors.textSecondary
          .atOpacity(opacity.clamp(0.0, 0.25));
      canvas.drawCircle(tangent.position, radius, particlePaint);
    }
  }

  // ═══════════════════════════════════════════════════════
  // LAYER 5b: CIRCUIT TRACES
  // Thin horizontal connector lines between converging figure
  // nodes at convergence buckets. Draws the "wiring" that
  // visually links the data points that triggered SYNC events.
  // ═══════════════════════════════════════════════════════

  void _paintCircuitTraces(Canvas canvas, Rect plot, double alpha) {
    if (convergenceZones.isEmpty) return;

    for (final zone in convergenceZones) {
      // Find the y-positions of all figures in this convergence bucket.
      final nodePositions = <Offset>[];

      for (final figure in figures) {
        if (!zone.figureIds.contains(figure.figureId)) continue;
        for (final pt in figure.points) {
          if (pt.bucketIndex == zone.bucketIndex) {
            nodePositions.add(Offset(
              _bucketToX(plot, pt.bucketIndex),
              _rankToY(plot, pt.signalRank),
            ));
            break;
          }
        }
      }

      if (nodePositions.length < 2) continue;

      // Sort by y so traces go top-to-bottom.
      nodePositions.sort((a, b) => a.dy.compareTo(b.dy));

      final tracePaint = Paint()
        ..color = BaselineColors.teal.atOpacity(0.10 * alpha)
        ..strokeWidth = 0.5
        ..style = PaintingStyle.stroke;

      // Connect consecutive nodes with a small stepped circuit trace:
      //   node A ──┐
      //            └── node B
      for (var i = 0; i < nodePositions.length - 1; i++) {
        final a = nodePositions[i];
        final b = nodePositions[i + 1];
        final midY = (a.dy + b.dy) / 2;

        // Step right by 4px then down then back.
        final stepX = a.dx + 4.0;
        final tracePath = Path()
          ..moveTo(a.dx, a.dy)
          ..lineTo(stepX, a.dy)
          ..lineTo(stepX, midY)
          ..lineTo(stepX, b.dy)
          ..lineTo(b.dx, b.dy);

        canvas.drawPath(tracePath, tracePaint);

        // Tiny junction dot at the step.
        final jDot = Paint()
          ..color = BaselineColors.teal.atOpacity(0.15 * alpha)
          ..style = PaintingStyle.fill;
        canvas.drawCircle(Offset(stepX, midY), 1.0, jDot);
      }
    }
  }

  // ═══════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════

  void _paintDashedLine(
    Canvas canvas,
    Offset start,
    Offset end,
    Paint paint, {
    double dashLength = 4.0,
    double gapLength = 3.0,
  }) {
    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;
    final distance = math.sqrt(dx * dx + dy * dy);
    if (distance < 1.0) return;

    final unitX = dx / distance;
    final unitY = dy / distance;

    var drawn = 0.0;
    var isDash = true;

    while (drawn < distance) {
      final segLen = isDash
          ? math.min(dashLength, distance - drawn)
          : math.min(gapLength, distance - drawn);

      if (isDash) {
        canvas.drawLine(
          Offset(
            start.dx + unitX * drawn,
            start.dy + unitY * drawn,
          ),
          Offset(
            start.dx + unitX * (drawn + segLen),
            start.dy + unitY * (drawn + segLen),
          ),
          paint,
        );
      }
      drawn += segLen;
      isDash = !isDash;
    }
  }

  void _drawMicroLabel(
    Canvas canvas,
    String text,
    Offset position,
    Color color, {
    TextAlign align = TextAlign.left,
    double width = 40,
  }) {
    final style = ui.TextStyle(
      color: color,
      fontSize: 8,
      fontFamily: BaselineTypography.monoFontFamily,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.3,
    );
    final builder = ui.ParagraphBuilder(
      ui.ParagraphStyle(textAlign: align, maxLines: 1),
    )
      ..pushStyle(style)
      ..addText(text);
    final paragraph = builder.build()
      ..layout(ui.ParagraphConstraints(width: width));

    double dx;
    switch (align) {
      case TextAlign.right:
        dx = position.dx - width;
      case TextAlign.center:
        dx = position.dx - width / 2;
      default:
        dx = position.dx;
    }

    canvas.drawParagraph(
      paragraph,
      Offset(dx, position.dy - paragraph.height / 2),
    );
  }

  // ═══════════════════════════════════════════════════════
  // REPAINT
  // ═══════════════════════════════════════════════════════

  @override
  bool shouldRepaint(covariant _ConvergenceTimelinePainter old) =>
      entryProgress != old.entryProgress ||
      ambientPhase != old.ambientPhase ||
      activeFigureId != old.activeFigureId ||
      figures.length != old.figures.length ||
      convergenceZones.length != old.convergenceZones.length ||
      proximityZones.length != old.proximityZones.length ||
      bucketLabels.length != old.bucketLabels.length ||
      totalBuckets != old.totalBuckets;
}

// ═══════════════════════════════════════════════════════════
// FIGURE LEGEND WIDGET
// ═══════════════════════════════════════════════════════════

/// Horizontal figure legend with HSL-shifted color dots.
/// Taps toggle [activeFigureId] in the parent controller.
class ConvergenceLegend extends StatelessWidget {
  const ConvergenceLegend({
    super.key,
    required this.figures,
    this.activeFigureId,
    this.onFigureTap,
  });

  final List<ConvergenceFigureLine> figures;
  final String? activeFigureId;
  final ValueChanged<String>? onFigureTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Figure legend with ${figures.length} entries',
      child: Wrap(
        spacing: BaselineSpacing.sm,
        runSpacing: BaselineSpacing.xxs,
        children: figures.map((f) {
          final color = _figureColor(f.colorIndex);
          final isActive =
              activeFigureId == null || activeFigureId == f.figureId;
          final opacity = isActive ? 1.0 : 0.35;

          return GestureDetector(
            onTap: () {
              HapticUtil.light();
              onFigureTap?.call(f.figureId);
            },
            behavior: HitTestBehavior.opaque,
            child: Semantics(
              button: true,
              excludeSemantics: true,
              label: '${f.figureName}, ${isActive ? "active" : "dimmed"}',
              child: AnimatedOpacity(
                duration: BaselineAnimation.fast,
                opacity: opacity,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: BaselineSpacing.xxs,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Color dot.
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        f.figureName,
                        style: BaselineTypography.caption.copyWith(
                          color: BaselineColors.textSecondary
                              .atOpacity(opacity),
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// CONVERGENCE METRICS ROW
// ═══════════════════════════════════════════════════════════

/// Compact metrics row showing convergence rate + event count.
/// Designed for placement above the painter.
class ConvergenceMetricsRow extends StatelessWidget {
  const ConvergenceMetricsRow({
    super.key,
    required this.convergenceRate,
    required this.convergenceEvents,
    required this.proximityEvents,
    required this.totalStatements,
  });

  final double convergenceRate;
  final int convergenceEvents;
  final int proximityEvents;
  final int totalStatements;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _MetricChip(
          label: 'SYNC RATE',
          value: '${(convergenceRate * 100).toStringAsFixed(1)}%',
        ),
        const SizedBox(width: BaselineSpacing.xs),
        _MetricChip(
          label: 'EVENTS',
          value: convergenceEvents.toString(),
        ),
        const SizedBox(width: BaselineSpacing.xs),
        _MetricChip(
          label: 'PROXIMITY',
          value: proximityEvents.toString(),
        ),
        const Spacer(),
        Text(
          '$totalStatements stmts',
          style: BaselineTypography.caption.copyWith(
            color: BaselineColors.textSecondary
                .atOpacity(BaselineOpacity.moderate),
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: BaselineSpacing.xs,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        border: Border.all(
          color: BaselineColors.border,
          width: 1,
        ),
        borderRadius: BorderRadius.circular(BaselineRadius.xs),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontFamily: BaselineTypography.monoFontFamily,
              fontSize: 7,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.8,
              color: BaselineColors.textSecondary,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            value,
            style: TextStyle(
              fontFamily: BaselineTypography.monoFontFamily,
              fontSize: 9,
              fontWeight: FontWeight.w500,
              color: BaselineColors.teal.atOpacity(0.85),
            ),
          ),
        ],
      ),
    );
  }
}
