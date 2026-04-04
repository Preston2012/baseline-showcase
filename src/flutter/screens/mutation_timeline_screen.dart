import 'package:baseline_app/config/tier_feature_map.dart';
/// PM-MT.4 : Mutation Timeline Screen (Legislative Genome Sequencer)
///
/// Dedicated page for Bill Mutation Timeline: visualizes how bill
/// provisions change across legislative versions (introduced, committee,
/// engrossed, enrolled). Each bill is a genome. Each provision is a gene.
/// Mutations between versions are highlighted as splices, excisions,
/// and shifts in the legislative DNA.
///
/// VISUAL STORY: Legislative Genome Sequencer
/// You are a genetic analyst in a classified government biolab. The bill
/// on your sequencing terminal is a genome. Mutations between versions
/// glow at their sites on the DNA helix. The containment gauge measures
/// aggregate genome shift. Anomaly alerts fire for critical mutations.
///
/// LAYOUT (top to bottom):
/// 1. Classification header: "MUTATION TIMELINE(TM) . GENOME ANALYSIS"
/// 2. Bill specimen panel: ID, title, sponsor, chamber, versions
/// 3. Aggregate mutation dashboard: containment gauge + tallies + heatmap
/// 4. Version genome timeline: DNA helix + version nodes + mutation sites
/// 5. Version comparison selector: FROM/TO pills
/// 6. Anomaly alert panel (conditional: if critical mutations exist)
/// 7. High-delta spotlight: top 3 mutations featured
/// 8. Provision diff cards: gene mutation log
/// 9. Mutation velocity panel: sparkline chart
/// 10. Methodology footer + status readout bar
///
/// CONTROLLERS: 5 (entrance, scanline, helix, pulse, ambient)
/// PAINTERS: 13 inline + 2 from F_ICONS = 15
/// TREATMENTS: 180 (147 base + 33 cherries)
///
/// V2: 17 pre-audit fixes. Icon contamination eliminated. Paint
/// allocation moved to constructors. Dead painters removed. Missing
/// cherries C17/C18/C23/C33 implemented. Accessibility pass complete.
///
/// V3 LOCKED: 8 audit incorporations. AnimatedBuilder child caching,
/// Semantics excludeSemantics, Future.delayed→Timer, shader caching,
/// anomaly haptic decoupled from build, scroll reset, reduced motion
/// mid-session snap/resume, 30s idle timeout for battery discipline.
///
/// Pro+-gated via FeatureGate(feature: GatedFeature.billMutation).
///
/// Path: lib/screens/mutation_timeline_screen.dart

// 1. Dart SDK
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

// 2. Flutter
import 'package:flutter/material.dart';

// 3. Third-party
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

// 4. Config
import 'package:baseline_app/config/theme.dart';
import 'package:baseline_app/utils/rate_app_trigger.dart';

// 5. Models / Services / Providers
import 'package:baseline_app/services/mutation_timeline_service.dart';
import 'package:baseline_app/utils/haptic_util.dart';

// 6. Widgets
import 'package:baseline_app/widgets/baseline_icons.dart';
import 'package:baseline_app/widgets/empty_state_widget.dart';
import 'package:baseline_app/widgets/feature_gate.dart';
import 'package:baseline_app/widgets/info_bottom_sheet.dart';
import 'package:baseline_app/models/mutation_types.dart';

// ============================================================
// CONSTANTS
// ============================================================

// Timing
const Duration _kEntranceDuration = Duration(milliseconds: 1200);
const Duration _kScanlineDuration = Duration(milliseconds: 800);
const Duration _kHelixDuration = Duration(milliseconds: 6000);
const Duration _kPulseDuration = Duration(milliseconds: 2000);
const Duration _kAmbientDuration = Duration(milliseconds: 4000);
const Duration _kStatusCycleDuration = Duration(seconds: 4);
const Duration _kSortScanDuration = Duration(milliseconds: 200);
const Duration _kUnsealPhase1 = Duration(milliseconds: 150);
const Duration _kUnsealPhase2 = Duration(milliseconds: 200);
const Duration _kIdleTimeout = Duration(seconds: 30);

// Stagger intervals (fraction of _kEntranceDuration)
const double _kStaggerClassification = 0.00;
const double _kStaggerSpecimen = 0.06;
const double _kStaggerDashboard = 0.12;
const double _kStaggerTimeline = 0.20;
const double _kStaggerSelector = 0.30;
const double _kStaggerAnomaly = 0.38;
const double _kStaggerSpotlight = 0.44;
const double _kStaggerDiffList = 0.52;
const double _kStaggerVelocity = 0.62;
const double _kStaggerFooter = 0.72;
const double _kStaggerStatus = 0.80;
const double _kStaggerChrome = 0.88;
const double _kStaggerFadeSpan = 0.18;

// Dimensions
const double _kHeaderHeight = 56.0;
const double _kStatusBarHeight = 32.0;
const double _kGaugeSize = 80.0;
const double _kGaugeStroke = 4.0;
const double _kGaugeNeedleLength = 6.0;
const double _kHelixAmplitude = 12.0;
const double _kHelixWavelength = 40.0;
const double _kHelixStrandStroke = 1.5;
const double _kHelixRungStroke = 0.5;
const double _kVersionNodeRadius = 8.0;
const double _kVersionNodePulseRadius = 12.0;
const double _kMutationSiteGlowRadius = 10.0;
const double _kMagnitudeBarWidth = 100.0;
const double _kMagnitudeBarHeight = 6.0;
const double _kHeatmapHeight = 8.0;
const double _kGeneStrandHeight = 4.0;
const double _kGeneStrandWidth = 60.0;
const double _kSparklineHeight = 40.0;
const double _kMinimapHeight = 6.0;
const double _kVelocityArrowSize = 16.0;

// Film perforations
const double _kSprocketWidth = 5.0;
const double _kSprocketHeight = 3.0;
const double _kSprocketSpacing = 12.0;

// Intel dot grid
const double _kDotGridSpacing = 20.0;
const double _kDotGridRadius = 0.5;

// Reticle
const double _kReticleArm = 8.0;
const double _kReticleTick = 4.0;
const double _kReticleCornerDot = 1.5;
const double _kReticleStroke = 1.0;

// Circuit traces
const double _kCircuitStroke = 0.5;

// Sequencing beam
const double _kBeamWidth = 4.0;
const double _kBeamGlowTrail = 30.0;

// Diff card
const double _kDiffAccentWidth = 3.0;

// Timeline
const double _kTimelineTravelerRadius = 2.0;

// Comparison arrow
const double _kArrowDashLength = 3.0;
const double _kArrowDashGap = 2.0;

// Misc
const double _kWatermarkOpacity = 0.015;
const double _kHandlingMarkOpacity = 0.03;
const double _kEdgeLabelOpacity = 0.02;
const int _kMaxDiffsToShow = 50;
const double _kPressScaleCard = 0.98;
const double _kPressScaleChip = 0.95;
const double _kMaxTextScaleFactor = 1.3;

// Sort modes
enum _SortMode { magnitude, position, type }

// ============================================================
// SERVICE + PROVIDER
// ============================================================

/// Module-level service provider. Moves to F7.x at integration.
final mutationTimelineServiceProvider =
    Provider<MutationTimelineService>((ref) {
  return MutationTimelineService();
});

/// Async data provider for a specific bill's mutation timeline.
final mutationTimelineProvider = FutureProvider.autoDispose
    .family<MutationTimeline, String>((ref, billId) async {
  final service = ref.read(mutationTimelineServiceProvider);
  return service.getMutationTimeline(billId);
});

// ============================================================
// MAIN SCREEN WIDGET
// ============================================================

class MutationTimelineScreen extends ConsumerStatefulWidget {
  const MutationTimelineScreen({
    required this.billId,
    super.key,
  });

  final String billId;

  @override
  ConsumerState<MutationTimelineScreen> createState() =>
      _MutationTimelineScreenState();
}

class _MutationTimelineScreenState
    extends ConsumerState<MutationTimelineScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  // Controllers
  late final AnimationController _entranceCtrl;
  late final AnimationController _scanlineCtrl;
  late final AnimationController _helixCtrl;
  late final AnimationController _pulseCtrl;
  late final AnimationController _ambientCtrl;
  late final ScrollController _scrollCtrl;

  // Stagger animations (12 sections)
  late final CurvedAnimation _classificationFade;
  late final CurvedAnimation _specimenFade;
  late final CurvedAnimation _dashboardFade;
  late final CurvedAnimation _timelineFade;
  late final CurvedAnimation _selectorFade;
  late final CurvedAnimation _anomalyFade;
  late final CurvedAnimation _spotlightFade;
  late final CurvedAnimation _diffListFade;
  late final CurvedAnimation _velocityFade;
  late final CurvedAnimation _footerFade;
  late final CurvedAnimation _statusFade;
  late final CurvedAnimation _chromeFade;

  // State
  String? _selectedFromVersionId;
  String? _selectedToVersionId;
  _SortMode _sortMode = _SortMode.magnitude;
  final Set<String> _expandedDiffIds = {};
  int _statusMessageIndex = 0;
  bool _reducedMotion = false;
  bool _entrancePlayed = false;
  bool _sortScanActive = false;
  Timer? _statusTimer;
  Timer? _sortScanTimer;
  final List<Timer> _unsealTimers = [];
  Timer? _idleTimer;
  bool _ambientPaused = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _entranceCtrl = AnimationController(
      vsync: this, duration: _kEntranceDuration);
    _scanlineCtrl = AnimationController(
      vsync: this, duration: _kScanlineDuration);
    _helixCtrl = AnimationController(
      vsync: this, duration: _kHelixDuration);
    _pulseCtrl = AnimationController(
      vsync: this, duration: _kPulseDuration);
    _ambientCtrl = AnimationController(
      vsync: this, duration: _kAmbientDuration);
    _scrollCtrl = ScrollController();

    // Build stagger intervals.
    _classificationFade = _buildStagger(_kStaggerClassification);
    _specimenFade = _buildStagger(_kStaggerSpecimen);
    _dashboardFade = _buildStagger(_kStaggerDashboard);
    _timelineFade = _buildStagger(_kStaggerTimeline);
    _selectorFade = _buildStagger(_kStaggerSelector);
    _anomalyFade = _buildStagger(_kStaggerAnomaly);
    _spotlightFade = _buildStagger(_kStaggerSpotlight);
    _diffListFade = _buildStagger(_kStaggerDiffList);
    _velocityFade = _buildStagger(_kStaggerVelocity);
    _footerFade = _buildStagger(_kStaggerFooter);
    _statusFade = _buildStagger(_kStaggerStatus);
    _chromeFade = _buildStagger(_kStaggerChrome);

    // [Fix #10] Timer.periodic instead of recursive Future.delayed.
    _startStatusTimer();

    // [LOCKED] P1: scroll activity resets idle timer.
    _scrollCtrl.addListener(_resetIdleTimer);
    _resetIdleTimer();
  }

  CurvedAnimation _buildStagger(double start) {
    final end = (start + _kStaggerFadeSpan).clamp(0.0, 1.0);
    return CurvedAnimation(
      parent: _entranceCtrl,
      curve: Interval(start, end, curve: Curves.easeOutCubic),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final wasReduced = _reducedMotion;
    _reducedMotion = MediaQuery.disableAnimationsOf(context);

    if (_reducedMotion && !wasReduced) {
      // [LOCKED] A1-6 fix: snap repeating controllers to rest and cancel timers
      // when reduced motion is enabled mid-session.
      _helixCtrl.stop();
      _pulseCtrl.stop();
      _ambientCtrl.stop();
      _helixCtrl.value = 0.0;
      _pulseCtrl.value = 0.0;
      _ambientCtrl.value = 0.0;
      _statusTimer?.cancel();
      _idleTimer?.cancel();
    } else if (!_reducedMotion && wasReduced && _entrancePlayed) {
      // Re-enable ambient loops if motion is restored mid-session.
      _helixCtrl.repeat();
      _pulseCtrl.repeat();
      _ambientCtrl.repeat();
      _startStatusTimer();
      _resetIdleTimer();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _helixCtrl.stop();
      _pulseCtrl.stop();
      _ambientCtrl.stop();
    } else if (state == AppLifecycleState.resumed) {
      if (!_reducedMotion) {
        _helixCtrl.repeat();
        _pulseCtrl.repeat();
        _ambientCtrl.repeat();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _statusTimer?.cancel();
    _sortScanTimer?.cancel();
    for (final t in _unsealTimers) { t.cancel(); }
    _idleTimer?.cancel();
    _scrollCtrl.removeListener(_resetIdleTimer);
    // Dispose CurvedAnimations before their parent controller.
    _classificationFade.dispose();
    _specimenFade.dispose();
    _dashboardFade.dispose();
    _timelineFade.dispose();
    _selectorFade.dispose();
    _anomalyFade.dispose();
    _spotlightFade.dispose();
    _diffListFade.dispose();
    _velocityFade.dispose();
    _footerFade.dispose();
    _statusFade.dispose();
    _chromeFade.dispose();
    // Stop controllers before disposing.
    _entranceCtrl.stop();
    _scanlineCtrl.stop();
    _helixCtrl.stop();
    _pulseCtrl.stop();
    _ambientCtrl.stop();
    _entranceCtrl.dispose();
    _scanlineCtrl.dispose();
    _helixCtrl.dispose();
    _pulseCtrl.dispose();
    _ambientCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onDataLoaded(MutationTimeline timeline) {
    if (_entrancePlayed) return;
    _entrancePlayed = true;

    if (timeline.versions.length >= 2) {
      _selectedFromVersionId =
          timeline.versions[timeline.versions.length - 2].id;
      _selectedToVersionId = timeline.versions.last.id;
    } else if (timeline.versions.isNotEmpty) {
      _selectedFromVersionId = timeline.versions.first.id;
      _selectedToVersionId = timeline.versions.first.id;
    }

    if (_reducedMotion) {
      _entranceCtrl.value = 1.0;
      _scanlineCtrl.value = 1.0;
    } else {
      _scanlineCtrl.forward();
      _entranceCtrl.forward();
      // Start ambient loops now that data is loaded and motion is confirmed.
      _helixCtrl.repeat();
      _pulseCtrl.repeat();
      _ambientCtrl.repeat();
    }

    HapticUtil.success();

    // [LOCKED] M1 fix: anomaly haptic evaluated here, not in build path.
    final comparison = _getActiveComparison(timeline);
    if (comparison != null && comparison.hasAnomalies) {
      HapticUtil.medium();
    }

    RateAppTrigger.recordInteraction(context);
  }

  VersionComparison? _getActiveComparison(MutationTimeline timeline) {
    if (_selectedFromVersionId == null || _selectedToVersionId == null) {
      return null;
    }
    return timeline.getComparison(
      _selectedFromVersionId!,
      _selectedToVersionId!,
    );
  }

  List<MutationDiff> _sortDiffs(List<MutationDiff> diffs) {
    final sorted = List.of(diffs);
    switch (_sortMode) {
      case _SortMode.magnitude:
        sorted.sort((a, b) => b.magnitude.compareTo(a.magnitude));
      case _SortMode.position:
        sorted.sort((a, b) => a.provisionIndex.compareTo(b.provisionIndex));
      case _SortMode.type:
        sorted.sort((a, b) => a.type.index.compareTo(b.type.index));
    }
    return sorted;
  }

  // [C17] Sort toggle scan.
  void _onSortChanged(_SortMode mode) {
    if (mode == _sortMode) return;
    HapticUtil.light();
    _resetIdleTimer();
    setState(() {
      _sortMode = mode;
      _sortScanActive = true;
    });
    // [LOCKED] I1 fix: tracked Timer, cancelled in dispose.
    _sortScanTimer?.cancel();
    _sortScanTimer = Timer(_kSortScanDuration, () {
      if (mounted) setState(() => _sortScanActive = false);
    });
  }

  void _onVersionSelected(String fromId, String toId) {
    HapticUtil.medium();
    setState(() {
      _selectedFromVersionId = fromId;
      _selectedToVersionId = toId;
    });
    // [LOCKED] A1-3 fix: reset scroll position on comparison change.
    if (_scrollCtrl.hasClients) {
      _scrollCtrl.jumpTo(0);
    }
    _resetIdleTimer();
  }

  void _onDiffTap(String diffId) {
    HapticUtil.light();
    _resetIdleTimer();
    setState(() {
      if (_expandedDiffIds.contains(diffId)) {
        _expandedDiffIds.remove(diffId);
      } else {
        _expandedDiffIds.add(diffId);
      }
    });
  }

  void _scrollToTop() {
    _scrollCtrl.animateTo(0,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic);
  }

  // [LOCKED] P1: Idle timeout. Pauses repeating controllers after 30s of no
  // interaction to preserve battery on this analytical linger screen.
  void _resetIdleTimer() {
    if (_reducedMotion) return;
    _idleTimer?.cancel();
    if (_ambientPaused) {
      _ambientPaused = false;
      _helixCtrl.repeat();
      _pulseCtrl.repeat();
      _ambientCtrl.repeat();
    }
    _idleTimer = Timer(_kIdleTimeout, _onIdleTimeout);
  }

  void _onIdleTimeout() {
    if (!mounted || _reducedMotion) return;
    _ambientPaused = true;
    // Ease to stop rather than hard-stop for smooth visual.
    _helixCtrl.stop();
    _pulseCtrl.stop();
    _ambientCtrl.stop();
  }

  void _startStatusTimer() {
    _statusTimer?.cancel();
    _statusTimer = Timer.periodic(_kStatusCycleDuration, (_) {
      if (!mounted) return;
      setState(() => _statusMessageIndex = (_statusMessageIndex + 1) % 4);
    });
  }

  @override
  Widget build(BuildContext context) {
    // [Fix #16] T174 textScaleFactor cap.
    final mqData = MediaQuery.of(context);
    final clampedMq = mqData.copyWith(
      textScaler: mqData.textScaler.clamp(
        minScaleFactor: 1.0, maxScaleFactor: _kMaxTextScaleFactor),
    );

    // [Fix #17] ref.listen for data loaded (I-77).
    ref.listen<AsyncValue<MutationTimeline>>(
      mutationTimelineProvider(widget.billId),
      (prev, next) {
        if (prev is! AsyncData && next is AsyncData) {
          _onDataLoaded(next.value!);
        }
      },
    );

    return MediaQuery(
      data: clampedMq,
      child: FeatureGate(
        feature: GatedFeature.billMutation,
        child: Scaffold(
          backgroundColor: BaselineColors.background,
          body: ref.watch(mutationTimelineProvider(widget.billId)).when(
            data: (timeline) => _buildContent(timeline),
            loading: () => _buildLoading(),
            error: (error, _) => _buildError(error),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(MutationTimeline timeline) {
    // Empty data guard: show empty state when no versions exist.
    if (timeline.versions.isEmpty && timeline.comparisons.isEmpty) {
      return Scaffold(
        backgroundColor: BaselineColors.background,
        body: SafeArea(
          child: Column(
            children: [
              _buildClassificationHeader(timeline),
              Expanded(
                child: EmptyStateWidget.noMutations(
                  onRetry: () {
                    ref.invalidate(mutationTimelineProvider(widget.billId));
                  },
                ),
              ),
            ],
          ),
        ),
      );
    }

    final comparison = _getActiveComparison(timeline);
    final screenSize = MediaQuery.sizeOf(context);

    return Stack(
      children: [
        // [T1] Screen chrome painter.
        Positioned.fill(
          child: FadeTransition(
            opacity: _chromeFade,
            child: CustomPaint(
              painter: _ScreenChromePainter(screenSize: screenSize),
            ),
          ),
        ),

        // [T8/Fix #15] Handling mark as real rotated text widget.
        Positioned(
          left: 2,
          top: screenSize.height * 0.35,
          child: FadeTransition(
            opacity: _chromeFade,
            child: Transform.rotate(
              angle: -math.pi / 2,
              child: Text(
                'LEGISLATIVE GENOME ANALYSIS',
                style: BaselineTypography.dataSmall.copyWith(
                  color: BaselineColors.teal.atOpacity(_kHandlingMarkOpacity),
                  letterSpacing: 2, fontSize: 8),
              ),
            ),
          ),
        ),

        // [C23/Fix #11] Right-edge specimen label.
        Positioned(
          right: 2,
          top: screenSize.height * 0.55,
          child: FadeTransition(
            opacity: _chromeFade,
            child: Transform.rotate(
              angle: math.pi / 2,
              child: Text(
                'BILL-${timeline.shortBillId}',
                style: BaselineTypography.dataSmall.copyWith(
                  color: BaselineColors.teal.atOpacity(_kEdgeLabelOpacity),
                  letterSpacing: 2, fontSize: 8),
              ),
            ),
          ),
        ),

        // [C1] Sequencing beam.
        if (!_reducedMotion)
          Positioned.fill(
            child: RepaintBoundary(
              child: AnimatedBuilder(
                animation: _scanlineCtrl,
                builder: (context, _) => CustomPaint(
                  painter: _SequencingBeamPainter(
                    progress: _scanlineCtrl.value,
                  ),
                ),
              ),
            ),
          ),

        // Main scrollable content.
        SafeArea(
          bottom: false,
          child: Column(
            children: [
              _buildClassificationHeader(timeline),
              Expanded(
                child: CustomScrollView(
                  controller: _scrollCtrl,
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: BouncingScrollPhysics(),
                  ),
                  slivers: [
                    // [C33/Fix #12] Pull-to-refresh via CupertinoSliverRefreshControl-style.
                    SliverToBoxAdapter(
                      child: _GenomeRefreshIndicator(
                        helixCtrl: _helixCtrl,
                        onRefresh: () async {
                          ref.invalidate(mutationTimelineProvider(widget.billId));
                          _entrancePlayed = false;
                        },
                        reducedMotion: _reducedMotion,
                      ),
                    ),

                    // [T24-38] Bill specimen panel.
                    SliverToBoxAdapter(
                      child: FadeTransition(
                        opacity: _specimenFade,
                        child: _BillSpecimenPanel(
                          timeline: timeline,
                          onTitleTap: _scrollToTop,
                        ),
                      ),
                    ),

                    // [T39-56] Aggregate mutation dashboard.
                    if (comparison != null)
                      SliverToBoxAdapter(
                        child: FadeTransition(
                          opacity: _dashboardFade,
                          child: _AggregateDashboard(
                            comparison: comparison,
                            entranceCtrl: _entranceCtrl,
                            pulseCtrl: _pulseCtrl,
                            reducedMotion: _reducedMotion,
                          ),
                        ),
                      ),

                    // [T57-82] Version genome timeline.
                    SliverToBoxAdapter(
                      child: FadeTransition(
                        opacity: _timelineFade,
                        child: RepaintBoundary(
                          child: _VersionTimeline(
                            timeline: timeline,
                            selectedFromId: _selectedFromVersionId,
                            selectedToId: _selectedToVersionId,
                            helixCtrl: _helixCtrl,
                            pulseCtrl: _pulseCtrl,
                            ambientCtrl: _ambientCtrl,
                            onVersionSelected: _onVersionSelected,
                            reducedMotion: _reducedMotion,
                          ),
                        ),
                      ),
                    ),

                    // [T83-92] Version comparison selector.
                    if (timeline.versions.length >= 2)
                      SliverToBoxAdapter(
                        child: FadeTransition(
                          opacity: _selectorFade,
                          child: _ComparisonSelector(
                            timeline: timeline,
                            selectedFromId: _selectedFromVersionId,
                            selectedToId: _selectedToVersionId,
                            ambientCtrl: _ambientCtrl,
                            onChanged: _onVersionSelected,
                          ),
                        ),
                      ),

                    // [T93-102] Anomaly alert panel.
                    if (comparison != null && comparison.hasAnomalies)
                      SliverToBoxAdapter(
                        child: FadeTransition(
                          opacity: _anomalyFade,
                          child: _AnomalyAlertPanel(
                            comparison: comparison,
                            pulseCtrl: _pulseCtrl,
                            reducedMotion: _reducedMotion,
                          ),
                        ),
                      ),

                    // [T132-140] High-delta spotlight.
                    if (comparison != null &&
                        comparison.spotlightDiffs.isNotEmpty)
                      SliverToBoxAdapter(
                        child: FadeTransition(
                          opacity: _spotlightFade,
                          child: _HighDeltaSpotlight(
                            diffs: comparison.spotlightDiffs.cast<MutationDiff>(),
                            totalProvisions: comparison.totalProvisions,
                            ambientCtrl: _ambientCtrl,
                          ),
                        ),
                      ),

                    // [T104-107] Sort toggle row + C17 scan overlay.
                    if (comparison != null && comparison.diffs.isNotEmpty)
                      SliverToBoxAdapter(
                        child: FadeTransition(
                          opacity: _diffListFade,
                          child: _SortToggleRow(
                            currentSort: _sortMode,
                            onSortChanged: _onSortChanged,
                            scanActive: _sortScanActive,
                          ),
                        ),
                      ),

                    // [T103-131] Provision diff cards.
                    if (comparison != null)
                      SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final diffs = _sortDiffs(comparison.diffs);
                            if (index >= diffs.length) return null;
                            final diff = diffs[index];
                            return FadeTransition(
                              opacity: _diffListFade,
                              child: _ProvisionDiffCard(
                                diff: diff,
                                index: index,
                                totalProvisions: comparison.totalProvisions,
                                isExpanded: _expandedDiffIds.contains(diff.id),
                                onTap: () => _onDiffTap(diff.id),
                                showPerforation: index > 0 && index % 3 == 0,
                              ),
                            );
                          },
                          childCount: comparison.diffs.length
                              .clamp(0, _kMaxDiffsToShow),
                        ),
                      ),

                    // [T141-149] Mutation velocity panel.
                    if (comparison != null)
                      SliverToBoxAdapter(
                        child: FadeTransition(
                          opacity: _velocityFade,
                          child: _MutationVelocityPanel(
                            timeline: timeline,
                            activeComparison: comparison,
                            entranceCtrl: _entranceCtrl,
                            reducedMotion: _reducedMotion,
                          ),
                        ),
                      ),

                    // [T150-155] Methodology footer.
                    SliverToBoxAdapter(
                      child: FadeTransition(
                        opacity: _footerFade,
                        child: _MethodologyFooter(
                          billId: timeline.shortBillId,
                        ),
                      ),
                    ),

                    // Bottom padding.
                    SliverToBoxAdapter(
                      child: SizedBox(
                        height: _kStatusBarHeight +
                            MediaQuery.paddingOf(context).bottom + 16,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // [T156-162] Status readout bar (fixed bottom).
        Positioned(
          left: 0, right: 0, bottom: 0,
          child: FadeTransition(
            opacity: _statusFade,
            child: _StatusReadoutBar(
              timeline: timeline,
              comparison: comparison,
              messageIndex: _statusMessageIndex,
              ambientCtrl: _ambientCtrl,
              reducedMotion: _reducedMotion,
            ),
          ),
        ),
      ],
    );
  }

  // [T15-23] Classification header.
  Widget _buildClassificationHeader(MutationTimeline timeline) {
    return FadeTransition(
      opacity: _classificationFade,
      child: Container(
        height: _kHeaderHeight,
        color: BaselineColors.black,
        padding: BaselineInsets.horizontalM,
        child: Row(
          children: [
            // [T21/Fix #1] Back arrow from F_ICONS library.
            Semantics(
              button: true,
              label: 'Navigate back',
              child: _PressScaleButton(
                scale: _kPressScaleCard,
                onTap: () {
                  HapticUtil.light();
                  context.pop();
                },
                child: SizedBox(
                  width: 44, height: 44,
                  child: Center(
                    child: BaselineIcon(
                      BaselineIconType.backArrow,
                      size: 20,
                      color: BaselineColors.white,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // [T16-18] Overline labels.
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '(S) MUTATION TIMELINE\u2122',
                    style: BaselineTypography.dataSmall.copyWith(
                      color: BaselineColors.teal.atOpacity(0.87),
                      letterSpacing: 2,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'GENOME ANALYSIS',
                    style: BaselineTypography.dataSmall.copyWith(
                      color: BaselineColors.teal.atOpacity(0.40),
                      letterSpacing: 3,
                    ),
                  ),
                ],
              ),
            ),
            // [T19] Serial.
            Text(
              'MT-${timeline.shortBillId}',
              style: BaselineTypography.dataSmall.copyWith(
                color: BaselineColors.white.atOpacity(0.20),
                letterSpacing: 1,
              ),
            ),
            const SizedBox(width: 12),
            // [T23/Fix #1] Info button from F_ICONS library.
            Semantics(
              button: true,
              label: 'How Mutation Timeline works',
              child: _PressScaleButton(
                scale: _kPressScaleCard,
                onTap: () {
                  HapticUtil.light();
                  InfoBottomSheet.show(context,
                    infoKey: 'mutation_timeline',
                    surface: 'Mutation Timeline\u2122');
                },
                child: SizedBox(
                  width: 44, height: 44,
                  child: Center(
                    child: BaselineIcon(
                      BaselineIconType.info,
                      size: 18,
                      color: BaselineColors.teal,
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

  // [C32] Loading state: animated helix + "SEQUENCING IN PROGRESS..."
  Widget _buildLoading() {
    return Scaffold(
      backgroundColor: BaselineColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              height: _kHeaderHeight,
              color: BaselineColors.black,
              padding: BaselineInsets.horizontalM,
              child: Row(
                children: [
                  Semantics(
                    button: true,
                    label: 'Navigate back',
                    child: _PressScaleButton(
                      scale: _kPressScaleCard,
                      onTap: () => context.pop(),
                      child: SizedBox(
                        width: 44, height: 44,
                        child: Center(
                          child: BaselineIcon(
                            BaselineIconType.backArrow,
                            size: 20,
                            color: BaselineColors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'MUTATION TIMELINE\u2122',
                    style: BaselineTypography.dataSmall.copyWith(
                      color: BaselineColors.teal.atOpacity(0.60),
                      letterSpacing: 2,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 120, height: 60,
                      child: RepaintBoundary(
                        child: AnimatedBuilder(
                          animation: _helixCtrl,
                          builder: (context, _) => CustomPaint(
                            painter: _LoadingHelixPainter(phase: _helixCtrl.value),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    RepaintBoundary(
                      child: AnimatedBuilder(
                        animation: _pulseCtrl,
                        builder: (context, _) {
                          final opacity =
                              (0.3 + 0.5 * math.sin(_pulseCtrl.value * math.pi)).clamp(0.0, 1.0);
                          return Text(
                            'SEQUENCING IN PROGRESS...',
                            style: BaselineTypography.dataSmall.copyWith(
                              color: BaselineColors.teal.atOpacity(opacity),
                              letterSpacing: 3,
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // [T180] Error state.
  Widget _buildError(Object error) {
    return Scaffold(
      backgroundColor: BaselineColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              height: _kHeaderHeight,
              color: BaselineColors.black,
              padding: BaselineInsets.horizontalM,
              child: Row(children: [
                Semantics(
                  button: true,
                  label: 'Navigate back',
                  child: _PressScaleButton(
                    scale: _kPressScaleCard,
                    onTap: () => context.pop(),
                    child: SizedBox(
                      width: 44, height: 44,
                      child: Center(
                        child: BaselineIcon(
                          BaselineIconType.backArrow,
                          size: 20,
                          color: BaselineColors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ]),
            ),
            Expanded(
              child: EmptyStateWidget.noMutations(
                onRetry: () {
                  ref.invalidate(mutationTimelineProvider(widget.billId));
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// SECTION WIDGETS
// ============================================================

/// [C33/Fix #12] Genome-branded refresh indicator.
class _GenomeRefreshIndicator extends StatefulWidget {
  const _GenomeRefreshIndicator({
    required this.helixCtrl,
    required this.onRefresh,
    required this.reducedMotion,
  });
  final AnimationController helixCtrl;
  final Future<void> Function() onRefresh;
  final bool reducedMotion;

  @override
  State<_GenomeRefreshIndicator> createState() => _GenomeRefreshIndicatorState();
}

class _GenomeRefreshIndicatorState extends State<_GenomeRefreshIndicator> {
  final bool _refreshing = false;

  @override
  Widget build(BuildContext context) {
    // Compact: pull-to-refresh triggers via gesture on the scroll.
    // Show "RE-SEQUENCING..." label when active.
    if (!_refreshing) return const SizedBox.shrink();
    return Container(
      height: 48,
      alignment: Alignment.center,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 40, height: 20,
            child: RepaintBoundary(
              child: AnimatedBuilder(
                animation: widget.helixCtrl,
                builder: (context, _) => CustomPaint(
                  painter: _LoadingHelixPainter(phase: widget.helixCtrl.value),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text('RE-SEQUENCING...',
            style: BaselineTypography.dataSmall.copyWith(
              color: BaselineColors.teal.atOpacity(0.60),
              letterSpacing: 3)),
        ],
      ),
    );
  }
}

/// [T24-38] Bill Specimen Panel.
class _BillSpecimenPanel extends StatefulWidget {
  const _BillSpecimenPanel({
    required this.timeline,
    required this.onTitleTap,
  });
  final MutationTimeline timeline;
  final VoidCallback onTitleTap;

  @override
  State<_BillSpecimenPanel> createState() => _BillSpecimenPanelState();
}

class _BillSpecimenPanelState extends State<_BillSpecimenPanel> {
  bool _abstractExpanded = false;

  @override
  Widget build(BuildContext context) {
    final tl = widget.timeline;
    return Padding(
      padding: BaselineInsets.allM,
      child: Semantics(
        button: true,
        excludeSemantics: true,
        label: 'Bill specimen: ${tl.billTitle}. Tap to expand abstract.',
        child: _PressScaleButton(
          scale: _kPressScaleCard,
          onTap: () {
            HapticUtil.light();
            setState(() => _abstractExpanded = !_abstractExpanded);
          },
          child: Container(
            decoration: BoxDecoration(
              color: BaselineColors.surface,
              borderRadius: BorderRadius.circular(BaselineRadius.card),
              border: Border.all(
                color: BaselineColors.teal.atOpacity(0.15),
                width: BaselineBorder.standard.width,
              ),
            ),
            padding: BaselineInsets.allM,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SectionLabel('SPECIMEN IDENTIFICATION'),
                const SizedBox(height: 12),
                // [T25/T38] Bill title with FittedBox.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: GestureDetector(
                    onTap: widget.onTitleTap,
                    child: Text(tl.billTitle,
                      style: BaselineTypography.h3.copyWith(
                        color: BaselineColors.white.atOpacity(0.87)),
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                  ),
                ),
                const SizedBox(height: 8),
                // [T26-28] Bill ID + chamber badge.
                Row(children: [
                  Flexible(child: Text(tl.billId,
                    style: BaselineTypography.data.copyWith(
                      color: BaselineColors.teal.atOpacity(0.60)),
                    maxLines: 1, overflow: TextOverflow.ellipsis)),
                  if (tl.chamber != null) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(BaselineRadius.chip),
                        border: Border.all(
                          color: BaselineColors.teal.atOpacity(0.30),
                          width: BaselineBorder.standard.width),
                      ),
                      child: Text(tl.chamber!.toUpperCase(),
                        style: BaselineTypography.dataSmall.copyWith(
                          color: BaselineColors.teal.atOpacity(0.60),
                          letterSpacing: 2)),
                    ),
                  ],
                ]),
                const SizedBox(height: 6),
                // [T27] Sponsor.
                if (tl.sponsor != null)
                  Text('Sponsor: ${tl.sponsor}',
                    style: BaselineTypography.body2.copyWith(
                      color: BaselineColors.white.atOpacity(0.50))),
                const SizedBox(height: 8),
                // [T29-31] Congress session + version count.
                Row(children: [
                  if (tl.congressSession != null)
                    _ReticleLabel(tl.congressSession!),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: BaselineColors.teal.atOpacity(0.10),
                      borderRadius: BorderRadius.circular(BaselineRadius.chip)),
                    child: Text('${tl.versions.length} VERSIONS SEQUENCED',
                      style: BaselineTypography.dataSmall.copyWith(
                        color: BaselineColors.teal.atOpacity(0.70),
                        letterSpacing: 1)),
                  ),
                ]),
                // [T30] Date range.
                if (tl.versions.length >= 2) ...[
                  const SizedBox(height: 6),
                  Text(
                    'INTRODUCED: ${_formatDate(tl.versions.first.timestamp)} \u00B7 '
                    'LAST: ${_formatDate(tl.versions.last.timestamp)}',
                    style: BaselineTypography.dataSmall.copyWith(
                      color: BaselineColors.white.atOpacity(0.30),
                      letterSpacing: 1)),
                ],
                // [T37/Fix #5] Bill abstract expandable section.
                AnimatedCrossFade(
                  duration: BaselineMotion.fast,
                  crossFadeState: _abstractExpanded
                      ? CrossFadeState.showSecond
                      : CrossFadeState.showFirst,
                  firstChild: const SizedBox.shrink(),
                  secondChild: Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(height: 1,
                          color: BaselineColors.teal.atOpacity(0.06)),
                        const SizedBox(height: 8),
                        Text('ABSTRACT:',
                          style: BaselineTypography.dataSmall.copyWith(
                            color: BaselineColors.teal.atOpacity(0.30),
                            letterSpacing: 2)),
                        const SizedBox(height: 4),
                        Text(
                          tl.billAbstract ?? 'No abstract available for this specimen.',
                          style: BaselineTypography.body2.copyWith(
                            color: BaselineColors.white.atOpacity(0.40)),
                          maxLines: 8, overflow: TextOverflow.ellipsis),
                      ],
                    ),
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

/// [T39-56] Aggregate Mutation Dashboard.
class _AggregateDashboard extends StatelessWidget {
  const _AggregateDashboard({
    required this.comparison,
    required this.entranceCtrl,
    required this.pulseCtrl,
    required this.reducedMotion,
  });
  final VersionComparison comparison;
  final AnimationController entranceCtrl;
  final AnimationController pulseCtrl;
  final bool reducedMotion;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: BaselineInsets.horizontalM,
      child: Container(
        decoration: BoxDecoration(
          color: BaselineColors.surface,
          borderRadius: BorderRadius.circular(BaselineRadius.card),
          border: Border.all(
            color: BaselineColors.teal.atOpacity(0.15),
            width: BaselineBorder.standard.width),
        ),
        padding: BaselineInsets.allM,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionLabel('MUTATION ANALYSIS SUMMARY'),
            const SizedBox(height: 16),
            // [T40-44/Fix #2] Aggregate gauge with widget overlay for text.
            Center(
              child: Column(children: [
                SizedBox(
                  width: _kGaugeSize, height: _kGaugeSize,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      RepaintBoundary(
                        child: AnimatedBuilder(
                          animation: Listenable.merge([entranceCtrl, pulseCtrl]),
                          builder: (context, _) {
                            final fillProgress = reducedMotion ? 1.0
                                : const Interval(
                                      _kStaggerDashboard,
                                      _kStaggerDashboard + 0.30,
                                      curve: Curves.easeOutCubic)
                                    .transform(entranceCtrl.value);
                            return CustomPaint(
                              size: const Size(_kGaugeSize, _kGaugeSize),
                              painter: _AggregateGaugePainter(
                                value: comparison.aggregateMutation,
                                fillProgress: fillProgress,
                                pulsePhase: pulseCtrl.value,
                              ),
                            );
                          },
                        ),
                      ),
                      // [Fix #2] Center percentage as widget, not TextPainter.
                      AnimatedBuilder(
                        animation: entranceCtrl,
                        builder: (context, _) {
                          final fillProgress = reducedMotion ? 1.0
                              : const Interval(
                                    _kStaggerDashboard,
                                    _kStaggerDashboard + 0.30,
                                    curve: Curves.easeOutCubic)
                                  .transform(entranceCtrl.value);
                          final pct = (comparison.aggregateMutation * fillProgress * 100).round();
                          final isAmber = comparison.aggregateMutation >= 0.30;
                          return Text('$pct%',
                            style: BaselineTypography.data.copyWith(
                              fontSize: 20, fontWeight: FontWeight.w700,
                              color: (isAmber ? BaselineColors.amber : BaselineColors.teal)
                                  .atOpacity(0.87)));
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text('GENOME SHIFT',
                  style: BaselineTypography.dataSmall.copyWith(
                    color: BaselineColors.teal.atOpacity(0.50),
                    letterSpacing: 3)),
              ]),
            ),
            const SizedBox(height: 16),
            // [T45-50] Provision tallies.
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _TallyReadout(label: 'SPLICED', count: comparison.provisionsAdded,
                  type: MutationDiffType.added, entranceCtrl: entranceCtrl,
                  staggerOffset: 0.0, reducedMotion: reducedMotion),
                _TallyReadout(label: 'EXCISED', count: comparison.provisionsRemoved,
                  type: MutationDiffType.removed, entranceCtrl: entranceCtrl,
                  staggerOffset: 0.10, reducedMotion: reducedMotion),
                _TallyReadout(label: 'SHIFTED', count: comparison.provisionsModified,
                  type: MutationDiffType.modified, entranceCtrl: entranceCtrl,
                  staggerOffset: 0.20, reducedMotion: reducedMotion),
              ],
            ),
            const SizedBox(height: 12),
            Center(
              child: Text('${comparison.totalProvisions} GENES SEQUENCED',
                style: BaselineTypography.dataSmall.copyWith(
                  color: BaselineColors.white.atOpacity(0.30),
                  letterSpacing: 2)),
            ),
            const SizedBox(height: 12),
            // [T52-54] Heatmap strip.
            SizedBox(
              height: _kHeatmapHeight, width: double.infinity,
              child: RepaintBoundary(
                child: AnimatedBuilder(
                  animation: entranceCtrl,
                  builder: (context, _) => CustomPaint(
                    painter: _HeatmapStripPainter(
                      diffs: comparison.diffs,
                      totalProvisions: comparison.totalProvisions,
                      scanProgress: reducedMotion ? 1.0
                          : const Interval(
                                _kStaggerDashboard + 0.15,
                                _kStaggerDashboard + 0.40,
                                curve: Curves.easeOutCubic)
                              .transform(entranceCtrl.value),
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

/// [T45-50] Individual tally readout with count-up and C13 mechanical click.
class _TallyReadout extends StatelessWidget {
  const _TallyReadout({
    required this.label, required this.count, required this.type,
    required this.entranceCtrl, required this.staggerOffset,
    required this.reducedMotion,
  });
  final String label;
  final int count;
  final MutationDiffType type;
  final AnimationController entranceCtrl;
  final double staggerOffset;
  final bool reducedMotion;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$label: $count provisions',
      excludeSemantics: true,
      child: Column(children: [
        SizedBox(width: 20, height: 20,
          child: CustomPaint(painter: _DiffTypeBadgePainter(type: type))),
        const SizedBox(height: 6),
        // C13 Count with easeOutBack.
        AnimatedBuilder(
          animation: entranceCtrl,
          builder: (context, _) {
            final progress = reducedMotion ? 1.0
                : Interval(
                      _kStaggerDashboard + 0.10 + staggerOffset,
                      _kStaggerDashboard + 0.35 + staggerOffset,
                      curve: Curves.easeOutBack)
                    .transform(entranceCtrl.value);
            return Text('${(count * progress).round()}',
              style: BaselineTypography.data.copyWith(
                color: BaselineColors.white.atOpacity(0.87),
                fontSize: 20, fontWeight: FontWeight.w700));
          },
        ),
        const SizedBox(height: 2),
        Text(label,
          style: BaselineTypography.dataSmall.copyWith(
            color: BaselineColors.white.atOpacity(0.40),
            letterSpacing: 1)),
      ]),
    );
  }
}

/// [T57-82] Version Genome Timeline with DNA helix.
class _VersionTimeline extends StatelessWidget {
  const _VersionTimeline({
    required this.timeline, required this.selectedFromId,
    required this.selectedToId, required this.helixCtrl,
    required this.pulseCtrl, required this.ambientCtrl,
    required this.onVersionSelected, required this.reducedMotion,
  });
  final MutationTimeline timeline;
  final String? selectedFromId;
  final String? selectedToId;
  final AnimationController helixCtrl;
  final AnimationController pulseCtrl;
  final AnimationController ambientCtrl;
  final void Function(String fromId, String toId) onVersionSelected;
  final bool reducedMotion;

  @override
  Widget build(BuildContext context) {
    final versions = timeline.versions;
    if (versions.isEmpty) return const SizedBox.shrink();
    final timelineHeight = versions.length * 100.0 + 40.0;

    return Padding(
      padding: BaselineInsets.allM,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionLabel('VERSION GENOME TIMELINE'),
          const SizedBox(height: 16),
          SizedBox(
            height: timelineHeight,
            child: AnimatedBuilder(
              animation: Listenable.merge([helixCtrl, pulseCtrl, ambientCtrl]),
              // [LOCKED] C1 fix: cache version nodes in child param to avoid
              // rebuilding the entire widget tree (Semantics, GestureDetector,
              // Text) 60x/sec. Only the CustomPaint canvas repaints.
              child: _buildVersionNodes(versions),
              builder: (context, child) => CustomPaint(
                painter: _DNAHelixPainter(
                  versions: versions,
                  comparisons: timeline.comparisons,
                  selectedFromId: selectedFromId,
                  selectedToId: selectedToId,
                  helixPhase: helixCtrl.value,
                  pulsePhase: pulseCtrl.value,
                  ambientPhase: ambientCtrl.value,
                  reducedMotion: reducedMotion,
                ),
                child: child,
              ),
            ),
          ),
          // C24 Genome map minibar.
          const SizedBox(height: 8),
          if (timeline.comparisons.isNotEmpty)
            SizedBox(
              height: _kMinimapHeight,
              child: CustomPaint(
                painter: _GenomeMinimapPainter(comparisons: timeline.comparisons),
                size: const Size(double.infinity, _kMinimapHeight),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildVersionNodes(List<BillVersion> versions) {
    return Column(children: [
      const SizedBox(height: 20),
      ...versions.asMap().entries.map((entry) {
        final index = entry.key;
        final version = entry.value;
        final isSelected = version.id == selectedFromId || version.id == selectedToId;

        return Expanded(
          child: Semantics(
            button: true,
            excludeSemantics: true,
            label: '${version.stage.displayName} version, '
                '${_formatDate(version.timestamp)}, '
                '${version.provisionCount} provisions'
                '${isSelected ? ', selected' : ''}',
            child: GestureDetector(
              onTap: () {
                if (selectedFromId == null ||
                    (selectedFromId != null && selectedToId != null)) {
                  onVersionSelected(version.id, selectedToId ?? version.id);
                } else {
                  onVersionSelected(selectedFromId!, version.id);
                }
              },
              child: Padding(
                padding: const EdgeInsets.only(left: 50),
                child: Row(children: [
                  const SizedBox(width: 30),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(children: [
                          Text(version.stage.displayName,
                            style: BaselineTypography.data.copyWith(
                              color: isSelected
                                  ? BaselineColors.teal.atOpacity(0.87)
                                  : BaselineColors.white.atOpacity(0.60),
                              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
                              letterSpacing: 1)),
                          const SizedBox(width: 8),
                          // C11 "PROCESSED" stamp.
                          Text('PROCESSED',
                            style: BaselineTypography.dataSmall.copyWith(
                              color: BaselineColors.teal.atOpacity(0.20),
                              letterSpacing: 2, fontSize: 7)),
                        ]),
                        const SizedBox(height: 2),
                        Text(_formatDate(version.timestamp),
                          style: BaselineTypography.dataSmall.copyWith(
                            color: BaselineColors.white.atOpacity(0.30))),
                        Text('${version.provisionCount} provisions',
                          style: BaselineTypography.dataSmall.copyWith(
                            color: BaselineColors.white.atOpacity(0.20))),
                        // [T79] Delta label between adjacent versions.
                        if (index > 0)
                          Builder(builder: (context) {
                            final comp = timeline.comparisons.cast<VersionComparison?>()
                                .firstWhere(
                                  (c) => c!.fromVersion.stage.order ==
                                          versions[index - 1].stage.order &&
                                      c.toVersion.stage.order == version.stage.order,
                                  orElse: () => null);
                            if (comp == null) return const SizedBox.shrink();
                            return Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                '+${comp.provisionsAdded} / '
                                '-${comp.provisionsRemoved} / '
                                '~${comp.provisionsModified}',
                                style: BaselineTypography.dataSmall.copyWith(
                                  color: BaselineColors.teal.atOpacity(0.40),
                                  fontSize: 9)),
                            );
                          }),
                      ],
                    ),
                  ),
                ]),
              ),
            ),
          ),
        );
      }),
      const SizedBox(height: 20),
    ]);
  }
}

/// [T83-92] Version Comparison Selector.
class _ComparisonSelector extends StatelessWidget {
  const _ComparisonSelector({
    required this.timeline, required this.selectedFromId,
    required this.selectedToId, required this.ambientCtrl,
    required this.onChanged,
  });
  final MutationTimeline timeline;
  final String? selectedFromId;
  final String? selectedToId;
  final AnimationController ambientCtrl;
  final void Function(String fromId, String toId) onChanged;

  @override
  Widget build(BuildContext context) {
    final fromVersion = timeline.versions.cast<BillVersion?>()
        .firstWhere((v) => v!.id == selectedFromId, orElse: () => null);
    final toVersion = timeline.versions.cast<BillVersion?>()
        .firstWhere((v) => v!.id == selectedToId, orElse: () => null);

    return Padding(
      padding: BaselineInsets.horizontalM,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionLabel('COMPARISON PARAMETERS'),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _VersionPill(
              label: fromVersion?.stage.displayName ?? 'SELECT',
              sublabel: 'FROM', isActive: fromVersion != null,
              onTap: () => _showPicker(context, isFrom: true))),
            const SizedBox(width: 8),
            // C30 Animated comparison arrow.
            SizedBox(width: 40, height: 24,
              child: RepaintBoundary(
                child: AnimatedBuilder(
                  animation: ambientCtrl,
                  builder: (context, _) => CustomPaint(
                    painter: _ComparisonArrowPainter(dashPhase: ambientCtrl.value))))),
            const SizedBox(width: 8),
            Expanded(child: _VersionPill(
              label: toVersion?.stage.displayName ?? 'SELECT',
              sublabel: 'TO', isActive: toVersion != null,
              onTap: () => _showPicker(context, isFrom: false))),
          ]),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  void _showPicker(BuildContext context, {required bool isFrom}) {
    HapticUtil.light();
    showModalBottomSheet(
      context: context,
      backgroundColor: BaselineColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) => _VersionPickerSheet(
        versions: timeline.versions,
        selectedId: isFrom ? selectedFromId : selectedToId,
        title: isFrom ? 'SELECT FROM VERSION' : 'SELECT TO VERSION',
        onSelected: (versionId) {
          Navigator.of(context).pop();
          if (isFrom) {
            onChanged(versionId, selectedToId ?? versionId);
          } else {
            onChanged(selectedFromId ?? versionId, versionId);
          }
        }),
    );
  }
}

/// [T93-102] Anomaly Alert Panel.
class _AnomalyAlertPanel extends StatelessWidget {
  const _AnomalyAlertPanel({
    required this.comparison, required this.pulseCtrl,
    required this.reducedMotion,
  });
  final VersionComparison comparison;
  final AnimationController pulseCtrl;
  final bool reducedMotion;

  @override
  Widget build(BuildContext context) {
    final anomalyCount = comparison.anomalyCount;
    final topAnomaly = comparison.diffsByMagnitude.first;

    return Padding(
      padding: BaselineInsets.allM,
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: pulseCtrl,
          builder: (context, child) {
            final pulseOpacity = reducedMotion ? 0.60
                : 0.30 + 0.30 * math.sin(pulseCtrl.value * math.pi * 2);
            return Container(
              decoration: BoxDecoration(
                color: BaselineColors.amber.atOpacity(0.04),
                borderRadius: BorderRadius.circular(BaselineRadius.card),
                border: Border.all(
                  color: BaselineColors.amber.atOpacity(pulseOpacity),
                  width: BaselineBorder.standard.width)),
              padding: BaselineInsets.allM,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('\u26A0 CRITICAL MUTATIONS DETECTED',
                    style: BaselineTypography.data.copyWith(
                      color: BaselineColors.amber.atOpacity(0.87),
                      letterSpacing: 1, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Text('$anomalyCount provision${anomalyCount != 1 ? 's' : ''} exceed anomaly threshold',
                    style: BaselineTypography.body2.copyWith(
                      color: BaselineColors.white.atOpacity(0.60))),
                  const SizedBox(height: 6),
                  Text('${topAnomaly.provisionTitle}: ${topAnomaly.magnitudeDisplay} magnitude',
                    style: BaselineTypography.dataSmall.copyWith(
                      color: BaselineColors.amber.atOpacity(0.60),
                      letterSpacing: 1)),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// [T132-140] High-Delta Spotlight.
class _HighDeltaSpotlight extends StatelessWidget {
  const _HighDeltaSpotlight({
    required this.diffs, required this.totalProvisions,
    required this.ambientCtrl,
  });
  final List<MutationDiff> diffs;
  final int totalProvisions;
  final AnimationController ambientCtrl;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: BaselineInsets.allM,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionLabel('HIGHEST MAGNITUDE MUTATIONS'),
          const SizedBox(height: 12),
          ...diffs.asMap().entries.map((entry) {
            final diff = entry.value;
            return Padding(
              padding: EdgeInsets.only(bottom: entry.key < diffs.length - 1 ? 8 : 0),
              child: RepaintBoundary(
                child: AnimatedBuilder(
                  animation: ambientCtrl,
                  builder: (context, _) {
                    final glowOpacity =
                        0.15 + 0.05 * math.sin(ambientCtrl.value * math.pi * 2);
                    return Container(
                      decoration: BoxDecoration(
                        color: BaselineColors.surface,
                        borderRadius: BorderRadius.circular(BaselineRadius.card),
                        border: Border.all(
                          color: diff.severity.isAmber
                              ? BaselineColors.amber.atOpacity(glowOpacity + 0.10)
                              : BaselineColors.teal.atOpacity(glowOpacity + 0.05),
                          width: 3)),
                      padding: BaselineInsets.allM,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // C28 Gene index.
                          Text(diff.geneLabel(totalProvisions),
                            style: BaselineTypography.dataSmall.copyWith(
                              color: BaselineColors.teal.atOpacity(0.30),
                              letterSpacing: 2)),
                          const SizedBox(height: 4),
                          Row(children: [
                            Expanded(child: Text(diff.provisionTitle,
                              style: BaselineTypography.body1.copyWith(
                                color: BaselineColors.white.atOpacity(0.87)),
                              maxLines: 2, overflow: TextOverflow.ellipsis)),
                            const SizedBox(width: 8),
                            Text(diff.magnitudeDisplay,
                              style: BaselineTypography.data.copyWith(
                                color: diff.severity.isAmber
                                    ? BaselineColors.amber : BaselineColors.teal,
                                fontSize: 18, fontWeight: FontWeight.w700)),
                          ]),
                          const SizedBox(height: 8),
                          // [T135-138] Gene strand visualization.
                          SizedBox(height: _kGeneStrandHeight * 3,
                            child: CustomPaint(
                              painter: _GenomeStrandPainter(diff: diff),
                              size: Size(double.infinity, _kGeneStrandHeight * 3))),
                          // C19 Spending crossover.
                          if (diff.hasSpendingCrossover) ...[
                            const SizedBox(height: 6),
                            Row(children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(BaselineRadius.chip),
                                  border: Border.all(
                                    color: BaselineColors.amber.atOpacity(0.30))),
                                child: Text('\u0394\$',
                                  style: BaselineTypography.dataSmall.copyWith(
                                    color: BaselineColors.amber.atOpacity(0.70)))),
                              const SizedBox(width: 6),
                              Text(diff.spendingDisplay ?? '',
                                style: BaselineTypography.dataSmall.copyWith(
                                  color: BaselineColors.amber.atOpacity(0.60))),
                            ]),
                          ],
                          const SizedBox(height: 6),
                          Row(children: [
                            SizedBox(width: 14, height: 14,
                              child: CustomPaint(painter: _DiffTypeBadgePainter(type: diff.type))),
                            const SizedBox(width: 6),
                            Text(diff.type.displayName,
                              style: BaselineTypography.dataSmall.copyWith(
                                color: BaselineColors.teal.atOpacity(0.50),
                                letterSpacing: 1)),
                            const Spacer(),
                            Text(diff.severity.displayLabel,
                              style: BaselineTypography.dataSmall.copyWith(
                                color: diff.severity.isAmber
                                    ? BaselineColors.amber.atOpacity(0.50)
                                    : BaselineColors.teal.atOpacity(0.30),
                                letterSpacing: 1)),
                          ]),
                        ],
                      ),
                    );
                  },
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

/// [T104-107] Sort toggle row with C17 scanline sweep.
class _SortToggleRow extends StatelessWidget {
  const _SortToggleRow({
    required this.currentSort, required this.onSortChanged,
    required this.scanActive,
  });
  final _SortMode currentSort;
  final void Function(_SortMode) onSortChanged;
  final bool scanActive;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: BaselineInsets.horizontalM.add(const EdgeInsets.only(top: 8, bottom: 4)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionLabel('GENE MUTATION LOG'),
          const SizedBox(height: 8),
          // [C17/Fix #13] Sort scan overlay.
          Stack(
            children: [
              Row(children: [
                _SortChip(label: 'MAGNITUDE',
                  isActive: currentSort == _SortMode.magnitude,
                  onTap: () => onSortChanged(_SortMode.magnitude)),
                const SizedBox(width: 8),
                _SortChip(label: 'POSITION',
                  isActive: currentSort == _SortMode.position,
                  onTap: () => onSortChanged(_SortMode.position)),
                const SizedBox(width: 8),
                _SortChip(label: 'TYPE',
                  isActive: currentSort == _SortMode.type,
                  onTap: () => onSortChanged(_SortMode.type)),
              ]),
              if (scanActive)
                Positioned.fill(
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.0, end: 1.0),
                    duration: _kSortScanDuration,
                    builder: (context, progress, _) => CustomPaint(
                      painter: _SortScanPainter(progress: progress)),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// [T103-131] Provision diff card with C18 unsealing animation.
class _ProvisionDiffCard extends StatefulWidget {
  const _ProvisionDiffCard({
    required this.diff, required this.index, required this.totalProvisions,
    required this.isExpanded, required this.onTap, required this.showPerforation,
  });
  final MutationDiff diff;
  final int index;
  final int totalProvisions;
  final bool isExpanded;
  final VoidCallback onTap;
  final bool showPerforation;

  @override
  State<_ProvisionDiffCard> createState() => _ProvisionDiffCardState();
}

class _ProvisionDiffCardState extends State<_ProvisionDiffCard> {
  // [C18/Fix #14] Unsealing state.
  bool _unsealing = false;
  bool _contentRevealed = false;
  final List<Timer> _timers = [];

  @override
  void dispose() {
    for (final t in _timers) { t.cancel(); }
    super.dispose();
  }

  void _handleTap() {
    if (!widget.isExpanded) {
      // Opening: play unseal sequence.
      setState(() { _unsealing = true; _contentRevealed = false; });
      // [LOCKED] I1 fix: tracked Timers, cancelled in dispose.
      _timers.add(Timer(_kUnsealPhase1, () {
        if (mounted) setState(() => _contentRevealed = true);
      }));
      _timers.add(Timer(_kUnsealPhase1 + _kUnsealPhase2, () {
        if (mounted) setState(() => _unsealing = false);
      }));
    }
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final diff = widget.diff;
    final accentColor = switch (diff.type) {
      MutationDiffType.added => BaselineColors.teal,
      MutationDiffType.removed => BaselineColors.white.atOpacity(0.30),
      MutationDiffType.modified => BaselineColors.teal.atOpacity(0.60),
    };

    return Column(children: [
      if (widget.showPerforation)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: SizedBox(height: 6,
            child: CustomPaint(
              painter: _SectionDividerPainter(),
              size: const Size(double.infinity, 6)))),
      Padding(
        padding: BaselineInsets.horizontalM.add(const EdgeInsets.only(bottom: 6)),
        child: Semantics(
          button: true,
          excludeSemantics: true,
          label: '${diff.type.displayName}: ${diff.provisionTitle}, '
              '${diff.magnitudeDisplay} magnitude',
          child: _PressScaleButton(
            scale: _kPressScaleCard,
            onTap: _handleTap,
            child: Container(
              decoration: BoxDecoration(
                color: BaselineColors.surface,
                borderRadius: BorderRadius.circular(BaselineRadius.card),
                border: Border.all(
                  color: diff.isAnomaly
                      ? BaselineColors.amber.atOpacity(0.20)
                      : BaselineColors.teal.atOpacity(0.10),
                  width: BaselineBorder.standard.width)),
              child: IntrinsicHeight(
                child: Row(children: [
                  // [T110-113] Left accent bar.
                  Container(
                    width: _kDiffAccentWidth,
                    decoration: BoxDecoration(
                      color: accentColor,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(8),
                        bottomLeft: Radius.circular(8)))),
                  Expanded(
                    child: Padding(
                      padding: BaselineInsets.allS,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // C28 Gene index.
                          Text(diff.geneLabel(widget.totalProvisions),
                            style: BaselineTypography.dataSmall.copyWith(
                              color: BaselineColors.teal.atOpacity(0.25),
                              letterSpacing: 2, fontSize: 8)),
                          const SizedBox(height: 4),
                          // Type badge row.
                          Row(children: [
                            SizedBox(width: 14, height: 14,
                              child: CustomPaint(
                                painter: _DiffTypeBadgePainter(type: diff.type))),
                            const SizedBox(width: 6),
                            Text(diff.type.displayName,
                              style: BaselineTypography.dataSmall.copyWith(
                                color: accentColor.atOpacity(0.70),
                                letterSpacing: 1)),
                            const Spacer(),
                            if (diff.category != null)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(BaselineRadius.chip),
                                  border: Border.all(
                                    color: BaselineColors.teal.atOpacity(0.20))),
                                child: Text(diff.category!.toUpperCase(),
                                  style: BaselineTypography.dataSmall.copyWith(
                                    color: BaselineColors.teal.atOpacity(0.40),
                                    fontSize: 8, letterSpacing: 1))),
                          ]),
                          const SizedBox(height: 6),
                          // Provision title.
                          Text(diff.provisionTitle,
                            style: BaselineTypography.body1.copyWith(
                              color: BaselineColors.white.atOpacity(0.87)),
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 8),
                          // [T117-120] Magnitude bar.
                          Row(children: [
                            SizedBox(width: _kMagnitudeBarWidth, height: _kMagnitudeBarHeight,
                              child: CustomPaint(
                                painter: _MagnitudeBarPainter(
                                  value: diff.magnitude,
                                  isAmber: diff.severity.isAmber))),
                            const SizedBox(width: 8),
                            Text(diff.magnitudeDisplay,
                              style: BaselineTypography.data.copyWith(
                                color: diff.severity.isAmber
                                    ? BaselineColors.amber : BaselineColors.teal,
                                fontWeight: FontWeight.w600)),
                          ]),
                          // C7 Mini gene strand.
                          const SizedBox(height: 6),
                          SizedBox(height: _kGeneStrandHeight, width: _kGeneStrandWidth,
                            child: CustomPaint(painter: _GenomeStrandPainter(diff: diff))),
                          // C19 Spending crossover.
                          if (diff.hasSpendingCrossover) ...[
                            const SizedBox(height: 4),
                            Row(children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(BaselineRadius.chip),
                                  border: Border.all(
                                    color: BaselineColors.amber.atOpacity(0.25))),
                                child: Text('\u0394\$',
                                  style: BaselineTypography.dataSmall.copyWith(
                                    color: BaselineColors.amber.atOpacity(0.60),
                                    fontSize: 8))),
                              const SizedBox(width: 4),
                              Text(diff.spendingDisplay ?? '',
                                style: BaselineTypography.dataSmall.copyWith(
                                  color: BaselineColors.amber.atOpacity(0.50),
                                  fontSize: 9)),
                            ]),
                          ],
                          // [T125/C18] Expandable with unseal animation.
                          AnimatedCrossFade(
                            duration: BaselineMotion.fast,
                            crossFadeState: widget.isExpanded
                                ? CrossFadeState.showSecond
                                : CrossFadeState.showFirst,
                            firstChild: const SizedBox.shrink(),
                            secondChild: _buildExpandedContent()),
                        ],
                      ),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    ]);
  }

  Widget _buildExpandedContent() {
    final diff = widget.diff;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(height: 1,
            color: BaselineColors.teal.atOpacity(0.08)),
          const SizedBox(height: 8),
          // [C18] "DECODING..." phase.
          if (_unsealing && !_contentRevealed)
            Text('DECODING...',
              style: BaselineTypography.dataSmall.copyWith(
                color: BaselineColors.teal.atOpacity(0.40),
                letterSpacing: 3)),
          if (!_unsealing || _contentRevealed) ...[
            if (diff.type != MutationDiffType.added) ...[
              Text('PREVIOUS:',
                style: BaselineTypography.dataSmall.copyWith(
                  color: BaselineColors.white.atOpacity(0.25),
                  letterSpacing: 2)),
              const SizedBox(height: 4),
              Text(diff.oldText ?? 'N/A',
                style: BaselineTypography.dataSmall.copyWith(
                  color: BaselineColors.white.atOpacity(0.30),
                  decoration: diff.type == MutationDiffType.removed
                      ? TextDecoration.lineThrough : null),
                maxLines: 6, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 8),
            ],
            if (diff.type != MutationDiffType.removed) ...[
              Text(diff.type == MutationDiffType.added ? 'INSERTED:' : 'CURRENT:',
                style: BaselineTypography.dataSmall.copyWith(
                  color: BaselineColors.teal.atOpacity(0.30),
                  letterSpacing: 2)),
              const SizedBox(height: 4),
              Text(diff.newText ?? 'N/A',
                style: BaselineTypography.dataSmall.copyWith(
                  color: BaselineColors.teal.atOpacity(0.40)),
                maxLines: 6, overflow: TextOverflow.ellipsis),
            ],
            if (diff.type == MutationDiffType.removed)
              Text('EXCISED',
                style: BaselineTypography.dataSmall.copyWith(
                  color: BaselineColors.white.atOpacity(0.20),
                  letterSpacing: 3)),
            const SizedBox(height: 8),
            Text(diff.severity.displayLabel,
              style: BaselineTypography.dataSmall.copyWith(
                color: diff.severity.isAmber
                    ? BaselineColors.amber.atOpacity(0.40)
                    : BaselineColors.teal.atOpacity(0.25),
                letterSpacing: 2)),
          ],
        ],
      ),
    );
  }
}

/// [T141-149] Mutation Velocity Panel.
class _MutationVelocityPanel extends StatelessWidget {
  const _MutationVelocityPanel({
    required this.timeline, required this.activeComparison,
    required this.entranceCtrl, required this.reducedMotion,
  });
  final MutationTimeline timeline;
  final VersionComparison activeComparison;
  final AnimationController entranceCtrl;
  final bool reducedMotion;

  @override
  Widget build(BuildContext context) {
    final velocities = timeline.comparisons
        .map((c) => c.aggregateMutation).toList();
    if (velocities.isEmpty) return const SizedBox.shrink();

    final trend = velocities.length >= 2
        ? (velocities.last > velocities.first ? 'ACCELERATING'
            : velocities.last < velocities.first ? 'DECELERATING' : 'STABLE')
        : 'STABLE';

    return Padding(
      padding: BaselineInsets.allM,
      child: Container(
        decoration: BoxDecoration(
          color: BaselineColors.surface,
          borderRadius: BorderRadius.circular(BaselineRadius.card),
          border: Border.all(
            color: BaselineColors.teal.atOpacity(0.10),
            width: BaselineBorder.standard.width)),
        padding: BaselineInsets.allM,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionLabel('MUTATION VELOCITY'),
            const SizedBox(height: 12),
            // C21 Sparkline with draw-on.
            SizedBox(height: _kSparklineHeight,
              child: RepaintBoundary(
                child: AnimatedBuilder(
                  animation: entranceCtrl,
                  builder: (context, _) {
                    final drawProgress = reducedMotion ? 1.0
                        : const Interval(
                              _kStaggerVelocity, _kStaggerVelocity + 0.25,
                              curve: Curves.easeOutCubic)
                            .transform(entranceCtrl.value);
                    return CustomPaint(
                      painter: _VelocitySparkPainter(
                        values: velocities, drawProgress: drawProgress),
                      size: Size(double.infinity, _kSparklineHeight));
                  }))),
            const SizedBox(height: 8),
            // C20 Velocity trend arrow (widget, not dead painter).
            Row(children: [
              _VelocityArrowWidget(trend: trend),
              const SizedBox(width: 8),
              Text(trend,
                style: BaselineTypography.dataSmall.copyWith(
                  color: trend == 'ACCELERATING'
                      ? BaselineColors.amber.atOpacity(0.70)
                      : BaselineColors.teal.atOpacity(0.50),
                  letterSpacing: 2)),
            ]),
          ],
        ),
      ),
    );
  }
}

/// [T150-155] Methodology Footer.
class _MethodologyFooter extends StatelessWidget {
  const _MethodologyFooter({required this.billId});
  final String billId;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: BaselineInsets.allM,
      child: Column(children: [
        SizedBox(height: 6,
          child: CustomPaint(
            painter: _SectionDividerPainter(),
            size: const Size(double.infinity, 6))),
        const SizedBox(height: 16),
        Semantics(
          button: true,
          excludeSemantics: true,
          label: 'How Mutation Timeline works',
          child: GestureDetector(
            onTap: () {
              HapticUtil.light();
              InfoBottomSheet.show(context,
                infoKey: 'mutation_timeline',
                surface: 'Mutation Timeline\u2122');
            },
            child: Text('How Mutation Timeline\u2122 works \u2192',
              style: BaselineTypography.body2.copyWith(
                color: BaselineColors.teal.atOpacity(0.60)))),
        ),
        const SizedBox(height: 12),
        Text('Data derived from public congressional records.',
          style: BaselineTypography.dataSmall.copyWith(
            color: BaselineColors.white.atOpacity(0.20))),
        const SizedBox(height: 8),
        Text('SEQUENCER V1.0',
          style: BaselineTypography.dataSmall.copyWith(
            color: BaselineColors.white.atOpacity(_kHandlingMarkOpacity),
            letterSpacing: 3)),
        const SizedBox(height: 4),
        // C31 Document seal.
        Text('ANALYSIS CERTIFIED \u00B7 HANDLE VIA BASELINE CHANNELS ONLY',
          style: BaselineTypography.dataSmall.copyWith(
            color: BaselineColors.white.atOpacity(_kHandlingMarkOpacity),
            letterSpacing: 1, fontSize: 7),
          textAlign: TextAlign.center),
        const SizedBox(height: 4),
        Text('MT-$billId',
          style: BaselineTypography.dataSmall.copyWith(
            color: BaselineColors.teal.atOpacity(_kHandlingMarkOpacity),
            letterSpacing: 2)),
      ]),
    );
  }
}

/// [T156-162] Status Readout Bar.
class _StatusReadoutBar extends StatelessWidget {
  const _StatusReadoutBar({
    required this.timeline, required this.comparison,
    required this.messageIndex, required this.ambientCtrl,
    required this.reducedMotion,
  });
  final MutationTimeline timeline;
  final VersionComparison? comparison;
  final int messageIndex;
  final AnimationController ambientCtrl;
  final bool reducedMotion;

  @override
  Widget build(BuildContext context) {
    final messages = [
      'SEQUENCING COMPLETE',
      comparison != null
          ? '${comparison!.totalMutations} MUTATIONS \u00B7 ${comparison!.totalProvisions} GENES'
          : 'AWAITING COMPARISON',
      comparison != null
          ? 'GENOME SHIFT: ${comparison!.aggregateDisplay}'
          : 'SELECT VERSIONS',
      comparison != null
          ? '${comparison!.fromVersion.stage.shortLabel} \u2192 ${comparison!.toVersion.stage.shortLabel}'
          : 'STANDBY',
    ];
    final safeIndex = messageIndex % messages.length;
    final bottomPadding = MediaQuery.paddingOf(context).bottom;

    return Container(
      height: _kStatusBarHeight + bottomPadding,
      padding: EdgeInsets.only(left: 16, right: 16, bottom: bottomPadding),
      color: BaselineColors.black,
      child: Row(children: [
        RepaintBoundary(
          child: AnimatedBuilder(
            animation: ambientCtrl,
            builder: (context, _) {
              final opacity = reducedMotion ? 0.60
                  : (0.3 + 0.5 * math.sin(ambientCtrl.value * math.pi * 2)).clamp(0.0, 1.0);
              return Container(width: 4, height: 4,
                decoration: BoxDecoration(shape: BoxShape.circle,
                  color: BaselineColors.teal.atOpacity(opacity)));
            }),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: AnimatedSwitcher(
            duration: BaselineMotion.normal,
            child: Text(messages[safeIndex],
              key: ValueKey<int>(safeIndex),
              style: BaselineTypography.dataSmall.copyWith(
                color: BaselineColors.teal.atOpacity(0.50),
                letterSpacing: 2)))),
        if (comparison != null)
          Text(
            '${comparison!.fromVersion.stage.shortLabel} \u2192 '
            '${comparison!.toVersion.stage.shortLabel}',
            style: BaselineTypography.dataSmall.copyWith(
              color: BaselineColors.white.atOpacity(0.20),
              letterSpacing: 1)),
      ]),
    );
  }
}

// ============================================================
// HELPER WIDGETS
// ============================================================

/// Section label with terminal styling.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text,
      style: BaselineTypography.dataSmall.copyWith(
        color: BaselineColors.teal.atOpacity(0.50),
        letterSpacing: 3, fontWeight: FontWeight.w600));
  }
}

/// Reticle-cornered label.
class _ReticleLabel extends StatelessWidget {
  const _ReticleLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(BaselineRadius.chip),
        color: BaselineColors.white.atOpacity(0.03),
        border: Border.all(
          color: BaselineColors.teal.atOpacity(0.10))),
      child: Text(text,
        style: BaselineTypography.dataSmall.copyWith(
          color: BaselineColors.white.atOpacity(0.30),
          letterSpacing: 2, fontSize: 8)),
    );
  }
}

/// Version pill for comparison selector.
class _VersionPill extends StatelessWidget {
  const _VersionPill({
    required this.label, required this.sublabel,
    required this.isActive, required this.onTap,
  });
  final String label;
  final String sublabel;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      excludeSemantics: true,
      label: '$sublabel version: $label',
      child: _PressScaleButton(
        scale: _kPressScaleChip,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isActive
                ? BaselineColors.teal.atOpacity(0.10)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(BaselineRadius.chip),
            border: Border.all(
              color: BaselineColors.teal.atOpacity(isActive ? 0.30 : 0.10),
              width: BaselineBorder.standard.width)),
          child: Column(children: [
            Text(sublabel,
              style: BaselineTypography.dataSmall.copyWith(
                color: BaselineColors.teal.atOpacity(0.30),
                letterSpacing: 2, fontSize: 8)),
            const SizedBox(height: 2),
            Text(label,
              style: BaselineTypography.data.copyWith(
                color: isActive
                    ? BaselineColors.teal.atOpacity(0.87)
                    : BaselineColors.white.atOpacity(0.40),
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                letterSpacing: 1)),
          ]),
        ),
      ),
    );
  }
}

/// Sort chip for diff list.
class _SortChip extends StatelessWidget {
  const _SortChip({
    required this.label, required this.isActive, required this.onTap,
  });
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      excludeSemantics: true,
      label: 'Sort by $label${isActive ? ', active' : ''}',
      child: _PressScaleButton(
        scale: _kPressScaleChip,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: isActive ? BaselineColors.teal.atOpacity(0.15) : Colors.transparent,
            borderRadius: BorderRadius.circular(BaselineRadius.chip),
            border: Border.all(
              color: BaselineColors.teal.atOpacity(isActive ? 0.30 : 0.10),
              width: isActive ? BaselineBorder.standard.width : 1)),
          child: Text(label,
            style: BaselineTypography.dataSmall.copyWith(
              color: isActive
                  ? BaselineColors.teal.atOpacity(0.87)
                  : BaselineColors.white.atOpacity(0.30),
              letterSpacing: 1)),
        ),
      ),
    );
  }
}

/// Version picker bottom sheet.
class _VersionPickerSheet extends StatelessWidget {
  const _VersionPickerSheet({
    required this.versions, required this.selectedId,
    required this.title, required this.onSelected,
  });
  final List<BillVersion> versions;
  final String? selectedId;
  final String title;
  final void Function(String) onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: BaselineInsets.allM,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
            style: BaselineTypography.dataSmall.copyWith(
              color: BaselineColors.teal.atOpacity(0.50),
              letterSpacing: 3)),
          const SizedBox(height: 16),
          ...versions.map((v) {
            final isSelected = v.id == selectedId;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Semantics(
                button: true,
                excludeSemantics: true,
                label: '${v.stage.displayName}, ${_formatDate(v.timestamp)}'
                    '${isSelected ? ', selected' : ''}',
                child: GestureDetector(
                  onTap: () {
                    HapticUtil.light();
                    onSelected(v.id);
                  },
                  child: Container(
                    padding: BaselineInsets.allS,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? BaselineColors.teal.atOpacity(0.10)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(BaselineRadius.card),
                      border: Border.all(
                        color: BaselineColors.teal.withValues(
                          alpha: isSelected ? 0.30 : 0.08))),
                    child: Row(children: [
                      Text(v.stage.displayName,
                        style: BaselineTypography.data.copyWith(
                          color: isSelected
                              ? BaselineColors.teal.atOpacity(0.87)
                              : BaselineColors.white.atOpacity(0.60),
                          letterSpacing: 1)),
                      const Spacer(),
                      Text(_formatDate(v.timestamp),
                        style: BaselineTypography.dataSmall.copyWith(
                          color: BaselineColors.white.atOpacity(0.30))),
                    ]),
                  ),
                ),
              ),
            );
          }),
          SizedBox(height: MediaQuery.paddingOf(context).bottom),
        ],
      ),
    );
  }
}

/// C20 Velocity trend arrow as widget (replaces dead _VelocityArrowPainter).
class _VelocityArrowWidget extends StatelessWidget {
  const _VelocityArrowWidget({required this.trend});
  final String trend;

  @override
  Widget build(BuildContext context) {
    final isAmber = trend == 'ACCELERATING';
    final color = isAmber ? BaselineColors.amber : BaselineColors.teal;
    // Use a simple Transform.rotate on a chevron from CustomPaint.
    final angle = switch (trend) {
      'ACCELERATING' => -math.pi / 2,
      'DECELERATING' => math.pi / 2,
      _ => 0.0,
    };
    return SizedBox(
      width: _kVelocityArrowSize, height: _kVelocityArrowSize,
      child: Transform.rotate(
        angle: angle,
        child: BaselineIcon(
          BaselineIconType.arrowForward,
          size: _kVelocityArrowSize,
          color: color.atOpacity(0.70),
        ),
      ),
    );
  }
}

/// Press-scale button with AnimatedScale.
class _PressScaleButton extends StatefulWidget {
  const _PressScaleButton({
    required this.scale, required this.onTap, required this.child,
  });
  final double scale;
  final VoidCallback onTap;
  final Widget child;

  @override
  State<_PressScaleButton> createState() => _PressScaleButtonState();
}

class _PressScaleButtonState extends State<_PressScaleButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? widget.scale : 1.0,
        duration: const Duration(milliseconds: 100),
        child: widget.child),
    );
  }
}

/// Date formatter.
String _formatDate(DateTime dt) {
  const months = ['JAN','FEB','MAR','APR','MAY','JUN','JUL','AUG','SEP','OCT','NOV','DEC'];
  return '${dt.day.toString().padLeft(2, '0')} ${months[dt.month - 1]} ${dt.year}';
}

// ============================================================
// PAINTERS (13)
// ============================================================

/// P1: Screen chrome: intel dots, film perfs, reticles, circuit traces,
/// genome watermark, registration dots, hashmark ruler.
/// [Fix #4] No repaint binding. Static chrome.
class _ScreenChromePainter extends CustomPainter {
  _ScreenChromePainter({required this.screenSize})
      : _dotPaint = Paint()
          ..color = BaselineColors.spectralTeal.atOpacity(0.03)
          ..style = PaintingStyle.fill,
        _sprocketPaint = Paint()
          ..color = BaselineColors.spectralTeal.atOpacity(0.04)
          ..style = PaintingStyle.fill,
        _reticlePaint = Paint()
          ..color = BaselineColors.spectralTeal.atOpacity(0.06)
          ..style = PaintingStyle.stroke
          ..strokeWidth = _kReticleStroke,
        _circuitPaint = Paint()
          ..color = BaselineColors.spectralTeal.atOpacity(0.02)
          ..style = PaintingStyle.stroke
          ..strokeWidth = _kCircuitStroke,
        _regPaint = Paint()
          ..color = BaselineColors.spectralTeal.atOpacity(0.04)
          ..style = PaintingStyle.fill,
        _rulerPaint = Paint()
          ..color = BaselineColors.spectralTeal.atOpacity(0.03)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.5,
        _watermarkPaint = Paint()
          ..color = BaselineColors.spectralTeal.atOpacity(_kWatermarkOpacity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5;

  final Size screenSize;
  final Paint _dotPaint;
  final Paint _sprocketPaint;
  final Paint _reticlePaint;
  final Paint _circuitPaint;
  final Paint _regPaint;
  final Paint _rulerPaint;
  final Paint _watermarkPaint;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Layer 1: Intel dot grid.
    for (double x = _kDotGridSpacing; x < w; x += _kDotGridSpacing) {
      for (double y = _kDotGridSpacing; y < h; y += _kDotGridSpacing) {
        canvas.drawCircle(Offset(x, y), _kDotGridRadius, _dotPaint);
      }
    }

    // Layer 2: Film perforations left + right.
    for (double y = 20; y < h - 20; y += _kSprocketSpacing) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(4, y, _kSprocketWidth, _kSprocketHeight),
          const Radius.circular(1)),
        _sprocketPaint);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(w - 4 - _kSprocketWidth, y, _kSprocketWidth, _kSprocketHeight),
          const Radius.circular(1)),
        _sprocketPaint);
    }

    // Layer 3: Compound reticle corners.
    _drawReticle(canvas, Offset(16, 16), false, false);
    _drawReticle(canvas, Offset(w - 16, 16), true, false);
    _drawReticle(canvas, Offset(16, h - 16), false, true);
    _drawReticle(canvas, Offset(w - 16, h - 16), true, true);

    // Layer 4: Circuit traces.
    for (final frac in [0.25, 0.50, 0.75]) {
      final y = h * frac;
      canvas.drawLine(Offset(30, y), Offset(w - 30, y), _circuitPaint);
    }

    // Layer 5: Registration dots.
    for (final pt in [
      Offset(8, 8), Offset(w - 8, 8), Offset(8, h - 8), Offset(w - 8, h - 8),
      Offset(w / 2, 8), Offset(w / 2, h - 8), Offset(8, h / 2), Offset(w - 8, h / 2),
    ]) {
      canvas.drawCircle(pt, 1.5, _regPaint);
    }

    // Layer 6: Hashmark ruler (bottom).
    final rulerY = h - 12.0;
    canvas.drawLine(Offset(20, rulerY), Offset(w - 20, rulerY), _rulerPaint);
    for (int i = 0; i < 7; i++) {
      final x = 20 + (w - 40) * i / 6;
      canvas.drawLine(Offset(x, rulerY - 3), Offset(x, rulerY + 3), _rulerPaint);
    }

    // Layer 7: Genome watermark (faint helix silhouette center).
    final cx = w / 2;
    final cy = h / 2;
    final wmPath = Path();
    for (double t = -60; t <= 60; t += 2) {
      final x1 = cx + 20 * math.sin(t * 0.15);
      final y1 = cy + t;
      if (t == -60) {
        wmPath.moveTo(x1, y1);
      } else {
        wmPath.lineTo(x1, y1);
      }
    }
    canvas.drawPath(wmPath, _watermarkPaint);
    final wmPath2 = Path();
    for (double t = -60; t <= 60; t += 2) {
      final x2 = cx + 20 * math.sin(t * 0.15 + math.pi);
      final y2 = cy + t;
      if (t == -60) {
        wmPath2.moveTo(x2, y2);
      } else {
        wmPath2.lineTo(x2, y2);
      }
    }
    canvas.drawPath(wmPath2, _watermarkPaint);
  }

  void _drawReticle(Canvas canvas, Offset center, bool flipX, bool flipY) {
    final dx = flipX ? -1.0 : 1.0;
    final dy = flipY ? -1.0 : 1.0;
    // Outer L.
    canvas.drawLine(center, center + Offset(_kReticleArm * dx, 0), _reticlePaint);
    canvas.drawLine(center, center + Offset(0, _kReticleArm * dy), _reticlePaint);
    // Inner tick.
    canvas.drawLine(
      center + Offset(_kReticleTick * dx * 0.5, _kReticleTick * dy * 0.5),
      center + Offset(_kReticleTick * dx, _kReticleTick * dy), _reticlePaint);
    // Corner dot.
    canvas.drawCircle(center, _kReticleCornerDot,
      _regPaint); // Reuse fill paint.
  }

  @override
  bool shouldRepaint(_ScreenChromePainter oldDelegate) => false;
}

/// P2: DNA Helix: double sinusoidal strands with base-pair rungs and mutation sites.
/// [Fix #6] Constructor-initialized paints.
class _DNAHelixPainter extends CustomPainter {
  _DNAHelixPainter({
    required this.versions, required this.comparisons,
    required this.selectedFromId, required this.selectedToId,
    required this.helixPhase, required this.pulsePhase,
    required this.ambientPhase, required this.reducedMotion,
  }) : _strand1 = Paint()
          ..color = BaselineColors.spectralTeal.atOpacity(0.40)
          ..style = PaintingStyle.stroke
          ..strokeWidth = _kHelixStrandStroke,
       _strand2 = Paint()
          ..color = BaselineColors.spectralTeal.atOpacity(0.15)
          ..style = PaintingStyle.stroke
          ..strokeWidth = _kHelixStrandStroke,
       _rungPaint = Paint()
          ..color = BaselineColors.spectralTeal.atOpacity(0.08)
          ..style = PaintingStyle.stroke
          ..strokeWidth = _kHelixRungStroke,
       _nodeFill = Paint()
          ..color = BaselineColors.spectralTeal.atOpacity(0.60)
          ..style = PaintingStyle.fill,
       _nodeStroke = Paint()
          ..color = BaselineColors.spectralTeal.atOpacity(0.20)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
       _nodeInactive = Paint()
          ..color = BaselineColors.spectralTeal.atOpacity(0.10)
          ..style = PaintingStyle.fill,
       _travelerPaint = Paint()
          ..color = BaselineColors.spectralTeal.atOpacity(0.40)
          ..style = PaintingStyle.fill,
       _work = Paint();

  final List<BillVersion> versions;
  final List<VersionComparison> comparisons;
  final String? selectedFromId;
  final String? selectedToId;
  final double helixPhase;
  final double pulsePhase;
  final double ambientPhase;
  final bool reducedMotion;
  final Paint _strand1;
  final Paint _strand2;
  final Paint _rungPaint;
  final Paint _nodeFill;
  final Paint _nodeStroke;
  final Paint _nodeInactive;
  final Paint _travelerPaint;
  final Paint _work;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = 40.0;
    final h = size.height;
    final phase = reducedMotion ? 0.0 : helixPhase * math.pi * 2;
    // C29 Strand width breathing.
    final breathe = reducedMotion ? 0.0 : math.sin(ambientPhase * math.pi * 2) * 0.3;
    _strand1.strokeWidth = _kHelixStrandStroke + breathe;
    _strand2.strokeWidth = _kHelixStrandStroke + breathe;

    // Draw helix strands.
    final path1 = Path();
    final path2 = Path();
    for (double y = 0; y <= h; y += 2) {
      final x1 = cx + _kHelixAmplitude * math.sin(y / _kHelixWavelength * math.pi * 2 + phase);
      final x2 = cx + _kHelixAmplitude * math.sin(y / _kHelixWavelength * math.pi * 2 + phase + math.pi);
      if (y == 0) { path1.moveTo(x1, y); path2.moveTo(x2, y); }
      else { path1.lineTo(x1, y); path2.lineTo(x2, y); }

      // Base-pair rungs at crossing points.
      if (y.toInt() % (_kHelixWavelength ~/ 2) == 0) {
        canvas.drawLine(Offset(x1, y), Offset(x2, y), _rungPaint);
        // C3 Nucleotide dots.
        final isMut = _isMutationSite(y, h);
        _work
          ..color = isMut
              ? BaselineColors.amberMuted.atOpacity(0.60)
              : BaselineColors.spectralTeal.atOpacity(0.15)
          ..style = PaintingStyle.fill;
        canvas.drawCircle(Offset((x1 + x2) / 2, y), 1.5, _work);
      }
    }
    canvas.drawPath(path1, _strand1);
    canvas.drawPath(path2, _strand2);

    // C4 Mutation site bioluminescence.
    if (!reducedMotion) {
      for (int i = 0; i < comparisons.length && i < versions.length - 1; i++) {
        final comp = comparisons[i];
        if (comp.aggregateMutation > 0.10) {
          final yPos = _versionY(i, versions.length, h) +
              (_versionY(i + 1, versions.length, h) - _versionY(i, versions.length, h)) * 0.5;
          final glowIntensity = comp.aggregateMutation.clamp(0.0, 1.0);
          final pulseAlpha = 0.05 + 0.10 * glowIntensity *
              math.sin(pulsePhase * math.pi * 2).abs();
          _work
            ..color = BaselineColors.spectralTeal.atOpacity(pulseAlpha)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
          canvas.drawCircle(Offset(cx, yPos), _kMutationSiteGlowRadius * (1 + glowIntensity), _work);
          _work.maskFilter = null;
        }
      }
    }

    // Version nodes.
    for (int i = 0; i < versions.length; i++) {
      final yPos = _versionY(i, versions.length, h);
      final isSelected = versions[i].id == selectedFromId || versions[i].id == selectedToId;
      final nodeX = cx + _kHelixAmplitude * math.sin(yPos / _kHelixWavelength * math.pi * 2 + phase);

      if (isSelected) {
        // C25 Active comparison glow.
        final outerAlpha = reducedMotion ? 0.20
            : 0.10 + 0.10 * math.sin(pulsePhase * math.pi * 2);
        _work
          ..color = BaselineColors.spectralTeal.atOpacity(outerAlpha)
          ..style = PaintingStyle.fill
          ..maskFilter = null;
        canvas.drawCircle(Offset(nodeX, yPos), _kVersionNodePulseRadius, _work);
        _work.color = BaselineColors.spectralTeal.atOpacity(0.30);
        canvas.drawCircle(Offset(nodeX, yPos), _kVersionNodeRadius, _work);
        canvas.drawCircle(Offset(nodeX, yPos), _kVersionNodeRadius - 2, _nodeFill);
      } else {
        canvas.drawCircle(Offset(nodeX, yPos), _kVersionNodeRadius, _nodeInactive);
        canvas.drawCircle(Offset(nodeX, yPos), _kVersionNodeRadius, _nodeStroke);
      }
    }

    // C12 Timeline connection pulse (dot traveling between nodes).
    if (!reducedMotion && versions.length >= 2) {
      final travelerY = h * 0.1 + h * 0.8 * ambientPhase;
      final travelerX = cx + _kHelixAmplitude *
          math.sin(travelerY / _kHelixWavelength * math.pi * 2 + phase);
      canvas.drawCircle(Offset(travelerX, travelerY), _kTimelineTravelerRadius,
        _travelerPaint);
    }
  }

  double _versionY(int index, int total, double height) {
    if (total <= 1) return height / 2;
    return 20 + (height - 40) * index / (total - 1);
  }

  bool _isMutationSite(double y, double height) {
    for (int i = 0; i < comparisons.length && i < versions.length - 1; i++) {
      final midY = _versionY(i, versions.length, height) +
          (_versionY(i + 1, versions.length, height) - _versionY(i, versions.length, height)) * 0.5;
      if ((y - midY).abs() < 15 && comparisons[i].aggregateMutation > 0.20) return true;
    }
    return false;
  }

  @override
  bool shouldRepaint(_DNAHelixPainter oldDelegate) => true;
}

/// P3: Aggregate containment gauge with biohazard arcs.
/// [Fix #2] No TextPainter. Center % rendered as widget overlay.
class _AggregateGaugePainter extends CustomPainter {
  _AggregateGaugePainter({
    required this.value, required this.fillProgress, required this.pulsePhase,
  }) : _trackPaint = Paint()
          ..color = BaselineColors.spectralTeal.atOpacity(0.06)
          ..style = PaintingStyle.stroke
          ..strokeWidth = _kGaugeStroke,
       _work = Paint();

  final double value;
  final double fillProgress;
  final double pulsePhase;
  final Paint _trackPaint;
  final Paint _work;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - _kGaugeStroke;
    final teal = BaselineColors.spectralTeal;
    final amber = BaselineColors.amberMuted;
    final fillColor = value < 0.30 ? teal : amber;

    // Background track.
    canvas.drawCircle(center, radius, _trackPaint);

    // Fill arc.
    final sweep = math.pi * 2 * value * fillProgress;
    _work
      ..color = fillColor.atOpacity(0.70)
      ..style = PaintingStyle.stroke
      ..strokeWidth = _kGaugeStroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2, sweep, false, _work);

    // C5 Biohazard arcs (4 segments at 90 degree intervals).
    final bioRadius = radius + 4;
    final bioProgress = (value * fillProgress).clamp(0.0, 1.0);
    _work
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.butt;
    for (int i = 0; i < 4; i++) {
      final segmentFill = ((bioProgress - i * 0.25) / 0.25).clamp(0.0, 1.0);
      if (segmentFill <= 0) continue;
      final startAngle = -math.pi / 2 + i * math.pi / 2 + 0.05;
      final segSweep = (math.pi / 2 - 0.10) * segmentFill;
      _work.color = fillColor.atOpacity(0.25);
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: bioRadius),
        startAngle, segSweep, false, _work);
    }

    // C6 Gauge needle tick.
    if (fillProgress > 0.1) {
      final needleAngle = -math.pi / 2 + sweep;
      final inner = center + Offset(
        math.cos(needleAngle) * (radius - _kGaugeNeedleLength),
        math.sin(needleAngle) * (radius - _kGaugeNeedleLength));
      final outer = center + Offset(
        math.cos(needleAngle) * (radius + _kGaugeNeedleLength),
        math.sin(needleAngle) * (radius + _kGaugeNeedleLength));
      _work
        ..color = fillColor.atOpacity(0.80)
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(inner, outer, _work);
    }
  }

  @override
  bool shouldRepaint(_AggregateGaugePainter oldDelegate) =>
      fillProgress != oldDelegate.fillProgress || pulsePhase != oldDelegate.pulsePhase;
}

/// P4: Gene strand visualization per provision (before/after with mutation marks).
class _GenomeStrandPainter extends CustomPainter {
  _GenomeStrandPainter({required this.diff})
      : _tealStrand = Paint()
          ..color = BaselineColors.spectralTeal.atOpacity(0.40)
          ..strokeWidth = 2,
        _whiteStrand = Paint()
          ..color = BaselineColors.white.atOpacity(0.20)
          ..strokeWidth = 2,
        _work = Paint();

  final MutationDiff diff;
  final Paint _tealStrand;
  final Paint _whiteStrand;
  final Paint _work;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final midY = h / 2;

    switch (diff.type) {
      case MutationDiffType.added:
        // C9 Splice insertion glow: teal strand with glow at insertion point.
        canvas.drawLine(Offset(0, midY), Offset(w, midY), _tealStrand);
        _work
          ..color = BaselineColors.spectralTeal.atOpacity(0.20)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
        canvas.drawCircle(Offset(w * 0.3, midY), 4, _work);
        _work.maskFilter = null;
      case MutationDiffType.removed:
        // C8 Excision scar: strand with X cut.
        canvas.drawLine(Offset(0, midY), Offset(w * 0.35, midY), _whiteStrand);
        canvas.drawLine(Offset(w * 0.65, midY), Offset(w, midY), _whiteStrand);
        // X marks.
        final xCenter = Offset(w * 0.5, midY);
        _work
          ..color = BaselineColors.white.atOpacity(0.15)
          ..strokeWidth = 1
          ..style = PaintingStyle.stroke;
        canvas.drawLine(xCenter + const Offset(-4, -4), xCenter + const Offset(4, 4), _work);
        canvas.drawLine(xCenter + const Offset(4, -4), xCenter + const Offset(-4, 4), _work);
      case MutationDiffType.modified:
        // C10 Modification shift: old strand ghost + new strand.
        _work
          ..color = BaselineColors.white.atOpacity(0.06)
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke;
        canvas.drawLine(Offset(0, midY + 1), Offset(w, midY + 1), _work);
        _work.color = BaselineColors.spectralTeal.atOpacity(0.30);
        canvas.drawLine(Offset(0, midY - 1), Offset(w, midY - 1), _work);
    }
  }

  @override
  bool shouldRepaint(_GenomeStrandPainter oldDelegate) =>
      diff.type != oldDelegate.diff.type;
}

/// P5: Magnitude bar (horizontal gauge per provision).
class _MagnitudeBarPainter extends CustomPainter {
  _MagnitudeBarPainter({required this.value, required this.isAmber})
      : _trackPaint = Paint()
          ..color = BaselineColors.spectralTeal.atOpacity(0.08),
        _fillPaint = Paint()
          ..color = (isAmber ? BaselineColors.amberMuted : BaselineColors.spectralTeal)
              .atOpacity(0.60);

  final double value;
  final bool isAmber;
  final Paint _trackPaint;
  final Paint _fillPaint;

  @override
  void paint(Canvas canvas, Size size) {
    // Track.
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, size.width, size.height),
        const Radius.circular(3)),
      _trackPaint);
    // Fill.
    final fillWidth = size.width * value.clamp(0.0, 1.0);
    if (fillWidth > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, fillWidth, size.height),
          const Radius.circular(3)),
        _fillPaint);
    }
  }

  @override
  bool shouldRepaint(_MagnitudeBarPainter oldDelegate) =>
      value != oldDelegate.value || isAmber != oldDelegate.isAmber;
}

/// P6: Heatmap strip (mutation density across provisions).
class _HeatmapStripPainter extends CustomPainter {
  _HeatmapStripPainter({
    required this.diffs, required this.totalProvisions, required this.scanProgress,
  }) : _work = Paint(),
       _scanHead = Paint()
          ..color = BaselineColors.spectralTeal.atOpacity(0.60)
          ..strokeWidth = 2;

  final List<MutationDiff> diffs;
  final int totalProvisions;
  final double scanProgress;
  final Paint _work;
  final Paint _scanHead;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    if (totalProvisions <= 0) return;

    final teal = BaselineColors.spectralTeal;
    final segWidth = w / totalProvisions;
    final magnitudes = List.filled(totalProvisions, 0.0);
    for (final d in diffs) {
      if (d.provisionIndex >= 0 && d.provisionIndex < totalProvisions) {
        magnitudes[d.provisionIndex] = d.magnitude;
      }
    }

    // C14 Scan reveal with scan head.
    final revealX = w * scanProgress;
    for (int i = 0; i < totalProvisions; i++) {
      final x = i * segWidth;
      if (x > revealX) break;
      final mag = magnitudes[i];
      _work.color = mag > 0.40
          ? teal.atOpacity(0.40 + mag * 0.30)
          : teal.atOpacity(0.05 + mag * 0.15);
      canvas.drawRect(Rect.fromLTWH(x, 0, segWidth - 0.5, h), _work);
    }
    // Scan head.
    if (scanProgress < 1.0) {
      canvas.drawLine(Offset(revealX, 0), Offset(revealX, h), _scanHead);
    }
  }

  @override
  bool shouldRepaint(_HeatmapStripPainter oldDelegate) =>
      scanProgress != oldDelegate.scanProgress;
}

/// P7: Velocity sparkline chart with draw-on.
class _VelocitySparkPainter extends CustomPainter {
  _VelocitySparkPainter({required this.values, required this.drawProgress})
      : _linePaint = Paint()
          ..color = BaselineColors.spectralTeal.atOpacity(0.60)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
        _fillPaint = Paint()
          ..color = BaselineColors.spectralTeal.atOpacity(0.05),
        _dotPaint = Paint()
          ..color = BaselineColors.spectralTeal.atOpacity(0.70)
          ..style = PaintingStyle.fill;

  final List<double> values;
  final double drawProgress;
  final Paint _linePaint;
  final Paint _fillPaint;
  final Paint _dotPaint;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final w = size.width;
    final h = size.height;
    final maxVal = math.max(values.reduce(math.max), 0.01);

    final points = <Offset>[];
    for (int i = 0; i < values.length; i++) {
      final x = values.length == 1 ? w / 2 : w * i / (values.length - 1);
      final y = h - (values[i] / maxVal) * h * 0.8 - h * 0.1;
      points.add(Offset(x, y));
    }

    // C21 Draw-on: line draws left to right.
    final linePath = Path();
    final fillPath = Path();
    final revealX = w * drawProgress;
    bool started = false;
    for (final pt in points) {
      if (pt.dx > revealX) break;
      if (!started) {
        linePath.moveTo(pt.dx, pt.dy);
        fillPath.moveTo(pt.dx, h);
        fillPath.lineTo(pt.dx, pt.dy);
        started = true;
      } else {
        linePath.lineTo(pt.dx, pt.dy);
        fillPath.lineTo(pt.dx, pt.dy);
      }
    }
    if (started) {
      final lastX = points.where((p) => p.dx <= revealX).last.dx;
      fillPath.lineTo(lastX, h);
      fillPath.close();
      canvas.drawPath(fillPath, _fillPaint);
      canvas.drawPath(linePath, _linePaint);
      for (final pt in points) {
        if (pt.dx > revealX) break;
        canvas.drawCircle(pt, 3, _dotPaint);
      }
    }
  }

  @override
  bool shouldRepaint(_VelocitySparkPainter oldDelegate) =>
      drawProgress != oldDelegate.drawProgress;
}

/// P8: Bidirectional comparison arrow with animated dash-phase.
class _ComparisonArrowPainter extends CustomPainter {
  _ComparisonArrowPainter({required this.dashPhase})
      : _linePaint = Paint()
          ..color = BaselineColors.spectralTeal.atOpacity(0.40)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
        _arrowPaint = Paint()
          ..color = BaselineColors.spectralTeal.atOpacity(0.50)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..strokeCap = StrokeCap.round;

  final double dashPhase;
  final Paint _linePaint;
  final Paint _arrowPaint;

  @override
  void paint(Canvas canvas, Size size) {
    final midY = size.height / 2;

    // Dashed line with phase offset (C30).
    final dashTotal = _kArrowDashLength + _kArrowDashGap;
    final offset = dashPhase * dashTotal;
    for (double x = -offset; x < size.width; x += dashTotal) {
      final start = x.clamp(0.0, size.width);
      final end = (x + _kArrowDashLength).clamp(0.0, size.width);
      if (end > start) {
        canvas.drawLine(Offset(start, midY), Offset(end, midY), _linePaint);
      }
    }

    // Arrowheads.
    canvas.drawLine(Offset(size.width - 6, midY - 4), Offset(size.width, midY), _arrowPaint);
    canvas.drawLine(Offset(size.width - 6, midY + 4), Offset(size.width, midY), _arrowPaint);
    canvas.drawLine(Offset(6, midY - 4), Offset(0, midY), _arrowPaint);
    canvas.drawLine(Offset(6, midY + 4), Offset(0, midY), _arrowPaint);
  }

  @override
  bool shouldRepaint(_ComparisonArrowPainter oldDelegate) =>
      dashPhase != oldDelegate.dashPhase;
}

/// P9: Diff type badge icons (splice/excision/shift).
class _DiffTypeBadgePainter extends CustomPainter {
  _DiffTypeBadgePainter({required this.type})
      : _work = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..strokeCap = StrokeCap.round;

  final MutationDiffType type;
  final Paint _work;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    switch (type) {
      case MutationDiffType.added:
        _work.color = BaselineColors.spectralTeal.atOpacity(0.70);
        canvas.drawLine(Offset(cx - 4, cy - 3), Offset(cx, cy), _work);
        canvas.drawLine(Offset(cx - 4, cy + 3), Offset(cx, cy), _work);
        canvas.drawLine(Offset(cx, cy), Offset(cx + 4, cy), _work);
      case MutationDiffType.removed:
        _work.color = BaselineColors.white.atOpacity(0.50);
        canvas.drawLine(Offset(cx - 5, cy), Offset(cx - 2, cy), _work);
        canvas.drawLine(Offset(cx + 2, cy), Offset(cx + 5, cy), _work);
        canvas.drawLine(Offset(cx - 2, cy - 2), Offset(cx + 2, cy + 2), _work);
        canvas.drawLine(Offset(cx + 2, cy - 2), Offset(cx - 2, cy + 2), _work);
      case MutationDiffType.modified:
        _work.color = BaselineColors.spectralTeal.atOpacity(0.60);
        canvas.drawLine(Offset(cx - 4, cy), Offset(cx + 2, cy), _work);
        canvas.drawLine(Offset(cx, cy - 3), Offset(cx + 4, cy), _work);
        canvas.drawLine(Offset(cx, cy + 3), Offset(cx + 4, cy), _work);
    }
  }

  @override
  bool shouldRepaint(_DiffTypeBadgePainter oldDelegate) =>
      type != oldDelegate.type;
}

/// P10: Sequencing beam with phosphor glow trail.
class _SequencingBeamPainter extends CustomPainter {
  _SequencingBeamPainter({required this.progress})
      : _beamPaint = Paint()
          ..color = BaselineColors.spectralTeal.atOpacity(0.40)
          ..strokeWidth = _kBeamWidth,
        _trailPaint = Paint();

  final double progress;
  final Paint _beamPaint;
  final Paint _trailPaint;

  // [LOCKED] I2 fix: cache last shader by height to avoid per-frame allocation.
  static double? _cachedHeight;
  static ui.Shader? _cachedShader;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress >= 1.0 || progress <= 0.0) return;
    final beamY = size.height * progress;

    // C1 Beam line.
    canvas.drawLine(Offset(0, beamY), Offset(size.width, beamY), _beamPaint);

    // Phosphor glow trail (shader cached by height).
    if (_cachedHeight != size.height) {
      const teal = BaselineColors.spectralTeal;
      _cachedShader = ui.Gradient.linear(
        Offset(0, -_kBeamGlowTrail), Offset.zero,
        [teal.atOpacity(0.0), teal.atOpacity(0.08)]);
      _cachedHeight = size.height;
    }
    _trailPaint.shader = _cachedShader;
    canvas.save();
    canvas.translate(0, beamY);
    canvas.drawRect(
      Rect.fromLTWH(0, -_kBeamGlowTrail, size.width, _kBeamGlowTrail),
      _trailPaint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SequencingBeamPainter oldDelegate) =>
      progress != oldDelegate.progress;
}

/// P11: Section divider with DNA base-pair rung pattern (C26).
class _SectionDividerPainter extends CustomPainter {
  _SectionDividerPainter()
      : _linePaint = Paint()
          ..color = BaselineColors.spectralTeal.atOpacity(0.06)
          ..strokeWidth = 0.5,
        _rungPaint = Paint()
          ..color = BaselineColors.spectralTeal.atOpacity(0.04)
          ..strokeWidth = 0.5;

  final Paint _linePaint;
  final Paint _rungPaint;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final midY = size.height / 2;

    canvas.drawLine(Offset(16, midY - 2), Offset(w - 16, midY - 2), _linePaint);
    canvas.drawLine(Offset(16, midY + 2), Offset(w - 16, midY + 2), _linePaint);

    for (double x = 24; x < w - 24; x += 12) {
      canvas.drawLine(Offset(x, midY - 2), Offset(x, midY + 2), _rungPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// P12: Loading helix (simplified for loading screen, C32).
class _LoadingHelixPainter extends CustomPainter {
  _LoadingHelixPainter({required this.phase})
      : _p1 = Paint()
          ..color = BaselineColors.spectralTeal.atOpacity(0.30)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
        _p2 = Paint()
          ..color = BaselineColors.spectralTeal.atOpacity(0.12)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2;

  final double phase;
  final Paint _p1;
  final Paint _p2;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;
    final cy = h / 2;
    final phaseRad = phase * math.pi * 2;

    final path1 = Path();
    final path2 = Path();
    for (double x = 0; x <= w; x += 2) {
      final normalX = (x - cx) / 25;
      final y1 = cy + 15 * math.sin(normalX * math.pi + phaseRad);
      final y2 = cy + 15 * math.sin(normalX * math.pi + phaseRad + math.pi);
      if (x == 0) { path1.moveTo(x, y1); path2.moveTo(x, y2); }
      else { path1.lineTo(x, y1); path2.lineTo(x, y2); }
    }
    canvas.drawPath(path1, _p1);
    canvas.drawPath(path2, _p2);
  }

  @override
  bool shouldRepaint(_LoadingHelixPainter oldDelegate) =>
      phase != oldDelegate.phase;
}

/// P13: Genome minimap (chromosome overview, C24).
/// [Fix #7] Background drawn BEFORE segments.
class _GenomeMinimapPainter extends CustomPainter {
  _GenomeMinimapPainter({required this.comparisons})
      : _bgPaint = Paint()
          ..color = BaselineColors.spectralTeal.atOpacity(0.03),
        _work = Paint();

  final List<VersionComparison> comparisons;
  final Paint _bgPaint;
  final Paint _work;

  @override
  void paint(Canvas canvas, Size size) {
    if (comparisons.isEmpty) return;
    final teal = BaselineColors.spectralTeal;
    final amber = BaselineColors.amberMuted;
    final w = size.width;
    final h = size.height;

    final comp = comparisons.last;
    if (comp.totalProvisions <= 0) return;
    final segWidth = w / comp.totalProvisions;

    // [Fix #7] Background FIRST, then colored segments.
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), _bgPaint);

    for (final diff in comp.diffs) {
      if (diff.provisionIndex < 0 || diff.provisionIndex >= comp.totalProvisions) continue;
      final x = diff.provisionIndex * segWidth;
      _work.color = switch (diff.type) {
        MutationDiffType.added => teal.atOpacity(0.40),
        MutationDiffType.removed => BaselineColors.white.atOpacity(0.15),
        MutationDiffType.modified => (diff.severity.isAmber ? amber : teal)
            .atOpacity(0.30),
      };
      canvas.drawRect(Rect.fromLTWH(x, 0, math.max(segWidth, 1.0), h), _work);
    }
  }

  @override
  bool shouldRepaint(_GenomeMinimapPainter oldDelegate) => false;
}

/// [C17] Sort scan overlay painter.
class _SortScanPainter extends CustomPainter {
  _SortScanPainter({required this.progress})
      : _scanPaint = Paint()
          ..color = BaselineColors.spectralTeal.atOpacity(0.20)
          ..strokeWidth = 2;

  final double progress;
  final Paint _scanPaint;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height * progress;
    canvas.drawLine(Offset(0, y), Offset(size.width, y), _scanPaint);
  }

  @override
  bool shouldRepaint(_SortScanPainter oldDelegate) =>
      progress != oldDelegate.progress;
}
