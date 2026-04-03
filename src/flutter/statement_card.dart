/// F2.9: Statement Card (Intelligence Briefing Card): LOCKED
///
/// THE SINGLE MOST IMPORTANT WIDGET. Primary list item in Today Feed,
/// Search results, Figure Profile, everywhere. Users see this card 90%
/// of the time.
///
/// Concept: Classified intelligence briefing transmitted to your desk.
/// The pulse bar breathes with live activity. The scanline verifies on
/// entry, leaving phosphor residue as proof. The compound reticle
/// corners frame classified content. The film perforations mark it as
/// a document. The avatar ring pulses with rhetorical activity. The
/// bookmark flag lets you file the briefing. Every pixel serves the
/// reading.
///
/// Visual layers (painted bottom to top):
///   1.  Top edge highlight (machined catch-light)
///   2.  Film perforation marks (right edge)
///   3.  Intel dot grid (top-right texture)
///   4.  Compound reticle corners + registration dots (classified framing)
///   5.  Activity beacon (monitoring station indicator)
///   6.  Pulse bar track + hashmark ruler (measurement baseline)
///   7.  Pulse bar fill + leading-edge glow (activity readout)
///   8.  Transmission receipt hairline + RCVD stamp (arrival provenance)
///   9.  Document serial stamp (filing index)
///   10. Entry scanline beam + phosphor wake (verification sweep)
///   11. Void hatch (revoked only)
///
/// 80 visual treatments. 11 painted layers. Classified document that
/// happens to be interactive.
///
/// Accessibility: Outer Semantics(container: true) groups the card.
/// Decorative text/chrome wrapped in ExcludeSemantics. Bookmark has
/// its own Semantics(button: true) node with onTap, exposed to the
/// accessibility tree independently of the card's main tap action.
///
/// Composes: SignalPulseWidget (FE-3), SourceBadge (F2.6),
///           SignalChip (F2.2), HapticUtil.
///
/// Patches: FE-3 . FE-5 . FE-8 . FE-10 . FE-12 . Hitlist #13.
///
/// Path: lib/widgets/statement_card.dart
library;

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:baseline_app/config/theme.dart';
import 'package:baseline_app/utils/haptic_util.dart';
import 'package:baseline_app/widgets/signal_chip.dart';
import 'package:baseline_app/widgets/signal_pulse_widget.dart';
import 'package:baseline_app/widgets/source_badge.dart';

// ═══════════════════════════════════════════════════════════
// CONSTANTS
// ═══════════════════════════════════════════════════════════

// ── Card chrome ─────────────────────────────────────────

const double _kReticleArm = 4.0;
const double _kReticleStroke = 0.5;
const double _kReticleOpacity = 0.10;
const double _kReticleInnerTick = 1.5;
const double _kReticleInnerStroke = 0.3;
const double _kReticleInnerOpacity = 0.06;
const double _kRegDotRadius = 1.0;
const double _kRegDotOpacity = 0.08;

const double _kIntelDotRadius = 0.5;
const double _kIntelDotOpacity = 0.03;
const int _kIntelDotCols = 3;
const int _kIntelDotRows = 2;
const double _kIntelDotSpacing = 6.0;
const double _kIntelDotInset = 8.0;

const double _kPerfSize = 2.0;
const double _kPerfSpacing = 8.0;
const int _kPerfCount = 3;
const double _kPerfOpacity = 0.05;
const double _kPerfInsetRight = 5.0;

/// Edge highlight uses literal white. This is a physical light
/// reflection (catch-light), not a brand color. Intentional hardcode.
const double _kEdgeHighlightStroke = 0.3;

// ── Activity beacon ────────────────────────────────────

const double _kBeaconRadius = 1.5;
const double _kBeaconMinOpacity = 0.04;
const double _kBeaconMaxOpacity = 0.14;
const double _kBeaconInsetX = 6.0;
const double _kBeaconInsetY = 6.0;

// ── Pulse bar (FE-8) ────────────────────────────────────

const double _kPulseBarHeight = 3.0;
const double _kPulseBarRadius = 1.5;
const double _kPulseBarGlowSigma = 3.0;
const double _kPulseBarGlowOpacity = 0.30;
const double _kPulseBarTrackOpacity = 0.08;
const double _kPulseBarMinActivity = 0.02;

const int _kPulseBarTicks = 5;
const double _kTickHeight = 3.0;
const double _kTickStroke = 0.3;
const double _kTickOpacity = 0.06;

const double _kBreathMin = 0.55;
const double _kBreathMax = 0.70;

/// Ambient animation starts when activity >= this threshold.
/// Uses hysteresis: starts at 0.10, stops at 0.07 to prevent
/// floating-point thrashing at the boundary. [B2 audit fix]
const double _kAmbientStartThreshold = 0.10;
const double _kAmbientStopThreshold = 0.07;

// ── Scanline + phosphor wake ───────────────────────────

const double _kScanlineHeight = 2.0;
const double _kScanlineOpacity = 0.15;
const double _kScanlineGlowSigma = 2.0;
const double _kScanlineStart = 0.20;
const double _kScanlineEnd = 0.85;
const double _kPhosphorWakeWidth = 6.0;
const double _kPhosphorWakeOpacity = 0.04;

// ── Transmission receipt ───────────────────────────────

const double _kReceiptLineY = 0.92;
const double _kReceiptDashWidth = 3.0;
const double _kReceiptDashGap = 4.0;
const double _kReceiptStroke = 0.3;
const double _kReceiptOpacity = 0.04;
const double _kReceiptLabelOpacity = 0.035;

// ── Document serial ────────────────────────────────────

const double _kSerialOpacity = 0.04;
const double _kSerialFontSize = 4.5;

// ── Teal flash (FE-5) ──────────────────────────────────

const double _kFlashPeakOpacity = 0.45;
const Duration _kFlashDuration = Duration(milliseconds: 400);

// ── Entry ───────────────────────────────────────────────

const Duration _kEntryDuration = Duration(milliseconds: 350);
const double _kEntrySlide = 6.0;
const Duration _kStaggerInterval = Duration(milliseconds: 40);
const int _kMaxStaggerIndex = 20;

// ── Ambient ─────────────────────────────────────────────

const Duration _kAmbientDuration = Duration(milliseconds: 2800);

// ── Avatar ──────────────────────────────────────────────

const double _kAvatarDiameter = 40.0;

// ── Bookmark ────────────────────────────────────────────

const double _kBookmarkSize = 18.0;
const double _kBookmarkTouchTarget = 44.0;
const double _kBookmarkStroke = 1.2;
const double _kBookmarkIdleOpacity = 0.18;
const double _kBookmarkActiveOpacity = 0.70;

// ── Credential underline ───────────────────────────────

/// Decorative micro-engraving (0.3px), not structural 2px border.
/// Simulates engraved inscription on a nameplate. Documented
/// exception to 2px border doctrine. [A3 audit fix]
const double _kCredLineStroke = 0.3;
const double _kCredLineOpacity = 0.12;

// ── Layout ──────────────────────────────────────────────

const double _kCardPadH = 14.0;
const double _kCardPadV = 12.0;
const double _kCardPadTop = 4.0;
const double _kCardPadHCompact = 12.0;
const double _kCardPadVCompact = 8.0;
const double _kCardPadTopCompact = 4.0;
const double _kClassFontSize = 7.0;
const double _kClassLetterSpacing = 1.2;
const double _kClassDotSize = 2.0;
const double _kAffordanceFontSize = 7.0;
const double _kDateLetterSpacing = 0.8;
const double _kRevokedOpacity = 0.55;
const double _kPressScale = 0.98;
const double _kTopicChipRadius = 10.0;
const double _kTopicMaxWidth = 140.0;

// ── Void hatch ──────────────────────────────────────────

const double _kHatchSpacing = 6.0;
const double _kHatchStroke = 0.3;
const double _kHatchOpacity = 0.06;

// ═══════════════════════════════════════════════════════════
// TOPIC DISPLAY HELPER
// ═══════════════════════════════════════════════════════════

String _topicDisplay(String raw) {
  const names = {
    'US_POLITICS': 'US Politics',
    'FOREIGN_POLICY': 'Foreign Policy',
    'CULTURE_SOCIETY': 'Culture & Society',
    'CLIMATE_ENVIRONMENT': 'Climate & Environment',
    'MILITARY_DEFENSE': 'Military & Defense',
    'AI_TECHNOLOGY': 'AI & Technology',
    'ECONOMY': 'Economy',
    'IMMIGRATION': 'Immigration',
    'HEALTHCARE': 'Healthcare',
    'CRIME_JUSTICE': 'Crime & Justice',
    'ELECTIONS': 'Elections',
    'EDUCATION': 'Education',
    'OTHER': 'Other',
  };
  return names[raw] ??
      raw
          .replaceAll('_', ' ')
          .split(' ')
          .map((w) =>
              w.isEmpty ? '' : '${w[0]}${w.substring(1).toLowerCase()}')
          .join(' ');
}

// ═══════════════════════════════════════════════════════════
// DATE FORMATTER
// ═══════════════════════════════════════════════════════════

String _formatDateCompact(DateTime dt) {
  const m = [
    'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
    'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC',
  ];
  final local = dt.toLocal();
  final h = local.hour;
  final period = h >= 12 ? 'PM' : 'AM';
  final h12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
  final min = local.minute.toString().padLeft(2, '0');
  return '${m[local.month - 1]} ${local.day} · $h12:$min $period';
}

// ═══════════════════════════════════════════════════════════
// STATEMENT CARD
// ═══════════════════════════════════════════════════════════

class StatementCard extends StatefulWidget {
  const StatementCard({
    super.key,
    required this.figureName,
    required this.statementText,
    this.sourceName = '',
    required this.sourceUrl,
    required this.statedAt,
    required this.onTap,
    this.figurePhotoUrl,
    this.figureActivityLevel = 0.0,
    this.topics = const [],
    this.signalRank,
    this.isRevoked = false,
    this.staggerIndex = 0,
    this.statementIdShort,
    this.favicon,
    this.onLongPress,
    this.isBookmarked = false,
    this.onBookmark,
    this.isCompact = false,
  })  : assert(
          figureActivityLevel >= 0.0 && figureActivityLevel <= 1.0,
          'figureActivityLevel must be 0.0\u20131.0',
        ),
        assert(
          signalRank == null || (signalRank >= 0 && signalRank <= 100),
          'signalRank must be 0\u2013100',
        ),
        assert(staggerIndex >= 0, 'staggerIndex must be non-negative');

  /// Compact card factory from a statement summary object.
  /// Used in Figure Profile where figure context is already shown.
  factory StatementCard.compact({
    Key? key,
    required dynamic statement,
    VoidCallback? onTap,
  }) {
    return StatementCard(
      key: key,
      figureName: '',
      statementText: statement.headline as String? ?? '',
      sourceUrl: statement.sourceUrl as String? ?? '',
      statedAt: statement.createdAt as DateTime? ?? DateTime.now(),
      onTap: onTap ?? () {},
      topics: (statement.topics as List<String>?) ?? const [],
      signalRank: statement.signalRank as double?,
      isCompact: true,
    );
  }

  final String figureName;
  final String? figurePhotoUrl;
  final double figureActivityLevel;
  final String statementText;
  final String sourceName;
  final String sourceUrl;
  final DateTime statedAt;
  final List<String> topics;
  final double? signalRank;
  final bool isRevoked;
  final int staggerIndex;
  final String? statementIdShort;
  final Widget? favicon;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool isBookmarked;
  final VoidCallback? onBookmark;

  /// Compact mode for Figure Profile context. Hides avatar and
  /// classification row since figure identity is already established.
  /// Tightens padding. Chrome layers fully preserved.
  final bool isCompact;

  @override
  State<StatementCard> createState() => _StatementCardState();
}

class _StatementCardState extends State<StatementCard>
    with TickerProviderStateMixin {
  bool _pressed = false;

  // ── Controllers ─────────────────────────────────────────
  late final AnimationController _entryCtrl;
  late final AnimationController _flashCtrl;
  late final AnimationController _ambientCtrl;
  Timer? _staggerTimer;

  /// Tracks whether a non-null signalRank has been received at least
  /// once. FE-5 flash only fires on CHANGES after the first load,
  /// not on initial data arrival. If the first frame includes a
  /// non-null signalRank, this flag sets but no flash occurs. [A5]
  bool _hasLoadedOnce = false;
  bool _tickerMuted = false;

  bool get _reduceMotion =>
      ui.PlatformDispatcher.instance.accessibilityFeatures.reduceMotion;

  // ═════════════════════════════════════════════════════════
  // LIFECYCLE
  // ═════════════════════════════════════════════════════════

  @override
  void initState() {
    super.initState();

    _entryCtrl = AnimationController(
      vsync: this,
      duration: _kEntryDuration,
    );

    _flashCtrl = AnimationController(
      vsync: this,
      duration: _kFlashDuration,
    );

    _ambientCtrl = AnimationController(
      vsync: this,
      duration: _kAmbientDuration,
    );

    // Entry -> ambient chain via status listener (not fragile .then()).
    _entryCtrl.addStatusListener(_onEntryStatus);

    if (_reduceMotion) {
      _entryCtrl.value = 1.0;
      // Ambient does NOT run under reduceMotion.
    } else {
      final delay = widget.staggerIndex.clamp(0, _kMaxStaggerIndex);
      if (delay == 0) {
        _entryCtrl.forward();
      } else {
        _staggerTimer = Timer(
          _kStaggerInterval * delay,
          () {
            if (mounted) _entryCtrl.forward();
          },
        );
      }
    }
  }

  void _onEntryStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _startAmbientIfNeeded();
    }
  }

  void _startAmbientIfNeeded() {
    if (!mounted) return;
    if (_reduceMotion) return;
    if (widget.isRevoked) return;
    if (widget.figureActivityLevel < _kAmbientStartThreshold) return;
    if (_ambientCtrl.isAnimating) return;

    _ambientCtrl.repeat(reverse: true);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // TickerMode: mute/resume all controllers when scrolled offscreen.
    final muted = !TickerMode.valuesOf(context).enabled;
    if (muted != _tickerMuted) {
      _tickerMuted = muted;
      if (muted) {
        _ambientCtrl.stop();
      } else if (_entryCtrl.isCompleted) {
        _startAmbientIfNeeded();
      }
    }
  }

  @override
  void didUpdateWidget(StatementCard oldWidget) {
    super.didUpdateWidget(oldWidget);

    // FE-5: Flash on signal rank change (skip first load). [A5]
    if (_hasLoadedOnce &&
        oldWidget.signalRank != widget.signalRank &&
        widget.signalRank != null &&
        !_reduceMotion) {
      _flashCtrl.forward(from: 0.0);
    }
    if (widget.signalRank != null) _hasLoadedOnce = true;

    // Sync ambient on activity change. Uses hysteresis band to
    // prevent floating-point thrashing at the boundary. [B2]
    // Start threshold: 0.10, stop threshold: 0.07.
    if (oldWidget.figureActivityLevel != widget.figureActivityLevel) {
      if (widget.figureActivityLevel >= _kAmbientStartThreshold &&
          !_ambientCtrl.isAnimating &&
          !_reduceMotion &&
          !widget.isRevoked &&
          _entryCtrl.isCompleted) {
        _ambientCtrl.repeat(reverse: true);
      } else if (widget.figureActivityLevel < _kAmbientStopThreshold &&
          _ambientCtrl.isAnimating) {
        _ambientCtrl.stop();
        _ambientCtrl.value = 0.0;
      }
    }
  }

  @override
  void dispose() {
    _staggerTimer?.cancel();
    _entryCtrl.removeStatusListener(_onEntryStatus);
    _entryCtrl.dispose();
    _flashCtrl.dispose();
    _ambientCtrl.dispose();
    super.dispose();
  }

  // ═════════════════════════════════════════════════════════
  // BUILD
  // ═════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: Listenable.merge([_entryCtrl, _flashCtrl, _ambientCtrl]),
        builder: (context, _) {
          final entryVal = _entryCtrl.value;
          final fade = Curves.easeOut.transform(entryVal);
          final slide = _kEntrySlide *
              (1.0 - Curves.easeOutCubic.transform(entryVal));

          return Opacity(
            opacity: fade,
            child: Transform.translate(
              offset: Offset(0.0, slide),
              child: _buildInteractiveCard(),
            ),
          );
        },
      ),
    );
  }

  // ── Semantic architecture [A1/B3 audit fix] ────────────
  // Outer Semantics: container groups the card, button + label
  // for the main tap action, onTap for assistive tech.
  // Decorative text/chrome: ExcludeSemantics on identity row,
  // statement text, metrics footer, revoked content.
  // Bookmark: its own Semantics(button: true, onTap:) node,
  // exposed to the accessibility tree independently.

  Widget _buildInteractiveCard() {
    return Semantics(
      container: true,
      button: true,
      label: _buildSemanticLabel(),
      onTap: () {
        HapticUtil.medium();
        widget.onTap();
      },
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) {
          setState(() => _pressed = false);
          HapticUtil.medium();
          widget.onTap();
        },
        onTapCancel: () => setState(() => _pressed = false),
        onLongPress: widget.onLongPress != null
            ? () {
                HapticUtil.medium();
                widget.onLongPress!();
              }
            : null,
        behavior: HitTestBehavior.opaque,
        child: AnimatedScale(
          scale: _pressed ? _kPressScale : 1.0,
          duration: BaselineAnimation.fast,
          curve: BaselineAnimation.curve,
          child: _buildCard(),
        ),
      ),
    );
  }

  Widget _buildCard() {
    // FE-5: Flash border.
    final flashVal = _flashCtrl.value;
    final flashOpacity = flashVal > 0.0
        ? _kFlashPeakOpacity * (1.0 - Curves.easeOut.transform(flashVal))
        : 0.0;
    final borderColor = flashOpacity > 0.01
        ? BaselineColors.teal.atOpacity(flashOpacity)
        : BaselineColors.border;

    // Derive document serial from SID or fallback.
    final serial = widget.statementIdShort?.trim().isNotEmpty == true
        ? widget.statementIdShort!.toUpperCase()
        : '';

    // Compact layout adjustments.
    final padH = widget.isCompact ? _kCardPadHCompact : _kCardPadH;
    final padV = widget.isCompact ? _kCardPadVCompact : _kCardPadV;
    final padTop = widget.isCompact ? _kCardPadTopCompact : _kCardPadTop;

    return Opacity(
      opacity: widget.isRevoked ? _kRevokedOpacity : 1.0,
      child: Container(
        decoration: BoxDecoration(
          color: BaselineColors.card,
          borderRadius: BorderRadius.circular(BaselineRadius.card),
          border: Border.all(
            color: borderColor,
            width: BaselineCardStyle.borderWidth,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(
            BaselineRadius.card - BaselineCardStyle.borderWidth,
          ),
          child: CustomPaint(
            painter: _CardChromePainter(
              isRevoked: widget.isRevoked,
              activityLevel: widget.figureActivityLevel,
              pulseBarProgress: _reduceMotion
                  ? 1.0
                  : Curves.easeOutCubic
                      .transform(_entryCtrl.value.clamp(0.0, 1.0)),
              breathValue: _ambientCtrl.value,
              scanlineProgress: _reduceMotion
                  ? 0.0
                  : _entryCtrl.value.clamp(0.0, 1.0),
              documentSerial: serial,
            ),
            child: Padding(
              padding: EdgeInsets.fromLTRB(padH, padTop, padH, padV),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Pulse bar zone (painted by CustomPaint).
                  const SizedBox(height: _kPulseBarHeight + 4),

                  // Classification micro-label + bookmark (hidden in compact).
                  // Bookmark stays outside ExcludeSemantics for a11y. [A1/B3]
                  if (!widget.isRevoked && !widget.isCompact)
                    _buildClassificationRow(),

                  // In compact mode, show bookmark inline after pulse bar.
                  if (!widget.isRevoked && widget.isCompact)
                    _buildCompactBookmarkRow(),

                  SizedBox(height: widget.isCompact ? 4 : 6),

                  // Identity row: decorative (label covers it). [A1/B3]
                  ExcludeSemantics(child: _buildIdentityRow()),

                  const SizedBox(height: 8),

                  // Content or redaction: decorative (label covers it). [A1/B3]
                  if (widget.isRevoked)
                    ExcludeSemantics(child: _buildRevokedContent())
                  else ...[
                    ExcludeSemantics(child: _buildStatementText()),
                    const SizedBox(height: 12), // [B7: 8 -> 12px]
                    ExcludeSemantics(child: _buildMetricsFooter()),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ═════════════════════════════════════════════════════════
  // CLASSIFICATION MICRO-LABEL (standard mode)
  // ═════════════════════════════════════════════════════════

  /// Classification row contains both decorative text (excluded from
  /// semantics) and the bookmark action (exposed). The text elements
  /// are wrapped in ExcludeSemantics; bookmark retains its own
  /// Semantics node. [A1/B3]
  Widget _buildClassificationRow() {
    final hasSid = widget.statementIdShort?.trim().isNotEmpty ?? false;
    final hasTopic = widget.topics.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Decorative classification text.
          Flexible(
            child: ExcludeSemantics(
              child: Text(
                hasSid
                    ? 'SID-${widget.statementIdShort!.toUpperCase()}'
                    : 'CLASSIFIED',
                style: BaselineTypography.dataSmall.copyWith(
                  color: BaselineColors.teal.atOpacity(0.20),
                  fontSize: _kClassFontSize,
                  letterSpacing: _kClassLetterSpacing,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          if (hasTopic) ...[
            const SizedBox(width: 5),
            Container(
              width: _kClassDotSize,
              height: _kClassDotSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: BaselineColors.teal.atOpacity(0.12),
              ),
            ),
            const SizedBox(width: 5),
            Flexible(
              child: ExcludeSemantics(
                child: Text(
                  _topicDisplay(widget.topics.first).toUpperCase(),
                  style: BaselineTypography.dataSmall.copyWith(
                    color: BaselineColors.textSecondary.atOpacity(0.30),
                    fontSize: _kClassFontSize,
                    letterSpacing: _kClassLetterSpacing,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
          const Spacer(),

          // Bookmark action (Hitlist #13: visible to ALL users).
          // NOT wrapped in ExcludeSemantics. Exposed to a11y tree.
          // Constrained height so the 44px touch target doesn't
          // inflate the classification row's vertical footprint.
          SizedBox(
            height: 24,
            child: _buildBookmarkAction(),
          ),

          const SizedBox(width: 4),

          ExcludeSemantics(
            child: Text(
              'TAP FOR DETAIL \u2192',
              style: BaselineTypography.dataSmall.copyWith(
                color: BaselineColors.teal.atOpacity(0.18),
                fontSize: _kAffordanceFontSize,
                letterSpacing: 0.6,
              ),
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }

  // ═════════════════════════════════════════════════════════
  // COMPACT BOOKMARK ROW (Figure Profile context)
  // ═════════════════════════════════════════════════════════

  /// Minimal row: just the bookmark action aligned right.
  /// Classification chrome omitted since figure context is known.
  Widget _buildCompactBookmarkRow() {
    return Align(
      alignment: Alignment.centerRight,
      child: _buildBookmarkAction(),
    );
  }

  // ═════════════════════════════════════════════════════════
  // BOOKMARK ACTION (HITLIST #13)
  // ═════════════════════════════════════════════════════════

  /// Bookmark has its own Semantics node with button: true, label,
  /// and onTap for assistive technology. [A1/A2/B3 audit fix]
  Widget _buildBookmarkAction() {
    return Semantics(
      button: true,
      label: widget.isBookmarked ? 'Remove bookmark' : 'Bookmark statement',
      onTap: widget.onBookmark, // [A2 audit fix]
      child: GestureDetector(
        onTap: () {
          HapticUtil.light();
          widget.onBookmark?.call();
        },
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: _kBookmarkTouchTarget,
          height: _kBookmarkTouchTarget,
          child: Center(
            child: CustomPaint(
              size: const Size(_kBookmarkSize, _kBookmarkSize),
              painter: _BookmarkPainter(
                isActive: widget.isBookmarked,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ═════════════════════════════════════════════════════════
  // IDENTITY ROW
  // ═════════════════════════════════════════════════════════

  Widget _buildIdentityRow() {
    // Compact: no avatar (figure identity established by parent screen).
    if (widget.isCompact) {
      final compactName = widget.figureName.isNotEmpty
          ? widget.figureName
          : 'Unknown Figure';

      return Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: CustomPaint(
                    foregroundPainter: _CredentialUnderlinePainter(),
                    child: Text(
                      compactName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: BaselineTypography.h4.copyWith(
                        color: BaselineColors.textPrimary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _formatDateCompact(widget.statedAt),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: BaselineTypography.dataSmall.copyWith(
                    color: BaselineColors.teal.atOpacity(0.35),
                    letterSpacing: _kDateLetterSpacing,
                  ),
                ),
              ],
            ),
          ),
          if (widget.signalRank != null && widget.signalRank != 0) ...[
            const SizedBox(width: 8),
            SignalChip(
              label: 'Signal',
              value: widget.signalRank,
              compact: true,
            ),
          ] else ...[
            const SizedBox(width: 8),
            Text(
              'COLLECTING',
              style: TextStyle(
                fontFamily: BaselineTypography.monoFontFamily,
                fontSize: 8,
                color: BaselineColors.textSecondary.atOpacity(0.3),
                letterSpacing: 0.5,
              ),
            ),
          ],
        ],
      );
    }

    // Standard: avatar + name column + signal chip.
    final displayName = widget.figureName.isNotEmpty
        ? widget.figureName
        : 'Unknown Figure';

    return Row(
      children: [
        SignalPulseWidget.feedCard(
          activityLevel: widget.figureActivityLevel,
          child: ClipOval(child: _buildAvatarContent()),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Figure name with credential underline.
              CustomPaint(
                foregroundPainter: _CredentialUnderlinePainter(),
                child: Text(
                  displayName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: BaselineTypography.h4.copyWith(
                    color: BaselineColors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(height: 1),
              Text(
                _formatDateCompact(widget.statedAt),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: BaselineTypography.dataSmall.copyWith(
                  color: BaselineColors.teal.atOpacity(0.35),
                  letterSpacing: _kDateLetterSpacing,
                ),
              ),
            ],
          ),
        ),
        if (widget.signalRank != null && widget.signalRank != 0) ...[
          const SizedBox(width: 8),
          SignalChip(
            label: 'Signal',
            value: widget.signalRank,
            compact: true,
          ),
        ] else ...[
          const SizedBox(width: 8),
          Text(
            'COLLECTING',
            style: TextStyle(
              fontFamily: BaselineTypography.monoFontFamily,
              fontSize: 8,
              color: BaselineColors.textSecondary.atOpacity(0.3),
              letterSpacing: 0.5,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildAvatarContent() {
    final url = widget.figurePhotoUrl;
    if (url == null || url.trim().isEmpty) {
      return _buildInitialsAvatar();
    }
    return Image.network(
      url,
      width: _kAvatarDiameter,
      height: _kAvatarDiameter,
      cacheWidth: 80,
      cacheHeight: 80,
      fit: BoxFit.cover,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded || frame != null) return child;
        return _buildInitialsAvatar();
      },
      errorBuilder: (context, error, stackTrace) => _buildInitialsAvatar(),
    );
  }

  Widget _buildInitialsAvatar() {
    final initials = widget.figureName.isNotEmpty
        ? widget.figureName
            .split(' ')
            .where((w) => w.isNotEmpty)
            .take(2)
            .map((w) => w[0].toUpperCase())
            .join()
        : '?';

    return Container(
      width: _kAvatarDiameter,
      height: _kAvatarDiameter,
      color: BaselineColors.card,
      alignment: Alignment.center,
      child: Text(
        initials,
        style: BaselineTypography.dataSmall.copyWith(
          color: BaselineColors.teal.atOpacity(0.6),
          fontSize: 13,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  // ═════════════════════════════════════════════════════════
  // STATEMENT TEXT
  // ═════════════════════════════════════════════════════════

  Widget _buildStatementText() {
    return Text(
      widget.statementText,
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
      style: BaselineTypography.body.copyWith(
        color: BaselineColors.textPrimary.atOpacity(0.85),
        height: 1.5,
      ),
    );
  }

  // ═════════════════════════════════════════════════════════
  // METRICS FOOTER
  // ═════════════════════════════════════════════════════════

  Widget _buildMetricsFooter() {
    // Derive sourceName: use provided value, fall back to domain extraction.
    final effectiveSourceName = widget.sourceName.isNotEmpty
        ? widget.sourceName
        : _extractDomain(widget.sourceUrl);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SourceBadge(
          sourceName: effectiveSourceName,
          sourceUrl: widget.sourceUrl,
          favicon: widget.favicon,
        ),
        if (widget.topics.isNotEmpty) ...[
          const SizedBox(height: 12), // [B7: 8 -> 12px for tap isolation]
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              ...widget.topics.take(3).map((t) => _TopicChip(topic: t)),
              if (widget.topics.length > 3)
                _TopicChip(topic: '+${widget.topics.length - 3}'),
            ],
          ),
        ],
      ],
    );
  }

  /// Extracts a display-friendly domain from a URL.
  /// Returns empty string if URL is invalid.
  static String _extractDomain(String url) {
    if (url.isEmpty) return '';
    var trimmed = url.trim();
    if (!trimmed.startsWith('http://') && !trimmed.startsWith('https://')) {
      trimmed = 'https://$trimmed';
    }
    final uri = Uri.tryParse(trimmed);
    if (uri == null || uri.host.isEmpty) return '';
    var host = uri.host;
    if (host.startsWith('www.')) host = host.substring(4);
    return host;
  }

  // ═════════════════════════════════════════════════════════
  // REVOKED
  // ═════════════════════════════════════════════════════════

  Widget _buildRevokedContent() {
    final effectiveSourceName = widget.sourceName.isNotEmpty
        ? widget.sourceName
        : _extractDomain(widget.sourceUrl);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'CONTENT WITHDRAWN',
          style: BaselineTypography.dataSmall.copyWith(
            color: BaselineColors.teal.atOpacity(0.25),
            letterSpacing: 1.6,
            fontSize: 9,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 6),
        SourceBadge(
          sourceName: effectiveSourceName,
          sourceUrl: widget.sourceUrl,
          favicon: widget.favicon,
        ),
      ],
    );
  }

  // ═════════════════════════════════════════════════════════
  // SEMANTICS
  // ═════════════════════════════════════════════════════════

  String _buildSemanticLabel() {
    final date = _formatDateCompact(widget.statedAt);

    if (widget.isRevoked) {
      return '${widget.figureName}. Content withdrawn. '
          '$date. Source: ${widget.sourceName}';
    }

    final text = widget.statementText.length > 80
        ? '${widget.statementText.substring(0, 80)}\u2026'
        : widget.statementText;

    // Strip trailing periods from each part to prevent double
    // punctuation when joined with '. ' separator. [A10]
    final parts = <String>[
      '${widget.figureName}: $text'.replaceAll(RegExp(r'\.+$'), ''),
      'Source: ${widget.sourceName}'.replaceAll(RegExp(r'\.+$'), ''),
      date,
    ];

    if (widget.signalRank != null) {
      // "Signal 72 out of 100" is clearer for screen readers
      // than "Signal: 72". [A11]
      parts.add('Signal ${widget.signalRank!.round()} out of 100');
    }
    if (widget.topics.isNotEmpty) {
      parts.add('Topics: ${widget.topics.take(3).map(_topicDisplay).join(', ')}');
    }
    if (widget.isBookmarked) {
      parts.add('Bookmarked');
    }

    return '${parts.join('. ')}.';
  }
}

// ═══════════════════════════════════════════════════════════
// CREDENTIAL UNDERLINE PAINTER
// ═══════════════════════════════════════════════════════════

/// Paints a hair-thin teal line beneath the figure name text,
/// simulating an engraved credential inscription on a nameplate.
/// Decorative micro-engraving (0.3px), not structural 2px border.
/// Documented exception to border doctrine. [A3]
class _CredentialUnderlinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height + 0.5;
    canvas.drawLine(
      Offset(0, y),
      Offset(size.width * 0.85, y),
      Paint()
        ..color = BaselineColors.teal.atOpacity(_kCredLineOpacity)
        ..strokeWidth = _kCredLineStroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_CredentialUnderlinePainter old) => false;
}

// ═══════════════════════════════════════════════════════════
// BOOKMARK PAINTER
// ═══════════════════════════════════════════════════════════

/// Bespoke bookmark flag icon. Drawn as a banner/pennant shape:
/// a tall rectangle with a V-notch cut from the bottom. When
/// active (bookmarked), fills teal. When idle, stroked only.
/// No stock icons. Every pixel is ours.
class _BookmarkPainter extends CustomPainter {
  const _BookmarkPainter({required this.isActive});

  final bool isActive;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Banner proportions: centered, 55% width, full height.
    final bw = w * 0.55;
    final bx = (w - bw) / 2;
    final notchDepth = h * 0.22;

    final path = Path()
      ..moveTo(bx, 0)
      ..lineTo(bx + bw, 0)
      ..lineTo(bx + bw, h)
      ..lineTo(bx + bw / 2, h - notchDepth)
      ..lineTo(bx, h)
      ..close();

    if (isActive) {
      canvas.drawPath(
        path,
        Paint()
          ..color = BaselineColors.teal.atOpacity(_kBookmarkActiveOpacity)
          ..style = PaintingStyle.fill,
      );
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = BaselineColors.teal.atOpacity(
          isActive ? _kBookmarkActiveOpacity : _kBookmarkIdleOpacity,
        )
        ..style = PaintingStyle.stroke
        ..strokeWidth = _kBookmarkStroke
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_BookmarkPainter old) => old.isActive != isActive;
}

// ═══════════════════════════════════════════════════════════
// CARD CHROME PAINTER
// ═══════════════════════════════════════════════════════════

/// Single-pass CustomPaint: 11 visual layers.
///   1.  Top edge highlight       2.  Film perforations
///   3.  Intel dots               4.  Compound reticle corners + reg dots
///   5.  Activity beacon          6.  Pulse bar track + hashmarks
///   7.  Pulse bar fill + glow    8.  Transmission receipt hairline
///   9.  Document serial          10. Scanline + phosphor wake
///   11. Void hatch
class _CardChromePainter extends CustomPainter {
  const _CardChromePainter({
    required this.isRevoked,
    required this.activityLevel,
    required this.pulseBarProgress,
    required this.breathValue,
    required this.scanlineProgress,
    this.documentSerial = '',
  });

  final bool isRevoked;
  final double activityLevel;
  final double pulseBarProgress;
  final double breathValue;
  final double scanlineProgress;
  final String documentSerial;

  @override
  void paint(Canvas canvas, Size size) {
    _paintEdgeHighlight(canvas, size);
    _paintFilmPerforations(canvas, size);
    _paintIntelDots(canvas, size);
    _paintCompoundReticles(canvas, size);
    _paintActivityBeacon(canvas, size);
    _paintPulseBar(canvas, size);
    _paintTransmissionReceipt(canvas, size);
    _paintDocumentSerial(canvas, size);
    _paintScanline(canvas, size);
    if (isRevoked) _paintVoidHatch(canvas, size);
  }

  // ── 1. Top edge highlight ──────────────────────────────
  // Machined metal catch-light. Uses literal white (physical
  // reflected light, not brand color: documented exception).

  void _paintEdgeHighlight(Canvas canvas, Size size) {
    final arcWidth = size.width * 0.6;
    final arcStart = (size.width - arcWidth) / 2;
    canvas.drawLine(
      Offset(arcStart, 1.0),
      Offset(arcStart + arcWidth, 1.0),
      Paint()
        ..color = const Color(0x0AFFFFFF) // white 4%: catch-light
        ..strokeWidth = _kEdgeHighlightStroke
        ..strokeCap = StrokeCap.round,
    );
  }

  // ── 2. Film perforations ───────────────────────────────

  void _paintFilmPerforations(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = BaselineColors.teal.atOpacity(_kPerfOpacity)
      ..style = PaintingStyle.fill;

    final x = size.width - _kPerfInsetRight;
    final startY = size.height * 0.35;

    for (var i = 0; i < _kPerfCount; i++) {
      canvas.drawRect(
        Rect.fromLTWH(x, startY + i * _kPerfSpacing, _kPerfSize, _kPerfSize),
        paint,
      );
    }
  }

  // ── 3. Intel dots ──────────────────────────────────────

  void _paintIntelDots(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = BaselineColors.teal.atOpacity(_kIntelDotOpacity)
      ..style = PaintingStyle.fill;

    final startX = size.width -
        _kIntelDotInset -
        (_kIntelDotCols - 1) * _kIntelDotSpacing;
    final startY = _kIntelDotInset + _kPulseBarHeight + 6;

    for (var r = 0; r < _kIntelDotRows; r++) {
      for (var c = 0; c < _kIntelDotCols; c++) {
        canvas.drawCircle(
          Offset(
            startX + c * _kIntelDotSpacing,
            startY + r * _kIntelDotSpacing,
          ),
          _kIntelDotRadius,
          paint,
        );
      }
    }
  }

  // ── 4. Compound reticle corners + registration dots ────
  // Upgraded from simple L-brackets: outer L + inner tick
  // at 1.5px inward + registration dot at vertex. Matches
  // F4.7/F4.9 classified document vocabulary.

  void _paintCompoundReticles(Canvas canvas, Size size) {
    final outerPaint = Paint()
      ..color = BaselineColors.teal.atOpacity(_kReticleOpacity)
      ..strokeWidth = _kReticleStroke
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.square;

    final innerPaint = Paint()
      ..color = BaselineColors.teal.atOpacity(_kReticleInnerOpacity)
      ..strokeWidth = _kReticleInnerStroke
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.square;

    final dotPaint = Paint()
      ..color = BaselineColors.teal.atOpacity(_kRegDotOpacity)
      ..style = PaintingStyle.fill;

    final w = size.width;
    final h = size.height;
    const a = _kReticleArm;
    const i = 3.0;
    const it = _kReticleInnerTick;

    // Helper to draw one compound corner.
    void drawCorner(double cx, double cy, double dx, double dy) {
      // Outer L-bracket.
      canvas.drawLine(Offset(cx, cy), Offset(cx + a * dx, cy), outerPaint);
      canvas.drawLine(Offset(cx, cy), Offset(cx, cy + a * dy), outerPaint);
      // Inner tick marks (1.5px inside).
      final ix = cx + it * dx;
      final iy = cy + it * dy;
      canvas.drawLine(
        Offset(ix, iy),
        Offset(ix + (a * 0.5) * dx, iy),
        innerPaint,
      );
      canvas.drawLine(
        Offset(ix, iy),
        Offset(ix, iy + (a * 0.5) * dy),
        innerPaint,
      );
      // Registration dot at vertex.
      canvas.drawCircle(Offset(cx, cy), _kRegDotRadius, dotPaint);
    }

    drawCorner(i, i, 1, 1);           // top-left
    drawCorner(w - i, i, -1, 1);      // top-right
    drawCorner(i, h - i, 1, -1);      // bottom-left
    drawCorner(w - i, h - i, -1, -1); // bottom-right
  }

  // ── 5. Activity beacon ─────────────────────────────────
  // Breathing dot at top-left. Monitoring station indicator.
  // Pulses with ambient controller when activity > threshold.

  void _paintActivityBeacon(Canvas canvas, Size size) {
    if (isRevoked) return;
    if (activityLevel < _kAmbientStartThreshold) return;

    final opacity = ui.lerpDouble(
      _kBeaconMinOpacity,
      _kBeaconMaxOpacity,
      breathValue,
    )!;

    canvas.drawCircle(
      Offset(_kBeaconInsetX, _kBeaconInsetY),
      _kBeaconRadius,
      Paint()
        ..color = BaselineColors.teal.atOpacity(opacity)
        ..style = PaintingStyle.fill,
    );
  }

  // ── 6+7. Pulse bar ─────────────────────────────────────

  void _paintPulseBar(Canvas canvas, Size size) {
    // Track.
    const barX = _kCardPadH;
    final barMaxW = size.width - _kCardPadH * 2;
    const barY = _kCardPadTop + 2;
    const barMidY = barY + _kPulseBarHeight / 2;

    canvas.drawRRect(
      RRect.fromLTRBR(
        barX, barY,
        barX + barMaxW, barY + _kPulseBarHeight,
        const Radius.circular(_kPulseBarRadius),
      ),
      Paint()
        ..color = BaselineColors.teal.atOpacity(_kPulseBarTrackOpacity)
        ..style = PaintingStyle.fill,
    );

    // Hashmark ruler ticks.
    final tickPaint = Paint()
      ..color = BaselineColors.teal.atOpacity(_kTickOpacity)
      ..strokeWidth = _kTickStroke;

    for (var t = 0; t < _kPulseBarTicks; t++) {
      final frac = t / (_kPulseBarTicks - 1);
      final tx = barX + barMaxW * frac;
      // Major ticks at 0%, 50%, 100%.
      final isMajor = t == 0 || t == 2 || t == _kPulseBarTicks - 1;
      final th = isMajor ? _kTickHeight + 1.0 : _kTickHeight;
      canvas.drawLine(
        Offset(tx, barY - 1),
        Offset(tx, barY - 1 - th),
        tickPaint,
      );
    }

    if (activityLevel < _kPulseBarMinActivity) return;

    // Breathing opacity modulation.
    final barOpacity = ui.lerpDouble(_kBreathMin, _kBreathMax, breathValue)!;

    // Fill width.
    final fillW = barMaxW *
        activityLevel.clamp(0.0, 1.0) *
        pulseBarProgress.clamp(0.0, 1.0);

    if (fillW < 1.0) return;

    // Teal fill with breathing.
    canvas.drawRRect(
      RRect.fromLTRBR(
        barX, barY,
        barX + fillW, barY + _kPulseBarHeight,
        const Radius.circular(_kPulseBarRadius),
      ),
      Paint()
        ..color = BaselineColors.teal.atOpacity(barOpacity)
        ..style = PaintingStyle.fill,
    );

    // Leading-edge glow.
    canvas.drawCircle(
      Offset(barX + fillW, barMidY),
      _kPulseBarHeight,
      Paint()
        ..color = BaselineColors.teal.atOpacity(
          _kPulseBarGlowOpacity * (barOpacity / _kBreathMax),
        )
        ..maskFilter = const MaskFilter.blur(
          BlurStyle.normal, _kPulseBarGlowSigma,
        ),
    );
  }

  // ── 8. Transmission receipt hairline ───────────────────
  // Ultra-faint dashed line near bottom with "RCVD" stamp.
  // Every classified document shows when it was received.

  void _paintTransmissionReceipt(Canvas canvas, Size size) {
    if (isRevoked) return;

    final y = size.height * _kReceiptLineY;
    final dashPaint = Paint()
      ..color = BaselineColors.teal.atOpacity(_kReceiptOpacity)
      ..strokeWidth = _kReceiptStroke;

    // Dashed line.
    var dx = _kCardPadH;
    final endX = size.width - _kCardPadH;
    while (dx < endX) {
      final dashEnd = (dx + _kReceiptDashWidth).clamp(0.0, endX);
      canvas.drawLine(Offset(dx, y), Offset(dashEnd, y), dashPaint);
      dx += _kReceiptDashWidth + _kReceiptDashGap;
    }

    // "RCVD" micro-stamp. Uses fontFamily token, not raw string.
    final tp = TextPainter(
      text: TextSpan(
        text: 'RCVD',
        style: TextStyle(
          fontFamily: BaselineTypography.monoFontFamily,
          fontSize: 4.0,
          color: BaselineColors.teal.atOpacity(_kReceiptLabelOpacity),
          letterSpacing: 0.8,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(_kCardPadH, y - tp.height - 1));
    tp.dispose();
  }

  // ── 9. Document serial stamp ───────────────────────────
  // "DOC\u00B7[SID]" at bottom-right. Filing index. Every
  // classified document has a serial number pressed into
  // the footer.

  void _paintDocumentSerial(Canvas canvas, Size size) {
    if (isRevoked) return;
    if (documentSerial.isEmpty) return;

    final label = 'DOC\u00B7$documentSerial';

    // Uses fontFamily token, not raw string.
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          fontFamily: BaselineTypography.monoFontFamily,
          fontSize: _kSerialFontSize,
          color: BaselineColors.teal.atOpacity(_kSerialOpacity),
          letterSpacing: 0.6,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(
      canvas,
      Offset(size.width - _kCardPadH - tp.width, size.height - tp.height - 4),
    );
    tp.dispose();
  }

  // ── 10. Scanline + phosphor wake ───────────────────────

  void _paintScanline(Canvas canvas, Size size) {
    if (scanlineProgress < _kScanlineStart ||
        scanlineProgress > _kScanlineEnd) {
      return;
    }

    final t = ((scanlineProgress - _kScanlineStart) /
            (_kScanlineEnd - _kScanlineStart))
        .clamp(0.0, 1.0);
    final y = Curves.easeInOut.transform(t) * size.height;

    // Fade in over first 15%, fade out over last 20%.
    final fadeIn =
        ((scanlineProgress - _kScanlineStart) / 0.10).clamp(0.0, 1.0);
    final fadeOut =
        ((_kScanlineEnd - scanlineProgress) / 0.13).clamp(0.0, 1.0);
    final opacity = _kScanlineOpacity * fadeIn * fadeOut;

    if (opacity < 0.01) return;

    // Phosphor wake trail (decaying gradient behind the beam).
    if (y > _kPhosphorWakeWidth) {
      final wakeRect = Rect.fromLTWH(
        0,
        y - _kPhosphorWakeWidth,
        size.width,
        _kPhosphorWakeWidth,
      );
      canvas.drawRect(
        wakeRect,
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(0, y - _kPhosphorWakeWidth),
            Offset(0, y),
            [
              BaselineColors.teal.atOpacity(0.0),
              BaselineColors.teal.atOpacity(_kPhosphorWakeOpacity * fadeIn),
            ],
          ),
      );
    }

    // Beam.
    canvas.drawLine(
      Offset(0, y),
      Offset(size.width, y),
      Paint()
        ..color = BaselineColors.teal.atOpacity(opacity)
        ..strokeWidth = _kScanlineHeight,
    );

    // Glow halo.
    canvas.drawLine(
      Offset(0, y),
      Offset(size.width, y),
      Paint()
        ..color = BaselineColors.teal.atOpacity(opacity * 0.4)
        ..strokeWidth = _kScanlineHeight * 3
        ..maskFilter = const MaskFilter.blur(
          BlurStyle.normal, _kScanlineGlowSigma,
        ),
    );
  }

  // ── 11. Void hatch ─────────────────────────────────────

  void _paintVoidHatch(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = BaselineColors.textSecondary.atOpacity(_kHatchOpacity)
      ..strokeWidth = _kHatchStroke;

    final maxDim = size.width + size.height;
    for (var d = 0.0; d < maxDim; d += _kHatchSpacing) {
      canvas.drawLine(
        Offset(d, 0),
        Offset(d - size.height, size.height),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_CardChromePainter old) {
    return old.isRevoked != isRevoked ||
        old.activityLevel != activityLevel ||
        old.pulseBarProgress != pulseBarProgress ||
        old.breathValue != breathValue ||
        old.scanlineProgress != scanlineProgress ||
        old.documentSerial != documentSerial;
  }
}

// ═══════════════════════════════════════════════════════════
// TOPIC CHIP
// ═══════════════════════════════════════════════════════════

class _TopicChip extends StatelessWidget {
  const _TopicChip({required this.topic});

  final String topic;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: _kTopicMaxWidth),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_kTopicChipRadius),
        border: Border.all(
          color: BaselineColors.borderInactive,
          width: 1,
        ),
      ),
      child: Text(
        _topicDisplay(topic),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: BaselineTypography.caption.copyWith(
          color: BaselineColors.textSecondary.atOpacity(0.7),
          fontSize: 9,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}
