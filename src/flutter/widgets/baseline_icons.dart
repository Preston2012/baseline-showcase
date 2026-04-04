/// F-ICONS: BASELINE Bespoke Icon Library (Utility Set) V2
///
/// 96 utility icons for navigation, actions, status, tab bar,
/// content, features, and settings. Every path is hand-drawn on
/// Canvas using the BASELINE visual vocabulary.
///
/// V2: Consolidated from F4.4 (34 feature icons) + F4.17 (25
/// settings icons) + original 37 utility icons.
///
/// This file IS part of the sellable icon pack.
/// For TM stamps, see baseline_tm_icons.dart (brand-exclusive).
///
/// Path: lib/widgets/baseline_icons.dart
library;

// 1. Dart SDK
import 'dart:math' as math;
import 'dart:ui' as ui;

// 2. Flutter
import 'package:flutter/material.dart';

// 3. Project: config
import 'package:baseline_app/config/theme.dart';

// ── File-level constants ──
const String _kMonoFontFamily = BaselineTypography.monoFontFamily;
const double _kMicroLabelFontSize = 5.5;

// ═══════════════════════════════════════════════════════════
// ICON TYPE ENUM (96 values)
// ═══════════════════════════════════════════════════════════

enum BaselineIconType {
  // ── Navigation (6) ──
  backArrow,
  arrowForward,
  arrowUpward,
  chevronRight,
  northEast,
  northWest,

  // ── Actions (9) ──
  search,
  clear,
  export,
  cite,
  share,
  bookmark,
  check,
  checkCircle,
  deleteIcon,

  // ── Status (7) ──
  info,
  error,
  warning,
  offline,
  cloudOff,
  noResults,
  syncIcon,

  // ── Tab Bar (6) ──
  tabToday,
  tabPerson,
  tabSearch,
  tabExplore,
  tabBills,
  tabSettings,

  // ── Content (11) ──
  star,
  starOutline,
  person,
  personOutline,
  globe,
  chart,
  history,
  lock,
  email,
  visibility,
  visibilityOff,

  // ── Feature Icons (from F4.4) (34) ──
  signalMetrics,
  delta,
  consensus,
  variance,
  trends,
  sort,
  feedCards,
  trending,
  why,
  attribution,
  feedSort,
  peek,
  annotate,
  profile,
  badgeWeek,
  silent,
  favorites,
  heatmap,
  vote,
  bill,
  resonance,
  cascade,
  league,
  annotatePrivate,
  request,
  featureInfo,
  guide,
  featureExport,
  ghost,
  copy,
  watermark,
  digest,
  notifs,
  shift,
  threshold,
  annDelta,

  // ── Settings Icons (from F4.17) (25) ──
  sectionAccount,
  sectionSubscription,
  sectionPreferences,
  sectionFeedback,
  sectionAbout,
  user,
  signOut,
  signIn,
  currentPlan,
  manageSubscription,
  restorePurchases,
  appearance,
  notifications,
  haptic,
  rateStar,
  reportBug,
  contactSupport,
  shareApp,
  methodology,
  privacy,
  terms,
  changelog,
  deleteAccount,
  upgradeGem,
  // Additional
  close,
  signalLost,
  searchOff,
  delete,
}

// ═══════════════════════════════════════════════════════════
// CONVENIENCE WIDGET
// ═══════════════════════════════════════════════════════════

class BaselineIcon extends StatelessWidget {
  const BaselineIcon(
    this.icon, {
    super.key,
    required this.size,
    required this.color,
    this.filled = false,
    this.semanticLabel,
  });

  factory BaselineIcon.teal(
    BaselineIconType icon, {
    Key? key,
    required double size,
    bool filled = false,
    String? semanticLabel,
  }) =>
      BaselineIcon(icon, key: key, size: size, color: BaselineColors.teal,
          filled: filled, semanticLabel: semanticLabel);

  factory BaselineIcon.amber(
    BaselineIconType icon, {
    Key? key,
    required double size,
    bool filled = false,
    String? semanticLabel,
  }) =>
      BaselineIcon(icon, key: key, size: size, color: BaselineColors.amber,
          filled: filled, semanticLabel: semanticLabel);

  factory BaselineIcon.muted(
    BaselineIconType icon, {
    Key? key,
    required double size,
    bool filled = false,
    String? semanticLabel,
  }) =>
      BaselineIcon(icon, key: key, size: size,
          color: BaselineColors.textSecondary,
          filled: filled, semanticLabel: semanticLabel);

  final BaselineIconType icon;
  final double size;
  final Color color;
  final bool filled;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final child = SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        size: Size(size, size),
        painter: BaselineIconPainter(
          icon: icon, color: color, filled: filled,
          textScaler: scaler,
        ),
      ),
    );
    if (semanticLabel != null) {
      return Semantics(
        label: semanticLabel,
        excludeSemantics: true,
        child: child,
      );
    }
    return ExcludeSemantics(child: child);
  }
}

// ═══════════════════════════════════════════════════════════
// ICON PAINTER (96 icons)
// ═══════════════════════════════════════════════════════════

class BaselineIconPainter extends CustomPainter {
  BaselineIconPainter({
    required this.icon,
    required this.color,
    this.filled = false,
    this.textScaler = TextScaler.noScaling,
  })  : _stroke = Paint()
          ..color = color..strokeWidth = 1.5
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round,
        _strokeHeavy = Paint()
          ..color = color..strokeWidth = 2.0
          ..style = PaintingStyle.stroke..strokeCap = StrokeCap.round,
        _strokeLight = Paint()
          ..color = color.atOpacity(0.5)..strokeWidth = 0.8
          ..style = PaintingStyle.stroke..strokeCap = StrokeCap.round,
        _fill = Paint()..color = color..style = PaintingStyle.fill,
        _fillDim = Paint()
          ..color = color.atOpacity(0.4)..style = PaintingStyle.fill,
        _primary = Paint()
          ..color = color.atOpacity(0.8)..strokeWidth = 1.2
          ..style = PaintingStyle.stroke..strokeCap = StrokeCap.round,
        _secondary = Paint()
          ..color = color.atOpacity(0.33)..strokeWidth = 0.8
          ..style = PaintingStyle.stroke..strokeCap = StrokeCap.round,
        _featureFill = Paint()
          ..color = color.atOpacity(0.8)..style = PaintingStyle.fill,
        _featureFillDim = Paint()
          ..color = color.atOpacity(0.33)..style = PaintingStyle.fill,
        _work = Paint();

  final BaselineIconType icon;
  final Color color;
  final bool filled;
  final TextScaler textScaler;

  // ── Paint objects (initialized once in constructor) ──
  final Paint _stroke;
  final Paint _strokeHeavy;
  final Paint _strokeLight;
  final Paint _fill;
  final Paint _fillDim;
  final Paint _primary;
  final Paint _secondary;
  final Paint _featureFill;
  final Paint _featureFillDim;
  /// Mutable scratch paint for loops and one-off variations.
  final Paint _work;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final c = Offset(s / 2, s / 2);
    switch (icon) {
      // ── Navigation (6) ──
      case BaselineIconType.backArrow:     _drawBackArrow(canvas, s, c);
      case BaselineIconType.arrowForward:  _drawArrowForward(canvas, s, c);
      case BaselineIconType.arrowUpward:   _drawArrowUpward(canvas, s, c);
      case BaselineIconType.chevronRight:  _drawChevronRight(canvas, s, c);
      case BaselineIconType.northEast:     _drawNorthEast(canvas, s, c);
      case BaselineIconType.northWest:     _drawNorthWest(canvas, s, c);
      // ── Actions (9) ──
      case BaselineIconType.search:        _drawSearch(canvas, s, c);
      case BaselineIconType.clear:         _drawClear(canvas, s, c);
      case BaselineIconType.export:        _drawExport(canvas, s, c);
      case BaselineIconType.cite:          _drawCite(canvas, s, c);
      case BaselineIconType.share:         _drawShare(canvas, s, c);
      case BaselineIconType.bookmark:      _drawBookmark(canvas, s, c);
      case BaselineIconType.check:         _drawCheck(canvas, s, c);
      case BaselineIconType.checkCircle:   _drawCheckCircle(canvas, s, c);
      case BaselineIconType.deleteIcon:    _drawDelete(canvas, s, c);
      // ── Status (7) ──
      case BaselineIconType.info:          _drawInfo(canvas, s, c);
      case BaselineIconType.error:         _drawError(canvas, s, c);
      case BaselineIconType.warning:       _drawWarning(canvas, s, c);
      case BaselineIconType.offline:       _drawOffline(canvas, s, c);
      case BaselineIconType.cloudOff:      _drawCloudOff(canvas, s, c);
      case BaselineIconType.noResults:     _drawNoResults(canvas, s, c);
      case BaselineIconType.syncIcon:      _drawSync(canvas, s, c);
      // ── Tab Bar (5) ──
      case BaselineIconType.tabToday:      _drawTabToday(canvas, s, c);
      case BaselineIconType.tabPerson:     _drawTabPerson(canvas, s, c);
      case BaselineIconType.tabSearch:     _drawTabSearch(canvas, s, c);
      case BaselineIconType.tabExplore:    _drawTabExplore(canvas, s, c);
      case BaselineIconType.tabBills:      _drawTabBills(canvas, s, c);
      case BaselineIconType.tabSettings:   _drawTabSettings(canvas, s, c);
      // ── Content (11) ──
      case BaselineIconType.star:          _drawStar(canvas, s, c, filled: true);
      case BaselineIconType.starOutline:   _drawStar(canvas, s, c, filled: false);
      case BaselineIconType.person:        _drawPerson(canvas, s, c, filled: true);
      case BaselineIconType.personOutline: _drawPerson(canvas, s, c, filled: false);
      case BaselineIconType.globe:         _drawGlobe(canvas, s, c);
      case BaselineIconType.chart:         _drawChart(canvas, s, c);
      case BaselineIconType.history:       _drawHistory(canvas, s, c);
      case BaselineIconType.lock:          _drawLock(canvas, s, c);
      case BaselineIconType.email:         _drawEmail(canvas, s, c);
      case BaselineIconType.visibility:    _drawVisibility(canvas, s, c, visible: true);
      case BaselineIconType.visibilityOff: _drawVisibility(canvas, s, c, visible: false);
      // ── Feature Icons (34) ──
      case BaselineIconType.signalMetrics:   _drawSignalMetrics(canvas, s, c);
      case BaselineIconType.delta:           _drawDelta(canvas, s, c);
      case BaselineIconType.consensus:       _drawConsensus(canvas, s, c);
      case BaselineIconType.variance:        _drawVariance(canvas, s, c);
      case BaselineIconType.trends:          _drawTrends(canvas, s, c);
      case BaselineIconType.sort:            _drawSort(canvas, s, c);
      case BaselineIconType.feedCards:       _drawFeedCards(canvas, s, c);
      case BaselineIconType.trending:        _drawTrending(canvas, s, c);
      case BaselineIconType.why:             _drawWhy(canvas, s, c);
      case BaselineIconType.attribution:     _drawAttribution(canvas, s, c);
      case BaselineIconType.feedSort:        _drawFeedSort(canvas, s, c);
      case BaselineIconType.peek:            _drawPeek(canvas, s, c);
      case BaselineIconType.annotate:        _drawAnnotate(canvas, s, c);
      case BaselineIconType.profile:         _drawProfile(canvas, s, c);
      case BaselineIconType.badgeWeek:       _drawBadgeWeek(canvas, s, c);
      case BaselineIconType.silent:          _drawSilent(canvas, s, c);
      case BaselineIconType.favorites:       _drawFavorites(canvas, s, c);
      case BaselineIconType.heatmap:         _drawHeatmap(canvas, s, c);
      case BaselineIconType.vote:            _drawVote(canvas, s, c);
      case BaselineIconType.bill:            _drawBill(canvas, s, c);
      case BaselineIconType.resonance:       _drawResonance(canvas, s, c);
      case BaselineIconType.cascade:         _drawCascade(canvas, s, c);
      case BaselineIconType.league:          _drawLeague(canvas, s, c);
      case BaselineIconType.annotatePrivate: _drawAnnotatePrivate(canvas, s, c);
      case BaselineIconType.request:         _drawRequest(canvas, s, c);
      case BaselineIconType.featureInfo:     _drawFeatureInfo(canvas, s, c);
      case BaselineIconType.guide:           _drawGuide(canvas, s, c);
      case BaselineIconType.featureExport:   _drawFeatureExport(canvas, s, c);
      case BaselineIconType.ghost:           _drawGhost(canvas, s, c);
      case BaselineIconType.copy:            _drawCopy(canvas, s, c);
      case BaselineIconType.watermark:       _drawWatermark(canvas, s, c);
      case BaselineIconType.digest:          _drawDigest(canvas, s, c);
      case BaselineIconType.notifs:          _drawNotifs(canvas, s, c);
      case BaselineIconType.shift:           _drawShift(canvas, s, c);
      case BaselineIconType.threshold:       _drawThreshold(canvas, s, c);
      case BaselineIconType.annDelta:        _drawAnnDelta(canvas, s, c);
      // ── Settings Icons (25) ──
      case BaselineIconType.sectionAccount:      _drawSectionShield(canvas, s, c);
      case BaselineIconType.sectionSubscription: _drawSectionGem(canvas, s, c);
      case BaselineIconType.sectionPreferences:  _drawSectionTuning(canvas, s, c);
      case BaselineIconType.sectionFeedback:     _drawSectionBroadcast(canvas, s, c);
      case BaselineIconType.sectionAbout:        _drawSectionDoc(canvas, s, c);
      case BaselineIconType.user:                _drawUser(canvas, s, c);
      case BaselineIconType.signOut:             _drawSignOut(canvas, s, c);
      case BaselineIconType.signIn:              _drawSignIn(canvas, s, c);
      case BaselineIconType.currentPlan:         _drawCurrentPlan(canvas, s, c);
      case BaselineIconType.manageSubscription:  _drawManageSub(canvas, s, c);
      case BaselineIconType.restorePurchases:    _drawRestore(canvas, s, c);
      case BaselineIconType.appearance:          _drawAppearance(canvas, s, c);
      case BaselineIconType.notifications:       _drawNotifications(canvas, s, c);
      case BaselineIconType.haptic:              _drawHaptic(canvas, s, c);
      case BaselineIconType.rateStar:            _drawRateStar(canvas, s, c);
      case BaselineIconType.reportBug:           _drawReportBug(canvas, s, c);
      case BaselineIconType.contactSupport:      _drawContactSupport(canvas, s, c);
      case BaselineIconType.shareApp:            _drawShareApp(canvas, s, c);
      case BaselineIconType.methodology:         _drawMethodology(canvas, s, c);
      case BaselineIconType.privacy:             _drawPrivacy(canvas, s, c);
      case BaselineIconType.terms:               _drawTerms(canvas, s, c);
      case BaselineIconType.changelog:           _drawChangelog(canvas, s, c);
      case BaselineIconType.deleteAccount:       _drawDeleteAccount(canvas, s, c);
      case BaselineIconType.upgradeGem:          _drawUpgradeGem(canvas, s, c);
      // ── Additional Icons (4) ──
      case BaselineIconType.close:              _drawClear(canvas, s, c);
      case BaselineIconType.signalLost:         _drawOffline(canvas, s, c);
      case BaselineIconType.searchOff:          _drawSearch(canvas, s, c);
      case BaselineIconType.delete:             _drawDelete(canvas, s, c);
    }
  }

  @override
  bool shouldRepaint(BaselineIconPainter old) =>
      icon != old.icon || color != old.color || filled != old.filled ||
      textScaler != old.textScaler;

  // ═══════════════════════════════════════════════════════
  // SHARED HELPERS
  // ═══════════════════════════════════════════════════════

  void _drawReticleCorners(Canvas canvas, Rect rect, double arm) {
    final p = _secondary;
    canvas.drawLine(rect.topLeft, rect.topLeft + Offset(arm, 0), p);
    canvas.drawLine(rect.topLeft, rect.topLeft + Offset(0, arm), p);
    canvas.drawLine(rect.topRight, rect.topRight + Offset(-arm, 0), p);
    canvas.drawLine(rect.topRight, rect.topRight + Offset(0, arm), p);
    canvas.drawLine(rect.bottomLeft, rect.bottomLeft + Offset(arm, 0), p);
    canvas.drawLine(rect.bottomLeft, rect.bottomLeft + Offset(0, -arm), p);
    canvas.drawLine(rect.bottomRight, rect.bottomRight + Offset(-arm, 0), p);
    canvas.drawLine(rect.bottomRight, rect.bottomRight + Offset(0, -arm), p);
  }

  void _drawHashmarks(Canvas canvas, Offset start, Offset end, int count, double tickLen) {
    final p = _secondary;
    final dx = (end.dx - start.dx) / (count - 1);
    final dy = (end.dy - start.dy) / (count - 1);
    final isH = dx.abs() > dy.abs();
    for (int i = 0; i < count; i++) {
      final x = start.dx + dx * i; final y = start.dy + dy * i;
      final len = (i % 3 == 0) ? tickLen : tickLen * 0.5;
      if (isH) { canvas.drawLine(Offset(x, y - len), Offset(x, y + len), p); }
      else { canvas.drawLine(Offset(x - len, y), Offset(x + len, y), p); }
    }
  }

  void _drawMicroLabel(Canvas canvas, double s, String text, Offset pos) {
    final scaledSize = textScaler.scale(_kMicroLabelFontSize);
    final builder = ui.ParagraphBuilder(
      ui.ParagraphStyle(fontFamily: _kMonoFontFamily, fontSize: scaledSize, maxLines: 1),
    )..pushStyle(ui.TextStyle(color: color.atOpacity(0.45), letterSpacing: 0.8))
     ..addText(text);
    final para = builder.build()..layout(ui.ParagraphConstraints(width: s * 1.5));
    canvas.drawParagraph(para, pos);
  }

  // ═══════════════════════════════════════════════════════
  // NAVIGATION (6): core set
  // ═══════════════════════════════════════════════════════

  void _drawBackArrow(Canvas canvas, double s, Offset c) {
    final p = _strokeHeavy; final my = c.dy;
    canvas.drawLine(Offset(s * 0.7, my), Offset(s * 0.3, my), p);
    canvas.drawLine(Offset(s * 0.3, my), Offset(s * 0.3 + s * 0.15, my - s * 0.15), p);
    canvas.drawLine(Offset(s * 0.3, my), Offset(s * 0.3 + s * 0.15, my + s * 0.15), p);
  }

  void _drawArrowForward(Canvas canvas, double s, Offset c) {
    final p = _strokeHeavy; final my = c.dy;
    canvas.drawLine(Offset(s * 0.3, my), Offset(s * 0.7, my), p);
    canvas.drawLine(Offset(s * 0.7, my), Offset(s * 0.7 - s * 0.15, my - s * 0.15), p);
    canvas.drawLine(Offset(s * 0.7, my), Offset(s * 0.7 - s * 0.15, my + s * 0.15), p);
  }

  void _drawArrowUpward(Canvas canvas, double s, Offset c) {
    final p = _strokeHeavy; final mx = c.dx;
    canvas.drawLine(Offset(mx, s * 0.7), Offset(mx, s * 0.3), p);
    canvas.drawLine(Offset(mx, s * 0.3), Offset(mx - s * 0.15, s * 0.3 + s * 0.15), p);
    canvas.drawLine(Offset(mx, s * 0.3), Offset(mx + s * 0.15, s * 0.3 + s * 0.15), p);
  }

  void _drawChevronRight(Canvas canvas, double s, Offset c) {
    final p = _strokeHeavy;
    canvas.drawLine(Offset(s * 0.35, s * 0.25), Offset(s * 0.65, c.dy), p);
    canvas.drawLine(Offset(s * 0.65, c.dy), Offset(s * 0.35, s * 0.75), p);
  }

  void _drawNorthEast(Canvas canvas, double s, Offset c) {
    final p = _stroke;
    canvas.drawLine(Offset(s * 0.3, s * 0.7), Offset(s * 0.7, s * 0.3), p);
    canvas.drawLine(Offset(s * 0.7, s * 0.3), Offset(s * 0.45, s * 0.3), p);
    canvas.drawLine(Offset(s * 0.7, s * 0.3), Offset(s * 0.7, s * 0.55), p);
  }

  void _drawNorthWest(Canvas canvas, double s, Offset c) {
    final p = _stroke;
    canvas.drawLine(Offset(s * 0.7, s * 0.7), Offset(s * 0.3, s * 0.3), p);
    canvas.drawLine(Offset(s * 0.3, s * 0.3), Offset(s * 0.55, s * 0.3), p);
    canvas.drawLine(Offset(s * 0.3, s * 0.3), Offset(s * 0.3, s * 0.55), p);
  }

  // ═══════════════════════════════════════════════════════
  // ACTIONS (9): core set
  // ═══════════════════════════════════════════════════════

  void _drawSearch(Canvas canvas, double s, Offset c) {
    final p = _stroke; final lc = Offset(s * 0.42, s * 0.42); final lr = s * 0.22;
    canvas.drawCircle(lc, lr, p);
    final ha = math.pi / 4;
    canvas.drawLine(Offset(lc.dx + lr * math.cos(ha), lc.dy + lr * math.sin(ha)), Offset(s * 0.75, s * 0.75), _strokeHeavy);
    final ch = _strokeLight;
    canvas.drawLine(Offset(lc.dx - lr * 0.5, lc.dy), Offset(lc.dx + lr * 0.5, lc.dy), ch);
    canvas.drawLine(Offset(lc.dx, lc.dy - lr * 0.5), Offset(lc.dx, lc.dy + lr * 0.5), ch);
  }

  void _drawClear(Canvas canvas, double s, Offset c) {
    final p = _strokeHeavy; final i = s * 0.3;
    canvas.drawLine(Offset(i, i), Offset(s - i, s - i), p);
    canvas.drawLine(Offset(s - i, i), Offset(i, s - i), p);
  }

  void _drawExport(Canvas canvas, double s, Offset c) {
    final p = _stroke;
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(s * 0.15, s * 0.1, s * 0.7, s * 0.8), const Radius.circular(2)), p);
    canvas.drawLine(Offset(c.dx, s * 0.7), Offset(c.dx, s * 0.3), p);
    canvas.drawLine(Offset(c.dx, s * 0.3), Offset(s * 0.35, s * 0.45), p);
    canvas.drawLine(Offset(c.dx, s * 0.3), Offset(s * 0.65, s * 0.45), p);
  }

  void _drawCite(Canvas canvas, double s, Offset c) {
    final p = _stroke;
    for (final xFrac in [0.15, 0.38]) {
      canvas.drawArc(Rect.fromCenter(center: Offset(s * xFrac + s * 0.08, s * 0.3), width: s * 0.14, height: s * 0.14), 0, math.pi * 1.5, false, p);
    }
    canvas.drawLine(Offset(s * 0.55, s * 0.65), Offset(s * 0.68, s * 0.78), p);
    canvas.drawLine(Offset(s * 0.68, s * 0.78), Offset(s * 0.88, s * 0.42), p);
  }

  void _drawShare(Canvas canvas, double s, Offset c) {
    final src = Offset(s * 0.3, c.dy);
    for (final t in [Offset(s * 0.7, s * 0.2), Offset(s * 0.7, c.dy), Offset(s * 0.7, s * 0.8)]) {
      canvas.drawLine(src, t, _strokeLight);
      canvas.drawCircle(t, s * 0.06, _fill);
    }
    canvas.drawCircle(src, s * 0.08, _fill);
  }

  void _drawBookmark(Canvas canvas, double s, Offset c) {
    final path = Path()
      ..moveTo(s * 0.25, s * 0.15)..lineTo(s * 0.75, s * 0.15)
      ..lineTo(s * 0.75, s * 0.85)..lineTo(c.dx, s * 0.65)
      ..lineTo(s * 0.25, s * 0.85)..close();
    canvas.drawPath(path, filled ? _fill : _stroke);
  }

  void _drawCheck(Canvas canvas, double s, Offset c) {
    final p = _strokeHeavy;
    canvas.drawLine(Offset(s * 0.25, c.dy), Offset(s * 0.42, s * 0.65), p);
    canvas.drawLine(Offset(s * 0.42, s * 0.65), Offset(s * 0.75, s * 0.3), p);
  }

  void _drawCheckCircle(Canvas canvas, double s, Offset c) {
    canvas.drawCircle(c, s * 0.35, _stroke);
    _drawCheck(canvas, s, c);
  }

  void _drawDelete(Canvas canvas, double s, Offset c) {
    final p = _stroke;
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(s * 0.25, s * 0.3, s * 0.5, s * 0.55), Radius.circular(s * 0.03)), p);
    canvas.drawLine(Offset(s * 0.18, s * 0.3), Offset(s * 0.82, s * 0.3), p);
    canvas.drawLine(Offset(s * 0.38, s * 0.15), Offset(s * 0.62, s * 0.15), p);
    canvas.drawLine(Offset(s * 0.38, s * 0.15), Offset(s * 0.38, s * 0.3), _strokeLight);
    canvas.drawLine(Offset(s * 0.62, s * 0.15), Offset(s * 0.62, s * 0.3), _strokeLight);
    for (final x in [0.38, 0.5, 0.62]) {
      canvas.drawLine(Offset(s * x, s * 0.4), Offset(s * x, s * 0.75), _strokeLight);
    }
  }

  // ═══════════════════════════════════════════════════════
  // STATUS (7): core set
  // ═══════════════════════════════════════════════════════

  void _drawInfo(Canvas canvas, double s, Offset c) {
    canvas.drawCircle(c, s * 0.35, _stroke);
    canvas.drawCircle(Offset(c.dx, c.dy - s * 0.12), s * 0.03, _fill);
    canvas.drawLine(Offset(c.dx, c.dy - s * 0.03), Offset(c.dx, c.dy + s * 0.18), _strokeHeavy);
  }

  void _drawError(Canvas canvas, double s, Offset c) {
    canvas.drawCircle(c, s * 0.35, _stroke);
    canvas.drawLine(Offset(c.dx, s * 0.25), Offset(c.dx, s * 0.55), _strokeHeavy);
    canvas.drawCircle(Offset(c.dx, s * 0.68), s * 0.03, _fill);
  }

  void _drawWarning(Canvas canvas, double s, Offset c) {
    final path = Path()..moveTo(c.dx, s * 0.15)..lineTo(s * 0.85, s * 0.82)..lineTo(s * 0.15, s * 0.82)..close();
    canvas.drawPath(path, _stroke);
    canvas.drawLine(Offset(c.dx, s * 0.4), Offset(c.dx, s * 0.6), _strokeHeavy);
    canvas.drawCircle(Offset(c.dx, s * 0.7), s * 0.025, _fill);
  }

  void _drawOffline(Canvas canvas, double s, Offset c) {
    canvas.drawCircle(c, s * 0.12, _fill);
    for (var i = 1; i <= 3; i++) {
      canvas.drawArc(Rect.fromCenter(center: c, width: s * 0.3 * i, height: s * 0.3 * i), -math.pi * 0.75, math.pi * 0.5, false, _stroke);
    }
    canvas.drawLine(Offset(s * 0.2, s * 0.2), Offset(s * 0.8, s * 0.8), _strokeHeavy);
  }

  void _drawCloudOff(Canvas canvas, double s, Offset c) {
    final path = Path()
      ..moveTo(s * 0.2, s * 0.6)..quadraticBezierTo(s * 0.1, s * 0.6, s * 0.1, s * 0.5)
      ..quadraticBezierTo(s * 0.1, s * 0.35, s * 0.3, s * 0.35)..quadraticBezierTo(s * 0.35, s * 0.2, s * 0.5, s * 0.2)
      ..quadraticBezierTo(s * 0.7, s * 0.2, s * 0.75, s * 0.35)..quadraticBezierTo(s * 0.9, s * 0.38, s * 0.9, s * 0.5)
      ..quadraticBezierTo(s * 0.9, s * 0.6, s * 0.8, s * 0.6)..close();
    canvas.drawPath(path, _stroke);
    canvas.drawLine(Offset(s * 0.22, s * 0.22), Offset(s * 0.78, s * 0.78), _strokeHeavy);
  }

  void _drawNoResults(Canvas canvas, double s, Offset c) {
    _drawSearch(canvas, s, c);
    canvas.drawLine(Offset(s * 0.3, s * 0.3), Offset(s * 0.55, s * 0.55), _strokeLight);
  }

  void _drawSync(Canvas canvas, double s, Offset c) {
    final p = _stroke; final r = s * 0.3;
    canvas.drawArc(Rect.fromCenter(center: c, width: r * 2, height: r * 2), -math.pi * 0.8, math.pi * 1.2, false, p);
    canvas.drawArc(Rect.fromCenter(center: c, width: r * 2, height: r * 2), math.pi * 0.2, math.pi * 1.2, false, p);
    final a1 = Offset(c.dx + r * math.cos(-math.pi * 0.8), c.dy + r * math.sin(-math.pi * 0.8));
    canvas.drawLine(a1, Offset(a1.dx + s * 0.08, a1.dy), p);
    canvas.drawLine(a1, Offset(a1.dx, a1.dy + s * 0.08), p);
  }

  // ═══════════════════════════════════════════════════════
  // TAB BAR (4): core set
  // ═══════════════════════════════════════════════════════

  void _drawTabToday(Canvas canvas, double s, Offset c) {
    final p = _stroke;
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(s * 0.15, s * 0.2, s * 0.7, s * 0.65), Radius.circular(s * 0.06)), p);
    canvas.drawLine(Offset(s * 0.15, s * 0.38), Offset(s * 0.85, s * 0.38), p);
    canvas.drawLine(Offset(s * 0.35, s * 0.12), Offset(s * 0.35, s * 0.28), p);
    canvas.drawLine(Offset(s * 0.65, s * 0.12), Offset(s * 0.65, s * 0.28), p);
    canvas.drawCircle(Offset(s * 0.4, s * 0.55), s * 0.05, _fill);
    canvas.drawCircle(Offset(s * 0.6, s * 0.55), s * 0.05, _fillDim);
    canvas.drawCircle(Offset(s * 0.4, s * 0.7), s * 0.05, _fillDim);
  }

  void _drawTabPerson(Canvas canvas, double s, Offset c) => _drawPerson(canvas, s, c, filled: false);
  void _drawTabSearch(Canvas canvas, double s, Offset c) => _drawSearch(canvas, s, c);

  void _drawTabExplore(Canvas canvas, double s, Offset c) {
    // Compass: outer circle, NSEW ticks, NE diamond pointer
    final p = _stroke;
    final r = s * 0.34;
    canvas.drawCircle(c, r, p);
    // Cardinal tick marks (N, E, S, W)
    const tickLen = 0.08;
    for (var i = 0; i < 4; i++) {
      final a = -math.pi / 2 + i * math.pi / 2;
      canvas.drawLine(
        Offset(c.dx + r * math.cos(a), c.dy + r * math.sin(a)),
        Offset(c.dx + (r + s * tickLen) * math.cos(a), c.dy + (r + s * tickLen) * math.sin(a)),
        p,
      );
    }
    // Diamond pointer (NE direction)
    final dPath = Path();
    final da = -math.pi / 4; // NE angle
    final dr = s * 0.18;
    dPath.moveTo(c.dx + dr * math.cos(da), c.dy + dr * math.sin(da));
    dPath.lineTo(c.dx + s * 0.06 * math.cos(da - math.pi / 2), c.dy + s * 0.06 * math.sin(da - math.pi / 2));
    dPath.lineTo(c.dx - s * 0.06 * math.cos(da), c.dy - s * 0.06 * math.sin(da));
    dPath.lineTo(c.dx + s * 0.06 * math.cos(da + math.pi / 2), c.dy + s * 0.06 * math.sin(da + math.pi / 2));
    dPath.close();
    canvas.drawPath(dPath, _fill);
  }

  void _drawTabBills(Canvas canvas, double s, Offset c) {
    // Document: rounded rectangle with 3 centered text lines
    final p = _stroke;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(s * 0.2, s * 0.1, s * 0.6, s * 0.8),
        const Radius.circular(2),
      ),
      p,
    );
    final lineW = s * 0.36; // 60% of document width (0.6*s)
    final lx = s * 0.5 - lineW / 2; // centered
    final rx = s * 0.5 + lineW / 2;
    canvas.drawLine(Offset(lx, s * 0.30), Offset(rx, s * 0.30), p);
    canvas.drawLine(Offset(lx, s * 0.50), Offset(rx, s * 0.50), p);
    canvas.drawLine(Offset(lx, s * 0.70), Offset(rx, s * 0.70), p);
  }

  void _drawTabSettings(Canvas canvas, double s, Offset c) {
    final p = _stroke; final r = s * 0.15;
    canvas.drawCircle(c, r, p);
    for (var i = 0; i < 8; i++) {
      final a = i * math.pi / 4;
      canvas.drawLine(
        Offset(c.dx + (r + s * 0.04) * math.cos(a), c.dy + (r + s * 0.04) * math.sin(a)),
        Offset(c.dx + (r + s * 0.12) * math.cos(a), c.dy + (r + s * 0.12) * math.sin(a)), p,
      );
    }
    canvas.drawCircle(c, s * 0.06, _fill);
  }

  // ═══════════════════════════════════════════════════════
  // CONTENT (11): core set
  // ═══════════════════════════════════════════════════════

  void _drawStar(Canvas canvas, double s, Offset c, {required bool filled}) {
    final path = Path(); final r = s * 0.38; final ir = r * 0.4;
    for (var i = 0; i < 5; i++) {
      final oa = -math.pi / 2 + (i * 2 * math.pi / 5);
      if (i == 0) {
        path.moveTo(c.dx + r * math.cos(oa), c.dy + r * math.sin(oa));
      } else {
        path.lineTo(c.dx + r * math.cos(oa), c.dy + r * math.sin(oa));
      }
      final ia = oa + math.pi / 5;
      path.lineTo(c.dx + ir * math.cos(ia), c.dy + ir * math.sin(ia));
    }
    path.close();
    if (filled) canvas.drawPath(path, _fill);
    canvas.drawPath(path, _stroke);
  }

  void _drawPerson(Canvas canvas, double s, Offset c, {required bool filled}) {
    final p = filled ? _fill : _stroke;
    canvas.drawCircle(Offset(c.dx, s * 0.3), s * 0.14, p);
    canvas.drawPath(Path()..addArc(Rect.fromCenter(center: Offset(c.dx, s * 0.85), width: s * 0.52, height: s * 0.44), -math.pi, math.pi), p);
  }

  void _drawGlobe(Canvas canvas, double s, Offset c) {
    final p = _stroke; final r = s * 0.35;
    canvas.drawCircle(c, r, p);
    canvas.drawLine(Offset(c.dx - r, c.dy), Offset(c.dx + r, c.dy), p);
    canvas.drawOval(Rect.fromCenter(center: c, width: r * 0.8, height: r * 2), _strokeLight);
    canvas.drawOval(Rect.fromCenter(center: c, width: r * 1.4, height: r * 2), _strokeLight);
  }

  void _drawChart(Canvas canvas, double s, Offset c) {
    final p = _stroke;
    canvas.drawLine(Offset(s * 0.2, s * 0.2), Offset(s * 0.2, s * 0.8), p);
    canvas.drawLine(Offset(s * 0.2, s * 0.8), Offset(s * 0.85, s * 0.8), p);
    for (final yF in [0.35, 0.5, 0.65]) {
      canvas.drawLine(Offset(s * 0.17, s * yF), Offset(s * 0.23, s * yF), _strokeLight);
    }
    canvas.drawPath(Path()..moveTo(s * 0.25, s * 0.7)..lineTo(s * 0.4, s * 0.55)..lineTo(s * 0.55, s * 0.6)..lineTo(s * 0.72, s * 0.32), _strokeHeavy);
    for (final pt in [Offset(s * 0.25, s * 0.7), Offset(s * 0.4, s * 0.55), Offset(s * 0.55, s * 0.6), Offset(s * 0.72, s * 0.32)]) {
      canvas.drawCircle(pt, s * 0.03, _fill);
    }
  }

  void _drawHistory(Canvas canvas, double s, Offset c) {
    final p = _stroke; final r = s * 0.32;
    canvas.drawArc(Rect.fromCenter(center: c, width: r * 2, height: r * 2), -math.pi * 0.3, math.pi * 1.8, false, p);
    canvas.drawLine(c, Offset(c.dx, c.dy - r * 0.55), _strokeHeavy);
    canvas.drawLine(c, Offset(c.dx + r * 0.4, c.dy + r * 0.1), _stroke);
    final at = Offset(c.dx + r * math.cos(-math.pi * 0.3), c.dy + r * math.sin(-math.pi * 0.3));
    canvas.drawLine(at, Offset(at.dx - s * 0.08, at.dy - s * 0.04), p);
    canvas.drawLine(at, Offset(at.dx + s * 0.02, at.dy - s * 0.09), p);
  }

  void _drawLock(Canvas canvas, double s, Offset c) {
    final p = _stroke;
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(s * 0.25, s * 0.45, s * 0.5, s * 0.38), Radius.circular(s * 0.04)), p);
    canvas.drawArc(Rect.fromCenter(center: Offset(c.dx, s * 0.45), width: s * 0.32, height: s * 0.35), math.pi, math.pi, false, _strokeHeavy);
    canvas.drawCircle(Offset(c.dx, s * 0.58), s * 0.04, _fill);
    canvas.drawLine(Offset(c.dx, s * 0.6), Offset(c.dx, s * 0.7), _stroke);
  }

  void _drawEmail(Canvas canvas, double s, Offset c) {
    final p = _stroke;
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(s * 0.12, s * 0.25, s * 0.76, s * 0.5), Radius.circular(s * 0.04)), p);
    canvas.drawLine(Offset(s * 0.12, s * 0.25), Offset(c.dx, s * 0.52), p);
    canvas.drawLine(Offset(s * 0.88, s * 0.25), Offset(c.dx, s * 0.52), p);
  }

  void _drawVisibility(Canvas canvas, double s, Offset c, {required bool visible}) {
    final p = _stroke;
    final eye = Path()..moveTo(s * 0.1, c.dy)..quadraticBezierTo(c.dx, s * 0.25, s * 0.9, c.dy)..quadraticBezierTo(c.dx, s * 0.75, s * 0.1, c.dy);
    canvas.drawPath(eye, p); canvas.drawCircle(c, s * 0.1, _fill); canvas.drawCircle(c, s * 0.16, p);
    if (!visible) canvas.drawLine(Offset(s * 0.18, s * 0.18), Offset(s * 0.82, s * 0.82), _strokeHeavy);
  }

  // ═══════════════════════════════════════════════════════
  // FEATURE ICONS (34): from F4.4
  // ═══════════════════════════════════════════════════════

  void _drawSignalMetrics(Canvas canvas, double s, Offset c) {
    _drawReticleCorners(canvas, Rect.fromLTWH(3, 3, s - 6, s - 6), 4);
    final barW = 3.0; final heights = [0.6, 0.4, 0.75, 0.5];
    for (int i = 0; i < 4; i++) {
      final x = 8.0 + i * 5.5; final barH = (s - 14) * heights[i];
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, s - 7 - barH, barW, barH), const Radius.circular(1)), i == 0 ? _featureFill : _featureFillDim);
    }
    _drawMicroLabel(canvas, s, 'RNAE', Offset(7, 3.5));
  }

  void _drawDelta(Canvas canvas, double s, Offset c) {
    final path = Path()..moveTo(c.dx, 7)..lineTo(c.dx + 9, s - 8)..lineTo(c.dx - 9, s - 8)..close();
    canvas.drawPath(path, _primary);
    canvas.drawLine(Offset(s - 7, 10), Offset(s - 7, 16), _secondary);
    canvas.drawLine(Offset(s - 10, 13), Offset(s - 4, 13), _secondary);
    canvas.drawLine(Offset(7, s - 14), Offset(11, s - 14), _secondary);
  }

  void _drawConsensus(Canvas canvas, double s, Offset c) {
    for (final o in [Offset(c.dx - 5, c.dy - 3), Offset(c.dx + 5, c.dy - 3), Offset(c.dx, c.dy + 4)]) {
      canvas.drawCircle(o, 6, _primary);
    }
    canvas.drawCircle(Offset(c.dx, c.dy - 0.5), 2, _featureFill);
  }

  void _drawVariance(Canvas canvas, double s, Offset c) {
    _drawReticleCorners(canvas, Rect.fromLTWH(4, 4, s - 8, s - 8), 3.5);
    canvas.drawCircle(c, 2.5, _featureFill);
    canvas.drawLine(c, Offset(7, 8), _primary); canvas.drawLine(c, Offset(s - 7, 8), _primary);
    canvas.drawLine(Offset(7, 8), Offset(10, 10), _secondary); canvas.drawLine(Offset(s - 7, 8), Offset(s - 10, 10), _secondary);
    canvas.drawLine(Offset(9, s - 8), Offset(s - 9, s - 8), _secondary);
  }

  void _drawTrends(Canvas canvas, double s, Offset c) {
    final pts = [Offset(6, s * 0.65), Offset(s * 0.28, s * 0.45), Offset(s * 0.48, s * 0.55), Offset(s * 0.68, s * 0.35), Offset(s - 6, s * 0.3)];
    final path = Path()..moveTo(pts[0].dx, pts[0].dy);
    for (int i = 1; i < pts.length; i++) {
      path.lineTo(pts[i].dx, pts[i].dy);
    }
    canvas.drawPath(path, _primary);
    for (final p in pts) {
      canvas.drawCircle(p, 1.8, _featureFill);
    }
    _drawHashmarks(canvas, Offset(6, s - 6), Offset(s - 6, s - 6), 6, 2);
  }

  void _drawSort(Canvas canvas, double s, Offset c) {
    final widths = [s * 0.7, s * 0.55, s * 0.4];
    for (int i = 0; i < 3; i++) {
      canvas.drawLine(Offset(6, 9.0 + i * 6.5), Offset(6 + widths[i], 9.0 + i * 6.5), i == 0 ? _primary : _secondary);
    }
    canvas.drawLine(Offset(s - 8, 8), Offset(s - 8, s - 10), _primary);
    canvas.drawLine(Offset(s - 11, s - 14), Offset(s - 8, s - 10), _primary);
    canvas.drawLine(Offset(s - 5, s - 14), Offset(s - 8, s - 10), _primary);
  }

  void _drawFeedCards(Canvas canvas, double s, Offset c) {
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(8, 5, s - 14, s * 0.4), const Radius.circular(2)), _secondary);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(5, s * 0.35, s - 10, s * 0.4), const Radius.circular(2)), _primary);
    canvas.drawLine(Offset(8, s * 0.45), Offset(s * 0.6, s * 0.45), _secondary);
    canvas.drawLine(Offset(8, s * 0.55), Offset(s * 0.45, s * 0.55), _secondary);
  }

  void _drawTrending(Canvas canvas, double s, Offset c) {
    canvas.drawLine(Offset(8, s - 8), Offset(s - 8, 8), _primary);
    canvas.drawLine(Offset(s - 8, 8), Offset(s - 13, 12), _primary);
    canvas.drawLine(Offset(s - 8, 8), Offset(s - 8, 14), _primary);
    canvas.drawCircle(Offset(10, s * 0.5), 1.5, _featureFillDim);
    canvas.drawCircle(Offset(s * 0.4, s * 0.35), 1.5, _featureFillDim);
  }

  void _drawWhy(Canvas canvas, double s, Offset c) {
    final path = Path()..moveTo(c.dx - 4, 10)..cubicTo(c.dx - 4, 6, c.dx + 6, 6, c.dx + 6, 12)..cubicTo(c.dx + 6, 16, c.dx, 16, c.dx, 19);
    canvas.drawPath(path, _primary); canvas.drawCircle(Offset(c.dx, s - 9), 2, _featureFill);
    _drawReticleCorners(canvas, Rect.fromLTWH(4, 4, s - 8, s - 8), 3);
  }

  void _drawAttribution(Canvas canvas, double s, Offset c) {
    final nodes = [Offset(8, c.dy - 6), Offset(c.dx, c.dy + 6), Offset(s - 8, c.dy - 6)];
    canvas.drawLine(nodes[0], nodes[1], _secondary); canvas.drawLine(nodes[1], nodes[2], _secondary);
    for (final n in nodes) { canvas.drawCircle(n, 3.5, _primary); canvas.drawCircle(n, 1.5, _featureFill); }
  }

  void _drawFeedSort(Canvas canvas, double s, Offset c) {
    for (int i = 0; i < 3; i++) {
      canvas.drawLine(Offset(6, 8.0 + i * 7), Offset(s - 12, 8.0 + i * 7), _secondary);
    }
    canvas.drawLine(Offset(s - 8, 8), Offset(s - 8, 20), _primary);
    canvas.drawLine(Offset(s - 11, 11), Offset(s - 8, 8), _primary);
    canvas.drawLine(Offset(s - 5, 11), Offset(s - 8, 8), _primary);
  }

  void _drawPeek(Canvas canvas, double s, Offset c) {
    final eyePath = Path()..moveTo(4, c.dy)..quadraticBezierTo(c.dx, c.dy - 9, s - 4, c.dy)..quadraticBezierTo(c.dx, c.dy + 9, 4, c.dy);
    canvas.drawPath(eyePath, _primary); canvas.drawCircle(c, 3.5, _featureFill);
    canvas.drawLine(Offset(2, c.dy), Offset(s - 2, c.dy), _secondary);
  }

  void _drawAnnotate(Canvas canvas, double s, Offset c) {
    canvas.drawLine(Offset(7, s - 7), Offset(s - 9, 9), _primary);
    canvas.drawLine(Offset(s - 9, 9), Offset(s - 6, 7), _secondary);
    canvas.drawLine(Offset(s - 9, 9), Offset(s - 7, 12), _secondary);
    canvas.drawCircle(Offset(10, s - 10), 2, _featureFillDim);
  }

  void _drawProfile(Canvas canvas, double s, Offset c) {
    canvas.drawCircle(Offset(c.dx, c.dy - 3), 5, _primary);
    final path = Path()..moveTo(c.dx - 10, s - 7)..quadraticBezierTo(c.dx, c.dy + 7, c.dx + 10, s - 7);
    canvas.drawPath(path, _primary); canvas.drawCircle(Offset(c.dx, c.dy - 3), 8, _secondary);
  }

  void _drawBadgeWeek(Canvas canvas, double s, Offset c) {
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(5, 7, s - 10, s - 12), const Radius.circular(2)), _primary);
    canvas.drawLine(Offset(5, 13), Offset(s - 5, 13), _primary);
    _drawMicroLabel(canvas, s, '7d', Offset(c.dx - 4, 16));
  }

  void _drawSilent(Canvas canvas, double s, Offset c) {
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(6, 8, s - 12, s - 14), const Radius.circular(2)), _secondary);
    canvas.drawLine(Offset(c.dx - 5, c.dy - 3), Offset(c.dx + 5, c.dy + 5), _primary);
    canvas.drawLine(Offset(c.dx + 5, c.dy - 3), Offset(c.dx - 5, c.dy + 5), _primary);
    canvas.drawLine(Offset(4, s - 5), Offset(s - 4, 5), _work..color = color.atOpacity(0.15)..strokeWidth = 0.5..style = PaintingStyle.stroke);
  }

  void _drawFavorites(Canvas canvas, double s, Offset c) {
    final path = Path();
    for (int i = 0; i < 5; i++) {
      final angle = -math.pi / 2 + i * 2 * math.pi / 5;
      final innerAngle = angle + math.pi / 5;
      final outerR = s * 0.38; final innerR = s * 0.17;
      if (i == 0) {
        path.moveTo(c.dx + outerR * math.cos(angle), c.dy + outerR * math.sin(angle));
      } else {
        path.lineTo(c.dx + outerR * math.cos(angle), c.dy + outerR * math.sin(angle));
      }
      path.lineTo(c.dx + innerR * math.cos(innerAngle), c.dy + innerR * math.sin(innerAngle));
    }
    path.close(); canvas.drawPath(path, _primary);
  }

  void _drawHeatmap(Canvas canvas, double s, Offset c) {
    final cellSize = (s - 12) / 4;
    final ints = [0.15, 0.35, 0.55, 0.20, 0.45, 0.10, 0.40, 0.65, 0.25, 0.50, 0.15, 0.35, 0.55, 0.30, 0.45, 0.10];
    _work.style = PaintingStyle.fill;
    for (int row = 0; row < 4; row++) {
      for (int col = 0; col < 4; col++) {
        _work.color = color.atOpacity(ints[row * 4 + col]);
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(6 + col * cellSize, 6 + row * cellSize, cellSize - 1.5, cellSize - 1.5), const Radius.circular(1)),
          _work);
      }
    }
  }

  void _drawVote(Canvas canvas, double s, Offset c) {
    canvas.drawCircle(c, s * 0.35, _primary);
    canvas.drawPath(Path()..moveTo(c.dx - 5, c.dy)..lineTo(c.dx - 1, c.dy + 5)..lineTo(c.dx + 6, c.dy - 5), _primary);
  }

  void _drawBill(Canvas canvas, double s, Offset c) {
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(7, 4, s - 14, s - 8), const Radius.circular(2)), _primary);
    for (int i = 0; i < 4; i++) {
      canvas.drawLine(Offset(10, 10.0 + i * 5), Offset(10 + ((i % 2 == 0) ? s * 0.5 : s * 0.35), 10.0 + i * 5), _secondary);
    }
  }

  void _drawResonance(Canvas canvas, double s, Offset c) {
    final a = Offset(8, c.dy); final b = Offset(s - 8, c.dy);
    canvas.drawCircle(a, 3.5, _featureFill); canvas.drawCircle(b, 3.5, _featureFill);
    canvas.drawPath(Path()..moveTo(a.dx + 3.5, a.dy)..quadraticBezierTo(c.dx, c.dy - 10, b.dx - 3.5, b.dy), _primary);
    canvas.drawPath(Path()..moveTo(a.dx + 3.5, a.dy)..quadraticBezierTo(c.dx, c.dy + 8, b.dx - 3.5, b.dy), _secondary);
  }

  void _drawCascade(Canvas canvas, double s, Offset c) {
    final tops = [8.0, 12.0, 15.0, 18.0, 22.0];
    for (int i = 0; i < 5; i++) {
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(5 + i * 5.0, tops[i], 4, s - 6 - tops[i]), const Radius.circular(1)), i == 0 ? _featureFill : _featureFillDim);
    }
  }

  void _drawLeague(Canvas canvas, double s, Offset c) {
    final heights = [s * 0.6, s * 0.45, s * 0.35]; final xs = [6.0, 14.0, 22.0];
    for (int i = 0; i < 3; i++) {
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(xs[i], s - 6 - heights[i], 5.5, heights[i]), const Radius.circular(1)), i == 0 ? _featureFill : _featureFillDim);
    }
    canvas.drawLine(Offset(4, s - 5), Offset(s - 4, s - 5), _secondary);
  }

  void _drawAnnotatePrivate(Canvas canvas, double s, Offset c) {
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(c.dx - 6, c.dy - 1, 12, 10), const Radius.circular(2)), _primary);
    canvas.drawPath(Path()..moveTo(c.dx - 4, c.dy)..lineTo(c.dx - 4, c.dy - 5)..quadraticBezierTo(c.dx, c.dy - 10, c.dx + 4, c.dy - 5)..lineTo(c.dx + 4, c.dy), _primary);
    canvas.drawCircle(Offset(c.dx, c.dy + 3), 1.5, _featureFill);
  }

  void _drawRequest(Canvas canvas, double s, Offset c) {
    canvas.drawCircle(c, s * 0.35, _primary);
    canvas.drawLine(Offset(c.dx, c.dy - 5), Offset(c.dx, c.dy + 5), _primary);
    canvas.drawLine(Offset(c.dx - 5, c.dy), Offset(c.dx + 5, c.dy), _primary);
  }

  void _drawFeatureInfo(Canvas canvas, double s, Offset c) {
    canvas.drawCircle(c, s * 0.35, _primary);
    canvas.drawCircle(Offset(c.dx, c.dy - 4), 1.5, _featureFill);
    canvas.drawLine(Offset(c.dx, c.dy - 1), Offset(c.dx, c.dy + 6), _primary);
  }

  void _drawGuide(Canvas canvas, double s, Offset c) {
    canvas.drawCircle(c, s * 0.35, _secondary);
    canvas.drawPath(Path()..moveTo(c.dx, c.dy - 9)..lineTo(c.dx - 3, c.dy)..lineTo(c.dx + 3, c.dy)..close(), _featureFill);
    canvas.drawLine(c, Offset(c.dx, c.dy + 8), _secondary);
  }

  void _drawFeatureExport(Canvas canvas, double s, Offset c) {
    canvas.drawLine(Offset(6, s - 7), Offset(s - 6, s - 7), _secondary);
    canvas.drawLine(Offset(6, s - 7), Offset(6, c.dy + 4), _secondary);
    canvas.drawLine(Offset(s - 6, s - 7), Offset(s - 6, c.dy + 4), _secondary);
    canvas.drawLine(Offset(c.dx, c.dy + 2), Offset(c.dx, 6), _primary);
    canvas.drawLine(Offset(c.dx - 4, 10), Offset(c.dx, 6), _primary);
    canvas.drawLine(Offset(c.dx + 4, 10), Offset(c.dx, 6), _primary);
  }

  void _drawGhost(Canvas canvas, double s, Offset c) {
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(4, 6, s * 0.5, s * 0.6), const Radius.circular(2)), _secondary);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(s * 0.3, s * 0.25, s * 0.5, s * 0.6), const Radius.circular(2)), _primary);
    canvas.drawLine(Offset(c.dx - 2, c.dy), Offset(c.dx + 4, c.dy), _primary);
  }

  void _drawCopy(Canvas canvas, double s, Offset c) {
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(9, 4, s - 15, s - 11), const Radius.circular(2)), _secondary);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(5, 8, s - 15, s - 11), const Radius.circular(2)), _primary);
  }

  void _drawWatermark(Canvas canvas, double s, Offset c) {
    canvas.save(); canvas.translate(c.dx, c.dy); canvas.rotate(-0.3);
    for (int i = -1; i <= 1; i++) {
      canvas.drawLine(Offset(-12, i * 6.0), Offset(12, i * 6.0), _secondary);
    }
    canvas.restore();
    _drawReticleCorners(canvas, Rect.fromLTWH(3, 3, s - 6, s - 6), 3.5);
  }

  void _drawDigest(Canvas canvas, double s, Offset c) {
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(5, 9, s - 10, s - 16), const Radius.circular(2)), _primary);
    canvas.drawLine(Offset(5, 9), Offset(c.dx, c.dy + 2), _primary);
    canvas.drawLine(Offset(s - 5, 9), Offset(c.dx, c.dy + 2), _primary);
  }

  void _drawNotifs(Canvas canvas, double s, Offset c) {
    canvas.drawPath(Path()..moveTo(c.dx - 7, s - 10)..quadraticBezierTo(c.dx - 8, c.dy - 4, c.dx, 7)..quadraticBezierTo(c.dx + 8, c.dy - 4, c.dx + 7, s - 10), _primary);
    canvas.drawLine(Offset(c.dx - 9, s - 10), Offset(c.dx + 9, s - 10), _primary);
    canvas.drawCircle(Offset(c.dx, s - 7), 1.5, _featureFill);
    canvas.drawArc(Rect.fromCenter(center: Offset(s - 6, 8), width: 6, height: 6), -0.5, 1.0, false, _secondary);
  }

  void _drawShift(Canvas canvas, double s, Offset c) {
    canvas.drawPath(Path()..moveTo(c.dx + 2, 5)..lineTo(c.dx - 4, c.dy + 1)..lineTo(c.dx + 1, c.dy + 1)..lineTo(c.dx - 3, s - 5), _primary);
    canvas.drawCircle(Offset(s - 8, 10), 1.2, _featureFillDim);
    canvas.drawCircle(Offset(8, s - 10), 1.2, _featureFillDim);
  }

  void _drawThreshold(Canvas canvas, double s, Offset c) {
    canvas.drawLine(Offset(4, c.dy), Offset(s - 4, c.dy), _secondary);
    canvas.drawLine(Offset(c.dx, c.dy), Offset(c.dx, 7), _primary);
    canvas.drawCircle(Offset(c.dx, 7), 2.5, _featureFill);
    _drawMicroLabel(canvas, s, '\u25B2', Offset(c.dx - 2, c.dy - 12));
  }

  void _drawAnnDelta(Canvas canvas, double s, Offset c) {
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(4, 5, s * 0.55, s * 0.55), const Radius.circular(2)), _secondary);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(s * 0.3, s * 0.3, s * 0.55, s * 0.55), const Radius.circular(2)), _primary);
    canvas.drawPath(Path()..moveTo(c.dx, c.dy - 3)..lineTo(c.dx + 4, c.dy + 4)..lineTo(c.dx - 4, c.dy + 4)..close(), _featureFill);
  }

  // ═══════════════════════════════════════════════════════
  // SETTINGS ICONS (25): from F4.17
  // ═══════════════════════════════════════════════════════

  void _drawSectionShield(Canvas canvas, double s, Offset c) {
    canvas.drawPath(Path()..moveTo(c.dx, 1)..lineTo(s - 1, s * 0.3)..quadraticBezierTo(s - 1, s - 1, c.dx, s - 1)..quadraticBezierTo(1, s - 1, 1, s * 0.3)..close(), _primary);
    canvas.drawCircle(Offset(c.dx, c.dy - 1), 2, _primary);
    canvas.drawLine(Offset(c.dx, c.dy + 1), Offset(c.dx, c.dy + 3.5), _primary);
  }

  void _drawSectionGem(Canvas canvas, double s, Offset c) {
    canvas.drawPath(Path()..moveTo(c.dx, 1.5)..lineTo(s - 2, c.dy - 1)..lineTo(c.dx, s - 1.5)..lineTo(2, c.dy - 1)..close(), _primary);
    canvas.drawLine(Offset(2, c.dy - 1), Offset(s - 2, c.dy - 1), _secondary);
    canvas.drawLine(Offset(c.dx, 1.5), Offset(c.dx, s - 1.5), _secondary);
  }

  void _drawSectionTuning(Canvas canvas, double s, Offset c) {
    final positions = [0.3, 0.6, 0.45];
    for (int i = 0; i < 3; i++) {
      final x = 2.5 + i * (s - 5) / 2.5;
      canvas.drawLine(Offset(x, 2), Offset(x, s - 2), _secondary);
      canvas.drawCircle(Offset(x, 2 + (s - 4) * positions[i]), 1.8, _featureFill);
    }
  }

  void _drawSectionBroadcast(Canvas canvas, double s, Offset c) {
    canvas.drawCircle(Offset(2, c.dy), 1.5, _featureFill);
    for (int i = 1; i <= 3; i++) {
      canvas.drawArc(Rect.fromCircle(center: Offset(2, c.dy), radius: i * 3.5), -0.6, 1.2, false, _secondary);
    }
  }

  void _drawSectionDoc(Canvas canvas, double s, Offset c) {
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(2, 1, s - 4, s - 2), const Radius.circular(1)), _primary);
    canvas.drawLine(Offset(4, s * 0.35), Offset(s - 4, s * 0.35), _secondary);
    canvas.drawLine(Offset(4, s * 0.55), Offset(s * 0.65, s * 0.55), _secondary);
    canvas.drawLine(Offset(4, s * 0.75), Offset(s * 0.5, s * 0.75), _secondary);
  }

  void _drawUser(Canvas canvas, double s, Offset c) {
    canvas.drawCircle(Offset(c.dx, c.dy - 3), 3.5, _primary);
    canvas.drawPath(Path()..moveTo(c.dx - 5, s - 3)..quadraticBezierTo(c.dx - 5, c.dy + 2, c.dx, c.dy + 2)..quadraticBezierTo(c.dx + 5, c.dy + 2, c.dx + 5, s - 3), _primary);
  }

  void _drawSignOut(Canvas canvas, double s, Offset c) {
    canvas.drawLine(Offset(3, 3), Offset(3, s - 3), _secondary);
    canvas.drawLine(Offset(3, 3), Offset(s * 0.4, 3), _secondary);
    canvas.drawLine(Offset(3, s - 3), Offset(s * 0.4, s - 3), _secondary);
    canvas.drawLine(Offset(c.dx - 2, c.dy), Offset(s - 3, c.dy), _primary);
    canvas.drawLine(Offset(s - 6, c.dy - 3), Offset(s - 3, c.dy), _primary);
    canvas.drawLine(Offset(s - 6, c.dy + 3), Offset(s - 3, c.dy), _primary);
  }

  void _drawSignIn(Canvas canvas, double s, Offset c) {
    canvas.drawLine(Offset(s - 3, 3), Offset(s - 3, s - 3), _secondary);
    canvas.drawLine(Offset(s - 3, 3), Offset(s * 0.6, 3), _secondary);
    canvas.drawLine(Offset(s - 3, s - 3), Offset(s * 0.6, s - 3), _secondary);
    canvas.drawLine(Offset(2, c.dy), Offset(c.dx + 2, c.dy), _primary);
    canvas.drawLine(Offset(c.dx - 1, c.dy - 3), Offset(c.dx + 2, c.dy), _primary);
    canvas.drawLine(Offset(c.dx - 1, c.dy + 3), Offset(c.dx + 2, c.dy), _primary);
  }

  void _drawCurrentPlan(Canvas canvas, double s, Offset c) {
    _drawReticleCorners(canvas, Rect.fromLTWH(2, 2, s - 4, s - 4), 4);
    canvas.drawCircle(c, 3.5, _primary); canvas.drawCircle(c, 1, _featureFill);
  }

  void _drawManageSub(Canvas canvas, double s, Offset c) {
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(2, 4, s - 4, s - 8), const Radius.circular(2)), _primary);
    canvas.drawLine(Offset(4, c.dy), Offset(s - 4, c.dy), _secondary);
    canvas.drawCircle(Offset(s * 0.7, c.dy), 1.2, _featureFill);
  }

  void _drawRestore(Canvas canvas, double s, Offset c) {
    canvas.drawArc(Rect.fromCircle(center: c, radius: s * 0.35), -1.2, 4.5, false, _primary);
    canvas.drawLine(Offset(c.dx + 1, 3), Offset(c.dx + 4, 5.5), _primary);
    canvas.drawLine(Offset(c.dx + 1, 3), Offset(c.dx - 2, 5.5), _primary);
  }

  void _drawAppearance(Canvas canvas, double s, Offset c) {
    canvas.drawCircle(c, s * 0.35, _primary);
    canvas.drawPath(Path()..moveTo(c.dx, c.dy - s * 0.35)..arcTo(Rect.fromCircle(center: c, radius: s * 0.35), -math.pi / 2, math.pi, false)..close(), _featureFillDim);
  }

  void _drawNotifications(Canvas canvas, double s, Offset c) {
    canvas.drawPath(Path()..moveTo(c.dx - 5, s - 4)..quadraticBezierTo(c.dx - 6, c.dy - 3, c.dx, 3)..quadraticBezierTo(c.dx + 6, c.dy - 3, c.dx + 5, s - 4), _primary);
    canvas.drawLine(Offset(c.dx - 6, s - 4), Offset(c.dx + 6, s - 4), _primary);
    canvas.drawCircle(Offset(c.dx, s - 2), 1, _featureFill);
    canvas.drawArc(Rect.fromCenter(center: Offset(s - 3, 4), width: 5, height: 5), -0.5, 1.0, false, _secondary);
  }

  void _drawHaptic(Canvas canvas, double s, Offset c) {
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: c, width: s * 0.3, height: s * 0.55), const Radius.circular(2)), _primary);
    for (int i = 1; i <= 2; i++) {
      final offset = i * 3.5;
      canvas.drawLine(Offset(c.dx - s * 0.15 - offset, c.dy - 4), Offset(c.dx - s * 0.15 - offset, c.dy + 4), _secondary);
      canvas.drawLine(Offset(c.dx + s * 0.15 + offset, c.dy - 4), Offset(c.dx + s * 0.15 + offset, c.dy + 4), _secondary);
    }
  }

  void _drawRateStar(Canvas canvas, double s, Offset c) {
    final path = Path();
    for (int i = 0; i < 5; i++) {
      final angle = -math.pi / 2 + i * 2 * math.pi / 5;
      final innerAngle = angle + math.pi / 5;
      final outerR = s * 0.38; final innerR = s * 0.17;
      if (i == 0) {
        path.moveTo(c.dx + outerR * math.cos(angle), c.dy + outerR * math.sin(angle));
      } else {
        path.lineTo(c.dx + outerR * math.cos(angle), c.dy + outerR * math.sin(angle));
      }
      path.lineTo(c.dx + innerR * math.cos(innerAngle), c.dy + innerR * math.sin(innerAngle));
    }
    path.close(); canvas.drawPath(path, _primary);
  }

  void _drawReportBug(Canvas canvas, double s, Offset c) {
    canvas.drawCircle(c, s * 0.3, _primary);
    canvas.drawLine(Offset(c.dx, 2), Offset(c.dx, s - 2), _secondary);
    canvas.drawLine(Offset(2, c.dy), Offset(s - 2, c.dy), _secondary);
    canvas.drawCircle(c, 1.5, _featureFill);
  }

  void _drawContactSupport(Canvas canvas, double s, Offset c) {
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(2, 4, s - 4, s - 8), const Radius.circular(1.5)), _primary);
    canvas.drawLine(Offset(2, 4), Offset(c.dx, c.dy + 1), _primary);
    canvas.drawLine(Offset(s - 2, 4), Offset(c.dx, c.dy + 1), _primary);
  }

  void _drawShareApp(Canvas canvas, double s, Offset c) {
    canvas.drawCircle(Offset(3, c.dy), 2, _featureFill);
    for (final t in [Offset(s - 3, 3), Offset(s - 3, c.dy), Offset(s - 3, s - 3)]) {
      canvas.drawLine(Offset(5, c.dy), t, _secondary); canvas.drawCircle(t, 1.5, _featureFill);
    }
  }

  void _drawMethodology(Canvas canvas, double s, Offset c) {
    canvas.drawCircle(c, s * 0.38, _secondary);
    canvas.drawPath(Path()..moveTo(c.dx, c.dy - 6)..lineTo(c.dx - 2.5, c.dy)..lineTo(c.dx + 2.5, c.dy)..close(), _featureFill);
    canvas.drawLine(c, Offset(c.dx, c.dy + 5), _secondary);
    canvas.drawLine(Offset(c.dx - 5, c.dy), Offset(c.dx + 5, c.dy), _secondary);
  }

  void _drawPrivacy(Canvas canvas, double s, Offset c) {
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(c.dx - 5, c.dy - 1, 10, 8), const Radius.circular(1.5)), _primary);
    canvas.drawArc(Rect.fromLTWH(c.dx - 3.5, c.dy - 6, 7, 7), math.pi, math.pi, false, _primary);
    canvas.drawCircle(Offset(c.dx, c.dy + 2.5), 1, _featureFill);
  }

  void _drawTerms(Canvas canvas, double s, Offset c) {
    canvas.drawLine(Offset(c.dx, 3), Offset(c.dx, s - 4), _secondary);
    canvas.drawLine(Offset(3, 5), Offset(s - 3, 5), _primary);
    canvas.drawArc(Rect.fromLTWH(2, 5, 8, 8), 0, math.pi, false, _secondary);
    canvas.drawArc(Rect.fromLTWH(s - 10, 5, 8, 8), 0, math.pi, false, _secondary);
    canvas.drawLine(Offset(c.dx - 3, s - 4), Offset(c.dx + 3, s - 4), _primary);
  }

  void _drawChangelog(Canvas canvas, double s, Offset c) {
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(3, 2, s - 6, s - 4), const Radius.circular(1.5)), _primary);
    canvas.drawLine(Offset(5.5, c.dy - 2), Offset(s * 0.65, c.dy - 2), _secondary);
    canvas.drawLine(Offset(5.5, c.dy + 2), Offset(s * 0.5, c.dy + 2), _secondary);
    canvas.drawCircle(Offset(s - 5, 4), 1.5, _featureFill);
  }

  void _drawDeleteAccount(Canvas canvas, double s, Offset c) {
    canvas.drawPath(Path()..moveTo(c.dx, 2)..lineTo(s - 2, s - 2)..lineTo(2, s - 2)..close(), _primary);
    canvas.drawLine(Offset(c.dx - 2, c.dy + 1), Offset(c.dx + 2, c.dy + 1), _primary);
  }

  void _drawUpgradeGem(Canvas canvas, double s, Offset c) {
    canvas.drawPath(Path()..moveTo(c.dx, 1)..lineTo(s - 2, s * 0.35)..lineTo(c.dx, s - 1)..lineTo(2, s * 0.35)..close(), _primary);
    canvas.drawLine(Offset(2, s * 0.35), Offset(s - 2, s * 0.35), _secondary);
    canvas.drawLine(Offset(c.dx, 1), Offset(c.dx, s - 1), _secondary);
  }
}
