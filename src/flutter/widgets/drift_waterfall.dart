/// A-10 — Drift Cascade Waterfall
///
/// Sonar waterfall display for Provision Drift™. Each provision
/// is a return ping against the bill's stated purpose — the
/// further right the bar extends, the further that provision
/// has drifted from why the bill says it exists.
///
/// Threshold zone bands · category grouping · cascade entrance ·
/// signal decay trails · cumulative drift spine · sonar sweep ·
/// inline expansion on tap.
///
/// Pro+ gated via F6.3 `driftWaterfall`.
///
/// Path: lib/widgets/drift_waterfall.dart
library;
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:baseline_app/config/theme.dart';
import 'package:baseline_app/widgets/baseline_icons.dart';
import 'package:baseline_app/models/bill_summary.dart';
import 'package:baseline_app/widgets/info_bottom_sheet.dart';
import 'package:baseline_app/utils/haptic_util.dart';
//
// ═══════════════════════════════════════════════════════════
// CONSTANTS
//
// ═══════════════════════════════════════════════════════════
// Card.
const double _kCardRadius = 14.0;
const double _kCardBorder = 2.0, _kCardBorderOp = 0.30;
const double _kPad = 14.0;
// Grid.
const double _kGridHSp = 8.0, _kGridVSp = 8.0;
const double _kGridHOp = 0.01, _kGridVOp = 0.006;
// Reticle.
const double _kRetOA = 6.0, _kRetOS = 0.5, _kRetOOp = 0.10;
const double _kRetIA = 3.0, _kRetIS = 0.3, _kRetIOp = 0.15;
const double _kRetInset = 6.0;
// Origin line.
const double _kOriginSt = 0.5, _kOriginOp = 0.12;
// Avg drift line.
const double _kAvgSt = 0.5, _kAvgOp = 0.15;
const double _kAvgDash = 4.0, _kAvgGap = 4.0;
// Threshold zones.
const List<double> _kZoneBounds = [0.25, 0.50, 0.75, 1.0];
const List<double> _kZoneOps = [0.0, 0.015, 0.03, 0.05];
const List<String> _kZoneLabels = ['LOW', 'MOD', 'HIGH', 'V.HIGH'];
// Bars.
const double _kBarH = 14.0;
const double _kBarGap = 6.0;
const double _kCatGap = 12.0;
const double _kLeadGlowW = 4.0;
const double _kDecayW = 20.0;
const double _kTitleFont = 10.0, _kTitleOp = 0.40;
const double _kScoreFont = 8.0;
const double _kPillFont = 6.0;
const double _kCatLabelFont = 7.0;
const double _kCatCountFont = 6.0;
const double _kNoteFont = 4.0;
// Header.
const double _kHdrTitleFont = 10.0, _kHdrTitleOp = 0.50;
const double _kHdrSubFont = 5.0, _kHdrSubOp = 0.12;
const double _kAnchorFont = 11.0, _kAnchorOp = 0.30;
const double _kStatFont = 8.0;
// Footer.
const double _kAggScoreFont = 16.0;
const double _kAggLabelFont = 5.0;
const double _kDistH = 3.0, _kDistGap = 1.0;
// Spine.
const double _kSpineSt = 0.5;
// Cascade lines.
const double _kCascSt = 0.3, _kCascOp = 0.03;
// Depth markers.
const double _kDepthFont = 5.0, _kDepthOp = 0.03;
// Observation note.
const double _kObsFont = 5.0, _kObsOp = 0.08;
// Animation durations.
const Duration _kFadeDur = Duration(milliseconds: 200);
const Duration _kSweepDur = Duration(milliseconds: 800);
const Duration _kOriginDur = Duration(milliseconds: 300);
const Duration _kAvgDur = Duration(milliseconds: 200);
const Duration _kBarDur = Duration(milliseconds: 400);
const Duration _kBarStagger = Duration(milliseconds: 40);
const Duration _kSpineDur = Duration(milliseconds: 500);
const Duration _kFooterDur = Duration(milliseconds: 200);
const Duration _kTitleLetterDur = Duration(milliseconds: 400);
// ── Bar area layout ──
// The bar area sits right of depth markers + category icons.
//
// ═══════════════════════════════════════════════════════════
// DRIFT COLOR HELPERS
//
// ═══════════════════════════════════════════════════════════
Color _driftColor(double? score, {double baseOp = 1.0}) {
final s = score ?? 0;
double op;
if (s > 0.75) { op = 0.65; }
else if (s > 0.50) { op = 0.50; }
else if (s > 0.25) { op = 0.35; }
else { op = 0.20; }
return BaselineColors.teal.atOpacity((op * baseOp).clamp(0.0, 1.0));
}
Color _driftPillColor(String? label) {
if (label == 'Very High') return BaselineColors.amber.atOpacity(0.40);
return _driftColor(_labelToScore(label));
}
double _labelToScore(String? label) {
switch (label) {
case 'Very High': return 0.80;
case 'High': return 0.60;
case 'Moderate': return 0.40;
default: return 0.15;
}
}
// Category display order.
const _kCatOrder = [
ProvisionCategory.standaloneProvision,
ProvisionCategory.amendment,
ProvisionCategory.earmark,
ProvisionCategory.rider,
];
//
// ═══════════════════════════════════════════════════════════
// MAIN WIDGET
//
// ═══════════════════════════════════════════════════════════
class DriftWaterfall extends StatefulWidget {
const DriftWaterfall({
super.key,
required this.summary,
this.onInfoTap,
this.onProvisionTap,
});
final BillSummary summary;
final VoidCallback? onInfoTap;
final ValueChanged<Provision>? onProvisionTap;
@override
State<DriftWaterfall> createState() => _DriftWaterfallState();
}
class _DriftWaterfallState extends State<DriftWaterfall>
with TickerProviderStateMixin {
late final AnimationController _fadeCtrl;
late final AnimationController _sweepCtrl;
late final AnimationController _originCtrl;
late final AnimationController _avgCtrl;
late final AnimationController _titleLetterCtrl;
late final List<AnimationController> _barCtrls;
late final AnimationController _spineCtrl;
late final AnimationController _footerCtrl;
bool _disposed = false;
bool _reduceMotion = false;
bool _sequenceStarted = false;
int? _expandedIdx;
late final List<_BarEntry> _entries;
// Spine: GlobalKeys per bar row → measure actual Y positions.
late final List<GlobalKey> _barKeys;
// Tip offsets passed to _BgPainter, updated post-frame.
final ValueNotifier<List<Offset>> _tipOffsets = ValueNotifier([]);
// Parent key for coordinate space.
final GlobalKey _cardKey = GlobalKey();
@override
void initState() {
super.initState();
_buildEntries();
_barKeys = List.generate(_entries.length, (_) => GlobalKey());
_fadeCtrl = AnimationController(vsync: this, duration: _kFadeDur);
_sweepCtrl = AnimationController(vsync: this, duration: _kSweepDur);
_originCtrl = AnimationController(vsync: this, duration: _kOriginDur);
_avgCtrl = AnimationController(vsync: this, duration: _kAvgDur);
_titleLetterCtrl = AnimationController(vsync: this, duration: _kTitleLetterDur);
_barCtrls = List.generate(_entries.length, (_) =>
AnimationController(vsync: this, duration: _kBarDur));
_spineCtrl = AnimationController(vsync: this, duration: _kSpineDur);
_footerCtrl = AnimationController(vsync: this, duration: _kFooterDur);
}
@override
void didChangeDependencies() {
super.didChangeDependencies();
_reduceMotion = MediaQuery.disableAnimationsOf(context);
if (!_sequenceStarted) {
_sequenceStarted = true;
_runSequence();
}
}
void _buildEntries() {
_entries = [];
final byCategory = <ProvisionCategory, List<Provision>>{};
for (final p in widget.summary.provisions) {
if (p.driftScore == null) continue;
(byCategory[p.category] ??= []).add(p);
}
for (final cat in _kCatOrder) {
final list = byCategory[cat];
if (list == null || list.isEmpty) continue;
list.sort((a, b) => (b.driftScore ?? 0).compareTo(a.driftScore ?? 0));
for (int i = 0; i < list.length; i++) {
_entries.add(_BarEntry(
provision: list[i],
isFirstInCategory: i == 0,
globalIdx: _entries.length,
));
}
}
}
Future<void> _runSequence() async {
if (_reduceMotion) {
_fadeCtrl.value = 1.0;
_sweepCtrl.value = 1.0;
_originCtrl.value = 1.0;
_avgCtrl.value = 1.0;
_titleLetterCtrl.value = 1.0;
for (final c in _barCtrls) {
  c.value = 1.0;
}
_spineCtrl.value = 1.0;
_footerCtrl.value = 1.0;
WidgetsBinding.instance.addPostFrameCallback((_) => _measureTips());
return;
}
HapticUtil.light();
_fadeCtrl.forward();
_titleLetterCtrl.forward();
await _wait(_kFadeDur);
if (_disposed) return;
_sweepCtrl.forward();
await _wait(const Duration(milliseconds: 100));
if (_disposed) return;
_originCtrl.forward();
await _wait(_kOriginDur);
if (_disposed) return;
_avgCtrl.forward();
await _wait(const Duration(milliseconds: 100));
for (int i = 0; i < _barCtrls.length; i++) {
if (_disposed) return;
_barCtrls[i].forward();
await _wait(_kBarStagger);
}
// Measure bar tip positions after bars have rendered.
WidgetsBinding.instance.addPostFrameCallback((_) => _measureTips());
await _wait(const Duration(milliseconds: 200));
if (_disposed) return;
_spineCtrl.forward();
await _wait(_kSpineDur);
if (_disposed) return;
_footerCtrl.forward();
}
/// Measure actual bar row positions for spine/cascade alignment.
void _measureTips() {
if (_disposed) return;
final cardRO = _cardKey.currentContext?.findRenderObject() as RenderBox?;
if (cardRO == null) return;
final tips = <Offset>[];
for (int i = 0; i < _barKeys.length; i++) {
final barRO = _barKeys[i].currentContext?.findRenderObject() as RenderBox?;
if (barRO == null) continue;
// Bar center Y in card coordinate space.
final localPos = barRO.localToGlobal(
Offset(barRO.size.width, barRO.size.height / 2),
ancestor: cardRO);
// Tip X = origin + score * barAreaWidth (painter computes this).
// We pass Y only; X is computed in painter from score.
tips.add(Offset(0, localPos.dy)); // X placeholder, painter fills from score.
}
_tipOffsets.value = tips;
}
Future<void> _wait(Duration d) async {
if (_disposed || !mounted) return;
final c = Completer<void>();
Timer(d, c.complete);
await c.future;
}
@override
void dispose() {
_disposed = true;
_fadeCtrl.dispose();
_sweepCtrl.dispose();
_originCtrl.dispose();
_avgCtrl.dispose();
_titleLetterCtrl.dispose();
for (final c in _barCtrls) {
  c.dispose();
}
_spineCtrl.dispose();
_footerCtrl.dispose();
_tipOffsets.dispose();
super.dispose();
}
void _onBarTap(int idx) {
HapticUtil.selection();
setState(() {
_expandedIdx = _expandedIdx == idx ? null : idx;
});
// Re-measure tips after AnimatedSize settles.
Timer(const Duration(milliseconds: 250), () {
if (!_disposed) _measureTips();
});
widget.onProvisionTap?.call(_entries[idx].provision);
}
@override
Widget build(BuildContext context) {
if (_entries.isEmpty) return const SizedBox.shrink();
return FadeTransition(
opacity: _fadeCtrl,
child: Semantics(
label: 'Provision Drift waterfall. '
'${_entries.length} provisions. '
'Average drift ${((widget.summary.avgDriftScore ?? 0) * 100).toStringAsFixed(0)} percent.',
child: Container(
key: _cardKey,
width: double.infinity,
decoration: BoxDecoration(
color: BaselineColors.card,
border: Border.all(
color: BaselineColors.borderInactive.atOpacity(_kCardBorderOp),
width: _kCardBorder),
borderRadius: BorderRadius.circular(_kCardRadius),
),
child: CustomPaint(
painter: _BgPainter(
sweepAnim: _sweepCtrl,
originAnim: _originCtrl,
avgAnim: _avgCtrl,
avgDrift: widget.summary.avgDriftScore,
entries: _entries,
spineAnim: _spineCtrl,
tipOffsets: _tipOffsets,
),
foregroundPainter: _ChromePainter(
color: BaselineColors.teal,
),
child: Padding(
padding: const EdgeInsets.all(_kPad),
child: Column(
mainAxisSize: MainAxisSize.min,
crossAxisAlignment: CrossAxisAlignment.stretch,
children: [
_Header(
summary: widget.summary,
onInfoTap: widget.onInfoTap ?? () =>
InfoBottomSheet.show(context, key: 'provision_drift'),
letterAnim: _titleLetterCtrl,
entryCount: _entries.length,
),
const SizedBox(height: 12),
for (int i = 0; i < _entries.length; i++) ...[
if (_entries[i].isFirstInCategory) ...[
if (i > 0) ...[
const SizedBox(height: _kCatGap),
_GradDiv(),
const SizedBox(height: 6),
],
_AnimW(ctrl: _barCtrls[i], child:
_CatHeader(
category: _entries[i].provision.category,
count: _countCat(_entries[i].provision.category),
avgDrift: _avgCat(_entries[i].provision.category),
)),
const SizedBox(height: 4),
],
_AnimBarW(
ctrl: _barCtrls[i],
child: KeyedSubtree(
key: _barKeys[i],
child: _BarRow(
entry: _entries[i],
isExpanded: _expandedIdx == i,
onTap: () => _onBarTap(i),
animValue: _barCtrls[i],
),
),
),
if (i < _entries.length - 1 &&
!_entries[i + 1].isFirstInCategory)
const SizedBox(height: _kBarGap),
],
const SizedBox(height: 12),
Container(height: 0.5,
color: BaselineColors.teal.atOpacity(0.06)),
const SizedBox(height: 10),
_AnimW(ctrl: _footerCtrl, child:
_Footer(
summary: widget.summary,
entries: _entries,
)),
],
),
),
),
),
),
);
}
int _countCat(ProvisionCategory cat) =>
_entries.where((e) => e.provision.category == cat).length;
double _avgCat(ProvisionCategory cat) {
final list = _entries
.where((e) => e.provision.category == cat)
.map((e) => e.provision.driftScore ?? 0)
.toList();
if (list.isEmpty) return 0;
return list.reduce((a, b) => a + b) / list.length;
}
}
//
// ═══════════════════════════════════════════════════════════
// DATA STRUCTURES
//
// ═══════════════════════════════════════════════════════════
class _BarEntry {
const _BarEntry({
required this.provision,
required this.isFirstInCategory,
required this.globalIdx,
});
final Provision provision;
final bool isFirstInCategory;
final int globalIdx;
}
//
// ═══════════════════════════════════════════════════════════
// ANIMATION WRAPPERS
//
// ═══════════════════════════════════════════════════════════
class _AnimW extends StatelessWidget {
const _AnimW({required this.ctrl, required this.child});
final AnimationController ctrl;
final Widget child;
@override
Widget build(BuildContext context) => FadeTransition(
opacity: CurvedAnimation(parent: ctrl, curve: Curves.easeOut),
child: SlideTransition(
position: Tween<Offset>(
begin: const Offset(0, 0.06), end: Offset.zero,
).animate(CurvedAnimation(parent: ctrl, curve: Curves.easeOutCubic)),
child: child,
),
);
}
/// Bar-specific wrapper: fades in + bar extends right via ClipRect.
class _AnimBarW extends StatelessWidget {
const _AnimBarW({required this.ctrl, required this.child});
final AnimationController ctrl;
final Widget child;
@override
Widget build(BuildContext context) => FadeTransition(
opacity: CurvedAnimation(parent: ctrl, curve: Curves.easeOut),
child: AnimatedBuilder(
animation: ctrl,
builder: (_, c) => ClipRect(
clipper: _BarRevealClipper(ctrl.value),
child: c,
),
child: child,
),
);
}
class _BarRevealClipper extends CustomClipper<Rect> {
_BarRevealClipper(this.reveal);
final double reveal;
@override
Rect getClip(Size size) =>
Rect.fromLTWH(0, 0, size.width * reveal.clamp(0, 1), size.height);
@override
bool shouldReclip(_BarRevealClipper old) => reveal != old.reveal;
}
//
// ═══════════════════════════════════════════════════════════
// HEADER
//
// ═══════════════════════════════════════════════════════════
class _Header extends StatelessWidget {
const _Header({
required this.summary,
required this.onInfoTap,
required this.letterAnim,
required this.entryCount,
});
final BillSummary summary;
final VoidCallback onInfoTap;
final Animation<double> letterAnim;
final int entryCount;
@override
Widget build(BuildContext context) {
return GestureDetector(
onTap: onInfoTap,
behavior: HitTestBehavior.opaque,
child: Semantics(
button: true,
label: 'Provision Drift info. Tap for explanation.',
child: Column(
crossAxisAlignment: CrossAxisAlignment.start,
mainAxisSize: MainAxisSize.min,
children: [
Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
Expanded(child: Column(
crossAxisAlignment: CrossAxisAlignment.start,
mainAxisSize: MainAxisSize.min,
children: [
AnimatedBuilder(
animation: letterAnim,
builder: (_, _) => Text('PROVISION DRIFT™',
style: BaselineTypography.dataSmall.copyWith(
fontSize: _kHdrTitleFont,
color: BaselineColors.teal.atOpacity(_kHdrTitleOp),
letterSpacing: 4.0 - (letterAnim.value * 2.0),
)),
),
const SizedBox(height: 2),
Text('DRIFT CASCADE · WATERFALL VIEW',
style: BaselineTypography.dataSmall.copyWith(
fontSize: _kHdrSubFont,
color: BaselineColors.white.atOpacity(_kHdrSubOp),
letterSpacing: 1.5)),
],
)),
Column(
crossAxisAlignment: CrossAxisAlignment.end,
mainAxisSize: MainAxisSize.min,
children: [
Text('$entryCount PROVISIONS',
style: BaselineTypography.dataSmall.copyWith(
fontSize: _kStatFont,
color: BaselineColors.teal.atOpacity(0.30))),
if (summary.avgDriftScore != null)
Text('μ ${(summary.avgDriftScore! * 100).toStringAsFixed(1)}%',
style: BaselineTypography.dataSmall.copyWith(
fontSize: 7,
color: _driftColor(summary.avgDriftScore))),
],
),
const SizedBox(width: 8),
BaselineIcon(BaselineIconType.info, size: 16,
color: BaselineColors.white.atOpacity(0.20)),
]),
// Stated purpose anchor.
const SizedBox(height: 8),
Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
Text('ANCHOR: ', style: BaselineTypography.dataSmall.copyWith(
fontSize: 5, color: BaselineColors.teal.atOpacity(0.10),
letterSpacing: 1.0)),
Expanded(child: Text(summary.statedPurpose,
maxLines: 2, overflow: TextOverflow.ellipsis,
style: TextStyle(
fontFamily: BaselineTypography.bodyFontFamily, fontSize: _kAnchorFont,
color: BaselineColors.white.atOpacity(_kAnchorOp),
height: 1.4))),
]),
],
),
),
);
}
}
//
// ═══════════════════════════════════════════════════════════
// CATEGORY HEADER
//
// ═══════════════════════════════════════════════════════════
class _CatHeader extends StatelessWidget {
const _CatHeader({
required this.category,
required this.count,
required this.avgDrift,
});
final ProvisionCategory category;
final int count;
final double avgDrift;
@override
Widget build(BuildContext context) {
return Padding(
padding: const EdgeInsets.only(left: 2),
child: Row(children: [
// Category icon.
CustomPaint(
size: const Size(6, 6),
painter: _CatIconPainter(category)),
const SizedBox(width: 5),
Text(category.label.toUpperCase(),
style: BaselineTypography.dataSmall.copyWith(
fontSize: _kCatLabelFont,
color: BaselineColors.white.atOpacity(0.20),
letterSpacing: 1.5)),
const SizedBox(width: 4),
Text('(×$count)',
style: BaselineTypography.dataSmall.copyWith(
fontSize: _kCatCountFont,
color: BaselineColors.teal.atOpacity(0.15))),
const Spacer(),
Text('μ ${(avgDrift * 100).toStringAsFixed(1)}%',
style: BaselineTypography.dataSmall.copyWith(
fontSize: _kCatCountFont,
color: _driftColor(avgDrift))),
]),
);
}
}
class _CatIconPainter extends CustomPainter {
_CatIconPainter(this.cat);
final ProvisionCategory cat;
@override
void paint(Canvas canvas, Size size) {
final cx = size.width / 2, cy = size.height / 2;
switch (cat) {
case ProvisionCategory.standaloneProvision:
canvas.drawRect(
Rect.fromCenter(center: Offset(cx, cy), width: 3, height: 3),
Paint()..color = BaselineColors.teal.atOpacity(0.30));
break;
case ProvisionCategory.amendment:
final path = Path()
..moveTo(cx, cy - 1.5)
..lineTo(cx + 1.5, cy + 1.5)
..lineTo(cx - 1.5, cy + 1.5)
..close();
canvas.drawPath(path, Paint()..color = BaselineColors.teal.atOpacity(0.25)
..style = PaintingStyle.stroke..strokeWidth = 0.8);
break;
case ProvisionCategory.earmark:
final path = Path()
..moveTo(cx, cy - 2)..lineTo(cx + 2, cy)
..lineTo(cx, cy + 2)..lineTo(cx - 2, cy)..close();
canvas.drawPath(path,
Paint()..color = BaselineColors.teal.atOpacity(0.20));
break;
case ProvisionCategory.rider:
canvas.drawCircle(Offset(cx, cy), 2,
Paint()..color = BaselineColors.teal.atOpacity(0.15)
..style = PaintingStyle.stroke..strokeWidth = 0.8);
break;
}
}
@override
bool shouldRepaint(covariant _CatIconPainter old) => cat != old.cat;
}
//
// ═══════════════════════════════════════════════════════════
// BAR ROW
//
// ═══════════════════════════════════════════════════════════
class _BarRow extends StatelessWidget {
const _BarRow({
required this.entry,
required this.isExpanded,
required this.onTap,
required this.animValue,
});
final _BarEntry entry;
final bool isExpanded;
final VoidCallback onTap;
final Animation<double> animValue;
Provision get _p => entry.provision;
double get _score => _p.driftScore ?? 0;
@override
Widget build(BuildContext context) {
final barColor = _driftColor(_score);
final glowOp = 0.003 + (_score).clamp(0.0, 1.0) * 0.02;
return GestureDetector(
onTap: onTap,
behavior: HitTestBehavior.opaque,
child: Semantics(
label: '${_p.title}. ${_p.category.label}. '
'Drift ${(_score * 100).toStringAsFixed(0)} percent, ${_p.driftLabel ?? "unknown"}.',
child: AnimatedSize(
duration: const Duration(milliseconds: 200),
curve: Curves.easeOutCubic,
alignment: Alignment.topCenter,
child: Container(
decoration: BoxDecoration(
gradient: LinearGradient(
colors: [
BaselineColors.teal.atOpacity(glowOp),
Colors.transparent,
],
),
borderRadius: BorderRadius.circular(4),
),
padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
child: Column(
crossAxisAlignment: CrossAxisAlignment.stretch,
mainAxisSize: MainAxisSize.min,
children: [
// Depth marker + bar.
Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
// Depth index.
SizedBox(width: 16, child: Text(
(entry.globalIdx + 1).toString().padLeft(2, '0'),
style: BaselineTypography.dataSmall.copyWith(
fontSize: _kDepthFont,
color: BaselineColors.white.atOpacity(_kDepthOp)),
)),
// Bar.
Expanded(child: LayoutBuilder(
builder: (_, constraints) {
final barW = constraints.maxWidth;
return SizedBox(
height: _kBarH,
child: AnimatedBuilder(
animation: animValue,
builder: (_, _) => CustomPaint(
size: Size(barW, _kBarH),
painter: _BarPainter(
score: _score,
barColor: barColor,
barWidth: barW,
seed: _p.title.hashCode,
settlePhase: animValue.value,
),
),
),
);
},
)),
// Score label.
const SizedBox(width: 6),
SizedBox(width: 36, child: Text(
'${(_score * 100).toStringAsFixed(1)}%',
textAlign: TextAlign.right,
style: BaselineTypography.dataSmall.copyWith(
fontSize: _kScoreFont, color: barColor),
)),
]),
// Title row.
const SizedBox(height: 2),
Padding(
padding: const EdgeInsets.only(left: 16),
child: Row(children: [
CustomPaint(
size: const Size(4, 4),
painter: _CatIconPainter(_p.category)),
const SizedBox(width: 4),
Expanded(child: Text(_p.title,
maxLines: isExpanded ? 3 : 1,
overflow: TextOverflow.ellipsis,
style: TextStyle(
fontFamily: BaselineTypography.bodyFontFamily, fontSize: _kTitleFont,
color: BaselineColors.white.atOpacity(_kTitleOp),
height: 1.3))),
if (_p.provisionNote.isNotEmpty && !isExpanded)
Container(
margin: const EdgeInsets.only(left: 4),
padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
decoration: BoxDecoration(
border: Border.all(
color: BaselineColors.teal.atOpacity(0.06), width: 1),
borderRadius: BorderRadius.circular(2)),
child: Text('NOTE', style: BaselineTypography.dataSmall.copyWith(
fontSize: _kNoteFont,
color: BaselineColors.teal.atOpacity(0.12))),
),
const SizedBox(width: 4),
// Drift label pill.
Container(
padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
decoration: BoxDecoration(
border: Border.all(
color: _driftPillColor(_p.driftLabel).atOpacity(0.30),
width: 1),
borderRadius: BorderRadius.circular(3)),
child: Text(_p.driftLabel ?? '-',
style: BaselineTypography.dataSmall.copyWith(
fontSize: _kPillFont,
color: _driftPillColor(_p.driftLabel))),
),
]),
),
// Expanded detail.
if (isExpanded) ...[
const SizedBox(height: 6),
Padding(
padding: const EdgeInsets.only(left: 20),
child: Column(
crossAxisAlignment: CrossAxisAlignment.start,
mainAxisSize: MainAxisSize.min,
children: [
Text(_p.description,
maxLines: 3, overflow: TextOverflow.ellipsis,
style: TextStyle(
fontFamily: BaselineTypography.bodyFontFamily, fontSize: 10,
color: BaselineColors.white.atOpacity(0.30),
height: 1.4)),
if (_p.provisionNote.isNotEmpty) ...[
const SizedBox(height: 4),
Text(_p.provisionNote,
maxLines: 2, overflow: TextOverflow.ellipsis,
style: BaselineTypography.dataSmall.copyWith(
fontSize: 8,
color: BaselineColors.teal.atOpacity(0.20),
fontStyle: FontStyle.italic)),
],
],
),
),
],
],
),
),
),
),
);
}
}
//
// ═══════════════════════════════════════════════════════════
// BAR PAINTER (per bar — track, fill, glow, decay, noise)
//
// ═══════════════════════════════════════════════════════════
class _BarPainter extends CustomPainter {
_BarPainter({
required this.score,
required this.barColor,
required this.barWidth,
required this.seed,
required this.settlePhase,
});
final double score;
final Color barColor;
final double barWidth;
final int seed; // provision.title.hashCode — stable identity.
final double settlePhase; // 0→1, bar controller value for echo ring anim.
@override
void paint(Canvas canvas, Size size) {
final h = size.height, midY = h / 2;
final fillW = score * barWidth;
// Track.
canvas.drawLine(Offset(0, midY), Offset(barWidth, midY),
Paint()..color = BaselineColors.white.atOpacity(0.02)..strokeWidth = 0.3);
if (fillW < 1) return;
// ── Sawtooth leading edge path (seeded from provision title) ──
final sawRng = math.Random(seed);
final jitterAmp = 0.5 + score.clamp(0.0, 1.0) * 1.0;
final barPath = Path()..moveTo(0, 0)..lineTo(0, h);
barPath.lineTo(fillW, h);
for (double y = h; y > 0; y -= 2) {
final jitter = (sawRng.nextDouble() - 0.5) * jitterAmp * 2;
barPath.lineTo(fillW + jitter, y);
}
barPath.close();
canvas.drawPath(barPath, Paint()..color = barColor);
// Signal noise texture (seeded from provision title).
final noiseRng = math.Random(seed ^ 0x5F3759DF);
final nP = Paint()..color = barColor.atOpacity(
(barColor.a - 0.05).clamp(0.01, 1.0))..strokeWidth = 0.3;
for (double x = 2; x < fillW - 2; x += 4) {
final jitter = (noiseRng.nextDouble() - 0.5) * 1.0;
canvas.drawLine(Offset(x, midY + jitter - 0.3),
Offset(x + 2, midY + jitter + 0.3), nP);
}
// Leading edge glow.
final glowRect = Rect.fromLTWH(
fillW - _kLeadGlowW, 0, _kLeadGlowW * 2.5, h);
canvas.drawRect(glowRect, Paint()..shader = LinearGradient(
colors: [Colors.transparent,
barColor.atOpacity((barColor.a + 0.12).clamp(0.0, 1.0)),
Colors.transparent],
stops: const [0.0, 0.45, 1.0],
).createShader(glowRect));
// Flash dot at tip.
canvas.drawCircle(Offset(fillW, midY), 1.5,
Paint()..color = BaselineColors.teal.atOpacity(0.30));
// Signal decay trail (high drift).
if (score > 0.50 && fillW < barWidth - _kDecayW) {
final decayOp = (score - 0.5) * 0.16;
final decayRect = Rect.fromLTWH(fillW, 0, _kDecayW, h);
canvas.drawRect(decayRect, Paint()..shader = LinearGradient(
colors: [barColor.atOpacity(decayOp), Colors.transparent],
).createShader(decayRect));
}
// ── Ping echo rings (drift > 40%, animated on settle) ──
if (score > 0.40 && settlePhase > 0.8) {
final ringProgress = ((settlePhase - 0.8) / 0.2).clamp(0.0, 1.0);
final ringScale = 0.8 + 0.2 * Curves.easeOutCubic.transform(ringProgress);
final ringCount = score > 0.65 ? 3 : 2;
for (int r = 0; r < ringCount; r++) {
final baseRadius = 4.0 + r * 4.0;
final radius = baseRadius * ringScale;
final ringOp = (0.06 / (r + 1)) * ringProgress;
canvas.drawArc(
Rect.fromCircle(center: Offset(fillW, midY), radius: radius),
-0.8, 1.6, false,
Paint()..color = BaselineColors.teal.atOpacity(ringOp)
..strokeWidth = 0.3..style = PaintingStyle.stroke);
}
}
}
@override
bool shouldRepaint(covariant _BarPainter old) =>
score != old.score || barWidth != old.barWidth ||
settlePhase != old.settlePhase;
}
//
// ═══════════════════════════════════════════════════════════
// FOOTER
//
// ═══════════════════════════════════════════════════════════
class _Footer extends StatelessWidget {
const _Footer({required this.summary, required this.entries});
final BillSummary summary;
final List<_BarEntry> entries;
String get _level {
final s = summary.avgDriftScore ?? 0;
if (s > 0.75) return 'VERY HIGH';
if (s > 0.50) return 'HIGH';
if (s > 0.25) return 'MODERATE';
return 'LOW';
}
@override
Widget build(BuildContext context) {
// Distribution counts.
int low = 0, mod = 0, high = 0, vhigh = 0;
for (final e in entries) {
final s = e.provision.driftScore ?? 0;
if (s > 0.75) {
  vhigh++;
} else if (s > 0.50) {
  high++;
} else if (s > 0.25) {
  mod++;
} else {
  low++;
}
}
return Column(
crossAxisAlignment: CrossAxisAlignment.start,
mainAxisSize: MainAxisSize.min,
children: [
// Distribution bar.
SizedBox(
height: _kDistH,
child: Builder(builder: (_) {
final segments = <(int, double)>[
if (low > 0) (low, 0.15),
if (mod > 0) (mod, 0.30),
if (high > 0) (high, 0.45),
if (vhigh > 0) (vhigh, 0.60),
];
return Row(children: [
for (int s = 0; s < segments.length; s++) ...[
if (s > 0) const SizedBox(width: _kDistGap),
Expanded(
flex: segments[s].$1,
child: Container(
decoration: BoxDecoration(
color: BaselineColors.teal.atOpacity(segments[s].$2),
borderRadius: BorderRadius.circular(0.5)),
),
),
],
]);
}),
),
const SizedBox(height: 3),
// Count labels.
Row(children: [
for (final (label, count) in [
('Low', low), ('Mod', mod), ('High', high), ('V.High', vhigh),
])
if (count > 0)
Padding(
padding: const EdgeInsets.only(right: 8),
child: Text('$label ×$count',
style: BaselineTypography.dataSmall.copyWith(
fontSize: 5, color: BaselineColors.white.atOpacity(0.08)))),
]),
const SizedBox(height: 8),
// Aggregate readout.
Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
Column(
crossAxisAlignment: CrossAxisAlignment.start,
mainAxisSize: MainAxisSize.min,
children: [
Text('AVG DRIFT', style: BaselineTypography.dataSmall.copyWith(
fontSize: _kAggLabelFont,
color: BaselineColors.white.atOpacity(0.10),
letterSpacing: 1.5)),
Text(
'${((summary.avgDriftScore ?? 0) * 100).toStringAsFixed(1)}%',
style: BaselineTypography.dataSmall.copyWith(
fontSize: _kAggScoreFont,
color: _driftColor(summary.avgDriftScore, baseOp: 1.4))),
],
),
const SizedBox(width: 10),
Text(_level, style: BaselineTypography.dataSmall.copyWith(
fontSize: 7,
color: _level == 'VERY HIGH'
? BaselineColors.amber.atOpacity(0.40)
: _driftColor(summary.avgDriftScore),
letterSpacing: 1.0)),
const Spacer(),
// Timestamp.
Text(
'COMPUTED ${_formatDate(summary.createdAt)}',
style: BaselineTypography.dataSmall.copyWith(
fontSize: 4,
color: BaselineColors.teal.atOpacity(0.06))),
]),
const SizedBox(height: 8),
// Observation note.
Text(
'Provision Drift™ measures semantic distance from stated purpose. Not an evaluation.',
style: BaselineTypography.dataSmall.copyWith(
fontSize: _kObsFont,
color: BaselineColors.white.atOpacity(_kObsOp),
letterSpacing: 0.3)),
],
);
}
String _formatDate(DateTime dt) {
final m = dt.month.toString().padLeft(2, '0');
final d = dt.day.toString().padLeft(2, '0');
return '${dt.year}-$m-$d';
}
}
//
// ═══════════════════════════════════════════════════════════
// BACKGROUND PAINTER (grid, zones, origin, avg, sweep, spine)
//
// ═══════════════════════════════════════════════════════════
class _BgPainter extends CustomPainter {
_BgPainter({
required this.sweepAnim,
required this.originAnim,
required this.avgAnim,
required this.avgDrift,
required this.entries,
required this.spineAnim,
required this.tipOffsets,
}) : super(repaint: Listenable.merge([sweepAnim, originAnim, avgAnim, spineAnim,
tipOffsets]));
final Animation<double> sweepAnim;
final Animation<double> originAnim;
final Animation<double> avgAnim;
final double? avgDrift;
final List<_BarEntry> entries;
final Animation<double> spineAnim;
final ValueNotifier<List<Offset>> tipOffsets;
@override
void paint(Canvas canvas, Size size) {
canvas.save();
canvas.clipRRect(RRect.fromRectAndRadius(
Rect.fromLTWH(0, 0, size.width, size.height),
const Radius.circular(_kCardRadius)));
// ── Scan grid ──
final hP = Paint()..color = BaselineColors.white.atOpacity(_kGridHOp)..strokeWidth = 0.3;
final vP = Paint()..color = BaselineColors.white.atOpacity(_kGridVOp)..strokeWidth = 0.3;
for (double y = _kGridHSp; y < size.height; y += _kGridHSp) {
canvas.drawLine(Offset(0, y), Offset(size.width, y), hP);
}
for (double x = _kGridVSp; x < size.width; x += _kGridVSp) {
canvas.drawLine(Offset(x, 0), Offset(x, size.height), vP);
}
// Bar area bounds (estimated to match layout).
final barL = _kPad + 32;
final barR = size.width - _kPad - 42;
final barW = barR - barL;
// ── Threshold zone bands ──
for (int z = 0; z < 4; z++) {
final zStart = z == 0 ? 0.0 : _kZoneBounds[z - 1];
final zEnd = _kZoneBounds[z];
if (_kZoneOps[z] > 0) {
canvas.drawRect(
Rect.fromLTRB(
barL + zStart * barW, 0,
barL + zEnd * barW, size.height),
Paint()..color = BaselineColors.teal.atOpacity(_kZoneOps[z]));
}
// Zone label at top.
final tp = TextPainter(
text: TextSpan(text: _kZoneLabels[z], style: TextStyle(
fontFamily: BaselineTypography.monoFontFamily, fontSize: 4,
color: BaselineColors.white.atOpacity(0.03), letterSpacing: 0.5)),
textDirection: TextDirection.ltr)..layout();
final zMid = barL + (zStart + zEnd) / 2 * barW - tp.width / 2;
tp.paint(canvas, Offset(zMid, _kPad + 2));
}
// V.HIGH right edge border.
canvas.drawLine(
Offset(barL + barW, 0), Offset(barL + barW, size.height),
Paint()..color = BaselineColors.teal.atOpacity(0.06)..strokeWidth = 0.3);
// ── Origin line ──
if (originAnim.value > 0) {
final originH = size.height * originAnim.value;
canvas.drawLine(Offset(barL, 0), Offset(barL, originH),
Paint()..color = BaselineColors.teal.atOpacity(_kOriginOp)
..strokeWidth = _kOriginSt);
if (originAnim.value > 0.5) {
final tp = TextPainter(
text: TextSpan(text: 'PURPOSE', style: TextStyle(
fontFamily: BaselineTypography.monoFontFamily, fontSize: 4,
color: BaselineColors.teal.atOpacity(0.08 * originAnim.value),
letterSpacing: 1.0)),
textDirection: TextDirection.ltr)..layout();
tp.paint(canvas, Offset(barL + 2, _kPad + 10));
}
}
// ── Average drift line ──
if (avgDrift != null && avgAnim.value > 0) {
final ax = barL + avgDrift! * barW;
final dashP = Paint()
..color = BaselineColors.teal.atOpacity(_kAvgOp * avgAnim.value)
..strokeWidth = _kAvgSt;
double dy = 0;
while (dy < size.height) {
canvas.drawLine(Offset(ax, dy),
Offset(ax, (dy + _kAvgDash).clamp(0, size.height)), dashP);
dy += _kAvgDash + _kAvgGap;
}
final tp = TextPainter(
text: TextSpan(text: 'μ', style: TextStyle(
fontFamily: BaselineTypography.monoFontFamily, fontSize: 6,
color: BaselineColors.teal.atOpacity(0.10 * avgAnim.value))),
textDirection: TextDirection.ltr)..layout();
tp.paint(canvas, Offset(ax - tp.width / 2, _kPad + 10));
}
// ── Sonar sweep with phosphor wake ──
if (sweepAnim.value > 0 && sweepAnim.value < 1) {
final sweepPos = Curves.easeOutCubic.transform(sweepAnim.value);
final sx = barL + sweepPos * barW;
final edgeFade = 1.0 - sweepPos; // Fades near right edge.
// Phosphor wake trail (24px behind leading edge).
const trailW = 24.0;
final trailRect = Rect.fromLTWH(
(sx - trailW).clamp(barL.toDouble(), sx), 0, trailW, size.height);
canvas.drawRect(trailRect, Paint()..shader = LinearGradient(
colors: [
Colors.transparent,
BaselineColors.teal.atOpacity(0.03 * edgeFade),
BaselineColors.teal.atOpacity(0.08 * edgeFade),
],
stops: const [0.0, 0.4, 1.0],
).createShader(trailRect));
// Leading edge line.
canvas.drawRect(
Rect.fromLTWH(sx, 0, 1.5, size.height),
Paint()..color = BaselineColors.teal.atOpacity(0.12 * edgeFade));
}
// ── Cascade lines + Cumulative drift spine ──
// Uses measured Y positions from GlobalKeys (tipOffsets).
// tipOffsets.value[i].dy = measured center Y of bar row i.
// tipOffsets.value[i].dx = 0 (placeholder — X computed from score).
final measuredYs = tipOffsets.value;
if (entries.isNotEmpty && spineAnim.value > 0 && measuredYs.length == entries.length) {
final tips = <Offset>[];
for (int i = 0; i < entries.length; i++) {
final tipX = barL + (entries[i].provision.driftScore ?? 0) * barW;
tips.add(Offset(tipX, measuredYs[i].dy));
}
final revealCount = (tips.length * spineAnim.value).ceil().clamp(0, tips.length);
// ── Cascade lines (diagonal connectors) ──
final cascP = Paint()..color = BaselineColors.white.atOpacity(_kCascOp)
..strokeWidth = _kCascSt;
for (int i = 0; i < revealCount - 1; i++) {
canvas.drawLine(tips[i], tips[i + 1], cascP);
}
// ── Cumulative drift spine ──
if (revealCount >= 2) {
// Spine glow halo.
final glowPath = Path()..moveTo(tips[0].dx, tips[0].dy);
for (int i = 1; i < revealCount; i++) {
glowPath.lineTo(tips[i].dx, tips[i].dy);
}
canvas.drawPath(glowPath, Paint()
..color = BaselineColors.teal.atOpacity(0.03)
..strokeWidth = 3.0..style = PaintingStyle.stroke
..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round);
// Spine core line.
final spinePath = Path()..moveTo(tips[0].dx, tips[0].dy);
for (int i = 1; i < revealCount; i++) {
spinePath.lineTo(tips[i].dx, tips[i].dy);
}
canvas.drawPath(spinePath, Paint()
..color = BaselineColors.teal.atOpacity(0.10)
..strokeWidth = _kSpineSt..style = PaintingStyle.stroke
..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round);
// Tip dots.
for (int i = 0; i < revealCount; i++) {
canvas.drawCircle(tips[i], 1.5, Paint()
..color = BaselineColors.teal.atOpacity(0.12));
}
}
}
canvas.restore();
}
@override
bool shouldRepaint(covariant _BgPainter old) => false;
}
//
// ═══════════════════════════════════════════════════════════
// CHROME PAINTER (reticle corners, scan count)
//
// ═══════════════════════════════════════════════════════════
class _ChromePainter extends CustomPainter {
_ChromePainter({required this.color});
final Color color;
@override
void paint(Canvas canvas, Size size) {
final oP = Paint()..color = color.atOpacity(_kRetOOp)
..strokeWidth = _kRetOS..strokeCap = StrokeCap.square;
final iP = Paint()..color = color.atOpacity(_kRetIOp)
..strokeWidth = _kRetIS..strokeCap = StrokeCap.square;
for (final (cx, cy, dx, dy) in [
(_kRetInset, _kRetInset, 1.0, 1.0),
(size.width - _kRetInset, _kRetInset, -1.0, 1.0),
(_kRetInset, size.height - _kRetInset, 1.0, -1.0),
(size.width - _kRetInset, size.height - _kRetInset, -1.0, -1.0),
]) {
canvas.drawLine(Offset(cx, cy), Offset(cx + _kRetOA * dx, cy), oP);
canvas.drawLine(Offset(cx, cy), Offset(cx, cy + _kRetOA * dy), oP);
final ix = cx + 2 * dx, iy = cy + 2 * dy;
canvas.drawLine(Offset(ix, iy), Offset(ix + _kRetIA * dx, iy), iP);
canvas.drawLine(Offset(ix, iy), Offset(ix, iy + _kRetIA * dy), iP);
}
}
@override
bool shouldRepaint(covariant _ChromePainter old) => false;
}
//
// ═══════════════════════════════════════════════════════════
// HELPERS
//
// ═══════════════════════════════════════════════════════════
class _GradDiv extends StatelessWidget {
@override
Widget build(BuildContext c) => Container(height: 1,
decoration: BoxDecoration(gradient: LinearGradient(
colors: [Colors.transparent,
BaselineColors.teal.atOpacity(0.10),
BaselineColors.teal.atOpacity(0.10),
Colors.transparent],
stops: const [0, 0.3, 0.7, 1])));
}
