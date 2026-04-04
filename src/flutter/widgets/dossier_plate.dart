/// FG-8a — Dossier Plate (LOCKED, 200%)
///
/// Declassified Dossier™ exhibit plate. Expandable classified
/// intelligence briefing for a single figure. Every measurement
/// signal consolidated into one cinematic expandable plate.
///
/// Consumes [DossierState] from FG-8b [dossierProvider]. Each
/// exhibit folder checks [sectionAvailability] for render decision.
///
/// AMBER DOCTRINE (DOSSIER EXCEPTION):
/// Up to 3 amber elements (standard screens: 2). Each from
/// a different exhibit, data-warranted, spaced. Sources:
/// 1. Exhibit F shift severity badge
/// 2. Exhibit B variance gauge ring (varianceRatio >= 0.30)
/// 3. Intelligence Brief shift/variance bullet icons
///
/// 90 visual treatments. Pro+ gated at caller.
///
/// Path: lib/widgets/dossier_plate.dart
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:baseline_app/config/theme.dart';
import 'package:baseline_app/config/routes.dart';
import 'package:baseline_app/controllers/dossier_mode_controller.dart';
import 'package:baseline_app/services/image_service.dart';
import 'package:baseline_app/utils/haptic_util.dart';
import 'package:baseline_app/widgets/framing_fingerprint.dart';
import 'package:baseline_app/widgets/disclaimer_footer.dart';
import 'package:baseline_app/models/shift_types.dart';

// ═══════════════════════════════════════════════════════════
// CONSTANTS
// ═══════════════════════════════════════════════════════════

/// Declassification sequence duration.
const Duration _kDeclassDuration = Duration(milliseconds: 1200);

/// Content reveal orchestration.
const Duration _kRevealDuration = Duration(milliseconds: 1400);

/// Per-section stagger.
const Duration _kSectionStagger = Duration(milliseconds: 50);

/// Scanline sweep.
const Duration _kScanlineDuration = Duration(milliseconds: 800);

/// Folder expand/collapse.
const Duration _kExpandDuration = Duration(milliseconds: 300);
const Duration _kCollapseDuration = Duration(milliseconds: 200);

/// Gauge needle.
const Duration _kGaugeDuration = Duration(milliseconds: 400);

/// Counter tick-up.
const Duration _kCounterDuration = Duration(milliseconds: 800);

/// Breathing ambient pulse on circuit trace junctions.
const Duration _kBreathDuration = Duration(milliseconds: 2400);

/// Number of revealable sections (brief + density + 8 exhibits).
const int _kSectionCount = 10;

/// Gauge cluster size.
const double _kGaugeSize = 72.0;

/// Fingerprint exhibit size.
const double _kFingerprintSize = 140.0;
const double _kFingerprintMini = 32.0;

/// Timeline dot size range.
const double _kDotMinR = 3.0;
const double _kDotMaxR = 6.0;

/// Reticle arms.
const double _kReticleArm = 16.0;
const double _kReticleInnerArm = 8.0;
const double _kReticleInnerOff = 4.0;
const double _kReticleDotR = 2.0;

/// Film perf dimensions.
const double _kPerfW = 6.0;
const double _kPerfH = 3.0;
const double _kPerfSpacing = 8.0;

/// Ruler tick sizes.
const double _kRulerMajor = 8.0;
const double _kRulerMinor = 4.0;

/// Max items.
const int _kMaxTimeline = 8;
const int _kMaxTopics = 10;

/// Sparkline height.
const double _kSparklineH = 64.0;
const double _kSparklineMiniH = 32.0;

/// Diamond size.
const double _kDiamondSize = 8.0;

/// Deep link chevron.
const String _kDeepLinkArrow = '\u2192';

/// Colors.
const Color _kTeal = BaselineColors.spectralTeal;
const Color _kAmber = BaselineColors.amberMuted;
const Color _kBg = BaselineColors.nearBlack;

/// Variance ratio threshold for amber flip.
const double _kVarianceAmberThreshold = 0.30;

/// Circuit trace bus width from left edge.
const double _kBusX = 8.0;
const double _kBusJunctionR = 3.0;

/// Registration dot size.
const double _kRegDotR = 2.0;

// ═══════════════════════════════════════════════════════════
// DOSSIER PLATE
// ═══════════════════════════════════════════════════════════

class DossierPlate extends ConsumerStatefulWidget {
  const DossierPlate({super.key, required this.figureId, this.baselineScore});
  final String figureId;
  final double? baselineScore;

  @override
  ConsumerState<DossierPlate> createState() => _DossierPlateState();
}

class _DossierPlateState extends ConsumerState<DossierPlate>
    with TickerProviderStateMixin {
  // ── Animation controllers ──────────────────────────────
  late final AnimationController _declassCtrl;
  late final AnimationController _revealCtrl;
  late final AnimationController _scanlineCtrl;
  late final AnimationController _gaugeCtrl;
  late final AnimationController _counterCtrl;
  late final AnimationController _breathCtrl;

  // ── Curved animations (dispose BEFORE parents) ─────────
  late final CurvedAnimation _blurAnim;
  late final CurvedAnimation _stampFade;
  late final List<CurvedAnimation> _sectionFades;

  // ── Cached merged listenables (avoid alloc in build) ───
  late final Listenable _declassBreathMerge;
  late final Listenable _scanRevealBreathMerge;

  /// Expand state per exhibit (A-H).
  final List<bool> _expanded = List.filled(8, false);

  /// Whether entrance has played.
  bool _hasAnimated = false;
  bool _reduceMotion = false;

  final ScrollController _scrollCtrl = ScrollController();

  /// Cancellable timers for entrance sequencing.
  final List<Timer> _pendingTimers = [];

  @override
  void initState() {
    super.initState();

    _declassCtrl = AnimationController(
      vsync: this,
      duration: _kDeclassDuration,
    );
    _revealCtrl = AnimationController(
      vsync: this,
      duration: _kRevealDuration,
    );
    _scanlineCtrl = AnimationController(
      vsync: this,
      duration: _kScanlineDuration,
    );
    _gaugeCtrl = AnimationController(
      vsync: this,
      duration: _kGaugeDuration,
    );
    _counterCtrl = AnimationController(
      vsync: this,
      duration: _kCounterDuration,
    );
    _breathCtrl = AnimationController(
      vsync: this,
      duration: _kBreathDuration,
    );

    // Blur dissolve: 12 -> 0 over first 60% of declass.
    _blurAnim = CurvedAnimation(
      parent: _declassCtrl,
      curve: const Interval(0, 0.6, curve: Curves.easeOut),
    );

    // Stamp reveal: fade in at 40%-70% of declass.
    _stampFade = CurvedAnimation(
      parent: _declassCtrl,
      curve: const Interval(0.4, 0.7, curve: Curves.easeIn),
    );

    // Stagger intervals for content sections.
    _sectionFades = List.generate(_kSectionCount, (i) {
      final start = (_kSectionStagger.inMilliseconds * i) /
          _kRevealDuration.inMilliseconds;
      final end = (start + 0.2).clamp(0.0, 1.0);
      return CurvedAnimation(
        parent: _revealCtrl,
        curve: Interval(start.clamp(0.0, 1.0), end, curve: Curves.easeOut),
      );
    });

    // Cached merged listenables (avoid per-build allocation).
    _declassBreathMerge = Listenable.merge([_declassCtrl, _breathCtrl]);
    _scanRevealBreathMerge = Listenable.merge([
      _scanlineCtrl,
      _revealCtrl,
      _breathCtrl,
    ]);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final wasReduced = _reduceMotion;
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    // Mid-flight snap (Rule 9).
    if (_reduceMotion && !wasReduced) {
      for (final t in _pendingTimers) {
        t.cancel();
      }
      _pendingTimers.clear();
      _declassCtrl.value = 1.0;
      _revealCtrl.value = 1.0;
      _scanlineCtrl.value = 1.0;
      _gaugeCtrl.value = 1.0;
      _counterCtrl.value = 1.0;
      _breathCtrl
        ..stop()
        ..value = 0.0;
    }
  }

  @override
  void dispose() {
    // 1. Cancel pending timers.
    for (final t in _pendingTimers) {
      t.cancel();
    }
    _pendingTimers.clear();

    // 2. CurvedAnimations first (reverse creation order).
    for (final f in _sectionFades) {
      f.dispose();
    }
    _stampFade.dispose();
    _blurAnim.dispose();

    // 3. Parent controllers.
    _breathCtrl.dispose();
    _counterCtrl.dispose();
    _gaugeCtrl.dispose();
    _scanlineCtrl.dispose();
    _revealCtrl.dispose();
    _declassCtrl.dispose();

    // 4. Scroll controller.
    _scrollCtrl.dispose();
    super.dispose();
  }

  /// Play the full entrance sequence.
  void _playEntrance() {
    if (_hasAnimated) return;
    _hasAnimated = true;

    if (_reduceMotion) {
      _declassCtrl.value = 1;
      _revealCtrl.value = 1;
      _scanlineCtrl.value = 1;
      _gaugeCtrl.value = 1;
      _counterCtrl.value = 1;
      return;
    }

    // Low-end device detection.
    final view = View.of(context);
    final isLowEnd = view.physicalSize.shortestSide < 720;
    final declassDelay = isLowEnd ? 400 : 600;
    final gaugeDelay = isLowEnd ? 600 : 900;
    final completeDelay = isLowEnd ? 1000 : 1600;

    // Phase 1: Declassification.
    _declassCtrl.forward();
    HapticUtil.light();

    // Phase 2: Scanline + content reveal.
    _pendingTimers.add(Timer(Duration(milliseconds: declassDelay), () {
      if (!mounted) return;
      _scanlineCtrl.forward();
      _revealCtrl.forward();
      HapticUtil.medium();
    }));

    // Phase 3: Gauges + counters.
    _pendingTimers.add(Timer(Duration(milliseconds: gaugeDelay), () {
      if (!mounted) return;
      _gaugeCtrl.forward();
      _counterCtrl.forward();
    }));

    // Phase 4: Completion haptic + start breathing.
    _pendingTimers.add(Timer(Duration(milliseconds: completeDelay), () {
      if (!mounted) return;
      HapticUtil.success();
      _breathCtrl.repeat(reverse: true, count: 8);
    }));
  }

  void _toggleExhibit(int index) {
    setState(() => _expanded[index] = !_expanded[index]);
    HapticUtil.light();
  }

  Future<void> _onRefresh() async {
    final notifier = ref.read(dossierProvider(widget.figureId).notifier);
    await notifier.refresh();
    HapticUtil.success();
  }

  void _navigate(BuildContext context, String route) {
    HapticUtil.medium();
    context.push(route);
  }

  /// Shift-specific deep link fires shiftDetected() haptic.
  void _navigateShift(BuildContext context, String route) {
    HapticUtil.shiftDetected();
    context.push(route);
  }

  // ── Route helpers ──────────────────────────────────────
  String _radarRoute() => AppRoutes.framingRadarPath(widget.figureId);
  String _trendsRoute() => AppRoutes.trendsPath(widget.figureId);
  String _votesRoute() => AppRoutes.voteRecordPath(widget.figureId);
  String _profileRoute() => AppRoutes.figureProfilePath(widget.figureId);

  String _statementRoute(String id) => AppRoutes.statementPath(id);

  String _searchTopicRoute(String topic) =>
      '${AppRoutes.explore}?topic=${Uri.encodeComponent(topic)}';

  /// SIG hash (deterministic from figureId).
  String get _sigHash {
    var hash = widget.figureId.hashCode.abs();
    const chars = '0123456789ABCDEF';
    final buf = StringBuffer('SIG-');
    for (int i = 0; i < 8; i++) {
      buf.write(chars[hash % 16]);
      hash = (hash >> 4) | (hash << 28);
    }
    return buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    final asyncState = ref.watch(dossierProvider(widget.figureId));

    return RepaintBoundary(
      child: asyncState.when(
        loading: () => const _DossierSkeleton(),
        error: (e, _) => _DossierError(
          onRetry: () => ref.invalidate(dossierProvider(widget.figureId)),
        ),
        data: (state) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _playEntrance();
          });

          return AnimatedBuilder(
            animation: _declassBreathMerge,
            builder: (_, _) {
              // Declassification: fixed-sigma blur overlay fades out
              // via opacity. GPU caches a single blur pass instead of
              // re-rasterising every frame at a new sigma.
              final blurOpacity = 1.0 - _blurAnim.value;
              final content = _buildContent(state);

              return Stack(
                children: [
                  content,

                  // ── Fixed-sigma blur overlay (fades out) ──
                  if (blurOpacity > 0.01)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: ExcludeSemantics(
                          child: Opacity(
                            opacity: blurOpacity,
                            child: ImageFiltered(
                              imageFilter: ui.ImageFilter.blur(
                                sigmaX: 12,
                                sigmaY: 12,
                              ),
                              child: ColoredBox(
                                color: BaselineColors.nearBlack,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                  // ── Plate frame overlay (decorative) ──
                  if (!_reduceMotion)
                    Positioned.fill(
                      child: ExcludeSemantics(
                        child: IgnorePointer(
                          child: AnimatedBuilder(
                            animation: _scanRevealBreathMerge,
                            builder: (_, _) => CustomPaint(
                              painter: _PlateFramePainter(
                                scanlineProgress: _scanlineCtrl.value,
                                circuitTraceProgress: _revealCtrl.value,
                                breathProgress: _breathCtrl.value,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                  // ── Classification stamps (decorative) ──
                  if (!_reduceMotion && _stampFade.value > 0.01)
                    Positioned.fill(
                      child: ExcludeSemantics(
                        child: IgnorePointer(
                          child: _ClassificationStamps(
                            opacity: _stampFade.value,
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildContent(DossierState state) {
    int sectionIndex = 0;
    // Compute brief once so amber flags flow to gauges.
    final brief = _computeBrief(state);

    Animation<double> nextFade() {
      final fade = sectionIndex < _sectionFades.length
          ? _sectionFades[sectionIndex]
          : _sectionFades.last;
      sectionIndex++;
      return fade;
    }

    return RefreshIndicator(
      onRefresh: _onRefresh,
      color: _kTeal,
      backgroundColor: BaselineColors.black,
      child: CustomScrollView(
        controller: _scrollCtrl,
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        slivers: [
          // ── Classification header ──
          SliverToBoxAdapter(
            child: _SlideReveal(
              fade: _reduceMotion ? null : nextFade(),
              child: const _ClassificationHeader(),
            ),
          ),

          // ── Subject header ──
          SliverToBoxAdapter(
            child: _SlideReveal(
              fade: _reduceMotion ? null : nextFade(),
              child: _SubjectHeader(
                state: state,
                counterAnimation: _reduceMotion ? null : _counterCtrl,
              ),
            ),
          ),

          // ── Intelligence Brief ──
          SliverToBoxAdapter(
            child: _SlideReveal(
              fade: _reduceMotion ? null : nextFade(),
              child: _IntelligenceBrief(
                brief: brief,
                onExpandAll: () {
                  setState(() {
                    for (int i = 0; i < _expanded.length; i++) {
                      _expanded[i] = true;
                    }
                  });
                  HapticUtil.medium();
                },
              ),
            ),
          ),

          // ── Signal Density Meter ──
          SliverToBoxAdapter(
            child: _SlideReveal(
              fade: _reduceMotion ? null : nextFade(),
              child: _SignalDensityMeter(state: state),
            ),
          ),

          // ── Exhibit A: Framing Profile ──
          if (state.sectionAvailability(DossierSection.framingRadar) !=
              SectionStatus.notApplicable)
            SliverToBoxAdapter(
              child: _SlideReveal(
                fade: _reduceMotion ? null : nextFade(),
                child: _ExhibitFolder(
                  index: 0,
                  designation: 'EXHIBIT A \u00B7 FRAMING PROFILE',
                  isExpanded: _expanded[0],
                  onToggle: () => _toggleExhibit(0),
                  status: state.sectionAvailability(
                      DossierSection.framingRadar),
                  collapsedChild: _FramingCollapsed(state: state),
                  expandedChild: _FramingExpanded(
                    state: state,
                    onViewRadar: () =>
                        _navigate(context, _radarRoute()),
                  ),
                ),
              ),
            ),

          // ── Exhibit B: Intelligence Gauges ──
          SliverToBoxAdapter(
            child: _SlideReveal(
              fade: _reduceMotion ? null : nextFade(),
              child: _ExhibitFolder(
                index: 1,
                designation: 'EXHIBIT B \u00B7 INTELLIGENCE GAUGES',
                isExpanded: _expanded[1],
                onToggle: () => _toggleExhibit(1),
                status: SectionStatus.available,
                collapsedChild: _GaugesCollapsed(state: state),
                expandedChild: _GaugesExpanded(
                  state: state,
                  gaugeAnimation: _reduceMotion ? null : _gaugeCtrl,
                  briefClaimedVarianceAmber: brief.briefClaimedVarianceAmber,
                  onViewStatements: () =>
                      _navigate(context, _profileRoute()),
                  onViewTrends: () =>
                      _navigate(context, _trendsRoute()),
                  onViewLensLab: () =>
                      _navigate(context, _profileRoute()),
                ),
              ),
            ),
          ),

          // ── Exhibit C: Statement Record ──
          if (state.sectionAvailability(DossierSection.statements) !=
              SectionStatus.notApplicable)
            SliverToBoxAdapter(
              child: _SlideReveal(
                fade: _reduceMotion ? null : nextFade(),
                child: _ExhibitFolder(
                  index: 2,
                  designation: 'EXHIBIT C \u00B7 STATEMENT RECORD',
                  isExpanded: _expanded[2],
                  onToggle: () => _toggleExhibit(2),
                  status: state.sectionAvailability(
                      DossierSection.statements),
                  collapsedChild: _StatementsCollapsed(state: state),
                  expandedChild: _StatementsExpanded(
                    state: state,
                    onViewStatement: (id) =>
                        _navigate(context, _statementRoute(id)),
                    onViewAll: () =>
                        _navigate(context, _profileRoute()),
                  ),
                ),
              ),
            ),

          // ── Exhibit D: Topic Intelligence ──
          SliverToBoxAdapter(
            child: _SlideReveal(
              fade: _reduceMotion ? null : nextFade(),
              child: _ExhibitFolder(
                index: 3,
                designation: 'EXHIBIT D \u00B7 TOPIC INTELLIGENCE',
                isExpanded: _expanded[3],
                onToggle: () => _toggleExhibit(3),
                status: SectionStatus.available,
                collapsedChild: _TopicsCollapsed(state: state),
                expandedChild: _TopicsExpanded(
                  state: state,
                  onSearchTopic: (topic) =>
                      _navigate(context, _searchTopicRoute(topic)),
                ),
              ),
            ),
          ),

          // ── Exhibit E: Metric Trend ──
          if (state.sectionAvailability(DossierSection.metricTrend) !=
              SectionStatus.notApplicable)
            SliverToBoxAdapter(
              child: _SlideReveal(
                fade: _reduceMotion ? null : nextFade(),
                child: _ExhibitFolder(
                  index: 4,
                  designation: 'EXHIBIT E \u00B7 METRIC TREND',
                  isExpanded: _expanded[4],
                  onToggle: () => _toggleExhibit(4),
                  status: state.sectionAvailability(
                      DossierSection.metricTrend),
                  collapsedChild: _TrendCollapsed(state: state),
                  expandedChild: _TrendExpanded(
                    state: state,
                    onViewTrends: () =>
                        _navigate(context, _trendsRoute()),
                  ),
                ),
              ),
            ),

          // ── Exhibit F: Shift Detection ──
          if (state.sectionAvailability(DossierSection.shiftDigest) !=
                  SectionStatus.notApplicable &&
              (state.shiftSeverity != null ||
                  state.sectionAvailability(DossierSection.shiftDigest) !=
                      SectionStatus.available))
            SliverToBoxAdapter(
              child: _SlideReveal(
                fade: _reduceMotion ? null : nextFade(),
                child: _ExhibitFolder(
                  index: 5,
                  designation: 'EXHIBIT F \u00B7 SHIFT DETECTION',
                  designationColor:
                      state.shiftSeverity != null ? _kAmber.atOpacity(0.4) : null,
                  isExpanded: _expanded[5],
                  onToggle: () => _toggleExhibit(5),
                  status: state.sectionAvailability(
                      DossierSection.shiftDigest),
                  collapsedChild: _ShiftCollapsed(state: state),
                  expandedChild: _ShiftExpanded(
                    state: state,
                    onViewStatement: (id) =>
                        _navigateShift(context, _statementRoute(id)),
                  ),
                ),
              ),
            ),

          // ── Exhibit G: Vote Record (congressional only) ──
          if (state.sectionAvailability(DossierSection.votes) !=
              SectionStatus.notApplicable)
            SliverToBoxAdapter(
              child: _SlideReveal(
                fade: _reduceMotion ? null : nextFade(),
                child: _ExhibitFolder(
                  index: 6,
                  designation: 'EXHIBIT G \u00B7 CONGRESSIONAL RECORD',
                  isExpanded: _expanded[6],
                  onToggle: () => _toggleExhibit(6),
                  status:
                      state.sectionAvailability(DossierSection.votes),
                  collapsedChild: _VotesCollapsed(state: state),
                  expandedChild: _VotesExpanded(
                    state: state,
                    onViewVotes: () =>
                        _navigate(context, _votesRoute()),
                  ),
                ),
              ),
            ),

          // ── Exhibit H: Measurement Attribution ──
          SliverToBoxAdapter(
            child: _SlideReveal(
              fade: _reduceMotion ? null : nextFade(),
              child: _ExhibitFolder(
                index: 7,
                designation: 'EXHIBIT H \u00B7 MEASUREMENT ATTRIBUTION',
                isExpanded: _expanded[7],
                onToggle: () => _toggleExhibit(7),
                status: SectionStatus.available,
                collapsedChild: const _AttributionCollapsed(),
                expandedChild: const _AttributionExpanded(),
              ),
            ),
          ),

          // ── Caveat footer ──
          SliverToBoxAdapter(
            child: _CaveatFooter(state: state, sigHash: _sigHash),
          ),

          // ── Disclaimer ──
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.only(top: 8, bottom: 32),
              child: DisclaimerFooter(),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 48)),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// INTELLIGENCE BRIEF (treatments 24-28)
// ═══════════════════════════════════════════════════════════

class _IntelligenceBrief extends StatelessWidget {
  const _IntelligenceBrief({required this.brief, required this.onExpandAll});
  final _BriefData brief;
  final VoidCallback onExpandAll;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Container(
        decoration: BoxDecoration(
          color: _kBg,
          border: Border(
            left: BorderSide(color: _kTeal.atOpacity(0.4), width: 3),
            top: BorderSide(color: _kTeal.atOpacity(0.06)),
            right: BorderSide(color: _kTeal.atOpacity(0.06)),
            bottom: BorderSide(color: _kTeal.atOpacity(0.06)),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Designation ──
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: _kTeal.atOpacity(0.06)),
                ),
              ),
              child: Text(
                'INTELLIGENCE BRIEF \u00B7 ${_formatMilitaryDTG(DateTime.now())}',
                style: const TextStyle(
                  fontFamily: BaselineTypography.monoFontFamily,
                  fontSize: 9,
                  color: Color(0x4DFFFFFF),
                  letterSpacing: 1.5,
                ),
              ),
            ),

            Padding(
              padding: BaselineInsets.allS,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Headline ──
                  Text(
                    brief.headline,
                    style: const TextStyle(
                      fontFamily: BaselineTypography.bodyFontFamily,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xE6FFFFFF),
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 8),

                  // ── Sub-points ──
                  ...brief.findings.map((f) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              f.icon,
                              style: TextStyle(
                                fontSize: 10,
                                color: f.isAmber
                                    ? _kAmber.atOpacity(0.7)
                                    : _kTeal.atOpacity(0.5),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                f.text,
                                style: const TextStyle(
                                  fontFamily: BaselineTypography.bodyFontFamily,
                                  fontSize: 12,
                                  color: Color(0x99FFFFFF),
                                  height: 1.3,
                                ),
                              ),
                            ),
                          ],
                        ),
                      )),

                  const SizedBox(height: 8),

                  // ── Expand all CTA ──
                  GestureDetector(
                    onTap: onExpandAll,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 44),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '$_kDeepLinkArrow EXPAND COMPLETE DOSSIER',
                          style: TextStyle(
                            fontFamily: BaselineTypography.monoFontFamily,
                            fontSize: 10,
                            color: _kTeal.atOpacity(0.6),
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                  ),

                  // ── Brief disclaimer ──
                  Text(
                    'Observational analysis only. Not a fact-check.',
                    style: TextStyle(
                      fontFamily: BaselineTypography.monoFontFamily,
                      fontSize: 8,
                      color: BaselineColors.white.atOpacity(0.15),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// BRIEF COMPUTATION
// ═══════════════════════════════════════════════════════════

_BriefData _computeBrief(DossierState s) {
  final findings = <_BriefFinding>[];
  String headline;
  bool briefClaimedVarianceAmber = false;

  final hasShifts = s.shiftSeverity != null;
  final trajLabel = s.agreementTrajectory.label;

  if (s.activityLevel == ActivityLevel.surging ||
      s.activityLevel == ActivityLevel.active) {
    if (s.agreementTrajectory == AgreementTrajectory.diverging) {
      headline = hasShifts
          ? 'Highly active figure showing divergent speech patterns '
              'with detected measurement shifts.'
          : 'Highly active figure showing divergent speech patterns.';
    } else if (s.agreementTrajectory == AgreementTrajectory.converging) {
      headline = 'Active figure with converging analysis patterns '
          'across measurement models.';
    } else {
      headline = hasShifts
          ? 'Active figure with stable patterns but detected '
              'measurement shifts.'
          : 'Active figure with consistent, stable measurement '
              'patterns across all models.';
    }
  } else {
    final trajDesc = s.agreementTrajectory == AgreementTrajectory.unknown
        ? 'insufficient'
        : trajLabel.toLowerCase();
    headline = 'Low-activity figure with $trajDesc '
        'measurement patterns.${hasShifts ? ' Shifts detected.' : ''}';
  }

  // Activity finding.
  findings.add(_BriefFinding(
    icon: '\u25C9',
    text: '${s.totalStatementCount} statements observed. '
        '${s.velocityLabel} recent pace.',
  ));

  // Framing finding.
  if (s.dominantFraming != null) {
    findings.add(_BriefFinding(
      icon: '\u25C8',
      text: 'Primary framing: ${s.dominantFraming!.toLowerCase()}. '
          '${s.varianceLabel} show model disagreement.',
    ));
  }

  // Shift finding (amber bullet).
  if (hasShifts) {
    findings.add(_BriefFinding(
      icon: '\u25B2',
      text: '${s.shiftSeverity!.name.toUpperCase()} shift detected. '
          'Tap Exhibit F to view the shifted statement.',
      isAmber: true,
    ));
  }

  // Variance finding (amber if above threshold).
  if (s.varianceRatio >= _kVarianceAmberThreshold) {
    briefClaimedVarianceAmber = true;
    findings.add(_BriefFinding(
      icon: '\u25C7',
      text: '${s.varianceLabel} show model disagreement: '
          'above normal variance threshold.',
      isAmber: true,
    ));
  }

  return _BriefData(
    headline: headline,
    findings: findings,
    briefClaimedVarianceAmber: briefClaimedVarianceAmber,
  );
}

class _BriefData {
  const _BriefData({
    required this.headline,
    required this.findings,
    this.briefClaimedVarianceAmber = false,
  });
  final String headline;
  final List<_BriefFinding> findings;
  final bool briefClaimedVarianceAmber;
}

class _BriefFinding {
  const _BriefFinding({
    required this.icon,
    required this.text,
    this.isAmber = false,
  });
  final String icon;
  final String text;
  final bool isAmber;
}

// ═══════════════════════════════════════════════════════════
// SIGNAL DENSITY METER (treatments 29-31)
// ═══════════════════════════════════════════════════════════

class _SignalDensityMeter extends StatelessWidget {
  const _SignalDensityMeter({required this.state});
  final DossierState state;

  @override
  Widget build(BuildContext context) {
    int availableCount = 0;
    int totalCount = 0;
    final sources = <String>[];
    for (final section in DossierSection.values) {
      final status = state.sectionAvailability(section);
      if (status != SectionStatus.notApplicable) {
        totalCount++;
        if (status == SectionStatus.available) {
          availableCount++;
          sources.add(section.name.toUpperCase());
        }
      }
    }
    final baseDensity = totalCount > 0 ? availableCount / totalCount : 0.0;
    final stmtFactor =
        (state.totalStatementCount / 50).clamp(0.0, 1.0);
    final density = ((baseDensity * 0.6) + (stmtFactor * 0.4)).clamp(0.0, 1.0);
    final pct = (density * 100).round();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'SIGNAL DENSITY: $pct%',
                style: const TextStyle(
                  fontFamily: BaselineTypography.monoFontFamily,
                  fontSize: 10,
                  color: Color(0x80FFFFFF),
                  letterSpacing: 1.0,
                ),
              ),
              const Spacer(),
              Flexible(
                child: Text(
                  sources.join(' \u00B7 '),
                  style: TextStyle(
                    fontFamily: BaselineTypography.monoFontFamily,
                    fontSize: 8,
                    color: _kTeal.atOpacity(0.3),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 6,
            child: CustomPaint(
              size: const Size(double.infinity, 6),
              painter: _DensityBarPainter(fill: density),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// EXPANDABLE EXHIBIT FOLDER (treatments 32-38)
// ═══════════════════════════════════════════════════════════

class _ExhibitFolder extends StatelessWidget {
  const _ExhibitFolder({
    required this.index,
    required this.designation,
    required this.isExpanded,
    required this.onToggle,
    required this.status,
    required this.collapsedChild,
    required this.expandedChild,
    this.designationColor,
  });
  final int index;
  final String designation;
  final bool isExpanded;
  final VoidCallback onToggle;
  final SectionStatus status;
  final Widget collapsedChild;
  final Widget expandedChild;
  final Color? designationColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              color: _kTeal.atOpacity(isExpanded ? 0.15 : 0.06),
              width: 2,
            ),
            top: BorderSide(color: _kTeal.atOpacity(0.06)),
            right: BorderSide(color: _kTeal.atOpacity(0.06)),
            bottom: BorderSide(color: _kTeal.atOpacity(0.06)),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Folder tab ──
            Semantics(
              button: status == SectionStatus.available,
              expanded: status == SectionStatus.available ? isExpanded : null,
              label: designation,
              onTapHint: status == SectionStatus.available
                  ? (isExpanded ? 'Collapse' : 'Expand')
                  : null,
              child: GestureDetector(
                onTap: status == SectionStatus.available ? onToggle : null,
                behavior: HitTestBehavior.opaque,
                child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: _kTeal.atOpacity(0.04)),
                    ),
                  ),
                  child: Row(
                    children: [
                      // Circuit trace junction dot.
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _kTeal.atOpacity(isExpanded ? 0.4 : 0.15),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          designation,
                          style: TextStyle(
                            fontFamily: BaselineTypography.monoFontFamily,
                            fontSize: 9,
                            color: designationColor ??
                                Color(isExpanded ? 0x80FFFFFF : 0x4DFFFFFF),
                            letterSpacing: 1.5,
                          ),
                        ),
                      ),
                      if (status == SectionStatus.available)
                        AnimatedRotation(
                          turns: isExpanded ? 0.25 : 0,
                          duration: const Duration(milliseconds: 200),
                          // Bespoke chevron (no stock icons).
                          child: CustomPaint(
                            size: const Size(16, 16),
                            painter: _ChevronPainter(
                              color: _kTeal.atOpacity(0.3),
                            ),
                          ),
                        ),
                      if (status == SectionStatus.gated)
                        CustomPaint(
                          size: const Size(14, 14),
                          painter: _LockPainter(
                            color: _kTeal.atOpacity(0.2),
                          ),
                        ),
                      if (status == SectionStatus.failed)
                        Text(
                          'SIGNAL LOST',
                          style: TextStyle(
                            fontFamily: BaselineTypography.monoFontFamily,
                            fontSize: 8,
                            color: BaselineColors.white.atOpacity(0.2),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              ),
            ),

            // ── Content ──
            if (status == SectionStatus.available) ...[
              if (!isExpanded) collapsedChild,
              AnimatedCrossFade(
                firstChild: const SizedBox(width: double.infinity, height: 0),
                secondChild: expandedChild,
                crossFadeState: isExpanded
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
                duration: _kExpandDuration,
                reverseDuration: _kCollapseDuration,
                sizeCurve: Curves.easeOutCubic,
              ),
            ] else if (status == SectionStatus.gated) ...[
              const _GatedPlaceholder(),
            ] else if (status == SectionStatus.failed) ...[
              const _FailedPlaceholder(),
            ],
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// COLLAPSED/EXPANDED CONTENT PAIRS
// ═══════════════════════════════════════════════════════════

// ── FRAMING (A) ──────────────────────────────────────────

class _FramingCollapsed extends StatelessWidget {
  const _FramingCollapsed({required this.state});
  final DossierState state;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: BaselineInsets.allS,
      child: Row(
        children: [
          if (state.framingRadar != null)
            SizedBox(
              width: _kFingerprintMini,
              height: _kFingerprintMini,
              child: FramingFingerprint.fromCategoryMap(
                data: state.framingRadar!.currentPeriod,
                size: _kFingerprintMini,
              ),
            ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              state.dominantFraming != null
                  ? 'Primary: ${state.dominantFraming}'
                  : 'Framing data available',
              style: const TextStyle(
                fontFamily: BaselineTypography.bodyFontFamily,
                fontSize: 12,
                color: Color(0x99FFFFFF),
              ),
            ),
          ),
          _DeepLinkLabel(text: 'EXPAND'),
        ],
      ),
    );
  }
}

class _FramingExpanded extends StatelessWidget {
  const _FramingExpanded({
    required this.state,
    required this.onViewRadar,
  });
  final DossierState state;
  final VoidCallback onViewRadar;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: BaselineInsets.allM,
      child: Column(
        children: [
          Center(
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: _kFingerprintSize + 40,
                  height: _kFingerprintSize + 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        _kTeal.atOpacity(0.04),
                        _kTeal.atOpacity(0),
                      ],
                    ),
                  ),
                ),
                if (state.framingRadar != null)
                  SizedBox(
                    width: _kFingerprintSize,
                    height: _kFingerprintSize,
                    child: FramingFingerprint.fromCategoryMap(
                      data: state.framingRadar!.currentPeriod,
                      size: _kFingerprintSize,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (state.dominantFraming != null)
            _PillBadge(
                text: 'PRIMARY: ${state.dominantFraming!.toUpperCase()}'),
          const SizedBox(height: 12),
          ...state.framingDistribution.entries.take(5).map((e) {
            final max = state.framingDistribution.values
                .fold<int>(0, (a, b) => a > b ? a : b);
            return _DistributionRow(
              label: e.key,
              ratio: max > 0 ? e.value / max : 0.0,
              count: e.value,
            );
          }),
          const SizedBox(height: 12),
          // Source indicator.
          Text(
            'MEASURED BY GP \u00B7 CL \u00B7 GR',
            style: TextStyle(
              fontFamily: BaselineTypography.monoFontFamily,
              fontSize: 8,
              color: _kTeal.atOpacity(0.3),
            ),
          ),
          const SizedBox(height: 8),
          _DeepLinkButton(
            text: '$_kDeepLinkArrow VIEW FRAMING RADAR\u2122',
            onTap: onViewRadar,
          ),
        ],
      ),
    );
  }
}

// ── GAUGES (B) ───────────────────────────────────────────

class _GaugesCollapsed extends StatelessWidget {
  const _GaugesCollapsed({required this.state});
  final DossierState state;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: BaselineInsets.allS,
      child: Row(
        children: [
          _MiniGaugePreview(label: state.activityLevel.name.toUpperCase()),
          const SizedBox(width: 8),
          _MiniGaugePreview(label: state.agreementTrajectory.label),
          const SizedBox(width: 8),
          _MiniGaugePreview(label: state.velocityLabel),
          const SizedBox(width: 8),
          _MiniGaugePreview(label: state.varianceLabel),
          const Spacer(),
          _DeepLinkLabel(text: 'EXPAND'),
        ],
      ),
    );
  }
}

class _GaugesExpanded extends StatelessWidget {
  const _GaugesExpanded({
    required this.state,
    this.gaugeAnimation,
    this.briefClaimedVarianceAmber = false,
    required this.onViewStatements,
    required this.onViewTrends,
    required this.onViewLensLab,
  });
  final DossierState state;
  final Animation<double>? gaugeAnimation;
  final bool briefClaimedVarianceAmber;
  final VoidCallback onViewStatements;
  final VoidCallback onViewTrends;
  final VoidCallback onViewLensLab;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: BaselineInsets.allS,
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _GaugeTile(
                  label: 'ACTIVITY',
                  value: state.activityLevel.name.toUpperCase(),
                  deepLink: '$_kDeepLinkArrow STATEMENTS',
                  onTapLink: onViewStatements,
                  child: _ArcGaugePaint(
                    fill: _activityFill(state.activityLevel),
                    animation: gaugeAnimation,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _GaugeTile(
                  label: 'TRAJECTORY',
                  value: state.agreementTrajectory.label,
                  child: _TrajectoryPaint(
                    trajectory: state.agreementTrajectory,
                    delta: state.agreementTrajectoryDelta,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _GaugeTile(
                  label: 'VELOCITY',
                  value: state.velocityLabel,
                  deepLink: '$_kDeepLinkArrow TRENDS',
                  onTapLink: onViewTrends,
                  child: _ArcGaugePaint(
                    fill: (state.statementVelocity / 5).clamp(0, 1),
                    animation: gaugeAnimation,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _GaugeTile(
                  label: 'VARIANCE',
                  value: state.varianceLabel,
                  deepLink: '$_kDeepLinkArrow LENS LAB\u2122',
                  onTapLink: onViewLensLab,
                  child: _RingGaugePaint(
                    fill: state.varianceRatio,
                    animation: gaugeAnimation,
                    color: state.varianceRatio >= _kVarianceAmberThreshold &&
                            !briefClaimedVarianceAmber
                        ? _kAmber
                        : _kTeal,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  double _activityFill(ActivityLevel l) => switch (l) {
        ActivityLevel.silent => 0.1,
        ActivityLevel.quiet => 0.35,
        ActivityLevel.active => 0.65,
        ActivityLevel.surging => 0.95,
      };
}

// ── STATEMENTS (C) ───────────────────────────────────────

class _StatementsCollapsed extends StatelessWidget {
  const _StatementsCollapsed({required this.state});
  final DossierState state;

  @override
  Widget build(BuildContext context) {
    final latest =
        state.recentStatements.isNotEmpty ? state.recentStatements.first : null;
    return Padding(
      padding: BaselineInsets.allS,
      child: Row(
        children: [
          Expanded(
            child: Text(
              latest?.headline ?? 'No statements on record',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: BaselineTypography.bodyFontFamily,
                fontSize: 12,
                color: Color(0x99FFFFFF),
              ),
            ),
          ),
          if (latest?.signalRank != null) ...[
            const SizedBox(width: 8),
            Text(
              'SIG ${latest!.signalRank}',
              style: TextStyle(
                fontFamily: BaselineTypography.monoFontFamily,
                fontSize: 9,
                color: _kTeal.atOpacity(0.5),
              ),
            ),
          ],
          const SizedBox(width: 8),
          _DeepLinkLabel(text: 'EXPAND'),
        ],
      ),
    );
  }
}

class _StatementsExpanded extends StatelessWidget {
  const _StatementsExpanded({
    required this.state,
    required this.onViewStatement,
    required this.onViewAll,
  });
  final DossierState state;
  final void Function(String id) onViewStatement;
  final VoidCallback onViewAll;

  @override
  Widget build(BuildContext context) {
    final highlights = <(String, StatementSummary)>[
      if (state.highestSignalRank != null)
        ('HIGHEST SIGNAL', state.highestSignalRank!),
      if (state.mostShiftedStatement != null)
        ('BIGGEST SHIFT', state.mostShiftedStatement!),
      if (state.mostNovelStatement != null)
        ('MOST NOVEL', state.mostNovelStatement!),
      if (state.lowestSignalRank != null)
        ('MOST ROUTINE', state.lowestSignalRank!),
    ];

    return Padding(
      padding: BaselineInsets.allM,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...highlights.map((h) => _HighlightCard(
                label: h.$1,
                statement: h.$2,
                onTap: () => onViewStatement(h.$2.statementId),
              )),
          if (highlights.isNotEmpty) const SizedBox(height: 12),
          ...state.recentStatements
              .take(_kMaxTimeline)
              .toList()
              .asMap()
              .entries
              .map((e) => _TimelineRow(
                    statement: e.value,
                    isLast: e.key ==
                        math.min(_kMaxTimeline,
                                state.recentStatements.length) -
                            1,
                    onTap: () => onViewStatement(e.value.statementId),
                  )),
          const SizedBox(height: 8),
          _DeepLinkButton(
            text:
                '$_kDeepLinkArrow VIEW ALL ${state.totalStatementCount} STATEMENTS',
            onTap: onViewAll,
          ),
        ],
      ),
    );
  }
}

// ── TOPICS (D) ───────────────────────────────────────────

class _TopicsCollapsed extends StatelessWidget {
  const _TopicsCollapsed({required this.state});
  final DossierState state;

  @override
  Widget build(BuildContext context) {
    final top3 = state.topTopics.take(3).map((t) => t.label).join(', ');
    return Padding(
      padding: BaselineInsets.allS,
      child: Row(
        children: [
          Expanded(
            child: Text(
              top3.isNotEmpty ? top3 : 'No topics detected',
              style: const TextStyle(
                fontFamily: BaselineTypography.monoFontFamily,
                fontSize: 11,
                color: Color(0x80FFFFFF),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          _DeepLinkLabel(text: 'EXPAND'),
        ],
      ),
    );
  }
}

class _TopicsExpanded extends StatelessWidget {
  const _TopicsExpanded({
    required this.state,
    required this.onSearchTopic,
  });
  final DossierState state;
  final void Function(String topic) onSearchTopic;

  @override
  Widget build(BuildContext context) {
    if (state.topTopics.isEmpty) {
      return const _EmptyCrossHatch(label: 'NO TOPIC SIGNALS DETECTED');
    }
    return Padding(
      padding: BaselineInsets.allM,
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: state.topTopics.take(_kMaxTopics).map((t) {
          return GestureDetector(
            onTap: () => onSearchTopic(t.label),
            child: _TopicPill(
              label: t.label,
              ratio: t.ratio,
              isNew: state.newTopics.contains(t.label),
              isRecurring: state.recurringTopics.contains(t.label),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ── TREND (E) ────────────────────────────────────────────

class _TrendCollapsed extends StatelessWidget {
  const _TrendCollapsed({required this.state});
  final DossierState state;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: BaselineInsets.allS,
      child: Row(
        children: [
          SizedBox(
            width: 80,
            height: _kSparklineMiniH,
            child: state.metricTimeline?.points.isNotEmpty == true
                ? CustomPaint(
                    painter: _MiniSparklinePainter(
                      points: state.metricTimeline!.points,
                    ),
                  )
                : const SizedBox(),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Baseline delta trend',
              style: TextStyle(
                fontFamily: BaselineTypography.bodyFontFamily,
                fontSize: 12,
                color: Color(0x80FFFFFF),
              ),
            ),
          ),
          _DeepLinkLabel(text: 'EXPAND'),
        ],
      ),
    );
  }
}

class _TrendExpanded extends StatelessWidget {
  const _TrendExpanded({
    required this.state,
    required this.onViewTrends,
  });
  final DossierState state;
  final VoidCallback onViewTrends;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: BaselineInsets.allM,
      child: Column(
        children: [
          SizedBox(
            height: _kSparklineH,
            child: CustomPaint(
              size: Size(double.infinity, _kSparklineH),
              painter: _SparklinePainter(
                points: state.metricTimeline?.points ?? [],
              ),
            ),
          ),
          const SizedBox(height: 12),
          _DeepLinkButton(
            text: '$_kDeepLinkArrow VIEW FULL TRENDS',
            onTap: onViewTrends,
          ),
        ],
      ),
    );
  }
}

// ── SHIFT (F) ────────────────────────────────────────────

class _ShiftCollapsed extends StatelessWidget {
  const _ShiftCollapsed({required this.state});
  final DossierState state;

  @override
  Widget build(BuildContext context) {
    final sev = state.shiftSeverity;
    return Padding(
      padding: BaselineInsets.allS,
      child: Row(
        children: [
          if (sev != null) ...[
            CustomPaint(
              size: const Size(16, 16),
              painter: _SeverityDotPainter(severity: sev),
            ),
            const SizedBox(width: 8),
            Text(
              '${sev.name.toUpperCase()} SHIFT DETECTED',
              style: TextStyle(
                fontFamily: BaselineTypography.monoFontFamily,
                fontSize: 11,
                color: _kAmber.atOpacity(0.7),
              ),
            ),
          ] else ...[
            const Text(
              'No shifts detected',
              style: TextStyle(
                fontFamily: BaselineTypography.monoFontFamily,
                fontSize: 11,
                color: Color(0x4DFFFFFF),
              ),
            ),
          ],
          const Spacer(),
          _DeepLinkLabel(text: 'EXPAND'),
        ],
      ),
    );
  }
}

class _ShiftExpanded extends StatelessWidget {
  const _ShiftExpanded({
    required this.state,
    required this.onViewStatement,
  });
  final DossierState state;
  final void Function(String id) onViewStatement;

  @override
  Widget build(BuildContext context) {
    final sev = state.shiftSeverity;
    if (sev == null) return const SizedBox.shrink();

    return Padding(
      padding: BaselineInsets.allM,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CustomPaint(
                size: const Size(32, 32),
                painter: _SeverityBadgePainter(severity: sev),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    sev.name.toUpperCase(),
                    style: TextStyle(
                      fontFamily: BaselineTypography.monoFontFamily,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _kAmber.atOpacity(0.8),
                      letterSpacing: 1.0,
                    ),
                  ),
                  Text(
                    'Shift detected in recent observations',
                    style: TextStyle(
                      fontFamily: BaselineTypography.monoFontFamily,
                      fontSize: 10,
                      color: BaselineColors.white.atOpacity(0.4),
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (state.mostShiftedStatement != null) ...[
            const SizedBox(height: 12),
            _DeepLinkButton(
              text: '$_kDeepLinkArrow VIEW SHIFTED STATEMENT',
              onTap: () =>
                  onViewStatement(state.mostShiftedStatement!.statementId),
            ),
          ],
        ],
      ),
    );
  }
}

// ── VOTES (G) ────────────────────────────────────────────

class _VotesCollapsed extends StatelessWidget {
  const _VotesCollapsed({required this.state});
  final DossierState state;

  @override
  Widget build(BuildContext context) {
    final recorded = state.votes.length;
    return Padding(
      padding: BaselineInsets.allS,
      child: Row(
        children: [
          Text(
            '$recorded OF ${state.totalVoteCount} RECORDED',
            style: const TextStyle(
              fontFamily: BaselineTypography.monoFontFamily,
              fontSize: 11,
              color: Color(0x80FFFFFF),
            ),
          ),
          const Spacer(),
          ...List.generate(
            math.min(8, state.votes.length),
            (i) => Padding(
              padding: const EdgeInsets.only(left: 2),
              child: CustomPaint(
                size: const Size(6, 6),
                painter: _DiamondPainter(
                  color: _kTeal.atOpacity(0.5),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _DeepLinkLabel(text: 'EXPAND'),
        ],
      ),
    );
  }
}

class _VotesExpanded extends StatelessWidget {
  const _VotesExpanded({
    required this.state,
    required this.onViewVotes,
  });
  final DossierState state;
  final VoidCallback onViewVotes;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: BaselineInsets.allM,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: state.votes
                .take(47)
                .map((v) => CustomPaint(
                      size: const Size(_kDiamondSize, _kDiamondSize),
                      painter: _DiamondPainter(
                        color: _kTeal.atOpacity(0.6),
                      ),
                    ))
                .toList(),
          ),
          const SizedBox(height: 12),
          _DeepLinkButton(
            text: '$_kDeepLinkArrow VIEW FULL VOTE RECORD',
            onTap: onViewVotes,
          ),
        ],
      ),
    );
  }
}

// ── ATTRIBUTION (H) ──────────────────────────────────────

class _AttributionCollapsed extends StatelessWidget {
  const _AttributionCollapsed();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: BaselineInsets.allS,
      child: Text(
        'MEASURED BY GP \u00B7 CL \u00B7 GR',
        style: TextStyle(
          fontFamily: BaselineTypography.monoFontFamily,
          fontSize: 10,
          color: _kTeal.atOpacity(0.4),
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _AttributionExpanded extends StatelessWidget {
  const _AttributionExpanded();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: BaselineInsets.allM,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Pipeline visualization.
          Row(
            children: [
              for (final (label, isLast) in [
                ('INGESTED', false),
                ('STRUCTURED', false),
                ('ANALYZED', false),
                ('MEASURED', true),
              ]) ...[
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: BaselineTypography.monoFontFamily,
                    fontSize: 8,
                    color: _kTeal.atOpacity(0.5),
                    letterSpacing: 0.5,
                  ),
                ),
                if (!isLast) ...[
                  const SizedBox(width: 4),
                  Container(
                    width: 16,
                    height: 1,
                    color: _kTeal.atOpacity(0.15),
                  ),
                  Text(
                    '\u2192',
                    style: TextStyle(
                      fontSize: 10,
                      color: _kTeal.atOpacity(0.3),
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
              ],
            ],
          ),
          const SizedBox(height: 12),
          // Model dots. Lens codes only per brand neutrality.
          Row(
            children: [
              for (final model in ['GP', 'CL', 'GR']) ...[
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _kTeal.atOpacity(0.5),
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  model,
                  style: TextStyle(
                    fontFamily: BaselineTypography.monoFontFamily,
                    fontSize: 10,
                    color: _kTeal.atOpacity(0.6),
                  ),
                ),
                const SizedBox(width: 12),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Independent multi-model analysis. No single model controls the output.',
            style: TextStyle(
              fontFamily: BaselineTypography.bodyFontFamily,
              fontSize: 11,
              color: BaselineColors.white.atOpacity(0.4),
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// STRUCTURAL WIDGETS
// ═══════════════════════════════════════════════════════════

/// Classification header (treatments 9-14).
class _ClassificationHeader extends StatelessWidget {
  const _ClassificationHeader();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(color: _kTeal.atOpacity(0.08)),
        ),
        child: Stack(
          children: [
            // Intel dot grid background (treatment 89).
            Positioned.fill(
              child: ExcludeSemantics(
                child: CustomPaint(
                  painter: _IntelDotGridPainter(),
                ),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'DECLASSIFIED DOSSIER\u2122 \u00B7 OBSERVATIONAL RECORD',
                  style: TextStyle(
                    fontFamily: BaselineTypography.monoFontFamily,
                    fontSize: 10,
                    color: _kTeal.atOpacity(0.5),
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'HANDLE VIA BASELINE CHANNELS ONLY',
                  style: TextStyle(
                    fontFamily: BaselineTypography.monoFontFamily,
                    fontSize: 7,
                    color: BaselineColors.white.atOpacity(0.12),
                    letterSpacing: 2.0,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Subject header (treatments 15-23).
class _SubjectHeader extends StatelessWidget {
  const _SubjectHeader({required this.state, this.counterAnimation});
  final DossierState state;
  final Animation<double>? counterAnimation;

  @override
  Widget build(BuildContext context) {
    final figure = state.figure;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
        padding: BaselineInsets.allM,
        decoration: BoxDecoration(
          border: Border.all(color: _kTeal.atOpacity(0.12), width: 2),
        ),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Avatar with teal ring.
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: _kTeal, width: 3),
                  ),
                  child: ClipOval(
                    child: figure.photoUrl != null
                        ? CachedNetworkImage(
                            imageUrl: ImageService.resolve(figure.photoUrl!) ?? '',
                            fit: BoxFit.cover,
                            placeholder: (_, _) => Container(
                              color: _kBg,
                            ),
                            errorWidget: (_, _, _) => Container(
                              color: _kBg,
                              child: Center(
                                child: Text(
                                  figure.name.isNotEmpty
                                      ? figure.name[0]
                                      : '?',
                                  style: TextStyle(
                                    fontFamily: BaselineTypography.bodyFontFamily,
                                    fontSize: 32,
                                    color: _kTeal.atOpacity(0.4),
                                  ),
                                ),
                              ),
                            ),
                          )
                        : Container(
                            color: _kBg,
                            child: Center(
                              child: Text(
                                figure.name.isNotEmpty ? figure.name[0] : '?',
                                style: TextStyle(
                                  fontFamily: BaselineTypography.bodyFontFamily,
                                  fontSize: 32,
                                  color: _kTeal.atOpacity(0.4),
                                ),
                              ),
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Name.
                      Text(
                        figure.name.toUpperCase(),
                        style: const TextStyle(
                          fontFamily: BaselineTypography.bodyFontFamily,
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: Color(0xE6FFFFFF),
                          letterSpacing: 1.0,
                        ),
                      ),
                      // Teal underline extending past text.
                      Container(
                        height: 2,
                        width: double.infinity,
                        margin: const EdgeInsets.only(top: 2, bottom: 6),
                        color: _kTeal.atOpacity(0.3),
                      ),
                      // Role + party (NEVER color-coded).
                      if (figure.role != null || figure.party != null)
                        Text(
                          [figure.role, figure.party]
                              .where((s) => s != null)
                              .join(' \u00B7 '),
                          style: TextStyle(
                            fontFamily: BaselineTypography.monoFontFamily,
                            fontSize: 12,
                            color: BaselineColors.white.atOpacity(0.6),
                          ),
                        ),
                      const SizedBox(height: 4),
                      // Activity badge.
                      Text(
                        state.activityBadgeText,
                        style: TextStyle(
                          fontFamily: BaselineTypography.monoFontFamily,
                          fontSize: 10,
                          color: state.activityLevel == ActivityLevel.surging
                              ? _kTeal.atOpacity(0.8)
                              : _kTeal.atOpacity(0.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Last seen DTG.
                Text(
                  _formatMilitaryDTG(state.lastSeenAt),
                  style: TextStyle(
                    fontFamily: BaselineTypography.monoFontFamily,
                    fontSize: 9,
                    color: BaselineColors.white.atOpacity(0.3),
                  ),
                ),
                // Statement count (animated).
                if (counterAnimation != null)
                  AnimatedBuilder(
                    animation: counterAnimation!,
                    builder: (_, _) {
                      final count = (state.totalStatementCount *
                              Curves.easeOutCubic
                                  .transform(counterAnimation!.value))
                          .round();
                      return Text(
                        '$count STATEMENTS OBSERVED',
                        style: TextStyle(
                          fontFamily: BaselineTypography.monoFontFamily,
                          fontSize: 9,
                          color: _kTeal.atOpacity(0.5),
                        ),
                      );
                    },
                  )
                else
                  Text(
                    '${state.totalStatementCount} STATEMENTS OBSERVED',
                    style: TextStyle(
                      fontFamily: BaselineTypography.monoFontFamily,
                      fontSize: 9,
                      color: _kTeal.atOpacity(0.5),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            // Subject ID.
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'SID-${state.figure.id.substring(0, math.min(8, state.figure.id.length))}',
                style: TextStyle(
                  fontFamily: BaselineTypography.monoFontFamily,
                  fontSize: 8,
                  color: BaselineColors.white.atOpacity(0.2),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Caveat footer with serial, SIG hash, and TM branding.
class _CaveatFooter extends StatelessWidget {
  const _CaveatFooter({required this.state, required this.sigHash});
  final DossierState state;
  final String sigHash;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now().toUtc();
    final serial = 'BL-${now.year}-'
        '${_pad2(now.month)}${_pad2(now.day)}-DOSS-001';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'OBSERVATIONAL ANALYSIS ONLY',
            style: TextStyle(
              fontFamily: BaselineTypography.monoFontFamily,
              fontSize: 8,
              color: BaselineColors.white.atOpacity(0.15),
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                serial,
                style: TextStyle(
                  fontFamily: BaselineTypography.monoFontFamily,
                  fontSize: 8,
                  color: BaselineColors.white.atOpacity(0.1),
                ),
              ),
              Text(
                sigHash,
                style: TextStyle(
                  fontFamily: BaselineTypography.monoFontFamily,
                  fontSize: 8,
                  color: _kTeal.atOpacity(0.15),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // TM branding (treatment 88).
          Center(
            child: Text(
              'DECLASSIFIED DOSSIER\u2122',
              style: TextStyle(
                fontFamily: BaselineTypography.monoFontFamily,
                fontSize: 8,
                color: _kTeal.atOpacity(0.1),
                letterSpacing: 3.0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Slide-in reveal wrapper for staggered entrance.
class _SlideReveal extends StatelessWidget {
  const _SlideReveal({this.fade, required this.child});
  final Animation<double>? fade;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (fade == null) return child;
    return AnimatedBuilder(
      animation: fade!,
      builder: (_, _) {
        return Opacity(
          opacity: fade!.value,
          child: Transform.translate(
            offset: Offset(0, 6 * (1 - fade!.value)),
            child: child,
          ),
        );
      },
    );
  }
}

/// Loading skeleton for dossier.
class _DossierSkeleton extends StatelessWidget {
  const _DossierSkeleton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: BaselineInsets.allM,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header skeleton.
          Container(
            height: 56,
            decoration: BoxDecoration(
              border: Border.all(color: _kTeal.atOpacity(0.06)),
            ),
          ),
          const SizedBox(height: 12),
          // Avatar + text skeleton.
          Row(
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: _kTeal.atOpacity(0.08)),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(height: 20, color: _kTeal.atOpacity(0.04)),
                    const SizedBox(height: 8),
                    Container(height: 12, color: _kTeal.atOpacity(0.02)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Folder skeletons.
          for (int i = 0; i < 4; i++) ...[
            Container(
              height: 48,
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                border: Border.all(color: _kTeal.atOpacity(0.04)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Error state.
class _DossierError extends StatelessWidget {
  const _DossierError({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CustomPaint(
              size: const Size(48, 48),
              painter: _StaticNoisePainter(),
            ),
            const SizedBox(height: 16),
            const Text(
              'Unable to compile dossier.\nCheck connection and try again.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: BaselineTypography.monoFontFamily,
                fontSize: 11,
                color: Color(0x66FFFFFF),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: onRetry,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  decoration: BoxDecoration(
                    border: Border.all(color: _kTeal.atOpacity(0.2)),
                  ),
                  child: Text(
                    'RETRY',
                    style: TextStyle(
                      fontFamily: BaselineTypography.monoFontFamily,
                      fontSize: 11,
                      color: _kTeal.atOpacity(0.6),
                      letterSpacing: 1.5,
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
}

/// Highlight card with mini-reticle corners.
class _HighlightCard extends StatelessWidget {
  const _HighlightCard({
    required this.label,
    required this.statement,
    required this.onTap,
  });
  final String label;
  final StatementSummary statement;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: CustomPaint(
          painter: _MiniReticlePainter(),
          child: Container(
            width: double.infinity,
            padding: BaselineInsets.allS,
            decoration: BoxDecoration(
              border: Border.all(color: _kTeal.atOpacity(0.08)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: BaselineTypography.monoFontFamily,
                    fontSize: 8,
                    color: _kTeal.atOpacity(0.5),
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  statement.headline,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: BaselineTypography.bodyFontFamily,
                    fontSize: 12,
                    color: Color(0xB3FFFFFF),
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$_kDeepLinkArrow VIEW STATEMENT',
                  style: TextStyle(
                    fontFamily: BaselineTypography.monoFontFamily,
                    fontSize: 8,
                    color: _kTeal.atOpacity(0.4),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Timeline row for statement record.
class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.statement,
    required this.isLast,
    required this.onTap,
  });
  final StatementSummary statement;
  final bool isLast;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dotR = statement.signalRank != null
        ? (_kDotMinR +
            (statement.signalRank! / 100) * (_kDotMaxR - _kDotMinR))
        : _kDotMinR;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Timeline spine.
            SizedBox(
              width: 16,
              child: Column(
                children: [
                  Container(
                    width: dotR * 2,
                    height: dotR * 2,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _kTeal.atOpacity(0.5),
                    ),
                  ),
                  if (!isLast)
                    Expanded(
                      child: Container(
                        width: 1,
                        color: _kTeal.atOpacity(0.15),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  statement.headline,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: BaselineTypography.bodyFontFamily,
                    fontSize: 11,
                    color: Color(0x99FFFFFF),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Topic pill with proportional width.
class _TopicPill extends StatelessWidget {
  const _TopicPill({
    required this.label,
    required this.ratio,
    this.isNew = false,
    this.isRecurring = false,
  });
  final String label;
  final double ratio;
  final bool isNew;
  final bool isRecurring;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(
          color: _kTeal.atOpacity(0.06 + ratio * 0.14),
        ),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isRecurring)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Text(
                '\u25CF\u25CF',
                style: TextStyle(
                  fontSize: 6,
                  color: _kTeal.atOpacity(0.3),
                ),
              ),
            ),
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontFamily: BaselineTypography.monoFontFamily,
              fontSize: 9,
              color: BaselineColors.white.atOpacity(0.4 + ratio * 0.3),
            ),
          ),
          if (isNew)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                decoration: BoxDecoration(
                  border: Border.all(color: _kTeal.atOpacity(0.3)),
                ),
                child: Text(
                  'NEW',
                  style: TextStyle(
                    fontFamily: BaselineTypography.monoFontFamily,
                    fontSize: 6,
                    color: _kTeal.atOpacity(0.6),
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
// SHARED UI COMPONENTS
// ═══════════════════════════════════════════════════════════

class _DeepLinkLabel extends StatelessWidget {
  const _DeepLinkLabel({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      '$_kDeepLinkArrow $text',
      style: TextStyle(
        fontFamily: BaselineTypography.monoFontFamily,
        fontSize: 9,
        color: _kTeal.atOpacity(0.4),
      ),
    );
  }
}

class _DeepLinkButton extends StatelessWidget {
  const _DeepLinkButton({required this.text, required this.onTap});
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              text,
              style: TextStyle(
                fontFamily: BaselineTypography.monoFontFamily,
                fontSize: 10,
                color: _kTeal.atOpacity(0.6),
                letterSpacing: 0.5,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PillBadge extends StatelessWidget {
  const _PillBadge({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(color: _kTeal.atOpacity(0.15)),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: BaselineTypography.monoFontFamily,
          fontSize: 10,
          color: _kTeal.atOpacity(0.7),
          letterSpacing: 1.0,
        ),
      ),
    );
  }
}

class _GatedPlaceholder extends StatelessWidget {
  const _GatedPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          CustomPaint(
            size: const Size(20, 20),
            painter: _LockPainter(color: _kTeal.atOpacity(0.2)),
          ),
          const SizedBox(height: 6),
          const Text(
            'CLASSIFIED \u00B7 UPGRADE TO DECLASSIFY',
            style: TextStyle(
              fontFamily: BaselineTypography.monoFontFamily,
              fontSize: 9,
              color: Color(0x4DFFFFFF),
              letterSpacing: 1.0,
            ),
          ),
        ],
      ),
    );
  }
}

class _FailedPlaceholder extends StatelessWidget {
  const _FailedPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          CustomPaint(
            size: const Size(double.infinity, 24),
            painter: _StaticNoisePainter(),
          ),
          const SizedBox(height: 6),
          const Text(
            'SIGNAL LOST',
            style: TextStyle(
              fontFamily: BaselineTypography.monoFontFamily,
              fontSize: 9,
              color: Color(0x4DFFFFFF),
              letterSpacing: 1.0,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyCrossHatch extends StatelessWidget {
  const _EmptyCrossHatch({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: BaselineInsets.allM,
      child: SizedBox(
        height: 48,
        child: CustomPaint(
          painter: _CrossHatchPainter(),
          child: Center(
            child: Text(
              label,
              style: const TextStyle(
                fontFamily: BaselineTypography.monoFontFamily,
                fontSize: 10,
                color: Color(0x4DFFFFFF),
                letterSpacing: 1.0,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DistributionRow extends StatelessWidget {
  const _DistributionRow({
    required this.label,
    required this.ratio,
    required this.count,
  });
  final String label;
  final double ratio;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label.toUpperCase(),
              style: const TextStyle(
                fontFamily: BaselineTypography.monoFontFamily,
                fontSize: 9,
                color: Color(0x66FFFFFF),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: CustomPaint(
              size: const Size(double.infinity, 8),
              painter: _DistributionBarPainter(fill: ratio),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 20,
            child: Text(
              '$count',
              style: TextStyle(
                fontFamily: BaselineTypography.monoFontFamily,
                fontSize: 9,
                color: _kTeal.atOpacity(0.5),
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniGaugePreview extends StatelessWidget {
  const _MiniGaugePreview({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: _kTeal.atOpacity(0.08)),
        borderRadius: BorderRadius.circular(1),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontFamily: BaselineTypography.monoFontFamily,
          fontSize: 8,
          color: Color(0x66FFFFFF),
        ),
      ),
    );
  }
}

class _GaugeTile extends StatelessWidget {
  const _GaugeTile({
    required this.label,
    required this.value,
    required this.child,
    this.deepLink,
    this.onTapLink,
  });
  final String label;
  final String value;
  final Widget child;
  final String? deepLink;
  final VoidCallback? onTapLink;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$label: $value',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          border: Border.all(color: _kTeal.atOpacity(0.04)),
        ),
        child: Column(
          children: [
            SizedBox(width: _kGaugeSize, height: _kGaugeSize, child: child),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontFamily: BaselineTypography.monoFontFamily,
                fontSize: 8,
                color: BaselineColors.white.atOpacity(0.4),
                letterSpacing: 0.5,
              ),
            ),
            if (deepLink != null && onTapLink != null) ...[
              const SizedBox(height: 4),
              GestureDetector(
                onTap: onTapLink,
                behavior: HitTestBehavior.opaque,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 44),
                  child: Center(
                    child: Text(
                      deepLink!,
                      style: TextStyle(
                        fontFamily: BaselineTypography.monoFontFamily,
                        fontSize: 8,
                        color: _kTeal.atOpacity(0.4),
                      ),
                    ),
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

// ═══════════════════════════════════════════════════════════
// GAUGE PAINT WRAPPERS
// ═══════════════════════════════════════════════════════════

class _ArcGaugePaint extends StatelessWidget {
  const _ArcGaugePaint({required this.fill, this.animation});
  final double fill;
  final Animation<double>? animation;

  @override
  Widget build(BuildContext context) {
    if (animation == null) {
      return CustomPaint(painter: _ArcGaugePainter(fill: fill, color: _kTeal));
    }
    return AnimatedBuilder(
      animation: animation!,
      builder: (_, _) => CustomPaint(
        painter: _ArcGaugePainter(
          fill: fill * Curves.easeOutCubic.transform(animation!.value),
          color: _kTeal,
        ),
      ),
    );
  }
}

class _TrajectoryPaint extends StatelessWidget {
  const _TrajectoryPaint({required this.trajectory, required this.delta});
  final AgreementTrajectory trajectory;
  final double delta;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _TrajectoryPainter(
        trajectory: trajectory,
        delta: delta,
        progress: 1.0,
      ),
    );
  }
}

class _RingGaugePaint extends StatelessWidget {
  const _RingGaugePaint({
    required this.fill,
    this.animation,
    this.color = _kTeal,
  });
  final double fill;
  final Animation<double>? animation;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (animation == null) {
      return CustomPaint(
        painter: _RingGaugePainter(fill: fill, label: '', color: color),
      );
    }
    return AnimatedBuilder(
      animation: animation!,
      builder: (_, _) => CustomPaint(
        painter: _RingGaugePainter(
          fill: fill * Curves.easeOutCubic.transform(animation!.value),
          label: '',
          color: color,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// PAINTERS
// ═══════════════════════════════════════════════════════════

/// Plate frame: reticles, perfs, rulers, scanline, circuit trace,
/// registration dots, DTG watermark, hashmark ticks.
class _PlateFramePainter extends CustomPainter {
  _PlateFramePainter({
    required this.scanlineProgress,
    required this.circuitTraceProgress,
    required this.breathProgress,
  });
  final double scanlineProgress;
  final double circuitTraceProgress;
  final double breathProgress;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // ── Parallax depth borders (treatment 12) ──
    for (final (inset, op) in [(4.0, 0.12), (8.0, 0.08), (12.0, 0.04)]) {
      canvas.drawRect(
        Rect.fromLTRB(inset, inset, w - inset, h - inset),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.5
          ..color = _kTeal.atOpacity(op),
      );
    }

    // ── Compound reticle corners (treatment 13) ──
    _drawReticles(canvas, size);

    // ── Film perforations (treatment 14) ──
    _drawPerforations(canvas, size);

    // ── Hashmark rulers (treatment 90) ──
    _drawRulers(canvas, size);

    // ── Registration dots (treatment 85) ──
    final regPaint = Paint()..color = _kTeal.atOpacity(0.08);
    for (final offset in [
      Offset(_kRegDotR + 2, _kRegDotR + 2),
      Offset(w - _kRegDotR - 2, _kRegDotR + 2),
      Offset(_kRegDotR + 2, h - _kRegDotR - 2),
      Offset(w - _kRegDotR - 2, h - _kRegDotR - 2),
    ]) {
      canvas.drawCircle(offset, _kRegDotR, regPaint);
    }

    // ── Scanline sweep + phosphor trail (treatments 3, 84) ──
    if (scanlineProgress > 0 && scanlineProgress < 1) {
      final y = h * scanlineProgress;
      // Phosphor trail.
      final trailRect = Rect.fromLTRB(0, math.max(0, y - 40), w, y);
      canvas.drawRect(
        trailRect,
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(0, trailRect.top),
            Offset(0, trailRect.bottom),
            [Colors.transparent, _kTeal.atOpacity(0.05)],
          ),
      );
      // Scanline.
      canvas.drawLine(
        Offset(0, y),
        Offset(w, y),
        Paint()
          ..color = _kTeal.atOpacity(0.6)
          ..strokeWidth = 1.5,
      );
      // Glow.
      canvas.drawRect(
        Rect.fromLTRB(0, y - 8, w, y + 8),
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(0, y - 8),
            Offset(0, y + 8),
            [Colors.transparent, _kTeal.atOpacity(0.08), Colors.transparent],
            [0, 0.5, 1],
          ),
      );
    }

    // ── Circuit trace bus (treatment 5) ──
    if (circuitTraceProgress > 0) {
      final busP = Paint()
        ..color = _kTeal.atOpacity(0.10 * circuitTraceProgress)
        ..strokeWidth = 1;
      final busH = h * circuitTraceProgress;
      canvas.drawLine(
        Offset(_kBusX, 80),
        Offset(_kBusX, math.min(busH, h - 80)),
        busP,
      );

      // Junction dots with breathing pulse (treatment 83).
      final junctionP = Paint()
        ..color = _kTeal.atOpacity(
            (0.15 + breathProgress * 0.15) * circuitTraceProgress);
      final spacing = (h - 160) / 8;
      for (int i = 0; i < 8; i++) {
        final jy = 80 + spacing * (i + 0.5);
        if (jy < busH) {
          canvas.drawCircle(
            Offset(_kBusX, jy),
            _kBusJunctionR,
            junctionP,
          );
        }
      }
    }

    // ── DTG watermark (treatment 86) ──
    final dtgPainter = TextPainter(
      text: TextSpan(
        text: _formatMilitaryDTG(DateTime.now()),
        style: TextStyle(
          fontFamily: BaselineTypography.monoFontFamily,
          fontSize: 8,
          color: _kTeal.atOpacity(0.03),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    canvas.save();
    canvas.translate(w - 12, h * 0.4);
    canvas.rotate(-math.pi / 2);
    dtgPainter.paint(canvas, Offset.zero);
    canvas.restore();
    dtgPainter.dispose();
  }

  void _drawReticles(Canvas canvas, Size size) {
    final p = Paint()
      ..color = _kTeal.atOpacity(0.12)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    final dp = Paint()..color = _kTeal.atOpacity(0.15);
    final ip = Paint()
      ..color = _kTeal.atOpacity(0.08)
      ..strokeWidth = 0.5
      ..style = PaintingStyle.stroke;

    for (final (cx, cy, sx, sy) in [
      (0.0, 0.0, 1.0, 1.0),
      (size.width, 0.0, -1.0, 1.0),
      (0.0, size.height, 1.0, -1.0),
      (size.width, size.height, -1.0, -1.0),
    ]) {
      // Outer L.
      canvas.drawLine(
          Offset(cx, cy), Offset(cx + _kReticleArm * sx, cy), p);
      canvas.drawLine(
          Offset(cx, cy), Offset(cx, cy + _kReticleArm * sy), p);
      // Inner tick.
      canvas.drawLine(
        Offset(cx + _kReticleInnerOff * sx, cy + _kReticleInnerOff * sy),
        Offset(cx + (_kReticleInnerOff + _kReticleInnerArm) * sx,
            cy + _kReticleInnerOff * sy),
        ip,
      );
      // Corner dot.
      canvas.drawCircle(
        Offset(cx + _kReticleDotR * 2 * sx, cy + _kReticleDotR * 2 * sy),
        _kReticleDotR,
        dp,
      );
    }
  }

  void _drawPerforations(Canvas canvas, Size size) {
    final perfP = Paint()..color = _kTeal.atOpacity(0.06);
    // Top edge.
    double x = 20;
    while (x + _kPerfW < size.width - 20) {
      canvas.drawRect(Rect.fromLTWH(x, 1, _kPerfW, _kPerfH), perfP);
      x += _kPerfW + _kPerfSpacing;
    }
    // Bottom edge.
    x = 20;
    while (x + _kPerfW < size.width - 20) {
      canvas.drawRect(
        Rect.fromLTWH(x, size.height - _kPerfH - 1, _kPerfW, _kPerfH),
        perfP,
      );
      x += _kPerfW + _kPerfSpacing;
    }
  }

  void _drawRulers(Canvas canvas, Size size) {
    final rp = Paint()
      ..color = _kTeal.atOpacity(0.06)
      ..strokeWidth = 0.5;
    final majorInterval = size.height / 10;
    for (int i = 1; i < 10; i++) {
      final y = majorInterval * i;
      final isMajor = i % 2 == 0;
      canvas.drawLine(
        Offset(0, y),
        Offset(isMajor ? _kRulerMajor : _kRulerMinor, y),
        rp,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PlateFramePainter old) =>
      old.scanlineProgress != scanlineProgress ||
      old.circuitTraceProgress != circuitTraceProgress ||
      old.breathProgress != breathProgress;
}

/// Arc gauge (activity, velocity).
class _ArcGaugePainter extends CustomPainter {
  _ArcGaugePainter({required this.fill, required this.color});
  final double fill;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final r = math.min(size.width, size.height) / 2 - 4;
    // Track.
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: r),
      math.pi * 0.75,
      math.pi * 1.5,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..color = color.atOpacity(0.08),
    );
    // Fill.
    if (fill > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: r),
        math.pi * 0.75,
        math.pi * 1.5 * fill,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round
          ..color = color.atOpacity(0.5),
      );
    }
    // Center dot.
    canvas.drawCircle(center, 2, Paint()..color = color.atOpacity(0.3));
  }

  @override
  bool shouldRepaint(covariant _ArcGaugePainter old) =>
      old.fill != fill || old.color != color;
}

/// Trajectory arrows painter.
class _TrajectoryPainter extends CustomPainter {
  _TrajectoryPainter({
    required this.trajectory,
    required this.delta,
    required this.progress,
  });
  final AgreementTrajectory trajectory;
  final double delta;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final color = _kTeal.atOpacity(0.5);
    final p = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    if (trajectory == AgreementTrajectory.converging) {
      // Arrows pointing inward.
      canvas.drawLine(Offset(center.dx - 16, center.dy - 8),
          Offset(center.dx - 4, center.dy), p);
      canvas.drawLine(Offset(center.dx + 16, center.dy - 8),
          Offset(center.dx + 4, center.dy), p);
    } else if (trajectory == AgreementTrajectory.diverging) {
      // Arrows pointing outward.
      canvas.drawLine(Offset(center.dx - 4, center.dy),
          Offset(center.dx - 16, center.dy - 8), p);
      canvas.drawLine(Offset(center.dx + 4, center.dy),
          Offset(center.dx + 16, center.dy - 8), p);
    } else {
      // Stable: horizontal line.
      canvas.drawLine(Offset(center.dx - 12, center.dy),
          Offset(center.dx + 12, center.dy), p);
    }
  }

  @override
  bool shouldRepaint(covariant _TrajectoryPainter old) =>
      old.trajectory != trajectory || old.delta != delta;
}

/// Ring gauge (variance).
class _RingGaugePainter extends CustomPainter {
  _RingGaugePainter({
    required this.fill,
    required this.label,
    required this.color,
  });
  final double fill;
  final String label;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final r = math.min(size.width, size.height) / 2 - 4;
    // Track.
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = color.atOpacity(0.08),
    );
    // Fill arc.
    if (fill > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: r),
        -math.pi / 2,
        math.pi * 2 * fill,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round
          ..color = color.atOpacity(0.5),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RingGaugePainter old) =>
      old.fill != fill || old.color != color;
}

/// Full sparkline.
class _SparklinePainter extends CustomPainter {
  _SparklinePainter({required this.points});
  final List<dynamic> points;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    final values = points.map((p) {
      if (p is num) return p.toDouble();
      return 0.0;
    }).toList();
    final minV = values.reduce(math.min);
    final maxV = values.reduce(math.max);
    final range = maxV - minV == 0 ? 1.0 : maxV - minV;

    // Zero line (treatment 71).
    if (minV < 0 && maxV > 0) {
      final zeroY = size.height * (1 - (0 - minV) / range);
      final dp = Paint()
        ..color = BaselineColors.white.atOpacity(0.08)
        ..strokeWidth = 0.5;
      double x = 0;
      while (x < size.width) {
        canvas.drawLine(Offset(x, zeroY), Offset(x + 4, zeroY), dp);
        x += 8;
      }
    }

    final path = Path();
    for (int i = 0; i < values.length; i++) {
      final x = size.width * i / (values.length - 1);
      final y = size.height * (1 - (values[i] - minV) / range);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = _kTeal.atOpacity(0.6)
        ..strokeCap = StrokeCap.round,
    );

    // Latest point callout (treatment 72).
    if (values.isNotEmpty) {
      final lastX = size.width;
      final lastY =
          size.height * (1 - (values.last - minV) / range);
      canvas.drawCircle(
        Offset(lastX, lastY),
        6,
        Paint()..color = _kTeal.atOpacity(0.08),
      );
      canvas.drawCircle(
        Offset(lastX, lastY),
        3,
        Paint()..color = _kTeal.atOpacity(0.5),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter old) => old.points != points;
}

/// Mini sparkline for collapsed trend preview.
class _MiniSparklinePainter extends CustomPainter {
  _MiniSparklinePainter({required this.points});
  final List<dynamic> points;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    final values =
        points.map((p) => p is num ? p.toDouble() : 0.0).toList();
    final minV = values.reduce(math.min);
    final maxV = values.reduce(math.max);
    final range = maxV - minV == 0 ? 1.0 : maxV - minV;

    final path = Path();
    for (int i = 0; i < values.length; i++) {
      final x = size.width * i / (values.length - 1);
      final y = size.height * (1 - (values[i] - minV) / range);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = _kTeal.atOpacity(0.3),
    );
  }

  @override
  bool shouldRepaint(covariant _MiniSparklinePainter old) =>
      old.points != points;
}

/// Severity badge (Exhibit F expanded).
class _SeverityBadgePainter extends CustomPainter {
  _SeverityBadgePainter({required this.severity});
  final ShiftSeverity severity;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2;
    // Outer ring.
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = _kAmber.atOpacity(0.3),
    );
    // Inner fill proportional to severity.
    final sevFill = switch (severity) {
      ShiftSeverity.notice => 0.25,
      ShiftSeverity.elevated => 0.50,
      ShiftSeverity.high => 0.75,
      ShiftSeverity.critical => 0.95,
      _ => 0.1,
    };
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: r - 3),
      -math.pi / 2,
      math.pi * 2 * sevFill,
      true,
      Paint()..color = _kAmber.atOpacity(0.25),
    );
  }

  @override
  bool shouldRepaint(covariant _SeverityBadgePainter old) =>
      old.severity != severity;
}

/// Severity dot (Exhibit F collapsed).
class _SeverityDotPainter extends CustomPainter {
  _SeverityDotPainter({required this.severity});
  final ShiftSeverity severity;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    canvas.drawCircle(
        center, size.width / 3, Paint()..color = _kAmber.atOpacity(0.6));
    canvas.drawCircle(
      center,
      size.width / 2,
      Paint()
        ..color = _kAmber.atOpacity(0.15)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _SeverityDotPainter old) =>
      old.severity != severity;
}

/// Diamond (vote grid).
class _DiamondPainter extends CustomPainter {
  _DiamondPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width / 2, 0)
      ..lineTo(size.width, size.height / 2)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(0, size.height / 2)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _DiamondPainter old) => old.color != color;
}

/// Static noise (failed state).
class _StaticNoisePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rng = math.Random(42);
    final p = Paint();
    for (double x = 0; x < size.width; x += 3) {
      for (double y = 0; y < size.height; y += 3) {
        p.color = BaselineColors.white.atOpacity(rng.nextDouble() * 0.06);
        canvas.drawRect(Rect.fromLTWH(x, y, 2, 2), p);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _StaticNoisePainter old) => false;
}

/// Cross-hatch (empty state).
class _CrossHatchPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = _kTeal.atOpacity(0.04)
      ..strokeWidth = 0.5;
    for (double x = 0; x < size.width + size.height; x += 12) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x - size.height, size.height),
        p,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CrossHatchPainter old) => false;
}

/// Density thermometer bar.
class _DensityBarPainter extends CustomPainter {
  _DensityBarPainter({required this.fill});
  final double fill;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, size.width, size.height),
        const Radius.circular(1),
      ),
      Paint()..color = _kTeal.atOpacity(0.06),
    );
    if (fill > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, 0, size.width * fill, size.height),
          const Radius.circular(1),
        ),
        Paint()..color = _kTeal.atOpacity(0.20),
      );
    }
    final hp = Paint()
      ..color = BaselineColors.white.atOpacity(0.08)
      ..strokeWidth = 0.5;
    for (final pct in [0.25, 0.5, 0.75]) {
      canvas.drawLine(
        Offset(size.width * pct, 0),
        Offset(size.width * pct, size.height),
        hp,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DensityBarPainter old) => old.fill != fill;
}

/// Distribution bar (framing ratios).
class _DistributionBarPainter extends CustomPainter {
  _DistributionBarPainter({required this.fill});
  final double fill;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = _kTeal.atOpacity(0.04),
    );
    if (fill > 0) {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width * fill, size.height),
        Paint()..color = _kTeal.atOpacity(0.20),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DistributionBarPainter old) =>
      old.fill != fill;
}

/// Mini reticle corners for highlight cards.
class _MiniReticlePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = _kTeal.atOpacity(0.15)
      ..strokeWidth = 0.5
      ..style = PaintingStyle.stroke;
    const arm = 8.0;
    // TL.
    canvas.drawLine(const Offset(0, arm), Offset.zero, p);
    canvas.drawLine(Offset.zero, const Offset(arm, 0), p);
    // TR.
    canvas.drawLine(Offset(size.width - arm, 0), Offset(size.width, 0), p);
    canvas.drawLine(Offset(size.width, 0), Offset(size.width, arm), p);
    // BL.
    canvas.drawLine(
        Offset(0, size.height - arm), Offset(0, size.height), p);
    canvas.drawLine(Offset(0, size.height), Offset(arm, size.height), p);
    // BR.
    canvas.drawLine(Offset(size.width, size.height - arm),
        Offset(size.width, size.height), p);
    canvas.drawLine(Offset(size.width - arm, size.height),
        Offset(size.width, size.height), p);
  }

  @override
  bool shouldRepaint(covariant _MiniReticlePainter old) => false;
}

/// Classification stamps overlay.
class _ClassificationStamps extends StatelessWidget {
  const _ClassificationStamps({required this.opacity});
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity * 0.06,
      child: Center(
        child: Transform.rotate(
          angle: -0.5, // ~30 degrees.
          child: const Text(
            'DECLASSIFIED',
            style: TextStyle(
              fontFamily: BaselineTypography.monoFontFamily,
              fontSize: 48,
              fontWeight: FontWeight.w700,
              color: _kTeal,
              letterSpacing: 8,
            ),
          ),
        ),
      ),
    );
  }
}

/// Intel dot grid background.
class _IntelDotGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = _kTeal.atOpacity(0.02);
    for (double x = 8; x < size.width; x += 16) {
      for (double y = 8; y < size.height; y += 16) {
        canvas.drawCircle(Offset(x, y), 1, p);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _IntelDotGridPainter old) => false;
}

/// Bespoke chevron (replaces Icons.chevron_right).
class _ChevronPainter extends CustomPainter {
  _ChevronPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final cx = size.width / 2;
    final cy = size.height / 2;
    canvas.drawLine(Offset(cx - 3, cy - 5), Offset(cx + 3, cy), p);
    canvas.drawLine(Offset(cx + 3, cy), Offset(cx - 3, cy + 5), p);
  }

  @override
  bool shouldRepaint(covariant _ChevronPainter old) => old.color != color;
}

/// Bespoke lock icon (replaces Icons.lock_outline).
class _LockPainter extends CustomPainter {
  _LockPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    final w = size.width;
    final h = size.height;
    // Body.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.2, h * 0.45, w * 0.6, h * 0.45),
        const Radius.circular(1),
      ),
      p,
    );
    // Shackle.
    canvas.drawArc(
      Rect.fromLTWH(w * 0.3, h * 0.15, w * 0.4, h * 0.4),
      math.pi,
      math.pi,
      false,
      p,
    );
    // Keyhole dot.
    canvas.drawCircle(
      Offset(w * 0.5, h * 0.62),
      1.5,
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _LockPainter old) => old.color != color;
}

// ═══════════════════════════════════════════════════════════
// UTILITIES
// ═══════════════════════════════════════════════════════════

String _formatMilitaryDTG(DateTime? dt) {
  if (dt == null) return '';
  final u = dt.toUtc();
  return '${_pad2(u.day)}${_pad2(u.hour)}${_pad2(u.minute)}Z'
      '${_monthAbbrev(u.month)}${u.year.toString().substring(2)}';
}

String _pad2(int n) => n.toString().padLeft(2, '0');

String _monthAbbrev(int m) {
  const months = [
    '',
    'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
    'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC',
  ];
  return months[m.clamp(1, 12)];
}
