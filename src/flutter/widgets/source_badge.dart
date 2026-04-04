/// F2.6 -- Source Badge (Credential Stamp) -- LOCKED
///
/// Official provenance marker. FBI badge meets notary seal meets
/// classified document provenance chain. Appears on every statement
/// surface in the app (legally required, never hidden).
///
/// On mount, the seal ring pulses once (credential verification at a
/// door reader). A hair-thin provenance thread physically connects
/// seal → dot → name → arrow → terminator. On press, the seal emits
/// a ring flash (badge scanned). Micro "SRC" classification text
/// floats above the seal. When no favicon exists, a crosshair sits
/// inside the seal ring (source not yet acquired).
///
/// 34 visual treatments. Bespoke globe + arrow icons. Notary ticks.
/// Provenance thread. Verification pulse. Nobody else has this on
/// a source attribution link.
///
/// LEGAL REQUIREMENT: Must appear on every surface where a
/// statement is shown. Never hide, collapse, or make optional.
///
/// Usage:
///   SourceBadge(
///     sourceName: 'Reuters',
///     sourceUrl: 'https://reuters.com/article/...',
///     favicon: CachedNetworkImage(
///       imageUrl: 'https://www.google.com/s2/favicons?domain=reuters.com&sz=32',
///       width: 16, height: 16,
///     ),
///   )
///
/// Data source: get-statement (A9C), get-feed (A9B) → source_url field.
///
/// Path: lib/widgets/source_badge.dart
library;

// 1. Dart SDK
import 'dart:math' as math;
import 'dart:ui' show PlatformDispatcher;

// 2. Flutter
import 'package:flutter/material.dart';

// 3. Third-party
import 'package:url_launcher/url_launcher.dart';

// 4. Project ── config
import 'package:baseline_app/config/theme.dart';

// 5. Project ── utils
import 'package:baseline_app/utils/haptic_util.dart';

// ═══════════════════════════════════════════════════════════
// CONSTANTS
// ═══════════════════════════════════════════════════════════

// ── Seal geometry ───────────────────────────────────────

/// Favicon size inside seal.
const double _kFaviconSize = 16.0;

/// Outer seal ring diameter.
const double _kSealRingSize = 22.0;

/// Seal ring stroke width.
const double _kSealBorderWidth = 1.5;

/// Total seal widget size (ring + notary tick overhang).
const double _kSealTotalSize = 26.0;

// ── Seal ring notary ticks ──────────────────────────────

/// Cardinal tick outward length from ring edge.
const double _kNotaryTickLength = 2.0;

/// Tick stroke width.
const double _kNotaryTickStroke = 0.5;

/// Tick opacity.
const double _kNotaryTickOpacity = 0.15;

// ── Seal verification pulse ─────────────────────────────

/// Pulse animation duration (single pass on mount).
const Duration _kSealPulseDuration = Duration(milliseconds: 350);

/// Seal ring base opacity.
const double _kSealOpacity = 0.20;

/// Seal ring peak opacity during pulse.
const double _kSealPulseOpacity = 0.50;

/// Pulse outward expansion in px.
const double _kSealPulseExpand = 3.0;

// ── Seal tap ring flash ─────────────────────────────────

/// Tap flash glow blur sigma.
const double _kTapFlashSigma = 4.0;

/// Tap flash glow peak opacity.
const double _kTapFlashOpacity = 0.35;

// ── Seal inner crosshair (fallback, no favicon) ────────

/// Crosshair arm length.
const double _kCrosshairArm = 3.0;

/// Crosshair stroke width.
const double _kCrosshairStroke = 0.4;

/// Crosshair opacity.
const double _kCrosshairOpacity = 0.20;

// ── Micro "SRC" classification stamp ────────────────────

/// Classification text font size.
const double _kSrcFontSize = 4.0;

/// Classification text opacity.
const double _kSrcOpacity = 0.06;

// ── Classification micro-dot ────────────────────────────

/// Dot diameter.
const double _kDotSize = 2.0;

// ── External arrow ──────────────────────────────────────

/// Arrow icon size.
const double _kArrowSize = 11.0;

/// Arrow opacity ── subordinate to source name.
const double _kArrowOpacity = 0.70;

// ── Provenance chain terminator ─────────────────────────

/// Terminal dot size.
const double _kChainDotSize = 1.5;

/// Terminal dot opacity.
const double _kChainDotOpacity = 0.25;

// ── Provenance thread ───────────────────────────────────

/// Thread stroke width (hair-thin).
const double _kThreadStroke = 0.3;

/// Thread opacity.
const double _kThreadOpacity = 0.08;

// ── Press-scale ─────────────────────────────────────────

const double _kPressScale = 0.95;

// ── Entry animation ─────────────────────────────────────

const Duration _kEntryDuration = Duration(milliseconds: 300);

// ── Press underline flash ───────────────────────────────

const Duration _kUnderlineDuration = Duration(milliseconds: 120);

// ── Source name ─────────────────────────────────────────

/// Letter-spacing for credential identifier feel.
const double _kNameLetterSpacing = 0.3;

// ── Void state ──────────────────────────────────────────

/// Opacity when URL is invalid (unlinked credential).
const double _kVoidOpacity = 0.40;

// ═══════════════════════════════════════════════════════════
// WIDGET
// ═══════════════════════════════════════════════════════════

class SourceBadge extends StatefulWidget {
  const SourceBadge({
    super.key,
    this.sourceName = '',
    required this.sourceUrl,
    this.onLaunchFailed,
    this.favicon,
  });

  /// Human-readable source name (e.g., "Reuters", "White House").
  final String sourceName;

  /// Full URL to the original source. Must be http or https.
  final String sourceUrl;

  /// Called when URL launch fails. Screen can show a snackbar/toast.
  final VoidCallback? onLaunchFailed;

  /// FE-12: 16×16 favicon widget from parent.
  /// Falls back to a bespoke globe + crosshair when null.
  final Widget? favicon;

  @override
  State<SourceBadge> createState() => _SourceBadgeState();
}

class _SourceBadgeState extends State<SourceBadge>
    with TickerProviderStateMixin {
  late final AnimationController _entryCtrl;
  late final AnimationController _sealPulseCtrl;
  bool _pressed = false;

  // ── Cached validation ──────────────────────────────────

  late String _trimmedName;
  late Uri? _validUri;
  bool get _hasValidLink => _validUri != null;

  void _cacheFields() {
    _trimmedName = widget.sourceName.trim();
    _validUri = _parseUri(widget.sourceUrl);
  }

  static Uri? _parseUri(String raw) {
    var url = raw.trim();
    if (url.isEmpty) return null;
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://$url';
    }
    final uri = Uri.tryParse(url);
    if (uri == null) return null;
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    if (uri.host.isEmpty) return null;
    return uri;
  }

  // ── Reduce motion ──────────────────────────────────────

  late final bool _reduceMotion;

  // ── Lifecycle ──────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _cacheFields();
    _reduceMotion = PlatformDispatcher
        .instance.accessibilityFeatures.reduceMotion;

    _entryCtrl = AnimationController(
      vsync: this,
      duration: _kEntryDuration,
    );

    _sealPulseCtrl = AnimationController(
      vsync: this,
      duration: _kSealPulseDuration,
    );

    if (_reduceMotion) {
      _entryCtrl.value = 1.0;
    } else {
      _entryCtrl.forward();
      // Seal verification pulse fires after entry completes.
      _entryCtrl.addStatusListener(_onEntryDone);
    }
  }

  void _onEntryDone(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _sealPulseCtrl.forward();
    }
  }

  @override
  void didUpdateWidget(covariant SourceBadge old) {
    super.didUpdateWidget(old);
    if (old.sourceName != widget.sourceName ||
        old.sourceUrl != widget.sourceUrl) {
      _cacheFields();
    }
  }

  @override
  void dispose() {
    _entryCtrl.removeStatusListener(_onEntryDone);
    _entryCtrl.dispose();
    _sealPulseCtrl.dispose();
    super.dispose();
  }

  // ── Interaction ────────────────────────────────────────

  void _onTapDown(TapDownDetails _) {
    if (!_hasValidLink) return;
    setState(() => _pressed = true);
  }

  void _onTapUp(TapUpDetails _) {
    if (!_hasValidLink) return;
    setState(() => _pressed = false);
    _openSource();
  }

  void _onTapCancel() {
    if (_pressed) setState(() => _pressed = false);
  }

  Future<void> _openSource() async {
    final uri = _validUri;
    if (uri == null) {
      widget.onLaunchFailed?.call();
      return;
    }

    HapticUtil.light();

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (!mounted) return;
      widget.onLaunchFailed?.call();
    }
  }

  // ── Build ──────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_trimmedName.isEmpty) return const SizedBox.shrink();

    final scale = _pressed && !_reduceMotion ? _kPressScale : 1.0;

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: Listenable.merge([_entryCtrl, _sealPulseCtrl]),
        builder: (context, _) {
          return FadeTransition(
            opacity: _entryCtrl,
            child: Semantics(
              container: true,
              label: 'Source',
              value: _trimmedName,
              hint: _hasValidLink ? 'Opens external link' : null,
              link: _hasValidLink,
              onTap: _hasValidLink ? _openSource : null,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: BaselineTouchTarget.min,
                ),
                child: GestureDetector(
                  onTapDown: _onTapDown,
                  onTapUp: _onTapUp,
                  onTapCancel: _onTapCancel,
                  behavior: HitTestBehavior.opaque,
                  child: AnimatedScale(
                    scale: scale,
                    duration: _reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 100),
                    child: CustomPaint(
                      painter: _ProvenanceThreadPainter(
                        hasLink: _hasValidLink,
                        entry: _entryCtrl.value,
                      ),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // ── Credential Seal ──────────────
                            _buildSeal(),
                            const SizedBox(width: BaselineSpacing.xs),

                            // ── Classification micro-dot ─────
                            ExcludeSemantics(
                              child: Container(
                                width: _kDotSize,
                                height: _kDotSize,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: BaselineColors.teal.atOpacity(
                                    _hasValidLink ? 0.35 : 0.15,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: BaselineSpacing.xs),

                            // ── Source Name ──────────────────
                            Flexible(
                              child: ExcludeSemantics(
                                child: _buildName(),
                              ),
                            ),

                            // ── Arrow + Chain Terminator ─────
                            if (_hasValidLink) ...[
                              const SizedBox(width: BaselineSpacing.xxs),
                              ExcludeSemantics(
                                child: SizedBox(
                                  width: _kArrowSize,
                                  height: _kArrowSize,
                                  child: CustomPaint(
                                    painter: _ArrowPainter(
                                      color: BaselineColors.teal.atOpacity(
                                        _kArrowOpacity,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 3),
                              ExcludeSemantics(
                                child: Container(
                                  width: _kChainDotSize,
                                  height: _kChainDotSize,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: BaselineColors.teal.atOpacity(
                                      _kChainDotOpacity,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Sub-builds ─────────────────────────────────────────

  /// Credential seal: favicon inside teal ring with notary ticks,
  /// verification pulse, tap flash, and "SRC" classification stamp.
  Widget _buildSeal() {
    return ExcludeSemantics(
      child: SizedBox(
        width: _kSealTotalSize,
        height: _kSealTotalSize,
        child: CustomPaint(
          painter: _SealPainter(
            ringColor: BaselineColors.teal.atOpacity(_kSealOpacity),
            tickColor: BaselineColors.teal.atOpacity(_kNotaryTickOpacity),
            pulseProgress: _sealPulseCtrl.value,
            pressed: _pressed,
            hasLink: _hasValidLink,
          ),
          child: Center(
            child: ClipOval(
              clipBehavior: Clip.antiAlias,
              child: SizedBox(
                width: _kFaviconSize,
                height: _kFaviconSize,
                child: widget.favicon ?? _buildFallbackIcon(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Fallback: bespoke globe + crosshair (source not yet acquired).
  Widget _buildFallbackIcon() {
    return SizedBox(
      width: 10,
      height: 10,
      child: CustomPaint(
        painter: _GlobePainter(
          color: BaselineColors.teal.atOpacity(
            _hasValidLink ? 0.50 : 0.25,
          ),
          showCrosshair: true,
        ),
      ),
    );
  }

  /// Source name with credential typography and press underline.
  Widget _buildName() {
    final color = _hasValidLink
        ? BaselineColors.teal
        : BaselineColors.teal.atOpacity(_kVoidOpacity);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _trimmedName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: BaselineTypography.body2.copyWith(
            color: color,
            letterSpacing: _kNameLetterSpacing,
          ),
        ),
        // Press feedback flash (120ms momentary). NOT a structural
        // border: 0.5px decorative chrome, same ruling as F2.5 inner
        // chrome borders. 2px doctrine applies to card/interactive borders.
        AnimatedContainer(
          duration: _kUnderlineDuration,
          height: 0.5,
          margin: const EdgeInsets.only(top: 1),
          decoration: BoxDecoration(
            color: _pressed
                ? BaselineColors.teal.atOpacity(0.40)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(0.25),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════
// PAINTERS
// ═══════════════════════════════════════════════════════════

/// Credential seal ring with notary ticks, verification pulse,
/// tap ring flash, and "SRC" classification stamp.
class _SealPainter extends CustomPainter {
  _SealPainter({
    required this.ringColor,
    required this.tickColor,
    required this.pulseProgress,
    required this.pressed,
    required this.hasLink,
  });

  final Color ringColor;
  final Color tickColor;
  final double pulseProgress;
  final bool pressed;
  final bool hasLink;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final ringRadius = _kSealRingSize / 2;

    // ── Tap ring flash (pressed state glow) ─────────────
    if (pressed && hasLink) {
      canvas.drawCircle(
        center,
        ringRadius + 2,
        Paint()
          ..color = BaselineColors.teal.atOpacity(_kTapFlashOpacity)
          ..maskFilter = const MaskFilter.blur(
            BlurStyle.normal, _kTapFlashSigma,
          ),
      );
    }

    // ── Verification pulse ring (expands outward, fades) ─
    if (pulseProgress > 0.0 && pulseProgress < 1.0) {
      final expand = _kSealPulseExpand * pulseProgress;
      final fade = 1.0 - pulseProgress;
      final pulseOpacity =
          (_kSealPulseOpacity - _kSealOpacity) * fade + _kSealOpacity;

      canvas.drawCircle(
        center,
        ringRadius + expand,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = _kSealBorderWidth * (1.0 - pulseProgress * 0.5)
          ..color = BaselineColors.teal.atOpacity(pulseOpacity * fade),
      );
    }

    // ── Main seal ring ──────────────────────────────────
    // Brightens slightly during pulse, then returns to base.
    double ringOpacityBoost = 0.0;
    if (pulseProgress > 0.0 && pulseProgress < 0.3) {
      // Brief brighten at start of pulse.
      ringOpacityBoost = (1.0 - pulseProgress / 0.3) * 0.15;
    }

    canvas.drawCircle(
      center,
      ringRadius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _kSealBorderWidth
        ..color = BaselineColors.teal.atOpacity(
          _kSealOpacity + ringOpacityBoost,
        ),
    );

    // ── Notary ticks (4 cardinal positions) ─────────────
    final notaryPaint = Paint()
      ..strokeWidth = _kNotaryTickStroke
      ..color = tickColor
      ..strokeCap = StrokeCap.round;

    for (int i = 0; i < 4; i++) {
      final angle = i * math.pi / 2;
      final innerR = ringRadius - 1;
      final outerR = ringRadius + _kNotaryTickLength;
      canvas.drawLine(
        Offset(
          center.dx + innerR * math.cos(angle),
          center.dy + innerR * math.sin(angle),
        ),
        Offset(
          center.dx + outerR * math.cos(angle),
          center.dy + outerR * math.sin(angle),
        ),
        notaryPaint,
      );
    }

    // ── "SRC" micro-classification stamp ────────────────
    final srcTp = TextPainter(
      text: TextSpan(
        text: 'SRC',
        style: TextStyle(
          fontFamily: BaselineTypography.monoFontFamily,
          fontSize: _kSrcFontSize,
          color: BaselineColors.teal.atOpacity(_kSrcOpacity),
          letterSpacing: 0.8,
          fontWeight: FontWeight.w300,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    srcTp.paint(
      canvas,
      Offset(
        center.dx - srcTp.width / 2,
        center.dy - ringRadius - srcTp.height - 1,
      ),
    );
    srcTp.dispose();
  }

  @override
  bool shouldRepaint(_SealPainter old) =>
      ringColor != old.ringColor ||
      tickColor != old.tickColor ||
      pulseProgress != old.pulseProgress ||
      pressed != old.pressed ||
      hasLink != old.hasLink;
}

/// Provenance thread: hair-thin line connecting all badge elements.
/// Drawn as the background CustomPaint behind the Row children.
/// The chain of custody is physically visible.
class _ProvenanceThreadPainter extends CustomPainter {
  _ProvenanceThreadPainter({
    required this.hasLink,
    required this.entry,
  });

  final bool hasLink;
  final double entry;

  @override
  void paint(Canvas canvas, Size size) {
    if (entry < 0.1) return;

    final y = size.height / 2;
    // Thread runs from seal right edge to widget right edge.
    // Starts after the seal (approx _kSealTotalSize) and goes to end.
    final startX = _kSealTotalSize * 0.7;
    final endX = hasLink ? size.width : size.width * 0.7;

    final opacity = _kThreadOpacity * entry;
    if (opacity < 0.002) return;

    canvas.drawLine(
      Offset(startX, y),
      Offset(endX, y),
      Paint()
        ..strokeWidth = _kThreadStroke
        ..color = BaselineColors.teal.atOpacity(opacity),
    );
  }

  @override
  bool shouldRepaint(_ProvenanceThreadPainter old) =>
      hasLink != old.hasLink ||
      entry != old.entry;
}

/// Bespoke globe icon with optional crosshair (fallback).
class _GlobePainter extends CustomPainter {
  _GlobePainter({
    required this.color,
    this.showCrosshair = false,
  });

  final Color color;
  final bool showCrosshair;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2 - 0.5;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = color;

    // Outer circle.
    canvas.drawCircle(center, r, paint);

    // Equator.
    canvas.drawLine(
      Offset(center.dx - r, center.dy),
      Offset(center.dx + r, center.dy),
      paint,
    );

    // Prime meridian (narrow ellipse).
    canvas.drawOval(
      Rect.fromCenter(center: center, width: r * 0.9, height: r * 2),
      paint,
    );

    // Tilted meridian (wider ellipse, depth).
    canvas.drawOval(
      Rect.fromCenter(center: center, width: r * 1.5, height: r * 2),
      paint,
    );

    // Crosshair overlay when source not yet acquired.
    if (showCrosshair) {
      final chPaint = Paint()
        ..strokeWidth = _kCrosshairStroke
        ..color = BaselineColors.teal.atOpacity(_kCrosshairOpacity)
        ..strokeCap = StrokeCap.round;

      final arm = _kCrosshairArm;
      // Vertical.
      canvas.drawLine(
        Offset(center.dx, center.dy - arm),
        Offset(center.dx, center.dy + arm),
        chPaint,
      );
      // Horizontal.
      canvas.drawLine(
        Offset(center.dx - arm, center.dy),
        Offset(center.dx + arm, center.dy),
        chPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_GlobePainter old) =>
      color != old.color || showCrosshair != old.showCrosshair;
}

/// Bespoke north-east arrow (no stock icons).
class _ArrowPainter extends CustomPainter {
  _ArrowPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..strokeWidth = 1.2
      ..color = color
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final w = size.width;
    final h = size.height;
    final margin = w * 0.15;
    final topRight = Offset(w - margin, margin);
    final bottomLeft = Offset(margin, h - margin);

    canvas.drawLine(bottomLeft, topRight, paint);

    final headLen = w * 0.32;
    canvas.drawPath(
      Path()
        ..moveTo(topRight.dx - headLen, topRight.dy)
        ..lineTo(topRight.dx, topRight.dy)
        ..lineTo(topRight.dx, topRight.dy + headLen),
      paint,
    );
  }

  @override
  bool shouldRepaint(_ArrowPainter old) => color != old.color;
}
