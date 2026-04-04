/// FG-3 — Topic Heatmap
///
/// Single-canvas thermal intelligence grid. Figures x topics where the
/// entire data matrix is painted in one CustomPaint pass. Visible scanline
/// beam with phosphor trail, full-span crosshair targeting, radial heat
/// gradients, void cross-hatch markers, hashmark rulers, DTG timestamp,
/// SIG hash, intel dot grid, registration dots. Pro+ gated.
///
/// Path: lib/widgets/topic_heatmap.dart
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:baseline_app/config/baseline_colors.dart';
import 'package:baseline_app/config/baseline_spacing.dart';
import 'package:baseline_app/config/baseline_typography.dart';
import 'package:baseline_app/utils/haptic_util.dart';
import 'package:baseline_app/config/theme.dart';
import 'package:baseline_app/widgets/empty_state_widget.dart';

// ═══════════════════════════════════════════════════════════
// CONSTANTS
// ═══════════════════════════════════════════════════════════

// ── Cell geometry ──────────────────────────────────────────
const double _kCellWidth = 48.0;
const double _kCellHeight = 28.0;
const double _kCellRadius = 3.0;
const double _kCellGap = 2.0;
const double _kCellOpacityMin = 0.025;
const double _kCellOpacityMax = 0.78;

/// Row layout step: 44px for accessibility touch targets.
/// Visual cell height stays at _kCellHeight (28px); vertical gap absorbs rest.
const double _kRowStep = 44.0;

/// Epsilon for sub-pixel hit test edge tolerance.
const double _kHitEpsilon = 0.5;

// ── Radiance ───────────────────────────────────────────────
const double _kRadianceMinFrac = 0.15;
const double _kRadianceMaxFrac = 0.85;

// ── Void cross-hatch ───────────────────────────────────────
const double _kVoidArmLength = 3.5;
const double _kVoidStroke = 0.4;
const double _kVoidOpacity = 0.10;

// ── Peak ───────────────────────────────────────────────────
const double _kPeakBorderWidth = 1.0;
const double _kPeakBorderOpacity = 0.55;

// ── Adjacency bleed ────────────────────────────────────────
const double _kBleedThreshold = 0.45;
const double _kBleedOpacity = 0.06;

// ── Row headers ────────────────────────────────────────────
const double _kRowHeaderWidth = 140.0;
const double _kRowNumberWidth = 28.0;
const double _kFigureNameFontSize = 9.5;
const double _kRowNumberFontSize = 7.5;

// ── Column headers ─────────────────────────────────────────
const double _kColumnHeaderHeight = 76.0;
const double _kTopicFontSize = 8.0;
const double _kDesignatorFontSize = 7.0;
const double _kTopicRotation = -55.0 * math.pi / 180.0;
const double _kTickMarkHeight = 4.0;
const double _kTickMarkStroke = 0.5;

// ── Frame ──────────────────────────────────────────────────
const double _kBorderWidth = 2.0;
const double _kBorderRadius = 8.0;
const double _kReticleLength = 10.0;
const double _kReticleStroke = 1.5;
const double _kReticleInset = 4.0;
const double _kTitleFontSize = 7.0;
const int _kPerfDotCount = 16;
const double _kPerfDotRadius = 1.2;
const double _kPerfDotOpacity = 0.08;
const double _kRegDotRadius = 1.0;
const double _kRegDotOpacity = 0.12;
const double _kRegDotInset = 6.0;

// ── Heat legend ────────────────────────────────────────────
const double _kLegendHeight = 14.0;
const double _kLegendBarHeight = 3.0;
const double _kLegendFontSize = 7.0;
const double _kLegendPadH = 8.0;

// ── Selection ──────────────────────────────────────────────
const double _kCrosshairStroke = 0.5;
const double _kCrosshairOpacity = 0.10;
const double _kSelectedRingWidth = 1.5;
const double _kSelectedRingOpacity = 0.8;
const double _kCountFontSize = 9.0;
const double _kSelectedRowTint = 0.018;

// ── Scanline ───────────────────────────────────────────────
const Duration _kScanlineDuration = Duration(milliseconds: 1100);
const double _kScanlineGlowHalf = 18.0;
const double _kScanlineCoreWidth = 1.5;
const double _kScanlineCoreOpacity = 0.45;
const double _kScanlineGlowOpacity = 0.12;
const double _kPhosphorTrailWidth = 40.0;
const double _kPhosphorOpacity = 0.04;

// ── Breathing ──────────────────────────────────────────────
const Duration _kBreathingDuration = Duration(milliseconds: 3500);
const int _kBreathingCycles = 5;
const double _kBreathingAmplitude = 0.08;

// ── Interaction ────────────────────────────────────────────
const Duration _kHapticDebounce = Duration(milliseconds: 200);

// ── Hashmark ruler ─────────────────────────────────────────
const double _kRulerTickWidth = 3.0;
const double _kRulerTickStroke = 0.5;
const double _kRulerTickOpacity = 0.08;
const double _kRulerMajorWidth = 6.0;
const double _kRulerMajorStroke = 0.8;
const double _kRulerMajorOpacity = 0.12;
const int _kRulerMajorEvery = 5;

// ── Intel dot grid ─────────────────────────────────────────
const double _kDotGridSpacing = 12.0;
const double _kDotGridRadius = 0.3;
const double _kDotGridOpacity = 0.03;

// ── Edge gradient ──────────────────────────────────────────
const double _kEdgeGradientHeight = 8.0;
const double _kEdgeGradientOpacity = 0.15;

// ── Row alternate tint ─────────────────────────────────────
const double _kRowAltOpacity = 0.012;

// ── Topics ─────────────────────────────────────────────────
const Map<String, String> _kTopicDisplayNames = {
  'ECONOMY': 'Econ',
  'IMMIGRATION': 'Immig',
  'AI_TECHNOLOGY': 'AI',
  'FOREIGN_POLICY': 'FP',
  'HEALTHCARE': 'Health',
  'CLIMATE_ENVIRONMENT': 'Clim',
  'CRIME_JUSTICE': 'CJ',
  'ELECTIONS': 'Elec',
  'MILITARY_DEFENSE': 'Mil',
  'CULTURE_SOCIETY': 'Cult',
  'OTHER': 'Other',
};

const List<String> _kTopicOrder = [
  'ECONOMY', 'IMMIGRATION', 'AI_TECHNOLOGY', 'FOREIGN_POLICY',
  'HEALTHCARE', 'CLIMATE_ENVIRONMENT', 'CRIME_JUSTICE', 'ELECTIONS',
  'MILITARY_DEFENSE', 'CULTURE_SOCIETY', 'OTHER',
];

const String _kDesignators = 'ABCDEFGHIJK';

// ═══════════════════════════════════════════════════════════
// DATA MODEL
// ═══════════════════════════════════════════════════════════

class HeatmapFigure {
  const HeatmapFigure({
    required this.figureId,
    required this.displayName,
    required this.topicCounts,
  });

  final String figureId;
  final String displayName;
  final Map<String, int> topicCounts;

  int countFor(String topic) => topicCounts[topic] ?? 0;
}

// ═══════════════════════════════════════════════════════════
// COMPACT COUNT FORMATTER
// ═══════════════════════════════════════════════════════════

/// Formats count for cell label: 999 -> "999", 1200 -> "1.2k".
String _formatCount(int count) {
  if (count < 1000) return '$count';
  if (count < 10000) {
    final k = count / 1000;
    return '${k.toStringAsFixed(1)}k';
  }
  return '${(count / 1000).toStringAsFixed(0)}k';
}

// ═══════════════════════════════════════════════════════════
// SIG HASH (deterministic FNV-1a)
// ═══════════════════════════════════════════════════════════

/// Generates a short hex hash from matrix dimensions for SIG footer.
String _sigHash(int rows, int cols) {
  int h = 0x811c9dc5;
  final bytes = [rows, cols, rows * cols, rows ^ cols];
  for (final b in bytes) {
    h ^= b & 0xFF;
    h = (h * 0x01000193) & 0xFFFFFFFF;
  }
  return h.toRadixString(16).padLeft(8, '0').substring(0, 8).toUpperCase();
}

// ═══════════════════════════════════════════════════════════
// DTG FORMATTER
// ═══════════════════════════════════════════════════════════

/// DTG timestamp in military format, UTC.
String _dtgFormat() {
  final now = DateTime.now().toUtc();
  final d = now.day.toString().padLeft(2, '0');
  final h = now.hour.toString().padLeft(2, '0');
  final m = now.minute.toString().padLeft(2, '0');
  const months = [
    'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
    'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC',
  ];
  final mon = months[now.month - 1];
  return '$d$h${m}Z $mon ${now.year}';
}

// ═══════════════════════════════════════════════════════════
// WIDGET
// ═══════════════════════════════════════════════════════════

class TopicHeatmap extends StatefulWidget {
  const TopicHeatmap({
    super.key,
    required this.figures,
    this.onCellTap,
    this.onFigureTap,
  });

  final List<HeatmapFigure> figures;
  final void Function(String figureId, String topic)? onCellTap;
  final ValueChanged<String>? onFigureTap;

  @override
  State<TopicHeatmap> createState() => _TopicHeatmapState();
}

class _TopicHeatmapState extends State<TopicHeatmap>
    with TickerProviderStateMixin {
  late final AnimationController _scanlineCtrl;
  late final CurvedAnimation _scanlineCurved;
  late final AnimationController _breathingCtrl;
  late final CurvedAnimation _breathingCurved;

  final List<Timer> _pendingTimers = [];

  (int, int)? _selectedCell;
  List<int> _columnMaxes = const [];
  DateTime _lastHapticTime = DateTime(2000);
  bool _reduceMotion = false;

  /// Cached DTG stamp, refreshed on data change (not per-build).
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
    _breathingCtrl = AnimationController(
      vsync: this,
      duration: _kBreathingDuration,
    );
    _breathingCurved = CurvedAnimation(
      parent: _breathingCtrl,
      curve: Curves.easeInOut,
    );

    // Status listener chain: scanline complete -> start breathing.
    _scanlineCtrl.addStatusListener(_onScanlineComplete);
    _computeMaxes();
  }

  void _onScanlineComplete(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _scanlineCtrl.removeStatusListener(_onScanlineComplete);
      if (mounted && !_reduceMotion) _startBreathingIfNeeded();
    }
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
      // Mid-flight: stop, cancel, snap to end state.
      _scanlineCtrl
        ..stop()
        ..value = 1.0;
      _breathingCtrl
        ..stop()
        ..value = 0.0;
      for (final t in _pendingTimers) {
        t.cancel();
      }
      _pendingTimers.clear();
    } else {
      if (!_scanlineCtrl.isAnimating && _scanlineCtrl.value < 1.0) {
        _scanlineCtrl.forward();
      } else if (_scanlineCtrl.value >= 1.0) {
        // Scanline already complete (rebuild / data refresh).
        _startBreathingIfNeeded();
      }
    }
  }

  /// Start breathing if conditions met and not already running.
  void _startBreathingIfNeeded() {
    if (!mounted || _reduceMotion) return;
    if (_breathingCtrl.isAnimating) return;
    if (!_columnMaxes.any((m) => m > 0)) return;
    _breathingCtrl.repeat(reverse: true, count: _kBreathingCycles);
  }

  @override
  void didUpdateWidget(TopicHeatmap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.figures, widget.figures)) {
      _computeMaxes();
    }
  }

  void _computeMaxes() {
    _columnMaxes = List.generate(_kTopicOrder.length, (col) {
      final topic = _kTopicOrder[col];
      int m = 0;
      for (final fig in widget.figures) {
        final c = fig.countFor(topic);
        if (c > m) m = c;
      }
      return m;
    });
    // Refresh DTG at data boundary, not per-build.
    _dtgStamp = _dtgFormat();
    if (!_reduceMotion) _applyMotionPolicy();
  }

  @override
  void dispose() {
    // 1. Cancel pending timers.
    for (final t in _pendingTimers) {
      t.cancel();
    }
    _pendingTimers.clear();
    // 2. CurvedAnimations first (reverse creation order).
    _breathingCurved.dispose();
    _scanlineCurved.dispose();
    // 3. Parent controllers.
    _breathingCtrl.dispose();
    _scanlineCtrl.dispose();
    super.dispose();
  }

  // ── Tap handling ─────────────────────────────────────────

  /// Gap-aware hit testing with bounds protection and epsilon tolerance.
  void _onGridTapDown(TapDownDetails details) {
    final local = details.localPosition;
    final stepX = _kCellWidth + _kCellGap;
    final col = (local.dx / stepX).floor();
    final row = (local.dy / _kRowStep).floor();

    // Reject taps in the gap between cells (with epsilon tolerance).
    final dxInStep = local.dx % stepX;
    final dyInStep = local.dy % _kRowStep;
    if (dxInStep > _kCellWidth + _kHitEpsilon) return;
    if (dyInStep > _kCellHeight + _kHitEpsilon) return;

    // Bounds check (including >= 0 for overscroll protection).
    if (row < 0 || row >= widget.figures.length) return;
    if (col < 0 || col >= _kTopicOrder.length) return;

    setState(() {
      _selectedCell = _selectedCell == (row, col) ? null : (row, col);
    });
    _fireHaptic();
    widget.onCellTap?.call(
      widget.figures[row].figureId,
      _kTopicOrder[col],
    );
  }

  void _onFigureTap(int row) {
    if (row < 0 || row >= widget.figures.length) return;
    _fireHaptic();
    widget.onFigureTap?.call(widget.figures[row].figureId);
  }

  void _fireHaptic() {
    final now = DateTime.now();
    if (now.difference(_lastHapticTime) >= _kHapticDebounce) {
      _lastHapticTime = now;
      HapticUtil.light();
    }
  }

  // ── Build ────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (widget.figures.isEmpty) {
      return const EmptyStateWidget(
        message: 'No heatmap data available.',
        icon: Icons.grid_off_rounded,
      );
    }

    final figCount = widget.figures.length;
    final hash = _sigHash(figCount, _kTopicOrder.length);

    return Semantics(
      label: 'Topic Heatmap. $figCount figures across '
          '${_kTopicOrder.length} topics. '
          'Heat intensity shows statement count per topic. '
          'Absence is signal. '
          'Tap cells to filter feed. Tap figure names for profile.',
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(
            color: BaselineColors.borderInactive,
            width: _kBorderWidth,
          ),
          borderRadius: BorderRadius.circular(_kBorderRadius),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildFrameHeader(figCount),
                Flexible(child: _buildScrollableContent(context)),
                _buildFooter(figCount, hash),
              ],
            ),
            // Frame overlay (reticle corners + perforations + registration dots).
            Positioned.fill(
              child: ExcludeSemantics(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _FrameOverlayPainter(
                      teal: BaselineColors.teal,
                      borderColor: BaselineColors.borderInactive,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFrameHeader(int figCount) {
    return ExcludeSemantics(
      child: Padding(
        padding: const EdgeInsets.only(
          left: _kReticleInset + 2,
          top: _kReticleInset + 2,
          right: _kReticleInset + 2,
          bottom: 2,
        ),
        child: Row(
          children: [
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  'SIGNAL DENSITY MATRIX // FG-3 // '
                  '${figCount}x${_kTopicOrder.length}',
                  style: TextStyle(
                    fontFamily: BaselineTypography.monoFontFamily,
                    fontSize: _kTitleFontSize,
                    color: BaselineColors.textSecondary.atOpacity(0.25),
                    letterSpacing: 1.5,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter(int figCount, String hash) {
    return ExcludeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: _kLegendPadH,
          vertical: 2,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeatLegend(),
            const SizedBox(height: 2),
            Row(
              children: [
                // DTG timestamp (cached at data refresh).
                Text(
                  _dtgStamp,
                  style: TextStyle(
                    fontFamily: BaselineTypography.monoFontFamily,
                    fontSize: 6.5,
                    color: BaselineColors.textSecondary.atOpacity(0.12),
                    letterSpacing: 0.5,
                  ),
                ),
                const Spacer(),
                // SIG hash.
                Text(
                  'SIG:$hash',
                  style: TextStyle(
                    fontFamily: BaselineTypography.monoFontFamily,
                    fontSize: 6.5,
                    color: BaselineColors.teal.atOpacity(0.10),
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 1),
            // Micro-text identity line.
            Text(
              'THERMAL GRID // $figCount FIGURES \u00D7 14 AXES',
              style: TextStyle(
                fontFamily: BaselineTypography.monoFontFamily,
                fontSize: 6.0,
                color: BaselineColors.textSecondary.atOpacity(0.08),
                letterSpacing: 1.0,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Heat legend with "per-topic" normalization note.
  Widget _buildHeatLegend() {
    return SizedBox(
      height: _kLegendHeight,
      child: Row(
        children: [
          Text(
            '0',
            style: TextStyle(
              fontFamily: BaselineTypography.monoFontFamily,
              fontSize: _kLegendFontSize,
              color: BaselineColors.textSecondary.atOpacity(0.25),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Container(
              height: _kLegendBarHeight,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(1),
                gradient: LinearGradient(
                  colors: [
                    BaselineColors.teal.atOpacity(_kCellOpacityMin),
                    BaselineColors.teal.atOpacity(0.25),
                    BaselineColors.teal.atOpacity(0.55),
                    BaselineColors.teal.atOpacity(_kCellOpacityMax),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            'MAX',
            style: TextStyle(
              fontFamily: BaselineTypography.monoFontFamily,
              fontSize: _kLegendFontSize,
              color: BaselineColors.textSecondary.atOpacity(0.25),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            'per topic',
            style: TextStyle(
              fontFamily: BaselineTypography.monoFontFamily,
              fontSize: _kLegendFontSize - 1,
              color: BaselineColors.textSecondary.atOpacity(0.15),
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScrollableContent(BuildContext context) {
    final gridWidth = _kTopicOrder.length * (_kCellWidth + _kCellGap);
    final gridHeight = widget.figures.length * _kRowStep;
    final textScaler = MediaQuery.textScalerOf(context);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: SizedBox(
        width: _kRowNumberWidth + _kRowHeaderWidth + gridWidth + 8,
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildColumnHeaders(),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Row headers column.
                  SizedBox(
                    width: _kRowNumberWidth + _kRowHeaderWidth,
                    height: gridHeight,
                    child: Column(
                      children: List.generate(
                        widget.figures.length,
                        (row) => _buildRowHeader(row),
                      ),
                    ),
                  ),
                  // Single CustomPaint canvas for entire grid.
                  GestureDetector(
                    onTapDown: _onGridTapDown,
                    behavior: HitTestBehavior.opaque,
                    child: RepaintBoundary(
                      child: ListenableBuilder(
                        listenable: Listenable.merge([
                          _scanlineCtrl,
                          _breathingCtrl,
                        ]),
                        builder: (context, _) => CustomPaint(
                          size: Size(gridWidth, gridHeight),
                          painter: _GridPainter(
                            figures: widget.figures,
                            columnMaxes: _columnMaxes,
                            selectedCell: _selectedCell,
                            scanlineT: _scanlineCurved.value,
                            breathingT: _breathingCurved.value,
                            scanlineComplete: _scanlineCtrl.value >= 1.0,
                            teal: BaselineColors.teal,
                            textSecondary: BaselineColors.textSecondary,
                            textScaler: textScaler,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: BaselineSpacing.xs),
            ],
          ),
        ),
      ),
    );
  }

  /// Column designators (A-N) + rotated short topic names + tick marks.
  Widget _buildColumnHeaders() {
    return ExcludeSemantics(
      child: SizedBox(
        height: _kColumnHeaderHeight,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            SizedBox(width: _kRowNumberWidth + _kRowHeaderWidth),
            ...List.generate(_kTopicOrder.length, (col) {
              final topic = _kTopicOrder[col];
              final display = _kTopicDisplayNames[topic] ?? topic;
              final letter = col < _kDesignators.length
                  ? _kDesignators[col]
                  : '?';
              return SizedBox(
                width: _kCellWidth + _kCellGap,
                height: _kColumnHeaderHeight,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      letter,
                      style: TextStyle(
                        fontFamily: BaselineTypography.monoFontFamily,
                        fontSize: _kDesignatorFontSize,
                        color: BaselineColors.textSecondary
                            .atOpacity(0.2),
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Expanded(
                      child: Align(
                        alignment: Alignment.bottomLeft,
                        child: Transform.rotate(
                          angle: _kTopicRotation,
                          alignment: Alignment.bottomLeft,
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              display,
                              style: TextStyle(
                                fontFamily: BaselineTypography.monoFontFamily,
                                fontSize: _kTopicFontSize,
                                color: BaselineColors.textSecondary
                                    .atOpacity(0.4),
                                letterSpacing: 0.3,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Tick mark alignment indicator.
                    Container(
                      width: _kTickMarkStroke,
                      height: _kTickMarkHeight,
                      color: BaselineColors.textSecondary
                          .atOpacity(0.08),
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

  Widget _buildRowHeader(int row) {
    if (row >= widget.figures.length) return const SizedBox.shrink();
    final figure = widget.figures[row];
    final isSelectedRow = _selectedCell?.$1 == row;

    return SizedBox(
      height: _kRowStep,
      child: Row(
        children: [
          // Row number: decorative index, excluded from semantics.
          ExcludeSemantics(
            child: SizedBox(
              width: _kRowNumberWidth,
              child: Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(left: 6, right: 3),
                  child: Text(
                    '${row + 1}'.padLeft(2, '0'),
                    style: TextStyle(
                      fontFamily: BaselineTypography.monoFontFamily,
                      fontSize: _kRowNumberFontSize,
                      color: BaselineColors.textSecondary
                          .atOpacity(isSelectedRow ? 0.5 : 0.2),
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Figure name: interactive, 44px hit target via full _kRowStep.
          Semantics(
            button: true,
            label: 'View profile: ${figure.displayName}',
            child: GestureDetector(
              onTap: () => _onFigureTap(row),
              behavior: HitTestBehavior.opaque,
              child: SizedBox(
                width: _kRowHeaderWidth,
                height: _kRowStep,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.only(left: 6, right: 4),
                    decoration: isSelectedRow
                        ? BoxDecoration(
                            border: Border(
                              left: BorderSide(
                                color: BaselineColors.teal.atOpacity(0.5),
                                width: 2,
                              ),
                            ),
                          )
                        : null,
                    child: Text(
                      figure.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: BaselineTypography.monoFontFamily,
                        fontSize: _kFigureNameFontSize,
                        color: isSelectedRow
                            ? BaselineColors.textPrimary
                            : BaselineColors.textSecondary.atOpacity(0.6),
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// GRID PAINTER — single canvas for entire data matrix
// ═══════════════════════════════════════════════════════════

class _GridPainter extends CustomPainter {
  _GridPainter({
    required this.figures,
    required this.columnMaxes,
    required this.selectedCell,
    required this.scanlineT,
    required this.breathingT,
    required this.scanlineComplete,
    required this.teal,
    required this.textSecondary,
    required this.textScaler,
  });

  final List<HeatmapFigure> figures;
  final List<int> columnMaxes;
  final (int, int)? selectedCell;
  final double scanlineT;
  final double breathingT;
  final bool scanlineComplete;
  final Color teal;
  final Color textSecondary;
  final TextScaler textScaler;

  @override
  void paint(Canvas canvas, Size size) {
    if (figures.isEmpty) return;

    final rows = figures.length;
    final cols = _kTopicOrder.length;
    final stepX = _kCellWidth + _kCellGap;

    // ── Pass 0: Background chrome ──
    _drawIntelDotGrid(canvas, size);
    _drawRowAlternateTint(canvas, size, rows);
    _drawHashmarkRuler(canvas, size, rows);

    // ── Pass 1: All cells ──
    for (int row = 0; row < rows; row++) {
      for (int col = 0; col < cols; col++) {
        final x = col * stepX;
        final y = row * _kRowStep;
        final rect = Rect.fromLTWH(x, y, _kCellWidth, _kCellHeight);
        final rrect = RRect.fromRectAndRadius(
          rect,
          const Radius.circular(_kCellRadius),
        );
        final topic = _kTopicOrder[col];
        final count = figures[row].countFor(topic);
        final colMax = col < columnMaxes.length ? columnMaxes[col] : 1;

        // Ignition per column (scanline reveal).
        final colFrac = col / cols;
        final ignition = scanlineT >= 1.0
            ? 1.0
            : ((scanlineT - colFrac * 0.7) / 0.3).clamp(0.0, 1.0);
        if (ignition <= 0) continue;

        // Heat computation.
        final norm = (colMax > 0 && count > 0)
            ? (count / colMax).clamp(0.0, 1.0)
            : 0.0;
        final baseOpacity = norm > 0
            ? _kCellOpacityMin +
                (norm * (_kCellOpacityMax - _kCellOpacityMin))
            : _kCellOpacityMin;

        // Peak breathing.
        final isPeak = colMax > 0 && count == colMax && count > 0;
        double breathMod = 0.0;
        if (isPeak && scanlineComplete) {
          final phase = (col * 0.25) % 1.0;
          breathMod = math.sin((breathingT + phase) * math.pi * 2) *
              _kBreathingAmplitude;
        }

        final opacity =
            ((baseOpacity + breathMod) * ignition).clamp(0.0, 1.0);

        // Cell fill.
        canvas.drawRRect(
          rrect,
          Paint()..color = teal.atOpacity(opacity),
        );

        // Radiance bloom (hot cells).
        if (norm > 0.15 && count > 0) {
          final radFrac = _kRadianceMinFrac +
              (norm * (_kRadianceMaxFrac - _kRadianceMinFrac));
          final gradient = RadialGradient(
            radius: radFrac,
            colors: [
              teal.atOpacity((opacity * 1.4).clamp(0.0, 1.0)),
              teal.atOpacity(0.0),
            ],
          );
          canvas.save();
          canvas.clipRRect(rrect);
          canvas.drawRect(
            rect,
            Paint()..shader = gradient.createShader(rect),
          );
          canvas.restore();
        }

        // Void cross-hatch (empty cells).
        if (count == 0 && ignition > 0.3) {
          final cx = rect.center.dx;
          final cy = rect.center.dy;
          final voidPaint = Paint()
            ..color = teal.atOpacity(
                (_kVoidOpacity * ignition).clamp(0.0, 1.0))
            ..strokeWidth = _kVoidStroke
            ..strokeCap = StrokeCap.round;
          canvas.drawLine(
            Offset(cx - _kVoidArmLength, cy - _kVoidArmLength),
            Offset(cx + _kVoidArmLength, cy + _kVoidArmLength),
            voidPaint,
          );
          canvas.drawLine(
            Offset(cx + _kVoidArmLength, cy - _kVoidArmLength),
            Offset(cx - _kVoidArmLength, cy + _kVoidArmLength),
            voidPaint,
          );
        }

        // Intel dot grid in empty cell centers.
        if (count == 0 && ignition > 0.5) {
          _drawCellIntelDots(canvas, rect, ignition);
        }

        // Column peak border.
        if (isPeak && ignition > 0.5) {
          canvas.drawRRect(
            rrect.deflate(0.5),
            Paint()
              ..color = teal.atOpacity(
                  (_kPeakBorderOpacity * ignition).clamp(0.0, 1.0))
              ..style = PaintingStyle.stroke
              ..strokeWidth = _kPeakBorderWidth,
          );
        }
      }
    }

    // ── Pass 2: Adjacency glow bleed (horizontal + vertical) ──
    _drawHorizontalBleed(canvas, rows, cols, stepX);
    _drawVerticalBleed(canvas, rows, cols, stepX);

    // ── Pass 3: Scanline beam + phosphor trail ──
    if (scanlineT > 0 && scanlineT < 1.0) {
      final beamX = scanlineT * size.width;

      // Phosphor trail (ghost afterglow behind the beam).
      final trailStart = (beamX - _kPhosphorTrailWidth).clamp(0.0, size.width);
      final trailRect = Rect.fromLTWH(
        trailStart,
        0,
        beamX - trailStart,
        size.height,
      );
      if (trailRect.width > 0) {
        canvas.drawRect(
          trailRect,
          Paint()
            ..shader = LinearGradient(
              colors: [
                teal.atOpacity(0.0),
                teal.atOpacity(_kPhosphorOpacity),
              ],
            ).createShader(trailRect),
        );
      }

      // Glow halo.
      final glowRect = Rect.fromLTWH(
        beamX - _kScanlineGlowHalf,
        0,
        _kScanlineGlowHalf * 2,
        size.height,
      );
      canvas.drawRect(
        glowRect,
        Paint()
          ..shader = LinearGradient(
            colors: [
              teal.atOpacity(0.0),
              teal.atOpacity(_kScanlineGlowOpacity),
              teal.atOpacity(0.0),
            ],
            stops: const [0.0, 0.5, 1.0],
          ).createShader(glowRect),
      );

      // Core line.
      canvas.drawLine(
        Offset(beamX, 0),
        Offset(beamX, size.height),
        Paint()
          ..color = teal.atOpacity(_kScanlineCoreOpacity)
          ..strokeWidth = _kScanlineCoreWidth,
      );
    }

    // ── Pass 4: Edge gradient bleeds ──
    _drawEdgeGradients(canvas, size);

    // ── Pass 5: Selected row highlight + crosshair + cell ring ──
    if (selectedCell != null) {
      final selRow = selectedCell!.$1;
      final selCol = selectedCell!.$2;
      if (selRow >= 0 && selRow < rows && selCol >= 0 && selCol < cols) {
        // Selected row full-width tint.
        final rowY = selRow * _kRowStep;
        canvas.drawRect(
          Rect.fromLTWH(0, rowY, size.width, _kRowStep),
          Paint()..color = teal.atOpacity(_kSelectedRowTint),
        );

        final cellCenterX = selCol * stepX + _kCellWidth / 2;
        final cellCenterY = selRow * _kRowStep + _kCellHeight / 2;
        final crossPaint = Paint()
          ..color = teal.atOpacity(_kCrosshairOpacity)
          ..strokeWidth = _kCrosshairStroke;

        // Full-span horizontal line.
        canvas.drawLine(
          Offset(0, cellCenterY),
          Offset(size.width, cellCenterY),
          crossPaint,
        );
        // Full-span vertical line.
        canvas.drawLine(
          Offset(cellCenterX, 0),
          Offset(cellCenterX, size.height),
          crossPaint,
        );

        // Selected cell ring.
        final selRect = Rect.fromLTWH(
          selCol * stepX,
          selRow * _kRowStep,
          _kCellWidth,
          _kCellHeight,
        );
        final selRRect = RRect.fromRectAndRadius(
          selRect,
          const Radius.circular(_kCellRadius),
        );
        canvas.drawRRect(
          selRRect.deflate(0.5),
          Paint()
            ..color = teal.atOpacity(_kSelectedRingOpacity)
            ..style = PaintingStyle.stroke
            ..strokeWidth = _kSelectedRingWidth,
        );

        // Compact count label (text-scaled for accessibility).
        final topic = _kTopicOrder[selCol];
        final count = figures[selRow].countFor(topic);
        if (count > 0) {
          final tp = TextPainter(
            text: TextSpan(
              text: _formatCount(count),
              style: TextStyle(
                fontFamily: BaselineTypography.monoFontFamily,
                fontSize: textScaler.scale(_kCountFontSize),
                color: teal,
                fontWeight: FontWeight.w600,
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          tp.paint(
            canvas,
            Offset(
              selRect.center.dx - tp.width / 2,
              selRect.center.dy - tp.height / 2,
            ),
          );
          tp.dispose();
        }
      }
    }
  }

  // ── Background chrome helpers ──

  /// Intel dot grid: faint dots at regular intervals across grid.
  void _drawIntelDotGrid(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = textSecondary.atOpacity(_kDotGridOpacity)
      ..style = PaintingStyle.fill;
    double y = _kDotGridSpacing;
    while (y < size.height) {
      double x = _kDotGridSpacing;
      while (x < size.width) {
        canvas.drawCircle(Offset(x, y), _kDotGridRadius, paint);
        x += _kDotGridSpacing;
      }
      y += _kDotGridSpacing;
    }
  }

  /// Alternating row tint for readability.
  void _drawRowAlternateTint(Canvas canvas, Size size, int rows) {
    final paint = Paint()
      ..color = teal.atOpacity(_kRowAltOpacity);
    for (int row = 0; row < rows; row += 2) {
      canvas.drawRect(
        Rect.fromLTWH(0, row * _kRowStep, size.width, _kRowStep),
        paint,
      );
    }
  }

  /// Hashmark measurement ruler along left edge.
  void _drawHashmarkRuler(Canvas canvas, Size size, int rows) {
    for (int row = 0; row < rows; row++) {
      final y = row * _kRowStep + _kCellHeight / 2;
      final isMajor = (row + 1) % _kRulerMajorEvery == 0;
      final w = isMajor ? _kRulerMajorWidth : _kRulerTickWidth;
      final stroke = isMajor ? _kRulerMajorStroke : _kRulerTickStroke;
      final opacity = isMajor ? _kRulerMajorOpacity : _kRulerTickOpacity;
      canvas.drawLine(
        Offset(0, y),
        Offset(w, y),
        Paint()
          ..color = textSecondary.atOpacity(opacity)
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.square,
      );
    }
  }

  /// Intel dots inside empty cells (subtle data-void texture).
  void _drawCellIntelDots(Canvas canvas, Rect rect, double ignition) {
    final paint = Paint()
      ..color = teal.atOpacity((_kDotGridOpacity * ignition).clamp(0.0, 1.0))
      ..style = PaintingStyle.fill;
    // 2x2 dot pattern centered in cell.
    final cx = rect.center.dx;
    final cy = rect.center.dy;
    const off = 4.0;
    canvas.drawCircle(Offset(cx - off, cy - off), 0.4, paint);
    canvas.drawCircle(Offset(cx + off, cy - off), 0.4, paint);
    canvas.drawCircle(Offset(cx - off, cy + off), 0.4, paint);
    canvas.drawCircle(Offset(cx + off, cy + off), 0.4, paint);
  }

  /// Horizontal adjacency bleed between hot neighbors.
  void _drawHorizontalBleed(
    Canvas canvas,
    int rows,
    int cols,
    double stepX,
  ) {
    for (int row = 0; row < rows; row++) {
      for (int col = 0; col < cols - 1; col++) {
        final topicA = _kTopicOrder[col];
        final topicB = _kTopicOrder[col + 1];
        final maxA = col < columnMaxes.length ? columnMaxes[col] : 1;
        final maxB =
            col + 1 < columnMaxes.length ? columnMaxes[col + 1] : 1;
        final normA = maxA > 0
            ? (figures[row].countFor(topicA) / maxA).clamp(0.0, 1.0)
            : 0.0;
        final normB = maxB > 0
            ? (figures[row].countFor(topicB) / maxB).clamp(0.0, 1.0)
            : 0.0;
        if (normA >= _kBleedThreshold && normB >= _kBleedThreshold) {
          final x = (col + 1) * stepX - _kCellGap;
          final y = row * _kRowStep;
          final bleedRect =
              Rect.fromLTWH(x, y + 2, _kCellGap, _kCellHeight - 4);
          final bleedOp = (math.min(normA, normB) * _kBleedOpacity)
              .clamp(0.0, 1.0);
          canvas.drawRect(
            bleedRect,
            Paint()..color = teal.atOpacity(bleedOp),
          );
        }
      }
    }
  }

  /// Vertical adjacency bleed between hot neighbors in same column.
  void _drawVerticalBleed(
    Canvas canvas,
    int rows,
    int cols,
    double stepX,
  ) {
    for (int col = 0; col < cols; col++) {
      final colMax = col < columnMaxes.length ? columnMaxes[col] : 1;
      if (colMax <= 0) continue;
      final topic = _kTopicOrder[col];
      for (int row = 0; row < rows - 1; row++) {
        final normA =
            (figures[row].countFor(topic) / colMax).clamp(0.0, 1.0);
        final normB =
            (figures[row + 1].countFor(topic) / colMax).clamp(0.0, 1.0);
        if (normA >= _kBleedThreshold && normB >= _kBleedThreshold) {
          final x = col * stepX;
          final y = (row + 1) * _kRowStep - (_kRowStep - _kCellHeight);
          final bleedRect =
              Rect.fromLTWH(x + 2, y, _kCellWidth - 4, _kRowStep - _kCellHeight);
          final bleedOp = (math.min(normA, normB) * _kBleedOpacity)
              .clamp(0.0, 1.0);
          canvas.drawRect(
            bleedRect,
            Paint()..color = teal.atOpacity(bleedOp),
          );
        }
      }
    }
  }

  /// Top and bottom edge gradient bleeds (fade to dark).
  void _drawEdgeGradients(Canvas canvas, Size size) {
    // Top edge.
    final topRect = Rect.fromLTWH(
      0, 0, size.width, _kEdgeGradientHeight,
    );
    canvas.drawRect(
      topRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            BaselineColors.black.atOpacity(_kEdgeGradientOpacity),
            BaselineColors.black.atOpacity(0.0),
          ],
        ).createShader(topRect),
    );
    // Bottom edge.
    final bottomRect = Rect.fromLTWH(
      0,
      size.height - _kEdgeGradientHeight,
      size.width,
      _kEdgeGradientHeight,
    );
    canvas.drawRect(
      bottomRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            BaselineColors.black.atOpacity(_kEdgeGradientOpacity),
            BaselineColors.black.atOpacity(0.0),
          ],
        ).createShader(bottomRect),
    );
  }

  @override
  bool shouldRepaint(_GridPainter old) {
    return old.scanlineT != scanlineT ||
        old.breathingT != breathingT ||
        old.selectedCell != selectedCell ||
        old.scanlineComplete != scanlineComplete ||
        old.textScaler != textScaler ||
        !identical(old.figures, figures) ||
        !identical(old.columnMaxes, columnMaxes);
  }
}

// ═══════════════════════════════════════════════════════════
// FRAME OVERLAY PAINTER
// ═══════════════════════════════════════════════════════════

class _FrameOverlayPainter extends CustomPainter {
  _FrameOverlayPainter({
    required this.teal,
    required this.borderColor,
  });

  final Color teal;
  final Color borderColor;

  @override
  void paint(Canvas canvas, Size size) {
    _drawReticleCorners(canvas, size);
    _drawPerforations(canvas, size);
    _drawRegistrationDots(canvas, size);
  }

  void _drawReticleCorners(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = teal.atOpacity(0.18)
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

  void _drawPerforations(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = borderColor.atOpacity(_kPerfDotOpacity)
      ..style = PaintingStyle.fill;
    final spacing = size.width / (_kPerfDotCount + 1);
    for (int i = 1; i <= _kPerfDotCount; i++) {
      final x = i * spacing;
      canvas.drawCircle(Offset(x, 2), _kPerfDotRadius, paint);
      canvas.drawCircle(
          Offset(x, size.height - 2), _kPerfDotRadius, paint);
    }
  }

  /// Registration dots at four inner corners of the grid area.
  void _drawRegistrationDots(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = teal.atOpacity(_kRegDotOpacity)
      ..style = PaintingStyle.fill;
    final d = _kRegDotInset;
    canvas.drawCircle(Offset(d, d), _kRegDotRadius, paint);
    canvas.drawCircle(Offset(size.width - d, d), _kRegDotRadius, paint);
    canvas.drawCircle(Offset(d, size.height - d), _kRegDotRadius, paint);
    canvas.drawCircle(
        Offset(size.width - d, size.height - d), _kRegDotRadius, paint);
  }

  @override
  bool shouldRepaint(_FrameOverlayPainter old) => false;
}
