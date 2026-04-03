/// A-4 — Split Microscope™ Variance Strip
///
/// Chromatic aberration microscopy for model variance.
/// Three analytical wavelengths (GP · CL · GR) through the
/// same specimen — where they converge the signal is sharp,
/// where they diverge you see prismatic splitting.
///
/// Eyepiece reticle · specimen grid · wavelength emission
/// lines · chromatic aberration zones · diffraction rings ·
/// measurement calipers · signal noise · prismatic index ·
/// variance gauge · framing objective analysis.
///
/// Pro+ gated via F6.3 `splitMicroscope`.
///
/// Path: lib/widgets/variance_strip.dart
library;
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:baseline_app/config/theme.dart';
import 'package:baseline_app/models/lens_lab.dart';
import 'package:baseline_app/widgets/baseline_icons.dart';
import 'package:baseline_app/widgets/info_bottom_sheet.dart';
import 'package:baseline_app/utils/haptic_util.dart';
//
// ═══════════════════════════════════════════════════════════
// CONSTANTS
//
// ═══════════════════════════════════════════════════════════
// Card shell.
const double _kCardRadius = 14.0;
const double _kCardBorder = 2.0, _kCardBorderOp = 0.30;
const double _kPadOuter = 12.0; // Padding outside eyepiece.
// Eyepiece.
const double _kEyeDash = 6.0, _kEyeGap = 4.0;
const double _kEyeSt = 0.5, _kEyeOp = 0.04;
const double _kEyeInset = 8.0; // Inset from card padding.
// Reticle crosshairs.
const double _kCrossSt = 0.3, _kCrossOp = 0.02;
const double _kCrossDotR = 1.5, _kCrossDotOp = 0.06;
// Vignette.
const double _kVigOp = 0.04;
// Specimen grid.
const double _kGridSp = 20.0, _kGridSt = 0.3, _kGridOp = 0.012;
const double _kGridLabelFont = 4.0, _kGridLabelOp = 0.02;
// Three wavelengths.
const Color _kGPHue = BaselineColors.spectralTeal; // Pure teal — λ₁
const Color _kCLHue = BaselineColors.spectralCyan; // Cyan shift — λ₂
const Color _kGRHue = BaselineColors.spectralGreen; // Green shift — λ₃
const List<Color> _kHues = [_kGPHue, _kCLHue, _kGRHue];
const List<double> _kHueOps = [0.55, 0.45, 0.35];
// Header.
const double _kTitleFont = 10.0, _kTitleOp = 0.50;
const double _kSubFont = 5.0, _kSubOp = 0.12;
const double _kSpecIdFont = 5.0, _kSpecIdOp = 0.12;
const double _kMagFont = 12.0, _kMagOp = 0.06;
// Metric rows.
const double _kRowH = 60.0;
const double _kLabelFont = 6.0, _kLabelOp = 0.15;
const double _kTrackSt = 0.5, _kTrackOp = 0.04;
// Emission lines.
const double _kEmitH = 16.0, _kEmitSt = 0.5;
// Chromatic aberration.
const double _kAbH = 6.0; // Height of each model's aberration band.
const double _kAbShift = 1.0; // Vertical offset between model bands.
// Diffraction rings.
const double _kDiffSt = 0.3, _kDiffOp = 0.03;
// Calipers.
const double _kCalH = 8.0, _kCalSt = 1.0, _kCalOp = 0.12;
const double _kCalDashOp = 0.06;
// Consensus marker.
const double _kMuTriH = 4.0, _kMuOp = 0.20;
// Spread readout.
const double _kSpreadFont = 9.0;
const double _kSpreadLow = 10.0, _kSpreadHigh = 25.0;
// Ticks.
const double _kTickMinH = 3.0, _kTickMajH = 5.0;
const double _kTickMinOp = 0.03, _kTickMajOp = 0.05;
// Noise.
const double _kNoiseMaxAmp = 4.0;
// Row separator.
const double _kRowSepOp = 0.03;
// Prismatic index.
const double _kPrisH = 2.0, _kPrisGap = 1.0;
// Framing.
const double _kFramingFont = 8.0;
const double _kFramingBorderW = 2.0;
// Gauge.
const double _kGaugeW = 30.0;
const double _kGaugeTrackOp = 0.05, _kGaugeFillOp = 0.30;
const double _kGaugeNeedleOp = 0.45;
const double _kAggPctFont = 20.0, _kAggPctOp = 0.70;
const double _kAggLabelFont = 5.0, _kAggLabelOp = 0.12;
const double _kClassFont = 8.0;
const double _kAggLow = 0.08, _kAggHigh = 0.20;
// Mini bars.
const double _kMiniBarW = 2.0, _kMiniBarMinH = 4.0, _kMiniBarMaxH = 14.0;
const double _kMiniBarGap = 2.0;
// Stage coordinates.
const double _kStageFont = 5.0, _kStageOp = 0.08;
// Observation note.
const double _kNoteFont = 5.0, _kNoteOp = 0.08;
// Animation durations.
const Duration _kFadeIn = Duration(milliseconds: 200);
const Duration _kRingPulse = Duration(milliseconds: 600);
const Duration _kCrossDraw = Duration(milliseconds: 300);
const Duration _kGridFade = Duration(milliseconds: 250);
const Duration _kRowDur = Duration(milliseconds: 350);
const Duration _kRowStagger = Duration(milliseconds: 50);
const Duration _kNoiseDur = Duration(milliseconds: 300);
const Duration _kWaveDur = Duration(milliseconds: 200);
const Duration _kCaliperSnap = Duration(milliseconds: 150);
const Duration _kFocusDur = Duration(milliseconds: 300);
const Duration _kGaugeDur = Duration(milliseconds: 500);
const Duration _kTitleLetterDur = Duration(milliseconds: 400);
const Duration _kFramingDelay = Duration(milliseconds: 200);
const Duration _kFooterDelay = Duration(milliseconds: 150);
//
// ═══════════════════════════════════════════════════════════
// MAIN WIDGET
//
// ═══════════════════════════════════════════════════════════
class VarianceStrip extends StatefulWidget {
const VarianceStrip({
super.key,
required this.comparison,
this.onInfoTap,
});
final LensComparison comparison;
final VoidCallback? onInfoTap;
@override
State<VarianceStrip> createState() => _VarianceStripState();
}
class _VarianceStripState extends State<VarianceStrip>
with TickerProviderStateMixin {
// Controllers.
late final AnimationController _fadeCtrl;
late final AnimationController _ringCtrl;
late final AnimationController _crossCtrl;
late final AnimationController _gridCtrl;
late final AnimationController _titleLetterCtrl;
late final List<AnimationController> _rowCtrls;
late final List<AnimationController> _noiseCtrls;
late final List<AnimationController> _waveCtrls;
late final AnimationController _caliperCtrl;
late final AnimationController _focusCtrl;
late final AnimationController _framingCtrl;
late final AnimationController _footerCtrl;
late final AnimationController _gaugeCtrl;
// Breathe animation for high-spread underline.
late final AnimationController _breatheCtrl;
int _breatheCycles = 0;
bool _disposed = false;
List<MetricComparison> get _metrics =>
widget.comparison.metrics.where((m) => m.values.length >= 2).toList();
double get _aggScore {
final m = _metrics;
if (m.isEmpty) return 0.0;
return (m.fold<double>(0, (s, mc) => s + mc.spread) / (m.length * 100))
.clamp(0.0, 1.0);
}
int get _maxSpreadIdx {
final m = _metrics;
if (m.isEmpty) return 0;
int idx = 0;
for (int i = 1; i < m.length; i++) {
if (m[i].spread > m[idx].spread) idx = i;
}
return idx;
}
bool get _hasHighSpread => _metrics.any((m) => m.spread > _kSpreadHigh);
@override
void initState() {
super.initState();
final n = _metrics.length;
_fadeCtrl = AnimationController(vsync: this, duration: _kFadeIn);
_ringCtrl = AnimationController(vsync: this, duration: _kRingPulse);
_crossCtrl = AnimationController(vsync: this, duration: _kCrossDraw);
_gridCtrl = AnimationController(vsync: this, duration: _kGridFade);
_titleLetterCtrl = AnimationController(vsync: this, duration: _kTitleLetterDur);
_rowCtrls = List.generate(n, (_) =>
AnimationController(vsync: this, duration: _kRowDur));
_noiseCtrls = List.generate(n, (_) =>
AnimationController(vsync: this, duration: _kNoiseDur));
_waveCtrls = List.generate(n, (_) =>
AnimationController(vsync: this, duration: _kWaveDur));
_caliperCtrl = AnimationController(vsync: this, duration: _kCaliperSnap);
_focusCtrl = AnimationController(vsync: this, duration: _kFocusDur);
_framingCtrl = AnimationController(vsync: this, duration: _kRowDur);
_footerCtrl = AnimationController(vsync: this, duration: _kRowDur);
_gaugeCtrl = AnimationController(vsync: this, duration: _kGaugeDur);
_breatheCtrl = AnimationController(vsync: this,
duration: const Duration(milliseconds: 1000));
// Finite breathe: 3 forward/reverse cycles then stop.
_breatheCtrl.addStatusListener((status) {
if (status == AnimationStatus.completed) {
_breatheCycles++;
if (_breatheCycles < 3) _breatheCtrl.reverse();
} else if (status == AnimationStatus.dismissed && _breatheCycles < 3) {
_breatheCtrl.forward();
}
});
if (_hasHighSpread) _breatheCtrl.forward();
_runSequence();
}
Future<void> _runSequence() async {
// Fix 8: Skip animation sequence if reduce motion enabled.
final reduceMotion = MediaQuery.disableAnimationsOf(context);
if (reduceMotion) {
_fadeCtrl.value = 1.0;
_crossCtrl.value = 1.0;
_gridCtrl.value = 1.0;
_titleLetterCtrl.value = 1.0;
for (final c in _rowCtrls) {
  c.value = 1.0;
}
for (final c in _noiseCtrls) {
  c.value = 1.0;
}
for (final c in _waveCtrls) {
  c.value = 1.0;
}
_caliperCtrl.value = 1.0;
_focusCtrl.value = 1.0;
_framingCtrl.value = 1.0;
_footerCtrl.value = 1.0;
_gaugeCtrl.value = 1.0;
return;
}
// Fix 9: Single light haptic only.
HapticUtil.light();
// 1. Fade in.
_fadeCtrl.forward();
await _wait(_kFadeIn);
if (_disposed) return;
// 2. Ring pulse.
_ringCtrl.forward();
_titleLetterCtrl.forward();
// 3. Crosshairs emerge.
await _wait(const Duration(milliseconds: 100));
if (_disposed) return;
_crossCtrl.forward();
// 4. Grid.
await _wait(const Duration(milliseconds: 200));
if (_disposed) return;
_gridCtrl.forward();
// 5. Rows stagger.
await _wait(const Duration(milliseconds: 100));
for (int i = 0; i < _rowCtrls.length; i++) {
if (_disposed) return;
_rowCtrls[i].forward();
Timer(const Duration(milliseconds: 100), () {
if (!_disposed && mounted) _noiseCtrls[i].forward();
});
Timer(const Duration(milliseconds: 150), () {
if (!_disposed && mounted) _waveCtrls[i].forward();
});
await _wait(_kRowStagger);
}
// 6. Caliper snap.
await _wait(const Duration(milliseconds: 50));
if (_disposed) return;
_caliperCtrl.forward();
// 7. Focus ring.
await _wait(const Duration(milliseconds: 100));
if (_disposed) return;
_focusCtrl.forward();
// 8. Framing.
if (widget.comparison.framing.values.length >= 2) {
await _wait(_kFramingDelay);
if (_disposed) return;
_framingCtrl.forward();
}
// 9. Footer + gauge.
await _wait(_kFooterDelay);
if (_disposed) return;
_footerCtrl.forward();
_gaugeCtrl.forward();
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
_ringCtrl.dispose();
_crossCtrl.dispose();
_gridCtrl.dispose();
_titleLetterCtrl.dispose();
for (final c in _rowCtrls) {
  c.dispose();
}
for (final c in _noiseCtrls) {
  c.dispose();
}
for (final c in _waveCtrls) {
  c.dispose();
}
_caliperCtrl.dispose();
_focusCtrl.dispose();
_framingCtrl.dispose();
_footerCtrl.dispose();
_gaugeCtrl.dispose();
_breatheCtrl.dispose();
super.dispose();
}
@override
Widget build(BuildContext context) {
final metrics = _metrics;
if (metrics.isEmpty) return const SizedBox.shrink();
return FadeTransition(
opacity: _fadeCtrl,
child: Semantics(
label: 'Split Microscope chromatic variance analysis. '
'${metrics.length} metrics. '
'Aggregate divergence ${(_aggScore * 100).toStringAsFixed(1)} percent.',
child: Container(
width: double.infinity,
decoration: BoxDecoration(
color: BaselineColors.card,
border: Border.all(
color: BaselineColors.borderInactive.atOpacity(_kCardBorderOp),
width: _kCardBorder),
borderRadius: BorderRadius.circular(_kCardRadius),
),
child: CustomPaint(
painter: _EyepieceBgPainter(
metrics: metrics,
gridAnim: _gridCtrl,
crossAnim: _crossCtrl,
ringAnim: _ringCtrl,
),
foregroundPainter: _EyepieceFgPainter(
focusAnim: _focusCtrl,
maxSpreadIdx: _maxSpreadIdx,
rowCount: metrics.length,
),
child: Padding(
padding: const EdgeInsets.all(_kPadOuter),
child: Column(
mainAxisSize: MainAxisSize.min,
crossAxisAlignment: CrossAxisAlignment.stretch,
children: [
// Header (outside eyepiece conceptually).
_AnimW(ctrl: _fadeCtrl, child:
_Header(
onInfoTap: widget.onInfoTap ?? () =>
InfoBottomSheet.show(context,
key: 'split_microscope'),
letterAnim: _titleLetterCtrl,
metrics: metrics,
)),
const SizedBox(height: 10),
// Metric rows (inside eyepiece).
for (int i = 0; i < metrics.length; i++) ...[
if (i > 0) _RowSep(),
_AnimW(ctrl: _rowCtrls[i], slideX: true, child:
_MetricRow(
metric: metrics[i],
noiseAnim: _noiseCtrls[i],
waveAnim: _waveCtrls[i],
caliperAnim: _caliperCtrl,
breatheAnim: _breatheCtrl,
isMaxSpread: i == _maxSpreadIdx,
rowIndex: i,
)),
],
const SizedBox(height: 10),
// Prismatic index bar.
_AnimW(ctrl: _caliperCtrl, child:
_PrismaticBar(metrics: metrics)),
// Framing.
if (widget.comparison.framing.values.length >= 2) ...[
const SizedBox(height: 10),
_GradDiv(),
const SizedBox(height: 8),
_AnimW(ctrl: _framingCtrl, child:
_FramingObjective(
framing: widget.comparison.framing)),
],
// Aggregate.
const SizedBox(height: 10),
Container(height: 0.5,
color: BaselineColors.teal.atOpacity(0.06)),
const SizedBox(height: 8),
_AnimW(ctrl: _footerCtrl, child:
_AggReadout(
score: _aggScore,
metrics: metrics,
gaugeAnim: _gaugeCtrl,
)),
// Observation note.
const SizedBox(height: 8),
_AnimW(ctrl: _footerCtrl, child: Text(
'Chromatic separation indicates independent model divergence. Not an error.',
style: BaselineTypography.dataSmall.copyWith(
fontSize: _kNoteFont,
color: BaselineColors.white.atOpacity(_kNoteOp),
letterSpacing: 0.3),
)),
// Stage coordinates.
const SizedBox(height: 4),
_AnimW(ctrl: _footerCtrl, child: _StageCoords(
metrics: metrics)),
],
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
// ANIMATION WRAPPER
//
// ═══════════════════════════════════════════════════════════
class _AnimW extends StatelessWidget {
const _AnimW({
required this.ctrl, required this.child, this.slideX = false});
final AnimationController ctrl;
final Widget child;
final bool slideX; // true = slide right, false = slide up.
@override
Widget build(BuildContext context) {
final offset = slideX
? const Offset(-0.04, 0) : const Offset(0, 0.06);
return FadeTransition(
opacity: CurvedAnimation(parent: ctrl, curve: Curves.easeOut),
child: SlideTransition(
position: Tween<Offset>(begin: offset, end: Offset.zero)
.animate(CurvedAnimation(parent: ctrl, curve: Curves.easeOutCubic)),
child: child,
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
const _Header({
required this.onInfoTap,
required this.letterAnim,
required this.metrics,
});
final VoidCallback onInfoTap;
final Animation<double> letterAnim;
final List<MetricComparison> metrics;
String get _specId {
final hash = metrics.fold<int>(0, (h, m) =>
h ^ m.values.fold<int>(0, (vh, v) => vh ^ v.value.hashCode));
final hex = hash.abs().toRadixString(16).toUpperCase();
return 'SPEC-${hex.padLeft(4, '0').substring(0, 4)}';
}
@override
Widget build(BuildContext context) {
return GestureDetector(
onTap: onInfoTap,
behavior: HitTestBehavior.opaque,
child: Semantics(
button: true,
label: 'Split Microscope info. Tap for explanation.',
child: Column(
crossAxisAlignment: CrossAxisAlignment.start,
mainAxisSize: MainAxisSize.min,
children: [
Row(
crossAxisAlignment: CrossAxisAlignment.start,
children: [
Expanded(child: AnimatedBuilder(
animation: letterAnim,
builder: (_, _) => Text('SPLIT MICROSCOPE™',
style: BaselineTypography.dataSmall.copyWith(
fontSize: _kTitleFont,
color: BaselineColors.teal.atOpacity(_kTitleOp),
letterSpacing: 4.0 - (letterAnim.value * 2.0),
)),
)),
Text(_specId, style: BaselineTypography.dataSmall.copyWith(
fontSize: _kSpecIdFont,
color: BaselineColors.teal.atOpacity(_kSpecIdOp),
letterSpacing: 0.5)),
const SizedBox(width: 8),
BaselineIcon(BaselineIconType.info, size: 16,
color: BaselineColors.white.atOpacity(0.20)),
],
),
const SizedBox(height: 2),
Text('VARIANCE DECOMPOSITION · CHROMATIC ANALYSIS',
style: BaselineTypography.dataSmall.copyWith(
fontSize: _kSubFont,
color: BaselineColors.white.atOpacity(_kSubOp),
letterSpacing: 1.5)),
],
),
),
);
}
}
//
// ═══════════════════════════════════════════════════════════
// METRIC ROW
//
// ═══════════════════════════════════════════════════════════
class _MetricRow extends StatelessWidget {
const _MetricRow({
required this.metric,
required this.noiseAnim,
required this.waveAnim,
required this.caliperAnim,
required this.breatheAnim,
required this.isMaxSpread,
required this.rowIndex,
});
final MetricComparison metric;
final Animation<double> noiseAnim;
final Animation<double> waveAnim;
final Animation<double> caliperAnim;
final Animation<double> breatheAnim;
final bool isMaxSpread;
final int rowIndex;
Color _spreadColor() {
if (metric.spread > _kSpreadHigh) return BaselineColors.teal.atOpacity(0.65);
if (metric.spread > _kSpreadLow) return BaselineColors.teal.atOpacity(0.40);
return BaselineColors.white.atOpacity(0.18);
}
@override
Widget build(BuildContext context) {
return Semantics(
label: '${metric.metric.label}: spread ${metric.spread.toStringAsFixed(1)}. '
'${metric.values.map((v) => '${v.providerLabel} ${v.value.toStringAsFixed(1)}').join(', ')}',
child: SizedBox(
height: _kRowH,
child: Row(children: [
// Rotated metric label (vertical).
SizedBox(
width: 16,
child: Center(child: RotatedBox(quarterTurns: 3,
child: Text(metric.metric.label.toUpperCase(),
style: BaselineTypography.dataSmall.copyWith(
fontSize: _kLabelFont,
color: BaselineColors.white.atOpacity(_kLabelOp),
letterSpacing: 1.5)))),
),
const SizedBox(width: 4),
// Axis.
Expanded(
child: AnimatedBuilder(
animation: Listenable.merge([noiseAnim, waveAnim, caliperAnim]),
builder: (_, _) => CustomPaint(
size: Size(double.infinity, _kRowH),
painter: _SpecimenAxisPainter(
values: metric.values,
consensusAvg: metric.consensusAvg,
spread: metric.spread,
noiseReveal: noiseAnim.value,
waveReveal: waveAnim.value,
caliperScale: Curves.easeOutBack.transform(
caliperAnim.value.clamp(0, 1)),
rowIndex: rowIndex,
),
),
),
),
const SizedBox(width: 6),
// Spread readout.
SizedBox(
width: 44,
child: Column(
mainAxisAlignment: MainAxisAlignment.center,
crossAxisAlignment: CrossAxisAlignment.end,
children: [
Text('Δ ${metric.spread.toStringAsFixed(1)}',
style: BaselineTypography.dataSmall.copyWith(
fontSize: _kSpreadFont, color: _spreadColor())),
if (metric.spread > _kSpreadHigh)
AnimatedBuilder(
animation: breatheAnim,
builder: (_, _) => Container(
margin: const EdgeInsets.only(top: 2),
width: 20, height: 1,
color: BaselineColors.teal.atOpacity(
0.08 + breatheAnim.value * 0.10))),
],
),
),
]),
),
);
}
}
//
// ═══════════════════════════════════════════════════════════
// SPECIMEN AXIS PAINTER (per metric row — the core)
//
// ═══════════════════════════════════════════════════════════
class _SpecimenAxisPainter extends CustomPainter {
_SpecimenAxisPainter({
required this.values,
required this.consensusAvg,
required this.spread,
required this.noiseReveal,
required this.waveReveal,
required this.caliperScale,
required this.rowIndex,
});
final List<LensMetricValue> values;
final double? consensusAvg;
final double spread;
final double noiseReveal; // 0→1
final double waveReveal; // 0→1
final double caliperScale; // 0→1 with overshoot
final int rowIndex;
@override
void paint(Canvas canvas, Size size) {
final w = size.width, h = size.height;
final midY = h / 2;
// ── Track ──
canvas.drawLine(Offset(0, midY), Offset(w, midY),
Paint()..color = BaselineColors.white.atOpacity(_kTrackOp)
..strokeWidth = _kTrackSt);
// ── Tick marks ──
for (int i = 0; i <= 4; i++) {
final x = w * i / 4;
final major = i % 2 == 0;
canvas.drawLine(
Offset(x, midY - (major ? _kTickMajH : _kTickMinH)),
Offset(x, midY + (major ? _kTickMajH : _kTickMinH)),
Paint()..color = BaselineColors.white.atOpacity(major ? _kTickMajOp : _kTickMinOp)
..strokeWidth = 0.5);
}
// ── Signal noise ──
if (noiseReveal > 0 && spread > 2) {
canvas.save();
canvas.clipRect(Rect.fromLTWH(0, 0, w * noiseReveal, h));
final amp = (spread / 50).clamp(0.0, 1.0) * _kNoiseMaxAmp;
final nOp = 0.02 + (spread / 50).clamp(0.0, 1.0) * 0.06;
// Use highest-outlier model's hue.
final outlierIdx = _findOutlierIdx();
final noiseColor = (outlierIdx < _kHues.length
? _kHues[outlierIdx] : _kHues[0]).atOpacity(nOp);
final p = Paint()..color = noiseColor..strokeWidth = 0.5
..style = PaintingStyle.stroke;
final seed = values.fold<int>(0, (h, v) => h ^ v.value.hashCode) + rowIndex;
final rng = math.Random(seed);
final path = Path()..moveTo(0, midY);
for (double x = 1; x < w; x += 2) {
final a = amp * (0.3 + rng.nextDouble() * 0.7);
path.lineTo(x, midY + (rng.nextBool() ? a : -a));
}
canvas.drawPath(path, p);
canvas.restore();
}
if (values.isEmpty) return;
final vals = values.map((v) => v.value).toList();
final minV = vals.reduce(math.min);
final maxV = vals.reduce(math.max);
final x1 = (minV / 100) * w, x2 = (maxV / 100) * w;
final zoneW = x2 - x1;
// ── Chromatic aberration zone ── (THE MONEY TREATMENT)
if (zoneW > 1 && waveReveal > 0) {
for (int i = 0; i < values.length && i < _kHues.length; i++) {
final vx = (values[i].value / 100) * w;
// Each model gets a translucent band, shifted vertically.
final bandY = midY - _kAbH * 1.5 + i * _kAbShift;
final bandOp = (spread / 50).clamp(0.04, 0.18) * waveReveal;
final bandW = zoneW.clamp(2.0, w);
canvas.drawRect(
Rect.fromLTWH(x1, bandY, bandW * waveReveal, _kAbH),
Paint()..color = _kHues[i].atOpacity(bandOp));
// Model-specific intensity peak at its position.
canvas.drawRect(
Rect.fromLTWH(vx - 0.5, bandY, 1, _kAbH),
Paint()..color = _kHues[i].atOpacity(bandOp * 2));
}
}
// ── Interference fringes (inside zone) ──
if (zoneW > 6 && waveReveal > 0.5) {
for (double fx = x1 + 3; fx < x2; fx += 3) {
final t = (fx - x1) / zoneW;
final op = 0.02 + (math.sin(t * math.pi * 6) * 0.5 + 0.5) * 0.05;
canvas.drawLine(
Offset(fx, midY - _kCalH / 2),
Offset(fx, midY + _kCalH / 2),
Paint()..color = BaselineColors.teal.atOpacity(op * waveReveal)
..strokeWidth = 0.5);
}
}
// ── Diffraction rings (high spread only) ──
if (spread > 20 && waveReveal > 0.8) {
final cx = (x1 + x2) / 2, cy = midY;
for (int r = 1; r <= 2; r++) {
final radius = zoneW / 2 + r * 6;
canvas.drawArc(
Rect.fromCircle(center: Offset(cx, cy), radius: radius),
-0.4, 0.8, false,
Paint()..color = BaselineColors.teal.atOpacity(_kDiffOp * waveReveal)
..strokeWidth = _kDiffSt..style = PaintingStyle.stroke);
}
}
// ── Caliper brackets ──
if (caliperScale > 0 && zoneW > 2) {
canvas.save();
final cx = (x1 + x2) / 2;
canvas.translate(cx, midY);
canvas.scale(caliperScale, 1.0);
canvas.translate(-cx, -midY);
final cP = Paint()..color = BaselineColors.white.atOpacity(_kCalOp)
..strokeWidth = _kCalSt;
// Left 「
canvas.drawLine(Offset(x1, midY - _kCalH / 2), Offset(x1, midY + _kCalH / 2), cP);
canvas.drawLine(Offset(x1, midY - _kCalH / 2), Offset(x1 + 3, midY - _kCalH / 2), cP);
canvas.drawLine(Offset(x1, midY + _kCalH / 2), Offset(x1 + 3, midY + _kCalH / 2), cP);
// Right 」
canvas.drawLine(Offset(x2, midY - _kCalH / 2), Offset(x2, midY + _kCalH / 2), cP);
canvas.drawLine(Offset(x2, midY - _kCalH / 2), Offset(x2 - 3, midY - _kCalH / 2), cP);
canvas.drawLine(Offset(x2, midY + _kCalH / 2), Offset(x2 - 3, midY + _kCalH / 2), cP);
// Dashed span.
final dP = Paint()..color = BaselineColors.white.atOpacity(_kCalDashOp)..strokeWidth = 0.5;
double dx = x1 + 4;
while (dx < x2 - 4) {
canvas.drawLine(Offset(dx, midY),
Offset((dx + 4).clamp(0, x2 - 4), midY), dP);
dx += 8;
}
canvas.restore();
}
// ── Consensus marker (μ triangle) ──
if (consensusAvg != null && waveReveal > 0) {
final ax = (consensusAvg! / 100).clamp(0.0, 1.0) * w;
final tri = Path()
..moveTo(ax - _kMuTriH / 2, midY - _kCalH / 2 - 2)
..lineTo(ax + _kMuTriH / 2, midY - _kCalH / 2 - 2)
..lineTo(ax, midY - _kCalH / 2 + 1)
..close();
canvas.drawPath(tri,
Paint()..color = BaselineColors.teal.atOpacity(_kMuOp * waveReveal));
// "μ" label.
final tp = TextPainter(
text: TextSpan(text: 'μ', style: TextStyle(
fontFamily: BaselineTypography.monoFontFamily, fontSize: 5,
color: BaselineColors.teal.atOpacity(0.10 * waveReveal))),
textDirection: TextDirection.ltr)..layout();
tp.paint(canvas, Offset(ax - tp.width / 2, midY - _kCalH / 2 - tp.height - 3));
}
// ── Wavelength emission lines + model markers ──
if (waveReveal > 0) {
for (int i = 0; i < values.length && i < _kHues.length; i++) {
final v = values[i];
final mx = (v.value / 100).clamp(0.0, 1.0) * w;
final hue = _kHues[i];
final op = _kHueOps[i];
final reveal = waveReveal;
// Emission line (draws top→bottom).
final lineH = _kEmitH * reveal;
canvas.drawLine(
Offset(mx, midY - lineH / 2),
Offset(mx, midY + lineH / 2),
Paint()..color = hue.atOpacity(op * reveal)
..strokeWidth = _kEmitSt);
// Marker: GP diamond, CL serif, GR circle.
_drawMarker(canvas, i, mx, midY, hue, op * reveal);
// Value readout + code (stagger above/below).
final above = i.isEven;
final valTp = TextPainter(
text: TextSpan(text: v.value.toStringAsFixed(1),
style: TextStyle(fontFamily: BaselineTypography.monoFontFamily,
fontSize: 5, color: hue.atOpacity(op * reveal))),
textDirection: TextDirection.ltr)..layout();
final codeTp = TextPainter(
text: TextSpan(text: v.providerLabel,
style: TextStyle(fontFamily: BaselineTypography.monoFontFamily,
fontSize: 6, color: hue.atOpacity(op * reveal))),
textDirection: TextDirection.ltr)..layout();
if (above) {
codeTp.paint(canvas, Offset(mx - codeTp.width / 2,
midY - _kEmitH / 2 - codeTp.height - 2));
valTp.paint(canvas, Offset(mx - valTp.width / 2,
midY - _kEmitH / 2 - codeTp.height - valTp.height - 3));
} else {
codeTp.paint(canvas, Offset(mx - codeTp.width / 2,
midY + _kEmitH / 2 + 2));
valTp.paint(canvas, Offset(mx - valTp.width / 2,
midY + _kEmitH / 2 + codeTp.height + 3));
}
}
}
}
void _drawMarker(Canvas c, int i, double x, double y, Color hue, double op) {
switch (i) {
case 0: // GP: Diamond.
const d = 3.5;
c.drawPath(Path()
..moveTo(x, y - d)..lineTo(x + d, y)
..lineTo(x, y + d)..lineTo(x - d, y)..close(),
Paint()..color = hue.atOpacity(op));
break;
case 1: // CL: Serif bar.
c.drawLine(Offset(x, y - 4), Offset(x, y + 4),
Paint()..color = hue.atOpacity(op)..strokeWidth = 1);
c.drawLine(Offset(x - 2.5, y - 4), Offset(x + 2.5, y - 4),
Paint()..color = hue.atOpacity(op)..strokeWidth = 0.5);
c.drawLine(Offset(x - 2.5, y + 4), Offset(x + 2.5, y + 4),
Paint()..color = hue.atOpacity(op)..strokeWidth = 0.5);
break;
default: // GR: Circle with center dot.
c.drawCircle(Offset(x, y), 2.5,
Paint()..color = hue.atOpacity(op)
..style = PaintingStyle.stroke..strokeWidth = 0.8);
c.drawCircle(Offset(x, y), 0.8,
Paint()..color = hue.atOpacity(op));
break;
}
}
int _findOutlierIdx() {
if (values.length < 2) return 0;
final avg = values.fold<double>(0, (s, v) => s + v.value) / values.length;
int idx = 0; double maxDist = 0;
for (int i = 0; i < values.length; i++) {
final d = (values[i].value - avg).abs();
if (d > maxDist) { maxDist = d; idx = i; }
}
return idx;
}
@override
bool shouldRepaint(_SpecimenAxisPainter o) =>
noiseReveal != o.noiseReveal || waveReveal != o.waveReveal ||
caliperScale != o.caliperScale;
}
//
// ═══════════════════════════════════════════════════════════
// PRISMATIC INDEX BAR
//
// ═══════════════════════════════════════════════════════════
class _PrismaticBar extends StatelessWidget {
const _PrismaticBar({required this.metrics});
final List<MetricComparison> metrics;
@override
Widget build(BuildContext context) {
final totalSpread = metrics.fold<double>(0, (s, m) => s + m.spread);
if (totalSpread == 0) return const SizedBox.shrink();
return Column(
mainAxisSize: MainAxisSize.min,
children: [
SizedBox(
height: _kPrisH,
child: Row(children: [
for (int i = 0; i < metrics.length; i++) ...[
if (i > 0) SizedBox(width: _kPrisGap),
Expanded(
flex: math.max(1, (metrics[i].spread / totalSpread * 100).round()),
child: Container(
decoration: BoxDecoration(
gradient: LinearGradient(
colors: metrics[i].spread > _kSpreadLow
? [_kGPHue.atOpacity(0.12),
_kCLHue.atOpacity(0.10),
_kGRHue.atOpacity(0.08)]
: [BaselineColors.teal.atOpacity(0.06),
BaselineColors.teal.atOpacity(0.06)],
),
borderRadius: BorderRadius.circular(0.5),
),
),
),
],
]),
),
const SizedBox(height: 3),
Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
Text('CONVERGED', style: BaselineTypography.dataSmall.copyWith(
fontSize: 4, color: BaselineColors.teal.atOpacity(0.10),
letterSpacing: 1.0)),
Text('ABERRANT', style: BaselineTypography.dataSmall.copyWith(
fontSize: 4, color: BaselineColors.teal.atOpacity(0.10),
letterSpacing: 1.0)),
]),
],
);
}
}
//
// ═══════════════════════════════════════════════════════════
// FRAMING OBJECTIVE
//
// ═══════════════════════════════════════════════════════════
class _FramingObjective extends StatelessWidget {
const _FramingObjective({required this.framing});
final FramingComparison framing;
@override
Widget build(BuildContext context) {
final isSplit = framing.hasSplit;
return Semantics(
label: isSplit
? 'Framing divergence detected'
: 'Framing wavelengths aligned',
child: Container(
decoration: BoxDecoration(
border: Border(left: BorderSide(
color: isSplit
? BaselineColors.amber.atOpacity(0.30)
: BaselineColors.teal.atOpacity(0.10),
width: _kFramingBorderW)),
),
padding: const EdgeInsets.only(left: 10),
child: Column(
crossAxisAlignment: CrossAxisAlignment.start,
mainAxisSize: MainAxisSize.min,
children: [
Text(
isSplit ? 'CHROMATIC SPLIT' : 'WAVELENGTHS ALIGNED',
style: BaselineTypography.dataSmall.copyWith(
fontSize: 5,
color: isSplit
? BaselineColors.amber.atOpacity(0.25)
: BaselineColors.teal.atOpacity(0.15),
letterSpacing: 1.5)),
const SizedBox(height: 6),
for (int i = 0; i < framing.values.length && i < _kHues.length; i++)
Padding(
padding: const EdgeInsets.only(bottom: 4),
child: Row(children: [
Container(
padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
decoration: BoxDecoration(
color: _kHues[i].atOpacity(0.08),
borderRadius: BorderRadius.circular(2)),
child: Text(framing.values[i].providerLabel,
style: BaselineTypography.dataSmall.copyWith(
fontSize: 7, color: _kHues[i].atOpacity(0.35)))),
Padding(
padding: const EdgeInsets.symmetric(horizontal: 5),
child: Text('→', style: TextStyle(
fontSize: 8, color: BaselineColors.white.atOpacity(0.10)))),
Flexible(child: Text(
_shorten(framing.values[i].framing),
style: BaselineTypography.dataSmall.copyWith(
fontSize: _kFramingFont,
color: BaselineColors.white.atOpacity(0.50)),
maxLines: 1, overflow: TextOverflow.ellipsis)),
]),
),
],
),
),
);
}
String _shorten(String f) {
final slash = f.indexOf(' / ');
return slash > 0 ? f.substring(0, slash) : f;
}
}
//
// ═══════════════════════════════════════════════════════════
// AGGREGATE READOUT
//
// ═══════════════════════════════════════════════════════════
class _AggReadout extends StatelessWidget {
const _AggReadout({
required this.score,
required this.metrics,
required this.gaugeAnim,
});
final double score;
final List<MetricComparison> metrics;
final Animation<double> gaugeAnim;
String get _level {
if (score > _kAggHigh) return 'HIGH';
if (score > _kAggLow) return 'MODERATE';
return 'LOW';
}
Color get _levelColor {
if (score > _kAggHigh) return BaselineColors.amber.atOpacity(0.40);
if (score > _kAggLow) return BaselineColors.teal.atOpacity(0.50);
return BaselineColors.teal.atOpacity(0.25);
}
@override
Widget build(BuildContext context) {
final pct = (score * 100).clamp(0.0, 100.0).toStringAsFixed(1);
return Row(
crossAxisAlignment: CrossAxisAlignment.center,
children: [
// Gauge.
AnimatedBuilder(
animation: gaugeAnim,
builder: (_, _) => CustomPaint(
size: Size(_kGaugeW, _kGaugeW / 2 + 4),
painter: _GaugePainter(
fill: (score * Curves.easeOutBack.transform(
gaugeAnim.value.clamp(0, 1))).clamp(0, 1),
color: BaselineColors.teal))),
const SizedBox(width: 10),
Column(
crossAxisAlignment: CrossAxisAlignment.start,
mainAxisSize: MainAxisSize.min,
children: [
Text('$pct%', style: BaselineTypography.dataSmall.copyWith(
fontSize: _kAggPctFont,
color: BaselineColors.teal.atOpacity(_kAggPctOp))),
Text('AGGREGATE DIVERGENCE',
style: BaselineTypography.dataSmall.copyWith(
fontSize: _kAggLabelFont,
color: BaselineColors.white.atOpacity(_kAggLabelOp),
letterSpacing: 1.5)),
],
),
const Spacer(),
Column(
crossAxisAlignment: CrossAxisAlignment.end,
mainAxisSize: MainAxisSize.min,
children: [
Text('SIGNAL VARIANCE', style: BaselineTypography.dataSmall.copyWith(
fontSize: 5, color: BaselineColors.white.atOpacity(0.08),
letterSpacing: 1.0)),
const SizedBox(height: 2),
Text(_level, style: BaselineTypography.dataSmall.copyWith(
fontSize: _kClassFont, color: _levelColor,
letterSpacing: 1.0)),
const SizedBox(height: 4),
// Mini sparkline bars.
Row(
mainAxisSize: MainAxisSize.min,
crossAxisAlignment: CrossAxisAlignment.end,
children: [
for (int i = 0; i < metrics.length && i < _kHues.length; i++)
Padding(
padding: EdgeInsets.only(left: i > 0 ? _kMiniBarGap : 0),
child: Container(
width: _kMiniBarW,
height: _kMiniBarMinH + (metrics[i].spread / 50)
.clamp(0.0, 1.0) * (_kMiniBarMaxH - _kMiniBarMinH),
decoration: BoxDecoration(
color: _kHues[i].atOpacity(0.25),
borderRadius: BorderRadius.circular(0.5)))),
],
),
],
),
],
);
}
}
//
// ═══════════════════════════════════════════════════════════
// GAUGE PAINTER
//
// ═══════════════════════════════════════════════════════════
class _GaugePainter extends CustomPainter {
_GaugePainter({required this.fill, required this.color});
final double fill; final Color color;
@override
void paint(Canvas canvas, Size size) {
final ctr = Offset(size.width / 2, size.height - 2);
final r = size.width / 2 - 1;
canvas.drawArc(Rect.fromCircle(center: ctr, radius: r),
math.pi, math.pi, false,
Paint()..color = color.atOpacity(_kGaugeTrackOp)
..style = PaintingStyle.stroke..strokeWidth = 2.5);
if (fill > 0) {
canvas.drawArc(Rect.fromCircle(center: ctr, radius: r),
math.pi, math.pi * fill.clamp(0, 1), false,
Paint()..color = color.atOpacity(_kGaugeFillOp)
..style = PaintingStyle.stroke..strokeWidth = 2.5
..strokeCap = StrokeCap.round);
}
final angle = math.pi + math.pi * fill.clamp(0, 1);
canvas.drawLine(ctr, Offset(
ctr.dx + (r - 3) * math.cos(angle),
ctr.dy + (r - 3) * math.sin(angle)),
Paint()..color = color.atOpacity(_kGaugeNeedleOp)..strokeWidth = 1);
canvas.drawCircle(ctr, 1.5, Paint()..color = color.atOpacity(0.25));
final tp = TextPainter(
text: TextSpan(text: 'VARIANCE', style: TextStyle(
fontFamily: BaselineTypography.monoFontFamily, fontSize: 4,
color: color.atOpacity(0.07), letterSpacing: 0.5)),
textDirection: TextDirection.ltr)..layout();
tp.paint(canvas, Offset(ctr.dx - tp.width / 2, ctr.dy + 2));
}
@override
bool shouldRepaint(_GaugePainter o) => fill != o.fill;
}
//
// ═══════════════════════════════════════════════════════════
// STAGE COORDINATES
//
// ═══════════════════════════════════════════════════════════
class _StageCoords extends StatelessWidget {
const _StageCoords({required this.metrics});
final List<MetricComparison> metrics;
@override
Widget build(BuildContext context) {
// Find dominant metric (highest spread).
final dominant = metrics.isNotEmpty
? metrics.reduce((a, b) => a.spread > b.spread ? a : b)
: null;
final rangeStr = dominant != null
? '${dominant.values.map((v) => v.value).reduce(math.min).toStringAsFixed(0)}'
'-${dominant.values.map((v) => v.value).reduce(math.max).toStringAsFixed(0)}'
: '-';
return Row(
mainAxisAlignment: MainAxisAlignment.spaceBetween,
children: [
Text(
'X: ${dominant?.metric.label.toUpperCase() ?? '-'} '
'Y: $rangeStr',
style: BaselineTypography.dataSmall.copyWith(
fontSize: _kStageFont,
color: BaselineColors.teal.atOpacity(_kStageOp),
letterSpacing: 0.5)),
Text('×3 OBJ', style: BaselineTypography.dataSmall.copyWith(
fontSize: _kStageFont,
color: BaselineColors.teal.atOpacity(0.06),
letterSpacing: 1.0)),
],
);
}
}
//
// ═══════════════════════════════════════════════════════════
// EYEPIECE BACKGROUND PAINTER
//
// ═══════════════════════════════════════════════════════════
class _EyepieceBgPainter extends CustomPainter {
_EyepieceBgPainter({
required this.metrics,
required this.gridAnim,
required this.crossAnim,
required this.ringAnim,
}) : super(repaint: Listenable.merge([gridAnim, crossAnim, ringAnim]));
final List<MetricComparison> metrics;
final Animation<double> gridAnim;
final Animation<double> crossAnim;
final Animation<double> ringAnim;
@override
void paint(Canvas canvas, Size size) {
final cx = size.width / 2, cy = size.height / 2;
final eyeR = math.min(size.width, size.height) / 2 - _kEyeInset;
canvas.save();
canvas.clipRRect(RRect.fromRectAndRadius(
Rect.fromLTWH(0, 0, size.width, size.height),
const Radius.circular(_kCardRadius)));
// ── Vignette ──
canvas.drawCircle(Offset(cx, cy), eyeR,
Paint()..shader = RadialGradient(
colors: [Colors.transparent, BaselineColors.black.atOpacity(_kVigOp)],
stops: const [0.6, 1.0],
).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: eyeR)));
// ── Variance heatmap strips ──
if (metrics.isNotEmpty) {
final rowStart = _kPadOuter + 32 + 10; // header + gap
for (int i = 0; i < metrics.length; i++) {
final y = rowStart + i * (_kRowH + 1);
final op = (metrics[i].spread / 50).clamp(0.0, 1.0) * 0.02;
if (op > 0.001) {
canvas.drawRect(Rect.fromLTWH(0, y, size.width, _kRowH),
Paint()..color = BaselineColors.teal.atOpacity(op));
}
}
}
// ── Specimen grid ──
if (gridAnim.value > 0) {
final gP = Paint()..color = BaselineColors.white.atOpacity(
_kGridOp * gridAnim.value)..strokeWidth = _kGridSt;
for (double x = _kGridSp; x < size.width; x += _kGridSp) {
canvas.drawLine(Offset(x, 0), Offset(x, size.height), gP);
}
for (double y = _kGridSp; y < size.height; y += _kGridSp) {
canvas.drawLine(Offset(0, y), Offset(size.width, y), gP);
}
}
// ── Reticle crosshairs ──
if (crossAnim.value > 0) {
final cP = Paint()..color = BaselineColors.white.atOpacity(
_kCrossOp * crossAnim.value)..strokeWidth = _kCrossSt;
// Horizontal: draws from center outward.
final hHalf = (size.width / 2) * crossAnim.value;
canvas.drawLine(Offset(cx - hHalf, cy), Offset(cx + hHalf, cy), cP);
// Vertical: draws 50ms later feel (use value * 0.9).
final vHalf = (size.height / 2) * (crossAnim.value * 0.95).clamp(0, 1);
canvas.drawLine(Offset(cx, cy - vHalf), Offset(cx, cy + vHalf), cP);
// Center dot.
if (crossAnim.value > 0.5) {
canvas.drawCircle(Offset(cx, cy), _kCrossDotR,
Paint()..color = BaselineColors.teal.atOpacity(
_kCrossDotOp * crossAnim.value));
}
}
// ── Eyepiece ring ──
if (ringAnim.value > 0) {
// Dashed circle.
final ringPath = Path()..addOval(
Rect.fromCircle(center: Offset(cx, cy), radius: eyeR));
final metric = ringPath.computeMetrics().first;
// Stroke width pulses: 0.5 → 1.0 → 0.5
final sw = _kEyeSt + 0.5 * math.sin(ringAnim.value * math.pi);
// Opacity pulses: 0.04 → 0.15 → 0.04
final rop = _kEyeOp + 0.11 * math.sin(ringAnim.value * math.pi);
final rP = Paint()..color = BaselineColors.teal.atOpacity(rop)
..strokeWidth = sw..style = PaintingStyle.stroke;
double dist = 0;
while (dist < metric.length) {
final end = (dist + _kEyeDash).clamp(0.0, metric.length);
canvas.drawPath(metric.extractPath(dist, end), rP);
dist += _kEyeDash + _kEyeGap;
}
// Magnification label inside eyepiece top-left.
if (ringAnim.value > 0.5) {
final tp = TextPainter(
text: TextSpan(text: '×3', style: TextStyle(
fontFamily: BaselineTypography.monoFontFamily, fontSize: _kMagFont,
color: BaselineColors.teal.atOpacity(_kMagOp))),
textDirection: TextDirection.ltr)..layout();
tp.paint(canvas, Offset(_kPadOuter + 4, _kPadOuter + 4));
final objTp = TextPainter(
text: TextSpan(text: 'OBJ', style: TextStyle(
fontFamily: BaselineTypography.monoFontFamily, fontSize: 4,
color: BaselineColors.teal.atOpacity(0.04))),
textDirection: TextDirection.ltr)..layout();
objTp.paint(canvas, Offset(_kPadOuter + 4, _kPadOuter + 4 + tp.height));
}
// ── Grid labels 0/25/50/75/100 along bottom ──
if (gridAnim.value > 0.5) {
for (int i = 0; i <= 4; i++) {
final x = _kPadOuter + 20 + (size.width - _kPadOuter * 2 - 40) * i / 4;
final tp = TextPainter(
text: TextSpan(text: '${i * 25}', style: TextStyle(
fontFamily: BaselineTypography.monoFontFamily, fontSize: _kGridLabelFont,
color: BaselineColors.white.atOpacity(_kGridLabelOp * gridAnim.value))),
textDirection: TextDirection.ltr)..layout();
tp.paint(canvas, Offset(x - tp.width / 2, size.height - _kPadOuter - tp.height));
}
}
}
canvas.restore();
}
@override
bool shouldRepaint(covariant _EyepieceBgPainter old) => false;
}
//
// ═══════════════════════════════════════════════════════════
// EYEPIECE FOREGROUND PAINTER (focus ring)
//
// ═══════════════════════════════════════════════════════════
class _EyepieceFgPainter extends CustomPainter {
_EyepieceFgPainter({
required this.focusAnim,
required this.maxSpreadIdx,
required this.rowCount,
}) : super(repaint: focusAnim);
final Animation<double> focusAnim;
final int maxSpreadIdx;
final int rowCount;
@override
void paint(Canvas canvas, Size size) {
if (focusAnim.value <= 0 || rowCount == 0) return;
// Estimate row position.
final rowTop = _kPadOuter + 32 + 10 + maxSpreadIdx * (_kRowH + 1);
final rowMidY = rowTop + _kRowH / 2;
final cx = size.width / 2;
canvas.save();
final scale = 0.85 + focusAnim.value * 0.15;
canvas.translate(cx, rowMidY);
canvas.scale(scale);
// Dashed ellipse.
final ellipse = Rect.fromCenter(
center: Offset.zero, width: size.width * 0.65, height: _kRowH * 0.9);
final path = Path()..addOval(ellipse);
final metric = path.computeMetrics().first;
final dashP = Paint()
..color = BaselineColors.teal.atOpacity(0.05 * focusAnim.value)
..strokeWidth = 0.5..style = PaintingStyle.stroke;
double dist = 0;
while (dist < metric.length) {
final end = (dist + 5).clamp(0.0, metric.length);
canvas.drawPath(metric.extractPath(dist, end), dashP);
dist += 10;
}
// "FOCUS" label.
final tp = TextPainter(
text: TextSpan(text: 'FOCUS', style: TextStyle(
fontFamily: BaselineTypography.monoFontFamily, fontSize: 4,
color: BaselineColors.teal.atOpacity(0.04 * focusAnim.value),
letterSpacing: 1.0)),
textDirection: TextDirection.ltr)..layout();
tp.paint(canvas, Offset(-tp.width / 2, -ellipse.height / 2 - tp.height - 2));
canvas.restore();
}
@override
bool shouldRepaint(covariant _EyepieceFgPainter old) => false;
}
//
// ═══════════════════════════════════════════════════════════
// HELPERS
//
// ═══════════════════════════════════════════════════════════
class _RowSep extends StatelessWidget {
@override
Widget build(BuildContext c) => Container(
height: 0.5, color: BaselineColors.white.atOpacity(_kRowSepOp));
}
class _GradDiv extends StatelessWidget {
@override
Widget build(BuildContext c) => Container(height: 1,
decoration: BoxDecoration(gradient: LinearGradient(
colors: [Colors.transparent,
BaselineColors.teal.atOpacity(0.12),
BaselineColors.teal.atOpacity(0.12),
Colors.transparent],
stops: const [0, 0.3, 0.7, 1])));
}
