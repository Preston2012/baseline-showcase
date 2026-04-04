///
/// Path: lib/widgets/framing_fingerprint.dart
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:baseline_app/config/theme.dart';
import 'package:baseline_app/models/framing.dart';

// ═══════════════════════════════════════════════════════════
// CONSTANTS
// ═══════════════════════════════════════════════════════════

/// Number of framing axes. LOCKED at 5 (matches Framing Radar™).
const int _kAxisCount = 5;

/// Minimum widget size.
const double _kMinSize = 20.0;

/// Size threshold: compact chrome (subtle echo ring).
const double _kCompactChromeThreshold = 48.0;

/// Size threshold: hero chrome (full biometric treatment).
const double _kHeroChromeThreshold = 80.0;

/// Size threshold: detail chrome (axis labels + classification).
const double _kDetailThreshold = 120.0;

/// Size threshold below which skeleton spokes are hidden.
const double _kSkeletonVisibleThreshold = 60.0;

/// Size threshold below which vertex dots are hidden.
const double _kVertexVisibleThreshold = 48.0;

// ── Chrome detail tiers ──

enum _ChromeDetail { none, compact, hero, detail }

_ChromeDetail _chromeForSize(double size) {
  if (size >= _kDetailThreshold) return _ChromeDetail.detail;
  if (size >= _kHeroChromeThreshold) return _ChromeDetail.hero;
  if (size >= _kCompactChromeThreshold) return _ChromeDetail.compact;
  return _ChromeDetail.none;
}

bool _isHeroOrAbove(_ChromeDetail c) =>
    c == _ChromeDetail.hero || c == _ChromeDetail.detail;

// ── Asymmetry amplification ──

const double _kAmplificationExponent = 0.7;
const double _kMinAxisValue = 0.08;

// ── Fill ──
const double _kFillOpacityCenter = 0.12;
const double _kFillOpacityEdge = 0.04;

// ── Stroke ──
const double _kStrokeOpacity = 0.65;
const double _kStrokeWidthBase = 1.5;
const double _kStrokeWidthMin = 0.8;

// ── Contour ridges ──
const int _kRidgeCount = 3;
const List<double> _kRidgeScales = [0.70, 0.45, 0.22];
const List<double> _kRidgeOpacities = [0.22, 0.14, 0.08];
const double _kRidgeStrokeWidth = 0.7;

// ── Dominant axis hotspot ──
const double _kHotspotBlurSigma = 4.0;
const double _kHotspotOpacity = 0.45;
const double _kHotspotRadius = 3.5;
const double _kHotspotMinLead = 0.05;

// ── Skeleton ──
const double _kSkeletonOpacity = 0.08;

// ── Vertices ──
const double _kVertexRadius = 2.0;
const double _kVertexOpacity = 0.7;

// ── Center dot / Whorl ──
const double _kCenterDotRadius = 1.5;
const double _kCenterDotOpacity = 0.5;
const double _kWhorlRingSpacing = 2.5;
const double _kWhorlRingStrokeWidth = 0.4;

// ── Animation durations ──
const Duration _kAcquireDuration = Duration(milliseconds: 500);
const Duration _kBezelMorphDuration = Duration(milliseconds: 400);
const Duration _kDrawOnDuration = Duration(milliseconds: 500);
const Duration _kVertexPopDuration = Duration(milliseconds: 300);
const Duration _kAcquiredFlashDuration = Duration(milliseconds: 200);
const Duration _kBreathingDuration = Duration(milliseconds: 5000);
const Duration _kMorphDuration = Duration(milliseconds: 600);

// ── Hero chrome: adaptive bezel ──
const double _kBezelGap = 4.0;
const double _kBezelStrokeWidth = 1.0;
const double _kBezelOpacity = 0.18;
const double _kBezelAdaptiveAmplitude = 0.15;
const double _kBezelHashLength = 4.0;
const double _kBezelHashOpacity = 0.25;
const double _kInnerHairlineOpacity = 0.06;
const double _kInstrumentGapDegrees = 3.0;
const double _kBezelDriftAmplitude = 0.5;
const Duration _kBezelDriftDuration = Duration(milliseconds: 8000);

// ── Bifurcation markers ──
const double _kBifurcationLength = 3.5;
const double _kBifurcationSpread = 0.35;
const double _kBifurcationOpacity = 0.30;

// ── Registration dots ──
const double _kRegistrationDotRadius = 1.2;
const double _kRegistrationDotOpacity = 0.30;

// ── Reticle corners ──
const double _kReticleLength = 6.0;
const double _kReticleStrokeWidth = 0.8;
const double _kReticleOpacity = 0.15;

// ── Phosphor persistence ──
const double _kPhosphorOpacity = 0.04;
const double _kPhosphorScale = 1.015;

// ── Compact chrome ──
const double _kCompactRingOpacity = 0.10;
const double _kCompactAdaptiveAmplitude = 0.08;

// ── Acquired flash ──
const double _kAcquiredFlashOpacity = 0.12;

// ── Spline ──
const double _kSplineTension = 0.4;
const int _kSplineSegments = 8;

// ── Axis labels ──
const List<String> _kAxisLabels = [
  'adversarial',
  'problem',
  'commitment',
  'justification',
  'imperative',
];

/// Short axis labels for detail-size bezel text.
const List<String> _kAxisAbbreviations = [
  'ADV',
  'PRB',
  'CMT',
  'JST',
  'IMP',
];

const Map<String, int> _kBackendKeyToIndex = {
  'adversarial / oppositional': 0,
  'adversarial': 0,
  'problem identification': 1,
  'problem': 1,
  'commitment / forward-looking': 2,
  'commitment': 2,
  'justification / reactive': 3,
  'justification': 3,
  'imperative / directive': 4,
  'imperative': 4,
};

// ═══════════════════════════════════════════════════════════
// FRAMING VALUES — DATA MODEL
// ═══════════════════════════════════════════════════════════

/// Immutable container for 5-axis framing proportions (0.0 to 1.0).
///
/// Two typed constructors bridge different data sources:
/// - [fromCategoryMap]: typed F3.7 FramingCategory enum keys
/// - [fromJsonMap]: raw backend JSON string keys (handles num to double)
class FramingValues {
  const FramingValues({
    required this.adversarial,
    required this.problem,
    required this.commitment,
    required this.justification,
    required this.imperative,
  });

  static const FramingValues empty = FramingValues(
    adversarial: 0,
    problem: 0,
    commitment: 0,
    justification: 0,
    imperative: 0,
  );

  factory FramingValues.fromCategoryMap(Map<FramingCategory, double> map) {
    return FramingValues(
      adversarial: (map[FramingCategory.adversarial] ?? 0.0).clamp(0.0, 1.0),
      problem: (map[FramingCategory.problem] ?? 0.0).clamp(0.0, 1.0),
      commitment: (map[FramingCategory.commitment] ?? 0.0).clamp(0.0, 1.0),
      justification:
          (map[FramingCategory.justification] ?? 0.0).clamp(0.0, 1.0),
      imperative: (map[FramingCategory.imperative] ?? 0.0).clamp(0.0, 1.0),
    );
  }

  factory FramingValues.fromJsonMap(Map<String, dynamic> map) {
    final result = [0.0, 0.0, 0.0, 0.0, 0.0];
    for (final entry in map.entries) {
      final normalizedKey = entry.key.trim().toLowerCase();
      final index = _kBackendKeyToIndex[normalizedKey];
      if (index != null && entry.value is num) {
        result[index] = (entry.value as num).toDouble().clamp(0.0, 1.0);
      }
    }
    return FramingValues(
      adversarial: result[0],
      problem: result[1],
      commitment: result[2],
      justification: result[3],
      imperative: result[4],
    );
  }

  final double adversarial;
  final double problem;
  final double commitment;
  final double justification;
  final double imperative;

  List<double> toList() => [
        adversarial,
        problem,
        commitment,
        justification,
        imperative,
      ];

  /// Returns 5 values with asymmetry amplification applied.
  /// This is the SINGLE source of clamping.
  List<double> toAmplifiedList() => toList().map((v) {
        final clamped = v.clamp(_kMinAxisValue, 1.0);
        return math.pow(clamped, _kAmplificationExponent).toDouble();
      }).toList();

  int get dominantIndex {
    final list = toList();
    int maxIdx = 0;
    for (int i = 1; i < list.length; i++) {
      if (list[i] > list[maxIdx]) maxIdx = i;
    }
    return maxIdx;
  }

  bool get hasClearDominant {
    final list = toList();
    final sorted = List<double>.from(list)..sort();
    return (sorted.last - sorted[sorted.length - 2]) >= _kHotspotMinLead;
  }

  /// Whorl ring count based on dominant axis strength.
  /// 3 = strong dominant (>= 0.6), 2 = moderate (>= 0.35), 1 = flat.
  int get whorlRingCount {
    final list = toList();
    final dominantStrength = list[dominantIndex];
    if (dominantStrength >= 0.6) return 3;
    if (dominantStrength >= 0.35) return 2;
    return 1;
  }

  static FramingValues lerp(FramingValues a, FramingValues b, double t) {
    return FramingValues(
      adversarial: ui.lerpDouble(a.adversarial, b.adversarial, t)!,
      problem: ui.lerpDouble(a.problem, b.problem, t)!,
      commitment: ui.lerpDouble(a.commitment, b.commitment, t)!,
      justification: ui.lerpDouble(a.justification, b.justification, t)!,
      imperative: ui.lerpDouble(a.imperative, b.imperative, t)!,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FramingValues &&
          adversarial == other.adversarial &&
          problem == other.problem &&
          commitment == other.commitment &&
          justification == other.justification &&
          imperative == other.imperative;

  @override
  int get hashCode => Object.hash(
        adversarial,
        problem,
        commitment,
        justification,
        imperative,
      );
}

class FramingValuesTween extends Tween<FramingValues> {
  FramingValuesTween({
    required FramingValues begin,
    required FramingValues end,
  }) : super(begin: begin, end: end);

  @override
  FramingValues lerp(double t) => FramingValues.lerp(
        begin ?? FramingValues.empty,
        end ?? FramingValues.empty,
        t,
      );
}

// ═══════════════════════════════════════════════════════════
// FRAMING FINGERPRINT WIDGET
// ═══════════════════════════════════════════════════════════

class FramingFingerprint extends StatefulWidget {
  const FramingFingerprint({
    super.key,
    required this.size,
    required this.values,
    this.animate = true,
    this.showDrawOn = false,
    this.enabled = true,
  }) : assert(size >= _kMinSize,
            'FramingFingerprint: size must be >= $_kMinSize');

  /// Compact badge for feed cards and list rows (28px).
  /// Static: zero animation for scroll performance.
  const FramingFingerprint.badge({
    super.key,
    required this.values,
  })  : size = 28.0,
        animate = false,
        showDrawOn = false,
        enabled = true;

  /// Medium glyph for Crossfire™ comparison cards (48px).
  const FramingFingerprint.compact({
    super.key,
    required this.values,
    this.animate = true,
  })  : size = 48.0,
        showDrawOn = false,
        enabled = true;

  /// Large glyph for figure profile hero section (80px).
  /// Full biometric acquisition entrance.
  const FramingFingerprint.profile({
    super.key,
    required this.values,
    this.animate = true,
    this.showDrawOn = true,
  })  : size = 80.0,
        enabled = true;

  /// Extra-large for detail view or social card export (120px).
  /// Axis labels, classification box, maximum chrome.
  const FramingFingerprint.detail({
    super.key,
    required this.values,
    this.animate = true,
    this.showDrawOn = true,
  })  : size = 120.0,
        enabled = true;

  /// Constructs a fingerprint from a FramingCategory map.
  /// Converts the map to FramingValues internally.
  factory FramingFingerprint.fromCategoryMap({
    Key? key,
    required Map<FramingCategory, double> data,
    required double size,
    bool animate = false,
    bool showDrawOn = false,
    bool enabled = true,
  }) {
    return FramingFingerprint(
      key: key,
      size: size,
      values: FramingValues.fromCategoryMap(data),
      animate: animate,
      showDrawOn: showDrawOn,
      enabled: enabled,
    );
  }

  final double size;
  final FramingValues values;
  final bool animate;
  final bool showDrawOn;
  final bool enabled;

  @override
  State<FramingFingerprint> createState() => _FramingFingerprintState();
}

class _FramingFingerprintState extends State<FramingFingerprint>
    with TickerProviderStateMixin {
  // ── Controllers ──

  /// Breathing cycle (all animated sizes).
  AnimationController? _breathCtrl;

  /// Hero Phase 1: radial acquisition sweep (center outward).
  AnimationController? _acquireCtrl;
  CurvedAnimation? _acquireCurve;

  /// Hero Phase 2: adaptive bezel morph from circle to data shape.
  AnimationController? _bezelMorphCtrl;
  CurvedAnimation? _bezelMorphCurve;

  /// Hero Phase 3: spline draw-on.
  AnimationController? _drawOnCtrl;
  CurvedAnimation? _drawOnCurve;

  /// Hero Phase 4: vertex + hotspot pop.
  AnimationController? _vertexPopCtrl;
  CurvedAnimation? _vertexPopCurve;

  /// Hero ambient: bezel rotation drift.
  AnimationController? _bezelDriftCtrl;

  /// "ACQUIRED" flash on entrance complete (one-shot).
  AnimationController? _acquiredFlashCtrl;

  late FramingValues _prevValues;
  bool _reduceMotion = false;
  final List<Timer> _pendingTimers = [];
  late _ChromeDetail _chrome;

  // ── Lifecycle ──

  @override
  void initState() {
    super.initState();
    _prevValues = widget.values;
    _chrome = _chromeForSize(widget.size);
    _initControllers();
  }

  void _initControllers() {
    final isHero = _isHeroOrAbove(_chrome);

    if (widget.animate) {
      _breathCtrl = AnimationController(
        vsync: this,
        duration: _kBreathingDuration,
      );
    }

    if (isHero && widget.showDrawOn) {
      _acquireCtrl = AnimationController(
        vsync: this,
        duration: _kAcquireDuration,
      );
      _acquireCurve = CurvedAnimation(
        parent: _acquireCtrl!,
        curve: Curves.easeOutCubic,
      );

      _bezelMorphCtrl = AnimationController(
        vsync: this,
        duration: _kBezelMorphDuration,
      );
      _bezelMorphCurve = CurvedAnimation(
        parent: _bezelMorphCtrl!,
        curve: Curves.easeInOut,
      );

      _drawOnCtrl = AnimationController(
        vsync: this,
        duration: _kDrawOnDuration,
      );
      _drawOnCurve = CurvedAnimation(
        parent: _drawOnCtrl!,
        curve: Curves.easeOut,
      );

      _vertexPopCtrl = AnimationController(
        vsync: this,
        duration: _kVertexPopDuration,
      );
      _vertexPopCurve = CurvedAnimation(
        parent: _vertexPopCtrl!,
        curve: Curves.easeOutBack,
      );

      _acquiredFlashCtrl = AnimationController(
        vsync: this,
        duration: _kAcquiredFlashDuration,
      );

      _bezelDriftCtrl = AnimationController(
        vsync: this,
        duration: _kBezelDriftDuration,
      );

      // Wire status listener chain (3C).
      _acquireCtrl!.addStatusListener(_onAcquireComplete);
    } else if (widget.showDrawOn) {
      // Non-hero draw-on (fallback).
      _drawOnCtrl = AnimationController(
        vsync: this,
        duration: _kDrawOnDuration,
      );
      _drawOnCurve = CurvedAnimation(
        parent: _drawOnCtrl!,
        curve: Curves.easeOut,
      );
    }
  }

  // ── Status listener chain (3C) ──
  // Phase 1 (acquire) → Phase 2 (bezel morph) → Phase 3 (draw-on)
  // → Phase 4 (vertex pop + acquired flash) → ambient

  void _onAcquireComplete(AnimationStatus s) {
    if (s != AnimationStatus.completed) return;
    _acquireCtrl!.removeStatusListener(_onAcquireComplete);
    if (!mounted || _reduceMotion) return;
    _bezelMorphCtrl!.addStatusListener(_onBezelMorphComplete);
    _bezelMorphCtrl!.forward();
  }

  void _onBezelMorphComplete(AnimationStatus s) {
    if (s != AnimationStatus.completed) return;
    _bezelMorphCtrl!.removeStatusListener(_onBezelMorphComplete);
    if (!mounted || _reduceMotion) return;
    _drawOnCtrl!.addStatusListener(_onDrawOnComplete);
    _drawOnCtrl!.forward();
  }

  void _onDrawOnComplete(AnimationStatus s) {
    if (s != AnimationStatus.completed) return;
    _drawOnCtrl!.removeStatusListener(_onDrawOnComplete);
    if (!mounted || _reduceMotion) return;
    _vertexPopCtrl!.addStatusListener(_onVertexPopComplete);
    _vertexPopCtrl!.forward();
    // Fire acquired flash simultaneously with vertex pop.
    _acquiredFlashCtrl!.forward();
  }

  void _onVertexPopComplete(AnimationStatus s) {
    if (s != AnimationStatus.completed) return;
    _vertexPopCtrl!.removeStatusListener(_onVertexPopComplete);
    if (!mounted || _reduceMotion) return;
    // Start ambient after entrance (I-18).
    _breathCtrl?.repeat();
    _bezelDriftCtrl?.repeat();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final newReduce = MediaQuery.disableAnimationsOf(context);
    if (newReduce != _reduceMotion) {
      _reduceMotion = newReduce;
      if (_reduceMotion) {
        _snapToFinal();
      }
    }
    _syncControllers();
  }

  @override
  void didUpdateWidget(covariant FramingFingerprint oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.values != widget.values) {
      _prevValues = oldWidget.values;
    }

    // MS1: Re-evaluate tier if size crossed a threshold.
    final newChrome = _chromeForSize(widget.size);
    if (newChrome != _chrome) {
      final wasHero = _isHeroOrAbove(_chrome);
      _chrome = newChrome;
      final isNowHero = _isHeroOrAbove(_chrome);

      // Upgrade: init missing hero controllers, snap to final.
      if (isNowHero && !wasHero && widget.showDrawOn) {
        _acquireCtrl ??= AnimationController(
          vsync: this,
          duration: _kAcquireDuration,
        )..value = 1.0;
        _acquireCurve ??= CurvedAnimation(
          parent: _acquireCtrl!,
          curve: Curves.easeOutCubic,
        );
        _bezelMorphCtrl ??= AnimationController(
          vsync: this,
          duration: _kBezelMorphDuration,
        )..value = 1.0;
        _bezelMorphCurve ??= CurvedAnimation(
          parent: _bezelMorphCtrl!,
          curve: Curves.easeInOut,
        );
        _drawOnCtrl ??= AnimationController(
          vsync: this,
          duration: _kDrawOnDuration,
        )..value = 1.0;
        _drawOnCurve ??= CurvedAnimation(
          parent: _drawOnCtrl!,
          curve: Curves.easeOut,
        );
        _vertexPopCtrl ??= AnimationController(
          vsync: this,
          duration: _kVertexPopDuration,
        )..value = 1.0;
        _vertexPopCurve ??= CurvedAnimation(
          parent: _vertexPopCtrl!,
          curve: Curves.easeOutBack,
        );
        _acquiredFlashCtrl ??= AnimationController(
          vsync: this,
          duration: _kAcquiredFlashDuration,
        )..value = 1.0;
        _bezelDriftCtrl ??= AnimationController(
          vsync: this,
          duration: _kBezelDriftDuration,
        );
        // Start ambient immediately (entrance already "complete").
        if (!_reduceMotion && widget.enabled) {
          _breathCtrl?.repeat();
          _bezelDriftCtrl?.repeat();
        }
      }
    }

    if (oldWidget.animate != widget.animate ||
        oldWidget.enabled != widget.enabled) {
      _syncControllers();
    }
  }

  /// Mid-flight reduceMotion snap (I-9).
  void _snapToFinal() {
    for (final t in _pendingTimers) {
      t.cancel();
    }
    _pendingTimers.clear();
    _acquireCtrl?.value = 1.0;
    _bezelMorphCtrl?.value = 1.0;
    _drawOnCtrl?.value = 1.0;
    _vertexPopCtrl?.value = 1.0;
    _acquiredFlashCtrl?.value = 1.0;
    _breathCtrl?.stop();
    _breathCtrl?.value = 0.0;
    _bezelDriftCtrl?.stop();
    _bezelDriftCtrl?.value = 0.0;
  }

  void _syncControllers() {
    final shouldAnimate = widget.enabled && !_reduceMotion;
    if (!shouldAnimate) {
      _snapToFinal();
      return;
    }

    final isHero = _isHeroOrAbove(_chrome);

    if (isHero && widget.showDrawOn && _acquireCtrl != null) {
      if (!_acquireCtrl!.isAnimating && !_acquireCtrl!.isCompleted) {
        _acquireCtrl!.forward();
      }
    } else if (widget.showDrawOn && _drawOnCtrl != null) {
      if (!_drawOnCtrl!.isAnimating && !_drawOnCtrl!.isCompleted) {
        _drawOnCtrl!.forward();
        _drawOnCtrl!.addStatusListener(_onNonHeroDrawOnComplete);
      }
    } else if (widget.animate && _breathCtrl != null) {
      if (!_breathCtrl!.isAnimating) {
        _breathCtrl!.repeat();
      }
    }
  }

  void _onNonHeroDrawOnComplete(AnimationStatus s) {
    if (s != AnimationStatus.completed) return;
    _drawOnCtrl!.removeStatusListener(_onNonHeroDrawOnComplete);
    if (!mounted || _reduceMotion) return;
    _breathCtrl?.repeat();
  }

  @override
  void dispose() {
    // 1. Cancel pending timers (I-11).
    for (final t in _pendingTimers) {
      t.cancel();
    }
    _pendingTimers.clear();

    // 2. Stop all controllers before disposing (I-29).
    _vertexPopCtrl?.stop();
    _acquiredFlashCtrl?.stop();
    _drawOnCtrl?.stop();
    _bezelMorphCtrl?.stop();
    _acquireCtrl?.stop();
    _bezelDriftCtrl?.stop();
    _breathCtrl?.stop();

    // 2b. Remove status listeners defensively (I-29).
    _acquireCtrl?.removeStatusListener(_onAcquireComplete);
    _bezelMorphCtrl?.removeStatusListener(_onBezelMorphComplete);
    _drawOnCtrl?.removeStatusListener(_onDrawOnComplete);
    _drawOnCtrl?.removeStatusListener(_onNonHeroDrawOnComplete);
    _vertexPopCtrl?.removeStatusListener(_onVertexPopComplete);

    // 3. CurvedAnimations first, reverse creation order (I-15).
    _vertexPopCurve?.dispose();
    _drawOnCurve?.dispose();
    _bezelMorphCurve?.dispose();
    _acquireCurve?.dispose();

    // 4. Parent controllers.
    _vertexPopCtrl?.dispose();
    _acquiredFlashCtrl?.dispose();
    _drawOnCtrl?.dispose();
    _bezelMorphCtrl?.dispose();
    _acquireCtrl?.dispose();

    // 5. Ambient controllers last.
    _bezelDriftCtrl?.dispose();
    _breathCtrl?.dispose();

    super.dispose();
  }

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Semantics(
        label: _semanticLabel(),
        excludeSemantics: true,
        child: TweenAnimationBuilder<FramingValues>(
          tween: FramingValuesTween(
            begin: _prevValues,
            end: widget.values,
          ),
          duration: _reduceMotion ? Duration.zero : _kMorphDuration,
          curve: Curves.easeInOut,
          builder: (context, morphedValues, _) {
            return SizedBox(
              width: widget.size,
              height: widget.size,
              child: _buildAnimatedPaint(morphedValues),
            );
          },
        ),
      ),
    );
  }

  Widget _buildAnimatedPaint(FramingValues morphedValues) {
    // Note: _bezelDriftCtrl excluded from merge. It drives a
    // Transform.rotate on the chrome layer instead, so the heavy
    // geometry path never repaints for a rotation change (C1 fix).
    final listenables = <Listenable>[
      ?_breathCtrl,
      ?_acquireCtrl,
      ?_bezelMorphCtrl,
      ?_drawOnCtrl,
      ?_vertexPopCtrl,
      ?_acquiredFlashCtrl,
    ];

    if (listenables.isEmpty) {
      return _buildPaintStack(morphedValues);
    }

    return AnimatedBuilder(
      animation: Listenable.merge(listenables),
      builder: (context, _) => _buildPaintStack(morphedValues),
    );
  }

  Widget _buildPaintStack(FramingValues morphedValues) {
    final amplified = morphedValues.toAmplifiedList();
    final raw = morphedValues.toList();
    final isHero = _isHeroOrAbove(_chrome);

    // ── Animation values ──
    double breathingScale = 1.0;
    if (!_reduceMotion && widget.animate && _breathCtrl != null) {
      final t = _breathCtrl!.value;
      final wave = (math.sin(t * 2 * math.pi) + 1) / 2;
      breathingScale = 1.0 + wave * 0.03;
    }

    final acquireFraction =
        (_acquireCurve?.value ?? _acquireCtrl?.value) ?? 1.0;
    final bezelMorphFraction =
        (_bezelMorphCurve?.value ?? _bezelMorphCtrl?.value) ?? 1.0;
    final drawOnFraction =
        (_drawOnCurve?.value ?? _drawOnCtrl?.value) ?? 1.0;
    final vertexPopFraction =
        (_vertexPopCurve?.value ?? _vertexPopCtrl?.value) ?? 1.0;
    final acquiredFlash = _acquiredFlashCtrl?.value ?? 1.0;

    // Phosphor persistence: previous-frame glyph at reduced opacity.
    // Only visible during breathing, creates afterimage trail.
    final showPhosphor = isHero &&
        !_reduceMotion &&
        _breathCtrl != null &&
        _breathCtrl!.isAnimating;

    // Chrome painter (no bezelDriftAngle — rotation is decoupled).
    final chromePaint = CustomPaint(
      painter: _ChromePainter(
        chrome: _chrome,
        widgetSize: widget.size,
        amplifiedValues: amplified,
        acquireFraction: isHero ? acquireFraction : 1.0,
        bezelMorphFraction: isHero ? bezelMorphFraction : 1.0,
        vertexPopFraction: isHero ? vertexPopFraction : 1.0,
        acquiredFlash: isHero
            ? (1.0 - acquiredFlash).clamp(0.0, 1.0)
            : 0.0,
      ),
    );

    return Transform.scale(
      scale: breathingScale,
      child: Stack(
        children: [
          // Layer 0: Phosphor persistence trail (behind everything).
          if (showPhosphor)
            Positioned.fill(
              child: Transform.scale(
                scale: _kPhosphorScale,
                child: CustomPaint(
                  painter: _FingerprintPainter(
                    values: amplified,
                    rawValues: raw,
                    dominantIndex: morphedValues.dominantIndex,
                    hasClearDominant: morphedValues.hasClearDominant,
                    drawOnFraction: 1.0,
                    vertexPopFraction: 1.0,
                    widgetSize: widget.size,
                    opacityMultiplier: _kPhosphorOpacity / _kStrokeOpacity,
                  ),
                ),
              ),
            ),

          // Layer 1: Chrome (adaptive bezel, reticles, acquisition sweep).
          // Bezel drift rotation decoupled via Transform.rotate so
          // shouldRepaint returns false after entrance settles.
          // GPU composite only — zero geometry recalculation (C1 fix).
          if (_chrome != _ChromeDetail.none)
            Positioned.fill(
              child: _bezelDriftCtrl != null
                  ? AnimatedBuilder(
                      animation: _bezelDriftCtrl!,
                      builder: (_, _) {
                        final driftAngle = _bezelDriftCtrl!.value *
                            2 *
                            math.pi *
                            _kBezelDriftAmplitude /
                            360.0;
                        return Transform.rotate(
                          angle: _reduceMotion ? 0.0 : driftAngle,
                          child: chromePaint,
                        );
                      },
                    )
                  : chromePaint,
            ),

          // Layer 2: Core glyph.
          Positioned.fill(
            child: CustomPaint(
              painter: _FingerprintPainter(
                values: amplified,
                rawValues: raw,
                dominantIndex: morphedValues.dominantIndex,
                hasClearDominant: morphedValues.hasClearDominant,
                drawOnFraction: drawOnFraction,
                vertexPopFraction: vertexPopFraction,
                widgetSize: widget.size,
              ),
            ),
          ),

          // Layer 3: Whorl classifier at center (hero only, after draw-on).
          if (isHero && drawOnFraction >= 1.0)
            Positioned.fill(
              child: CustomPaint(
                painter: _WhorlPainter(
                  ringCount: morphedValues.whorlRingCount,
                  popFraction: vertexPopFraction,
                  widgetSize: widget.size,
                ),
              ),
            ),

          // Layer 4: Hero text overlays (TM, DTG, SIG, axis labels).
          if (isHero && bezelMorphFraction > 0.5)
            Positioned.fill(
              child: CustomPaint(
                painter: _HeroTextPainter(
                  chrome: _chrome,
                  widgetSize: widget.size,
                  opacity:
                      ((bezelMorphFraction - 0.5) * 2.0).clamp(0.0, 1.0),
                  dominantAxisLabel:
                      _kAxisLabels[morphedValues.dominantIndex]
                          .toUpperCase(),
                  textScaler: MediaQuery.textScalerOf(context),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _semanticLabel() {
    final v = widget.values;
    final list = v.toList();
    final strengths = <String>[];
    for (int i = 0; i < _kAxisCount; i++) {
      final pct = (list[i] * 100).round();
      strengths.add('${_kAxisLabels[i]} $pct%');
    }
    return 'Framing pattern glyph. '
        'Dominant axis: ${_kAxisLabels[v.dominantIndex]}. '
        'Axes: ${strengths.join(', ')}.';
  }
}

// ═══════════════════════════════════════════════════════════
// CHROME PAINTER (adaptive bezel + biometric acquisition)
// ═══════════════════════════════════════════════════════════

/// Paints the measurement chrome that wraps the glyph. Key innovation:
/// the bezel ring is NOT a perfect circle. It deforms to echo the
/// data shape at [_kBezelAdaptiveAmplitude], so the containment
/// vessel reflects the specimen it measured.
///
/// Compact tier: subtle echo ring (deformed at 8% amplitude).
/// Hero tier: full adaptive bezel with hashmarks, bifurcation
/// markers, registration dots, reticle corners, radial acquisition
/// sweep, and "ACQUIRED" flash.
class _ChromePainter extends CustomPainter {
  _ChromePainter({
    required this.chrome,
    required this.widgetSize,
    required this.amplifiedValues,
    required this.acquireFraction,
    required this.bezelMorphFraction,
    required this.vertexPopFraction,
    required this.acquiredFlash,
  });

  final _ChromeDetail chrome;
  final double widgetSize;
  final List<double> amplifiedValues;
  final double acquireFraction;
  final double bezelMorphFraction;
  final double vertexPopFraction;
  final double acquiredFlash;

  @override
  void paint(Canvas canvas, Size size) {
    if (chrome == _ChromeDetail.none) return;

    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2;

    if (chrome == _ChromeDetail.compact) {
      _paintCompactEchoRing(canvas, center, maxRadius);
      return;
    }

    // Hero layers.

    // Radial acquisition sweep (Phase 1).
    if (acquireFraction < 1.0) {
      _paintRadialAcquire(canvas, center, maxRadius);
    }

    // "ACQUIRED" flash (one-shot glow).
    if (acquiredFlash > 0.0) {
      _paintAcquiredFlash(canvas, center, maxRadius);
    }

    // Adaptive bezel + furniture (Phase 2+).
    // Drift rotation handled by Transform.rotate widget wrapper (C1 fix).
    if (bezelMorphFraction > 0.0) {
      _paintAdaptiveBezel(canvas, center, maxRadius);
      _paintAxisHashmarks(canvas, center, maxRadius);
      _paintInnerHairline(canvas, center, maxRadius);
      _paintRegistrationDots(canvas, center, maxRadius);

      // Bifurcation markers (after vertex pop starts).
      if (vertexPopFraction > 0.0) {
        _paintBifurcationMarkers(canvas, center, maxRadius);
      }

      _paintReticleCorners(canvas, size);
    }
  }

  // ── Compact: echo ring that deforms to match glyph shape ──
  void _paintCompactEchoRing(
      Canvas canvas, Offset center, double maxRadius) {
    final baseRadius = maxRadius * 0.92;
    final path = _buildAdaptiveRingPath(
      center,
      baseRadius,
      _kCompactAdaptiveAmplitude,
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5
      ..color = BaselineColors.teal.atOpacity(_kCompactRingOpacity);
    canvas.drawPath(path, paint);
  }

  // ── Radial acquisition sweep (center outward) ──
  void _paintRadialAcquire(
      Canvas canvas, Offset center, double maxRadius) {
    final sweepRadius = maxRadius * acquireFraction * 1.2;
    final fadeOpacity = 0.15 * (1.0 - acquireFraction);

    // Expanding ring.
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = BaselineColors.teal.atOpacity(fadeOpacity);
    canvas.drawCircle(center, sweepRadius, ringPaint);

    // Inner fill (acquisition field).
    final fieldPaint = Paint()
      ..style = PaintingStyle.fill
      ..shader = ui.Gradient.radial(
        center,
        sweepRadius,
        [
          BaselineColors.teal.atOpacity(fadeOpacity * 0.3),
          BaselineColors.teal.atOpacity(0.0),
        ],
      );
    canvas.drawCircle(center, sweepRadius, fieldPaint);
  }

  // ── "ACQUIRED" flash ──
  void _paintAcquiredFlash(
      Canvas canvas, Offset center, double maxRadius) {
    final paint = Paint()
      ..style = PaintingStyle.fill
      ..shader = ui.Gradient.radial(
        center,
        maxRadius * 0.6,
        [
          BaselineColors.teal
              .atOpacity(_kAcquiredFlashOpacity * acquiredFlash),
          BaselineColors.teal.atOpacity(0.0),
        ],
      );
    canvas.drawCircle(center, maxRadius * 0.6, paint);
  }

  // ── Adaptive bezel: ring that deforms to echo glyph shape ──
  void _paintAdaptiveBezel(
      Canvas canvas, Offset center, double maxRadius) {
    final bezelRadius = maxRadius - _kBezelGap;

    // Morph from perfect circle (0.0) to data-adaptive shape (1.0).
    final amplitude = _kBezelAdaptiveAmplitude * bezelMorphFraction;
    final path = _buildAdaptiveRingPath(center, bezelRadius, amplitude);

    // Apply instrument gap at 12 o'clock by clipping.
    final gapRad = _kInstrumentGapDegrees * math.pi / 180;
    final gapPath = Path()
      ..moveTo(center.dx, center.dy)
      ..lineTo(
        center.dx + (bezelRadius + 2) * math.cos(-math.pi / 2 - gapRad),
        center.dy + (bezelRadius + 2) * math.sin(-math.pi / 2 - gapRad),
      )
      ..lineTo(
        center.dx + (bezelRadius + 2) * math.cos(-math.pi / 2 + gapRad),
        center.dy + (bezelRadius + 2) * math.sin(-math.pi / 2 + gapRad),
      )
      ..close();

    canvas.save();
    // Clip out the instrument gap.
    canvas.clipPath(
      Path.combine(PathOperation.difference,
          Path()..addRect(Offset.zero & Size(widgetSize, widgetSize)),
          gapPath),
    );

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _kBezelStrokeWidth
      ..strokeCap = StrokeCap.round
      ..color = BaselineColors.teal
          .atOpacity(_kBezelOpacity * bezelMorphFraction);
    canvas.drawPath(path, paint);
    canvas.restore();
  }

  /// Builds a closed path that follows a circle but deforms toward
  /// each axis data point at the given [amplitude].
  ///
  /// amplitude 0.0 = perfect circle.
  /// amplitude 0.15 = 15% pull toward data shape.
  /// Uses the same 5-axis radial layout as the glyph.
  Path _buildAdaptiveRingPath(
    Offset center,
    double baseRadius,
    double amplitude,
  ) {
    // Sample 60 points around the circle, interpolating radius
    // toward each axis value based on angular proximity.
    const sampleCount = 60;
    final points = <Offset>[];

    for (int s = 0; s < sampleCount; s++) {
      final angle =
          -math.pi / 2 + (2 * math.pi / sampleCount) * s;

      // Compute weighted influence from each axis.
      double dataInfluence = 0.0;
      double weightSum = 0.0;
      for (int a = 0; a < _kAxisCount; a++) {
        final axisAngle =
            -math.pi / 2 + (2 * math.pi / _kAxisCount) * a;
        // Angular distance (0 to pi).
        var diff = (angle - axisAngle).abs();
        if (diff > math.pi) diff = 2 * math.pi - diff;
        // Gaussian weight: closer axes have more influence.
        final weight = math.exp(-diff * diff * 3.0);
        dataInfluence += amplifiedValues[a] * weight;
        weightSum += weight;
      }
      if (weightSum > 0) dataInfluence /= weightSum;

      // Blend: circle radius + data pull.
      final r = baseRadius * (1.0 + amplitude * (dataInfluence - 0.5));
      points.add(Offset(
        center.dx + r * math.cos(angle),
        center.dy + r * math.sin(angle),
      ));
    }

    // Smooth path through sampled points.
    final path = Path();
    for (int i = 0; i <= sampleCount; i++) {
      final idx = i % sampleCount;
      if (i == 0) {
        path.moveTo(points[idx].dx, points[idx].dy);
      } else {
        // Smooth with quadratic bezier using midpoints.
        final prev = points[(i - 1) % sampleCount];
        final curr = points[idx];
        final mid = Offset(
          (prev.dx + curr.dx) / 2,
          (prev.dy + curr.dy) / 2,
        );
        if (i == 1) {
          path.lineTo(mid.dx, mid.dy);
        } else {
          path.quadraticBezierTo(prev.dx, prev.dy, mid.dx, mid.dy);
        }
      }
    }
    path.close();
    return path;
  }

  // ── Axis hashmarks on adaptive bezel ──
  void _paintAxisHashmarks(
      Canvas canvas, Offset center, double maxRadius) {
    final bezelRadius = maxRadius - _kBezelGap;

    // Major ticks at 5 axis positions.
    final majorPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..strokeCap = StrokeCap.round
      ..color = BaselineColors.teal
          .atOpacity(_kBezelHashOpacity * bezelMorphFraction);

    for (int i = 0; i < _kAxisCount; i++) {
      final angle = -math.pi / 2 + (2 * math.pi / _kAxisCount) * i;
      // Adaptive offset: hashmark moves with the deformed bezel.
      final dataInfluence = amplifiedValues[i];
      final adaptiveR = bezelRadius *
          (1.0 + _kBezelAdaptiveAmplitude *
              bezelMorphFraction *
              (dataInfluence - 0.5));
      final innerR = adaptiveR - _kBezelHashLength;
      final outerR = adaptiveR + 1.0;
      canvas.drawLine(
        Offset(
          center.dx + innerR * math.cos(angle),
          center.dy + innerR * math.sin(angle),
        ),
        Offset(
          center.dx + outerR * math.cos(angle),
          center.dy + outerR * math.sin(angle),
        ),
        majorPaint,
      );
    }

    // Minor ticks: 2 between each axis.
    final minorPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5
      ..strokeCap = StrokeCap.round
      ..color = BaselineColors.teal
          .atOpacity(_kBezelHashOpacity * 0.4 * bezelMorphFraction);

    for (int i = 0; i < _kAxisCount; i++) {
      for (int m = 1; m <= 2; m++) {
        final angle = -math.pi / 2 +
            (2 * math.pi / _kAxisCount) * (i + m / 3.0);
        final innerR = bezelRadius - _kBezelHashLength * 0.5;
        canvas.drawLine(
          Offset(
            center.dx + innerR * math.cos(angle),
            center.dy + innerR * math.sin(angle),
          ),
          Offset(
            center.dx + bezelRadius * math.cos(angle),
            center.dy + bezelRadius * math.sin(angle),
          ),
          minorPaint,
        );
      }
    }
  }

  // ── Inner hairline ring ──
  void _paintInnerHairline(
      Canvas canvas, Offset center, double maxRadius) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.3
      ..color = BaselineColors.teal
          .atOpacity(_kInnerHairlineOpacity * bezelMorphFraction);
    canvas.drawCircle(center, maxRadius * 0.85 * 0.5, paint);
  }

  // ── Registration dots at axis/bezel intersections ──
  void _paintRegistrationDots(
      Canvas canvas, Offset center, double maxRadius) {
    final bezelRadius = maxRadius - _kBezelGap;
    final paint = Paint()
      ..style = PaintingStyle.fill
      ..color = BaselineColors.teal
          .atOpacity(_kRegistrationDotOpacity * vertexPopFraction);

    for (int i = 0; i < _kAxisCount; i++) {
      final angle = -math.pi / 2 + (2 * math.pi / _kAxisCount) * i;
      final dataInfluence = amplifiedValues[i];
      final adaptiveR = bezelRadius *
          (1.0 + _kBezelAdaptiveAmplitude *
              bezelMorphFraction *
              (dataInfluence - 0.5));
      canvas.drawCircle(
        Offset(
          center.dx + adaptiveR * math.cos(angle),
          center.dy + adaptiveR * math.sin(angle),
        ),
        _kRegistrationDotRadius,
        paint,
      );
    }
  }

  // ── Bifurcation markers (V-shaped divergence ticks at vertices) ──
  void _paintBifurcationMarkers(
      Canvas canvas, Offset center, double maxRadius) {
    final dataRadius = maxRadius * 0.85;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.7
      ..strokeCap = StrokeCap.round
      ..color = BaselineColors.teal
          .atOpacity(_kBifurcationOpacity * vertexPopFraction);

    for (int i = 0; i < _kAxisCount; i++) {
      final axisAngle =
          -math.pi / 2 + (2 * math.pi / _kAxisCount) * i;
      final dataR = dataRadius * amplifiedValues[i];
      final vertexPos = Offset(
        center.dx + dataR * math.cos(axisAngle),
        center.dy + dataR * math.sin(axisAngle),
      );

      // V spread angle scales with data value: higher value = wider V.
      // Communicates: "this axis diverges more from flat distribution."
      final spreadAngle =
          _kBifurcationSpread * amplifiedValues[i];
      final bifLen = _kBifurcationLength * vertexPopFraction;

      // Left branch.
      final leftAngle = axisAngle + spreadAngle;
      canvas.drawLine(
        vertexPos,
        Offset(
          vertexPos.dx + bifLen * math.cos(leftAngle),
          vertexPos.dy + bifLen * math.sin(leftAngle),
        ),
        paint,
      );

      // Right branch.
      final rightAngle = axisAngle - spreadAngle;
      canvas.drawLine(
        vertexPos,
        Offset(
          vertexPos.dx + bifLen * math.cos(rightAngle),
          vertexPos.dy + bifLen * math.sin(rightAngle),
        ),
        paint,
      );
    }
  }

  // ── Reticle corners ──
  void _paintReticleCorners(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _kReticleStrokeWidth
      ..strokeCap = StrokeCap.square
      ..color = BaselineColors.teal
          .atOpacity(_kReticleOpacity * bezelMorphFraction);

    final w = size.width;
    final h = size.height;
    final l = _kReticleLength;
    const inset = 1.0;

    // Top-left.
    canvas.drawLine(
        Offset(inset, inset), Offset(inset + l, inset), paint);
    canvas.drawLine(
        Offset(inset, inset), Offset(inset, inset + l), paint);
    // Top-right.
    canvas.drawLine(
        Offset(w - inset, inset), Offset(w - inset - l, inset), paint);
    canvas.drawLine(
        Offset(w - inset, inset), Offset(w - inset, inset + l), paint);
    // Bottom-left.
    canvas.drawLine(
        Offset(inset, h - inset), Offset(inset + l, h - inset), paint);
    canvas.drawLine(
        Offset(inset, h - inset), Offset(inset, h - inset - l), paint);
    // Bottom-right (detail only).
    if (chrome == _ChromeDetail.detail) {
      canvas.drawLine(Offset(w - inset, h - inset),
          Offset(w - inset - l, h - inset), paint);
      canvas.drawLine(Offset(w - inset, h - inset),
          Offset(w - inset, h - inset - l), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ChromePainter old) =>
      chrome != old.chrome ||
      widgetSize != old.widgetSize ||
      acquireFraction != old.acquireFraction ||
      bezelMorphFraction != old.bezelMorphFraction ||
      vertexPopFraction != old.vertexPopFraction ||
      acquiredFlash != old.acquiredFlash ||
      !_listEq(amplifiedValues, old.amplifiedValues);

  bool _listEq(List<double> a, List<double> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

// ═══════════════════════════════════════════════════════════
// WHORL CLASSIFIER PAINTER
// ═══════════════════════════════════════════════════════════

/// Paints concentric micro-rings at the center of hero-size glyphs.
/// Ring count reflects dominant axis strength:
///   3 rings = strong dominant (>= 0.6)
///   2 rings = moderate (>= 0.35)
///   1 ring  = flat / no clear dominant
///
/// Users won't consciously count rings. They perceive that some
/// fingerprints have a denser, more defined core pattern. This is
/// a real data signal, not decoration.
class _WhorlPainter extends CustomPainter {
  _WhorlPainter({
    required this.ringCount,
    required this.popFraction,
    required this.widgetSize,
  });

  final int ringCount;
  final double popFraction;
  final double widgetSize;

  @override
  void paint(Canvas canvas, Size size) {
    if (popFraction <= 0.0) return;

    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _kWhorlRingStrokeWidth;

    for (int i = 0; i < ringCount; i++) {
      final radius = _kCenterDotRadius +
          _kWhorlRingSpacing * (i + 1) * popFraction;
      // Opacity decreases outward: inner ring most visible.
      final opacity = (0.30 - i * 0.08).clamp(0.06, 0.30) * popFraction;
      paint.color = BaselineColors.teal.atOpacity(opacity);
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _WhorlPainter old) =>
      ringCount != old.ringCount ||
      popFraction != old.popFraction;
}

// ═══════════════════════════════════════════════════════════
// HERO TEXT PAINTER (TM footer, DTG, SIG, axis labels, classification)
// ═══════════════════════════════════════════════════════════

/// Paints micro-text overlays for hero sizes.
///
/// Profile (80px): TM footer only.
/// Detail (120px): TM footer + DTG + SIG + axis abbreviations
/// at bezel hashmarks + "SPECIMEN: [DOMINANT]" classification.
///
/// Uses Flutter TextStyle with raw 'JetBrainsMono' string per I-10.
/// TextScaler injected for accessibility (I-31).
class _HeroTextPainter extends CustomPainter {
  _HeroTextPainter({
    required this.chrome,
    required this.widgetSize,
    required this.opacity,
    required this.dominantAxisLabel,
    required this.textScaler,
  });

  final _ChromeDetail chrome;
  final double widgetSize;
  final double opacity;
  final String dominantAxisLabel;
  final TextScaler textScaler;

  @override
  void paint(Canvas canvas, Size size) {
    if (opacity <= 0.0) return;

    final isDetail = chrome == _ChromeDetail.detail;
    final fontSize = isDetail ? 7.0 : 6.0;
    final bottomY = size.height - 2.0;

    // TM footer: "FRAMING FINGERPRINT" centered.
    _drawText(
      canvas,
      'FRAMING FINGERPRINT',
      Offset(size.width / 2, bottomY),
      fontSize,
      BaselineColors.teal.atOpacity(0.12 * opacity),
      align: TextAlign.center,
    );

    if (!isDetail) return;

    // ── Detail-only elements (120px) ──

    // DTG timestamp (bottom-left, above TM footer).
    final now = DateTime.now();
    final dtg =
        '${now.day.toString().padLeft(2, '0')}${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}Z';
    _drawText(
      canvas,
      dtg,
      Offset(4.0, bottomY - fontSize - 4.0),
      5.5,
      BaselineColors.teal.atOpacity(0.08 * opacity),
    );

    // SIG hash (bottom-right, above TM footer).
    _drawText(
      canvas,
      'SIG:FP01',
      Offset(size.width - 4.0, bottomY - fontSize - 4.0),
      5.5,
      BaselineColors.teal.atOpacity(0.08 * opacity),
      align: TextAlign.right,
    );

    // Classification box (top-left).
    _drawText(
      canvas,
      'SPECIMEN: $dominantAxisLabel',
      const Offset(4.0, 4.0),
      5.5,
      BaselineColors.teal.atOpacity(0.10 * opacity),
    );

    // Axis abbreviations at bezel hashmark positions.
    final center = Offset(size.width / 2, size.height / 2);
    final labelRadius = (size.width / 2) - 1.0;

    for (int i = 0; i < _kAxisCount; i++) {
      final angle =
          -math.pi / 2 + (2 * math.pi / _kAxisCount) * i;
      final labelPos = Offset(
        center.dx + labelRadius * math.cos(angle),
        center.dy + labelRadius * math.sin(angle),
      );

      // Determine text alignment based on position.
      TextAlign labelAlign;
      if (angle.abs() < 0.1 || (angle - math.pi).abs() < 0.1) {
        labelAlign = TextAlign.center;
      } else if (math.cos(angle) > 0) {
        labelAlign = TextAlign.left;
      } else {
        labelAlign = TextAlign.right;
      }

      _drawText(
        canvas,
        _kAxisAbbreviations[i],
        labelPos,
        5.0,
        BaselineColors.teal.atOpacity(0.14 * opacity),
        align: labelAlign,
      );
    }
  }

  void _drawText(
    Canvas canvas,
    String text,
    Offset position,
    double fontSize,
    Color color, {
    TextAlign align = TextAlign.left,
  }) {
    final scaledFontSize = textScaler.scale(fontSize);
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: BaselineTypography.monoFontFamily,
          fontSize: scaledFontSize,
          color: color,
          letterSpacing: 0.5,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    painter.layout();

    double dx;
    switch (align) {
      case TextAlign.center:
        dx = position.dx - painter.width / 2;
      case TextAlign.right:
        dx = position.dx - painter.width;
      default:
        dx = position.dx;
    }

    painter.paint(canvas, Offset(dx, position.dy));
    painter.dispose(); // I-23
  }

  @override
  bool shouldRepaint(covariant _HeroTextPainter old) =>
      chrome != old.chrome ||
      widgetSize != old.widgetSize ||
      opacity != old.opacity ||
      dominantAxisLabel != old.dominantAxisLabel ||
      textScaler != old.textScaler;
}

// ═══════════════════════════════════════════════════════════
// CORE GLYPH PAINTER
// ═══════════════════════════════════════════════════════════

/// Paints the radial glyph: the actual biometric identity mark.
///
/// Layers (bottom to top):
///   1. Skeleton spokes (>= 60px only)
///   2. Contour ridges (3 nested scaled glyph outlines)
///   3. Filled glyph (radial gradient teal)
///   4. Glyph stroke (crisp teal outline)
///   5. Vertex dots (>= 48px, scaled by vertexPopFraction)
///   6. Dominant axis hotspot (glow bloom)
///   7. Center dot
class _FingerprintPainter extends CustomPainter {
  _FingerprintPainter({
    required this.values,
    required this.rawValues,
    required this.dominantIndex,
    required this.hasClearDominant,
    required this.drawOnFraction,
    required this.vertexPopFraction,
    required this.widgetSize,
    this.opacityMultiplier = 1.0,
  });

  final List<double> values;
  final List<double> rawValues;
  final int dominantIndex;
  final bool hasClearDominant;
  final double drawOnFraction;
  final double vertexPopFraction;
  final double widgetSize;

  /// Global opacity scale for phosphor persistence trail.
  /// 1.0 = normal. < 1.0 = ghost afterimage.
  final double opacityMultiplier;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2 * 0.85;

    final dataPoints = _computeDataPoints(center, maxRadius, values);
    final glyphPath = _buildSplinePath(dataPoints);

    if (drawOnFraction < 1.0) {
      canvas.save();
      _applyDrawOnClip(canvas, center, maxRadius);
    }

    // Layer 1: Skeleton spokes.
    if (widgetSize >= _kSkeletonVisibleThreshold) {
      _paintSkeleton(canvas, center, maxRadius);
    }

    // Layer 2: Contour ridges.
    _paintContourRidges(canvas, center, dataPoints);

    // Layer 3: Filled glyph.
    _paintFill(canvas, center, maxRadius, glyphPath);

    // Layer 4: Glyph stroke.
    _paintStroke(canvas, glyphPath);

    if (drawOnFraction < 1.0) {
      canvas.restore();
    }

    // Layer 5: Vertex dots.
    if (widgetSize >= _kVertexVisibleThreshold && vertexPopFraction > 0.0) {
      _paintVertices(canvas, dataPoints);
    }

    // Layer 6: Dominant axis hotspot.
    if (hasClearDominant && vertexPopFraction > 0.0) {
      _paintHotspot(canvas, dataPoints[dominantIndex]);
    }

    // Layer 7: Center dot.
    _paintCenterDot(canvas, center);
  }

  List<Offset> _computeDataPoints(
    Offset center,
    double maxRadius,
    List<double> vals,
  ) {
    final points = <Offset>[];
    for (int i = 0; i < _kAxisCount; i++) {
      final angle = -math.pi / 2 + (2 * math.pi / _kAxisCount) * i;
      final r = maxRadius * vals[i];
      points.add(Offset(
        center.dx + r * math.cos(angle),
        center.dy + r * math.sin(angle),
      ));
    }
    return points;
  }

  Path _buildSplinePath(List<Offset> points) {
    final path = Path();
    final n = points.length;
    final totalSegments = n * _kSplineSegments;
    for (int seg = 0; seg <= totalSegments; seg++) {
      final t = seg / totalSegments;
      final segFloat = t * n;
      final i = segFloat.floor() % n;
      final localT = segFloat - segFloat.floor();
      final p0 = points[(i - 1 + n) % n];
      final p1 = points[i];
      final p2 = points[(i + 1) % n];
      final p3 = points[(i + 2) % n];
      final pt = _catmullRom(p0, p1, p2, p3, localT, _kSplineTension);
      if (seg == 0) {
        path.moveTo(pt.dx, pt.dy);
      } else {
        path.lineTo(pt.dx, pt.dy);
      }
    }
    path.close();
    return path;
  }

  Offset _catmullRom(
    Offset p0,
    Offset p1,
    Offset p2,
    Offset p3,
    double t,
    double tension,
  ) {
    final alpha = 1.0 - tension;
    final t2 = t * t;
    final t3 = t2 * t;
    double interp(double v0, double v1, double v2, double v3) {
      return 0.5 *
          ((2 * v1) +
              (-v0 + v2) * alpha * t +
              (2 * v0 - 5 * v1 + 4 * v2 - v3) * alpha * t2 +
              (-v0 + 3 * v1 - 3 * v2 + v3) * alpha * t3);
    }

    return Offset(
      interp(p0.dx, p1.dx, p2.dx, p3.dx),
      interp(p0.dy, p1.dy, p2.dy, p3.dy),
    );
  }

  void _applyDrawOnClip(Canvas canvas, Offset center, double maxRadius) {
    final clipPath = Path()
      ..addArc(
        Rect.fromCircle(center: center, radius: maxRadius * 1.2),
        -math.pi / 2,
        2 * math.pi * drawOnFraction,
      )
      ..lineTo(center.dx, center.dy)
      ..close();
    canvas.clipPath(clipPath);
  }

  void _paintSkeleton(Canvas canvas, Offset center, double maxRadius) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5
      ..color = BaselineColors.teal
          .atOpacity(_kSkeletonOpacity * opacityMultiplier);
    for (int i = 0; i < _kAxisCount; i++) {
      final angle = -math.pi / 2 + (2 * math.pi / _kAxisCount) * i;
      final end = Offset(
        center.dx + maxRadius * math.cos(angle),
        center.dy + maxRadius * math.sin(angle),
      );
      canvas.drawLine(center, end, paint);
    }
  }

  void _paintContourRidges(
    Canvas canvas,
    Offset center,
    List<Offset> outerPoints,
  ) {
    for (int r = 0; r < _kRidgeCount; r++) {
      final scale = _kRidgeScales[r];
      final opacity = _kRidgeOpacities[r] * opacityMultiplier;
      final ridgePoints = outerPoints
          .map((pt) => Offset(
                center.dx + (pt.dx - center.dx) * scale,
                center.dy + (pt.dy - center.dy) * scale,
              ))
          .toList();
      final ridgePath = _buildSplinePath(ridgePoints);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _kRidgeStrokeWidth
        ..strokeJoin = StrokeJoin.round
        ..color = BaselineColors.teal.atOpacity(opacity);
      canvas.drawPath(ridgePath, paint);
    }
  }

  void _paintFill(
    Canvas canvas,
    Offset center,
    double maxRadius,
    Path glyphPath,
  ) {
    final gradient = ui.Gradient.radial(
      center,
      maxRadius,
      [
        BaselineColors.teal
            .atOpacity(_kFillOpacityCenter * opacityMultiplier),
        BaselineColors.teal
            .atOpacity(_kFillOpacityEdge * opacityMultiplier),
      ],
    );
    final paint = Paint()
      ..style = PaintingStyle.fill
      ..shader = gradient;
    canvas.drawPath(glyphPath, paint);
  }

  void _paintStroke(Canvas canvas, Path glyphPath) {
    final strokeWidth = math.max(
      _kStrokeWidthMin,
      _kStrokeWidthBase * (widgetSize / 80.0),
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeJoin = StrokeJoin.round
      ..color = BaselineColors.teal
          .atOpacity(_kStrokeOpacity * opacityMultiplier);
    canvas.drawPath(glyphPath, paint);
  }

  void _paintVertices(Canvas canvas, List<Offset> points) {
    final scaledRadius = _kVertexRadius * vertexPopFraction;
    if (scaledRadius <= 0.0) return;

    final paint = Paint()
      ..style = PaintingStyle.fill
      ..color = BaselineColors.teal.atOpacity(
        _kVertexOpacity * vertexPopFraction * opacityMultiplier,
      );
    for (int i = 0; i < points.length; i++) {
      if (i == dominantIndex && hasClearDominant) continue;
      canvas.drawCircle(points[i], scaledRadius, paint);
    }
  }

  void _paintHotspot(Canvas canvas, Offset vertex) {
    final scaledBlur = _kHotspotBlurSigma * vertexPopFraction;
    final scaledRadius = _kHotspotRadius * vertexPopFraction;

    final glowPaint = Paint()
      ..style = PaintingStyle.fill
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, scaledBlur)
      ..color = BaselineColors.teal.atOpacity(
        _kHotspotOpacity * vertexPopFraction * opacityMultiplier,
      );
    canvas.drawCircle(vertex, scaledRadius, glowPaint);

    final dotPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = BaselineColors.teal
          .atOpacity(0.9 * vertexPopFraction * opacityMultiplier);
    canvas.drawCircle(
        vertex, _kVertexRadius * vertexPopFraction, dotPaint);
  }

  void _paintCenterDot(Canvas canvas, Offset center) {
    final paint = Paint()
      ..style = PaintingStyle.fill
      ..color = BaselineColors.teal
          .atOpacity(_kCenterDotOpacity * opacityMultiplier);
    canvas.drawCircle(center, _kCenterDotRadius, paint);
  }

  @override
  bool shouldRepaint(covariant _FingerprintPainter old) =>
      drawOnFraction != old.drawOnFraction ||
      vertexPopFraction != old.vertexPopFraction ||
      widgetSize != old.widgetSize ||
      dominantIndex != old.dominantIndex ||
      hasClearDominant != old.hasClearDominant ||
      opacityMultiplier != old.opacityMultiplier ||
      !_listEquals(values, old.values) ||
      !_listEquals(rawValues, old.rawValues);

  bool _listEquals(List<double> a, List<double> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
