/// F4.12 — Vote Record Screen (Congressional Roll Call Terminal)
///
/// Full congressional vote history for a specific figure: searchable,
/// chamber-filtered, vote-type-filtered, paginated docket with expandable
/// bill overviews and Provision Drift™ forensic analysis.
///
/// VISUAL STORY: Congressional Roll Call Terminal
/// Compound reticle corners frame the viewport. Edge tick rulers measure
/// the margins. You are the Senate Parliamentarian behind a classified
/// digital docket. Every vote filed, stamped, indexed. Chamber filter
/// toggles between legislative cabinets. Vote-type filter narrows to
/// exactly what you need. The double tap: bill search + vote-type filter.
///
/// Path: lib/screens/vote_record.dart
library;

// 1. Dart SDK
import 'dart:async';
import 'dart:ui' as ui;

// 2. Flutter
import 'package:flutter/material.dart';

// 3. Third-party
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

// 4. Config
import 'package:baseline_app/config/theme.dart';

// 5. Models
import 'package:baseline_app/models/figure.dart';
import 'package:baseline_app/models/vote.dart';
import 'package:baseline_app/models/bill_summary.dart';
import 'package:baseline_app/config/tier_feature_map.dart';

// 6. Services
import 'package:baseline_app/services/figures_service.dart';
import 'package:baseline_app/services/vote_service.dart';
import 'package:baseline_app/services/bill_summary_service.dart';

// 7. Providers (tier gating)

// 8. Widgets
import 'package:baseline_app/widgets/baseline_icons.dart';
import 'package:baseline_app/widgets/vote_card.dart';
import 'package:baseline_app/widgets/shimmer_loading.dart';
import 'package:baseline_app/widgets/disclaimer_footer.dart';
import 'package:baseline_app/widgets/info_bottom_sheet.dart';
import 'package:baseline_app/widgets/drift_waterfall.dart';
import 'package:baseline_app/widgets/drift_league_table.dart';
import 'package:baseline_app/widgets/feature_gate.dart';
import 'package:baseline_app/widgets/empty_state_widget.dart';
import 'package:baseline_app/widgets/error_state.dart';
import 'package:baseline_app/utils/rate_app_trigger.dart';

// 9. Utils
import 'package:baseline_app/utils/haptic_util.dart';

// ═══════════════════════════════════════════════════════════
// LAYOUT CONSTANTS
// ═══════════════════════════════════════════════════════════

const double _kIconTouchTarget = 44.0;
const double _kAccentLineHeight = 2.0;
const int _kPageSize = 50;
const double _kScrollThreshold = 300.0;
const Duration _kCardStagger = Duration(milliseconds: 40);
const int _kMaxStaggerIndex = 12;
const Duration _kEntranceDuration = Duration(milliseconds: 800);
const Duration _kTallyDuration = Duration(milliseconds: 600);
const Duration _kExpandDuration = Duration(milliseconds: 350);
const Duration _kScanlineDuration = Duration(milliseconds: 200);
const Duration _kUnsealPhase1 = Duration(milliseconds: 150);
const Duration _kScrollIndicatorHide = Duration(milliseconds: 1500);
const double _kDocketBarWidth = 3.0;
const double _kReticleArm = 4.0;
const double _kTallyBarWidth = 44.0;
const double _kTallyBarHeight = 4.0;
const double _kSearchFieldHeight = 44.0;
const double _kPatternDotSize = 5.0;
const double _kPatternDotGap = 2.0;
const int _kPatternDotCount = 50;
const double _kScreenChromeTickLen = 6.0;
const double _kScreenChromeMarkArm = 10.0;
const double _kPerfSpacing = 60.0;
const double _kPerfDotRadius = 1.0;
const double _kPressScaleCard = 0.98;

const EdgeInsets _kChipPadding = EdgeInsets.symmetric(
  horizontal: 14.0,
  vertical: 7.0,
);

const EdgeInsets _kMiniChipPadding = EdgeInsets.symmetric(
  horizontal: 10.0,
  vertical: 5.0,
);

// ═══════════════════════════════════════════════════════════
// ENUMS
// ═══════════════════════════════════════════════════════════

enum _ChamberFilter {
  both('Both'),
  house('House'),
  senate('Senate');

  const _ChamberFilter(this.label);
  final String label;

  Chamber? get chamber {
    switch (this) {
      case _ChamberFilter.both:
        return null;
      case _ChamberFilter.house:
        return Chamber.house;
      case _ChamberFilter.senate:
        return Chamber.senate;
    }
  }
}

enum _VoteTypeFilter {
  all('ALL'),
  yea('YEA'),
  nay('NAY'),
  notVoting('NV'),
  silent('SILENT'),
  highDrift('HIGH DRIFT');

  const _VoteTypeFilter(this.label);
  final String label;
}

// ═══════════════════════════════════════════════════════════
// VOTE RECORD SCREEN
// ═══════════════════════════════════════════════════════════

class VoteRecordScreen extends StatefulWidget {
  const VoteRecordScreen({
    super.key,
    required this.figureId,
  });

  final String figureId;

  @override
  State<VoteRecordScreen> createState() => _VoteRecordScreenState();
}

class _VoteRecordScreenState extends State<VoteRecordScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  // ── State ──────────────────────────────────────────────
  bool _isLoading = true;
  bool _isLoadingMore = false;
  String? _errorMessage;
  String? _errorCode;
  Figure? _figure;
  List<VoteSummary> _summaries = [];
  List<Vote> _votes = [];
  bool _hasMore = false;
  int _currentOffset = 0;
  _ChamberFilter _selectedChamber = _ChamberFilter.both;
  _VoteTypeFilter _selectedVoteType = _VoteTypeFilter.all;

  // Bill search.
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // Bill overview accordion.
  int? _expandedVoteIndex;
  BillSummary? _expandedBillSummary;
  bool _isLoadingBillSummary = false;
  bool _isWaterfallView = false;
  bool _unsealPhase1Complete = false;

  // Scroll position indicator.
  bool _showScrollIndicator = false;
  int _visibleEntryIndex = 0;

  // Bill summaries cache.
  final Map<String, BillSummary> _billSummaryCache = {};

  // I-11: Pending timers list.
  final List<Timer> _pendingTimers = [];

  // ── Controllers ────────────────────────────────────────
  final ScrollController _scrollController = ScrollController();
  late final AnimationController _entranceCtrl;
  late final AnimationController _tallyCtrl;
  late final AnimationController _scanlineCtrl;
  late final AnimationController _ambientCtrl;
  late final AnimationController _unsealCtrl;

  late final CurvedAnimation _entranceFade;

  // ── Services ───────────────────────────────────────────
  final FiguresService _figuresService = FiguresService();
  final VoteService _voteService = VoteService();
  final BillSummaryService _billSummaryService = BillSummaryService();

  // I-44: Pre-computed paragraphs for chrome text.
  ui.Paragraph? _watermarkParagraph;
  ui.Paragraph? _dtgParagraph;
  ui.Paragraph? _handlingParagraph;
  TextScaler _textScaler = TextScaler.noScaling;

  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    // 3N: Register observer for mid-flight accessibility changes.
    WidgetsBinding.instance.addObserver(this);

    _entranceCtrl = AnimationController(
      duration: _kEntranceDuration,
      vsync: this,
    );
    _entranceFade = CurvedAnimation(
      parent: _entranceCtrl,
      curve: Curves.easeOut,
    );

    _tallyCtrl = AnimationController(
      duration: _kTallyDuration,
      vsync: this,
    );

    _scanlineCtrl = AnimationController(
      duration: _kScanlineDuration,
      vsync: this,
    );

    _ambientCtrl = AnimationController(
      duration: const Duration(milliseconds: 4000),
      vsync: this,
    );

    _unsealCtrl = AnimationController(
      duration: _kExpandDuration,
      vsync: this,
    );

    // I-18: Ambient starts after entrance via self-removing status listener.
    void startAmbient(AnimationStatus status) {
      if (status == AnimationStatus.completed) {
        _entranceCtrl.removeStatusListener(startAmbient);
        if (!_disposed && !_reduceMotion) {
          _ambientCtrl.repeat(reverse: true);
        }
      }
    }
    _entranceCtrl.addStatusListener(startAmbient);

    _scrollController.addListener(_onScroll);
    _searchController.addListener(_onSearchChanged);

    HapticUtil.medium();
    _loadData();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // K-C2: Acquire TextScaler for canvas text scaling.
    _textScaler = MediaQuery.textScalerOf(context);
    _buildChromeParagraphs();
  }

  // K-X1 / 3N: Mid-flight reduce motion handling.
  @override
  void didChangeAccessibilityFeatures() {
    super.didChangeAccessibilityFeatures();
    if (_reduceMotion) {
      // I-9: Stop + cancel + snap to 1.0.
      _entranceCtrl
        ..stop()
        ..value = 1.0;
      _tallyCtrl
        ..stop()
        ..value = 1.0;
      _scanlineCtrl.stop();
      _ambientCtrl.stop();
      _unsealCtrl
        ..stop()
        ..value = 1.0;
      for (final t in _pendingTimers) {
        t.cancel();
      }
      _pendingTimers.clear();
      if (mounted) setState(() {});
    }
  }

  /// I-44 / K-I3 / K-M1: Pre-compute ALL chrome paragraphs.
  void _buildChromeParagraphs() {
    // Watermark.
    final wmBuilder = ui.ParagraphBuilder(ui.ParagraphStyle(
      textDirection: ui.TextDirection.ltr,
      textAlign: ui.TextAlign.center,
    ))
      ..pushStyle(ui.TextStyle(
        color: BaselineColors.white.atOpacity(0.02),
        fontSize: _textScaler.scale(48),
        fontWeight: FontWeight.w900,
        letterSpacing: 8,
      ))
      ..addText('OFFICIAL RECORD');
    _watermarkParagraph = wmBuilder.build()
      ..layout(const ui.ParagraphConstraints(width: 500));

    // K-M1: DTG timestamp computed once.
    final now = DateTime.now().toUtc();
    final dtg = '${now.day.toString().padLeft(2, '0')}'
        '${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}Z '
        '${_monthAbbr(now.month)} ${now.year}';
    final dtgBuilder = ui.ParagraphBuilder(ui.ParagraphStyle(
      textDirection: ui.TextDirection.ltr,
    ))
      ..pushStyle(ui.TextStyle(
        color: BaselineColors.teal.atOpacity(0.03),
        fontSize: _textScaler.scale(7),
        fontFamily: BaselineTypography.monoFontFamily,
        letterSpacing: 1,
      ))
      ..addText(dtg);
    _dtgParagraph = dtgBuilder.build()
      ..layout(const ui.ParagraphConstraints(width: 200));

    // Handling mark.
    final hmBuilder = ui.ParagraphBuilder(ui.ParagraphStyle(
      textAlign: ui.TextAlign.center,
      textDirection: ui.TextDirection.ltr,
    ))
      ..pushStyle(ui.TextStyle(
        color: BaselineColors.textSecondary.atOpacity(0.03),
        fontSize: _textScaler.scale(7),
        fontFamily: BaselineTypography.monoFontFamily,
        letterSpacing: 2,
      ))
      ..addText('HANDLE VIA BASELINE CHANNELS ONLY');
    _handlingParagraph = hmBuilder.build()
      ..layout(const ui.ParagraphConstraints(width: 400));
  }

  static String _monthAbbr(int m) =>
      const ['JAN','FEB','MAR','APR','MAY','JUN',
             'JUL','AUG','SEP','OCT','NOV','DEC'][m - 1];

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);

    for (final t in _pendingTimers) {
      t.cancel();
    }
    _pendingTimers.clear();

    _scrollController.removeListener(_onScroll);
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _scrollController.dispose();

    // I-15: CurvedAnimation before parent.
    _entranceFade.dispose();

    // I-29: .stop() before .dispose().
    _entranceCtrl
      ..stop()
      ..dispose();
    _tallyCtrl
      ..stop()
      ..dispose();
    _scanlineCtrl
      ..stop()
      ..dispose();
    _ambientCtrl
      ..stop()
      ..dispose();
    _unsealCtrl
      ..stop()
      ..dispose();

    super.dispose();
  }

  // I-2: Aspect-scoped reduce motion for persistent screen.
  bool get _reduceMotion => MediaQuery.disableAnimationsOf(context);

  // ── Data loading ───────────────────────────────────────

  Future<void> _loadData() async {
    if (_disposed) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _errorCode = null;
    });

    try {
      final results = await Future.wait([
        _figuresService.getFigure(widget.figureId),
        _voteService.getVoteSummary(
          figureId: widget.figureId,
          chamber: _selectedChamber.chamber,
        ),
        _voteService.getVotesForFigure(
          figureId: widget.figureId,
          chamber: _selectedChamber.chamber,
          limit: _kPageSize,
          offset: 0,
        ),
      ]);

      if (_disposed) return;

      final figure = results[0] as Figure;
      final summaries = results[1] as List<VoteSummary>;
      final votePage = results[2] as VotePage;

      setState(() {
        _figure = figure;
        _summaries = summaries;
        _votes = votePage.votes;
        _hasMore = votePage.hasMore;
        _currentOffset = votePage.votes.length;
        _isLoading = false;
      });

      if (_reduceMotion) {
        _entranceCtrl.value = 1.0;
        _tallyCtrl.value = 1.0;
      } else {
        _entranceCtrl.forward();
        _pendingTimers.add(Timer(const Duration(milliseconds: 500), () {
          if (!_disposed) _tallyCtrl.forward();
        }));
      }

      if (mounted) {
        RateAppTrigger.recordInteraction(context);
      }
    } on VoteServiceException catch (e) {
      if (_disposed) return;
      setState(() {
        _isLoading = false;
        _errorMessage = e.code == 'feature_disabled'
            ? 'Vote tracking is temporarily unavailable.'
            : 'Could not load vote record. Please try again.';
        _errorCode = e.code;
      });
    } catch (e) {
      if (_disposed) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Could not load vote record. Please try again.';
        _errorCode = null;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore || _disposed) return;
    setState(() => _isLoadingMore = true);

    try {
      final votePage = await _voteService.getVotesForFigure(
        figureId: widget.figureId,
        chamber: _selectedChamber.chamber,
        limit: _kPageSize,
        offset: _currentOffset,
      );

      if (_disposed) return;
      setState(() {
        _votes.addAll(votePage.votes);
        _hasMore = votePage.hasMore;
        _currentOffset += votePage.votes.length;
        _isLoadingMore = false;
      });
    } catch (e) {
      if (_disposed) return;
      setState(() => _isLoadingMore = false);
    }
  }

  Future<void> _loadBillSummary(String billId) async {
    if (_disposed) return;

    if (_billSummaryCache.containsKey(billId)) {
      setState(() {
        _expandedBillSummary = _billSummaryCache[billId];
        _isLoadingBillSummary = false;
      });
      return;
    }

    setState(() => _isLoadingBillSummary = true);

    try {
      final summary = await _billSummaryService.getBillSummary(billId);
      if (_disposed) return;
      if (summary != null) {
        _billSummaryCache[billId] = summary;
      }
      setState(() {
        _expandedBillSummary = summary;
        _isLoadingBillSummary = false;
      });
    } catch (e) {
      if (_disposed) return;
      setState(() {
        _expandedBillSummary = null;
        _isLoadingBillSummary = false;
      });
    }
  }

  // ── Scroll ─────────────────────────────────────────────

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;

    if (position.pixels >= position.maxScrollExtent - _kScrollThreshold) {
      _loadMore();
    }

    final filtered = _filteredVotes;
    if (filtered.isNotEmpty) {
      final idx = (position.pixels / 120.0).floor().clamp(0, filtered.length - 1);
      if (idx != _visibleEntryIndex) {
        setState(() => _visibleEntryIndex = idx);
      }
    }

    if (!_showScrollIndicator && filtered.length > 5) {
      setState(() => _showScrollIndicator = true);
    }

    _pendingTimers.removeWhere((t) => !t.isActive);
    _pendingTimers.add(Timer(_kScrollIndicatorHide, () {
      if (!_disposed && mounted) {
        setState(() => _showScrollIndicator = false);
      }
    }));
  }

  // ── Filters ────────────────────────────────────────────

  void _onChamberChanged(_ChamberFilter filter) {
    if (filter == _selectedChamber) return;
    HapticUtil.selection();

    if (!_reduceMotion) {
      _scanlineCtrl.forward(from: 0.0);
    }

    setState(() {
      _selectedChamber = filter;
      _votes = [];
      _summaries = [];
      _hasMore = false;
      _currentOffset = 0;
      _expandedVoteIndex = null;
      _expandedBillSummary = null;
      _searchQuery = '';
      _searchController.clear();
      _selectedVoteType = _VoteTypeFilter.all;
    });

    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }

    _tallyCtrl.reset();
    _loadData();
  }

  void _onVoteTypeChanged(_VoteTypeFilter filter) {
    if (filter == _selectedVoteType) return;
    HapticUtil.selection();
    setState(() {
      _selectedVoteType = filter;
      _expandedVoteIndex = null;
      _expandedBillSummary = null;
    });
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim().toLowerCase();
    if (query != _searchQuery) {
      setState(() {
        _searchQuery = query;
        _expandedVoteIndex = null;
        _expandedBillSummary = null;
      });
    }
  }

  List<Vote> get _filteredVotes {
    var result = _votes;

    if (_searchQuery.isNotEmpty) {
      result = result.where((v) {
        final billMatch = v.billId.toLowerCase().contains(_searchQuery);
        final titleMatch =
            v.billTitle.toLowerCase().contains(_searchQuery);
        return billMatch || titleMatch;
      }).toList();
    }

    switch (_selectedVoteType) {
      case _VoteTypeFilter.all:
        break;
      case _VoteTypeFilter.yea:
        result = result.where((v) => v.voteCast == VoteCast.yea).toList();
      case _VoteTypeFilter.nay:
        result = result.where((v) => v.voteCast == VoteCast.nay).toList();
      case _VoteTypeFilter.notVoting:
        result = result.where((v) => v.voteCast == VoteCast.notVoting).toList();
      case _VoteTypeFilter.silent:
        result = result.where((v) => v.isSilentVote).toList();
      case _VoteTypeFilter.highDrift:
        result = result.where((v) {
          final cached = _billSummaryCache[v.billId];
          return cached != null &&
              cached.avgDriftScore != null &&
              cached.avgDriftScore! >= 0.51;
        }).toList();
    }

    return result;
  }

  // ── Vote card tap ──────────────────────────────────────

  void _onVoteTap(int index, Vote vote) {
    HapticUtil.light();

    if (_expandedVoteIndex == index) {
      setState(() {
        _expandedVoteIndex = null;
        _expandedBillSummary = null;
        _isWaterfallView = false;
        _unsealPhase1Complete = false;
      });
      _unsealCtrl.reset();
    } else {
      setState(() {
        _expandedVoteIndex = index;
        _expandedBillSummary = null;
        _isWaterfallView = false;
        _unsealPhase1Complete = false;
      });

      _unsealCtrl.reset();
      if (!_reduceMotion) {
        _unsealCtrl.forward();
        _pendingTimers.add(Timer(_kUnsealPhase1, () {
          if (!_disposed && mounted) {
            setState(() => _unsealPhase1Complete = true);
          }
        }));
      } else {
        _unsealCtrl.value = 1.0;
        _unsealPhase1Complete = true;
      }

      _loadBillSummary(vote.billId);
    }
  }

  // ── Aggregate stats ────────────────────────────────────

  int get _totalVotes =>
      _summaries.fold(0, (sum, s) => sum + s.count);

  int _countFor(VoteCast cast) =>
      _summaries.where((s) => s.voteCast == cast.backendValue).fold(0, (sum, s) => sum + s.count);

  int get _silentVoteCount =>
      _votes.where((v) => v.isSilentVote).length;

  String? get _delegationLabel {
    final fig = _figure;
    if (fig == null) return null;
    final party = fig.party;
    final state = fig.state;
    final district = fig.district;
    if (party == null && state == null) return null;
    final parts = <String>[];
    if (party != null) parts.add(party);
    if (state != null) {
      if (district != null) {
        parts.add('$state-$district');
      } else {
        parts.add(state);
      }
    }
    return parts.join('-');
  }

  // ══════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BaselineColors.background,
      body: SafeArea(
        child: Stack(
          children: [
            // Screen chrome. I-24: RepaintBoundary.
            Positioned.fill(
              child: RepaintBoundary(
                child: ExcludeSemantics(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _ScreenChromePainter(
                        textScaler: _textScaler,
                        dtgParagraph: _dtgParagraph,
                        handlingParagraph: _handlingParagraph,
                      ),
                    ),
                  ),
                ),
              ),
            ),

            AnimatedSwitcher(
              duration: BaselineMotion.standard,
              child: _isLoading
                  ? _buildLoading()
                  : _errorMessage != null
                      ? _buildError()
                      : _buildContent(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoading() {
    return Column(
      key: const ValueKey('loading'),
      children: [
        _VoteRecordHeader(figureName: null, onBack: () => context.pop()),
        const Expanded(child: ShimmerLoading(lines: 8)),
      ],
    );
  }

  Widget _buildError() {
    return Column(
      key: const ValueKey('error'),
      children: [
        _VoteRecordHeader(
          figureName: _figure?.name,
          onBack: () => context.pop(),
        ),
        Expanded(
          child: ErrorState.fromCode(
            code: _errorCode,
            onRetry: _loadData,
          ),
        ),
      ],
    );
  }

  Widget _buildContent() {
    final filteredVotes = _filteredVotes;
    final total = _totalVotes;
    final yeaCount = _countFor(VoteCast.yea);
    final nayCount = _countFor(VoteCast.nay);
    final presentCount = _countFor(VoteCast.present);
    final notVotingCount = _countFor(VoteCast.notVoting);
    final silentCount = _silentVoteCount;

    return Stack(
      key: const ValueKey('content'),
      children: [
        // Watermark. I-44: Pre-computed paragraph.
        Positioned.fill(
          child: RepaintBoundary(
            child: ExcludeSemantics(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _RecordWatermarkPainter(
                    paragraph: _watermarkParagraph,
                  ),
                ),
              ),
            ),
          ),
        ),

        CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          slivers: [
            SliverToBoxAdapter(
              child: FadeTransition(
                opacity: _entranceFade,
                child: Column(
                  children: [
                    _VoteRecordHeader(
                      figureName: _figure?.name,
                      onBack: () => context.pop(),
                    ),

                    // Accent glow line.
                    Container(
                      height: _kAccentLineHeight,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.transparent,
                            BaselineColors.teal.atOpacity(0.6),
                            BaselineColors.teal,
                            BaselineColors.teal.atOpacity(0.6),
                            Colors.transparent,
                          ],
                          stops: const [0.0, 0.2, 0.5, 0.8, 1.0],
                        ),
                      ),
                    ),

                    // Designation.
                    ExcludeSemantics(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          'CONGRESSIONAL VOTE LEDGER',
                          style: BaselineTypography.dataSmall.copyWith(
                            color: BaselineColors.textSecondary.atOpacity(0.06),
                            letterSpacing: 3.0,
                            fontSize: 8,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: BaselineSpacing.md),

                    if (_figure?.name != null)
                      Text(
                        _figure!.name,
                        style: BaselineTypography.h3.copyWith(
                          color: BaselineColors.textSecondary,
                        ),
                        textAlign: TextAlign.center,
                      ),

                    // Delegation badge.
                    if (_delegationLabel != null) ...[
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: BaselineColors.teal.atOpacity(0.04),
                          borderRadius: BorderRadius.circular(BaselineRadius.xs),
                          border: Border.all(
                            color: BaselineColors.teal.atOpacity(0.12),
                            width: 1,
                          ),
                        ),
                        child: Text(
                          _delegationLabel!,
                          style: BaselineTypography.dataSmall.copyWith(
                            color: BaselineColors.teal.atOpacity(0.5),
                            letterSpacing: 1.5,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(height: BaselineSpacing.xs),

                    // Session badge.
                    const _SessionBadge(),

                    const SizedBox(height: BaselineSpacing.md),

                    // Chamber filter.
                    _ChamberFilterBar(
                      selected: _selectedChamber,
                      onChanged: _onChamberChanged,
                      scanlineProgress: _scanlineCtrl,
                      ambientCtrl: _ambientCtrl,
                    ),

                    const SizedBox(height: BaselineSpacing.sm),

                    // Vote-type filter.
                    _VoteTypeFilterBar(
                      selected: _selectedVoteType,
                      onChanged: _onVoteTypeChanged,
                      silentCount: silentCount,
                    ),

                    const SizedBox(height: BaselineSpacing.sm),

                    // Bill search.
                    _BillSearchField(controller: _searchController),

                    const SizedBox(height: BaselineSpacing.md),

                    // Summary tally.
                    _SummaryTallyBar(
                      total: total,
                      yea: yeaCount,
                      nay: nayCount,
                      present: presentCount,
                      notVoting: notVotingCount,
                      silentCount: silentCount,
                      tallyProgress: _tallyCtrl,
                    ),

                    const SizedBox(height: BaselineSpacing.sm),

                    // Vote pattern strip.
                    if (_votes.isNotEmpty)
                      _VotePatternStrip(votes: _votes),

                    const SizedBox(height: BaselineSpacing.xs),

                    // Hashmark ruler.
                    const _HashmarkRuler(),

                    const SizedBox(height: BaselineSpacing.md),

                    // Circuit trace divider.
                    const _CircuitTraceDivider(),

                    const SizedBox(height: BaselineSpacing.sm),
                  ],
                ),
              ),
            ),

            // ── Vote list ──
            if (filteredVotes.isEmpty && !_isLoadingMore)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(BaselineSpacing.xl),
                  child: EmptyStateWidget(
                    message: _searchQuery.isNotEmpty ||
                            _selectedVoteType != _VoteTypeFilter.all
                        ? 'No votes matching your filters.'
                        : _figure != null && !_figure!.isCongressional
                            ? 'Vote records track elected officials.'
                            : 'No vote records found.',
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(
                  horizontal: BaselineSpacing.md,
                ),
                sliver: SliverList.builder(
                  itemCount: filteredVotes.length +
                      (_isLoadingMore ? 1 : 0) +
                      1,
                  itemBuilder: (context, index) {
                    if (index == filteredVotes.length && _isLoadingMore) {
                      return const Padding(
                        padding: EdgeInsets.all(BaselineSpacing.lg),
                        child: Center(child: ShimmerLoading(lines: 2)),
                      );
                    }

                    // Disclaimer footer.
                    if (index ==
                        filteredVotes.length + (_isLoadingMore ? 1 : 0)) {
                      return Padding(
                        padding: const EdgeInsets.only(
                          top: BaselineSpacing.lg,
                          bottom: BaselineSpacing.xl,
                        ),
                        child: Column(
                          children: [
                            Semantics(
                              button: true,
                              excludeSemantics: true,
                              label: 'How vote tracking works',
                              child: GestureDetector(
                                onTap: () {
                                  HapticUtil.light();
                                  InfoBottomSheet.show(
                                    context,
                                    key: 'vote_record',
                                    surface: 'Vote Record',
                                  );
                                },
                                child: Text(
                                  'How vote tracking works \u2192',
                                  style: BaselineTypography.body2.copyWith(
                                    color: BaselineColors.teal,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: BaselineSpacing.md),
                            const DisclaimerFooter(),
                          ],
                        ),
                      );
                    }

                    // Vote entry.
                    final vote = filteredVotes[index];
                    final isExpanded = _expandedVoteIndex == index;

                    return _StaggeredVoteEntry(
                      index: index.clamp(0, _kMaxStaggerIndex),
                      reduceMotion: _reduceMotion,
                      // K-I1: IntrinsicHeight so DocketBindingStrip gets bounded height.
                      child: IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Docket binding strip.
                            _DocketBindingStrip(
                              ambientCtrl: _ambientCtrl,
                            ),

                            const SizedBox(width: BaselineSpacing.xs),

                            Expanded(
                              child: Column(
                                children: [
                                  _PressScale(
                                    scale: _kPressScaleCard,
                                    onTap: () => _onVoteTap(index, vote),
                                    child: VoteCard(
                                      billId: vote.billId,
                                      billTitle: vote.billTitle,
                                      vote: vote.vote,
                                      voteDate: vote.voteDate,
                                      chamber: vote.chamber?.name.toUpperCase() ?? '',
                                      result: vote.result,
                                      isSilentVote: vote.isSilentVote,
                                      index: index,
                                      onTap: () => _onVoteTap(index, vote),
                                    ),
                                  ),

                                  _BillOverviewAccordion(
                                    isExpanded: isExpanded,
                                    unsealCtrl: _unsealCtrl,
                                    phase1Complete: _unsealPhase1Complete,
                                    vote: vote,
                                    billSummary: _expandedBillSummary,
                                    isLoading: _isLoadingBillSummary,
                                    isWaterfallView: _isWaterfallView,
                                    onToggleDriftView: () {
                                      setState(() => _isWaterfallView =
                                          !_isWaterfallView);
                                    },
                                    onSourceTap: () {
                                      if (vote.sourceUrl != null) {
                                        HapticUtil.light();
                                        launchUrl(
                                          Uri.parse(vote.sourceUrl!),
                                          mode: LaunchMode.externalApplication,
                                        );
                                      }
                                    },
                                  ),

                                  const SizedBox(height: BaselineSpacing.sm),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),

        // Scroll position indicator.
        if (_showScrollIndicator && filteredVotes.length > 5)
          Positioned(
            right: BaselineSpacing.md,
            bottom: BaselineSpacing.lg,
            child: AnimatedOpacity(
              opacity: _showScrollIndicator ? 0.6 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: BaselineColors.surface.atOpacity(0.9),
                  borderRadius: BorderRadius.circular(BaselineRadius.xs),
                  border: Border.all(
                    color: BaselineColors.teal.atOpacity(0.2),
                    width: 1,
                  ),
                ),
                child: Text(
                  'ENTRY ${_visibleEntryIndex + 1} / ${filteredVotes.length}',
                  style: BaselineTypography.dataSmall.copyWith(
                    color: BaselineColors.textSecondary,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════
// SCREEN CHROME PAINTER
// ═══════════════════════════════════════════════════════════

class _ScreenChromePainter extends CustomPainter {
  _ScreenChromePainter({
    required this.textScaler,
    this.dtgParagraph,
    this.handlingParagraph,
  })  : _strokePaint = Paint()
          ..color = BaselineColors.teal.atOpacity(0.04)
          ..strokeWidth = 0.5
          ..style = PaintingStyle.stroke,
        _dotPaint = Paint()
          ..color = BaselineColors.teal.atOpacity(0.02)
          ..style = PaintingStyle.fill,
        _regDotPaint = Paint()
          ..color = BaselineColors.teal.atOpacity(0.05)
          ..style = PaintingStyle.fill,
        _hairlinePaint = Paint()
          ..color = BaselineColors.teal.atOpacity(0.04)
          ..strokeWidth = 0.5
          ..style = PaintingStyle.stroke;

  final TextScaler textScaler;
  final ui.Paragraph? dtgParagraph;
  final ui.Paragraph? handlingParagraph;
  final Paint _strokePaint;
  final Paint _dotPaint;
  final Paint _regDotPaint;
  final Paint _hairlinePaint;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final arm = _kScreenChromeMarkArm;
    const inset = 8.0;

    // Compound reticle corners (I-51).
    _drawCompoundCorner(canvas, Offset(inset, inset), arm, 1, 1);
    _drawCompoundCorner(canvas, Offset(w - inset, inset), arm, -1, 1);
    _drawCompoundCorner(canvas, Offset(inset, h - inset), arm, 1, -1);
    _drawCompoundCorner(canvas, Offset(w - inset, h - inset), arm, -1, -1);

    // Edge tick rulers.
    for (var y = 100.0; y < h - 50; y += 80) {
      canvas.drawLine(Offset(4, y), Offset(4 + _kScreenChromeTickLen, y), _strokePaint);
      canvas.drawLine(Offset(w - 4, y), Offset(w - 4 - _kScreenChromeTickLen, y), _strokePaint);
    }

    // Grid dot field.
    for (var x = 40.0; x < w - 40; x += 60) {
      for (var y = 120.0; y < h - 60; y += 60) {
        canvas.drawCircle(Offset(x, y), 0.5, _dotPaint);
      }
    }

    // Classification hairline.
    canvas.drawLine(
      Offset(inset + arm, 4),
      Offset(w - inset - arm, 4),
      _hairlinePaint,
    );

    // K-I3: Pre-computed handling mark paragraph.
    final hm = handlingParagraph;
    if (hm != null) {
      canvas.drawParagraph(hm, Offset((w - hm.maxIntrinsicWidth) / 2, h - 20));
    }

    // K-M1: Pre-computed DTG paragraph.
    final dtg = dtgParagraph;
    if (dtg != null) {
      canvas.drawParagraph(dtg, Offset(inset + 2, h - 32));
    }

    // Registration dots.
    canvas.drawCircle(Offset(inset, inset), 1.5, _regDotPaint);
    canvas.drawCircle(Offset(w - inset, inset), 1.5, _regDotPaint);
    canvas.drawCircle(Offset(inset, h - inset), 1.5, _regDotPaint);
    canvas.drawCircle(Offset(w - inset, h - inset), 1.5, _regDotPaint);
  }

  void _drawCompoundCorner(
    Canvas canvas, Offset origin, double arm, double dx, double dy,
  ) {
    canvas.drawLine(
      origin,
      Offset(origin.dx + arm * dx, origin.dy),
      _strokePaint,
    );
    canvas.drawLine(
      origin,
      Offset(origin.dx, origin.dy + arm * dy),
      _strokePaint,
    );
    final innerOff = Offset(origin.dx + 3 * dx, origin.dy + 3 * dy);
    canvas.drawLine(
      innerOff,
      Offset(innerOff.dx + (arm * 0.4) * dx, innerOff.dy),
      _strokePaint,
    );
    canvas.drawLine(
      innerOff,
      Offset(innerOff.dx, innerOff.dy + (arm * 0.4) * dy),
      _strokePaint,
    );
    canvas.drawCircle(origin, 1.0, _regDotPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ═══════════════════════════════════════════════════════════
// HEADER
// ═══════════════════════════════════════════════════════════

class _VoteRecordHeader extends StatelessWidget {
  const _VoteRecordHeader({this.figureName, this.onBack});

  final String? figureName;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      color: BaselineColors.black,
      padding: const EdgeInsets.symmetric(horizontal: BaselineSpacing.sm),
      child: Row(
        children: [
          if (onBack != null)
            // K-C3: excludeSemantics on interactive Semantics.
            Semantics(
              button: true,
              excludeSemantics: true,
              label: 'Go back',
              child: GestureDetector(
                onTap: () {
                  HapticUtil.light();
                  onBack!();
                },
                behavior: HitTestBehavior.opaque,
                child: SizedBox(
                  height: _kIconTouchTarget,
                  child: Padding(
                    padding: const EdgeInsets.only(right: BaselineSpacing.md),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        BaselineIcon(
                          BaselineIconType.backArrow,
                          size: 24,
                          color: BaselineColors.textPrimary,
                        ),
                        const SizedBox(width: BaselineSpacing.xs),
                        Text('Back',
                            style: BaselineTypography.body2
                                .copyWith(color: BaselineColors.textPrimary)),
                      ],
                    ),
                  ),
                ),
              ),
            )
          else
            const SizedBox(width: _kIconTouchTarget),
          const Spacer(),
          Text('Vote Record',
              style: BaselineTypography.h2
                  .copyWith(color: BaselineColors.textPrimary)),
          const Spacer(),
          ExcludeSemantics(
            child: SizedBox(
              width: _kIconTouchTarget,
              height: _kIconTouchTarget,
              child: CustomPaint(painter: _GavelMarkPainter()),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// GAVEL MARK
// ═══════════════════════════════════════════════════════════

class _GavelMarkPainter extends CustomPainter {
  _GavelMarkPainter()
      : _paint = Paint()
          ..color = BaselineColors.teal.atOpacity(0.08)
          ..strokeWidth = 1.5
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke,
        _dotPaint = Paint()
          ..color = BaselineColors.teal.atOpacity(0.06)
          ..style = PaintingStyle.fill;

  final Paint _paint;
  final Paint _dotPaint;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    canvas.drawLine(Offset(cx - 6, cy + 8), Offset(cx + 6, cy - 4), _paint);
    canvas.drawLine(Offset(cx + 3, cy - 8), Offset(cx + 9, cy - 1), _paint);
    canvas.drawCircle(Offset(cx - 8, cy + 10), 2.0, _dotPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ═══════════════════════════════════════════════════════════
// SESSION BADGE
// ═══════════════════════════════════════════════════════════

class _SessionBadge extends StatelessWidget {
  const _SessionBadge();

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SizedBox(
        height: 20,
        child: CustomPaint(
          painter: _ReticleBadgePainter(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              '119TH CONGRESS',
              style: BaselineTypography.dataSmall.copyWith(
                color: BaselineColors.textSecondary.atOpacity(0.4),
                letterSpacing: 2.0,
                fontSize: 9,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ReticleBadgePainter extends CustomPainter {
  _ReticleBadgePainter()
      : _paint = Paint()
          ..color = BaselineColors.teal.atOpacity(0.06)
          ..strokeWidth = 1.0
          ..style = PaintingStyle.stroke;

  final Paint _paint;

  @override
  void paint(Canvas canvas, Size size) {
    final a = _kReticleArm;
    final w = size.width;
    final h = size.height;
    canvas.drawLine(Offset(0, a), Offset.zero, _paint);
    canvas.drawLine(Offset.zero, Offset(a, 0), _paint);
    canvas.drawLine(Offset(w - a, 0), Offset(w, 0), _paint);
    canvas.drawLine(Offset(w, 0), Offset(w, a), _paint);
    canvas.drawLine(Offset(0, h - a), Offset(0, h), _paint);
    canvas.drawLine(Offset(0, h), Offset(a, h), _paint);
    canvas.drawLine(Offset(w - a, h), Offset(w, h), _paint);
    canvas.drawLine(Offset(w, h), Offset(w, h - a), _paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ═══════════════════════════════════════════════════════════
// CHAMBER FILTER BAR
// ═══════════════════════════════════════════════════════════

class _ChamberFilterBar extends StatelessWidget {
  const _ChamberFilterBar({
    required this.selected,
    required this.onChanged,
    required this.scanlineProgress,
    required this.ambientCtrl,
  });

  final _ChamberFilter selected;
  final ValueChanged<_ChamberFilter> onChanged;
  final AnimationController scanlineProgress;
  final AnimationController ambientCtrl;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([scanlineProgress, ambientCtrl]),
      builder: (context, _) {
        return Stack(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: _ChamberFilter.values.map((f) {
                final active = f == selected;
                final breathTint = active
                    ? 0.12 + (ambientCtrl.value * 0.04)
                    : 0.0;

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  // K-C3: excludeSemantics on interactive Semantics.
                  child: Semantics(
                    button: true,
                    excludeSemantics: true,
                    label: '${f.label} chamber${active ? ', selected' : ''}',
                    child: GestureDetector(
                      onTap: () => onChanged(f),
                      child: AnimatedScale(
                        scale: active ? 1.0 : 0.95,
                        duration: BaselineMotion.fast,
                        child: AnimatedContainer(
                          duration: BaselineMotion.standard,
                          padding: _kChipPadding,
                          decoration: BoxDecoration(
                            color: active
                                ? BaselineColors.teal.atOpacity(breathTint)
                                : Colors.transparent,
                            borderRadius:
                                BorderRadius.circular(BaselineRadius.pill),
                            border: Border.all(
                              color: active
                                  ? BaselineColors.teal
                                  : BaselineColors.border,
                              width: active
                                  ? BaselineBorder.standard.width
                                  : 1.0,
                            ),
                          ),
                          child: Text(
                            f.label,
                            style: BaselineTypography.body2.copyWith(
                              color: active
                                  ? BaselineColors.teal
                                  : BaselineColors.textSecondary,
                              fontWeight:
                                  active ? FontWeight.w600 : FontWeight.w400,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            if (scanlineProgress.value > 0 && scanlineProgress.value < 1)
              Positioned.fill(
                child: ExcludeSemantics(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _ScanlinePainter(progress: scanlineProgress.value),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════
// VOTE-TYPE FILTER BAR
// ═══════════════════════════════════════════════════════════

class _VoteTypeFilterBar extends StatelessWidget {
  const _VoteTypeFilterBar({
    required this.selected,
    required this.onChanged,
    required this.silentCount,
  });

  final _VoteTypeFilter selected;
  final ValueChanged<_VoteTypeFilter> onChanged;
  final int silentCount;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: BaselineSpacing.lg),
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: _VoteTypeFilter.values.map((f) {
          final active = f == selected;
          if (f == _VoteTypeFilter.silent && silentCount == 0) {
            return const SizedBox.shrink();
          }

          final isAmber = f == _VoteTypeFilter.silent;
          final accentColor =
              isAmber ? BaselineColors.amber : BaselineColors.teal;

          return Padding(
            padding: const EdgeInsets.only(right: 6),
            // K-C3: excludeSemantics.
            child: Semantics(
              button: true,
              excludeSemantics: true,
              label: '${f.label} filter${active ? ', selected' : ''}',
              child: GestureDetector(
                onTap: () => onChanged(f),
                child: AnimatedContainer(
                  duration: BaselineMotion.fast,
                  padding: _kMiniChipPadding,
                  decoration: BoxDecoration(
                    color: active
                        ? accentColor.atOpacity(0.12)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(BaselineRadius.pill),
                    border: Border.all(
                      color: active ? accentColor : BaselineColors.border,
                      width: active ? BaselineBorder.standard.width : 1.0,
                    ),
                  ),
                  child: Text(
                    f.label,
                    style: BaselineTypography.dataSmall.copyWith(
                      color: active
                          ? accentColor
                          : BaselineColors.textSecondary.atOpacity(0.5),
                      fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                      letterSpacing: 0.5,
                      fontSize: 10,
                    ),
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
// BILL SEARCH FIELD
// ═══════════════════════════════════════════════════════════

class _BillSearchField extends StatelessWidget {
  const _BillSearchField({required this.controller});
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: BaselineSpacing.lg),
      child: SizedBox(
        height: _kSearchFieldHeight,
        child: TextField(
          controller: controller,
          style: BaselineTypography.data
              .copyWith(color: BaselineColors.textPrimary),
          cursorColor: BaselineColors.teal,
          decoration: InputDecoration(
            hintText: 'Search: H.R. 401, Infrastructure...',
            hintStyle: BaselineTypography.data.copyWith(
              color: BaselineColors.textSecondary.atOpacity(0.3),
            ),
            prefixIcon: Padding(
              padding: const EdgeInsets.only(left: 12, right: 8),
              child: BaselineIcon(
                BaselineIconType.search,
                size: 18,
                color: BaselineColors.textSecondary,
              ),
            ),
            prefixIconConstraints:
                const BoxConstraints(minWidth: 36, minHeight: 0),
            suffixIcon: ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (context, value, _) {
                return AnimatedOpacity(
                  opacity: value.text.isNotEmpty ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 150),
                  child: GestureDetector(
                    onTap: value.text.isNotEmpty
                        ? () {
                            controller.clear();
                            HapticUtil.light();
                          }
                        : null,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: BaselineIcon(
                        BaselineIconType.clear,
                        size: 16,
                        color: BaselineColors.textSecondary,
                      ),
                    ),
                  ),
                );
              },
            ),
            suffixIconConstraints:
                const BoxConstraints(minWidth: 32, minHeight: 0),
            filled: true,
            fillColor: BaselineColors.surface,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(BaselineRadius.sm),
              borderSide: const BorderSide(
                color: BaselineColors.border,
                width: 1.0,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(BaselineRadius.sm),
              borderSide: BorderSide(
                color: BaselineColors.teal,
                width: BaselineBorder.standard.width,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// SUMMARY TALLY + MICRO-BAR + SILENT BEACON
// ═══════════════════════════════════════════════════════════

class _SummaryTallyBar extends StatelessWidget {
  const _SummaryTallyBar({
    required this.total, required this.yea, required this.nay,
    required this.present, required this.notVoting,
    required this.silentCount, required this.tallyProgress,
  });

  final int total, yea, nay, present, notVoting, silentCount;
  final AnimationController tallyProgress;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: tallyProgress,
      builder: (context, _) {
        final t = tallyProgress.value;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: BaselineSpacing.lg),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _TallyColumn('TOTAL', total, t, 0, BaselineColors.textPrimary),
                  _TallyColumn('YEA', yea, t, 1, BaselineColors.teal),
                  _TallyColumn('NAY', nay, t, 2, BaselineColors.teal),
                  _TallyColumn('PRES', present, t, 3, BaselineColors.teal),
                  _TallyColumn('NV', notVoting, t, 4, BaselineColors.textSecondary),
                ],
              ),
              const SizedBox(height: BaselineSpacing.sm),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (total > 0)
                    _MicroTallyBar(
                      recordedRatio: (yea + nay + present) / total,
                      progress: t,
                    ),
                  if (silentCount > 0) ...[
                    const SizedBox(width: BaselineSpacing.md),
                    ExcludeSemantics(
                      child: Container(
                        width: 6, height: 6,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: BaselineColors.amber,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '$silentCount silent',
                      style: BaselineTypography.dataSmall.copyWith(
                        color: BaselineColors.amber.atOpacity(0.7),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TallyColumn extends StatelessWidget {
  const _TallyColumn(this.label, this.value, this.t, this.index, this.color);
  final String label;
  final int value;
  final double t;
  final int index;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final delay = index * 0.08;
    final progress = ((t - delay) / (1.0 - delay)).clamp(0.0, 1.0);
    final curved = Curves.easeOutBack.transform(progress);
    final display = (value * curved.clamp(0.0, 1.0)).round();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
          style: BaselineTypography.dataSmall.copyWith(
            color: BaselineColors.textSecondary.atOpacity(0.4),
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 2),
        Text('$display',
          style: BaselineTypography.data.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
            fontSize: 20,
          ),
        ),
      ],
    );
  }
}

class _MicroTallyBar extends StatelessWidget {
  const _MicroTallyBar({required this.recordedRatio, required this.progress});
  final double recordedRatio;
  final double progress;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: _kTallyBarWidth * recordedRatio * progress,
            height: _kTallyBarHeight,
            decoration: BoxDecoration(
              color: BaselineColors.teal.atOpacity(0.6),
              borderRadius: const BorderRadius.horizontal(left: Radius.circular(2)),
            ),
          ),
          Container(
            width: _kTallyBarWidth * (1.0 - recordedRatio) * progress,
            height: _kTallyBarHeight,
            decoration: BoxDecoration(
              color: BaselineColors.textSecondary.atOpacity(0.2),
              borderRadius: const BorderRadius.horizontal(right: Radius.circular(2)),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// VOTE PATTERN STRIP
// ═══════════════════════════════════════════════════════════

class _VotePatternStrip extends StatelessWidget {
  const _VotePatternStrip({required this.votes});
  final List<Vote> votes;

  @override
  Widget build(BuildContext context) {
    final recent = votes.take(_kPatternDotCount).toList();
    final dotWidth = _kPatternDotSize + _kPatternDotGap;
    final totalWidth = recent.length * dotWidth - _kPatternDotGap;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: BaselineSpacing.lg),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              ExcludeSemantics(
                child: Text('VOTING PATTERN',
                  style: BaselineTypography.dataSmall.copyWith(
                    color: BaselineColors.textSecondary.atOpacity(0.3),
                    letterSpacing: 1.5, fontSize: 8,
                  ),
                ),
              ),
              ExcludeSemantics(
                child: Text('LAST ${recent.length}',
                  style: BaselineTypography.dataSmall.copyWith(
                    color: BaselineColors.textSecondary.atOpacity(0.3),
                    letterSpacing: 1.0, fontSize: 8,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Semantics(
            label: 'Voting pattern: ${recent.where((v) => v.voteCast != VoteCast.notVoting).length} recorded of ${recent.length}',
            child: SizedBox(
              height: _kPatternDotSize,
              width: totalWidth,
              child: CustomPaint(
                painter: _PatternStripPainter(votes: recent),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PatternStripPainter extends CustomPainter {
  _PatternStripPainter({required this.votes})
      : _tealPaint = Paint()..color = BaselineColors.teal.atOpacity(0.5)..style = PaintingStyle.fill,
        _grayPaint = Paint()..color = BaselineColors.textSecondary.atOpacity(0.15)..style = PaintingStyle.fill,
        _amberPaint = Paint()..color = BaselineColors.amber.atOpacity(0.5)..style = PaintingStyle.fill;

  final List<Vote> votes;
  final Paint _tealPaint;
  final Paint _grayPaint;
  final Paint _amberPaint;

  @override
  void paint(Canvas canvas, Size size) {
    final r = _kPatternDotSize / 2;
    for (var i = 0; i < votes.length; i++) {
      final vote = votes[i];
      final cx = i * (_kPatternDotSize + _kPatternDotGap) + r;
      final isSilent = vote.isSilentVote;
      final isRecorded = vote.voteCast != VoteCast.notVoting;

      final paint = isSilent ? _amberPaint : isRecorded ? _tealPaint : _grayPaint;
      canvas.drawCircle(Offset(cx, r), r, paint);
    }
  }

  @override
  bool shouldRepaint(_PatternStripPainter old) => old.votes != votes;
}

// ═══════════════════════════════════════════════════════════
// HASHMARK RULER
// ═══════════════════════════════════════════════════════════

class _HashmarkRuler extends StatelessWidget {
  const _HashmarkRuler();

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: BaselineSpacing.lg),
        // K-I2: Removed double.infinity. SizedBox constrains height; parent constrains width.
        child: SizedBox(
          height: 6,
          width: double.infinity,
          child: CustomPaint(painter: _HashmarkPainter()),
        ),
      ),
    );
  }
}

class _HashmarkPainter extends CustomPainter {
  _HashmarkPainter()
      : _paint = Paint()..color = BaselineColors.teal.atOpacity(0.08)..strokeWidth = 0.5..style = PaintingStyle.stroke,
        _dotPaint = Paint()..color = BaselineColors.teal.atOpacity(0.10)..style = PaintingStyle.fill;

  final Paint _paint;
  final Paint _dotPaint;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    for (var i = 0; i < 8; i++) {
      final x = size.width * ((i + 1) / 9);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), _paint);
    }
    canvas.drawCircle(Offset(size.width / 2, y), 1.5, _dotPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ═══════════════════════════════════════════════════════════
// CIRCUIT TRACE DIVIDER
// ═══════════════════════════════════════════════════════════

class _CircuitTraceDivider extends StatelessWidget {
  const _CircuitTraceDivider();

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: BaselineSpacing.lg),
        // K-I2: Same fix.
        child: SizedBox(
          height: 8,
          width: double.infinity,
          child: CustomPaint(painter: _CircuitTracePainter()),
        ),
      ),
    );
  }
}

class _CircuitTracePainter extends CustomPainter {
  _CircuitTracePainter()
      : _linePaint = Paint()..color = BaselineColors.teal.atOpacity(0.10)..strokeWidth = 1.0..style = PaintingStyle.stroke,
        _dotPaint = Paint()..color = BaselineColors.teal.atOpacity(0.15)..style = PaintingStyle.fill;

  final Paint _linePaint;
  final Paint _dotPaint;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    canvas.drawLine(Offset(0, y), Offset(size.width, y), _linePaint);
    for (var i = 0; i < 3; i++) {
      final x = size.width * (0.25 + i * 0.25);
      canvas.drawCircle(Offset(x, y), 2.0, _dotPaint);
      canvas.drawCircle(Offset(x, y), 3.5, _linePaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ═══════════════════════════════════════════════════════════
// DOCKET BINDING STRIP
// ═══════════════════════════════════════════════════════════

class _DocketBindingStrip extends StatelessWidget {
  const _DocketBindingStrip({required this.ambientCtrl});
  final AnimationController ambientCtrl;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: AnimatedBuilder(
        animation: ambientCtrl,
        builder: (context, _) {
          // K-I1: No double.infinity. Parent IntrinsicHeight + CrossAxisAlignment.stretch sizes this.
          return SizedBox(
            width: _kDocketBarWidth,
            child: CustomPaint(
              painter: _DocketStripPainter(glowPhase: ambientCtrl.value),
            ),
          );
        },
      ),
    );
  }
}

class _DocketStripPainter extends CustomPainter {
  _DocketStripPainter({required this.glowPhase});
  final double glowPhase;

  @override
  void paint(Canvas canvas, Size size) {
    final stripPaint = Paint()
      ..color = BaselineColors.teal.atOpacity(0.15 + glowPhase * 0.05);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), stripPaint);

    final perfPaint = Paint()..color = BaselineColors.background..style = PaintingStyle.fill;
    final cx = size.width / 2;
    for (var y = 10.0; y < size.height; y += _kPerfSpacing) {
      canvas.drawCircle(Offset(cx, y), _kPerfDotRadius, perfPaint);
    }
  }

  @override
  bool shouldRepaint(_DocketStripPainter old) => old.glowPhase != glowPhase;
}

// ═══════════════════════════════════════════════════════════
// SCANLINE PAINTER
// ═══════════════════════════════════════════════════════════

class _ScanlinePainter extends CustomPainter {
  _ScanlinePainter({required this.progress});
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0 || progress >= 1) return;
    final x = size.width * progress;
    final paint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(x - 20, 0), Offset(x + 20, 0),
        [Colors.transparent, BaselineColors.teal.atOpacity(0.25), Colors.transparent],
        [0.0, 0.5, 1.0],
      );
    canvas.drawRect(Offset(x - 20, 0) & Size(40, size.height), paint);
  }

  @override
  bool shouldRepaint(_ScanlinePainter old) => old.progress != progress;
}

// ═══════════════════════════════════════════════════════════
// STAGGERED VOTE ENTRY
// ═══════════════════════════════════════════════════════════

class _StaggeredVoteEntry extends StatefulWidget {
  const _StaggeredVoteEntry({
    required this.index, required this.reduceMotion, required this.child,
  });

  final int index;
  final bool reduceMotion;
  final Widget child;

  @override
  State<_StaggeredVoteEntry> createState() => _StaggeredVoteEntryState();
}

class _StaggeredVoteEntryState extends State<_StaggeredVoteEntry>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  Timer? _staggerTimer;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    if (widget.reduceMotion) {
      _ctrl.value = 1.0;
    } else {
      _staggerTimer = Timer(_kCardStagger * widget.index, () {
        if (mounted) _ctrl.forward();
      });
    }
  }

  @override
  void dispose() {
    _staggerTimer?.cancel();
    _ctrl..stop()..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        final t = Curves.easeOut.transform(_ctrl.value);
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, 7.0 * (1.0 - t)),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

// ═══════════════════════════════════════════════════════════
// PRESS-SCALE WRAPPER
// ═══════════════════════════════════════════════════════════

class _PressScale extends StatefulWidget {
  const _PressScale({
    required this.scale, required this.onTap, required this.child,
  });

  final double scale;
  final VoidCallback onTap;
  final Widget child;

  @override
  State<_PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<_PressScale> {
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
        child: widget.child,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// BILL OVERVIEW ACCORDION
// ═══════════════════════════════════════════════════════════

class _BillOverviewAccordion extends StatelessWidget {
  const _BillOverviewAccordion({
    required this.isExpanded, required this.unsealCtrl,
    required this.phase1Complete, required this.vote,
    required this.billSummary, required this.isLoading,
    required this.isWaterfallView, required this.onToggleDriftView,
    required this.onSourceTap,
  });

  final bool isExpanded;
  final AnimationController unsealCtrl;
  final bool phase1Complete;
  final Vote vote;
  final BillSummary? billSummary;
  final bool isLoading;
  final bool isWaterfallView;
  final VoidCallback onToggleDriftView;
  final VoidCallback onSourceTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: _kExpandDuration,
      curve: Curves.easeInOutCubic,
      alignment: Alignment.topCenter,
      child: isExpanded
          ? AnimatedBuilder(
              animation: unsealCtrl,
              builder: (context, _) {
                final progress = unsealCtrl.value;
                return Container(
                  margin: const EdgeInsets.only(top: 2, bottom: BaselineSpacing.xs),
                  padding: const EdgeInsets.all(BaselineSpacing.md),
                  decoration: BoxDecoration(
                    color: BaselineColors.surface,
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(BaselineRadius.sm),
                      bottomRight: Radius.circular(BaselineRadius.sm),
                    ),
                    border: Border.all(
                      color: BaselineColors.teal.atOpacity(0.10 + progress * 0.08),
                      width: 1.0,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!phase1Complete)
                        _UnsealingIndicator(progress: progress),
                      if (phase1Complete)
                        Opacity(
                          opacity: ((progress - 0.4) / 0.6).clamp(0.0, 1.0),
                          child: Transform.translate(
                            offset: Offset(0, 8.0 * (1.0 - ((progress - 0.4) / 0.6).clamp(0.0, 1.0))),
                            child: isLoading
                                ? const ShimmerLoading(lines: 4)
                                : billSummary == null
                                    ? Text('Bill overview not yet available.',
                                        style: BaselineTypography.body2.copyWith(color: BaselineColors.textSecondary))
                                    : _BillOverviewContent(
                                        summary: billSummary!,
                                        isWaterfallView: isWaterfallView,
                                        onToggleDriftView: onToggleDriftView,
                                        onSourceTap: onSourceTap,
                                      ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            )
          : const SizedBox.shrink(),
    );
  }
}

class _UnsealingIndicator extends StatelessWidget {
  const _UnsealingIndicator({required this.progress});
  final double progress;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SizedBox(
        height: 24,
        child: Stack(
          children: [
            Center(
              child: Text('UNSEALING...',
                style: BaselineTypography.dataSmall.copyWith(
                  color: BaselineColors.teal.atOpacity(0.3 + progress * 0.3),
                  letterSpacing: 2.0, fontSize: 9,
                ),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(painter: _ScanlinePainter(progress: progress)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// BILL OVERVIEW CONTENT
// ═══════════════════════════════════════════════════════════

class _BillOverviewContent extends StatelessWidget {
  const _BillOverviewContent({
    required this.summary, required this.isWaterfallView,
    required this.onToggleDriftView, required this.onSourceTap,
  });

  final BillSummary summary;
  final bool isWaterfallView;
  final VoidCallback onToggleDriftView;
  final VoidCallback onSourceTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(summary.billTitle,
          style: BaselineTypography.h3.copyWith(color: BaselineColors.textPrimary),
          maxLines: 3, overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: BaselineSpacing.sm),
        Text(summary.summary,
          style: BaselineTypography.body2.copyWith(
            color: BaselineColors.textSecondary, height: 1.5,
          ),
        ),
        const SizedBox(height: BaselineSpacing.md),

        if (summary.provisions.isNotEmpty) ...[
          ExcludeSemantics(
            child: Text('NOTABLE PROVISIONS (${summary.provisionCount})',
              style: BaselineTypography.dataSmall.copyWith(
                color: BaselineColors.textSecondary.atOpacity(0.5),
                letterSpacing: 1.5,
              ),
            ),
          ),
          const SizedBox(height: BaselineSpacing.sm),
          ...List.generate(
            summary.provisions.take(5).length,
            (i) {
              final provision = summary.provisions[i];
              final hasTint = i.isEven;
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: BaselineSpacing.xs, vertical: 4),
                decoration: hasTint
                    ? BoxDecoration(
                        color: BaselineColors.teal.atOpacity(0.01),
                        borderRadius: BorderRadius.circular(BaselineRadius.xs),
                      )
                    : null,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(BaselineRadius.xs),
                        border: Border.all(
                          color: BaselineColors.teal.atOpacity(0.3),
                          width: BaselineBorder.standard.width,
                        ),
                      ),
                      child: Text(_categoryLabel(provision.category),
                        style: BaselineTypography.dataSmall.copyWith(
                          color: BaselineColors.teal.atOpacity(0.6), fontSize: 8,
                        ),
                      ),
                    ),
                    const SizedBox(width: BaselineSpacing.xs),
                    Expanded(
                      child: Text(provision.title,
                        style: BaselineTypography.body2.copyWith(
                          color: BaselineColors.textPrimary, fontSize: 13,
                        ),
                        maxLines: 2, overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (provision.driftScore != null) ...[
                      const SizedBox(width: BaselineSpacing.xs),
                      Text(provision.driftLabel ?? 'N/A',
                        style: BaselineTypography.dataSmall.copyWith(
                          color: provision.driftLabel == 'Very High'
                              ? BaselineColors.amber
                              : BaselineColors.teal.atOpacity(0.6),
                          fontSize: 9,
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
          if (summary.provisions.length > 5)
            Padding(
              padding: const EdgeInsets.only(top: BaselineSpacing.xs),
              child: Text('+ ${summary.provisions.length - 5} more provisions',
                style: BaselineTypography.dataSmall.copyWith(
                  color: BaselineColors.textSecondary.atOpacity(0.4),
                ),
              ),
            ),
        ],

        if (summary.driftComputed && summary.provisions.isNotEmpty)
          _DriftSection(
            summary: summary,
            isWaterfallView: isWaterfallView,
            onToggle: onToggleDriftView,
          ),

        const SizedBox(height: BaselineSpacing.md),

        Row(
          children: [
            Expanded(
              // K-C3: excludeSemantics.
              child: Semantics(
                button: true,
                excludeSemantics: true,
                label: 'View bill source',
                child: GestureDetector(
                  onTap: onSourceTap,
                  child: Text('View bill source \u2192',
                    style: BaselineTypography.body2.copyWith(
                      color: BaselineColors.teal, fontSize: 12,
                    ),
                  ),
                ),
              ),
            ),
            Semantics(
              button: true,
              excludeSemantics: true,
              label: 'Report miscategorized provision',
              child: GestureDetector(
                onTap: () {
                  HapticUtil.light();
                  _openMiscatReport(summary.billId);
                },
                child: Text('Miscat? Report \u2192',
                  style: BaselineTypography.dataSmall.copyWith(
                    color: BaselineColors.teal.atOpacity(0.5), fontSize: 10,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _categoryLabel(ProvisionCategory category) {
    switch (category) {
      case ProvisionCategory.earmark: return 'EARMARK';
      case ProvisionCategory.rider: return 'RIDER';
      case ProvisionCategory.amendment: return 'AMEND';
      case ProvisionCategory.standaloneProvision: return 'CORE';
    }
  }

  void _openMiscatReport(String billId) {
    launchUrl(Uri(
      scheme: 'mailto',
      path: 'feedback@getbaseline.app',
      queryParameters: {
        'subject': 'Provision Miscategorization Report: $billId',
        'body': 'Bill ID: $billId\n\nProvision title:\n\nExpected category:\n\nNotes:\n',
      },
    ));
  }
}

// ═══════════════════════════════════════════════════════════
// DRIFT SECTION
// ═══════════════════════════════════════════════════════════

class _DriftSection extends StatelessWidget {
  const _DriftSection({
    required this.summary, required this.isWaterfallView, required this.onToggle,
  });

  final BillSummary summary;
  final bool isWaterfallView;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    // Drift bars visible to all (Core). Interactive toggle stays Pro+.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: BaselineSpacing.md),
        const _CircuitTraceDivider(),
        const SizedBox(height: BaselineSpacing.sm),
        Row(
          children: [
            Text('PROVISION DRIFT\u2122',
              style: BaselineTypography.dataSmall.copyWith(
                color: BaselineColors.teal.atOpacity(0.6), letterSpacing: 1.5,
              ),
            ),
            const Spacer(),
            FeatureGate(
              feature: GatedFeature.driftLeagueTable,
              child: _DriftViewToggle(isWaterfall: isWaterfallView, onToggle: onToggle),
            ),
          ],
        ),
        const SizedBox(height: BaselineSpacing.sm),
        if (summary.avgDriftScore != null)
          Padding(
            padding: const EdgeInsets.only(bottom: BaselineSpacing.sm),
            child: Text(
              'Avg drift: ${(summary.avgDriftScore! * 100).toStringAsFixed(0)}%',
              style: BaselineTypography.dataSmall.copyWith(
                color: BaselineColors.textSecondary.atOpacity(0.5),
              ),
            ),
          ),
        AnimatedSwitcher(
          duration: BaselineMotion.standard,
          child: isWaterfallView
              ? DriftWaterfall(key: const ValueKey('waterfall'), summary: summary)
              : DriftLeagueTable(key: const ValueKey('league'), summary: summary),
        ),
      ],
    );
  }
}

class _DriftViewToggle extends StatelessWidget {
  const _DriftViewToggle({required this.isWaterfall, required this.onToggle});
  final bool isWaterfall;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      excludeSemantics: true,
      label: isWaterfall ? 'Switch to league table' : 'Switch to waterfall',
      child: GestureDetector(
        onTap: () {
          HapticUtil.selection();
          onToggle();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(BaselineRadius.xs),
            border: Border.all(color: BaselineColors.border, width: 1),
          ),
          child: Text(isWaterfall ? 'TABLE' : 'CASCADE',
            style: BaselineTypography.dataSmall.copyWith(
              color: BaselineColors.teal.atOpacity(0.6),
              letterSpacing: 1.0, fontSize: 9,
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// RECORD WATERMARK
// ═══════════════════════════════════════════════════════════

class _RecordWatermarkPainter extends CustomPainter {
  _RecordWatermarkPainter({this.paragraph});
  final ui.Paragraph? paragraph;

  @override
  void paint(Canvas canvas, Size size) {
    final para = paragraph;
    if (para == null) return;
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(-0.35);
    canvas.drawParagraph(para, Offset(-para.maxIntrinsicWidth / 2, -para.height / 2));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_RecordWatermarkPainter old) => old.paragraph != paragraph;
}
