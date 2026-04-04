/// F2.11: Vote Card (Congressional Ledger Entry)
///
/// Filed legislative record for Vote Record screen (F4.12).
/// Each card is a docket entry in the permanent congressional record:
/// bill number, verdict stamp, tally notation, filing timestamp.
///
/// Concept: SCIF briefing document meets Bloomberg terminal
/// legislative data. Senate intelligence committee vote tally
/// rendered as a classified instrument readout. Film strip
/// archival energy: each card is a frame in the permanent record.
///
/// Vote color rules (CRITICAL, political neutrality):
///   YEA        → teal OUTLINE (vote was recorded)
///   NAY        → teal OUTLINE (vote was recorded)
///   PRESENT    → teal OUTLINE (vote was recorded)
///   NOT_VOTING → gray FILL (not recorded)
///   Unknown    → gray FILL (runtime fallback for unexpected values)
///   NEVER red/green. NEVER implies approval/disapproval.
///
/// Recorded votes use outline style (teal 2px border + teal text,
/// transparent fill) with glow bloom: verdict stamped and sealed.
/// Not-recorded uses gray fill at 20% + void hatch: absent from record.
/// Badge border hierarchy: recorded = 2px (stamped), not-recorded = 1px
/// (absent from record, intentionally subordinate).
///
/// FG-6: Silent vote indicator. Amber micro-dot when a figure voted
/// on a bill but made zero public statements about it. Amber is valid
/// here as a signal anomaly indicator (public data gap), not decorative.
///
/// No lens toggle, no metric bars on vote surfaces (spec locked).
///
/// Visual treatments (48):
///   Card chrome: docket binding bar, film perforation dots,
///   top edge highlight, classification hairline, docket field tint,
///   docket separation line, reticle corners, registration dots,
///   intel dot grid, hashmark measurement ruler, entry scanline.
///   Badge: glow bloom + validation ticks (recorded),
///   void hatch (not-recorded). FG-6 amber indicator.
///
/// Accessibility: Outer Semantics(container, button, onTap) for
/// assistive tech. GestureDetector owns haptic + navigation for
/// physical taps. No duplicated tap paths. Decorative chrome
/// wrapped in ExcludeSemantics.
///
/// Composes: BaselineIcon (F_ICONS), HapticUtil.
///
/// Data source: get-votes (A16C) → get_votes_for_figure RPC.
///
/// Path: lib/widgets/vote_card.dart
library;

// 1. Dart SDK
import 'dart:ui' as ui;

// 2. Flutter
import 'package:flutter/material.dart';

// 3. Project: config
import 'package:baseline_app/config/theme.dart';

// 4. Project: widgets
import 'package:baseline_app/widgets/baseline_icons.dart';

// 5. Project: utils
import 'package:baseline_app/utils/haptic_util.dart';

// ═══════════════════════════════════════════════════════════
// CONSTANTS
// ═══════════════════════════════════════════════════════════

/// Valid vote values: matches A1 schema CHECK constraint exactly.
const Set<String> _kValidVotes = {'YEA', 'NAY', 'PRESENT', 'NOT_VOTING'};

/// Recorded votes (teal outline). NOT_VOTING and unknown → gray fill.
const Set<String> _kRecordedVotes = {'YEA', 'NAY', 'PRESENT'};

/// Human-readable display labels: uppercase verdicts, stamped.
const Map<String, String> _kVoteLabels = {
  'YEA': 'YEA',
  'NAY': 'NAY',
  'PRESENT': 'PRESENT',
  'NOT_VOTING': 'NOT VOTING',
};

/// Entry animation duration.
const Duration _kEntryDuration = Duration(milliseconds: 300);

/// Scanline sweep window within entry animation (20%–85%).
const double _kScanlineStart = 0.20;
const double _kScanlineEnd = 0.85;

/// Stagger delay per list index.
const Duration _kStaggerDelay = Duration(milliseconds: 40);

/// Max stagger delay cap (prevent absurd delays on long lists).
const int _kMaxStaggerIndex = 12;

/// Docket binding bar width.
const double _kDocketBarWidth = 3.0;

/// Reticle corner arm length.
const double _kReticleArm = 4.0;

/// Registration dot radius.
const double _kRegDotRadius = 1.5;

/// Hashmark ruler tick count (bottom edge).
const int _kRulerTickCount = 11;

/// Film perforation dot count along docket bar.
const int _kPerfDotCount = 5;

/// Film perforation dot radius.
const double _kPerfDotRadius = 1.0;

/// Intel dot grid dimensions (cols × rows).
const int _kIntelCols = 3;
const int _kIntelRows = 2;

/// Docket field tint strip height (row 1 area).
const double _kDocketFieldHeight = 44.0;

// ═══════════════════════════════════════════════════════════
// DATE FORMATTER
// ═══════════════════════════════════════════════════════════

String _formatDate(DateTime dt) {
  const months = [
    'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
    'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC',
  ];
  return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
}

// ═══════════════════════════════════════════════════════════
// VOTE CARD
// ═══════════════════════════════════════════════════════════

class VoteCard extends StatefulWidget {
  const VoteCard({
    super.key,
    required this.billId,
    required this.billTitle,
    required this.vote,
    required this.voteDate,
    this.chamber,
    this.result,
    this.onTap,
    this.isSilentVote = false,
    this.index,
  }) : assert(billId.length > 0, 'VoteCard: billId must not be empty'),
       assert(billTitle.length > 0, 'VoteCard: billTitle must not be empty');

  /// Bill identifier (e.g., "H.R. 1234", "S. 567").
  final String billId;

  /// Full bill title / description.
  final String billTitle;

  /// Vote value: expected YEA, NAY, PRESENT, NOT_VOTING.
  /// Unknown values render as "UNKNOWN" with neutral styling (runtime safe).
  final String vote;

  /// Date of the vote.
  final DateTime voteDate;

  /// Chamber: "HOUSE" or "SENATE". Null → hidden.
  final String? chamber;

  /// Optional result string (e.g., "Passed 218-212"). Null → hidden.
  final String? result;

  /// Optional tap callback (e.g., open source URL).
  /// When null, card is not tappable (no press feedback, no link icon).
  final VoidCallback? onTap;

  /// FG-6: True when figure voted on this bill but made zero
  /// public statements about it. Renders amber indicator.
  final bool isSilentVote;

  /// List index for staggered entry animation. Null = no stagger.
  final int? index;

  @override
  State<VoteCard> createState() => _VoteCardState();
}

class _VoteCardState extends State<VoteCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entryController;
  late final Animation<double> _entryFade;
  late final Animation<Offset> _entrySlide;

  bool _pressed = false;
  bool _tickerMuted = false;

  /// Live reduce-motion check (F2.10 pattern). Getter ensures
  /// changes mid-session are respected on next build.
  bool get _reduceMotion =>
      ui.PlatformDispatcher.instance.accessibilityFeatures.reduceMotion;

  /// Whether this vote was recorded (teal outline) vs not (gray fill).
  bool get _isRecorded => _kRecordedVotes.contains(widget.vote);

  /// Display-safe vote label. Unknown values → "UNKNOWN" (never crashes).
  String get _voteLabel {
    assert(
      _kValidVotes.contains(widget.vote),
      'VoteCard: unexpected vote value "${widget.vote}"',
    );
    return _kVoteLabels[widget.vote] ?? 'UNKNOWN';
  }

  @override
  void initState() {
    super.initState();

    _entryController = AnimationController(
      vsync: this,
      duration: _kEntryDuration,
    );

    _entryFade = CurvedAnimation(
      parent: _entryController,
      curve: Curves.easeOut,
    );

    _entrySlide = Tween<Offset>(
      begin: const Offset(0, 6),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _entryController,
      curve: Curves.easeOutCubic,
    ));

    if (_reduceMotion) {
      _entryController.value = 1.0;
    } else {
      _scheduleEntry();
    }
  }

  void _scheduleEntry() {
    final staggerIndex =
        (widget.index ?? 0).clamp(0, _kMaxStaggerIndex);
    final delay = _kStaggerDelay * staggerIndex;

    if (delay == Duration.zero) {
      _entryController.forward();
    } else {
      Future<void>.delayed(delay, () {
        if (mounted) _entryController.forward();
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final muted = !TickerMode.valuesOf(context).enabled;
    if (muted != _tickerMuted) {
      _tickerMuted = muted;
      if (muted) {
        _entryController.stop();
      } else if (_entryController.value < 1.0) {
        _entryController.forward();
      }
    }
  }

  @override
  void dispose() {
    _entryController.dispose();
    super.dispose();
  }

  // ── Tap architecture (F2.10 pattern) ─────────────────
  // Semantics.onTap: forwards widget.onTap only (screen reader path).
  // GestureDetector.onTap: haptic + press reset + widget.onTap (physical).
  // Haptic: light() for list items (F2.10 precedent). medium() reserved
  // for primary navigation actions (F2.9 statement card).

  void _onTap() {
    setState(() => _pressed = false);
    HapticUtil.light();
    widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _entryController,
        builder: (context, child) {
          return FadeTransition(
            opacity: _entryFade,
            child: Transform.translate(
              offset: _entrySlide.value,
              child: child,
            ),
          );
        },
        child: _buildCard(),
      ),
    );
  }

  Widget _buildCard() {
    final content = CustomPaint(
      painter: _VoteCardChromePainter(
        entryProgress: _entryController,
        isRecorded: _isRecorded,
        isSilentVote: widget.isSilentVote,
        reduceMotion: _reduceMotion,
      ),
      child: Padding(
        // Left padding accounts for docket bar + gap.
        padding: const EdgeInsets.only(
          left: _kDocketBarWidth + BaselineSpacing.md,
          right: BaselineSpacing.md,
          top: BaselineSpacing.md,
          bottom: BaselineSpacing.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Row 1: Docket header: bill ID, chamber, date.
            _buildDocketHeader(),

            const SizedBox(height: BaselineSpacing.xs), // 8px

            // Row 2: Bill title (legislative description).
            Text(
              widget.billTitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: BaselineTypography.body2.copyWith(
                color: BaselineColors.textSecondary,
                height: 1.4,
              ),
            ),

            const SizedBox(height: BaselineSpacing.sm), // 12px

            // Row 3: Verdict: vote badge + result tally + FG-6.
            _buildVerdictRow(),
          ],
        ),
      ),
    );

    final card = Container(
      constraints: const BoxConstraints(minHeight: 44),
      decoration: BoxDecoration(
        color: BaselineColors.card,
        borderRadius: BorderRadius.circular(BaselineCardStyle.radius),
        border: Border.all(
          color: BaselineColors.border,
          width: BaselineCardStyle.borderWidth,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(
          BaselineCardStyle.radius - BaselineCardStyle.borderWidth,
        ),
        child: content,
      ),
    );

    // Static card (no onTap).
    if (widget.onTap == null) {
      return Semantics(
        container: true,
        label: _buildSemanticLabel(),
        child: card,
      );
    }

    // Tappable card with press feedback + haptic.
    return Semantics(
      container: true,
      button: true,
      label: _buildSemanticLabel(),
      onTap: widget.onTap,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: _onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedScale(
          scale: _pressed ? 0.98 : 1.0,
          duration: const Duration(milliseconds: 100),
          curve: BaselineAnimation.curve,
          child: card,
        ),
      ),
    );
  }

  /// Row 1: [dot BILL_ID] [CHAMBER] ............ [DATE]
  Widget _buildDocketHeader() {
    return Row(
      children: [
        // Classification dot (teal substrate mark, visual vocabulary).
        Container(
          width: 4,
          height: 4,
          decoration: BoxDecoration(
            color: BaselineColors.teal.atOpacity(0.5),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),

        // Bill ID: docket number.
        Flexible(
          child: Text(
            widget.billId,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: BaselineTypography.data.copyWith(
              letterSpacing: 0.8,
              color: BaselineColors.textPrimary,
            ),
          ),
        ),

        if (widget.chamber != null) ...[
          const SizedBox(width: BaselineSpacing.sm),
          // Chamber classification micro-label.
          Text(
            widget.chamber!.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: BaselineTypography.dataSmall.copyWith(
              color: BaselineColors.textSecondary,
              letterSpacing: 1.2,
            ),
          ),
        ],

        const Spacer(),

        // Filing timestamp.
        Text(
          _formatDate(widget.voteDate),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: BaselineTypography.dataSmall.copyWith(
            color: BaselineColors.textSecondary,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }

  /// Row 3: [VERDICT BADGE] [Result tally] [FG-6 silent] ... [link]
  Widget _buildVerdictRow() {
    return Row(
      children: [
        // Vote verdict badge.
        _VoteBadgePaint(
          label: _voteLabel,
          isRecorded: _isRecorded,
        ),

        // Result tally notation.
        if (widget.result != null && widget.result!.trim().isNotEmpty) ...[
          const SizedBox(width: BaselineSpacing.xs),
          // Micro-dot separator.
          Container(
            width: 3,
            height: 3,
            decoration: BoxDecoration(
              color: BaselineColors.textSecondary.atOpacity(0.4),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: BaselineSpacing.xs),
          Flexible(
            child: Text(
              widget.result!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: BaselineTypography.dataSmall.copyWith(
                color: BaselineColors.textSecondary,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],

        // FG-6: Silent vote amber indicator.
        if (widget.isSilentVote) ...[
          const SizedBox(width: BaselineSpacing.xs),
          _buildSilentVoteIndicator(),
        ],

        if (widget.onTap != null) ...[
          const Spacer(),
          // Bespoke NE-arrow from shared icon library (F_ICONS).
          ExcludeSemantics(
            child: BaselineIcon(
              BaselineIconType.northEast,
              size: 16,
              color: BaselineColors.teal.atOpacity(0.5),
            ),
          ),
        ],
      ],
    );
  }

  /// FG-6: Amber dot + "SILENT" micro-label.
  Widget _buildSilentVoteIndicator() {
    return ExcludeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: const BoxDecoration(
              color: BaselineColors.amber,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            'SILENT',
            style: BaselineTypography.dataSmall.copyWith(
              color: BaselineColors.amber,
              letterSpacing: 1.0,
              fontSize: 8,
            ),
          ),
        ],
      ),
    );
  }

  /// Semantic label: bill ID, vote, chamber, date, silent status, tap hint.
  /// Parts stripped of trailing periods before join (F2.10 pattern).
  String _buildSemanticLabel() {
    final parts = <String>[
      widget.billId,
      _voteLabel,
    ];
    if (widget.chamber != null) {
      parts.add(widget.chamber!.toUpperCase());
    }
    parts.add(_formatDate(widget.voteDate));
    if (widget.isSilentVote) {
      parts.add('Silent vote, no public statements');
    }
    if (widget.result != null && widget.result!.trim().isNotEmpty) {
      parts.add(widget.result!);
    }
    if (widget.onTap != null) {
      parts.add('Opens source');
    }
    // Strip trailing periods from each part, then join with ". "
    return parts
        .map((p) => p.endsWith('.') ? p.substring(0, p.length - 1) : p)
        .join('. ');
  }
}

// ═══════════════════════════════════════════════════════════
// CARD CHROME PAINTER: THE CLASSIFIED INSTRUMENT
// ═══════════════════════════════════════════════════════════

/// Paints: docket binding bar + film perforations, classification
/// hairline, top edge highlight, docket field tint strip, reticle
/// corners, registration dots, intel dot grid, hashmark ruler,
/// docket separation line, entry scanline.
class _VoteCardChromePainter extends CustomPainter {
  _VoteCardChromePainter({
    required this.entryProgress,
    required this.isRecorded,
    required this.isSilentVote,
    required this.reduceMotion,
  }) : super(repaint: entryProgress);

  final Animation<double> entryProgress;
  final bool isRecorded;
  final bool isSilentVote;
  final bool reduceMotion;

  @override
  void paint(Canvas canvas, Size size) {
    final progress = entryProgress.value;
    if (progress <= 0) return;

    final w = size.width;
    final h = size.height;
    final teal = BaselineColors.teal;

    // 1. Docket field tint strip (row 1 background).
    final tintPaint = Paint()
      ..color = teal.atOpacity(0.02 * progress);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, _kDocketFieldHeight),
      tintPaint,
    );

    // 2. Left docket binding bar.
    final barPaint = Paint()..color = teal.atOpacity(0.6 * progress);
    canvas.drawRRect(
      RRect.fromLTRBR(0, 0, _kDocketBarWidth, h, const Radius.circular(1)),
      barPaint,
    );

    // Docket bar glow bloom.
    final glowPaint = Paint()
      ..color = teal.atOpacity(0.12 * progress)
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 3);
    canvas.drawRRect(
      RRect.fromLTRBR(0, 0, _kDocketBarWidth, h, const Radius.circular(1)),
      glowPaint,
    );

    // 3. Film perforation dots along docket bar.
    // Archival film strip: each card is a frame in the record.
    final perfPaint = Paint()
      ..color = BaselineColors.card.atOpacity(0.7 * progress);
    final perfSpacing = h / (_kPerfDotCount + 1);
    for (int i = 1; i <= _kPerfDotCount; i++) {
      canvas.drawCircle(
        Offset(_kDocketBarWidth / 2, perfSpacing * i),
        _kPerfDotRadius,
        perfPaint,
      );
    }

    // 4. Top edge highlight (machined catch-light).
    // Intentional BaselineColors.white: physical catch-light, not brand token.
    final highlightPaint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(w * 0.2, 0),
        Offset(w * 0.8, 0),
        [
          BaselineColors.white.atOpacity(0.0),
          BaselineColors.white.atOpacity(0.06 * progress),
          BaselineColors.white.atOpacity(0.06 * progress),
          BaselineColors.white.atOpacity(0.0),
        ],
        [0.0, 0.3, 0.7, 1.0],
      )
      ..strokeWidth = 0.5;
    canvas.drawLine(
      Offset(w * 0.2, 0.25),
      Offset(w * 0.8, 0.25),
      highlightPaint,
    );

    // 5. Classification hairline (top edge, full width).
    final hairlinePaint = Paint()
      ..color = teal.atOpacity(0.08 * progress)
      ..strokeWidth = 0.5;
    canvas.drawLine(Offset.zero, Offset(w, 0), hairlinePaint);

    // 6. Docket separation line (below header, ~44px).
    final sepPaint = Paint()
      ..color = teal.atOpacity(0.06 * progress)
      ..strokeWidth = 0.5;
    canvas.drawLine(
      Offset(_kDocketBarWidth + 8, _kDocketFieldHeight),
      Offset(w - 8, _kDocketFieldHeight),
      sepPaint,
    );

    // 7. Reticle corners.
    final reticlePaint = Paint()
      ..color = teal.atOpacity(0.15 * progress)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    _drawReticle(canvas, 0, 0, 1, 1, reticlePaint);       // TL
    _drawReticle(canvas, w, 0, -1, 1, reticlePaint);      // TR
    _drawReticle(canvas, 0, h, 1, -1, reticlePaint);      // BL
    _drawReticle(canvas, w, h, -1, -1, reticlePaint);     // BR

    // 8. Registration dots.
    final dotPaint = Paint()
      ..color = teal.atOpacity(0.15 * progress);
    canvas.drawCircle(Offset.zero, _kRegDotRadius, dotPaint);
    canvas.drawCircle(Offset(w, 0), _kRegDotRadius, dotPaint);
    canvas.drawCircle(Offset(0, h), _kRegDotRadius, dotPaint);
    canvas.drawCircle(Offset(w, h), _kRegDotRadius, dotPaint);

    // 9. Intel dot grid (top-right, 3x2).
    final intelPaint = Paint()
      ..color = teal.atOpacity(0.10 * progress);
    const intelSpacing = 5.0;
    final intelBaseX = w - 14.0;
    const intelBaseY = 8.0;
    for (int r = 0; r < _kIntelRows; r++) {
      for (int c = 0; c < _kIntelCols; c++) {
        canvas.drawCircle(
          Offset(
            intelBaseX + (c * intelSpacing),
            intelBaseY + (r * intelSpacing),
          ),
          0.8,
          intelPaint,
        );
      }
    }

    // 10. Hashmark measurement ruler (bottom edge).
    final rulerStartX = _kDocketBarWidth + 8.0;
    final rulerEndX = w - 8.0;
    final rulerSpan = rulerEndX - rulerStartX;

    for (int i = 0; i <= _kRulerTickCount - 1; i++) {
      final x = rulerStartX + (rulerSpan * i / (_kRulerTickCount - 1));
      final isMajor = (i % 5 == 0); // 0, 5, 10 are major ticks.
      final tickH = isMajor ? 4.0 : 2.0;
      final tickAlpha = isMajor ? 0.15 : 0.08;
      final tickPaint = Paint()
        ..color = teal.atOpacity(tickAlpha * progress)
        ..strokeWidth = 0.5;
      canvas.drawLine(
        Offset(x, h - 1),
        Offset(x, h - 1 - tickH),
        tickPaint,
      );
    }

    // 11. Entry scanline.
    if (!reduceMotion && progress < 1.0) {
      final scanRange = _kScanlineEnd - _kScanlineStart;
      final scanT =
          ((progress - _kScanlineStart) / scanRange).clamp(0.0, 1.0);
      if (scanT > 0 && scanT < 1.0) {
        final scanY = h * scanT;
        final scanPaint = Paint()
          ..shader = ui.Gradient.linear(
            Offset(0, scanY),
            Offset(w, scanY),
            [
              teal.atOpacity(0.0),
              teal.atOpacity(0.25),
              teal.atOpacity(0.25),
              teal.atOpacity(0.0),
            ],
            [0.0, 0.2, 0.8, 1.0],
          )
          ..strokeWidth = 1.5;
        canvas.drawLine(Offset(0, scanY), Offset(w, scanY), scanPaint);
      }
    }
  }

  /// Draw a single reticle corner at (cx, cy) with direction (dx, dy).
  void _drawReticle(
    Canvas canvas,
    double cx,
    double cy,
    double dx,
    double dy,
    Paint paint,
  ) {
    canvas.drawLine(
      Offset(cx, cy),
      Offset(cx + _kReticleArm * dx, cy),
      paint,
    );
    canvas.drawLine(
      Offset(cx, cy),
      Offset(cx, cy + _kReticleArm * dy),
      paint,
    );
  }

  @override
  bool shouldRepaint(_VoteCardChromePainter oldDelegate) {
    return oldDelegate.isRecorded != isRecorded ||
        oldDelegate.isSilentVote != isSilentVote ||
        oldDelegate.reduceMotion != reduceMotion;
  }
}

// ═══════════════════════════════════════════════════════════
// VOTE BADGE: VERDICT STAMP WITH SEAL GLOW
// ═══════════════════════════════════════════════════════════

/// CustomPaint verdict badge. Recorded votes get a teal validation
/// stamp with corner ticks and sigma-4 glow bloom (wax seal illumination).
/// Not-recorded gets gray fill + void hatch (absent from record).
class _VoteBadgePaint extends StatelessWidget {
  const _VoteBadgePaint({
    required this.label,
    required this.isRecorded,
  });

  final String label;
  final bool isRecorded;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _BadgeChromePainter(isRecorded: isRecorded),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: BaselineSpacing.sm, // 12px
          vertical: BaselineSpacing.xxs,  // 4px
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: BaselineTypography.dataSmall.copyWith(
            color: isRecorded
                ? BaselineColors.voteRecorded
                : BaselineColors.textPrimary,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.0,
          ),
        ),
      ),
    );
  }
}

/// Paints the badge chrome: border + glow bloom + corner ticks (recorded),
/// or fill + void hatch (not recorded).
/// Border hierarchy: recorded = 2px (stamped verdict), not-recorded = 1px
/// (intentionally subordinate, absent from record).
class _BadgeChromePainter extends CustomPainter {
  const _BadgeChromePainter({required this.isRecorded});

  final bool isRecorded;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final radius = h / 2; // Fully rounded pill.
    final rrect = RRect.fromLTRBR(0, 0, w, h, Radius.circular(radius));

    if (isRecorded) {
      // Verdict stamp glow bloom (sigma-4, behind border).
      final glowPaint = Paint()
        ..color = BaselineColors.voteRecorded.atOpacity(0.12)
        ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 4);
      canvas.drawRRect(rrect, glowPaint);

      // Teal 2px outline: the stamp border (stamped verdict).
      final borderPaint = Paint()
        ..color = BaselineColors.voteRecorded
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
      canvas.drawRRect(rrect, borderPaint);

      // Corner validation ticks (cardinal points).
      final tickPaint = Paint()
        ..color = BaselineColors.voteRecorded.atOpacity(0.4)
        ..strokeWidth = 1.0;
      // Top center.
      canvas.drawLine(Offset(w / 2, -1), Offset(w / 2, -3), tickPaint);
      // Bottom center.
      canvas.drawLine(Offset(w / 2, h + 1), Offset(w / 2, h + 3), tickPaint);
      // Left center.
      canvas.drawLine(Offset(-1, h / 2), Offset(-3, h / 2), tickPaint);
      // Right center.
      canvas.drawLine(Offset(w + 1, h / 2), Offset(w + 3, h / 2), tickPaint);
    } else {
      // Not recorded: gray fill + void hatch.
      final fillPaint = Paint()
        ..color = BaselineColors.voteNotRecorded.atOpacity(0.15);
      canvas.drawRRect(rrect, fillPaint);

      // Void hatch micro-lines (diagonal, subtle).
      canvas.save();
      canvas.clipRRect(rrect);
      final hatchPaint = Paint()
        ..color = BaselineColors.voteNotRecorded.atOpacity(0.06)
        ..strokeWidth = 0.5;
      for (double x = -h; x < w + h; x += 6) {
        canvas.drawLine(Offset(x, h), Offset(x + h, 0), hatchPaint);
      }
      canvas.restore();

      // Subtle border (1px, intentionally subordinate to 2px stamped).
      final borderPaint = Paint()
        ..color = BaselineColors.voteNotRecorded.atOpacity(0.2)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;
      canvas.drawRRect(rrect, borderPaint);
    }
  }

  @override
  bool shouldRepaint(_BadgeChromePainter oldDelegate) {
    return oldDelegate.isRecorded != isRecorded;
  }
}
