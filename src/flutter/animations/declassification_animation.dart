/// T-5: Declassification Animation
///
/// Cinematic unlock transition for F6.4 FeatureGate. Plays exactly
/// once when a gated feature transitions locked→unlocked after
/// upgrade. Scanline sweep dissolves blur top→bottom with seal
/// break, clearance stamp, and redaction dispersion.
///
/// Path: lib/animations/declassification_animation.dart
library;
// 1. Dart SDK
import 'dart:math' as math;
import 'dart:ui' as ui show PlatformDispatcher, ImageFilter;
// 2. Flutter
import 'package:flutter/material.dart';
// 3. Config
import 'package:baseline_app/config/theme.dart';
// 4. Utils
import 'package:baseline_app/utils/haptic_util.dart';
//
// ═══════════════════════════════════════════════════════════
// CONSTANTS
//
// ═══════════════════════════════════════════════════════════
const double _kBlurSigma = 6.0;
const Duration _kTotalDuration = Duration(milliseconds: 900);
// Scanline: runs from t=150ms to t=750ms (600ms sweep).
const double _kScanStart = 150 / 900; // 0.167
const double _kScanEnd = 750 / 900; // 0.833
const double _kScanLineCoreOpacity = 0.60;
const double _kScanLineGlowHeight = 12.0;
const double _kScanLineGlowOpacity = 0.30;
const double _kEdgeLineOpacity = 0.20;
const double _kEdgeLineHeight = 4.0;
// Seal break.
const double _kSealFlashMax = 0.06;
// Stamp: appears at t=350ms, fades at t=700ms.
const double _kStampAppear = 350 / 900; // 0.389
const double _kStampScaleIn = 150 / 900; // +0.167
const double _kStampHold = 200 / 900; // +0.222
const double _kStampFadeOut = 150 / 900; // +0.167
const double _kStampScaleStart = 0.9;
// Post-sweep.
const double _kSettleFlashMax = 0.04;
const double _kSettleStart = 750 / 900;
// Haptics.
const double _kHapticMid = 350 / 900;
const double _kHapticEnd = 750 / 900;
// Redaction dispersion.
const double _kDispersionDriftY = 8.0;
const double _kDispersionJitterX = 3.0;
const double _kRowTargetHeight = 40.0; // target pixels per strip
const int _kMinRows = 4;
const int _kMaxRows = 16;
//
// ═══════════════════════════════════════════════════════════
// WIDGET
//
// ═══════════════════════════════════════════════════════════
class DeclassificationAnimation extends StatefulWidget {
const DeclassificationAnimation({
super.key,
required this.child,
this.onComplete,
this.autoPlay = true,
});
/// The locked overlay to declassify (dissolve away).
final Widget child;
/// Called when animation fully completes.
final VoidCallback? onComplete;
/// Start immediately on mount. Default true.
final bool autoPlay;
@override
State<DeclassificationAnimation> createState() =>
_DeclassificationAnimationState();
}
class _DeclassificationAnimationState
extends State<DeclassificationAnimation>
with SingleTickerProviderStateMixin {
late final AnimationController _controller;
bool _hapticMidFired = false;
bool _hapticEndFired = false;
bool _completeFired = false;
// Random jitter values for redaction strips (computed once per instance).
// Unseeded for organic per-session variance (A1-3).
List<double> _jitterValues = const [];
bool get _reduceMotion =>
ui.PlatformDispatcher.instance.accessibilityFeatures.reduceMotion;
@override
void initState() {
super.initState();
_controller = AnimationController(
vsync: this,
duration: _reduceMotion ? Duration.zero : _kTotalDuration,
);
_controller.addListener(_checkHaptics);
_controller.addStatusListener(_onStatus);
if (_reduceMotion) {
HapticUtil.medium();
_controller.value = 1.0;
WidgetsBinding.instance.addPostFrameCallback((_) {
if (mounted) widget.onComplete?.call();
});
} else if (widget.autoPlay) {
HapticUtil.medium();
_controller.forward();
}
}
/// Manually trigger the animation (if autoPlay is false).
void play() {
if (_controller.isAnimating || _controller.isCompleted) return;
HapticUtil.medium();
_controller.forward();
}
void _checkHaptics() {
final v = _controller.value;
if (!_hapticMidFired && v >= _kHapticMid) {
_hapticMidFired = true;
HapticUtil.light();
}
if (!_hapticEndFired && v >= _kHapticEnd) {
_hapticEndFired = true;
HapticUtil.medium();
}
}
void _onStatus(AnimationStatus status) {
if (status == AnimationStatus.completed && !_completeFired) {
_completeFired = true;
widget.onComplete?.call();
}
}
@override
void dispose() {
_controller.removeListener(_checkHaptics);
_controller.removeStatusListener(_onStatus);
_controller.dispose();
super.dispose();
}
// ── Jitter initialization (needs layout size) ────────────
/// Computes row count + jitter values on first layout pass.
void _ensureJitterValues(int rowCount) {
if (_jitterValues.length == rowCount) return;
final rng = math.Random(); // unseeded: organic per-session
_jitterValues = List.generate(
rowCount,
(_) => (rng.nextDouble() * 2 - 1) * _kDispersionJitterX,
);
}
// ── Derived animation values ─────────────────────────────
/// Seal break flash opacity (0→max→0 in first 150ms).
double get _sealFlash {
final t = _controller.value;
if (t > _kScanStart) return 0.0;
final sealT = t / _kScanStart; // 0..1 within seal phase
// Triangle: up then down.
return _kSealFlashMax *
(sealT < 0.5 ? sealT * 2 : (1.0 - sealT) * 2);
}
/// Scanline Y position as fraction of height (0..1).
double get _scanFraction {
final t = _controller.value;
if (t < _kScanStart) return -0.01;
if (t > _kScanEnd) return 1.01;
final scanT = (t - _kScanStart) / (_kScanEnd - _kScanStart);
return Curves.easeInOut.transform(scanT);
}
/// Stamp opacity (0..1).
double get _stampOpacity {
final t = _controller.value;
if (t < _kStampAppear) return 0.0;
final elapsed = t - _kStampAppear;
// Scale in.
if (elapsed < _kStampScaleIn) {
return (elapsed / _kStampScaleIn).clamp(0.0, 1.0);
}
// Hold.
if (elapsed < _kStampScaleIn + _kStampHold) return 1.0;
// Fade out.
final fadeElapsed = elapsed - _kStampScaleIn - _kStampHold;
if (fadeElapsed < _kStampFadeOut) {
return (1.0 - fadeElapsed / _kStampFadeOut).clamp(0.0, 1.0);
}
return 0.0;
}
/// Stamp scale (0.9→1.0 during scale-in, then 1.0).
double get _stampScale {
final t = _controller.value;
if (t < _kStampAppear) return _kStampScaleStart;
final elapsed = t - _kStampAppear;
if (elapsed < _kStampScaleIn) {
final frac = (elapsed / _kStampScaleIn).clamp(0.0, 1.0);
return _kStampScaleStart + (1.0 - _kStampScaleStart) * frac;
}
return 1.0;
}
/// Post-sweep settle flash.
double get _settleFlash {
final t = _controller.value;
if (t < _kSettleStart) return 0.0;
final settleT = (t - _kSettleStart) / (1.0 - _kSettleStart);
return _kSettleFlashMax * (1.0 - settleT).clamp(0.0, 1.0);
}
@override
Widget build(BuildContext context) {
if (_reduceMotion) return const SizedBox.shrink();
return AnimatedBuilder(
animation: _controller,
builder: (context, _) {
return LayoutBuilder(
builder: (context, constraints) {
final size = constraints.biggest;
final scanY = _scanFraction * size.height;
// Dynamic row count based on widget height (A1-9).
final rowCount = (size.height / _kRowTargetHeight)
.round()
.clamp(_kMinRows, _kMaxRows);
_ensureJitterValues(rowCount);
return Semantics(
label: 'Unlocking content',
child: SizedBox.expand(
child: Stack(
children: [
// ── Blurred child below scanline ──
if (_scanFraction < 1.0)
Positioned.fill(
child: ClipRect(
clipper: _BottomClipClipper(
splitY: scanY.clamp(0, size.height),
),
child: ImageFiltered(
imageFilter: ui.ImageFilter.blur(
sigmaX: _kBlurSigma,
sigmaY: _kBlurSigma,
),
child: widget.child,
),
),
),
// ── Clear child above scanline ──
if (_scanFraction > 0.0)
Positioned.fill(
child: ClipRect(
clipper: _TopClipClipper(
splitY: scanY.clamp(0, size.height),
),
child: widget.child,
),
),
// ── Redaction strip dispersion (A2-2) ──
// Renders clipped slices of actual overlay content
// with drift + jitter + fade. Real ink dissolving.
if (_scanFraction > 0.0 && _scanFraction < 1.2)
..._buildDispersionStrips(size, scanY, rowCount),
// ── Scanline + teal edge ──
if (_scanFraction > 0.0 && _scanFraction < 1.01)
Positioned(
left: 0,
right: 0,
top: scanY - _kScanLineGlowHeight,
height: _kScanLineGlowHeight + _kEdgeLineHeight,
child: CustomPaint(
painter: _ScanlinePainter(
glowHeight: _kScanLineGlowHeight,
edgeHeight: _kEdgeLineHeight,
coreOpacity: _kScanLineCoreOpacity,
glowOpacity: _kScanLineGlowOpacity,
edgeOpacity: _kEdgeLineOpacity,
color: BaselineColors.teal,
),
),
),
// ── Seal break flash ──
if (_sealFlash > 0.001)
Positioned.fill(
child: IgnorePointer(
child: ColoredBox(
color: BaselineColors.white.atOpacity(_sealFlash),
),
),
),
// ── CLEARANCE GRANTED stamp ──
if (_stampOpacity > 0.001)
Center(
child: Opacity(
opacity: _stampOpacity,
child: Transform.scale(
scale: _stampScale,
child: IgnorePointer(
child: Container(
padding: const EdgeInsets.symmetric(
horizontal: 12,
vertical: 6,
),
decoration: BoxDecoration(
border: Border.all(
color: BaselineColors.teal,
width: 1,
),
),
child: Text(
'CLEARANCE GRANTED',
style:
BaselineTypography.dataSmall.copyWith(
color: BaselineColors.teal,
fontSize: 10,
letterSpacing: 2.0,
),
),
),
),
),
),
),
// ── Post-sweep brightness settle ──
if (_settleFlash > 0.001)
Positioned.fill(
child: IgnorePointer(
child: ColoredBox(
color: BaselineColors.white.atOpacity(_settleFlash),
),
),
),
],
),
),
);
},
);
},
);
}
/// Builds dispersion strips from clipped slices of the actual overlay
/// content (widget.child). Each strip activates as the scanline passes,
/// then drifts down with horizontal jitter while fading out.
/// Real overlay fragments, not generic bands (A2-2).
List<Widget> _buildDispersionStrips(
Size size,
double scanY,
int rowCount,
) {
final rowHeight = size.height / rowCount;
return List.generate(rowCount, (i) {
final rowTop = i * rowHeight;
final rowCenter = rowTop + rowHeight / 2;
// How far past the scanline this strip is (0 = at line, 1 = fully past).
final pastFrac =
((scanY - rowCenter) / (size.height * 0.15)).clamp(0.0, 1.0);
if (pastFrac <= 0.0) return const SizedBox.shrink();
final driftY = _kDispersionDriftY * pastFrac;
final jitterX = _jitterValues[i] * pastFrac;
final opacity = (1.0 - pastFrac).clamp(0.0, 1.0);
return Positioned.fill(
child: Opacity(
opacity: opacity,
child: Transform.translate(
offset: Offset(jitterX, driftY),
child: ClipRect(
clipper: _StripClipper(
top: rowTop,
height: rowHeight,
),
child: widget.child,
),
),
),
);
});
}
}
//
// ═══════════════════════════════════════════════════════════
// CLIP HELPERS
//
// ═══════════════════════════════════════════════════════════
/// Clips to show only content ABOVE splitY.
class _TopClipClipper extends CustomClipper<Rect> {
_TopClipClipper({required this.splitY});
final double splitY;
@override
Rect getClip(Size size) => Rect.fromLTRB(0, 0, size.width, splitY);
@override
bool shouldReclip(_TopClipClipper old) => splitY != old.splitY;
}
/// Clips to show only content BELOW splitY.
class _BottomClipClipper extends CustomClipper<Rect> {
_BottomClipClipper({required this.splitY});
final double splitY;
@override
Rect getClip(Size size) =>
Rect.fromLTRB(0, splitY, size.width, size.height);
@override
bool shouldReclip(_BottomClipClipper old) => splitY != old.splitY;
}
/// Clips to show a single horizontal strip of content.
class _StripClipper extends CustomClipper<Rect> {
_StripClipper({required this.top, required this.height});
final double top;
final double height;
@override
Rect getClip(Size size) =>
Rect.fromLTWH(0, top, size.width, height);
@override
bool shouldReclip(_StripClipper old) =>
top != old.top || height != old.height;
}
//
// ═══════════════════════════════════════════════════════════
// SCANLINE PAINTER
//
// ═══════════════════════════════════════════════════════════
class _ScanlinePainter extends CustomPainter {
_ScanlinePainter({
required this.glowHeight,
required this.edgeHeight,
required this.coreOpacity,
required this.glowOpacity,
required this.edgeOpacity,
required this.color,
});
final double glowHeight;
final double edgeHeight;
final double coreOpacity;
final double glowOpacity;
final double edgeOpacity;
final Color color;
@override
void paint(Canvas canvas, Size size) {
// ── Upward glow trail ──
final glowRect = Rect.fromLTWH(0, 0, size.width, glowHeight);
final glowPaint = Paint()
..shader = LinearGradient(
begin: Alignment.topCenter,
end: Alignment.bottomCenter,
colors: [
color.atOpacity(0),
color.atOpacity(glowOpacity),
],
).createShader(glowRect);
canvas.drawRect(glowRect, glowPaint);
// ── Core line (1px at bottom of glow) ──
canvas.drawLine(
Offset(0, glowHeight),
Offset(size.width, glowHeight),
Paint()
..color = color.atOpacity(coreOpacity)
..strokeWidth = 1.0,
);
// ── Teal edge below core ──
final edgeRect = Rect.fromLTWH(
0,
glowHeight,
size.width,
edgeHeight,
);
final edgePaint = Paint()
..shader = LinearGradient(
begin: Alignment.topCenter,
end: Alignment.bottomCenter,
colors: [
color.atOpacity(edgeOpacity),
color.atOpacity(0),
],
).createShader(edgeRect);
canvas.drawRect(edgeRect, edgePaint);
}
@override
bool shouldRepaint(_ScanlinePainter old) => false; // props are const
}
