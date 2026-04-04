/// A-11 — Drift League Table
/// Path: lib/widgets/drift_league_table.dart
///
/// Provisions classified into tier bands (Very High → High → Moderate → Low).
/// Default view for Provision Drift™ in F4.12 Bill Overview.
/// Toggles with A-10 Drift Cascade Waterfall.
///
/// Depends on: F1.1/F1.11.9 (theme), F1.10 (constants), F2.18 (InfoBottomSheet),
/// P4 (BillSummary, Provision, ProvisionCategory), haptic_util
/// Consumed by: F4.12 (Vote Record — Bill Overview section)
/// Gated by: F6.3 driftLeagueTable (Pro+)
library;
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:baseline_app/widgets/baseline_icons.dart';
import 'package:baseline_app/config/baseline_colors.dart';
import 'package:baseline_app/config/baseline_spacing.dart';
import 'package:baseline_app/config/baseline_typography.dart';
import 'package:baseline_app/models/bill_summary.dart';
import 'package:baseline_app/widgets/info_bottom_sheet.dart';
import 'package:baseline_app/utils/haptic_util.dart';
import 'package:baseline_app/config/theme.dart';
//
// ═══════════════════════════════════════════════════════════
// CONSTANTS
//
// ═══════════════════════════════════════════════════════════
const double _kPad = 16;
const double _kRowMinH = 46;
const double _kBarH = 3;
const double _kBarW = 48.0;
const double _kBarTrackOp = 0.02;
const double _kPopBarH = 3;
const double _kDistBarH = 6;
const double _kReticleLen = 10;
const double _kReticleTick = 3;
const double _kGridH = 24;
const double _kGridV = 40;
const double _kClassStripeW = 2;
const double _kFingerprintDotR = 1.2;
const Duration _kScanDur = Duration(milliseconds: 800);
const Duration _kTitleDur = Duration(milliseconds: 400);
const Duration _kCursorBlink = Duration(milliseconds: 530);
const Duration _kExpandDur = Duration(milliseconds: 200);
const Duration _kRedactDur = Duration(milliseconds: 180);
/// Per-row stagger during cascade.
const int _kRowStaggerMs = 35;
/// Extra gap between band sections during cascade.
const int _kBandStaggerMs = 120;
/// Band display order: highest drift first.
const _kBandOrder = ['Very High', 'High', 'Moderate', 'Low'];
/// Band seal watermark text.
const _kBandSealText = {
'Very High': 'RESTRICTED',
'High': 'ELEVATED',
'Moderate': 'MODERATE',
'Low': 'NOMINAL',
};
//
// ═══════════════════════════════════════════════════════════
// COLOR + LABEL HELPERS (A-10 doctrine — shared)
//
// ═══════════════════════════════════════════════════════════
Color _driftColor(double? score, {double baseOp = 1.0}) {
final s = score ?? 0;
double op;
if (s > 0.75) {
op = 0.65;
} else if (s > 0.50) {
op = 0.50;
} else if (s > 0.25) {
op = 0.35;
} else {
op = 0.20;
}
return BaselineColors.teal.atOpacity((op * baseOp).clamp(0.0, 1.0));
}
Color _pillColor(String? label) {
if (label == 'Very High') return BaselineColors.amber.atOpacity(0.40);
return _driftColor(_labelToScore(label));
}
Color _pillTextColor(String? label) {
if (label == 'Very High') return BaselineColors.amber.atOpacity(0.85);
return _driftColor(_labelToScore(label), baseOp: 1.6);
}
double _labelToScore(String? label) {
switch (label) {
case 'Very High':
return 0.80;
case 'High':
return 0.60;
case 'Moderate':
return 0.40;
default:
return 0.15;
}
}
String _bandShort(String label) {
switch (label) {
case 'Very High':
return 'V.HIGH';
case 'Moderate':
return 'MOD';
default:
return label.toUpperCase();
}
}
int _severityDots(String label) {
switch (label) {
case 'Very High':
return 4;
case 'High':
return 3;
case 'Moderate':
return 2;
default:
return 1;
}
}
String _catIcon(ProvisionCategory cat) {
switch (cat) {
case ProvisionCategory.standaloneProvision:
return '▪';
case ProvisionCategory.amendment:
return '△';
case ProvisionCategory.earmark:
return '◆';
case ProvisionCategory.rider:
return '○';
}
}
Color _bandLabelColor(String label) {
if (label == 'Very High') {
return BaselineColors.amber.atOpacity(0.70);
}
return _driftColor(_labelToScore(label), baseOp: 1.4);
}
/// Generates a 5-dot fingerprint pattern from a hash code.
/// Returns list of 5 vertical offsets (0.0–1.0) for dot placement.
List<double> _fingerprint(int hashCode) {
final rng = math.Random(hashCode.abs());
return List.generate(5, (_) => rng.nextDouble());
}
//
// ═══════════════════════════════════════════════════════════
// DATA CLASSES
//
// ═══════════════════════════════════════════════════════════
class _Band {
final String label;
final List<Provision> provisions;
final double avgDrift;
final double minDrift;
final double maxDrift;
const _Band({
required this.label,
required this.provisions,
required this.avgDrift,
required this.minDrift,
required this.maxDrift,
});
}
enum _EntryKind { bandHeader, row }
class _Entry {
final _EntryKind kind;
final _Band? band;
final Provision? provision;
final int rankInBand;
const _Entry.header(this.band)
: kind = _EntryKind.bandHeader,
provision = null,
rankInBand = 0;
const _Entry.row({required this.provision, required this.rankInBand})
: kind = _EntryKind.row,
band = null;
}
//
// ═══════════════════════════════════════════════════════════
// MAIN WIDGET
//
// ═══════════════════════════════════════════════════════════
class DriftLeagueTable extends StatefulWidget {
const DriftLeagueTable({
super.key,
required this.summary,
this.onInfoTap,
});
final BillSummary summary;
final VoidCallback? onInfoTap;
@override
State<DriftLeagueTable> createState() => _DriftLeagueTableState();
}
class _DriftLeagueTableState extends State<DriftLeagueTable>
with TickerProviderStateMixin {
late final AnimationController _scanCtrl;
late final AnimationController _titleCtrl;
late final AnimationController _cursorCtrl;
late final AnimationController _rowsCtrl;
late List<_Band> _bands;
late List<_Entry> _entries;
late List<Interval> _rowIntervals;
late double _rowsTotalDur;
int _expandedIdx = -1;
bool _reduceMotion = false;
bool _disposed = false;
bool _titleComplete = false;
@override
void initState() {
super.initState();
_buildData();
_computeIntervals();
_scanCtrl = AnimationController(vsync: this, duration: _kScanDur);
_titleCtrl = AnimationController(vsync: this, duration: _kTitleDur)
..addStatusListener(_onTitleStatus);
// Bounded repeat: ~20 blinks covers the title duration + buffer.
_cursorCtrl = AnimationController(
vsync: this,
duration: _kCursorBlink,
)..repeat(reverse: true, count: 20);
_rowsCtrl = AnimationController(
vsync: this,
duration: Duration(milliseconds: _rowsTotalDur.ceil()),
);
}
void _computeIntervals() {
// Calculate total cascade duration and per-entry intervals.
// Each band header after the first adds _kBandStaggerMs.
// Each row adds _kRowStaggerMs. Each entry's anim is 280ms.
const entryDurMs = 280;
double offsetMs = 0;
_rowIntervals = [];
for (int i = 0; i < _entries.length; i++) {
final entry = _entries[i];
if (entry.kind == _EntryKind.bandHeader && i > 0) {
offsetMs += _kBandStaggerMs;
}
_rowIntervals.add(Interval(0, 1)); // placeholder, computed below
offsetMs += entry.kind == _EntryKind.row ? _kRowStaggerMs : 0;
}
_rowsTotalDur = offsetMs + entryDurMs; // total = last start + anim
if (_rowsTotalDur <= 0) _rowsTotalDur = 1;
// Recompute proper intervals now that we know total.
offsetMs = 0;
for (int i = 0; i < _entries.length; i++) {
final entry = _entries[i];
if (entry.kind == _EntryKind.bandHeader && i > 0) {
offsetMs += _kBandStaggerMs;
}
final startFrac = offsetMs / _rowsTotalDur;
final endFrac =
(offsetMs + entryDurMs) / _rowsTotalDur;
_rowIntervals[i] = Interval(
startFrac.clamp(0.0, 1.0),
endFrac.clamp(0.0, 1.0),
curve: Curves.easeOut,
);
if (entry.kind == _EntryKind.row) {
offsetMs += _kRowStaggerMs;
}
}
}
void _onTitleStatus(AnimationStatus status) {
if (status == AnimationStatus.completed && mounted) {
setState(() => _titleComplete = true);
_cursorCtrl.stop();
}
}
@override
void didChangeDependencies() {
super.didChangeDependencies();
_reduceMotion = MediaQuery.disableAnimationsOf(context);
if (_reduceMotion) {
_scanCtrl.value = 1;
_titleCtrl.value = 1;
_titleComplete = true;
_cursorCtrl.stop();
_rowsCtrl.value = 1;
} else if (_scanCtrl.status == AnimationStatus.dismissed) {
_startCascade();
}
}
void _buildData() {
final grouped = <String, List<Provision>>{};
for (final p in widget.summary.provisions) {
final label = p.driftLabel ?? 'Low';
grouped.putIfAbsent(label, () => []).add(p);
}
for (final list in grouped.values) {
list.sort(
(a, b) => (b.driftScore ?? 0).compareTo(a.driftScore ?? 0));
}
_bands = [];
for (final label in _kBandOrder) {
final provs = grouped[label];
if (provs == null || provs.isEmpty) continue;
final scores =
provs.map((p) => p.driftScore ?? 0).toList();
final avg =
scores.fold<double>(0, (s, v) => s + v) / scores.length;
_bands.add(_Band(
label: label,
provisions: provs,
avgDrift: avg,
minDrift: scores.reduce(math.min),
maxDrift: scores.reduce(math.max),
));
}
_entries = [];
for (final band in _bands) {
_entries.add(_Entry.header(band));
for (int i = 0; i < band.provisions.length; i++) {
_entries.add(_Entry.row(
provision: band.provisions[i],
rankInBand: i + 1,
));
}
}
}
Future<void> _startCascade() async {
if (_disposed) return;
_scanCtrl.forward();
await Future<void>.delayed(const Duration(milliseconds: 200));
if (_disposed) return;
_titleCtrl.forward();
await Future<void>.delayed(const Duration(milliseconds: 400));
if (_disposed) return;
_rowsCtrl.forward();
}
@override
void dispose() {
_disposed = true;
_titleCtrl.removeStatusListener(_onTitleStatus);
_scanCtrl.dispose();
_titleCtrl.dispose();
_cursorCtrl.dispose();
_rowsCtrl.dispose();
super.dispose();
}
void _onRowTap(int flatIdx) {
HapticUtil.light();
setState(() {
_expandedIdx = _expandedIdx == flatIdx ? -1 : flatIdx;
});
}
@override
Widget build(BuildContext context) {
final totalCount = widget.summary.provisions.length;
if (totalCount == 0) return const SizedBox.shrink();
return Semantics(
label: 'Provision Drift league table. '
'$totalCount provisions classified into drift bands.',
child: CustomPaint(
painter: _ChromePainter(color: BaselineColors.teal),
foregroundPainter: _ScanPainter(
animation: _scanCtrl,
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
titleAnim: _titleCtrl,
cursorAnim: _cursorCtrl,
titleComplete: _titleComplete,
entryCount: totalCount,
reduceMotion: _reduceMotion,
onInfoTap: widget.onInfoTap ??
() => InfoBottomSheet.show(context,
key: 'provision_drift'),
),
const SizedBox(height: 14),
for (int i = 0; i < _entries.length; i++)
_AnimW(
masterCtrl: _rowsCtrl,
interval: _rowIntervals[i],
isRow: _entries[i].kind == _EntryKind.row,
child: _entries[i].kind == _EntryKind.bandHeader
? _BandHeaderRow(
band: _entries[i].band!,
totalProvisions: totalCount,
isFirst: i == 0,
)
: _ProvisionRow(
provision: _entries[i].provision!,
rank: _entries[i].rankInBand,
isExpanded: _expandedIdx == i,
onTap: () => _onRowTap(i),
isLast: i == _entries.length - 1 ||
_entries[i + 1].kind ==
_EntryKind.bandHeader,
),
),
const SizedBox(height: 16),
_DistributionFooter(
bands: _bands,
totalCount: totalCount,
avgDrift: widget.summary.avgDriftScore,
),
const SizedBox(height: 10),
_Disclaimer(),
],
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
const _Header({
required this.summary,
required this.titleAnim,
required this.cursorAnim,
required this.titleComplete,
required this.entryCount,
required this.reduceMotion,
required this.onInfoTap,
});
final BillSummary summary;
final AnimationController titleAnim;
final AnimationController cursorAnim;
final bool titleComplete;
final int entryCount;
final bool reduceMotion;
final VoidCallback onInfoTap;
@override
Widget build(BuildContext context) {
return Column(
mainAxisSize: MainAxisSize.min,
crossAxisAlignment: CrossAxisAlignment.start,
children: [
// Title row with cursor.
Row(
children: [
Expanded(
child: AnimatedBuilder(
animation: titleAnim,
builder: (_, _) {
const title = 'PROVISION DRIFT™';
final len = (titleAnim.value * title.length)
.floor()
.clamp(0, title.length);
return Row(
mainAxisSize: MainAxisSize.min,
children: [
Text(
title.substring(0, len),
style: BaselineTypography.jbMono.copyWith(
fontSize: 9,
color: BaselineColors.teal.atOpacity(0.40),
letterSpacing: 2.5,
),
),
if (!titleComplete && !reduceMotion)
AnimatedBuilder(
animation: cursorAnim,
builder: (_, _) => Container(
width: 1,
height: 10,
margin: const EdgeInsets.only(left: 1),
color: BaselineColors.teal
.atOpacity(0.30 * cursorAnim.value),
),
),
],
);
},
),
),
GestureDetector(
onTap: () {
HapticUtil.selection();
onInfoTap();
},
behavior: HitTestBehavior.opaque,
child: Padding(
padding: const EdgeInsets.all(8),
child: BaselineIcon(
BaselineIconType.info,
size: 16,
color: BaselineColors.white.atOpacity(0.20),
),
),
),
],
),
const SizedBox(height: 2),
// Subtitle + stats.
Row(
children: [
Text(
'LEAGUE TABLE',
style: BaselineTypography.jbMono.copyWith(
fontSize: 7,
color: BaselineColors.white.atOpacity(0.15),
letterSpacing: 3,
),
),
const Spacer(),
Text(
'$entryCount CLASSIFIED',
style: BaselineTypography.jbMono.copyWith(
fontSize: 8,
color: BaselineColors.teal.atOpacity(0.25),
letterSpacing: 1,
),
),
const SizedBox(width: 10),
Text(
'μ ${((summary.avgDriftScore ?? 0) * 100).toStringAsFixed(0)}%',
style: BaselineTypography.jbMono.copyWith(
fontSize: 7,
color: _driftColor(summary.avgDriftScore),
),
),
],
),
const SizedBox(height: 8),
// Stated purpose anchor.
if (summary.statedPurpose.isNotEmpty) ...[
Row(
crossAxisAlignment: CrossAxisAlignment.start,
children: [
Padding(
padding: const EdgeInsets.only(top: 1),
child: Text(
'ANCHOR:',
style: BaselineTypography.jbMono.copyWith(
fontSize: 5,
color: BaselineColors.teal.atOpacity(0.10),
letterSpacing: 1,
),
),
),
const SizedBox(width: 4),
Expanded(
child: Text(
summary.statedPurpose,
maxLines: 2,
overflow: TextOverflow.ellipsis,
style: BaselineTypography.poppins.copyWith(
fontSize: 11,
color: BaselineColors.white.atOpacity(0.25),
height: 1.35,
),
),
),
],
),
const SizedBox(height: 4),
// Classification timestamp.
Align(
alignment: Alignment.centerRight,
child: Text(
'FILED: ${_formatDate(summary.createdAt)}',
style: BaselineTypography.jbMono.copyWith(
fontSize: 5,
color: BaselineColors.teal.atOpacity(0.08),
letterSpacing: 1,
),
),
),
const SizedBox(height: 6),
],
_GradRule(),
],
);
}
static String _formatDate(DateTime dt) {
return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-'
'${dt.day.toString().padLeft(2, '0')}';
}
}
//
// ═══════════════════════════════════════════════════════════
// BAND HEADER ROW
//
// ═══════════════════════════════════════════════════════════
class _BandHeaderRow extends StatelessWidget {
const _BandHeaderRow({
required this.band,
required this.totalProvisions,
required this.isFirst,
});
final _Band band;
final int totalProvisions;
final bool isFirst;
@override
Widget build(BuildContext context) {
final short = _bandShort(band.label);
final dots = _severityDots(band.label);
final labelColor = _bandLabelColor(band.label);
final proportion = totalProvisions > 0
? band.provisions.length / totalProvisions
: 0.0;
final sealText = _kBandSealText[band.label] ?? '';
return Semantics(
label: '${band.label} drift band. '
'${band.provisions.length} provisions. '
'Average drift ${(band.avgDrift * 100).toStringAsFixed(0)} percent.',
child: Padding(
padding: EdgeInsets.only(top: isFirst ? 0 : 14, bottom: 6),
child: Stack(
children: [
// Classification stripe — left edge.
Positioned(
left: 0,
top: 0,
bottom: 0,
width: _kClassStripeW,
child: Container(
decoration: BoxDecoration(
color: labelColor.atOpacity(0.60),
borderRadius: BorderRadius.circular(1),
),
),
),
// Band seal watermark.
Positioned(
top: 2,
right: 0,
child: Transform.rotate(
angle: -0.05,
child: Text(
sealText,
style: BaselineTypography.jbMono.copyWith(
fontSize: 4,
color: labelColor.atOpacity(0.06),
letterSpacing: 3,
),
),
),
),
// Main content.
Padding(
padding: const EdgeInsets.only(left: 8),
child: Column(
mainAxisSize: MainAxisSize.min,
crossAxisAlignment: CrossAxisAlignment.stretch,
children: [
if (!isFirst) ...[
_DashRule(color: labelColor.atOpacity(0.25)),
const SizedBox(height: 8),
],
Row(
children: [
for (int d = 0; d < dots; d++)
Padding(
padding: const EdgeInsets.only(right: 2),
child: Container(
width: 3,
height: 3,
decoration: BoxDecoration(
shape: BoxShape.circle,
color: labelColor,
),
),
),
const SizedBox(width: 4),
Text(
short,
style: BaselineTypography.jbMono.copyWith(
fontSize: 8,
color: labelColor,
letterSpacing: 2,
fontWeight: FontWeight.w600,
),
),
const SizedBox(width: 8),
Text(
'×${band.provisions.length}',
style: BaselineTypography.jbMono.copyWith(
fontSize: 7,
color: BaselineColors.white.atOpacity(0.15),
),
),
const Spacer(),
Text(
'μ ${(band.avgDrift * 100).toStringAsFixed(0)}%',
style: BaselineTypography.jbMono.copyWith(
fontSize: 7,
color: _driftColor(band.avgDrift),
),
),
],
),
const SizedBox(height: 4),
// Population bar.
LayoutBuilder(
builder: (context, constraints) {
final barW = constraints.maxWidth;
return Stack(
children: [
Container(
width: barW,
height: _kPopBarH,
color: BaselineColors.white.atOpacity(_kBarTrackOp),
),
Container(
width: barW * proportion.clamp(0.0, 1.0),
height: _kPopBarH,
decoration: BoxDecoration(
color: labelColor.atOpacity(0.30),
borderRadius:
const BorderRadius.horizontal(
right: Radius.circular(1),
),
),
),
],
);
},
),
const SizedBox(height: 2),
// Band range micro-label.
Text(
'RANGE: ${(band.minDrift * 100).toStringAsFixed(0)}–'
'${(band.maxDrift * 100).toStringAsFixed(0)}%',
style: BaselineTypography.jbMono.copyWith(
fontSize: 5,
color: BaselineColors.white.atOpacity(0.08),
letterSpacing: 0.5,
),
),
],
),
),
],
),
),
);
}
}
//
// ═══════════════════════════════════════════════════════════
// PROVISION ROW (expandable, with press scale + fingerprint)
//
// ═══════════════════════════════════════════════════════════
class _ProvisionRow extends StatefulWidget {
const _ProvisionRow({
required this.provision,
required this.rank,
required this.isExpanded,
required this.onTap,
required this.isLast,
});
final Provision provision;
final int rank;
final bool isExpanded;
final VoidCallback onTap;
final bool isLast;
@override
State<_ProvisionRow> createState() => _ProvisionRowState();
}
class _ProvisionRowState extends State<_ProvisionRow>
with SingleTickerProviderStateMixin {
late final AnimationController _pressCtrl;
late final Animation<double> _scaleAnim;
@override
void initState() {
super.initState();
_pressCtrl = AnimationController(
vsync: this,
duration: const Duration(milliseconds: 80),
reverseDuration: const Duration(milliseconds: 120),
);
_scaleAnim = Tween<double>(begin: 1.0, end: 0.98).animate(
CurvedAnimation(parent: _pressCtrl, curve: Curves.easeOut),
);
}
@override
void dispose() {
_pressCtrl.dispose();
super.dispose();
}
@override
Widget build(BuildContext context) {
final score = widget.provision.driftScore ?? 0;
final label = widget.provision.driftLabel ?? 'Low';
final rowGlow = _driftColor(score, baseOp: 0.04);
final fp = _fingerprint(widget.provision.title.hashCode);
return Semantics(
label: 'Rank ${widget.rank}. ${widget.provision.title}. '
'Drift ${(score * 100).toStringAsFixed(0)} percent. $label.',
child: Column(
mainAxisSize: MainAxisSize.min,
children: [
GestureDetector(
onTapDown: (_) => _pressCtrl.forward(),
onTapUp: (_) {
_pressCtrl.reverse();
widget.onTap();
},
onTapCancel: () => _pressCtrl.reverse(),
behavior: HitTestBehavior.opaque,
child: ScaleTransition(
scale: _scaleAnim,
child: Container(
constraints: const BoxConstraints(minHeight: _kRowMinH),
decoration: BoxDecoration(color: rowGlow),
padding: const EdgeInsets.symmetric(
horizontal: 4,
vertical: 8,
),
child: Row(
children: [
// Rank index.
SizedBox(
width: 18,
child: Text(
widget.rank.toString().padLeft(2, '0'),
style: BaselineTypography.jbMono.copyWith(
fontSize: 7,
color: BaselineColors.teal.atOpacity(0.15),
),
),
),
// Data fingerprint.
SizedBox(
width: 10,
height: 14,
child: CustomPaint(
painter: _FingerprintPainter(
offsets: fp,
color:
BaselineColors.teal.atOpacity(0.06),
),
),
),
const SizedBox(width: 2),
// Category icon.
SizedBox(
width: 12,
child: Text(
_catIcon(widget.provision.category),
style: BaselineTypography.jbMono.copyWith(
fontSize: 8,
color: _driftColor(score, baseOp: 0.8),
),
),
),
// Title.
Expanded(
flex: 3,
child: Text(
widget.provision.title,
maxLines: 1,
overflow: TextOverflow.ellipsis,
style: BaselineTypography.poppins.copyWith(
fontSize: 12,
color: BaselineColors.white.atOpacity(0.60),
height: 1.2,
),
),
),
const SizedBox(width: 6),
// Inline drift bar with hashmarks.
SizedBox(
width: _kBarW,
child: CustomPaint(
size: Size(_kBarW, _kBarH),
painter: _HashBarPainter(
score: score,
barColor: _driftColor(score),
trackColor:
BaselineColors.white.atOpacity(_kBarTrackOp),
hashColor:
BaselineColors.teal.atOpacity(0.04),
),
),
),
const SizedBox(width: 6),
// Score (0 decimal — glance).
SizedBox(
width: 28,
child: Text(
'${(score * 100).toStringAsFixed(0)}%',
textAlign: TextAlign.right,
style: BaselineTypography.jbMono.copyWith(
fontSize: 8,
color: _driftColor(score),
),
),
),
const SizedBox(width: 6),
// Drift pill.
Container(
padding: const EdgeInsets.symmetric(
horizontal: 5,
vertical: 1,
),
decoration: BoxDecoration(
border: Border.all(
color: _pillColor(label),
width: 1,
),
borderRadius: BorderRadius.circular(3),
),
child: Text(
_bandShort(label),
style: BaselineTypography.jbMono.copyWith(
fontSize: 6,
color: _pillTextColor(label),
letterSpacing: 0.5,
),
),
),
const SizedBox(width: 4),
// Expand chevron.
AnimatedRotation(
turns: widget.isExpanded ? 0.75 : 0.25,
duration: _kExpandDur,
child: BaselineIcon(
BaselineIconType.chevronRight,
size: 16,
color: BaselineColors.white.atOpacity(0.15),
),
),
],
),
),
),
),
// Expanded detail.
AnimatedSize(
duration: _kExpandDur,
curve: Curves.easeOutCubic,
alignment: Alignment.topCenter,
child: widget.isExpanded
? _ExpandedDetail(provision: widget.provision)
: const SizedBox.shrink(),
),
// Row separator.
if (!widget.isLast)
Container(
height: 0.5,
color: BaselineColors.white.atOpacity(0.03),
),
],
),
);
}
}
//
// ═══════════════════════════════════════════════════════════
// EXPANDED DETAIL (with redaction lift + focus border)
//
// ═══════════════════════════════════════════════════════════
class _ExpandedDetail extends StatefulWidget {
const _ExpandedDetail({required this.provision});
final Provision provision;
@override
State<_ExpandedDetail> createState() => _ExpandedDetailState();
}
class _ExpandedDetailState extends State<_ExpandedDetail>
with SingleTickerProviderStateMixin {
late final AnimationController _redactCtrl;
bool _reduceMotion = false;
@override
void initState() {
super.initState();
_redactCtrl = AnimationController(
vsync: this,
duration: _kRedactDur,
);
}
@override
void didChangeDependencies() {
super.didChangeDependencies();
_reduceMotion = MediaQuery.disableAnimationsOf(context);
if (_reduceMotion) {
_redactCtrl.value = 1;
} else if (_redactCtrl.status == AnimationStatus.dismissed) {
_redactCtrl.forward();
}
}
@override
void dispose() {
_redactCtrl.dispose();
super.dispose();
}
@override
Widget build(BuildContext context) {
final score = widget.provision.driftScore ?? 0;
return Container(
decoration: BoxDecoration(
color: _driftColor(score, baseOp: 0.02),
border: Border(
left: BorderSide(
color: BaselineColors.teal.atOpacity(0.08),
width: 1,
),
),
),
padding: const EdgeInsets.fromLTRB(38, 4, 8, 12),
child: Column(
mainAxisSize: MainAxisSize.min,
crossAxisAlignment: CrossAxisAlignment.start,
children: [
// Description with redaction lift.
if (widget.provision.description.isNotEmpty)
Padding(
padding: const EdgeInsets.only(bottom: 8),
child: Stack(
children: [
Text(
widget.provision.description,
maxLines: 3,
overflow: TextOverflow.ellipsis,
style: BaselineTypography.poppins.copyWith(
fontSize: 11,
color: BaselineColors.white.atOpacity(0.35),
height: 1.4,
),
),
if (!_reduceMotion)
AnimatedBuilder(
animation: _redactCtrl,
builder: (_, _) {
final op =
(1 - _redactCtrl.value).clamp(0.0, 1.0);
if (op <= 0) return const SizedBox.shrink();
return Positioned.fill(
child: Column(
mainAxisAlignment:
MainAxisAlignment.spaceEvenly,
children: List.generate(
3,
(_) => Container(
height: 10,
decoration: BoxDecoration(
color: BaselineColors.white
.atOpacity(0.05 * op),
borderRadius:
BorderRadius.circular(1),
),
),
),
),
);
},
),
],
),
),
// Category pill + full drift bar.
Row(
children: [
Container(
padding: const EdgeInsets.symmetric(
horizontal: 6,
vertical: 2,
),
decoration: BoxDecoration(
color: BaselineColors.teal.atOpacity(0.06),
borderRadius: BorderRadius.circular(3),
),
child: Text(
widget.provision.category.label.toUpperCase(),
style: BaselineTypography.jbMono.copyWith(
fontSize: 7,
color: BaselineColors.teal.atOpacity(0.30),
letterSpacing: 1,
),
),
),
const SizedBox(width: 10),
Expanded(
child: LayoutBuilder(
builder: (_, constraints) {
final w = constraints.maxWidth;
return Stack(
clipBehavior: Clip.none,
children: [
CustomPaint(
size: Size(w, 4),
painter: _HashBarPainter(
score: score,
barColor: _driftColor(score),
trackColor:
BaselineColors.white.atOpacity(_kBarTrackOp),
hashColor:
BaselineColors.teal.atOpacity(0.04),
barHeight: 4,
roundRadius: 2,
),
),
// Score at tip (1 decimal — detail precision).
Positioned(
left: (w * score.clamp(0.0, 1.0)) + 4,
top: -3,
child: Text(
'${(score * 100).toStringAsFixed(1)}%',
style: BaselineTypography.jbMono.copyWith(
fontSize: 7,
color: _driftColor(score),
),
),
),
],
);
},
),
),
],
),
],
),
);
}
}
//
// ═══════════════════════════════════════════════════════════
// DISTRIBUTION FOOTER
//
// ═══════════════════════════════════════════════════════════
class _DistributionFooter extends StatelessWidget {
const _DistributionFooter({
required this.bands,
required this.totalCount,
required this.avgDrift,
});
final List<_Band> bands;
final int totalCount;
final double? avgDrift;
@override
Widget build(BuildContext context) {
if (totalCount == 0) return const SizedBox.shrink();
// Build lookup map once (fixes firstOrNull dependency).
final bandMap = <String, _Band>{};
for (final b in bands) {
bandMap[b.label] = b;
}
// Build segments in reading order: Low on left → V.High on right.
final segments = <_DistSegment>[];
for (final label in _kBandOrder.reversed) {
final band = bandMap[label];
final count = band?.provisions.length ?? 0;
segments.add(_DistSegment(
label: label,
count: count,
fraction: count / totalCount.clamp(1, 9999),
));
}
return Column(
mainAxisSize: MainAxisSize.min,
crossAxisAlignment: CrossAxisAlignment.stretch,
children: [
_GradRule(),
const SizedBox(height: 10),
Text(
'DISTRIBUTION',
style: BaselineTypography.jbMono.copyWith(
fontSize: 6,
color: BaselineColors.white.atOpacity(0.12),
letterSpacing: 2,
),
),
const SizedBox(height: 6),
LayoutBuilder(
builder: (_, constraints) {
final totalW = constraints.maxWidth;
return SizedBox(
height: _kDistBarH + 26,
child: Stack(
clipBehavior: Clip.none,
children: [
// Bar track.
Positioned(
top: 6,
left: 0,
right: 0,
height: _kDistBarH,
child: Container(
decoration: BoxDecoration(
color: BaselineColors.white.atOpacity(_kBarTrackOp),
borderRadius: BorderRadius.circular(1),
),
),
),
// Quartile tick marks.
for (final pct in [0.25, 0.50, 0.75])
Positioned(
top: 4,
left: totalW * pct,
child: Container(
width: 1,
height: _kDistBarH + 4,
color: BaselineColors.teal.atOpacity(0.04),
),
),
// Segments.
..._buildSegments(segments, totalW),
// Avg drift marker.
if (avgDrift != null)
Positioned(
top: 0,
left:
(totalW * avgDrift!.clamp(0.0, 1.0)) - 3,
child: CustomPaint(
size: const Size(6, 5),
painter: _TrianglePainter(
color:
BaselineColors.teal.atOpacity(0.40),
),
),
),
// Labels below.
..._buildLabels(segments, totalW),
],
),
);
},
),
],
);
}
List<Widget> _buildSegments(
List<_DistSegment> segments, double totalW) {
final widgets = <Widget>[];
double offset = 0;
for (final seg in segments) {
final segW = totalW * seg.fraction;
if (seg.count > 0) {
final color = _bandLabelColor(seg.label);
widgets.add(Positioned(
top: 6,
left: offset,
width: segW,
height: _kDistBarH,
child: Container(
decoration: BoxDecoration(
color: color.atOpacity(0.35),
borderRadius: BorderRadius.circular(1),
),
),
));
}
offset += segW;
}
return widgets;
}
List<Widget> _buildLabels(
List<_DistSegment> segments, double totalW) {
final widgets = <Widget>[];
double offset = 0;
for (final seg in segments) {
final segW = totalW * seg.fraction;
if (seg.count > 0) {
final labelColor = _bandLabelColor(seg.label);
widgets.add(Positioned(
top: _kDistBarH + 9,
left: offset,
width: segW,
child: Text(
'${_bandShort(seg.label)}\n${seg.count}',
textAlign: TextAlign.center,
style: BaselineTypography.jbMono.copyWith(
fontSize: 5,
color: labelColor.atOpacity(0.60),
height: 1.3,
),
),
));
}
offset += segW;
}
return widgets;
}
}
class _DistSegment {
final String label;
final int count;
final double fraction;
const _DistSegment({
required this.label,
required this.count,
required this.fraction,
});
}
//
// ═══════════════════════════════════════════════════════════
// DISCLAIMER
//
// ═══════════════════════════════════════════════════════════
class _Disclaimer extends StatelessWidget {
@override
Widget build(BuildContext context) {
return Text(
'Observational analysis only. Not a fact-check.',
style: BaselineTypography.poppins.copyWith(
fontSize: 9,
color: BaselineColors.white.atOpacity(0.12),
),
);
}
}
//
// ═══════════════════════════════════════════════════════════
// ANIMATION WRAPPER (fade + slide + acquisition flash)
//
// ═══════════════════════════════════════════════════════════
class _AnimW extends StatelessWidget {
const _AnimW({
required this.masterCtrl,
required this.interval,
required this.child,
this.isRow = false,
});
final AnimationController masterCtrl;
final Interval interval;
final Widget child;
final bool isRow;
@override
Widget build(BuildContext context) {
return AnimatedBuilder(
animation: masterCtrl,
builder: (_, _) {
final t = interval.transform(masterCtrl.value);
// Signal acquisition flash: brief white pulse at end of reveal.
final flashOp = isRow && t > 0.85 && t < 0.95
? ((t - 0.85) / 0.05).clamp(0.0, 1.0) *
(1 - ((t - 0.90) / 0.05).clamp(0.0, 1.0)) *
0.03
: 0.0;
return Opacity(
opacity: t.clamp(0.0, 1.0),
child: Transform.translate(
offset: Offset(0, 6 * (1 - t)),
child: Container(
color: BaselineColors.white.atOpacity(flashOp.clamp(0.0, 1.0)),
child: child,
),
),
);
},
);
}
}
//
// ═══════════════════════════════════════════════════════════
// CUSTOM PAINTERS
//
// ═══════════════════════════════════════════════════════════
/// Chrome frame: reticle corners + scan grid.
class _ChromePainter extends CustomPainter {
_ChromePainter({required this.color});
final Color color;
@override
void paint(Canvas canvas, Size size) {
final paint = Paint()
..style = PaintingStyle.stroke
..strokeWidth = 1;
paint.color = color.atOpacity(0.02);
for (double y = 0; y < size.height; y += _kGridH) {
canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
}
for (double x = 0; x < size.width; x += _kGridV) {
canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
}
paint.color = color.atOpacity(0.06);
final corners = <Offset>[
Offset.zero,
Offset(size.width, 0),
Offset(0, size.height),
Offset(size.width, size.height),
];
for (final c in corners) {
final xDir = c.dx == 0 ? 1.0 : -1.0;
final yDir = c.dy == 0 ? 1.0 : -1.0;
canvas.drawLine(
c, Offset(c.dx + _kReticleLen * xDir, c.dy), paint);
canvas.drawLine(
c, Offset(c.dx, c.dy + _kReticleLen * yDir), paint);
canvas.drawLine(
Offset(c.dx + _kReticleTick * xDir,
c.dy + _kReticleTick * yDir),
Offset(c.dx + (_kReticleTick + 2) * xDir,
c.dy + _kReticleTick * yDir),
paint,
);
}
}
@override
bool shouldRepaint(covariant _ChromePainter old) => false;
}
/// Scanline sweep: vertical line L→R with phosphor wake.
class _ScanPainter extends CustomPainter {
_ScanPainter({required this.animation, required this.color})
: super(repaint: animation);
final Animation<double> animation;
final Color color;
@override
void paint(Canvas canvas, Size size) {
if (animation.value <= 0 || animation.value >= 1) return;
final x = animation.value * size.width;
const wakeW = 24.0;
final wakeRect = Rect.fromLTRB(
(x - wakeW).clamp(0.0, size.width), 0,
x.clamp(0.0, size.width), size.height,
);
final wakePaint = Paint()
..shader = LinearGradient(
colors: [color.atOpacity(0), color.atOpacity(0.04)],
).createShader(wakeRect);
canvas.drawRect(wakeRect, wakePaint);
final linePaint = Paint()
..color = color.atOpacity(0.12)
..strokeWidth = 1;
canvas.drawLine(Offset(x, 0), Offset(x, size.height), linePaint);
}
@override
bool shouldRepaint(covariant _ScanPainter old) => true;
}
/// Drift bar with measurement hashmarks at quartile positions.
class _HashBarPainter extends CustomPainter {
_HashBarPainter({
required this.score,
required this.barColor,
required this.trackColor,
required this.hashColor,
this.barHeight,
this.roundRadius,
});
final double score;
final Color barColor;
final Color trackColor;
final Color hashColor;
final double? barHeight;
final double? roundRadius;
@override
void paint(Canvas canvas, Size size) {
final h = barHeight ?? size.height;
final r = roundRadius ?? 0.0;
final yCenter = size.height / 2;
// Track.
final trackRect = RRect.fromLTRBR(
0, yCenter - h / 2, size.width, yCenter + h / 2,
Radius.circular(r),
);
canvas.drawRRect(trackRect, Paint()..color = trackColor);
// Fill.
final fillW = size.width * score.clamp(0.0, 1.0);
if (fillW > 0) {
final fillRect = RRect.fromLTRBAndCorners(
0, yCenter - h / 2, fillW, yCenter + h / 2,
topRight: Radius.circular(r),
bottomRight: Radius.circular(r),
);
canvas.drawRRect(fillRect, Paint()..color = barColor);
}
// Hashmarks at 25%, 50%, 75%.
final hashPaint = Paint()
..color = hashColor
..strokeWidth = 0.5;
for (final pct in [0.25, 0.50, 0.75]) {
final x = size.width * pct;
canvas.drawLine(
Offset(x, yCenter - h / 2 - 1),
Offset(x, yCenter + h / 2 + 1),
hashPaint,
);
}
}
@override
bool shouldRepaint(covariant _HashBarPainter old) =>
old.score != score || old.barColor != barColor;
}
/// Data fingerprint: 5 dots in a unique vertical pattern.
class _FingerprintPainter extends CustomPainter {
_FingerprintPainter({required this.offsets, required this.color});
final List<double> offsets;
final Color color;
@override
void paint(Canvas canvas, Size size) {
final paint = Paint()..color = color;
final spacing = size.width / (offsets.length + 1);
for (int i = 0; i < offsets.length; i++) {
final x = spacing * (i + 1);
final y = offsets[i] * size.height;
canvas.drawCircle(Offset(x, y), _kFingerprintDotR, paint);
}
}
@override
bool shouldRepaint(covariant _FingerprintPainter old) => false;
}
/// Avg drift triangle marker.
class _TrianglePainter extends CustomPainter {
_TrianglePainter({required this.color});
final Color color;
@override
void paint(Canvas canvas, Size size) {
final path = Path()
..moveTo(size.width / 2, size.height)
..lineTo(0, 0)
..lineTo(size.width, 0)
..close();
canvas.drawPath(path, Paint()..color = color);
}
@override
bool shouldRepaint(covariant _TrianglePainter old) =>
old.color != color;
}
//
// ═══════════════════════════════════════════════════════════
// HELPERS
//
// ═══════════════════════════════════════════════════════════
class _GradRule extends StatelessWidget {
@override
Widget build(BuildContext context) {
return Container(
height: 1,
decoration: BoxDecoration(
gradient: LinearGradient(
colors: [
Colors.transparent,
BaselineColors.teal.atOpacity(0.10),
BaselineColors.teal.atOpacity(0.10),
Colors.transparent,
],
stops: const [0, 0.3, 0.7, 1],
),
),
);
}
}
class _DashRule extends StatelessWidget {
const _DashRule({required this.color});
final Color color;
@override
Widget build(BuildContext context) {
return CustomPaint(
size: const Size(double.infinity, 1),
painter: _DashPainter(color: color),
);
}
}
class _DashPainter extends CustomPainter {
_DashPainter({required this.color});
final Color color;
@override
void paint(Canvas canvas, Size size) {
final paint = Paint()
..color = color
..strokeWidth = 0.5;
const dashW = 4.0;
const gapW = 3.0;
double x = 0;
while (x < size.width) {
canvas.drawLine(
Offset(x, size.height / 2),
Offset((x + dashW).clamp(0, size.width), size.height / 2),
paint,
);
x += dashW + gapW;
}
}
@override
bool shouldRepaint(covariant _DashPainter old) => old.color != color;
}
