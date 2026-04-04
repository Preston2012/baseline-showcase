/// F4.7: Statement Detail Screen (Classified Intelligence Brief)
///
/// The core content screen of BASELINE. WHERE USERS SPEND THE MOST TIME.
/// Opens a single statement as a classified intelligence document.
///
/// Visual layers (screen-level, single-pass `_DocumentChromePainter`):
///   1. Film perforations (left edge)
///   2. Intel dot grid (top-right corner)
///   3. Compound reticle corners + registration dots
///   4. Classification hairlines (top + bottom)
///   5. Hashmark ruler (bottom edge)
///   6. Handling mark (rotated, left margin)
///   7. Monitoring pulse (left border ambient glow)
///
/// Section painters:
///   - `_CompoundReticlePainter`: compound reticles on quote card + console
///   - `_InstrumentPanelPainter`: signal section backing
///   - `_FilmPerfDividerPainter`: section boundary markers
///   - `_AccentRulerPainter`: quote card left ruler
///   - `_QuoteGlyphPainter`: double-comma form (unique to F4.7)
///   - `_HashDividerPainter`: measurement ruler dividers
///   - `_HolographicSealPainter`: quote card auth watermark (cherry)
///   - `_AccessStampPainter`: document access certification (cherry)
///
/// LEGAL REQUIREMENTS (non-negotiable):
/// ✓ Source Badge visible (even when URL null)
/// ✓ Context Bridge always visible (never collapsed)
/// ✓ Disclaimer Footer at bottom
///
/// Path: lib/screens/statement_detail.dart
library;

// 1. Dart SDK
import 'dart:async';
import 'dart:math' as math;

// 2. Flutter
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:baseline_app/services/feed_service.dart';
import 'package:baseline_app/providers/tier_provider.dart';

// 3. Third-party
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
// 4. Config
import 'package:baseline_app/config/theme.dart';
import 'package:baseline_app/config/constants.dart';
import 'package:baseline_app/config/routes.dart';

// 5. Providers
import 'package:baseline_app/providers/statement_provider.dart';

// 6. Widgets
import 'package:baseline_app/widgets/baseline_icons.dart';
import 'package:baseline_app/widgets/consensus_badge.dart';
import 'package:baseline_app/widgets/signal_chip.dart';
import 'package:baseline_app/widgets/context_bridge.dart';
import 'package:baseline_app/widgets/source_badge.dart';
import 'package:baseline_app/widgets/tier_badge.dart';
import 'package:baseline_app/widgets/shimmer_loading.dart';
import 'package:baseline_app/widgets/disclaimer_footer.dart';
import 'package:baseline_app/widgets/info_bottom_sheet.dart';
import 'package:baseline_app/widgets/rate_app_popup.dart';
import 'package:baseline_app/widgets/soft_paywall_popup.dart';
import 'package:baseline_app/widgets/intersections_panel.dart';
import 'package:baseline_app/widgets/measured_by_row.dart';
import 'package:baseline_app/widgets/first_visit_overlay.dart';

// 7. Utils
import 'package:baseline_app/utils/export_util.dart';
import 'package:baseline_app/utils/haptic_util.dart';

// ═══════════════════════════════════════════════════════════
// DATE HELPERS (replaces package:intl)
// ═══════════════════════════════════════════════════════════
const _kMonths = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
String _fmtDateMDY(DateTime d) => '${_kMonths[d.month - 1]} ${d.day}, ${d.year}';

// ═══════════════════════════════════════════════════════════
// CONSTANTS
// ═══════════════════════════════════════════════════════════

// ── Sizing ────────────────────────────────────────────────
const double _kAvatarSize = 44.0;
const double _kAvatarBorderWidth = 2.0;
const double _kNavRowHeight = 56.0;
const double _kConsensusBadgeSize = 72.0;
const double _kTopicChipHeight = 28.0;
const int _kSignalChipColumns = 2;
const double _kIconTouchTarget = 44.0;
const double _kActionButtonSize = 44.0;
const double _kActionIconSize = 18.0;
const double _kMaxTextScale = 1.3;

// ── Chrome ────────────────────────────────────────────────
const double _kReticleArm = 6.0;
const double _kReticleInnerTick = 3.0;
const double _kCornerDotRadius = 1.0;
const double _kPerfWidth = 6.0;
const double _kPerfHeight = 3.0;
const double _kPerfSpacing = 8.0;
const int _kPerfCount = 8;
const double _kPerfInsetLeft = 6.0;
const double _kIntelDotSize = 1.0;
const double _kIntelDotSpacing = 10.0;
const int _kIntelDotGrid = 4;
const double _kRulerTickHeight = 3.0;
const int _kRulerTicks = 7;
const double _kHashDash = 4.0;
const double _kHashGap = 3.0;
const double _kSealRingCount = 3;

// ── Animations ────────────────────────────────────────────
const Duration _kEntranceDuration = Duration(milliseconds: 1200);
const Duration _kCountUpDuration = Duration(milliseconds: 600);
const Duration _kAmbientDuration = Duration(milliseconds: 3000);
const Duration _kPortionPulseDuration = Duration(milliseconds: 6000);
const int _kSectionCount = 7;

// ── Press-scale ───────────────────────────────────────────
const double _kScaleCard = 0.98;
const double _kScaleChip = 0.95;

// ═══════════════════════════════════════════════════════════
// SCREEN
// ═══════════════════════════════════════════════════════════

class StatementDetailScreen extends ConsumerStatefulWidget {
  const StatementDetailScreen({
    super.key,
    required this.statementId,
  });

  final String statementId;

  @override
  ConsumerState<StatementDetailScreen> createState() =>
      _StatementDetailScreenState();
}

class _StatementDetailScreenState
    extends ConsumerState<StatementDetailScreen>
    with TickerProviderStateMixin {

  // ── Controllers ─────────────────────────────────────────
  late final AnimationController _entrance;
  late final AnimationController _countUp;
  late final AnimationController _ambient;
  late final AnimationController _portionPulse;

  // ── CurvedAnimations (disposed before parent, I-15) ────
  late final CurvedAnimation _scanlineCurve;
  late final CurvedAnimation _chromeFadeCurve;
  late final List<CurvedAnimation> _sectionCurves;

  // ── Derived Animations ─────────────────────────────────
  late final Animation<double> _scanline;
  late final Animation<double> _chromeFade;
  late final Animation<double> _consensusBreath;
  late final List<Animation<double>> _sectionFade;
  late final List<Animation<Offset>> _sectionSlide;

  // ── Pre-computed merge (avoids allocation per build, I-15) ──
  late final Listenable _chromeAnimation;

  // ── Provider subscription (out of build, A2-1) ────────
  ProviderSubscription<AsyncValue<StatementState>>? _providerSub;

  // ── Timers (I-11) ──────────────────────────────────────
  final _pendingTimers = <Timer>[];

  // ── State ──────────────────────────────────────────────
  bool _reduceMotion = false;
  bool _entrancePlayed = false;
  bool _firstVisitFired = false;
  String _cachedDtg = '';
  String _cachedSerial = '';
  final _fullExportKey = GlobalKey();
  final _snippetExportKey = GlobalKey();
  String get _sid =>
      widget.statementId.substring(
        0, math.min(8, widget.statementId.length),
      ).toUpperCase();

  void _cacheDtg() {
    final now = DateTime.now().toUtc();
    final d = now.day.toString().padLeft(2, '0');
    final hr = now.hour.toString().padLeft(2, '0');
    final mn = now.minute.toString().padLeft(2, '0');
    const months = [
      'JAN','FEB','MAR','APR','MAY','JUN',
      'JUL','AUG','SEP','OCT','NOV','DEC',
    ];
    final mon = months[now.month - 1];
    final y = (now.year % 100).toString().padLeft(2, '0');
    _cachedDtg = '$d$hr${mn}Z$mon$y';
    _cachedSerial =
        'BL-${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}-$_sid';
  }

  // ── Lifecycle ─────────────────────────────────────────

  @override
  void initState() {
    super.initState();

    _entrance = AnimationController(vsync: this, duration: _kEntranceDuration);
    _countUp = AnimationController(vsync: this, duration: _kCountUpDuration);
    _ambient = AnimationController(vsync: this, duration: _kAmbientDuration);
    _portionPulse = AnimationController(
      vsync: this,
      duration: _kPortionPulseDuration,
    );

    // Scanline: first 40% of entrance.
    _scanlineCurve = CurvedAnimation(
      parent: _entrance,
      curve: const Interval(0.08, 0.45, curve: Curves.easeInOut),
    );
    _scanline = Tween(begin: 0.0, end: 1.0).animate(_scanlineCurve);

    // Chrome fade: first 15%.
    _chromeFadeCurve = CurvedAnimation(
      parent: _entrance,
      curve: const Interval(0.0, 0.15, curve: Curves.easeOut),
    );
    _chromeFade = Tween(begin: 0.0, end: 1.0).animate(_chromeFadeCurve);

    // Per-section stagger: share one CurvedAnimation for fade + slide.
    _sectionCurves = List.generate(_kSectionCount, (i) {
      final s = (0.15 + i * 0.08).clamp(0.0, 0.85);
      final e = (s + 0.20).clamp(s, 1.0);
      return CurvedAnimation(
        parent: _entrance,
        curve: Interval(s, e, curve: Curves.easeOut),
      );
    });
    _sectionFade = _sectionCurves.toList();
    _sectionSlide = List.generate(_kSectionCount, (i) {
      return Tween(
        begin: const Offset(0, 8),
        end: Offset.zero,
      ).animate(_sectionCurves[i]);
    });

    // Consensus badge breath: pre-computed tween (no per-frame sin()).
    _consensusBreath = Tween<double>(begin: 1.0, end: 1.01).animate(_ambient);

    // Pre-compute merged listenable (avoids allocation per build).
    _chromeAnimation = Listenable.merge([_entrance, _ambient]);

    // Start count-up when instruments section reveals (~40%).
    _entrance.addListener(_onEntranceTick);

    // Fire haptic when scanline completes.
    _entrance.addStatusListener(_onEntranceStatus);

    // Provider listener (out of build, A2-1).
    _providerSub = ref.listenManual(
      statementProvider(widget.statementId),
      _onProviderChange,
      fireImmediately: true,
    );

    // First visit overlay (once).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_firstVisitFired) {
        _firstVisitFired = true;
        FirstVisitOverlay.maybeShow(context);
      }
    });

    _cacheDtg();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = MediaQuery.disableAnimationsOf(context);
    if (reduced && !_reduceMotion) {
      // Mid-flight snap (I-9).
      _entrance.value = 1.0;
      _countUp.value = 1.0;
      _ambient.stop();
      _portionPulse.stop();
      for (final t in _pendingTimers) { t.cancel(); }
      _pendingTimers.clear();
    }
    _reduceMotion = reduced;
  }

  void _onProviderChange(
    AsyncValue<StatementState>? prev,
    AsyncValue<StatementState> next,
  ) {
    if (next.hasValue && (prev == null || !prev.hasValue)) {
      _onDataLoaded();
    }
    if (prev?.valueOrNull?.isRefreshing == true &&
        next.valueOrNull?.isRefreshing == false) {
      _onDataLoaded();
    }
  }

  void _onEntranceTick() {
    if (_entrance.value >= 0.40 &&
        !_countUp.isAnimating &&
        _countUp.value == 0.0) {
      _countUp.forward();
    }
  }

  void _onEntranceStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && mounted) {
      HapticUtil.measurementComplete();
    }
  }

  @override
  void dispose() {
    // Close provider subscription (A2-1).
    _providerSub?.close();
    // Cancel pending timers (I-11).
    for (final t in _pendingTimers) { t.cancel(); }
    _pendingTimers.clear();

    // Remove listeners before disposal (I-29).
    _entrance.removeListener(_onEntranceTick);
    _entrance.removeStatusListener(_onEntranceStatus);

    // Dispose CurvedAnimations before parent controllers (I-15).
    for (final c in _sectionCurves) { c.dispose(); }
    _scanlineCurve.dispose();
    _chromeFadeCurve.dispose();

    // Stop then dispose controllers (I-29).
    _portionPulse.stop();
    _portionPulse.dispose();
    _ambient.stop();
    _ambient.dispose();
    _countUp.stop();
    _countUp.dispose();
    _entrance.stop();
    _entrance.dispose();
    super.dispose();
  }

  // ── Data Callbacks ────────────────────────────────────

  void _onDataLoaded() {
    _cacheDtg();
    if (!_entrancePlayed) {
      _entrancePlayed = true;
      if (_reduceMotion) {
        _entrance.value = 1.0;
        _countUp.value = 1.0;
      } else {
        _entrance.forward();
      }
      if (!_reduceMotion) {
        _ambient.repeat(reverse: true);
        _portionPulse.repeat(reverse: true);
      }
    }

    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final s = ref.read(statementProvider(widget.statementId));
      final fid = s.valueOrNull?.figureId;
      // Sequential gate (A2-2): only one popup per screen activation.
      RateAppPopup.maybeShow(context, figureId: fid).then((_) {
        if (mounted) {
          final currentTier = ref.read(tierProvider).tier;
          SoftPaywallPopup.maybeShow(context, tier: currentTier.isEmpty ? 'free' : currentTier);
        }
      });
    });
  }

  Future<void> _onRefresh() async {
    ref.invalidate(statementProvider(widget.statementId));
    await ref.read(statementProvider(widget.statementId).future);
    if (!mounted) return;
    HapticUtil.refreshComplete();
  }

  void _copyWithCitation(String text, String name, DateTime date) {
    HapticUtil.light();
    final citation =
        '"$text"\n$name, ${_fmtDateMDY(date.toLocal())} (via BASELINE)';
    Clipboard.setData(ClipboardData(text: citation));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Statement copied with citation.',
          style: BaselineTypography.caption.copyWith(
            color: BaselineColors.textPrimary,
          ),
        ),
        backgroundColor: BaselineColors.card,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _exportFull(String name) {
    HapticUtil.light();
    ExportUtil.captureAndShare(
      _fullExportKey,
      subject: '$name: BASELINE',
    ).then((ok) {
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Export failed. Try again.')),
        );
      }
    });
  }

  void _shareSnippet(String name) {
    HapticUtil.medium();
    ExportUtil.captureAndShare(
      _snippetExportKey,
      subject: '$name: BASELINE',
    );
  }

  // ── Build ─────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final asyncState = ref.watch(statementProvider(widget.statementId));

    return MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(
          MediaQuery.of(context).textScaler
              .scale(1.0).clamp(1.0, _kMaxTextScale),
        ),
      ),
      child: Scaffold(
        backgroundColor: BaselineColors.scaffoldBackground,
        body: SafeArea(
          child: asyncState.when(
            loading: _buildLoading,
            error: (e, _) => _buildError(
              e is FeedServiceException
                  ? e.message
                  : 'Unable to load statement. Pull to retry.',
            ),
            data: _buildContent,
          ),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════
  // LOADING
  // ══════════════════════════════════════════════════════════

  Widget _buildLoading() {
    return Column(
      children: [
        _buildSubjectHeader(figureName: null),
        const Expanded(
          child: ShimmerLoading(variant: ShimmerVariant.detail),
        ),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════
  // ERROR
  // ══════════════════════════════════════════════════════════

  Widget _buildError(String msg) {
    return Column(
      children: [
        _buildSubjectHeader(figureName: null),
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: BaselineSpacing.xl,
              ),
              child: Semantics(
                liveRegion: true,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    BaselineIcon(
                      BaselineIconType.error,
                      size: 48,
                      color: BaselineColors.textSecondary,
                    ),
                    const SizedBox(height: BaselineSpacing.sm),
                    Text(
                      'RETRIEVAL FAILED',
                      style: BaselineTypography.dataSmall.copyWith(
                        color: BaselineColors.teal.atOpacity(0.4),
                        letterSpacing: 2.0,
                      ),
                    ),
                    const SizedBox(height: BaselineSpacing.xs),
                    Text(
                      msg, textAlign: TextAlign.center, maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: BaselineTypography.body1.copyWith(
                        color: BaselineColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: BaselineSpacing.lg),
                    _TapScale(
                      scale: _kScaleCard,
                      onTap: () {
                        HapticUtil.light();
                        ref.invalidate(
                          statementProvider(widget.statementId),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: BaselineSpacing.lg,
                          vertical: BaselineSpacing.sm,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: BaselineColors.teal, width: 2,
                          ),
                          borderRadius: BorderRadius.circular(26),
                        ),
                        child: Text(
                          'RETRY',
                          style: BaselineTypography.data.copyWith(
                            color: BaselineColors.teal,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════
  // CONTENT
  // ══════════════════════════════════════════════════════════

  Widget _buildContent(StatementState state) {
    final stmt = state.statement;
    final consensus = state.consensus;
    final analyses = state.analyses;

    return Stack(
      children: [
        // ── Screen chrome (own RepaintBoundary + builder, I-30/MS1) ──
        Positioned.fill(
          child: RepaintBoundary(
            child: AnimatedBuilder(
              animation: _chromeAnimation,
              builder: (context, _) => IgnorePointer(
                child: ExcludeSemantics(
                  child: Opacity(
                    opacity: _chromeFade.value,
                    child: CustomPaint(
                      painter: _DocumentChromePainter(
                        ambientProgress: _ambient.value,
                        scanlineProgress: _scanline.value,
                        sid: _sid,
                        dtg: _cachedDtg,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),

        // ── Main content (no wrapping builder: sections self-drive) ──
        RepaintBoundary(
          key: _fullExportKey,
          child: RefreshIndicator(
            onRefresh: _onRefresh,
            color: BaselineColors.teal,
            backgroundColor: BaselineColors.card,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(
                bottom: BaselineSpacing.xxl,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // §0 Classification header.
                  _sWrap(0, _buildClassificationHeader()),

                  // §1 Subject header (figure).
                  _buildSubjectHeader(
                      figureName: stmt.figureName,
                    ),
                    const SizedBox(height: BaselineSpacing.md),

                    // §2 Quote card (primary intel excerpt).
                    _sWrap(1, RepaintBoundary(
                      key: _snippetExportKey,
                      child: Hero(
                        tag: 'statement_${widget.statementId}',
                        flightShuttleBuilder:
                            (_, anim, _, _, _) =>
                                FadeTransition(
                          opacity: anim,
                          child: _buildQuoteCard(stmt),
                        ),
                        child: _buildQuoteCard(stmt),
                      ),
                    )),
                    const SizedBox(height: BaselineSpacing.md),

                    // §3 Context Bridge (LEGAL).
                    if (stmt.hasContext)
                      _sWrap(2, Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: BaselineSpacing.lg,
                        ),
                        child: ContextBridge(
                          contextBefore: stmt.contextBefore,
                          contextAfter: stmt.contextAfter,
                        ),
                      )),
                    if (stmt.hasContext)
                      const SizedBox(height: BaselineSpacing.md),

                    // Topic chips.
                    if (stmt.topics.isNotEmpty)
                      _sWrap(2, _buildTopicChips(stmt.topics)),
                    if (stmt.topics.isNotEmpty)
                      const SizedBox(height: BaselineSpacing.sm),

                    // ── Film perf divider + connector dot ──
                    if (consensus != null)
                      _sWrap(3, _buildFilmPerfDivider()),
                    if (consensus != null)
                      _sWrap(3, _buildConnectorDot()),

                    // §4 Signal instrument panel.
                    if (consensus != null)
                      _sWrap(3, _buildSignalPanel(
                        consensus, analyses ?? [],
                      )),

                    // Variance banner.
                    if (consensus?.varianceDetected == true)
                      _sWrap(3, _buildVarianceBanner()),

                    // ── Film perf divider + connector dot ──
                    _sWrap(4, _buildFilmPerfDivider()),
                    _sWrap(4, _buildConnectorDot()),

                    // §5 Action bar with connector trace.
                    _sWrap(4, _buildActionBar(stmt)),
                    const SizedBox(height: BaselineSpacing.md),

                    // §6 Command console (feature hub).
                    _sWrap(4, _buildCommandConsole(consensus)),
                    const SizedBox(height: BaselineSpacing.lg),

                    // §7 Intersections Panel™.
                    if (stmt.topics.isNotEmpty ||
                        consensus != null)
                      _sWrap(5, Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: BaselineSpacing.lg,
                        ),
                        child: IntersectionsPanel(
                          topics: stmt.topics,
                          framingConsensus:
                              consensus?.framingConsensus,
                          figureName: stmt.figureName,
                          figureId: stmt.figureId,
                          statedAt: stmt.statedAt,
                        ),
                      )),

                    // Partial failure.
                    // Note: response is String?; partial failure tracking
                    // is not available on this type.


                    // ── Film perf divider ──
                    _sWrap(6, _buildFilmPerfDivider()),

                    // Handling mark.
                    _sWrap(6, _buildHandlingMark()),

                    // Disclaimer (LEGAL).
                    _sWrap(6, const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: BaselineSpacing.lg,
                      ),
                      child: DisclaimerFooter(),
                    )),

                    // Document serial.
                    _sWrap(6, _buildDocumentSerial()),

                    // Access stamp (cherry #117).
                    if (_entrancePlayed)
                      _sWrap(6, _buildAccessStamp()),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
  }

  // ── Section wrapper ───────────────────────────────────

  Widget _sWrap(int i, Widget child) {
    if (_reduceMotion) return child;
    final idx = i.clamp(0, _kSectionCount - 1);
    return FadeTransition(
      opacity: _sectionFade[idx],
      child: AnimatedBuilder(
        animation: _sectionSlide[idx],
        builder: (_, _) => Transform.translate(
          offset: _sectionSlide[idx].value,
          child: child,
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════
  // §0 CLASSIFICATION HEADER
  // ══════════════════════════════════════════════════════════

  Widget _buildClassificationHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        BaselineSpacing.lg, BaselineSpacing.sm,
        BaselineSpacing.lg, BaselineSpacing.xs,
      ),
      child: Column(
        children: [
          // Top hairline.
          Container(
            height: 0.5,
            color: BaselineColors.teal.atOpacity(0.06),
          ),
          const SizedBox(height: BaselineSpacing.xxs),
          Row(
            children: [
              // Portion mark with breathing pulse (cherry #119).
              AnimatedBuilder(
                animation: _portionPulse,
                builder: (_, _) {
                  final alpha = _reduceMotion
                      ? 0.20
                      : 0.20 + 0.05 * math.sin(
                            _portionPulse.value * math.pi,
                          );
                  return Text(
                    '(U) ',
                    style: BaselineTypography.dataSmall.copyWith(
                      color: BaselineColors.teal.atOpacity(alpha),
                      letterSpacing: 1.5,
                    ),
                  );
                },
              ),
              Expanded(
                child: Text(
                  'STATEMENT ANALYSIS · BASELINE INTELLIGENCE',
                  style: BaselineTypography.dataSmall.copyWith(
                    color: BaselineColors.teal.atOpacity(0.20),
                    letterSpacing: 1.5,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: BaselineSpacing.xs),
              Text(
                'SID-$_sid',
                style: BaselineTypography.dataSmall.copyWith(
                  color: BaselineColors.textSecondary.atOpacity(0.15),
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
          const SizedBox(height: BaselineSpacing.xxs),
          // Bottom hairline.
          Container(
            height: 0.5,
            color: BaselineColors.teal.atOpacity(0.06),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════
  // §1 SUBJECT HEADER
  // ══════════════════════════════════════════════════════════

  Widget _buildSubjectHeader({required String? figureName}) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: BaselineSpacing.lg,
        vertical: BaselineSpacing.sm,
      ),
      child: Row(
        children: [
          // Back arrow from F_ICONS.
          Semantics(
            button: true, label: 'Go back',
            excludeSemantics: true,
            child: _TapScale(
              scale: _kScaleCard,
              onTap: () {
                HapticUtil.light();
                if (context.canPop()) {
                  context.pop();
                } else {
                  context.go(AppRoutes.today);
                }
              },
              child: SizedBox(
                width: _kIconTouchTarget,
                height: _kIconTouchTarget,
                child: Center(
                  child: BaselineIcon(
                    BaselineIconType.backArrow,
                    size: 20,
                    color: BaselineColors.textPrimary,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: BaselineSpacing.xs),

          // Figure name.
          Expanded(
            child: Text(
              figureName ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: BaselineTypography.h2.copyWith(
                color: BaselineColors.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: BaselineSpacing.sm),

          // Avatar (teal ring, LOCKED identity).
          Semantics(
            label: figureName != null
                ? 'Photo of $figureName'
                : 'Figure photo',
            excludeSemantics: true,
            child: _TapScale(
              scale: _kScaleCard,
              onTap: () {
                HapticUtil.light();
                final s = ref
                    .read(statementProvider(widget.statementId))
                    .valueOrNull;
                final fId = s?.figureId;
                if (s == null || fId == null || !mounted) return;
                context.push(
                  AppRoutes.figureProfilePath(fId),
                );
              },
              child: Container(
                width: _kAvatarSize,
                height: _kAvatarSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: BaselineColors.teal,
                    width: _kAvatarBorderWidth,
                  ),
                ),
                child: ClipOval(
                  child: BaselineIcon(
                    BaselineIconType.person,
                    size: 24,
                    color: BaselineColors.textSecondary,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════
  // §2 QUOTE CARD (primary intelligence excerpt)
  // ══════════════════════════════════════════════════════════

  Widget _buildQuoteCard(dynamic stmt) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: BaselineSpacing.lg,
      ),
      child: _TapScale(
        scale: _kScaleCard,
        onTap: () {}, // No-op: taps go to children.
        onLongPress: () => _shareSnippet(stmt.figureName),
        child: CustomPaint(
          foregroundPainter: _CompoundReticlePainter(
            color: BaselineColors.teal.atOpacity(0.06),
          ),
          child: Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: BaselineColors.card,
                  border: Border.all(
                    color: BaselineColors.teal.atOpacity(0.04),
                    width: 0.5,
                  ),
                  borderRadius: BorderRadius.circular(BaselineRadius.md),
                ),
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // ── Left accent ruler ──
                      // IntrinsicHeight gives the Row bounded height
                      // from the Expanded sibling, allowing stretch to
                      // size the ruler correctly in unbounded scroll context.
                      CustomPaint(
                        size: const Size(3, 0),
                        painter: _AccentRulerPainter(
                          color: BaselineColors.teal.atOpacity(0.20),
                        ),
                      ),

                    // ── Content ──
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(
                          BaselineSpacing.lg,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Classification label.
                            Align(
                              alignment: Alignment.centerRight,
                              child: Text(
                                'RECORDED STATEMENT',
                                style: BaselineTypography.dataSmall
                                    .copyWith(
                                  color: BaselineColors.teal
                                      .atOpacity(0.12),
                                  letterSpacing: 1.5,
                                ),
                              ),
                            ),
                            const SizedBox(height: BaselineSpacing.sm),

                            // Opening quote glyph.
                            CustomPaint(
                              size: const Size(18, 14),
                              painter: _QuoteGlyphPainter(
                                color: BaselineColors.teal
                                    .atOpacity(0.10),
                              ),
                            ),
                            const SizedBox(height: BaselineSpacing.xs),

                            // Statement text.
                            SelectableText(
                              stmt.statementText,
                              style: BaselineTypography.body1.copyWith(
                                color: BaselineColors.textPrimary,
                                height: 1.6,
                              ),
                            ),
                            const SizedBox(height: BaselineSpacing.xs),

                            // Closing quote glyph.
                            Align(
                              alignment: Alignment.centerRight,
                              child: Transform(
                                alignment: Alignment.center,
                                transform: Matrix4.rotationZ(math.pi),
                                child: CustomPaint(
                                  size: const Size(18, 14),
                                  painter: _QuoteGlyphPainter(
                                    color: BaselineColors.teal
                                        .atOpacity(0.10),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: BaselineSpacing.md),

                            // Source + date metadata row.
                            Row(
                              children: [
                                Flexible(
                                  child: stmt.sourceUrl != null
                                      ? SourceBadge(
                                          sourceUrl: stmt.sourceUrl!,
                                        )
                                      : Text(
                                          'Source',
                                          style: BaselineTypography
                                              .caption
                                              .copyWith(
                                            color: BaselineColors
                                                .textSecondary,
                                          ),
                                        ),
                                ),
                                const Spacer(),
                                Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      _fmtDateMDY(
                                        stmt.statedAt.toLocal(),
                                      ),
                                      style: BaselineTypography.caption
                                          .copyWith(
                                        color: BaselineColors
                                            .textSecondary,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      _cachedDtg,
                                      style: BaselineTypography.dataSmall
                                          .copyWith(
                                        color: BaselineColors
                                            .textSecondary
                                            .atOpacity(0.3),
                                        letterSpacing: 0.8,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),

                            // SID micro-label.
                            const SizedBox(height: BaselineSpacing.xs),
                            Text(
                              'SID-$_sid',
                              style: BaselineTypography.dataSmall
                                  .copyWith(
                                color: BaselineColors.textSecondary
                                    .atOpacity(0.12),
                                letterSpacing: 1.0,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    ],
                  ),
                ),
              ),

              // Holographic seal watermark (cherry #121).
              Positioned(
                right: 16,
                bottom: 16,
                child: ExcludeSemantics(
                  child: CustomPaint(
                    size: const Size(24, 24),
                    painter: _HolographicSealPainter(
                      color: BaselineColors.teal.atOpacity(0.03),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════
  // TOPIC CHIPS
  // ══════════════════════════════════════════════════════════

  Widget _buildTopicChips(List<String> topics) {
    return SizedBox(
      height: _kTopicChipHeight,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(
          horizontal: BaselineSpacing.lg,
        ),
        itemCount: topics.length,
        separatorBuilder: (_, _) =>
            const SizedBox(width: BaselineSpacing.xs),
        itemBuilder: (_, idx) {
          final label = kTopicDisplayNames[topics[idx]] ??
              topics[idx]
                  .replaceAll('_', ' ')
                  .split(' ')
                  .map((w) => w.isNotEmpty
                      ? '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}'
                      : '')
                  .join(' ');
          return Semantics(
            label: 'Topic: $label',
            excludeSemantics: true,
            child: _TapScale(
              scale: _kScaleChip,
              onTap: () => HapticUtil.light(),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: BaselineSpacing.sm,
                  vertical: BaselineSpacing.xxs,
                ),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: BaselineColors.teal.atOpacity(0.15),
                  ),
                  borderRadius: BaselineRadius.cardBorderRadius,
                ),
                alignment: Alignment.center,
                child: Text(
                  label,
                  style: BaselineTypography.caption.copyWith(
                    color: BaselineColors.textSecondary,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ══════════════════════════════════════════════════════════
  // FILM PERF DIVIDER + CONNECTOR DOT
  // ══════════════════════════════════════════════════════════

  Widget _buildFilmPerfDivider() {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: BaselineSpacing.lg,
        vertical: BaselineSpacing.sm,
      ),
      child: SizedBox(
        height: _kPerfHeight,
        child: CustomPaint(
          painter: _FilmPerfDividerPainter(
            color: BaselineColors.teal.atOpacity(0.06),
          ),
        ),
      ),
    );
  }

  /// Cherry #118: Registration alignment connector dot.
  Widget _buildConnectorDot() {
    return Center(
      child: ExcludeSemantics(
        child: Container(
          width: 2, height: 2,
          decoration: BoxDecoration(
            color: BaselineColors.teal.atOpacity(0.12),
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════
  // §4 SIGNAL INSTRUMENT PANEL
  // ══════════════════════════════════════════════════════════

  Widget _buildSignalPanel(dynamic consensus, List analyses) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: BaselineSpacing.lg,
      ),
      child: CustomPaint(
        foregroundPainter: _InstrumentPanelPainter(
          color: BaselineColors.teal.atOpacity(0.04),
        ),
        child: Padding(
          padding: const EdgeInsets.all(BaselineSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with circuit trace.
              Semantics(
                button: true,
                label: 'Signal Analysis information',
                excludeSemantics: true,
                child: GestureDetector(
                  onTap: () {
                    HapticUtil.light();
                    InfoBottomSheet.show(
                      context, key: 'signal_chips',
                    );
                  },
                  behavior: HitTestBehavior.opaque,
                  child: Row(
                    children: [
                      // Registration dot.
                      Container(
                        width: 3, height: 3,
                        decoration: BoxDecoration(
                          color: BaselineColors.teal.atOpacity(0.15),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'SIGNAL ANALYSIS',
                        style: BaselineTypography.dataSmall.copyWith(
                          color: BaselineColors.teal.atOpacity(0.40),
                          letterSpacing: 2.0,
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Circuit trace connector.
                      Expanded(
                        child: Container(
                          height: 0.5,
                          color: BaselineColors.teal.atOpacity(0.08),
                        ),
                      ),
                      const SizedBox(width: 4),
                      // Terminal dot.
                      Container(
                        width: 3, height: 3,
                        decoration: BoxDecoration(
                          color: BaselineColors.teal.atOpacity(0.12),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      BaselineIcon(
                        BaselineIconType.info,
                        size: 16,
                        color: BaselineColors.textSecondary.atOpacity(0.4),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: BaselineSpacing.xs),

              // Boot text (cherry #122).
              AnimatedBuilder(
                animation: _countUp,
                builder: (_, _) => ExcludeSemantics(
                  child: Text(
                    _countUp.value < 1.0 ? 'INITIALIZING...' : 'ONLINE',
                    style: BaselineTypography.dataSmall.copyWith(
                      color: _countUp.value < 1.0
                          ? BaselineColors.teal.atOpacity(0.15)
                          : BaselineColors.teal.atOpacity(0.25),
                      letterSpacing: 1.5,
                      fontSize: 7,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: BaselineSpacing.sm),

              // 2×2 signal chip grid with count-up.
              GridView.count(
                crossAxisCount: _kSignalChipColumns,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: BaselineSpacing.sm,
                crossAxisSpacing: BaselineSpacing.sm,
                childAspectRatio: 2.8,
                children: [
                  _countUpChip('Repetition',
                      consensus.repetitionAvg, 'repetition'),
                  _countUpChip('Novelty',
                      consensus.noveltyAvg, 'novelty'),
                  _countUpChip('Affect',
                      consensus.affectiveLanguageRateAvg, 'affect'),
                  _countUpChip('Entropy',
                      consensus.topicEntropyAvg, 'entropy'),
                ],
              ),
              const SizedBox(height: BaselineSpacing.md),

              // MeasuredByRow (A-7).
              if (analyses.isNotEmpty)
                MeasuredByRow(
                  modelProviders: analyses
                      .map((a) => a.modelProvider as String)
                      .toList(),
                  analyzedAt: analyses.first.analyzedAt,
                ),
              if (analyses.isNotEmpty)
                const SizedBox(height: BaselineSpacing.sm),
            ],
          ),
        ),
      ),
    );
  }

  Widget _countUpChip(String label, double val, String key) {
    return _TapScale(
      scale: _kScaleChip,
      onTap: () {
        HapticUtil.light();
        InfoBottomSheet.show(context, key: key);
      },
      child: AnimatedBuilder(
        animation: _countUp,
        builder: (_, _) => SignalChip(
          label: label,
          value: val * _countUp.value,
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════
  // VARIANCE BANNER
  // ══════════════════════════════════════════════════════════

  Widget _buildVarianceBanner() {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: BaselineSpacing.lg,
      ),
      child: Semantics(
        button: true,
        label: 'Variance detected between AI models. Tap for details.',
        excludeSemantics: true,
        child: _TapScale(
          scale: _kScaleCard,
          onTap: () {
            HapticUtil.light();
            InfoBottomSheet.show(context, key: 'variance_detected');
          },
          child: Container(
            padding: const EdgeInsets.all(BaselineSpacing.md),
            margin: const EdgeInsets.only(bottom: BaselineSpacing.md),
            decoration: BoxDecoration(
              color: BaselineColors.card,
              border: Border.all(
                color: BaselineColors.warning, width: 2,
              ),
              borderRadius: BorderRadius.circular(BaselineRadius.md),
            ),
            child: Row(
              children: [
                BaselineIcon.amber(
                  BaselineIconType.warning,
                  size: 20,
                ),
                const SizedBox(width: BaselineSpacing.sm),
                Expanded(
                  child: Text(
                    'Variance Detected',
                    style: BaselineTypography.body2.copyWith(
                      color: BaselineColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                BaselineIcon(
                  BaselineIconType.info,
                  size: 16,
                  color: BaselineColors.textSecondary.atOpacity(0.5),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════
  // §5 ACTION BAR
  // ══════════════════════════════════════════════════════════

  Widget _buildActionBar(dynamic stmt) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: BaselineSpacing.lg,
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Connector trace behind buttons (cherry #123).
          ExcludeSemantics(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: _kActionButtonSize,
              ),
              child: Container(
                height: 0.5,
                color: BaselineColors.teal.atOpacity(0.06),
              ),
            ),
          ),
          // Buttons.
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _ActionBtn(
                iconType: BaselineIconType.export,
                label: 'EXPORT',
                onTap: () => _exportFull(stmt.figureName),
              ),
              const SizedBox(width: BaselineSpacing.xl),
              _ActionBtn(
                iconType: BaselineIconType.cite,
                label: 'CITE',
                onTap: () => _copyWithCitation(
                  stmt.statementText,
                  stmt.figureName,
                  stmt.statedAt,
                ),
              ),
              const SizedBox(width: BaselineSpacing.xl),
              _ActionBtn(
                iconType: BaselineIconType.share,
                label: 'SHARE',
                onTap: () => _exportFull(stmt.figureName),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════
  // §6 COMMAND CONSOLE (feature hub)
  // ══════════════════════════════════════════════════════════

  Widget _buildCommandConsole(dynamic consensus) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: BaselineSpacing.lg,
      ),
      child: CustomPaint(
        foregroundPainter: _CompoundReticlePainter(
          color: BaselineColors.teal.atOpacity(0.05),
        ),
        child: Container(
          padding: const EdgeInsets.all(BaselineSpacing.lg),
          decoration: BoxDecoration(
            color: BaselineColors.card,
            border: Border.all(
              color: BaselineColors.teal.atOpacity(0.12),
              width: 2,
            ),
            borderRadius: BorderRadius.circular(BaselineRadius.lg),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Console designation.
              ExcludeSemantics(
                child: Text(
                  'ANALYSIS MODULES',
                  style: BaselineTypography.dataSmall.copyWith(
                    color: BaselineColors.teal.atOpacity(0.20),
                    letterSpacing: 2.0,
                  ),
                ),
              ),
              const SizedBox(height: BaselineSpacing.md),

              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Consensus badge.
                  if (consensus != null)
                    Column(
                      children: [
                        Semantics(
                          button: true,
                          label: 'Lens Convergence score',
                          excludeSemantics: true,
                          child: GestureDetector(
                            onTap: () {
                              HapticUtil.light();
                              InfoBottomSheet.show(
                                context, key: 'lens_convergence',
                              );
                            },
                            child: AnimatedBuilder(
                              animation: _ambient,
                              builder: (_, _) {
                                return Transform.scale(
                                  scale: _reduceMotion
                                      ? 1.0
                                      : _consensusBreath.value,
                                  child: ConsensusBadge(
                                    modelCount: consensus.modelCount,
                                    size: _kConsensusBadgeSize,
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: BaselineSpacing.xs),
                        Semantics(
                          button: true,
                          label: 'Lens Convergence information',
                          excludeSemantics: true,
                          child: GestureDetector(
                            onTap: () {
                              HapticUtil.light();
                              InfoBottomSheet.show(
                                context, key: 'lens_convergence',
                              );
                            },
                            behavior: HitTestBehavior.opaque,
                            child: Text(
                              'LENS\nCONVERGENCE',
                              textAlign: TextAlign.center,
                              style:
                                  BaselineTypography.dataSmall.copyWith(
                                color: BaselineColors.textSecondary,
                                letterSpacing: 1.0,
                                height: 1.3,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  if (consensus != null)
                    const SizedBox(width: BaselineSpacing.lg),

                  // Navigation channels.
                  Expanded(
                    child: Column(
                      children: [
                        _NavChannel(
                          title: 'The Receipt™',
                          onTap: () {
                            HapticUtil.light();
                            context.push(
                              AppRoutes.receiptPath(widget.statementId),
                            );
                          },
                          infoKey: 'receipt',
                        ),
                        _buildChannelDivider(),
                        _NavChannel(
                          title: 'Framing Radar™',
                          onTap: () {
                            HapticUtil.light();
                            final s = ref
                                .read(statementProvider(
                                    widget.statementId))
                                .valueOrNull;
                            if (s == null || s.figureId == null) return;
                            context.push(
                              AppRoutes.framingRadarPath(s.figureId!),
                            );
                          },
                          infoKey: 'framing_radar',
                        ),
                        _buildChannelDivider(),
                        _NavChannel(
                          title: 'Lens Lab™',
                          tier: 'pro',
                          onTap: () {
                            HapticUtil.light();
                            context.push(
                              AppRoutes.lensLabPath(widget.statementId),
                            );
                          },
                          infoKey: 'lens_lab',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChannelDivider() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: CustomPaint(
        size: const Size(double.infinity, 1),
        painter: _HashDividerPainter(
          color: BaselineColors.borderInactive.atOpacity(0.15),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════
  // HANDLING MARK + DOCUMENT SERIAL + ACCESS STAMP
  // ══════════════════════════════════════════════════════════

  Widget _buildHandlingMark() {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: BaselineSpacing.lg,
        vertical: BaselineSpacing.xs,
      ),
      child: Center(
        child: ExcludeSemantics(
          child: Text(
            'HANDLE VIA BASELINE CHANNELS ONLY',
            style: BaselineTypography.dataSmall.copyWith(
              color: BaselineColors.teal.atOpacity(0.08),
              letterSpacing: 2.0,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDocumentSerial() {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: BaselineSpacing.lg,
      ),
      child: Center(
        child: ExcludeSemantics(
          child: Text(
            _cachedSerial,
            style: BaselineTypography.dataSmall.copyWith(
              color: BaselineColors.textSecondary.atOpacity(0.10),
              letterSpacing: 1.0,
            ),
          ),
        ),
      ),
    );
  }

  /// Cherry #117: Document access stamp.
  Widget _buildAccessStamp() {
    return Padding(
      padding: const EdgeInsets.only(top: BaselineSpacing.md),
      child: Center(
        child: ExcludeSemantics(
          child: Transform.rotate(
            angle: -0.035, // ~2 degrees.
            child: Text(
              'ACCESSED $_cachedDtg',
              style: BaselineTypography.dataSmall.copyWith(
                color: BaselineColors.teal.atOpacity(0.06),
                letterSpacing: 2.0,
                fontSize: 7,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// NAVIGATION CHANNEL ROW
// ═══════════════════════════════════════════════════════════

class _NavChannel extends StatelessWidget {
  const _NavChannel({
    required this.title,
    required this.onTap,
    required this.infoKey,
    this.tier,
  });

  final String title;
  final VoidCallback onTap;
  final String infoKey;
  final String? tier;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: tier != null
          ? '$title, requires ${kTierDisplayNames[tier] ?? tier}'
          : title,
      excludeSemantics: true,
      child: _TapScale(
        scale: _kScaleCard,
        onTap: onTap,
        child: SizedBox(
          height: _kNavRowHeight,
          child: Row(
            children: [
              // Channel indicator dot.
              Container(
                width: 3, height: 3,
                decoration: BoxDecoration(
                  color: BaselineColors.teal.atOpacity(0.25),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),

              // Title + tier.
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: BaselineTypography.body1.copyWith(
                          color: BaselineColors.textPrimary,
                        ),
                      ),
                    ),
                    if (tier != null) ...[
                      const SizedBox(width: BaselineSpacing.xs),
                      TierBadge(tier: tier!),
                    ],
                  ],
                ),
              ),

              // Info icon from F_ICONS.
              GestureDetector(
                onTap: () {
                  HapticUtil.light();
                  InfoBottomSheet.show(context, key: infoKey);
                },
                behavior: HitTestBehavior.opaque,
                child: SizedBox(
                  width: _kIconTouchTarget,
                  height: _kIconTouchTarget,
                  child: Center(
                    child: BaselineIcon(
                      BaselineIconType.info,
                      size: 16,
                      color: BaselineColors.textSecondary,
                    ),
                  ),
                ),
              ),

              // Terminal arrow.
              Text(
                '→',
                style: BaselineTypography.data.copyWith(
                  color: BaselineColors.teal.atOpacity(0.35),
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
// ACTION BUTTON (refactored: BaselineIconType, not CustomPainter)
// ═══════════════════════════════════════════════════════════

class _ActionBtn extends StatelessWidget {
  const _ActionBtn({
    required this.iconType,
    required this.label,
    required this.onTap,
  });

  final BaselineIconType iconType;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true, label: label,
      excludeSemantics: true,
      child: _TapScale(
        scale: _kScaleCard,
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: _kActionButtonSize,
              height: _kActionButtonSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: BaselineColors.teal.atOpacity(0.15),
                  width: 1.5,
                ),
              ),
              child: Center(
                child: BaselineIcon.teal(
                  iconType,
                  size: _kActionIconSize,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: BaselineTypography.dataSmall.copyWith(
                color: BaselineColors.textSecondary.atOpacity(0.5),
                letterSpacing: 1.0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// TAP SCALE (reusable press-scale button)
// ═══════════════════════════════════════════════════════════

class _TapScale extends StatefulWidget {
  const _TapScale({
    required this.scale,
    required this.onTap,
    required this.child,
    this.onLongPress,
  });

  final double scale;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final Widget child;

  @override
  State<_TapScale> createState() => _TapScaleState();
}

class _TapScaleState extends State<_TapScale> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapUp: (_) {
        setState(() => _down = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _down = false),
      onLongPress: widget.onLongPress,
      behavior: HitTestBehavior.opaque,
      child: AnimatedScale(
        scale: _down ? widget.scale : 1.0,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeInOut,
        child: widget.child,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// PAINTERS
// ═══════════════════════════════════════════════════════════

/// Screen-level classified document chrome. 7-layer single-pass.
/// Static Paints cached as finals (I-71). Gradients replaced with
/// math-based alpha bands (F4.6 A2-I1 precedent).
class _DocumentChromePainter extends CustomPainter {
  _DocumentChromePainter({
    required this.ambientProgress,
    required this.scanlineProgress,
    required this.sid,
    required this.dtg,
  })  : _perfPaint = Paint()
          ..color = BaselineColors.teal.atOpacity(0.03)
          ..style = PaintingStyle.fill,
        _dotPaint = Paint()
          ..color = BaselineColors.teal.atOpacity(0.03),
        _reticlePaint = Paint()
          ..color = BaselineColors.teal.atOpacity(0.04)
          ..strokeWidth = 0.5
          ..strokeCap = StrokeCap.round,
        _hairPaint = Paint()
          ..color = BaselineColors.teal.atOpacity(0.03)
          ..strokeWidth = 0.5,
        _rulerPaint = Paint()
          ..color = BaselineColors.teal.atOpacity(0.03)
          ..strokeWidth = 0.5;

  final double ambientProgress;
  final double scanlineProgress;
  final String sid;
  final String dtg;

  // Static Paints (I-71).
  final Paint _perfPaint;
  final Paint _dotPaint;
  final Paint _reticlePaint;
  final Paint _hairPaint;
  final Paint _rulerPaint;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // ── 1. Film perforations (left edge) ──
    for (var i = 0; i < _kPerfCount; i++) {
      final y = 60.0 + i * _kPerfSpacing;
      canvas.drawRect(
        Rect.fromLTWH(
          _kPerfInsetLeft, y, _kPerfWidth, _kPerfHeight,
        ),
        _perfPaint,
      );
    }

    // ── 2. Intel dot grid (top-right) ──
    for (var r = 0; r < _kIntelDotGrid; r++) {
      for (var c = 0; c < _kIntelDotGrid; c++) {
        canvas.drawCircle(
          Offset(
            w - 20 - c * _kIntelDotSpacing,
            20.0 + r * _kIntelDotSpacing,
          ),
          _kIntelDotSize,
          _dotPaint,
        );
      }
    }

    // ── 3. Compound reticle corners ──
    _drawCompoundCorner(canvas, 16, 16, 1, 1);
    _drawCompoundCorner(canvas, w - 16, 16, -1, 1);
    _drawCompoundCorner(canvas, 16, h - 16, 1, -1);
    _drawCompoundCorner(canvas, w - 16, h - 16, -1, -1);

    // ── 4. Classification hairlines ──
    canvas.drawLine(Offset(28, 16), Offset(w - 28, 16), _hairPaint);
    canvas.drawLine(
      Offset(28, h - 16), Offset(w - 28, h - 16), _hairPaint,
    );

    // ── 5. Hashmark ruler (bottom) ──
    for (var i = 0; i < _kRulerTicks; i++) {
      final x = w * (i + 1) / (_kRulerTicks + 1);
      canvas.drawLine(
        Offset(x, h - 16 - _kRulerTickHeight),
        Offset(x, h - 16),
        _rulerPaint,
      );
    }

    // ── 6. Monitoring pulse (math-based alpha bands) ──
    if (ambientProgress > 0) {
      final pulseY = 60 + (h - 120) * ambientProgress;
      const halfSpan = 30.0;
      const steps = 6;
      for (var i = 0; i < steps; i++) {
        final frac = i / (steps - 1);
        final dist = (frac - 0.5).abs() * 2.0;
        final alpha = 0.06 * (1.0 - dist * dist);
        if (alpha < 0.004) continue;
        final bandY = pulseY - halfSpan + frac * halfSpan * 2;
        canvas.drawRect(
          Rect.fromLTWH(0, bandY, 2, halfSpan * 2 / steps),
          Paint()..color = BaselineColors.teal.atOpacity(alpha),
        );
      }
    }

    // ── 7. Entry scanline (math-based alpha bands) ──
    if (scanlineProgress > 0 && scanlineProgress < 1.0) {
      final beamY = scanlineProgress * h;
      final peakAlpha = 0.15 * (1.0 - scanlineProgress);
      if (peakAlpha > 0.01) {
        // Main beam core.
        canvas.drawRect(
          Rect.fromLTWH(w * 0.15, beamY - 0.5, w * 0.70, 1),
          Paint()..color = BaselineColors.teal.atOpacity(peakAlpha),
        );
        // Glow bands above/below (cherry #120: shadow trail).
        for (var i = 1; i <= 4; i++) {
          final fade = peakAlpha * (i <= 2 ? 0.3 : 0.08) *
              (1.0 - i / 5.0);
          if (fade < 0.004) continue;
          canvas.drawRect(
            Rect.fromLTWH(0, beamY - 2.5 * i, w, 2),
            Paint()..color = BaselineColors.teal.atOpacity(fade),
          );
          canvas.drawRect(
            Rect.fromLTWH(0, beamY + 2.5 * i, w, 2),
            Paint()..color = BaselineColors.teal.atOpacity(fade),
          );
        }
      }
    }
  }

  void _drawCompoundCorner(
    Canvas c, double x, double y, double dx, double dy,
  ) {
    // Outer L.
    c.drawLine(
      Offset(x, y), Offset(x + _kReticleArm * dx, y), _reticlePaint,
    );
    c.drawLine(
      Offset(x, y), Offset(x, y + _kReticleArm * dy), _reticlePaint,
    );
    // Inner tick.
    c.drawLine(
      Offset(x + 2 * dx, y + 2 * dy),
      Offset(x + (_kReticleInnerTick + 2) * dx, y + 2 * dy),
      _reticlePaint,
    );
    c.drawLine(
      Offset(x + 2 * dx, y + 2 * dy),
      Offset(x + 2 * dx, y + (_kReticleInnerTick + 2) * dy),
      _reticlePaint,
    );
    // Corner dot.
    c.drawCircle(
      Offset(x, y),
      _kCornerDotRadius,
      _reticlePaint..style = PaintingStyle.fill,
    );
    _reticlePaint.style = PaintingStyle.stroke;
  }

  @override
  bool shouldRepaint(_DocumentChromePainter old) =>
      ambientProgress != old.ambientProgress ||
      scanlineProgress != old.scanlineProgress;
}

/// Compound reticle corners + registration dots on cards.
class _CompoundReticlePainter extends CustomPainter {
  _CompoundReticlePainter({required this.color})
      : _paint = Paint()
          ..color = color
          ..strokeWidth = 0.5
          ..strokeCap = StrokeCap.round;

  final Color color;
  final Paint _paint;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    for (final corner in [
      [0.0, 0.0, 1.0, 1.0],
      [w, 0.0, -1.0, 1.0],
      [0.0, h, 1.0, -1.0],
      [w, h, -1.0, -1.0],
    ]) {
      final x = corner[0], y = corner[1];
      final dx = corner[2], dy = corner[3];
      // Outer L.
      canvas.drawLine(Offset(x, y), Offset(x + 6 * dx, y), _paint);
      canvas.drawLine(Offset(x, y), Offset(x, y + 6 * dy), _paint);
      // Dot.
      canvas.drawCircle(
        Offset(x, y), 0.8, _paint..style = PaintingStyle.fill,
      );
      _paint.style = PaintingStyle.stroke;
    }
  }

  @override
  bool shouldRepaint(_CompoundReticlePainter old) =>
      color != old.color;
}

/// Left accent ruler with hashmark ticks.
class _AccentRulerPainter extends CustomPainter {
  _AccentRulerPainter({required this.color})
      : _barPaint = Paint()..color = color,
        _tickPaint = Paint()
          ..color = color.atOpacity(0.5)
          ..strokeWidth = 0.5;

  final Color color;
  final Paint _barPaint;
  final Paint _tickPaint;

  @override
  void paint(Canvas canvas, Size size) {
    // Solid accent bar.
    canvas.drawRect(Offset.zero & size, _barPaint);
    // Hashmark ticks every 12px.
    for (double y = 12; y < size.height; y += 12) {
      canvas.drawLine(
        Offset(0, y), Offset(size.width, y), _tickPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_AccentRulerPainter old) => color != old.color;
}

/// Instrument panel background frame.
class _InstrumentPanelPainter extends CustomPainter {
  _InstrumentPanelPainter({required this.color})
      : _barPaint = Paint()..color = color,
        _dotPaint = Paint()..color = color;

  final Color color;
  final Paint _barPaint;
  final Paint _dotPaint;

  @override
  void paint(Canvas canvas, Size size) {
    // Left accent glow.
    canvas.drawRect(
      Rect.fromLTWH(0, 0, 1, size.height),
      _barPaint,
    );
    // Registration dots.
    canvas.drawCircle(const Offset(0, 0), 1.5, _dotPaint);
    canvas.drawCircle(
      Offset(size.width, size.height), 1.5, _dotPaint,
    );
  }

  @override
  bool shouldRepaint(_InstrumentPanelPainter old) =>
      color != old.color;
}

/// Film perforation divider (horizontal row of rects).
class _FilmPerfDividerPainter extends CustomPainter {
  _FilmPerfDividerPainter({required this.color})
      : _paint = Paint()
          ..color = color
          ..style = PaintingStyle.fill;

  final Color color;
  final Paint _paint;

  @override
  void paint(Canvas canvas, Size size) {
    double x = 0;
    while (x < size.width) {
      canvas.drawRect(
        Rect.fromLTWH(x, 0, _kPerfWidth, _kPerfHeight),
        _paint,
      );
      x += _kPerfWidth + _kPerfSpacing;
    }
  }

  @override
  bool shouldRepaint(_FilmPerfDividerPainter old) =>
      color != old.color;
}

/// Hashmark dash divider.
class _HashDividerPainter extends CustomPainter {
  _HashDividerPainter({required this.color})
      : _paint = Paint()
          ..color = color
          ..strokeWidth = 0.5;

  final Color color;
  final Paint _paint;

  @override
  void paint(Canvas canvas, Size size) {
    double x = 0;
    while (x < size.width) {
      canvas.drawLine(
        Offset(x, 0.5), Offset(x + _kHashDash, 0.5), _paint,
      );
      x += _kHashDash + _kHashGap;
    }
  }

  @override
  bool shouldRepaint(_HashDividerPainter old) => color != old.color;
}

/// Painted quote glyph (double-comma form). Unique to F4.7.
class _QuoteGlyphPainter extends CustomPainter {
  const _QuoteGlyphPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.height * 0.25;
    final gap = size.width * 0.5;
    final paint = Paint()..color = color;
    final strokeP = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.4
      ..strokeCap = StrokeCap.round;

    for (final xOff in [0.0, gap]) {
      final cx = xOff + r + 2;
      canvas.drawCircle(Offset(cx, r), r, paint);
      final tail = Path()
        ..moveTo(cx + r * 0.2, r + r * 0.5)
        ..quadraticBezierTo(
          cx - r * 0.4, r + r * 2.2,
          cx - r * 0.8, r + r * 2.5,
        );
      canvas.drawPath(tail, strokeP);
    }
  }

  @override
  bool shouldRepaint(_QuoteGlyphPainter old) => color != old.color;
}

/// Cherry #121: Holographic seal watermark (3 concentric rings).
class _HolographicSealPainter extends CustomPainter {
  _HolographicSealPainter({required this.color})
      : _paint = Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.5;

  final Color color;
  final Paint _paint;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    for (var i = 1; i <= _kSealRingCount.toInt(); i++) {
      canvas.drawCircle(center, 3.0 * i, _paint);
    }
  }

  @override
  bool shouldRepaint(_HolographicSealPainter old) =>
      color != old.color;
}
