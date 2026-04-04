/// E-1/E-3 -- Export Composer
///
/// Classified intelligence dossier for analysis exports.
/// Film perforations · measurement rulers · security crosshatch
/// · parallax depth borders · reticle corners · corner
/// classification triangles · margin annotations · chain of
/// custody pipeline · signal confidence bars · spectral
/// fingerprint · content crosshair · diagonal watermark ·
/// metric cells with data rail · drift rosette · data ribbon
/// · military DTG · handling caveat · page indicator.
///
/// Fixed 390px width. Captured at 3× by P6 ExportUtil.
///
/// Path: lib/utils/export_composer.dart
library;
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:baseline_app/config/theme.dart';
import 'package:baseline_app/config/constants.dart';
//
// ═══════════════════════════════════════════════════════════
// CONSTANTS
//
// ═══════════════════════════════════════════════════════════
const double _kW = 390.0, _kMinH = 520.0, _kPad = 28.0;
// Scan emergence.
const double _kEmH = 16.0, _kEmOp = 0.08;
// Scan rules.
const double _kScanSp = 8.0, _kScanOp = 0.02;
// Security crosshatch.
const double _kHatchSp = 24.0, _kHatchSt = 0.3, _kHatchOp = 0.015;
// Rulers.
const double _kRuMinor = 3.0, _kRuMajor = 6.0;
const double _kRuMinorSp = 20.0, _kRuMajorSp = 100.0;
// Glow bleed.
const double _kGlowBleed = 20.0, _kGlowOp = 0.025;
// Parallax depth borders.
const List<(double, double)> _kDepthBorders = [
(1.5, 0.05), // outer: inset, opacity
(4.0, 0.03), // middle
(7.0, 0.015), // inner
];
// Reticles.
const double _kRetOA = 10.0, _kRetOS = 1.5, _kRetOO = 0.15;
const double _kRetIA = 5.0, _kRetIS = 1.0, _kRetIO = 0.25, _kRetIOff = 3.0;
const double _kRetDR = 1.5, _kRetDO = 0.08;
// Corner triangles.
const double _kTriSize = 8.0, _kTriFill = 0.04, _kTriLabelOp = 0.06;
// Film perfs.
const double _kPfW = 4.0, _kPfH = 6.0, _kPfSp = 16.0, _kPfE = 6.0, _kPfOp = 0.04;
// Margin annotations.
const double _kMarginFont = 5.0, _kMarginOp = 0.025;
// Data ribbon.
const double _kRibH = 6.0;
// Content zone.
const double _kCtBorder = 0.05, _kCtPad = 16.0;
const double _kNodeR = 2.0, _kNodeOp = 0.12;
// Crosshair.
const double _kChLineOp = 0.02, _kChTickOp = 0.04, _kChTickL = 4.0;
// Signal bars.
const List<double> _kSigH = [4, 7, 10, 13];
const double _kSigW = 3.0, _kSigGap = 2.0, _kSigActiveOp = 0.30, _kSigInactiveOp = 0.06;
// Watermark.
const double _kWmFont = 24.0, _kWmOp = 0.03, _kWmAng = -30.0;
// Ghost.
const double _kGhOp = 0.28;
// Custody.
const double _kCustDotR = 1.5, _kCustActiveOp = 0.30, _kCustInactiveOp = 0.06;
const double _kCustLineOp = 0.08;
// Cells.
const double _kCellBOp = 0.12, _kCellPH = 10.0, _kCellPV = 8.0, _kCellGap = 8.0;
const int _kMaxMet = 4;
const double _kRailOp = 0.10;
const double _kRailThickness = 0.5; // ← FIX: separate from opacity
// Cell value/label fonts.
const double _kCellValueFont = 13.0;
const double _kCellLabelFont = 7.0;
// Micro-indicator dimensions.
const double _kArcD = 14.0;
const double _kDotR = 2.0;
const double _kArrowFont = 12.0;
const double _kBarW = 14.0, _kBarH = 4.0;
// Spectral fingerprint.
const double _kSpecBarW = 1.0, _kSpecMaxH = 10.0, _kSpecOp = 0.15;
// Grad divider.
const double _kGradOp = 0.25;
// Drift rosette.
const int _kDrMaxR = 5, _kDrSpokes = 8;
const double _kDrRSp = 4.5, _kDrRSt = 0.5, _kDrROp = 0.06;
const double _kDrSSt = 0.3, _kDrSOp = 0.04;
const double _kDrPR = 1.5, _kDrPOp = 0.10;
// Wordmark.
const double _kWmkH = 16.0, _kWmkOp = 0.15;
// Months.
const List<String> _kMo = [
'JAN','FEB','MAR','APR','MAY','JUN',
'JUL','AUG','SEP','OCT','NOV','DEC',
];
//
// ═══════════════════════════════════════════════════════════
// DATA CLASSES
//
// ═══════════════════════════════════════════════════════════
enum ExportAspectRatio { standard, square, wide }
class ExportMetric {
const ExportMetric({
required this.label, required this.value,
this.numericValue, this.maxValue,
});
final String label, value;
final double? numericValue, maxValue;
}
class ExportModelCode {
const ExportModelCode(this.code, {this.active = true});
final String code;
final bool active;
}
class CustodyStage {
const CustodyStage(this.label, {this.complete = true});
final String label;
final bool complete;
}
class ExportComposition {
const ExportComposition({
required this.figureName,
required this.toolName,
required this.child,
this.metrics = const [],
this.source,
this.analyzedAt,
this.ghostChild,
this.driftValue,
this.modelCount = 3,
this.modelCodes = const [
ExportModelCode('GP'),
ExportModelCode('CL'),
ExportModelCode('GR'),
],
this.custodyStages = const [
CustodyStage('INGESTED'),
CustodyStage('STRUCTURED'),
CustodyStage('ANALYZED'),
CustodyStage('VERIFIED'),
],
this.signalStrength = 4,
this.toolCode = 'FR',
this.aspectRatio = ExportAspectRatio.standard,
this.preloadedWordmark,
});
final String figureName, toolName;
final Widget child;
final List<ExportMetric> metrics;
final String? source;
final DateTime? analyzedAt;
final Widget? ghostChild;
final double? driftValue;
final int modelCount;
final List<ExportModelCode> modelCodes;
final List<CustodyStage> custodyStages;
final int signalStrength;
final String toolCode;
final ExportAspectRatio aspectRatio;
final ui.Image? preloadedWordmark;
}
//
// ═══════════════════════════════════════════════════════════
// MAIN WIDGET
//
// ═══════════════════════════════════════════════════════════
class ExportComposerWidget extends StatelessWidget {
const ExportComposerWidget({super.key, required this.composition});
final ExportComposition composition;
static Future<ui.Image?> preloadWordmark() async {
try {
final d = await rootBundle.load(kWordmarkAsset);
final c = await ui.instantiateImageCodec(
d.buffer.asUint8List(), targetHeight: (_kWmkH * 3).toInt());
return (await c.getNextFrame()).image;
} catch (_) { return null; }
}
double get _minH => switch (composition.aspectRatio) {
ExportAspectRatio.standard => _kMinH,
ExportAspectRatio.square => _kW,
ExportAspectRatio.wide => _kW * 9 / 16,
};
/// Stable seed for all deterministic visuals (ribbon, hash, spectral).
/// Computed once per build - no DateTime.now() scatter inside painters.
int get _exportSeed =>
(composition.analyzedAt ?? DateTime.now()).millisecondsSinceEpoch;
@override
Widget build(BuildContext context) {
final seed = _exportSeed; // Single computation, shared everywhere.
return Semantics(
label: 'Export: ${composition.figureName} '
'${composition.toolName} analysis',
child: SizedBox(
width: _kW,
child: ConstrainedBox(
constraints: BoxConstraints(minHeight: _minH),
child: CustomPaint(
painter: _BgPainter(accent: BaselineColors.teal),
child: CustomPaint(
foregroundPainter: _FgPainter(
accent: BaselineColors.teal, tsHash: seed),
child: Padding(
padding: const EdgeInsets.all(_kPad),
child: Column(
mainAxisSize: MainAxisSize.min,
crossAxisAlignment: CrossAxisAlignment.stretch,
children: [
_Header(c: composition, seed: seed),
const SizedBox(height: 12),
_Title(c: composition),
const SizedBox(height: 8),
_ModelRow(
codes: composition.modelCodes,
modelCount: composition.modelCount,
),
const SizedBox(height: 8),
_CustodyPipeline(stages: composition.custodyStages),
const SizedBox(height: 14),
_Content(c: composition),
const SizedBox(height: 14),
if (composition.metrics.isNotEmpty) ...[
_Metrics(metrics: composition.metrics),
const SizedBox(height: 8),
_SpectralFP(
metrics: composition.metrics, tsHash: seed),
const SizedBox(height: 12),
],
_GradDiv(),
const SizedBox(height: 12),
_Foot(c: composition, seed: seed),
],
),
),
),
),
),
),
);
}
}
//
// ═══════════════════════════════════════════════════════════
// HEADER
//
// ═══════════════════════════════════════════════════════════
class _Header extends StatelessWidget {
const _Header({required this.c, required this.seed});
final ExportComposition c;
final int seed;
String get _catalog {
final d = c.analyzedAt ?? DateTime.fromMillisecondsSinceEpoch(seed);
return 'EX-${(d.year % 100).toString().padLeft(2, '0')}'
'${d.month.toString().padLeft(2, '0')}'
'${d.day.toString().padLeft(2, '0')}-'
'${d.hour.toString().padLeft(2, '0')}'
'${d.minute.toString().padLeft(2, '0')}';
}
String get _serial {
final d = c.analyzedAt ?? DateTime.fromMillisecondsSinceEpoch(seed);
return 'BL-${d.year}-'
'${d.month.toString().padLeft(2, '0')}'
'${d.day.toString().padLeft(2, '0')}-'
'${c.toolCode}-001';
}
@override
Widget build(BuildContext context) {
return Column(
crossAxisAlignment: CrossAxisAlignment.start,
mainAxisSize: MainAxisSize.min,
children: [
Row(
mainAxisAlignment: MainAxisAlignment.spaceBetween,
children: [
// Classification badge.
Row(mainAxisSize: MainAxisSize.min, children: [
Container(width: 4, height: 4,
decoration: BoxDecoration(shape: BoxShape.circle,
color: BaselineColors.teal.atOpacity(0.25))),
const SizedBox(width: 5),
Container(
padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
decoration: BoxDecoration(border: Border.all(
color: BaselineColors.teal.atOpacity(0.20), width: 1)),
child: Text('MEASURED SIGNAL',
style: BaselineTypography.dataSmall.copyWith(
fontSize: 7, letterSpacing: 1.5,
color: BaselineColors.teal.atOpacity(0.35))),
),
]),
Text(_catalog, style: BaselineTypography.dataSmall.copyWith(
fontSize: 7, letterSpacing: 1.0,
color: BaselineColors.teal.atOpacity(0.25))),
],
),
const SizedBox(height: 4),
// Serial reference.
Text(_serial, style: BaselineTypography.dataSmall.copyWith(
fontSize: 6, letterSpacing: 0.8,
color: BaselineColors.teal.atOpacity(0.18))),
],
);
}
}
//
// ═══════════════════════════════════════════════════════════
// TITLE PLATE
//
// ═══════════════════════════════════════════════════════════
class _Title extends StatelessWidget {
const _Title({required this.c});
final ExportComposition c;
@override
Widget build(BuildContext context) {
return Column(
crossAxisAlignment: CrossAxisAlignment.start,
mainAxisSize: MainAxisSize.min,
children: [
Text(c.figureName.toUpperCase(),
style: BaselineTypography.bodyMedium.copyWith(
fontSize: 16, fontWeight: FontWeight.w600,
color: Colors.white.atOpacity(0.92),
letterSpacing: 1.6, height: 1.2),
maxLines: 2, overflow: TextOverflow.ellipsis),
const SizedBox(height: 3),
FractionallySizedBox(
alignment: Alignment.centerLeft, widthFactor: 0.6,
child: Container(height: 1,
color: BaselineColors.teal.atOpacity(0.12))),
const SizedBox(height: 6),
Text(c.toolName,
style: BaselineTypography.dataSmall.copyWith(
fontSize: 11, color: BaselineColors.teal.atOpacity(0.70)),
maxLines: 1, overflow: TextOverflow.ellipsis),
const SizedBox(height: 8),
Text('${c.modelCount} AI MODELS · INDEPENDENT ANALYSIS',
style: BaselineTypography.dataSmall.copyWith(
fontSize: 8, color: Colors.white.atOpacity(0.20),
letterSpacing: 2.0)),
],
);
}
}
//
// ═══════════════════════════════════════════════════════════
// MODEL ATTRIBUTION
//
// ═══════════════════════════════════════════════════════════
class _ModelRow extends StatelessWidget {
const _ModelRow({required this.codes, required this.modelCount});
final List<ExportModelCode> codes;
final int modelCount;
@override
Widget build(BuildContext context) {
// Clamp rendered codes to modelCount for safety.
final rendered = codes.take(modelCount).toList();
return Row(children: [
Text('MEASURED BY', style: BaselineTypography.dataSmall.copyWith(
fontSize: 7, color: Colors.white.atOpacity(0.18),
letterSpacing: 1.5)),
const SizedBox(width: 8),
...rendered.map((m) => Padding(
padding: const EdgeInsets.only(right: 10),
child: Row(mainAxisSize: MainAxisSize.min, children: [
Container(width: 5, height: 5,
decoration: BoxDecoration(shape: BoxShape.circle,
color: m.active
? BaselineColors.teal.atOpacity(0.40)
: Colors.white.atOpacity(0.08))),
const SizedBox(width: 4),
Text(m.code, style: BaselineTypography.dataSmall.copyWith(
fontSize: 8, color: m.active
? BaselineColors.teal.atOpacity(0.35)
: Colors.white.atOpacity(0.12))),
]),
)),
]);
}
}
//
// ═══════════════════════════════════════════════════════════
// CHAIN OF CUSTODY
//
// ═══════════════════════════════════════════════════════════
class _CustodyPipeline extends StatelessWidget {
const _CustodyPipeline({required this.stages});
final List<CustodyStage> stages;
@override
Widget build(BuildContext context) {
return SizedBox(
height: 20,
child: Row(
children: [
for (int i = 0; i < stages.length; i++) ...[
if (i > 0)
// Dashed connector.
Expanded(child: CustomPaint(
painter: _DashPainter(
color: BaselineColors.teal.atOpacity(_kCustLineOp)),
)),
// Stage.
Column(mainAxisSize: MainAxisSize.min, children: [
Text(stages[i].label,
style: BaselineTypography.dataSmall.copyWith(
fontSize: 5, color: Colors.white.atOpacity(0.15),
letterSpacing: 1.0)),
const SizedBox(height: 3),
Container(
width: _kCustDotR * 2, height: _kCustDotR * 2,
decoration: BoxDecoration(shape: BoxShape.circle,
color: stages[i].complete
? BaselineColors.teal.atOpacity(_kCustActiveOp)
: Colors.white.atOpacity(_kCustInactiveOp))),
]),
],
],
),
);
}
}
class _DashPainter extends CustomPainter {
_DashPainter({required this.color});
final Color color;
@override
void paint(Canvas canvas, Size size) {
final p = Paint()..color = color..strokeWidth = 0.5;
const dashW = 4.0, gapW = 3.0;
double x = 0;
final y = size.height * 0.7; // Align with dots.
while (x < size.width) {
canvas.drawLine(Offset(x, y),
Offset((x + dashW).clamp(0, size.width), y), p);
x += dashW + gapW;
}
}
@override
bool shouldRepaint(_DashPainter o) => false;
}
//
// ═══════════════════════════════════════════════════════════
// CONTENT ZONE
//
// ═══════════════════════════════════════════════════════════
class _Content extends StatelessWidget {
const _Content({required this.c});
final ExportComposition c;
@override
Widget build(BuildContext context) {
final hasGhost = c.ghostChild != null;
return Semantics(
label: 'Analysis visualization',
child: CustomPaint(
foregroundPainter: _ContentPainter(
signal: c.signalStrength.clamp(1, 4)),
child: Padding(
padding: const EdgeInsets.all(_kCtPad),
child: Stack(children: [
if (hasGhost)
Positioned.fill(child: Opacity(
opacity: _kGhOp, child: c.ghostChild!)),
c.child,
// Diagonal watermark.
Positioned.fill(child: IgnorePointer(child: Center(
child: Transform.rotate(
angle: _kWmAng * math.pi / 180,
child: Text('BASELINE · MEASURED',
style: TextStyle(fontFamily: BaselineTypography.bodyFontFamily,
fontSize: _kWmFont,
color: Colors.white.atOpacity(_kWmOp),
letterSpacing: 8.0, fontWeight: FontWeight.w600)))))),
if (hasGhost)
Positioned(left: -_kCtPad + 2, top: 0, bottom: 0,
child: Center(child: RotatedBox(quarterTurns: 3,
child: Text('PRIOR PERIOD',
style: BaselineTypography.dataSmall.copyWith(
fontSize: 7, color: Colors.white.atOpacity(0.18),
letterSpacing: 2.0))))),
]),
),
),
);
}
}
//
// ═══════════════════════════════════════════════════════════
// CONTENT OVERLAY PAINTER (border + crosshair + signal bars)
//
// ═══════════════════════════════════════════════════════════
class _ContentPainter extends CustomPainter {
_ContentPainter({required this.signal});
final int signal;
@override
void paint(Canvas canvas, Size size) {
// Border.
canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height),
Paint()..color = Colors.white.atOpacity(_kCtBorder)
..style = PaintingStyle.stroke..strokeWidth = 1.0);
// Corner nodes.
final nP = Paint()..color = BaselineColors.teal.atOpacity(_kNodeOp);
for (final p in [
Offset(_kNodeR + 1, _kNodeR + 1),
Offset(size.width - _kNodeR - 1, _kNodeR + 1),
Offset(_kNodeR + 1, size.height - _kNodeR - 1),
Offset(size.width - _kNodeR - 1, size.height - _kNodeR - 1),
]) {
  canvas.drawCircle(p, _kNodeR, nP);
}
// Crosshair.
final cx = size.width / 2, cy = size.height / 2;
final lP = Paint()..color = Colors.white.atOpacity(_kChLineOp)..strokeWidth = 0.5;
canvas.drawLine(Offset(cx, 0), Offset(cx, size.height), lP);
canvas.drawLine(Offset(0, cy), Offset(size.width, cy), lP);
final tP = Paint()..color = Colors.white.atOpacity(_kChTickOp)..strokeWidth = 1.0;
canvas.drawLine(Offset(cx - _kChTickL, cy), Offset(cx + _kChTickL, cy), tP);
canvas.drawLine(Offset(cx, cy - _kChTickL), Offset(cx, cy + _kChTickL), tP);
// Coord labels.
final st = TextStyle(fontFamily: BaselineTypography.monoFontFamily, fontSize: 5,
color: Colors.white.atOpacity(0.03));
final tl = TextPainter(text: TextSpan(text: '0,0', style: st),
textDirection: TextDirection.ltr)..layout();
tl.paint(canvas, const Offset(4, 4));
final br = TextPainter(
text: TextSpan(text: '${size.width.toInt()}×${size.height.toInt()}', style: st),
textDirection: TextDirection.ltr)..layout();
br.paint(canvas, Offset(size.width - br.width - 4, size.height - br.height - 4));
// Signal confidence bars (top-right).
final baseX = size.width - 8 - (_kSigH.length * (_kSigW + _kSigGap));
const baseY = 8.0;
for (int i = 0; i < _kSigH.length; i++) {
final h = _kSigH[i];
final active = i < signal;
final x = baseX + i * (_kSigW + _kSigGap);
canvas.drawRect(
Rect.fromLTWH(x, baseY + (_kSigH.last - h), _kSigW, h),
Paint()..color = active
? BaselineColors.teal.atOpacity(_kSigActiveOp)
: Colors.white.atOpacity(_kSigInactiveOp),
);
}
}
@override
bool shouldRepaint(_ContentPainter o) => signal != o.signal;
}
//
// ═══════════════════════════════════════════════════════════
// METRIC STRIP + DATA RAIL
//
// ═══════════════════════════════════════════════════════════
class _Metrics extends StatelessWidget {
const _Metrics({required this.metrics});
final List<ExportMetric> metrics;
@override
Widget build(BuildContext context) {
final cells = metrics.take(_kMaxMet).toList();
return Stack(children: [
// Data rail: thickness via _kRailThickness, color via _kRailOp.
Positioned.fill(child: Center(child: Container(
height: _kRailThickness,
color: BaselineColors.teal.atOpacity(_kRailOp)))),
Wrap(spacing: _kCellGap, runSpacing: _kCellGap,
children: cells.map((m) => _Cell(m: m)).toList()),
]);
}
}
class _Cell extends StatelessWidget {
const _Cell({required this.m});
final ExportMetric m;
@override
Widget build(BuildContext context) {
return Semantics(label: '${m.label} ${m.value}',
child: Container(
padding: const EdgeInsets.symmetric(
horizontal: _kCellPH, vertical: _kCellPV),
decoration: BoxDecoration(
color: BaselineColors.black,
border: Border.all(
color: BaselineColors.teal.atOpacity(_kCellBOp), width: 1)),
child: Column(mainAxisSize: MainAxisSize.min, children: [
_indicator(),
const SizedBox(height: 4),
Text(m.value, style: BaselineTypography.dataSmall.copyWith(
fontSize: _kCellValueFont,
color: BaselineColors.teal.atOpacity(0.85))),
const SizedBox(height: 2),
Text(m.label.toUpperCase(),
style: BaselineTypography.dataSmall.copyWith(
fontSize: _kCellLabelFont,
color: Colors.white.atOpacity(0.25),
letterSpacing: 1.5)),
]),
),
);
}
Widget _indicator() {
final l = m.label.toLowerCase(), v = m.value;
final n = m.numericValue ?? _parseN(v);
if (l.contains('consensus') || (v.contains('%') && n != null)) {
  return _Arc(fill: n ?? 0.0);
}
if (l.contains('model') || RegExp(r'^\d+/\d+$').hasMatch(v.trim())) {
final p = v.trim().split('/');
return _Dots(filled: int.tryParse(p[0]) ?? 0,
total: p.length > 1 ? int.tryParse(p[1]) ?? 3 : 3);
}
if (l.contains('δ') || l.contains('Δ') || l.contains('delta') ||
v.startsWith('+') || v.startsWith('-')) {
  return _Arrow(up: !v.startsWith('-'));
}
return _Bar(fill: n ?? 0.5);
}
static double? _parseN(String s) {
final c = s.replaceAll(RegExp(r'[%+]'), '').trim();
final p = double.tryParse(c);
return p == null ? null : (p > 1.0 ? p / 100 : p);
}
}
// ── Micro-indicators ──
class _Arc extends StatelessWidget {
const _Arc({required this.fill});
final double fill;
@override
Widget build(BuildContext c) => CustomPaint(
size: const Size(_kArcD, _kArcD / 2 + 2), painter: _ArcP(fill.clamp(0, 1)));
}
class _ArcP extends CustomPainter {
_ArcP(this.f);
final double f;
@override
void paint(Canvas c, Size s) {
final ctr = Offset(s.width / 2, s.height), r = s.width / 2;
c.drawArc(Rect.fromCircle(center: ctr, radius: r), math.pi, math.pi, false,
Paint()..color = BaselineColors.teal.atOpacity(0.08)
..style = PaintingStyle.stroke..strokeWidth = 2);
if (f > 0) {
  c.drawArc(Rect.fromCircle(center: ctr, radius: r),
math.pi, math.pi * f, false,
Paint()..color = BaselineColors.teal.atOpacity(0.30)
..style = PaintingStyle.stroke..strokeWidth = 2..strokeCap = StrokeCap.round);
}
}
@override
bool shouldRepaint(_ArcP o) => f != o.f;
}
class _Dots extends StatelessWidget {
const _Dots({required this.filled, required this.total});
final int filled, total;
@override
Widget build(BuildContext c) => Row(mainAxisSize: MainAxisSize.min,
children: List.generate(total, (i) => Padding(
padding: EdgeInsets.only(left: i > 0 ? 3 : 0),
child: Container(width: _kDotR * 2, height: _kDotR * 2,
decoration: BoxDecoration(shape: BoxShape.circle,
color: i < filled
? BaselineColors.teal.atOpacity(0.40)
: Colors.white.atOpacity(0.10))))));
}
class _Arrow extends StatelessWidget {
const _Arrow({required this.up});
final bool up;
@override
Widget build(BuildContext c) => Text(up ? '↑' : '↓',
style: TextStyle(fontSize: _kArrowFont, height: 1.0,
// Teal-only export palette: up = bold teal, down = muted teal.
color: BaselineColors.teal.atOpacity(up ? 0.40 : 0.18)));
}
class _Bar extends StatelessWidget {
const _Bar({required this.fill});
final double fill;
@override
Widget build(BuildContext c) => CustomPaint(
size: const Size(_kBarW, _kBarH), painter: _BarP(fill.clamp(0, 1)));
}
class _BarP extends CustomPainter {
_BarP(this.f);
final double f;
@override
void paint(Canvas c, Size s) {
c.drawRRect(RRect.fromRectAndRadius(
Rect.fromLTWH(0, 0, s.width, s.height), const Radius.circular(1)),
Paint()..color = BaselineColors.teal.atOpacity(0.08));
if (f > 0) {
  c.drawRRect(RRect.fromRectAndRadius(
Rect.fromLTWH(0, 0, s.width * f, s.height), const Radius.circular(1)),
Paint()..color = BaselineColors.teal.atOpacity(0.25));
}
}
@override
bool shouldRepaint(_BarP o) => f != o.f;
}
//
// ═══════════════════════════════════════════════════════════
// SPECTRAL FINGERPRINT
//
// ═══════════════════════════════════════════════════════════
class _SpectralFP extends StatelessWidget {
const _SpectralFP({required this.metrics, required this.tsHash});
final List<ExportMetric> metrics;
final int tsHash;
@override
Widget build(BuildContext context) {
return CustomPaint(
size: const Size(double.infinity, 12),
painter: _SpectralPainter(
metrics: metrics.take(_kMaxMet).toList(),
seed: tsHash,
),
);
}
}
class _SpectralPainter extends CustomPainter {
_SpectralPainter({required this.metrics, required this.seed});
final List<ExportMetric> metrics;
final int seed;
@override
void paint(Canvas canvas, Size size) {
final paint = Paint()
..color = BaselineColors.teal.atOpacity(_kSpecOp);
// Extract numeric values for bar heights.
final values = <double>[];
for (final m in metrics) {
final n = m.numericValue ??
double.tryParse(m.value.replaceAll(RegExp(r'[%+/a-zA-Z]'), ''));
values.add((n ?? 50).clamp(1, 100) / 100);
}
if (values.isEmpty) {
// Fallback: stable-seed pseudo-random bars.
final rng = math.Random(seed);
double x = 0;
while (x < size.width) {
final h = 2 + rng.nextDouble() * 8;
canvas.drawRect(
Rect.fromLTWH(x, size.height - h, _kSpecBarW, h), paint);
x += 2 + rng.nextDouble() * 4;
}
return;
}
// Compute real bar counts per cluster for accurate centering.
final rng = math.Random(seed);
final barCounts = <int>[];
for (final v in values) {
barCounts.add(3 + (v * 2).round()); // 3-5 bars per cluster.
}
const barSpacing = 2.0;
const clusterGap = 6.0;
final totalBars = barCounts.fold<int>(0, (s, c) => s + c);
final totalW = totalBars * barSpacing +
(barCounts.length - 1) * clusterGap;
final startX = ((size.width - totalW) / 2).clamp(0.0, size.width);
double x = startX;
for (int ci = 0; ci < barCounts.length; ci++) {
for (int bi = 0; bi < barCounts[ci]; bi++) {
final h = 2 + values[ci] * _kSpecMaxH *
(0.6 + rng.nextDouble() * 0.4);
canvas.drawRect(
Rect.fromLTWH(x, size.height - h, _kSpecBarW, h), paint);
x += barSpacing;
}
x += clusterGap;
}
}
@override
bool shouldRepaint(_SpectralPainter o) => seed != o.seed;
}
//
// ═══════════════════════════════════════════════════════════
// GRADIENT DIVIDER
//
// ═══════════════════════════════════════════════════════════
class _GradDiv extends StatelessWidget {
@override
Widget build(BuildContext c) => Container(height: 1,
decoration: BoxDecoration(gradient: LinearGradient(
colors: [Colors.transparent,
BaselineColors.teal.atOpacity(_kGradOp),
BaselineColors.teal.atOpacity(_kGradOp),
Colors.transparent],
stops: const [0, 0.3, 0.7, 1])));
}
//
// ═══════════════════════════════════════════════════════════
// FOOTER
//
// ═══════════════════════════════════════════════════════════
class _Foot extends StatelessWidget {
const _Foot({required this.c, required this.seed});
final ExportComposition c;
final int seed;
DateTime get _seedDate => DateTime.fromMillisecondsSinceEpoch(seed);
/// Full military Date-Time Group: "141847ZFEB26"
String? get _dtg {
final d = c.analyzedAt ?? _seedDate;
return '${d.day.toString().padLeft(2, '0')}'
'${d.hour.toString().padLeft(2, '0')}'
'${d.minute.toString().padLeft(2, '0')}Z'
'${_kMo[d.month - 1]}${(d.year % 100).toString().padLeft(2, '0')}';
}
String? get _civil {
final d = c.analyzedAt ?? _seedDate;
return '${d.day.toString().padLeft(2, '0')} ${_kMo[d.month - 1]} ${d.year}';
}
String get _hash {
final h = seed.toRadixString(16).toUpperCase();
return h.length >= 6 ? h.substring(h.length - 6) : h.padLeft(6, '0');
}
@override
Widget build(BuildContext context) {
final hasDrift = c.driftValue != null;
return Semantics(
label: _civil != null ? 'Analyzed $_civil' : null,
child: Stack(children: [
if (hasDrift)
Positioned(left: 0, bottom: 0, child: CustomPaint(
size: const Size(52, 60),
painter: _DriftP(
v: c.driftValue!.clamp(0.0, 1.0),
color: BaselineColors.teal,
))),
Padding(
padding: EdgeInsets.only(left: hasDrift ? 64 : 0),
child: Column(
crossAxisAlignment: CrossAxisAlignment.start,
mainAxisSize: MainAxisSize.min,
children: [
// DTG + civilian + source.
if (_dtg != null || c.source != null)
Padding(padding: const EdgeInsets.only(bottom: 6),
child: Text.rich(TextSpan(children: [
if (_dtg != null) TextSpan(text: _dtg,
style: BaselineTypography.dataSmall.copyWith(
fontSize: 9, color: BaselineColors.teal.atOpacity(0.30),
letterSpacing: 0.5)),
if (_dtg != null && _civil != null) TextSpan(text: ' ',
style: BaselineTypography.dataSmall.copyWith(fontSize: 9)),
if (_civil != null) TextSpan(text: _civil,
style: BaselineTypography.dataSmall.copyWith(
fontSize: 9, color: Colors.white.atOpacity(0.40),
letterSpacing: 0.8)),
if (c.source != null) TextSpan(
text: ' · SOURCE: ${c.source!.toUpperCase()}',
style: BaselineTypography.dataSmall.copyWith(
fontSize: 9, color: Colors.white.atOpacity(0.40),
letterSpacing: 0.8)),
]), maxLines: 1, overflow: TextOverflow.ellipsis)),
// Disclaimer.
Padding(padding: const EdgeInsets.only(bottom: 3),
child: Text('Observational analysis only. Not a fact-check.',
style: BaselineTypography.bodySmall.copyWith(
fontSize: 8, color: Colors.white.atOpacity(0.22),
fontStyle: FontStyle.italic, height: 1.3))),
// Classification footer.
Padding(padding: const EdgeInsets.only(bottom: 2),
child: Text('UNCLASSIFIED // FOR PUBLIC DISTRIBUTION',
style: BaselineTypography.dataSmall.copyWith(
fontSize: 6, color: Colors.white.atOpacity(0.12),
letterSpacing: 2.0))),
// Handling caveat.
Padding(padding: const EdgeInsets.only(bottom: 2),
child: Text('HANDLE VIA BASELINE CHANNELS ONLY',
style: BaselineTypography.dataSmall.copyWith(
fontSize: 5, color: Colors.white.atOpacity(0.08),
letterSpacing: 2.0))),
// Page indicator.
Padding(padding: const EdgeInsets.only(bottom: 8),
child: Text('PAGE 1 OF 1',
style: BaselineTypography.dataSmall.copyWith(
fontSize: 5, color: Colors.white.atOpacity(0.06),
letterSpacing: 1.5))),
// Wordmark + hash.
Align(alignment: Alignment.centerRight,
child: Column(
crossAxisAlignment: CrossAxisAlignment.end,
mainAxisSize: MainAxisSize.min,
children: [
_wmk(),
const SizedBox(height: 1),
Text('app', style: BaselineTypography.dataSmall.copyWith(
fontSize: 5, color: Colors.white.atOpacity(0.06),
letterSpacing: 2.0)),
const SizedBox(height: 2),
Text(_hash, style: BaselineTypography.dataSmall.copyWith(
fontSize: 6, color: Colors.white.atOpacity(0.07),
letterSpacing: 1.0)),
])),
],
),
),
]),
);
}
Widget _wmk() {
final img = c.preloadedWordmark;
if (img != null) {
  return Opacity(opacity: _kWmkOp,
child: RawImage(image: img, height: _kWmkH, fit: BoxFit.contain));
}
return Text('BASELINE', style: BaselineTypography.dataSmall.copyWith(
fontSize: 10, color: Colors.white.atOpacity(_kWmkOp),
letterSpacing: 3.0));
}
}
//
// ═══════════════════════════════════════════════════════════
// DRIFT ROSETTE (E-4)
//
// ═══════════════════════════════════════════════════════════
class _DriftP extends CustomPainter {
_DriftP({required this.v, required this.color});
final double v; final Color color;
@override
void paint(Canvas canvas, Size size) {
final c = Offset(size.width / 2, size.width / 2);
// Belt-and-suspenders: clamp input 0-1 even if caller already did.
final clamped = v.clamp(0.0, 1.0);
final rings = (clamped * _kDrMaxR).ceil().clamp(1, 5);
final maxR = rings * _kDrRSp;
final sP = Paint()..color = color.atOpacity(_kDrSOp)..strokeWidth = _kDrSSt;
for (int i = 0; i < _kDrSpokes; i++) {
final a = (i / _kDrSpokes) * 2 * math.pi;
canvas.drawLine(c, Offset(c.dx + maxR * math.cos(a),
c.dy + maxR * math.sin(a)), sP);
}
final rP = Paint()..color = color.atOpacity(_kDrROp)
..style = PaintingStyle.stroke..strokeWidth = _kDrRSt;
for (int i = 1; i <= rings; i++) {
  canvas.drawCircle(c, i * _kDrRSp, rP);
}
canvas.drawCircle(c, _kDrPR, Paint()..color = color.atOpacity(_kDrPOp));
final dTp = TextPainter(text: TextSpan(text: 'DRIFT',
style: TextStyle(fontFamily: BaselineTypography.monoFontFamily, fontSize: 5,
color: color.atOpacity(0.06), letterSpacing: 1)),
textDirection: TextDirection.ltr)..layout();
dTp.paint(canvas, Offset(c.dx - dTp.width / 2, c.dy - maxR - dTp.height - 2));
final vTp = TextPainter(text: TextSpan(text: '${(clamped * 100).round()}',
style: TextStyle(fontFamily: BaselineTypography.monoFontFamily, fontSize: 7,
color: color.atOpacity(0.10), letterSpacing: 0.5)),
textDirection: TextDirection.ltr)..layout();
vTp.paint(canvas, Offset(c.dx - vTp.width / 2, c.dy + maxR + 4));
}
@override
bool shouldRepaint(_DriftP o) => v != o.v || color != o.color;
}
//
// ═══════════════════════════════════════════════════════════
// BACKGROUND PAINTER
//
// ═══════════════════════════════════════════════════════════
class _BgPainter extends CustomPainter {
_BgPainter({required this.accent});
final Color accent;
@override
void paint(Canvas canvas, Size size) {
// 1. Black fill.
canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height),
Paint()..color = BaselineColors.black);
// 2. Scan emergence glow.
canvas.drawRect(Rect.fromLTWH(0, 0, size.width, _kEmH),
Paint()..shader = LinearGradient(
begin: Alignment.topCenter, end: Alignment.bottomCenter,
colors: [accent.atOpacity(_kEmOp), Colors.transparent],
).createShader(Rect.fromLTWH(0, 0, size.width, _kEmH)));
// 3. Scan rules.
final scanP = Paint()..color = Colors.white.atOpacity(_kScanOp)..strokeWidth = 0.5;
for (double y = _kScanSp; y < size.height; y += _kScanSp) {
  canvas.drawLine(Offset(0, y), Offset(size.width, y), scanP);
}
// 4. Security crosshatch (margins only).
canvas.save();
final contentRect = Rect.fromLTWH(_kPad, _kPad, size.width - _kPad * 2, size.height -
_kPad * 2);
canvas.clipPath(Path()
..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
..addRect(contentRect.deflate(-4)) // slight overlap prevention
..fillType = PathFillType.evenOdd);
final hP = Paint()..color = Colors.white.atOpacity(_kHatchOp)..strokeWidth = _kHatchSt;
for (double o = -size.height; o < size.width + size.height; o += _kHatchSp) {
canvas.drawLine(Offset(o, 0), Offset(o + size.height, size.height), hP);
canvas.drawLine(Offset(o, size.height), Offset(o + size.height, 0), hP);
}
canvas.restore();
// 5. Rulers.
final minP = Paint()..color = Colors.white.atOpacity(0.03)..strokeWidth = 0.5;
final majP = Paint()..color = Colors.white.atOpacity(0.05)..strokeWidth = 0.5;
for (double y = 0; y < size.height; y += _kRuMinorSp) {
final maj = (y % _kRuMajorSp).abs() < 0.5;
final t = maj ? _kRuMajor : _kRuMinor;
final p = maj ? majP : minP;
canvas.drawLine(Offset(0, y), Offset(t, y), p);
canvas.drawLine(Offset(size.width, y), Offset(size.width - t, y), p);
if (maj && y > 0) {
final tp = TextPainter(text: TextSpan(text: '${y.toInt()}',
style: TextStyle(fontFamily: BaselineTypography.monoFontFamily, fontSize: 5,
color: Colors.white.atOpacity(0.04))),
textDirection: TextDirection.ltr)..layout();
tp.paint(canvas, Offset(t + 1, y - tp.height / 2));
}
}
// 6. Teal glow bleed.
// NOTE: cT is an approximate content-zone top offset. The glow is 2.5%
// ambient bleed so minor layout drift is visually imperceptible.
final cL = _kPad, cR = size.width - _kPad;
final cT = _kPad + 140, cB = size.height - _kPad;
_glowStrip(canvas, Rect.fromLTWH(cL, cT - _kGlowBleed, cR - cL, _kGlowBleed),
Alignment.bottomCenter, Alignment.topCenter);
_glowStrip(canvas, Rect.fromLTWH(cL, cB, cR - cL, _kGlowBleed),
Alignment.topCenter, Alignment.bottomCenter);
_glowStrip(canvas, Rect.fromLTWH(cL - _kGlowBleed, cT, _kGlowBleed, cB - cT),
Alignment.centerRight, Alignment.centerLeft);
_glowStrip(canvas, Rect.fromLTWH(cR, cT, _kGlowBleed, cB - cT),
Alignment.centerLeft, Alignment.centerRight);
}
void _glowStrip(Canvas c, Rect r, Alignment a, Alignment b) {
c.drawRect(r, Paint()..shader = LinearGradient(begin: a, end: b,
colors: [accent.atOpacity(_kGlowOp), Colors.transparent])
.createShader(r));
}
@override
bool shouldRepaint(_BgPainter o) => false;
}
//
// ═══════════════════════════════════════════════════════════
// FOREGROUND PAINTER
//
// ═══════════════════════════════════════════════════════════
class _FgPainter extends CustomPainter {
_FgPainter({required this.accent, required this.tsHash});
final Color accent; final int tsHash;
@override
void paint(Canvas canvas, Size size) {
// 1. Parallax depth borders.
for (final (inset, op) in _kDepthBorders) {
canvas.drawRect(
Rect.fromLTWH(inset, inset, size.width - inset * 2, size.height - inset * 2),
Paint()..color = accent.atOpacity(op)
..style = PaintingStyle.stroke
..strokeWidth = inset == _kDepthBorders[0].$1 ? 1.5 : 0.5);
}
// 2. Reticle corners.
final oP = Paint()..color = accent.atOpacity(_kRetOO)
..strokeWidth = _kRetOS..strokeCap = StrokeCap.square;
final iP = Paint()..color = accent.atOpacity(_kRetIO)
..strokeWidth = _kRetIS..strokeCap = StrokeCap.square;
final dP = Paint()..color = accent.atOpacity(_kRetDO);
final ins = _kPad / 2;
for (final (cx, cy, dx, dy) in [
(ins, ins, 1.0, 1.0), (size.width - ins, ins, -1.0, 1.0),
(ins, size.height - ins, 1.0, -1.0),
(size.width - ins, size.height - ins, -1.0, -1.0),
]) {
canvas.drawLine(Offset(cx, cy), Offset(cx + _kRetOA * dx, cy), oP);
canvas.drawLine(Offset(cx, cy), Offset(cx, cy + _kRetOA * dy), oP);
final ix = cx + _kRetIOff * dx, iy = cy + _kRetIOff * dy;
canvas.drawLine(Offset(ix, iy), Offset(ix + _kRetIA * dx, iy), iP);
canvas.drawLine(Offset(ix, iy), Offset(ix, iy + _kRetIA * dy), iP);
canvas.drawCircle(Offset(cx, cy), _kRetDR, dP);
}
// 3. Film perforations.
final pfP = Paint()..color = Colors.white.atOpacity(_kPfOp);
final count = (size.width / _kPfSp).floor();
final sx = (size.width - count * _kPfSp) / 2;
for (int i = 0; i < count; i++) {
final x = sx + i * _kPfSp;
canvas.drawRect(Rect.fromLTWH(x, _kPfE, _kPfW, _kPfH), pfP);
canvas.drawRect(Rect.fromLTWH(x, size.height - _kPfE - _kPfH, _kPfW, _kPfH), pfP);
}
// 4. Corner classification triangles.
_paintCornerTriangles(canvas, size);
// 5. Data ribbon.
_paintRibbon(canvas, size);
// 6. Margin annotations.
_paintMarginText(canvas, size);
}
void _paintCornerTriangles(Canvas canvas, Size size) {
final triP = Paint()..color = accent.atOpacity(_kTriFill);
final labels = ['C1', 'C2', 'C3', 'C4'];
final corners = [
(Offset(_kPad, _kPad), 0), // TL
(Offset(size.width - _kPad, _kPad), 1), // TR
(Offset(_kPad, size.height - _kPad), 2), // BL
(Offset(size.width - _kPad, size.height - _kPad), 3), // BR
];
for (final (pos, idx) in corners) {
final dx = idx == 0 || idx == 2 ? 1.0 : -1.0;
final dy = idx == 0 || idx == 1 ? 1.0 : -1.0;
final path = Path()
..moveTo(pos.dx, pos.dy)
..lineTo(pos.dx + _kTriSize * dx, pos.dy)
..lineTo(pos.dx, pos.dy + _kTriSize * dy)
..close();
canvas.drawPath(path, triP);
final tp = TextPainter(
text: TextSpan(text: labels[idx],
style: TextStyle(fontFamily: BaselineTypography.monoFontFamily, fontSize: 4,
color: accent.atOpacity(_kTriLabelOp))),
textDirection: TextDirection.ltr)..layout();
tp.paint(canvas, Offset(
pos.dx + (dx > 0 ? _kTriSize + 2 : -_kTriSize - tp.width - 2),
pos.dy + (dy > 0 ? 1 : -tp.height - 1)));
}
}
void _paintRibbon(Canvas canvas, Size size) {
final rng = math.Random(tsHash);
final bars = 40 + rng.nextInt(20);
final rY = size.height - _kRibH;
final aW = size.width - _kPad * 2;
for (int i = 0; i < bars; i++) {
final x = _kPad + (aW * i / bars) + rng.nextDouble() * 2;
final h = 1.0 + rng.nextDouble() * 3;
canvas.drawRect(Rect.fromLTWH(x, rY + (_kRibH - h), 1, h),
Paint()..color = Colors.white.atOpacity(0.03 + rng.nextDouble() * 0.03));
}
}
void _paintMarginText(Canvas canvas, Size size) {
// Left margin: "BASELINE INTELLIGENCE PRODUCT"
_rotatedLabel(canvas, 'BASELINE INTELLIGENCE PRODUCT',
Offset(6, size.height / 2), -math.pi / 2);
// Right margin: "OBSERVATIONAL MEASUREMENT ONLY"
_rotatedLabel(canvas, 'OBSERVATIONAL MEASUREMENT ONLY',
Offset(size.width - 6, size.height / 2), math.pi / 2);
}
void _rotatedLabel(Canvas canvas, String text, Offset pos, double angle) {
final tp = TextPainter(
text: TextSpan(text: text,
style: TextStyle(fontFamily: BaselineTypography.monoFontFamily, fontSize: _kMarginFont,
color: Colors.white.atOpacity(_kMarginOp), letterSpacing: 3.0)),
textDirection: TextDirection.ltr)..layout();
canvas.save();
canvas.translate(pos.dx, pos.dy);
canvas.rotate(angle);
tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
canvas.restore();
}
@override
bool shouldRepaint(_FgPainter o) => tsHash != o.tsHash;
}
