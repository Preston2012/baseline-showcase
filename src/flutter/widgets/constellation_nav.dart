/// FG-2 -- Constellation Nav™
///
/// Signal intelligence star chart for figure profiles. A sensor sweep
/// discovers data points and maps measurement activity as a constellation.
/// Each dot encodes signal density: brighter means more activity.
/// Pro-gated trademark surface.
///
/// Path: lib/widgets/constellation_nav.dart
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:baseline_app/config/baseline_colors.dart';
import 'package:baseline_app/config/baseline_spacing.dart';
import 'package:baseline_app/config/baseline_typography.dart';
import 'package:baseline_app/utils/haptic_util.dart';
import 'package:baseline_app/config/theme.dart';

// ═══════════════════════════════════════════════════════════
// CONSTANTS
// ═══════════════════════════════════════════════════════════

// ── Geometry ───────────────────────────────────────────────
const double _kStripHeight = 72.0;
const double _kHorizontalPad = 20.0;
const double _kVerticalPad = 16.0;
const double _kBorderWidth = 2.0;
const double _kBorderRadius = 8.0;
const double _kReticleLength = 10.0;
const double _kReticleStroke = 1.5;
const double _kReticleInset = 4.0;
const double _kTickHeight = 4.0;
const double _kTickSpacing = 12.0;
const double _kTickStroke = 0.5;
const double _kGridlineOpacity = 0.04;
const double _kRegDotRadius = 1.2;
const double _kRegDotInset = 8.0;

// ── Dots ───────────────────────────────────────────────────
const double _kDotRadiusMin = 2.0;
const double _kDotRadiusMax = 5.5;
const double _kDotOpacityMin = 0.2;
const double _kDotOpacityMax = 1.0;
const double _kJitterAmplitude = 12.0;
const double _kIdealDotSpacing = 18.0;

// ── Filaments ──────────────────────────────────────────────
const double _kFilamentOpacity = 0.07;
const double _kFilamentStroke = 0.7;

// ── Variance halo ──────────────────────────────────────────
const double _kHaloMultiplier = 2.4;
const double _kHaloOpacity = 0.15;

// ── Selection ──────────────────────────────────────────────
const double _kCrosshairLength = 12.0;
const double _kCrosshairStroke = 0.8;
const double _kCrosshairGap = 3.0;
const double _kCrosshairOpacity = 0.5;
const double _kLabelFontSize = 9.0;
const double _kLabelOffsetY = 14.0;
const double _kPingMaxRadius = 16.0;
const Duration _kPingDuration = Duration(milliseconds: 1400);
const int _kPingRepeatCount = 3;
const Duration _kFlashDuration = Duration(milliseconds: 200);

// ── Background star dust ───────────────────────────────────
const int _kStarDustCount = 30;
const double _kStarDustRadius = 0.8;
const double _kStarDustOpacity = 0.03;
const double _kStarDustParallax = 0.3;

// ── Signal envelope ────────────────────────────────────────
const double _kEnvelopeOpacity = 0.02;

// ── Breathing (idle twinkle) ───────────────────────────────
const int _kBreathingDotCount = 3;
const Duration _kBreathingDuration = Duration(milliseconds: 4000);
const double _kBreathingAmplitude = 0.12;
const int _kBreathingCycles = 6;

// ── Animation timing ───────────────────────────────────────
const Duration _kScanlineDuration = Duration(milliseconds: 900);
const int _kMaxEntryMs = 2800;
const double _kScanlineHeight = 1.5;
const double _kScanlineHalfWidth = 35.0;
const double _kIgnitionFadeWindow = 40.0;
const double _kPhosphorTrailWidth = 60.0;
const double _kPhosphorTrailOpacity = 0.05;

// ── Interaction ────────────────────────────────────────────
const double _kTapRadius = 22.0;
const double _kCountFontSize = 9.0;
const double _kViewportBarHeight = 1.5;
const double _kViewportBarBottom = 3.0;
const Duration _kHapticDebounce = Duration(milliseconds: 200);
const double _kBrandingFontSize = 7.0;
const double _kWatermarkFontSize = 7.0;
const double _kLegendDotSmall = 2.0;
const double _kLegendDotLarge = 5.0;
const double _kAxisLabelFontSize = 6.0;

// ── Cluster nebula ─────────────────────────────────────────
const double _kClusterRadius = 24.0;
const int _kClusterMinDots = 3;
const double _kClusterGlowOpacity = 0.02;

// ═══════════════════════════════════════════════════════════
// DATA MODELS
// ═══════════════════════════════════════════════════════════

/// A single point in the constellation.
class ConstellationPoint {
  const ConstellationPoint({
    required this.id,
    required this.signalRank,
    this.noveltyScore = 50.0,
    this.varianceDetected = false,
  });

  final String id;
  final double signalRank;
  final double noveltyScore;
  final bool varianceDetected;
}

/// Precomputed cluster center for nebula glow rendering.
class _ClusterCenter {
  const _ClusterCenter(this.center, this.radius);
  final Offset center;
  final double radius;
}

// ═══════════════════════════════════════════════════════════
// DTG FORMATTER
// ═══════════════════════════════════════════════════════════

String _dtgFormat() {
  final now = DateTime.now().toUtc();
  final d = now.day.toString().padLeft(2, '0');
  final h = now.hour.toString().padLeft(2, '0');
  final m = now.minute.toString().padLeft(2, '0');
  return '$d$h${m}Z';
}

// ═══════════════════════════════════════════════════════════
// WIDGET
// ═══════════════════════════════════════════════════════════

class ConstellationNav extends StatefulWidget {
  const ConstellationNav({
    super.key,
    required this.points,
    this.selectedId,
    this.onStatementSelected,
  });

  final List<ConstellationPoint> points;
  final String? selectedId;
  final ValueChanged<String>? onStatementSelected;

  @override
  State<ConstellationNav> createState() => _ConstellationNavState();
}

class _ConstellationNavState extends State<ConstellationNav>
    with TickerProviderStateMixin {
  // ── Controllers ──────────────────────────────────────────
  late final AnimationController _scanlineCtrl;
  late final CurvedAnimation _scanlineCurved;
  late final AnimationController _entryCtrl;
  late final AnimationController _breathingCtrl;
  late final CurvedAnimation _breathingCurved;
  AnimationController? _pingCtrl;
  CurvedAnimation? _pingCurved;
  AnimationController? _flashCtrl;

  final ScrollController _scrollCtrl = ScrollController();

  List<Offset> _starDust = const [];
  double _starDustWidth = 0;
  List<int> _breathingIndices = const [];
  List<Offset> _dotPositions = const [];
  List<_ClusterCenter> _clusterCenters = const [];
  double _contentWidth = 0;
  double _viewportWidth = 0;
  bool _isScrollable = false;
  int _lastPointsCount = -1;
  double _lastLayoutWidth = -1;
  DateTime _lastHapticTime = DateTime(2000);
  bool _reduceMotion = false;
  bool _hasScrolled = false;
  String _dtgStamp = _dtgFormat();

  @override
  void initState() {
    super.initState();

    _scanlineCtrl = AnimationController(
      vsync: this,
      duration: _kScanlineDuration,
    );
    _scanlineCurved = CurvedAnimation(
      parent: _scanlineCtrl,
      curve: Curves.easeInOut,
    );

    final entryMs = (400 + (widget.points.length * 20))
        .clamp(400, _kMaxEntryMs);
    _entryCtrl = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: entryMs),
    );

    _breathingCtrl = AnimationController(
      vsync: this,
      duration: _kBreathingDuration,
    );
    _breathingCurved = CurvedAnimation(
      parent: _breathingCtrl,
      curve: Curves.easeInOut,
    );

    _computeBreathingIndices();
    _createPingIfNeeded();
    _scrollCtrl.addListener(_onScroll);
    _entryCtrl.addStatusListener(_onEntryComplete);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.disableAnimationsOf(context);
    if (reduce != _reduceMotion) {
      _reduceMotion = reduce;
      _applyMotionPolicy();
    }
  }

  void _applyMotionPolicy() {
    if (_reduceMotion) {
      _scanlineCtrl.value = 1.0;
      _entryCtrl.value = 1.0;
      _breathingCtrl.stop();
      _pingCtrl?.stop();
      _flashCtrl?.stop();
    } else {
      if (!_scanlineCtrl.isAnimating && _scanlineCtrl.value < 1.0) {
        _scanlineCtrl.forward();
      }
      if (!_entryCtrl.isAnimating && _entryCtrl.value < 1.0) {
        _entryCtrl.forward();
      }
    }
  }

  void _onEntryComplete(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    _entryCtrl.removeStatusListener(_onEntryComplete);
    if (mounted && !_reduceMotion && _breathingIndices.isNotEmpty) {
      _breathingCtrl.repeat(
        reverse: true,
        count: _kBreathingCycles,
      );
    }
  }

  @override
  void didUpdateWidget(ConstellationNav oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedId != widget.selectedId) {
      _disposePing();
      _createPingIfNeeded();
      _fireAcquisitionFlash();
    }
    if (oldWidget.points.length != widget.points.length) {
      _lastPointsCount = -1;
      _lastLayoutWidth = -1;
      _computeBreathingIndices();
    }
  }

  void _computeBreathingIndices() {
    final count = widget.points.length;
    if (count == 0) {
      _breathingIndices = const [];
      return;
    }
    final indexed = List.generate(count, (i) => i);
    indexed.sort((a, b) {
      final cmp = widget.points[b].signalRank
          .compareTo(widget.points[a].signalRank);
      return cmp != 0 ? cmp : a.compareTo(b);
    });
    final take = _kBreathingDotCount.clamp(0, count);
    _breathingIndices = indexed.take(take).toList();
  }

  void _createPingIfNeeded() {
    if (widget.selectedId == null || _reduceMotion) return;
    _pingCtrl = AnimationController(
      vsync: this,
      duration: _kPingDuration,
    );
    _pingCurved = CurvedAnimation(
      parent: _pingCtrl!,
      curve: Curves.easeOut,
    );
    _pingCtrl!.repeat(count: _kPingRepeatCount);
  }

  void _fireAcquisitionFlash() {
    if (_reduceMotion || widget.selectedId == null) return;
    _flashCtrl?.dispose();
    _flashCtrl = AnimationController(
      vsync: this,
      duration: _kFlashDuration,
    );
    _flashCtrl!.forward().then((_) {
      if (mounted) {
        _flashCtrl?.dispose();
        _flashCtrl = null;
      }
    });
  }

  void _disposePing() {
    _pingCurved?.dispose();
    _pingCurved = null;
    _pingCtrl?.dispose();
    _pingCtrl = null;
  }

  void _onScroll() {
    if (!_hasScrolled && _scrollCtrl.hasClients) {
      _hasScrolled = true;
      HapticUtil.light();
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    // 1. Scroll controller.
    _scrollCtrl.removeListener(_onScroll);
    _scrollCtrl.dispose();

    // 2. Flash controller (ephemeral).
    _flashCtrl?.dispose();

    // 3. Ping: CurvedAnimation before parent.
    _pingCurved?.dispose();
    _pingCtrl?.dispose();

    // 4. Breathing: CurvedAnimation before parent.
    _breathingCtrl.stop();
    _breathingCurved.dispose();
    _breathingCtrl.dispose();

    // 5. Entry.
    _entryCtrl.dispose();

    // 6. Scanline: CurvedAnimation before parent.
    _scanlineCurved.dispose();
    _scanlineCtrl.dispose();

    super.dispose();
  }

  // ── Layout ───────────────────────────────────────────────
  void _computeLayoutIfNeeded(double viewportWidth) {
    final count = widget.points.length;
    if (count == _lastPointsCount &&
        viewportWidth == _lastLayoutWidth) {
      return;
    }
    _lastPointsCount = count;
    _lastLayoutWidth = viewportWidth;

    // Refresh DTG at data boundary, not per-build.
    _dtgStamp = _dtgFormat();

    if (count == 0) {
      _dotPositions = const [];
      _clusterCenters = const [];
      _contentWidth = viewportWidth;
      _isScrollable = false;
      return;
    }

    final centerY = _kStripHeight / 2;

    if (count == 1) {
      _dotPositions = [Offset(viewportWidth / 2, centerY)];
      _clusterCenters = const [];
      _contentWidth = viewportWidth;
      _isScrollable = false;
      return;
    }

    final idealWidth =
        _kHorizontalPad * 2 + (count - 1) * _kIdealDotSpacing;
    _contentWidth = math.max(idealWidth, viewportWidth);
    _isScrollable = _contentWidth > viewportWidth + 1;

    final usableContent = _contentWidth - (_kHorizontalPad * 2);
    final spacing = usableContent / (count - 1);

    final positions = <Offset>[];
    for (int i = 0; i < count; i++) {
      final x = _kHorizontalPad + (i * spacing);
      final noveltyNorm =
          (widget.points[i].noveltyScore / 100.0).clamp(0.0, 1.0);
      final jitterSign = i.isEven ? 1.0 : -1.0;
      final jitter =
          jitterSign * (noveltyNorm - 0.5) * _kJitterAmplitude * 2;
      final y = (centerY + jitter).clamp(
        _kVerticalPad,
        _kStripHeight - _kVerticalPad,
      );
      positions.add(Offset(x, y));
    }
    _dotPositions = positions;

    // Precompute cluster centers (O(N^2) once at layout, not per-frame).
    _clusterCenters = _computeClusters(positions);

    // Regenerate star dust if content width changed.
    if (_contentWidth != _starDustWidth) {
      _starDustWidth = _contentWidth;
      _starDust = _generateStarDust(_contentWidth, _kStripHeight);
    }
  }

  /// Precompute cluster centers from dot positions.
  /// O(N^2) but runs only on data/layout change, not per-frame.
  static List<_ClusterCenter> _computeClusters(List<Offset> positions) {
    if (positions.length < _kClusterMinDots) return const [];

    // Track which positions already contributed to a cluster center
    // to avoid duplicate overlapping glows.
    final used = <int>{};
    final clusters = <_ClusterCenter>[];

    for (int i = 0; i < positions.length; i++) {
      if (used.contains(i)) continue;
      final nearby = <int>[i];

      for (int j = i + 1; j < positions.length; j++) {
        if ((positions[i] - positions[j]).distance < _kClusterRadius) {
          nearby.add(j);
        }
      }

      if (nearby.length >= _kClusterMinDots) {
        double cx = 0, cy = 0;
        for (final idx in nearby) {
          cx += positions[idx].dx;
          cy += positions[idx].dy;
          used.add(idx);
        }
        clusters.add(_ClusterCenter(
          Offset(cx / nearby.length, cy / nearby.length),
          _kClusterRadius,
        ));
      }
    }
    return clusters;
  }

  List<Offset> _generateStarDust(double width, double height) {
    final rng = math.Random(widget.points.length * 7 + 42);
    return List.generate(_kStarDustCount, (_) {
      return Offset(
        rng.nextDouble() * width,
        rng.nextDouble() * height,
      );
    });
  }

  // ── Tap handling ─────────────────────────────────────────
  void _handleTapDown(TapDownDetails details) {
    if (_dotPositions.isEmpty) return;

    // localPosition is already in content coordinates (GestureDetector
    // is child of scroll content). No scroll offset adjustment needed.
    final local = details.localPosition;

    double bestDist = double.infinity;
    int bestIdx = -1;
    for (int i = 0; i < _dotPositions.length; i++) {
      final dist = (local - _dotPositions[i]).distance;
      if (dist < bestDist && dist <= _kTapRadius) {
        bestDist = dist;
        bestIdx = i;
      }
    }

    if (bestIdx >= 0 && bestIdx < widget.points.length) {
      final now = DateTime.now();
      if (now.difference(_lastHapticTime) >= _kHapticDebounce) {
        _lastHapticTime = now;
        HapticUtil.selection();
      }
      widget.onStatementSelected?.call(widget.points[bestIdx].id);
    }
  }

  // ── Build ────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (widget.points.isEmpty) return const SizedBox.shrink();

    final textScaler = MediaQuery.textScalerOf(context);

    return RepaintBoundary(
      child: Semantics(
        label: 'Constellation Nav\u2122: ${widget.points.length} statements. '
            'Signal density encoded in dot brightness. '
            'Tap a dot to view statement details.',
        child: LayoutBuilder(
          builder: (context, constraints) {
            _viewportWidth = constraints.maxWidth;
            _computeLayoutIfNeeded(_viewportWidth);

            return Container(
              height: _kStripHeight,
              decoration: BoxDecoration(
                border: Border.all(
                  color: BaselineColors.borderInactive,
                  width: _kBorderWidth,
                ),
                borderRadius: BorderRadius.circular(_kBorderRadius),
              ),
              clipBehavior: Clip.antiAlias,
              child: _isScrollable
                  ? _buildScrollable(textScaler)
                  : _buildStatic(textScaler),
            );
          },
        ),
      ),
    );
  }

  Widget _buildStatic(TextScaler textScaler) {
    return Semantics(
      button: true,
      onTapHint: 'Select statement dot',
      child: GestureDetector(
        onTapDown: _handleTapDown,
        behavior: HitTestBehavior.opaque,
        child: ListenableBuilder(
          listenable: Listenable.merge([
            _scanlineCtrl,
            _entryCtrl,
            _breathingCtrl,
            ?_pingCtrl,
            ?_flashCtrl,
          ]),
          builder: (context, _) => CustomPaint(
            size: Size(_viewportWidth, _kStripHeight),
            painter: _ConstellationPainter(
              points: widget.points,
              positions: _dotPositions,
              clusterCenters: _clusterCenters,
              selectedId: widget.selectedId,
              scanlineT: _scanlineCurved.value,
              entryT: _entryCtrl.value,
              breathingT: _breathingCurved.value,
              breathingIndices: _breathingIndices,
              pingT: _pingCurved?.value ?? 0.0,
              flashT: _flashCtrl?.value ?? 0.0,
              starDust: _starDust,
              dtgStamp: _dtgStamp,
              teal: BaselineColors.teal,
              amber: BaselineColors.amber,
              borderColor: BaselineColors.borderInactive,
              textSecondary: BaselineColors.textSecondary,
              contentWidth: _viewportWidth,
              viewportOffset: 0,
              viewportWidth: _viewportWidth,
              isScrollable: false,
              textScaler: textScaler,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildScrollable(TextScaler textScaler) {
    return SingleChildScrollView(
      controller: _scrollCtrl,
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Semantics(
        button: true,
        onTapHint: 'Select statement dot',
        child: GestureDetector(
          onTapDown: _handleTapDown,
          behavior: HitTestBehavior.opaque,
          child: ListenableBuilder(
            listenable: Listenable.merge([
              _scanlineCtrl,
              _entryCtrl,
              _breathingCtrl,
              ?_pingCtrl,
              ?_flashCtrl,
            ]),
            builder: (context, _) => CustomPaint(
              size: Size(_contentWidth, _kStripHeight),
              painter: _ConstellationPainter(
                points: widget.points,
                positions: _dotPositions,
                clusterCenters: _clusterCenters,
                selectedId: widget.selectedId,
                scanlineT: _scanlineCurved.value,
                entryT: _entryCtrl.value,
                breathingT: _breathingCurved.value,
                breathingIndices: _breathingIndices,
                pingT: _pingCurved?.value ?? 0.0,
                flashT: _flashCtrl?.value ?? 0.0,
                starDust: _starDust,
                dtgStamp: _dtgStamp,
                teal: BaselineColors.teal,
                amber: BaselineColors.amber,
                borderColor: BaselineColors.borderInactive,
                textSecondary: BaselineColors.textSecondary,
                contentWidth: _contentWidth,
                viewportOffset: _scrollCtrl.hasClients
                    ? _scrollCtrl.offset
                    : 0.0,
                viewportWidth: _viewportWidth,
                isScrollable: true,
                textScaler: textScaler,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// PAINTER
// ═══════════════════════════════════════════════════════════

class _ConstellationPainter extends CustomPainter {
  _ConstellationPainter({
    required this.points,
    required this.positions,
    required this.clusterCenters,
    required this.selectedId,
    required this.scanlineT,
    required this.entryT,
    required this.breathingT,
    required this.breathingIndices,
    required this.pingT,
    required this.flashT,
    required this.starDust,
    required this.dtgStamp,
    required this.teal,
    required this.amber,
    required this.borderColor,
    required this.textSecondary,
    required this.contentWidth,
    required this.viewportOffset,
    required this.viewportWidth,
    required this.isScrollable,
    required this.textScaler,
  });

  final List<ConstellationPoint> points;
  final List<Offset> positions;
  final List<_ClusterCenter> clusterCenters;
  final String? selectedId;
  final double scanlineT;
  final double entryT;
  final double breathingT;
  final List<int> breathingIndices;
  final double pingT;
  final double flashT;
  final List<Offset> starDust;
  final String dtgStamp;
  final Color teal;
  final Color amber;
  final Color borderColor;
  final Color textSecondary;
  final double contentWidth;
  final double viewportOffset;
  final double viewportWidth;
  final bool isScrollable;
  final TextScaler textScaler;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty || positions.isEmpty) return;

    _drawStarDust(canvas, size);
    _drawSignalEnvelope(canvas, size);
    _drawClusterNebulae(canvas);
    _drawCenterGridline(canvas, size);
    _drawHashmarks(canvas, size);
    _drawFilaments(canvas);

    if (scanlineT > 0 && scanlineT < 1.0) {
      _drawPhosphorTrail(canvas, size);
      _drawScanline(canvas, size);
    }

    _drawDots(canvas);
    _drawAcquisitionFlash(canvas);
    _drawCrosshair(canvas);
    _drawPing(canvas);
    _drawReticleCorners(canvas, size);
    _drawRegistrationDots(canvas, size);
    _drawCountBadge(canvas, size);
    _drawMagnitudeLegend(canvas, size);
    _drawNoveltyAxisLabels(canvas, size);
    _drawTmBranding(canvas, size);
    _drawDtgWatermark(canvas, size);

    if (isScrollable) {
      _drawViewportIndicator(canvas, size);
    }
  }

  // ── Star dust (parallactic depth) ────────────────────────
  void _drawStarDust(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = teal.atOpacity(_kStarDustOpacity)
      ..style = PaintingStyle.fill;

    final revealX = scanlineT * size.width;
    final parallaxShift = viewportOffset * _kStarDustParallax;

    for (final star in starDust) {
      final shiftedX = star.dx - parallaxShift;
      if (shiftedX > revealX && scanlineT < 1.0) continue;
      canvas.drawCircle(
        Offset(shiftedX, star.dy),
        _kStarDustRadius,
        paint,
      );
    }
  }

  // ── Signal envelope (distribution awareness) ──────────────
  void _drawSignalEnvelope(Canvas canvas, Size size) {
    if (positions.length < 3 || entryT < 0.5) return;

    final envelopeOpacity =
        (_kEnvelopeOpacity * ((entryT - 0.5) * 2).clamp(0.0, 1.0));

    final upperPath = Path();

    for (int i = 0; i < positions.length; i++) {
      final pos = positions[i];
      final rankNorm =
          (points[i].signalRank / 100.0).clamp(0.0, 1.0);
      final radius = _kDotRadiusMin +
          (rankNorm * (_kDotRadiusMax - _kDotRadiusMin));

      if (i == 0) {
        upperPath.moveTo(pos.dx, pos.dy - radius - 3);
      } else {
        upperPath.lineTo(pos.dx, pos.dy - radius - 3);
      }
    }

    final envelope = Path()..addPath(upperPath, Offset.zero);
    for (int i = positions.length - 1; i >= 0; i--) {
      final pos = positions[i];
      final rankNorm =
          (points[i].signalRank / 100.0).clamp(0.0, 1.0);
      final radius = _kDotRadiusMin +
          (rankNorm * (_kDotRadiusMax - _kDotRadiusMin));
      envelope.lineTo(pos.dx, pos.dy + radius + 3);
    }
    envelope.close();

    canvas.drawPath(
      envelope,
      Paint()
        ..color = teal.atOpacity(envelopeOpacity)
        ..style = PaintingStyle.fill,
    );
  }

  // ── Cluster nebulae (precomputed density glow) ────────────
  void _drawClusterNebulae(Canvas canvas) {
    if (clusterCenters.isEmpty || entryT < 1.0) return;

    for (final cluster in clusterCenters) {
      final gradient = RadialGradient(
        colors: [
          teal.atOpacity(_kClusterGlowOpacity),
          teal.atOpacity(0.0),
        ],
      );
      canvas.drawCircle(
        cluster.center,
        cluster.radius,
        Paint()
          ..shader = gradient.createShader(
            Rect.fromCircle(
                center: cluster.center, radius: cluster.radius),
          ),
      );
    }
  }

  // ── Center gridline ──────────────────────────────────────
  void _drawCenterGridline(Canvas canvas, Size size) {
    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      Paint()
        ..color = teal.atOpacity(_kGridlineOpacity)
        ..strokeWidth = 0.5,
    );
  }

  // ── Hashmark ruler ───────────────────────────────────────
  void _drawHashmarks(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = borderColor.atOpacity(0.3)
      ..strokeWidth = _kTickStroke;

    final bottom = size.height;
    final tickCount = (size.width / _kTickSpacing).floor();
    for (int i = 0; i <= tickCount; i++) {
      final x = i * _kTickSpacing;
      final height = (i % 5 == 0) ? _kTickHeight * 1.5 : _kTickHeight;
      canvas.drawLine(
        Offset(x, bottom),
        Offset(x, bottom - height),
        paint,
      );
    }
  }

  // ── Filaments ────────────────────────────────────────────
  void _drawFilaments(Canvas canvas) {
    if (positions.length < 2) return;

    final paint = Paint()
      ..strokeWidth = _kFilamentStroke
      ..style = PaintingStyle.stroke;

    for (int i = 0; i < positions.length - 1; i++) {
      final a = _ignitionProgress(i);
      final b = _ignitionProgress(i + 1);
      if (a <= 0 || b <= 0) continue;

      final fraction = math.min(a, b);
      final opacity = (_kFilamentOpacity * fraction).clamp(0.0, 1.0);
      paint.color = teal.atOpacity(opacity);

      if (fraction >= 1.0) {
        // Full line: fast path.
        canvas.drawLine(positions[i], positions[i + 1], paint);
      } else {
        // Partial trace-on via linear interpolation.
        final end = Offset.lerp(positions[i], positions[i + 1], fraction)!;
        canvas.drawLine(positions[i], end, paint);
      }
    }
  }

  // ── Phosphor trail (scanline wake) ───────────────────────
  void _drawPhosphorTrail(Canvas canvas, Size size) {
    final x = scanlineT * size.width;
    final trailStart = (x - _kPhosphorTrailWidth).clamp(0.0, size.width);

    final trailRect = Rect.fromLTRB(trailStart, 0, x, size.height);
    final gradient = LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: [
        teal.atOpacity(0.0),
        teal.atOpacity(_kPhosphorTrailOpacity),
      ],
    );

    canvas.drawRect(
      trailRect,
      Paint()..shader = gradient.createShader(trailRect),
    );
  }

  // ── Scanline ─────────────────────────────────────────────
  void _drawScanline(Canvas canvas, Size size) {
    final x = scanlineT * size.width;

    final beamRect = Rect.fromLTWH(
      x - _kScanlineHalfWidth,
      (size.height - _kScanlineHeight) / 2,
      _kScanlineHalfWidth * 2,
      _kScanlineHeight,
    );
    canvas.drawRect(
      beamRect,
      Paint()
        ..shader = LinearGradient(
          colors: [
            teal.atOpacity(0.0),
            teal.atOpacity(0.5),
            teal.atOpacity(0.0),
          ],
          stops: const [0.0, 0.5, 1.0],
        ).createShader(beamRect),
    );

    canvas.drawLine(
      Offset(x, 0),
      Offset(x, size.height),
      Paint()
        ..color = teal.atOpacity(0.08)
        ..strokeWidth = 0.5,
    );
  }

  // ── Dots ─────────────────────────────────────────────────
  void _drawDots(Canvas canvas) {
    for (int i = 0; i < points.length; i++) {
      if (i >= positions.length) break;
      final pt = points[i];
      final pos = positions[i];
      final ignition = _ignitionProgress(i);
      if (ignition <= 0) continue;

      final rankNorm = (pt.signalRank / 100.0).clamp(0.0, 1.0);
      final isSelected = pt.id == selectedId;

      final radius = _kDotRadiusMin +
          (rankNorm * (_kDotRadiusMax - _kDotRadiusMin));

      var opacity = (_kDotOpacityMin +
              (rankNorm * (_kDotOpacityMax - _kDotOpacityMin))) *
          ignition;

      if (entryT >= 1.0 && breathingIndices.contains(i)) {
        final phase = (i * 0.33) % 1.0;
        final breathOffset = math.sin(
                (breathingT + phase) * math.pi * 2) *
            _kBreathingAmplitude;
        opacity = (opacity + breathOffset).clamp(0.0, 1.0);
      }

      // Variance double-ring halo.
      if (pt.varianceDetected) {
        final haloOp = (_kHaloOpacity * ignition).clamp(0.0, 1.0);
        canvas.drawCircle(
          pos,
          radius * _kHaloMultiplier,
          Paint()
            ..color = teal.atOpacity(haloOp)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.0,
        );
        canvas.drawCircle(
          pos,
          radius * _kHaloMultiplier * 0.7,
          Paint()
            ..color = teal.atOpacity(haloOp * 0.6)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.5,
        );
      }

      // Dot fill.
      canvas.drawCircle(
        pos,
        radius * ignition,
        Paint()..color = teal.atOpacity(opacity.clamp(0.0, 1.0)),
      );

      // Selected persistent ring.
      if (isSelected) {
        canvas.drawCircle(
          pos,
          radius + 3.0,
          Paint()
            ..color = teal.atOpacity(
              (0.7 * ignition).clamp(0.0, 1.0),
            )
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
      }
    }
  }

  // ── Acquisition flash ────────────────────────────────────
  void _drawAcquisitionFlash(Canvas canvas) {
    if (flashT <= 0 || selectedId == null) return;
    final idx = points.indexWhere((p) => p.id == selectedId);
    if (idx < 0 || idx >= positions.length) return;

    final pos = positions[idx];
    final rankNorm = (points[idx].signalRank / 100.0).clamp(0.0, 1.0);
    final radius = _kDotRadiusMin +
        (rankNorm * (_kDotRadiusMax - _kDotRadiusMin));
    final flashRadius = radius + (flashT * 10);
    final flashOpacity = ((1.0 - flashT) * 0.4).clamp(0.0, 1.0);
    final flashColor = points[idx].varianceDetected ? amber : teal;

    if (flashOpacity > 0.01) {
      canvas.drawCircle(
        pos,
        flashRadius,
        Paint()
          ..color = flashColor.atOpacity(flashOpacity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
  }

  // ── Crosshair + signal label ─────────────────────────────
  void _drawCrosshair(Canvas canvas) {
    if (selectedId == null) return;
    final idx = points.indexWhere((p) => p.id == selectedId);
    if (idx < 0 || idx >= positions.length) return;
    final ignition = _ignitionProgress(idx);
    if (ignition <= 0) return;

    final pos = positions[idx];
    final rankNorm =
        (points[idx].signalRank / 100.0).clamp(0.0, 1.0);
    final radius = _kDotRadiusMin +
        (rankNorm * (_kDotRadiusMax - _kDotRadiusMin));
    final crossColor = points[idx].varianceDetected ? amber : teal;

    final paint = Paint()
      ..color = crossColor.atOpacity(
        (_kCrosshairOpacity * ignition).clamp(0.0, 1.0),
      )
      ..strokeWidth = _kCrosshairStroke;

    final gap = radius + _kCrosshairGap;
    final arm = _kCrosshairLength;

    canvas.drawLine(
      Offset(pos.dx, pos.dy - gap),
      Offset(pos.dx, pos.dy - arm),
      paint,
    );
    canvas.drawLine(
      Offset(pos.dx, pos.dy + gap),
      Offset(pos.dx, pos.dy + arm),
      paint,
    );
    canvas.drawLine(
      Offset(pos.dx - gap, pos.dy),
      Offset(pos.dx - arm, pos.dy),
      paint,
    );
    canvas.drawLine(
      Offset(pos.dx + gap, pos.dy),
      Offset(pos.dx + arm, pos.dy),
      paint,
    );

    // Signal rank label above (text-scaled).
    final tp = TextPainter(
      text: TextSpan(
        text: points[idx].signalRank.toStringAsFixed(0),
        style: TextStyle(
          fontFamily: BaselineTypography.monoFontFamily,
          fontSize: textScaler.scale(_kLabelFontSize),
          color: crossColor.atOpacity(
            (0.7 * ignition).clamp(0.0, 1.0),
          ),
          letterSpacing: 0.8,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    tp.paint(
      canvas,
      Offset(
        pos.dx - tp.width / 2,
        pos.dy - _kLabelOffsetY - tp.height,
      ),
    );
    tp.dispose();
  }

  // ── Ping ripple ──────────────────────────────────────────
  void _drawPing(Canvas canvas) {
    if (selectedId == null || pingT <= 0) return;
    final idx = points.indexWhere((p) => p.id == selectedId);
    if (idx < 0 || idx >= positions.length) return;

    final pos = positions[idx];
    final rankNorm =
        (points[idx].signalRank / 100.0).clamp(0.0, 1.0);
    final baseRadius = _kDotRadiusMin +
        (rankNorm * (_kDotRadiusMax - _kDotRadiusMin));
    final pingRadius =
        baseRadius + (pingT * (_kPingMaxRadius - baseRadius));
    final pingOpacity = ((1.0 - pingT) * 0.3).clamp(0.0, 1.0);

    if (pingOpacity > 0.01) {
      canvas.drawCircle(
        pos,
        pingRadius,
        Paint()
          ..color = teal.atOpacity(pingOpacity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8,
      );
    }
  }

  // ── Reticle corners ──────────────────────────────────────
  void _drawReticleCorners(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = teal.atOpacity(0.2)
      ..strokeWidth = _kReticleStroke
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.square;

    final i = _kReticleInset;
    final l = _kReticleLength;
    final w = size.width;
    final h = size.height;

    canvas.drawLine(Offset(i, i), Offset(i + l, i), paint);
    canvas.drawLine(Offset(i, i), Offset(i, i + l), paint);
    canvas.drawLine(Offset(w - i, i), Offset(w - i - l, i), paint);
    canvas.drawLine(Offset(w - i, i), Offset(w - i, i + l), paint);
    canvas.drawLine(Offset(i, h - i), Offset(i + l, h - i), paint);
    canvas.drawLine(Offset(i, h - i), Offset(i, h - i - l), paint);
    canvas.drawLine(
        Offset(w - i, h - i), Offset(w - i - l, h - i), paint);
    canvas.drawLine(
        Offset(w - i, h - i), Offset(w - i, h - i - l), paint);
  }

  // ── Registration dots ────────────────────────────────────
  void _drawRegistrationDots(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = teal.atOpacity(0.1)
      ..style = PaintingStyle.fill;

    final d = _kRegDotInset;
    final r = _kRegDotRadius;
    final w = size.width;
    final h = size.height;

    canvas.drawCircle(Offset(d, d), r, paint);
    canvas.drawCircle(Offset(w - d, d), r, paint);
    canvas.drawCircle(Offset(d, h - d), r, paint);
    canvas.drawCircle(Offset(w - d, h - d), r, paint);
  }

  // ── Count badge (text-scaled) ────────────────────────────
  void _drawCountBadge(Canvas canvas, Size size) {
    final tp = TextPainter(
      text: TextSpan(
        text: '${points.length} pts',
        style: TextStyle(
          fontFamily: BaselineTypography.monoFontFamily,
          fontSize: textScaler.scale(_kCountFontSize),
          color: textSecondary.atOpacity(0.35),
          letterSpacing: 0.5,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    tp.paint(
      canvas,
      Offset(
        size.width - tp.width - _kReticleInset - 2,
        _kReticleInset + 2,
      ),
    );
    tp.dispose();
  }

  // ── Magnitude scale legend ───────────────────────────────
  void _drawMagnitudeLegend(Canvas canvas, Size size) {
    if (entryT < 1.0) return;

    final legendY = _kReticleInset + 3;
    final legendX = _kReticleInset + _kReticleLength + 4;
    const legendOpacity = 0.25;

    canvas.drawCircle(
      Offset(legendX, legendY + 3),
      _kLegendDotSmall,
      Paint()..color = teal.atOpacity(legendOpacity),
    );
    canvas.drawLine(
      Offset(legendX + 4, legendY + 3),
      Offset(legendX + 8, legendY + 3),
      Paint()
        ..color = teal.atOpacity(0.12)
        ..strokeWidth = 0.5,
    );
    canvas.drawCircle(
      Offset(legendX + 12, legendY + 3),
      _kLegendDotLarge,
      Paint()..color = teal.atOpacity(legendOpacity),
    );
  }

  // ── Novelty axis labels (text-scaled) ────────────────────
  void _drawNoveltyAxisLabels(Canvas canvas, Size size) {
    if (entryT < 1.0) return;

    final labelColor = textSecondary.atOpacity(0.18);
    final scaledSize = textScaler.scale(_kAxisLabelFontSize);

    final hiTp = TextPainter(
      text: TextSpan(
        text: 'HI',
        style: TextStyle(
          fontFamily: BaselineTypography.monoFontFamily,
          fontSize: scaledSize,
          color: labelColor,
          letterSpacing: 0.8,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    hiTp.paint(canvas, Offset(2, _kVerticalPad - 2));
    hiTp.dispose();

    final loTp = TextPainter(
      text: TextSpan(
        text: 'LO',
        style: TextStyle(
          fontFamily: BaselineTypography.monoFontFamily,
          fontSize: scaledSize,
          color: labelColor,
          letterSpacing: 0.8,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    loTp.paint(
      canvas,
      Offset(2, size.height - _kVerticalPad - loTp.height + 2),
    );
    loTp.dispose();
  }

  // ── TM branding (text-scaled) ────────────────────────────
  void _drawTmBranding(Canvas canvas, Size size) {
    if (entryT < 1.0) return;

    final tp = TextPainter(
      text: TextSpan(
        text: 'CONSTELLATION NAV\u2122',
        style: TextStyle(
          fontFamily: BaselineTypography.monoFontFamily,
          fontSize: textScaler.scale(_kBrandingFontSize),
          color: teal.atOpacity(0.12),
          letterSpacing: 1.2,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    tp.paint(
      canvas,
      Offset(
        _kReticleInset + 2,
        size.height - _kReticleInset - tp.height - 2,
      ),
    );
    tp.dispose();
  }

  // ── DTG watermark (rotated -90°, text-scaled, cached UTC) ─
  void _drawDtgWatermark(Canvas canvas, Size size) {
    if (entryT < 1.0) return;

    final tp = TextPainter(
      text: TextSpan(
        text: dtgStamp,
        style: TextStyle(
          fontFamily: BaselineTypography.monoFontFamily,
          fontSize: textScaler.scale(_kWatermarkFontSize),
          color: textSecondary.atOpacity(0.08),
          letterSpacing: 0.8,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    canvas.save();
    canvas.translate(
      size.width - _kReticleInset - 2,
      size.height / 2 + tp.width / 2,
    );
    canvas.rotate(-math.pi / 2);
    tp.paint(canvas, Offset.zero);
    canvas.restore();
    tp.dispose();
  }

  // ── Viewport indicator ───────────────────────────────────
  void _drawViewportIndicator(Canvas canvas, Size size) {
    if (contentWidth <= viewportWidth) return;
    final maxScroll =
        (contentWidth - viewportWidth).clamp(1.0, double.infinity);
    final t = (viewportOffset / maxScroll).clamp(0.0, 1.0);
    final barWidth = (viewportWidth / contentWidth) * size.width;
    final barX = t * (size.width - barWidth);
    final barY = size.height - _kViewportBarBottom;

    canvas.drawLine(
      Offset(0, barY),
      Offset(size.width, barY),
      Paint()
        ..color = borderColor.atOpacity(0.15)
        ..strokeWidth = _kViewportBarHeight,
    );
    canvas.drawLine(
      Offset(barX.clamp(0, size.width), barY),
      Offset(
        (barX + barWidth).clamp(0, size.width),
        barY,
      ),
      Paint()
        ..color = teal.atOpacity(0.4)
        ..strokeWidth = _kViewportBarHeight
        ..strokeCap = StrokeCap.round,
    );
  }

  // ── Ignition progress ────────────────────────────────────
  double _ignitionProgress(int i) {
    if (i >= positions.length) return 0.0;
    if (scanlineT >= 1.0) return entryT.clamp(0.0, 1.0);

    final dotX = positions[i].dx;
    final scanX = scanlineT * contentWidth;
    if (scanX < dotX) return 0.0;

    final distance = scanX - dotX;
    final fade = (distance / _kIgnitionFadeWindow).clamp(0.0, 1.0);
    return (fade * entryT).clamp(0.0, 1.0);
  }

  @override
  bool shouldRepaint(_ConstellationPainter old) {
    return old.scanlineT != scanlineT ||
        old.entryT != entryT ||
        old.breathingT != breathingT ||
        old.pingT != pingT ||
        old.flashT != flashT ||
        old.selectedId != selectedId ||
        old.textScaler != textScaler ||
        !identical(old.points, points) ||
        !identical(old.positions, positions) ||
        !identical(old.clusterCenters, clusterCenters);
  }
}
