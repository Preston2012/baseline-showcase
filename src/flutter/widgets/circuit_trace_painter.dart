/// T-1: Circuit Trace Painter
///
/// CustomPainter for analysis-screen route transitions. Renders a
/// teal signal trace with junction nodes, micro-branch traces,
/// leading node with glow, terminal impact, and afterglow pulse.
///
/// Used by F5.3 BaselineTransitions.circuitTrace() as the sweep
/// overlay painter. Receives animation progress (0.0–1.0) and
/// optional tap origin for bidirectional trace.
///
/// Path: lib/widgets/circuit_trace_painter.dart
library;
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:baseline_app/config/theme.dart';
//
// ═══════════════════════════════════════════════════════════
// CONSTANTS
//
// ═══════════════════════════════════════════════════════════
// ── Trace body ──
const double _kTraceHeight = 2.0;
const double _kBodyLeadingOpacity = 0.55;
const double _kBodyTailOpacity = 0.10;
// ── Leading node ──
const double _kNodeRadius = 3.0;
const double _kNodeGlowSigma = 5.0;
const double _kNodeGlowOpacity = 0.6;
const double _kNodeCoreOpacity = 0.95;
// ── Junction nodes ──
const int _kJunctionCount = 3;
const List<double> _kJunctionPositions = [0.25, 0.50, 0.75];
const double _kJunctionDormantRadius = 2.0;
const double _kJunctionActiveRadius = 3.0;
const double _kJunctionDormantOpacity = 0.12;
const double _kJunctionActiveOpacity = 0.8;
const double _kJunctionIgnitionSigma = 6.0;
const double _kJunctionIgnitionOpacity = 0.55;
/// Duration (fraction of trace travel) of the ignition bloom.
const double _kJunctionIgnitionWindow = 0.08;
// ── Micro-branches ──
const double _kBranchLength = 10.0;
const double _kBranchStrokeWidth = 1.0;
const double _kBranchPeakOpacity = 0.45;
/// AUDIT FIX: Separate decay window for branches (vs ignition bloom).
const double _kBranchFadeWindow = 0.12;
/// Vertical offset pairs for branches at each junction.
const List<List<double>> _kBranchAngles = [
[-1.0, 1.0],
[-0.85, 1.15],
[-1.15, 0.85],
];
// ── Terminal flash ──
const double _kTerminalRadius = 8.0;
const double _kTerminalSigma = 6.0;
const double _kTerminalPeakOpacity = 0.5;
const double _kTerminalFlashWindow = 0.10;
// ── Afterglow ──
const double _kAfterglowPeakOpacity = 0.7;
const double _kAfterglowBaseOpacity = 0.4;
const double _kAfterglowSpread = 6.0;
const double _kAfterglowBlurSigma = 3.0;
// ── Timeline intervals ──
const double _kTraceEnd = 0.50;
const double _kAfterglowStart = 0.50;
const double _kAfterglowEnd = 0.70;
// ── Origin spark (bidirectional) ──
const double _kSparkRadius = 6.0;
const double _kSparkSigma = 8.0;
const double _kSparkFadeWindow = 0.3;
//
// ═══════════════════════════════════════════════════════════
// CIRCUIT TRACE PAINTER
//
// ═══════════════════════════════════════════════════════════
/// Paints the teal circuit trace for analysis screen transitions.
///
/// [progress] is the route animation value (0.0–1.0).
/// [tapOriginX] is the optional horizontal tap position.
/// If null, trace races left → right. If provided, trace expands
/// bidirectionally from that X position.
/// [yPosition] is the vertical position of the trace line.
class CircuitTracePainter extends CustomPainter {
CircuitTracePainter({
required this.progress,
this.tapOriginX,
required this.yPosition,
});
final double progress;
final double? tapOriginX;
final double yPosition;
@override
void paint(Canvas canvas, Size size) {
if (progress <= 0.0) return;
final screenWidth = size.width;
// Phase 1: Trace travel (0.0 → _kTraceEnd).
final traceProgress = (progress / _kTraceEnd).clamp(0.0, 1.0);
final easedTrace = Curves.easeOut.transform(traceProgress);
// Phase 2: Afterglow (_kAfterglowStart → _kAfterglowEnd).
final afterglowT = progress <= _kAfterglowStart
? 0.0
: ((progress - _kAfterglowStart) /
(_kAfterglowEnd - _kAfterglowStart))
.clamp(0.0, 1.0);
// Phase 3: Fade-out (after afterglow).
final fadeOutT = progress <= _kAfterglowEnd
? 0.0
: ((progress - _kAfterglowEnd) / (1.0 - _kAfterglowEnd))
.clamp(0.0, 1.0);
final masterOpacity = 1.0 - Curves.easeIn.transform(fadeOutT);
if (masterOpacity <= 0.0) return;
canvas.save();
// AUDIT FIX: Zero maxDist fallback to unidirectional.
if (tapOriginX != null) {
final originX = tapOriginX!.clamp(0.0, screenWidth);
final maxDist = math.max(originX, screenWidth - originX);
if (maxDist < 1.0) {
// Tap dead center on a near-zero-width screen: fallback.
_paintUnidirectional(
canvas, screenWidth, easedTrace, traceProgress,
afterglowT, masterOpacity, progress,
);
} else {
_paintBidirectional(
canvas, screenWidth, originX, maxDist,
easedTrace, traceProgress, afterglowT, masterOpacity, progress,
);
}
} else {
_paintUnidirectional(
canvas, screenWidth, easedTrace, traceProgress,
afterglowT, masterOpacity, progress,
);
}
canvas.restore();
}
// ── Unidirectional (left → right) ──────────────────────
/// AUDIT FIX: [progress] passed in (was referencing instance field
/// which is accessible but should be explicit for clarity).
void _paintUnidirectional(
Canvas canvas,
double screenWidth,
double easedTrace,
double rawTrace,
double afterglowT,
double masterOpacity,
double progress,
) {
final leadingX = screenWidth * easedTrace;
// Dormant junctions (behind trace body).
_paintJunctionsDormant(canvas, screenWidth, rawTrace, masterOpacity, null);
// Trace body.
if (easedTrace > 0.0) {
_paintTraceBody(canvas, startX: 0.0, endX: leadingX,
masterOpacity: masterOpacity);
}
// Active junctions + branches (on top of trace body).
_paintJunctionsActive(
canvas, screenWidth, rawTrace, masterOpacity, null, 0.0,
);
// Leading node.
if (easedTrace > 0.0 && easedTrace < 1.0) {
_paintLeadingNode(canvas, leadingX, masterOpacity);
}
// Terminal flash (right edge).
if (rawTrace >= 1.0) {
final terminalT =
((progress - _kTraceEnd) / _kTerminalFlashWindow).clamp(0.0, 1.0);
_paintTerminalFlash(canvas, screenWidth, terminalT, masterOpacity);
}
// Afterglow.
if (afterglowT > 0.0) {
_paintAfterglow(canvas, 0.0, screenWidth, afterglowT, masterOpacity);
}
}
// ── Bidirectional (tap origin → both edges) ────────────
void _paintBidirectional(
Canvas canvas,
double screenWidth,
double originX,
double maxDist,
double easedTrace,
double rawTrace,
double afterglowT,
double masterOpacity,
double progress,
) {
final travel = maxDist * easedTrace;
final leftX = (originX - travel).clamp(0.0, screenWidth);
final rightX = (originX + travel).clamp(0.0, screenWidth);
// Dormant junctions.
_paintJunctionsDormant(canvas, screenWidth, rawTrace, masterOpacity, originX);
// Left trace body.
if (easedTrace > 0.0 && originX > 0) {
_paintTraceBody(canvas, startX: originX, endX: leftX,
masterOpacity: masterOpacity, reversed: true);
}
// Right trace body.
if (easedTrace > 0.0 && originX < screenWidth) {
_paintTraceBody(canvas, startX: originX, endX: rightX,
masterOpacity: masterOpacity);
}
// Active junctions + branches.
_paintJunctionsActive(
canvas, screenWidth, rawTrace, masterOpacity, originX, maxDist,
);
// Leading nodes.
if (easedTrace > 0.0 && easedTrace < 1.0) {
if (originX > 0) _paintLeadingNode(canvas, leftX, masterOpacity);
if (originX < screenWidth) {
_paintLeadingNode(canvas, rightX, masterOpacity);
}
}
// Origin spark.
if (easedTrace > 0.0 && rawTrace < _kSparkFadeWindow) {
final sparkOpacity =
(1.0 - rawTrace / _kSparkFadeWindow) * masterOpacity;
_paintOriginSpark(canvas, originX, sparkOpacity);
}
// Terminal flashes (both edges).
if (rawTrace >= 1.0) {
final terminalT =
((progress - _kTraceEnd) / _kTerminalFlashWindow).clamp(0.0, 1.0);
if (originX > 0) {
_paintTerminalFlash(canvas, 0.0, terminalT, masterOpacity);
}
if (originX < screenWidth) {
_paintTerminalFlash(canvas, screenWidth, terminalT, masterOpacity);
}
}
// Afterglow.
if (afterglowT > 0.0) {
_paintAfterglow(canvas, 0.0, screenWidth, afterglowT, masterOpacity);
}
}
// ── Trace Body ─────────────────────────────────────────
void _paintTraceBody(
Canvas canvas, {
required double startX,
required double endX,
required double masterOpacity,
bool reversed = false,
}) {
final left = math.min(startX, endX);
final right = math.max(startX, endX);
if ((right - left) < 0.5) return;
final colors = reversed
? [
BaselineColors.teal
.atOpacity(_kBodyLeadingOpacity * masterOpacity),
BaselineColors.teal
.atOpacity(_kBodyTailOpacity * masterOpacity),
]
: [
BaselineColors.teal
.atOpacity(_kBodyTailOpacity * masterOpacity),
BaselineColors.teal
.atOpacity(_kBodyLeadingOpacity * masterOpacity),
];
final paint = Paint()
..shader = ui.Gradient.linear(
Offset(left, yPosition),
Offset(right, yPosition),
colors,
)
..strokeWidth = _kTraceHeight
..strokeCap = StrokeCap.round
..isAntiAlias = true;
canvas.drawLine(
Offset(left, yPosition),
Offset(right, yPosition),
paint,
);
}
// ── Leading Node ───────────────────────────────────────
void _paintLeadingNode(Canvas canvas, double x, double masterOpacity) {
final center = Offset(x, yPosition);
final glowPaint = Paint()
..style = PaintingStyle.fill
..maskFilter = MaskFilter.blur(BlurStyle.normal, _kNodeGlowSigma)
..color = BaselineColors.teal
.atOpacity(_kNodeGlowOpacity * masterOpacity);
canvas.drawCircle(center, _kNodeRadius * 1.5, glowPaint);
final corePaint = Paint()
..style = PaintingStyle.fill
..color = BaselineColors.teal
.atOpacity(_kNodeCoreOpacity * masterOpacity);
canvas.drawCircle(center, _kNodeRadius, corePaint);
}
// ── Junction Nodes: Dormant Pass (behind trace body) ──
void _paintJunctionsDormant(
Canvas canvas,
double screenWidth,
double rawTraceProgress,
double masterOpacity,
double? originX,
) {
for (int i = 0; i < _kJunctionCount; i++) {
final junctionX = screenWidth * _kJunctionPositions[i];
final reached = _isJunctionReached(
junctionX, rawTraceProgress, screenWidth, originX);
if (!reached) {
final dormantPaint = Paint()
..style = PaintingStyle.fill
..color = BaselineColors.teal
.atOpacity(_kJunctionDormantOpacity * masterOpacity);
canvas.drawCircle(
Offset(junctionX, yPosition),
_kJunctionDormantRadius,
dormantPaint,
);
}
}
}
// ── Junction Nodes: Active Pass (on top of trace body) ──
void _paintJunctionsActive(
Canvas canvas,
double screenWidth,
double rawTraceProgress,
double masterOpacity,
double? originX,
double maxDist,
) {
for (int i = 0; i < _kJunctionCount; i++) {
final junctionX = screenWidth * _kJunctionPositions[i];
final reached = _isJunctionReached(
junctionX, rawTraceProgress, screenWidth, originX);
if (!reached) continue;
final center = Offset(junctionX, yPosition);
// AUDIT FIX: Correct activation age calculation.
final reachT = _junctionReachT(
junctionX, screenWidth, originX, maxDist);
final timeSinceReach = rawTraceProgress - reachT;
// Ignition bloom (brief bright flash, decays over ignition window).
final ignitionAge =
(timeSinceReach / _kJunctionIgnitionWindow).clamp(0.0, 1.0);
final ignitionOpacity =
_kJunctionIgnitionOpacity * (1.0 - ignitionAge) * masterOpacity;
if (ignitionOpacity > 0.01) {
final ignitionPaint = Paint()
..style = PaintingStyle.fill
..maskFilter = MaskFilter.blur(
BlurStyle.normal, _kJunctionIgnitionSigma)
..color = BaselineColors.teal.atOpacity(ignitionOpacity);
canvas.drawCircle(center, _kJunctionActiveRadius * 2, ignitionPaint);
}
// Active core (stays lit after ignition fades).
final corePaint = Paint()
..style = PaintingStyle.fill
..color = BaselineColors.teal
.atOpacity(_kJunctionActiveOpacity * masterOpacity);
canvas.drawCircle(center, _kJunctionActiveRadius, corePaint);
// AUDIT FIX: Branches use separate _kBranchFadeWindow.
final branchAge =
(timeSinceReach / _kBranchFadeWindow).clamp(0.0, 1.0);
final branchOpacity =
_kBranchPeakOpacity * (1.0 - branchAge) * masterOpacity;
if (branchOpacity > 0.01) {
_paintBranches(canvas, center, i, branchOpacity);
}
}
}
// ── Junction helpers ───────────────────────────────────
/// Whether the trace wavefront has reached this junction.
bool _isJunctionReached(
double junctionX,
double rawTraceProgress,
double screenWidth,
double? originX,
) {
if (originX == null) {
// Unidirectional: junction position IS the reach threshold.
return rawTraceProgress >= _junctionReachT(
junctionX, screenWidth, null, 0.0);
} else {
// Bidirectional: reached when wavefront has traveled far enough.
final maxDist = math.max(originX, screenWidth - originX);
if (maxDist < 1.0) return rawTraceProgress >= 0.5;
final reachT = _junctionReachT(
junctionX, screenWidth, originX, maxDist);
return rawTraceProgress >= reachT;
}
}
/// AUDIT FIX: Compute the trace progress value at which the
/// wavefront first reaches a junction.
///
/// Unidirectional: position along screen (0.0–1.0).
/// Bidirectional: distance from origin / max arm distance.
double _junctionReachT(
double junctionX,
double screenWidth,
double? originX,
double maxDist,
) {
if (originX == null) {
// Unidirectional: junction at 25% of screen → reached at rawTrace 0.25.
return screenWidth > 0 ? (junctionX / screenWidth) : 0.0;
} else {
// Bidirectional: distance from tap origin, normalized.
if (maxDist < 1.0) return 0.0;
return (junctionX - originX).abs() / maxDist;
}
}
// ── Micro-Branches ─────────────────────────────────────
void _paintBranches(
Canvas canvas,
Offset junctionCenter,
int junctionIndex,
double opacity,
) {
// AUDIT FIX: Bounds-safe index.
final angles = _kBranchAngles[junctionIndex % _kBranchAngles.length];
for (final direction in angles) {
final angle = direction * (math.pi / 2);
final endPoint = Offset(
junctionCenter.dx + _kBranchLength * math.sin(angle) * 0.15,
junctionCenter.dy + _kBranchLength * math.cos(angle),
);
final branchGradient = ui.Gradient.linear(
junctionCenter,
endPoint,
[
BaselineColors.teal.atOpacity(opacity),
BaselineColors.teal.atOpacity(opacity * 0.15),
],
);
final branchPaint = Paint()
..strokeWidth = _kBranchStrokeWidth
..strokeCap = StrokeCap.round
..isAntiAlias = true
..shader = branchGradient;
canvas.drawLine(junctionCenter, endPoint, branchPaint);
}
}
// ── Terminal Flash ─────────────────────────────────────
void _paintTerminalFlash(
Canvas canvas,
double x,
double flashT,
double masterOpacity,
) {
final flashOpacity = flashT < 0.25
? flashT / 0.25
: 1.0 - ((flashT - 0.25) / 0.75);
final effectiveOpacity =
_kTerminalPeakOpacity * flashOpacity * masterOpacity;
if (effectiveOpacity <= 0.01) return;
final center = Offset(x, yPosition);
final expandedRadius = _kTerminalRadius * (0.5 + 0.5 * flashT);
final bloomPaint = Paint()
..style = PaintingStyle.fill
..maskFilter = MaskFilter.blur(BlurStyle.normal, _kTerminalSigma)
..color = BaselineColors.teal.atOpacity(effectiveOpacity);
canvas.drawCircle(center, expandedRadius, bloomPaint);
if (flashT < 0.5) {
final coreOpacity = (effectiveOpacity * 1.3).clamp(0.0, 1.0);
final corePaint = Paint()
..style = PaintingStyle.fill
..color = BaselineColors.teal.atOpacity(coreOpacity);
canvas.drawCircle(center, _kNodeRadius, corePaint);
}
}
// ── Origin Spark (bidirectional) ───────────────────────
void _paintOriginSpark(Canvas canvas, double x, double opacity) {
if (opacity <= 0.01) return;
final center = Offset(x, yPosition);
final sparkPaint = Paint()
..style = PaintingStyle.fill
..maskFilter = MaskFilter.blur(BlurStyle.normal, _kSparkSigma)
..color = BaselineColors.teal.atOpacity(opacity * 0.5);
canvas.drawCircle(center, _kSparkRadius, sparkPaint);
}
// ── Afterglow ──────────────────────────────────────────
void _paintAfterglow(
Canvas canvas,
double startX,
double endX,
double pulseT,
double masterOpacity,
) {
final pulseOpacity = pulseT < 0.3
? ui.lerpDouble(
_kAfterglowBaseOpacity, _kAfterglowPeakOpacity, pulseT / 0.3)!
: ui.lerpDouble(
_kAfterglowPeakOpacity, 0.0, (pulseT - 0.3) / 0.7)!;
if (pulseOpacity <= 0.01) return;
final effectiveOpacity = pulseOpacity * masterOpacity;
// Full-width trace line.
final linePaint = Paint()
..color = BaselineColors.teal.atOpacity(effectiveOpacity)
..strokeWidth = _kTraceHeight
..strokeCap = StrokeCap.round;
canvas.drawLine(
Offset(startX, yPosition),
Offset(endX, yPosition),
linePaint,
);
// Vertical bloom.
final bloomPaint = Paint()
..maskFilter =
MaskFilter.blur(BlurStyle.normal, _kAfterglowBlurSigma)
..color = BaselineColors.teal.atOpacity(effectiveOpacity * 0.35);
canvas.drawRect(
Rect.fromLTRB(
startX,
yPosition - _kAfterglowSpread,
endX,
yPosition + _kAfterglowSpread,
),
bloomPaint,
);
// Junction residual glow during afterglow.
for (int i = 0; i < _kJunctionCount; i++) {
final jX = (endX - startX) * _kJunctionPositions[i] + startX;
final residualPaint = Paint()
..style = PaintingStyle.fill
..color = BaselineColors.teal
.atOpacity(effectiveOpacity * 0.5);
canvas.drawCircle(
Offset(jX, yPosition),
_kJunctionActiveRadius,
residualPaint,
);
}
}
// ── Repaint ────────────────────────────────────────────
@override
bool shouldRepaint(covariant CircuitTracePainter oldDelegate) =>
progress != oldDelegate.progress ||
tapOriginX != oldDelegate.tapOriginX ||
yPosition != oldDelegate.yPosition;
}
//
// ═══════════════════════════════════════════════════════════
// F5.3 INTEGRATION: DROP-IN OVERLAY WIDGET
//
// ═══════════════════════════════════════════════════════════
/// Positions the CircuitTracePainter below the header and handles
/// the animation lifecycle. Drop-in replacement for F5.3's current
/// sweep Container.
///
/// AUDIT FIX: Includes local reduce-motion guard. Returns empty
/// widget when platform animations are disabled.
///
///
