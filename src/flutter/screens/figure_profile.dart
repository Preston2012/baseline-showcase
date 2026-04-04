/// F4.8 -- Figure Profile Screen (Classified Personnel Record)
///
/// LOCKED: 148 treatments. Dual-mode with full dossier wrapper.
///
/// PROFILE MODE (Core): Classified personnel file. Baseline™ gauge
/// with glow bloom, activity classification badge, military DTG,
/// subject ID, code designation, framing distribution bars, timeline
/// spine, section data bus, intel sparkline. 113 profile-mode treatments.
///
/// DOSSIER MODE (Pro+/B2B): Clearance verification entrance (blur
/// dissolve + stamp cascade + haptic sequence), classified access
/// header (session timer, pipeline dots, Baseline™ secondary, session
/// integrity), DossierPlate (FG-8a, 82 treatments), re-seal exit.
/// 35 wrapper treatments around the plate's 82.
///
/// Path: lib/screens/figure_profile.dart
library;

// 1. Dart SDK
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

// 2. Flutter
import 'package:flutter/material.dart';

// 3. Third-party
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

// 4. Config
import 'package:baseline_app/config/routes.dart';
import 'package:baseline_app/config/theme.dart';

// 5. Models / Services
import 'package:baseline_app/models/figure.dart';
import 'package:baseline_app/models/feed_statement.dart';
import 'package:baseline_app/services/figures_service.dart';
import 'package:baseline_app/services/supabase_client.dart';

// 6. Providers
import 'package:baseline_app/providers/figures_provider.dart';

// 7. Widgets
import 'package:baseline_app/widgets/baseline_icons.dart';
import 'package:baseline_app/widgets/feature_gate.dart';
import 'package:baseline_app/widgets/framing_fingerprint.dart';
import 'package:baseline_app/widgets/info_bottom_sheet.dart';
import 'package:baseline_app/widgets/shimmer_loading.dart';
import 'package:baseline_app/widgets/statement_card.dart';
import 'package:baseline_app/widgets/tier_badge.dart';
import 'package:baseline_app/widgets/dossier_plate.dart';

// 8. Popups
import 'package:baseline_app/widgets/rate_app_popup.dart';
import 'package:baseline_app/widgets/soft_paywall_popup.dart';
import 'package:baseline_app/config/tier_feature_map.dart';

// 9. Utils
import 'package:baseline_app/utils/haptic_util.dart';

// ═══════════════════════════════════════════════════════════
// PROVIDERS
// ═══════════════════════════════════════════════════════════

/// Baseline score provider, keyed by figureId.
/// Returns a computed baseline score (0-100) for the figure.
final baselineScoreProvider = FutureProvider.family<double, String>(
  (ref, figureId) async {
    final response = await supabase.functions.invoke(
      'get-baseline-score',
      body: {'figure_ids': [figureId]},
    );
    final data = response.data as Map<String, dynamic>?;
    final scores = data?['scores'] as List<dynamic>?;
    if (scores != null && scores.isNotEmpty) {
      return (scores.first['baseline_score'] as num?)?.toDouble() ?? 0.0;
    }
    return 0.0;
  },
);

// ═══════════════════════════════════════════════════════════
// HELPERS
// ═══════════════════════════════════════════════════════════

/// Converts raw category DB strings to human-readable display format.
String _formatCategory(String category) {
  switch (category) {
    case 'US_POLITICS': return 'US Politics';
    case 'GLOBAL_POLITICS': return 'Global Politics';
    case 'AI_TECH': return 'AI / Technology';
    case 'FINANCE': return 'Finance';
    case 'CRYPTO': return 'Crypto';
    case 'MEDIA_CULTURE': return 'Media / Culture';
    case 'CENTRAL_BANK': return 'Central Banks';
    default: return category.replaceAll('_', ' ').toLowerCase().split(' ')
        .map((w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : '')
        .join(' ');
  }
}

/// Converts raw topic enum strings to human-readable display names.
String _topicDisplay(String raw) {
  const names = {
    'US_POLITICS': 'US Politics',
    'FOREIGN_POLICY': 'Foreign Policy',
    'CULTURE_SOCIETY': 'Culture & Society',
    'CLIMATE_ENVIRONMENT': 'Climate & Environment',
    'MILITARY_DEFENSE': 'Military & Defense',
    'AI_TECHNOLOGY': 'AI & Technology',
    'ECONOMY': 'Economy',
    'IMMIGRATION': 'Immigration',
    'HEALTHCARE': 'Healthcare',
    'CRIME_JUSTICE': 'Crime & Justice',
    'ELECTIONS': 'Elections',
    'EDUCATION': 'Education',
    'OTHER': 'Other',
  };
  return names[raw] ?? raw.replaceAll('_', ' ').split(' ').map((w) =>
      w.isEmpty ? '' : '${w[0]}${w.substring(1).toLowerCase()}').join(' ');
}

// ═══════════════════════════════════════════════════════════
// CONSTANTS
// ═══════════════════════════════════════════════════════════

/// Master entrance duration.
const Duration _kEntranceDuration = Duration(milliseconds: 1600);

/// Gauge score sweep.
const Duration _kGaugeDuration = Duration(milliseconds: 600);

/// Entry scanline beam.
const Duration _kScanlineDuration = Duration(milliseconds: 500);

/// Ambient right-border pulse cycle.
const Duration _kPulseDuration = Duration(milliseconds: 4000);

/// Ambient scanline repeat interval.
const Duration _kAmbientScanDuration = Duration(milliseconds: 8000);

/// Avatar active pulse (6 finite cycles).
const Duration _kActivePulseDuration = Duration(milliseconds: 1200);

/// Count-up animation.
const Duration _kCountUpDuration = Duration(milliseconds: 400);

/// Monitoring text pulse cycle.
const Duration _kMonitorPulseDuration = Duration(milliseconds: 6000);

/// Dossier clearance verification.
const Duration _kClearanceDuration = Duration(milliseconds: 1200);

/// Dossier blur dissolve.
const Duration _kBlurDuration = Duration(milliseconds: 800);

/// Dossier stamp cascade.
const Duration _kStampDuration = Duration(milliseconds: 600);

/// Dossier re-seal.
const Duration _kResealDuration = Duration(milliseconds: 300);

/// Session timer tick.
const Duration _kSessionTimerInterval = Duration(seconds: 1);

/// Maximum blur sigma for dossier entrance.
const double _kMaxBlurSigma = 12.0;

/// Re-seal sigma.
const double _kResealSigma = 8.0;

/// Film perforation dimensions.
const double _kPerfWidth = 6.0;
const double _kPerfHeight = 3.0;
const double _kPerfSpacing = 8.0;

/// Gauge track height.
const double _kGaugeTrackHeight = 4.0;

/// Timeline dot range.
const double _kTimelineDotMin = 3.0;
const double _kTimelineDotMax = 5.0;

/// Data bus opacity.
const double _kDataBusOpacity = 0.06;

/// Junction dot radius.
const double _kJunctionDotRadius = 3.0;

/// Avatar size.
const double _kAvatarSize = 120.0;

/// Idle timeout before ambient tickers rest (A2-S1).
const Duration _kIdleTimeout = Duration(seconds: 25);

// ═══════════════════════════════════════════════════════════
// SCREEN WIDGET
// ═══════════════════════════════════════════════════════════

class FigureProfileScreen extends ConsumerStatefulWidget {
  const FigureProfileScreen({
    super.key,
    required this.figureId,
    this.isDossierMode = false,
  });

  final String figureId;
  final bool isDossierMode;

  @override
  ConsumerState<FigureProfileScreen> createState() =>
      _FigureProfileScreenState();
}

class _FigureProfileScreenState extends ConsumerState<FigureProfileScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  // ── Provider subscription (I-77) ──
  ProviderSubscription<AsyncValue<Figure>>? _providerSub;

  // ── Pending timers (I-11) ──
  final List<Timer> _pendingTimers = [];

  // ── Reduce motion (A2-C1: PlatformDispatcher, not MediaQuery) ──
  bool _reduceMotion = false;
  bool _wasReduced = false; // A2-MS1: transition guard.

  // ── Safe padding ──
  EdgeInsets _safePadding = EdgeInsets.zero;

  // ── Data ──
  Figure? _figure;
  double? _baselineScore;
  int _statementCount = 0;
  List<FeedStatement> _recentStatements = [];
  FigureProfileData? _profileData;
  bool _isLoading = true;
  bool _hasError = false;

  // ── Profile Mode Controllers (8) ──
  late final AnimationController _entranceCtrl;
  late final AnimationController _gaugeCtrl;
  late final AnimationController _scanlineCtrl;
  late final AnimationController _pulseCtrl;
  late final AnimationController _ambientScanCtrl;
  late final AnimationController _activePulseCtrl;
  late final AnimationController _countUpCtrl;
  late final AnimationController _monitorPulseCtrl;

  // ── Calibrating state controller ──
  late final AnimationController _calibrateCtrl;

  // ── Profile CurvedAnimations (I-15) ──
  late final CurvedAnimation _entranceCurve;
  late final CurvedAnimation _gaugeCurve;
  late final CurvedAnimation _scanlineCurve;
  late final CurvedAnimation _countUpCurve;
  late final CurvedAnimation _activePulseCurve;
  late final CurvedAnimation _ambientScanCurve;

  // ── Dossier Mode Controllers (5) ──
  late final AnimationController _clearanceCtrl;
  late final AnimationController _blurCtrl;
  late final AnimationController _stampCtrl;
  late final AnimationController _resealCtrl;
  Timer? _sessionTimer;
  final Stopwatch _sessionStopwatch = Stopwatch();

  // ── Dossier CurvedAnimations (I-15) ──
  late final CurvedAnimation _clearanceCurve;
  late final CurvedAnimation _blurCurve;
  late final CurvedAnimation _stampCurve;
  late final CurvedAnimation _resealCurve;

  // ── Dossier state ──
  String _sessionElapsed = '00:00';
  bool _hasSeenDossierEntrance = false;
  bool _isResealing = false;

  // ── Computed intel (cached, I-45) ──
  String _activityDesignation = 'SILENT';
  String _activityDot = '\u25CC'; // ◌
  double _activityDotOpacity = 0.2;
  String _lastSeenDtg = '';
  String _lastSeenHuman = '';
  String _subjectId = '';
  String _codeDesignation = '';
  String _confidenceLevel = 'LOW';
  double _confidenceFill = 0.15;
  double _confidenceOpacity = 0.1;
  String _fingerprintHash = ''; // Cherry 142
  String _accessDtg = ''; // Cherry 139
  List<double> _sparklineData = []; // Cherry 143

  // ── Computed from _recentStatements ──
  double? get _computedAvgPulse {
    if (_recentStatements.isEmpty) return null;
    var sum = 0.0;
    var count = 0;
    for (final s in _recentStatements) {
      if (s.signalRank != null) {
        sum += s.signalRank!;
        count++;
      }
    }
    return count > 0 ? sum / count : null;
  }

  String? get _computedTopTopic {
    if (_recentStatements.isEmpty) return null;
    final freq = <String, int>{};
    for (final s in _recentStatements) {
      for (final t in s.topics ?? <String>[]) {
        freq[t] = (freq[t] ?? 0) + 1;
      }
    }
    if (freq.isEmpty) return null;
    return freq.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }

  // ── TextScaler (I-28/I-44) ──
  TextScaler _textScaler = TextScaler.noScaling;

  // ── Pre-computed TextPainters for chrome (A2-C2) ──
  TextPainter? _tpFileTab;
  TextPainter? _tpHandling;
  TextPainter? _tpSerial;
  TextPainter? _tpAccessLog;

  // ── Idle timeout (A2-S1) ──
  Timer? _idleTimer;
  bool _ambientIdle = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initProfileControllers();
    _initDossierControllers();

    // ── Provider subscription (I-77: ref.listenManual, not ref.listen in build) ──
    _providerSub = ref.listenManual(
      figureProvider(widget.figureId),
      fireImmediately: true,
      (previous, next) {
        next.whenData((figure) {
          if (!mounted) return;
          setState(() {
            _figure = figure;
            _isLoading = false;
            _hasError = false;
            _computeIntel(figure);
          });

          // Rebuild chrome TextPainters with new data.
          _prepareChromTextPainters();

          // Start entrance after data loads.
          if (!_reduceMotion && !_entranceCtrl.isAnimating &&
              _entranceCtrl.value == 0.0) {
            _startEntrance();
          }

          // ── Sequential popup gate (I-78) ──
          if (!widget.isDossierMode) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              RateAppPopup.maybeShow(
                context,
                figureId: widget.figureId,
              );
              // Skip soft paywall here; it fires on dossier CTA decline.
            });
          }
        });
        next.whenOrNull(
          error: (e, _) {
            if (mounted) setState(() { _hasError = true; _isLoading = false; });
          },
        );
      },
    );

    // Wire up real statement count from provider (not stub model getter)
    ref.listenManual(
      statementCountProvider(widget.figureId),
      fireImmediately: true,
      (_, next) {
        next.whenData((count) {
          if (!mounted) return;
          setState(() {
            _statementCount = count;
            if (_figure != null) _computeIntel(_figure!);
          });
        });
      },
    );

    // Wire up recent statements from feed service
    ref.listenManual(
      figureRecentStatementsProvider(widget.figureId),
      fireImmediately: true,
      (_, next) {
        next.whenData((statements) {
          if (!mounted) return;
          setState(() {
            _recentStatements = statements;
            // Derive baseline score from feed consensus data.
            if (statements.isNotEmpty) {
              final deltas = statements
                  .map((s) => s.baselineDeltaAvg)
                  .whereType<double>()
                  .toList();
              if (deltas.isNotEmpty) {
                _baselineScore = deltas.reduce((a, b) => a + b) / deltas.length;
              }
            }
            if (_figure != null) _computeIntel(_figure!);
          });
        });
      },
    );

    // Wire up profile analytics (framing, avg pulse, top topic)
    ref.listenManual(
      figureProfileDataProvider(widget.figureId),
      fireImmediately: true,
      (_, next) {
        next.whenData((data) {
          if (mounted) {
            setState(() {
              _profileData = data;
              if (_figure != null) _computeIntel(_figure!);
            });
          }
        });
      },
    );

    // Start dossier entrance if applicable.
    if (widget.isDossierMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _startDossierEntrance();
      });
    }

    // Start idle timer for ambient controllers (A2-S1).
    _resetIdleTimer();
  }

  void _initProfileControllers() {
    _entranceCtrl = AnimationController(
      vsync: this, duration: _kEntranceDuration,
    );
    _entranceCurve = CurvedAnimation(
      parent: _entranceCtrl, curve: Curves.easeOutCubic,
    );

    _gaugeCtrl = AnimationController(
      vsync: this, duration: _kGaugeDuration,
    );
    _gaugeCurve = CurvedAnimation(
      parent: _gaugeCtrl, curve: Curves.easeOutCubic,
    );

    _scanlineCtrl = AnimationController(
      vsync: this, duration: _kScanlineDuration,
    );
    _scanlineCurve = CurvedAnimation(
      parent: _scanlineCtrl, curve: Curves.easeInOut,
    );

    _countUpCtrl = AnimationController(
      vsync: this, duration: _kCountUpDuration,
    );
    _countUpCurve = CurvedAnimation(
      parent: _countUpCtrl, curve: Curves.easeOutCubic,
    );

    _pulseCtrl = AnimationController(
      vsync: this, duration: _kPulseDuration,
    );

    _ambientScanCtrl = AnimationController(
      vsync: this, duration: _kAmbientScanDuration,
    );
    _ambientScanCurve = CurvedAnimation(
      parent: _ambientScanCtrl, curve: Curves.linear,
    );

    _activePulseCtrl = AnimationController(
      vsync: this, duration: _kActivePulseDuration,
    );
    _activePulseCurve = CurvedAnimation(
      parent: _activePulseCtrl, curve: Curves.easeInOut,
    );

    _countUpCtrl.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        // Count-up done. Start ambient.
        if (!_reduceMotion && mounted) {
          _ambientScanCtrl.repeat();
        }
      }
    });

    _monitorPulseCtrl = AnimationController(
      vsync: this, duration: _kMonitorPulseDuration,
    );

    _calibrateCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 4000),
    );
  }

  void _initDossierControllers() {
    _clearanceCtrl = AnimationController(
      vsync: this, duration: _kClearanceDuration,
    );
    _clearanceCurve = CurvedAnimation(
      parent: _clearanceCtrl, curve: Curves.easeOutCubic,
    );

    _blurCtrl = AnimationController(
      vsync: this, duration: _kBlurDuration,
    );
    _blurCurve = CurvedAnimation(
      parent: _blurCtrl, curve: Curves.easeOut,
    );

    _stampCtrl = AnimationController(
      vsync: this, duration: _kStampDuration,
    );
    _stampCurve = CurvedAnimation(
      parent: _stampCtrl, curve: Curves.easeOutCubic,
    );

    _resealCtrl = AnimationController(
      vsync: this, duration: _kResealDuration,
    );
    _resealCurve = CurvedAnimation(
      parent: _resealCtrl, curve: Curves.easeIn,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // A2-C1: Query PlatformDispatcher, not MediaQuery.
    final reduced = ui.PlatformDispatcher.instance
        .accessibilityFeatures.reduceMotion;

    _safePadding = MediaQuery.paddingOf(context);
    _textScaler = MediaQuery.textScalerOf(context); // I-28

    // A2-MS1: Only snap on false→true transition.
    if (reduced && !_wasReduced) {
      // A2-I1: Cancel pending timers during snap.
      for (final t in _pendingTimers) { t.cancel(); }
      _pendingTimers.clear();

      // Snap all to final values.
      _entranceCtrl.value = 1.0;
      _gaugeCtrl.value = 1.0;
      _scanlineCtrl.value = 1.0;
      _countUpCtrl.value = 1.0;
      _pulseCtrl.stop();
      _pulseCtrl.value = 0.0;
      _ambientScanCtrl.stop();
      _ambientScanCtrl.value = 0.0;
      _activePulseCtrl.stop();
      _activePulseCtrl.value = 0.0;
      _monitorPulseCtrl.stop();
      _monitorPulseCtrl.value = 0.5;
      // Dossier controllers snapped in _startDossierEntrance.
    }
    _wasReduced = reduced;
    _reduceMotion = reduced;

    // Rebuild chrome TextPainters if TextScaler changed (A2-C2).
    _prepareChromTextPainters();
  }

  /// A2-C2: Pre-compute static TextPainters for chrome painter.
  /// Called from didChangeDependencies (TextScaler) and after data load.
  void _prepareChromTextPainters() {
    // Dispose previous if any.
    _tpFileTab?.dispose();
    _tpHandling?.dispose();
    _tpSerial?.dispose();
    _tpAccessLog?.dispose();

    final scaledSmall = _textScaler.scale(9);
    final scaledMicro = _textScaler.scale(8);
    final scaledTiny = _textScaler.scale(7);

    // 1. File tab: "PERSONNEL RECORD"
    _tpFileTab = TextPainter(
      text: TextSpan(
        text: 'PERSONNEL RECORD',
        style: TextStyle(
          fontFamily: BaselineTypography.monoFontFamily,
          fontSize: scaledSmall,
          color: BaselineColors.teal.atOpacity(0.2),
          letterSpacing: 1.0,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    // 2. Handling mark.
    _tpHandling = TextPainter(
      text: TextSpan(
        text: 'HANDLE VIA BASELINE CHANNELS ONLY',
        style: TextStyle(
          fontFamily: BaselineTypography.monoFontFamily,
          fontSize: scaledMicro,
          color: BaselineColors.teal.atOpacity(0.03),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    // 3. Document serial.
    final serial = 'PER-${widget.figureId.substring(
      0, math.min(8, widget.figureId.length),
    ).toUpperCase()}';
    _tpSerial = TextPainter(
      text: TextSpan(
        text: serial,
        style: TextStyle(
          fontFamily: BaselineTypography.monoFontFamily,
          fontSize: scaledMicro,
          color: BaselineColors.teal.atOpacity(0.03),
          letterSpacing: 0.5,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    // 4. Access log (cherry 139).
    if (_accessDtg.isNotEmpty) {
      _tpAccessLog = TextPainter(
        text: TextSpan(
          text: _accessDtg,
          style: TextStyle(
            fontFamily: BaselineTypography.monoFontFamily,
            fontSize: scaledTiny,
            color: BaselineColors.teal.atOpacity(0.03),
            letterSpacing: 0.5,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
    } else {
      _tpAccessLog = null;
    }
  }

  // ── Idle timeout (A2-S1) ──

  void _resetIdleTimer() {
    _idleTimer?.cancel();
    if (_ambientIdle && !_reduceMotion) {
      // Wake ambient controllers.
      _pulseCtrl.repeat(reverse: true);
      _monitorPulseCtrl.repeat(reverse: true);
      if (_countUpCtrl.isCompleted) _ambientScanCtrl.repeat();
      _ambientIdle = false;
    }
    _idleTimer = Timer(_kIdleTimeout, () {
      if (!mounted || _reduceMotion) return;
      // Ease ambient to rest.
      _pulseCtrl.stop();
      _ambientScanCtrl.stop();
      _monitorPulseCtrl.stop();
      _ambientIdle = true;
    });
    // Don't add to _pendingTimers - _idleTimer is separately cancelled in dispose.
  }

  @override
  void dispose() {
    // 1. Cancel pending timers (I-11).
    for (final t in _pendingTimers) { t.cancel(); }
    _pendingTimers.clear();

    // 2. Cancel idle + session timers.
    _idleTimer?.cancel();
    _sessionTimer?.cancel();
    _sessionStopwatch.stop();

    // 3. Close provider subscription (I-77).
    _providerSub?.close();

    // 4. Dispose pre-computed TextPainters (A2-C2).
    _tpFileTab?.dispose();
    _tpHandling?.dispose();
    _tpSerial?.dispose();
    _tpAccessLog?.dispose();

    // 5. Safety-net: remove status listener in case animation never completed.
    _scanlineCtrl.removeStatusListener(_onScanComplete);

    // 6. Stop all controllers (I-29).
    _calibrateCtrl.stop();
    _entranceCtrl.stop();
    _gaugeCtrl.stop();
    _scanlineCtrl.stop();
    _pulseCtrl.stop();
    _ambientScanCtrl.stop();
    _activePulseCtrl.stop();
    _countUpCtrl.stop();
    _monitorPulseCtrl.stop();
    _clearanceCtrl.stop();
    _blurCtrl.stop();
    _stampCtrl.stop();
    _resealCtrl.stop();

    // 6. Dispose CurvedAnimations FIRST (I-15: reverse creation order).
    _resealCurve.dispose();
    _stampCurve.dispose();
    _blurCurve.dispose();
    _clearanceCurve.dispose();
    _ambientScanCurve.dispose();
    _activePulseCurve.dispose();
    _countUpCurve.dispose();
    _scanlineCurve.dispose();
    _gaugeCurve.dispose();
    _entranceCurve.dispose();

    // 7. Dispose parent controllers.
    _calibrateCtrl.dispose();
    _resealCtrl.dispose();
    _stampCtrl.dispose();
    _blurCtrl.dispose();
    _clearanceCtrl.dispose();
    _monitorPulseCtrl.dispose();
    _countUpCtrl.dispose();
    _activePulseCtrl.dispose();
    _ambientScanCtrl.dispose();
    _pulseCtrl.dispose();
    _scanlineCtrl.dispose();
    _gaugeCtrl.dispose();
    _entranceCtrl.dispose();

    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _pulseCtrl.stop();
      _monitorPulseCtrl.stop();
      _calibrateCtrl.stop();
      _ambientScanCtrl.stop();
    } else if (state == AppLifecycleState.resumed) {
      if (!_reduceMotion) {
        if (_entranceCtrl.isCompleted) {
          _pulseCtrl.repeat(reverse: true);
          _monitorPulseCtrl.repeat(reverse: true);
          _calibrateCtrl.repeat();
          _ambientScanCtrl.repeat();
        }
      }
    }
  }

  // ═══════════════════════════════════════════════════════════
  // ENTRANCE SEQUENCES
  // ═══════════════════════════════════════════════════════════

  void _startEntrance() {
    if (_reduceMotion) return;
    _scanlineCtrl.forward();

    _scanlineCtrl.addStatusListener(_onScanComplete);
  }

  void _onScanComplete(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _scanlineCtrl.removeStatusListener(_onScanComplete);
      if (!mounted || _reduceMotion) return;
      _entranceCtrl.forward();

      // Start ambient loops now that entrance is running and motion is confirmed.
      _pulseCtrl.repeat(reverse: true);
      _monitorPulseCtrl.repeat(reverse: true);
      _calibrateCtrl.repeat();

      // Gauge starts at phase 4 (800ms into entrance).
      final gaugeTimer = Timer(const Duration(milliseconds: 800), () {
        if (mounted && !_reduceMotion) _gaugeCtrl.forward();
      });
      _pendingTimers.add(gaugeTimer);

      // Count-up at phase 5 (1000ms).
      final countTimer = Timer(const Duration(milliseconds: 1000), () {
        if (mounted && !_reduceMotion) _countUpCtrl.forward();
      });
      _pendingTimers.add(countTimer);

      // Active pulse on ACTIVE+ figures.
      if (_activityDesignation == 'SURGING' ||
          _activityDesignation == 'ACTIVE') {
        final pulseTimer = Timer(const Duration(milliseconds: 600), () {
          if (mounted && !_reduceMotion) {
            _activePulseCtrl.repeat(count: 6);
          }
        });
        _pendingTimers.add(pulseTimer);
      }
    }
  }

  void _startDossierEntrance() {
    if (_reduceMotion || _hasSeenDossierEntrance) {
      _hasSeenDossierEntrance = true;
      _blurCtrl.value = 1.0;
      _clearanceCtrl.value = 1.0;
      _stampCtrl.value = 1.0;
      _startSessionTimer();
      return;
    }

    HapticUtil.light();
    _clearanceCtrl.forward();

    // Blur dissolve at 500ms.
    final blurTimer = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      HapticUtil.medium();
      _blurCtrl.forward();
      _stampCtrl.forward();
    });
    _pendingTimers.add(blurTimer);

    // Completion.
    final doneTimer = Timer(_kClearanceDuration, () {
      if (!mounted) return;
      HapticUtil.success();
      _hasSeenDossierEntrance = true;
      _startSessionTimer();
    });
    _pendingTimers.add(doneTimer);
  }

  void _startSessionTimer() {
    _sessionStopwatch.start();
    _sessionTimer = Timer.periodic(_kSessionTimerInterval, (_) {
      if (!mounted) return;
      final elapsed = _sessionStopwatch.elapsed;
      setState(() {
        _sessionElapsed =
            '${elapsed.inMinutes.toString().padLeft(2, '0')}:'
            '${(elapsed.inSeconds % 60).toString().padLeft(2, '0')}';
      });
    });
  }

  void _handleDossierBack() {
    if (_isResealing) return;
    if (_reduceMotion) {
      _sessionTimer?.cancel();
      _sessionStopwatch.stop();
      if (context.canPop()) context.pop();
      return;
    }
    setState(() => _isResealing = true);
    HapticUtil.medium();
    _resealCtrl.forward().then((_) {
      _sessionTimer?.cancel();
      _sessionStopwatch.stop();
      if (mounted && context.canPop()) context.pop();
    });
  }

  Future<void> _fetchBaselineScore() async {
    try {
      final score = await ref.read(
        baselineScoreProvider(widget.figureId).future,
      );
      if (mounted) setState(() => _baselineScore = score as double?);
    } catch (_) {
      // Baseline score is supplementary; profile still renders.
    }
  }

  // ═══════════════════════════════════════════════════════════
  // COMPUTED INTEL (I-45: cached, never in paint())
  // ═══════════════════════════════════════════════════════════

  void _computeIntel(Figure figure) {
    // Activity designation (FG-8b vocabulary).
    final rc = _statementCount;
    if (rc >= 7) {
      _activityDesignation = 'SURGING';
      _activityDot = '\u25CF'; // ●
      _activityDotOpacity = 1.0;
    } else if (rc >= 3) {
      _activityDesignation = 'ACTIVE';
      _activityDot = '\u25CF'; // ●
      _activityDotOpacity = 0.7;
    } else if (rc >= 1) {
      _activityDesignation = 'QUIET';
      _activityDot = '\u25CB'; // ○
      _activityDotOpacity = 0.3;
    } else {
      _activityDesignation = 'SILENT';
      _activityDot = '\u25CC'; // ◌
      _activityDotOpacity = 0.2;
    }

    // Military DTG from LAST STATEMENT (not DateTime.now()). I-45 cached.
    const months = [
      'JAN','FEB','MAR','APR','MAY','JUN',
      'JUL','AUG','SEP','OCT','NOV','DEC',
    ];
    final lastStatementAt = _profileData?.lastStatementAt
        ?? (_recentStatements.isNotEmpty ? _recentStatements.first.statedAt : null);
    if (lastStatementAt != null) {
      final ts = lastStatementAt.toUtc();
      _lastSeenDtg = '${ts.day.toString().padLeft(2, '0')}'
          '${ts.hour.toString().padLeft(2, '0')}'
          '${ts.minute.toString().padLeft(2, '0')}Z'
          '${months[ts.month - 1]}'
          '${(ts.year % 100).toString().padLeft(2, '0')}';

      final diff = DateTime.now().toUtc().difference(ts);
      if (diff.inDays > 0) {
        _lastSeenHuman = '(${diff.inDays}d ago)';
      } else if (diff.inHours > 0) {
        _lastSeenHuman = '(${diff.inHours}h ago)';
      } else {
        _lastSeenHuman = '(${diff.inMinutes}m ago)';
      }
    } else {
      _lastSeenDtg = 'NO RECENT COMMS';
      _lastSeenHuman = '';
    }

    // Subject ID.
    _subjectId = 'SID-${widget.figureId.substring(
      0, math.min(8, widget.figureId.length),
    ).toUpperCase()}';

    // Code designation (NATO phonetic).
    _codeDesignation = _computeCodeDesignation(widget.figureId);

    // Access DTG (cherry 139).
    final now = DateTime.now().toUtc();
    _accessDtg = 'ACCESSED: ${now.day.toString().padLeft(2, '0')}'
        '${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}Z'
        '${months[now.month - 1]}'
        '${(now.year % 100).toString().padLeft(2, '0')}';

    // Measurement confidence.
    if (_statementCount >= 50) {
      _confidenceLevel = 'VERIFIED';
      _confidenceFill = 1.0;
      _confidenceOpacity = 0.5;
    } else if (_statementCount >= 20) {
      _confidenceLevel = 'HIGH';
      _confidenceFill = 0.75;
      _confidenceOpacity = 0.35;
    } else if (_statementCount >= 5) {
      _confidenceLevel = 'MODERATE';
      _confidenceFill = 0.4;
      _confidenceOpacity = 0.2;
    } else {
      _confidenceLevel = 'LOW';
      _confidenceFill = 0.15;
      _confidenceOpacity = 0.1;
    }

    // Fingerprint hash (cherry 142).
    if (_profileData?.framingDistribution != null) {
      var hash = 0;
      for (final v in _profileData!.framingDistribution!.values) {
        hash = (hash * 37 + (v * 1000).round()) & 0x7FFFFFFF;
      }
      _fingerprintHash = 'FPHASH: ${hash.toRadixString(16).padLeft(8, '0').toUpperCase().substring(0, 8)}';
    }

    // Intel sparkline (cherry 143): mock 30-day frequency from statement dates.
    _sparklineData = _computeSparkline();
  }

  static String _computeCodeDesignation(String figureId) {
    const phonetic = [
      'ALPHA', 'BRAVO', 'CHARLIE', 'DELTA', 'ECHO',
      'FOXTROT', 'GOLF', 'HOTEL', 'INDIA', 'JULIET',
      'KILO', 'LIMA', 'MIKE', 'NOVEMBER', 'OSCAR',
      'PAPA', 'QUEBEC', 'ROMEO', 'SIERRA', 'TANGO',
      'UNIFORM', 'VICTOR', 'WHISKEY', 'XRAY', 'YANKEE',
      'ZULU',
    ];
    var hash = 0;
    final segment = figureId.substring(
      0, math.min(8, figureId.length),
    );
    for (var i = 0; i < segment.length; i++) {
      hash = (hash * 31 + segment.codeUnitAt(i)) & 0x7FFFFFFF;
    }
    final word = phonetic[hash % phonetic.length];
    final number = (hash ~/ phonetic.length) % 10;
    return 'DESIGNATION: $word-$number';
  }

  List<double> _computeSparkline() {
    // Generate 30-day normalized frequency from statement timestamps.
    if (_recentStatements.isEmpty) {
      return List.filled(30, 0.0);
    }
    final now = DateTime.now();
    final buckets = List<int>.filled(30, 0);
    for (final s in _recentStatements) {
      final daysAgo = now.difference(s.statedAt).inDays.clamp(0, 29);
      buckets[29 - daysAgo]++;
    }
    final maxVal = buckets.reduce(math.max).clamp(1, 999);
    return buckets.map((b) => b / maxVal).toList();
  }

  // ═══════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BaselineColors.scaffoldBg,
      body: _isLoading
          ? Stack(children: [_buildLoading(), _buildBackButton()])
          : _hasError
              ? Stack(children: [_buildError(), _buildBackButton()])
              : widget.isDossierMode
                  ? _buildDossierMode()
                  : _buildProfileMode(),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // PROFILE MODE
  // ═══════════════════════════════════════════════════════════

  Widget _buildProfileMode() {
    return Stack(
      children: [
        // Layer 1: Chrome (I-79: isolated AnimatedBuilder + RepaintBoundary).
        RepaintBoundary(
          child: AnimatedBuilder(
            animation: Listenable.merge([
              _pulseCtrl,
              _ambientScanCtrl,
              _monitorPulseCtrl,
              _scanlineCtrl,
            ]),
            builder: (_, _) {
              return ExcludeSemantics(
                child: CustomPaint(
                  painter: _PersonnelFilePainter(
                    pulsePhase: _pulseCtrl.value,
                    scanlinePhase: _scanlineCurve.value,
                    ambientScanPhase: _ambientScanCurve.value,
                    monitorPulsePhase: _monitorPulseCtrl.value,
                    figureId: widget.figureId,
                    textScaler: _textScaler,
                    safeTop: _safePadding.top,
                    tpFileTab: _tpFileTab,
                    tpHandling: _tpHandling,
                    tpSerial: _tpSerial,
                    tpAccessLog: _tpAccessLog,
                  ),
                  size: Size.infinite,
                ),
              );
            },
          ),
        ),

        // Layer 2: Content (self-driving leaf builders, not wrapped).
        NotificationListener<ScrollNotification>(
          onNotification: (_) {
            _resetIdleTimer(); // A2-S1: wake on scroll.
            return false;
          },
          child: RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(figureProvider(widget.figureId));
              await _fetchBaselineScore();
            },
            color: BaselineColors.teal,
            backgroundColor: BaselineColors.card,
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.only(
                      top: _safePadding.top + 44,
                      left: 20,
                      right: 20,
                    ),
                    child: _buildProfileContent(),
                  ),
                ),
                SliverToBoxAdapter(
                  child: SizedBox(height: _safePadding.bottom + 24),
                ),
              ],
            ),
          ),
        ),

        // Layer 3: Back button (BUG-4.1 fix).
        _buildBackButton(),

        // Layer 4: Bookmark icon (Treatment 137).
        _buildBookmarkIcon(),
      ],
    );
  }

  Widget _buildBackButton() {
    return Positioned(
      top: _safePadding.top + 12,
      left: 12,
      child: Semantics(
        button: true,
        label: 'Go back',
        excludeSemantics: true,
        child: _PressScaleWidget(
          scale: 0.95,
          onTap: () {
            HapticUtil.light();
            if (context.canPop()) {
              context.pop();
            } else {
              context.go(AppRoutes.today);
            }
          },
          child: SizedBox(
            width: 44,
            height: 44,
            child: Center(
              child: BaselineIcon(
                BaselineIconType.backArrow,
                size: 24,
                color: BaselineColors.teal,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProfileContent() {
    final figure = _figure;
    if (figure == null) return const SizedBox.shrink();

    // BUG-2.8: Collapse sections that have no data (no empty chrome).
    final hasIntelData = _statementCount > 0 || _profileData != null;
    final hasFramingData = _profileData?.framingDistribution != null;
    final hasStatements = _recentStatements.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSubjectHeader(figure),
        _buildSectionDots(), // Cherry 141
        _buildAssessmentGauge(),
        if (hasIntelData) ...[
          _buildSectionDots(),
          _buildIntelFields(figure),
        ],
        if (hasFramingData || hasStatements) ...[
          _buildSectionDots(),
          _buildBehavioralProfile(figure),
        ],
        if (hasStatements) ...[
          _buildSectionDots(),
          _buildRecentStatements(),
        ],
        _buildSectionDots(),
        _buildAccessPoints(figure),
        const SizedBox(height: 16),
        _buildDossierCTA(),
        const SizedBox(height: 16),
        _buildMethodologyFooter(),
      ],
    );
  }

  // ── Cherry 141: Section rhythm dots ──
  Widget _buildSectionDots() {
    return ExcludeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < 3; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              Container(
                width: 2,
                height: 2,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: BaselineColors.teal.atOpacity(0.05),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // SUBJECT HEADER (Treatments 15–32)
  // ═══════════════════════════════════════════════════════════

  Widget _buildSubjectHeader(Figure figure) {
    return AnimatedBuilder(
      animation: _entranceCurve,
      builder: (_, _) {
        final opacity = _entranceCurve.value.clamp(0.0, 1.0);
        final slideY = 6.0 * (1.0 - opacity);

        return Transform.translate(
          offset: Offset(0, slideY),
          child: Opacity(
            opacity: opacity,
            child: Container(
              padding: BaselineInsets.allM,
              decoration: BoxDecoration(
                color: BaselineColors.card,
                border: Border.all(
                  color: BaselineColors.teal.atOpacity(0.06),
                  width: 2,
                ),
                borderRadius: BaselineRadius.cardBorderRadius,
              ),
              child: Column(
                children: [
                  // Overline (Treatment 17).
                  ExcludeSemantics(
                    child: Text(
                      '(U) SUBJECT IDENTIFICATION \u00B7 BASELINE INTELLIGENCE',
                      style: BaselineTypography.dataSmall.copyWith(
                        color: BaselineColors.teal.atOpacity(0.15),
                        letterSpacing: 0.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Avatar (Treatment 18–21).
                  _buildAvatar(figure),
                  const SizedBox(height: 12),

                  // Cherry 140: Avatar measurement ticks.
                  _buildAvatarMeasurementTicks(),
                  const SizedBox(height: 8),

                  // Name (Treatment 22).
                  Text(
                    figure.name.toUpperCase(),
                    style: BaselineTypography.h1.copyWith(
                      letterSpacing: 1.2,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),

                  // Teal underline (Treatment 23).
                  ExcludeSemantics(
                    child: Container(
                      margin: const EdgeInsets.only(top: 4),
                      height: 2,
                      width: 60,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            BaselineColors.teal.atOpacity(0.0),
                            BaselineColors.teal.atOpacity(0.3),
                            BaselineColors.teal.atOpacity(0.0),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Role · Party (Treatment 24).
                  // Show role if available, fallback to formatted category.
                  Builder(builder: (context) {
                    final parts = <String>[];
                    if (figure.role != null && figure.role!.isNotEmpty) {
                      parts.add(figure.role!);
                    } else {
                      parts.add(_formatCategory(figure.category));
                    }
                    if (figure.party != null && figure.party!.isNotEmpty) {
                      parts.add(figure.party!);
                    }
                    return Text(
                      parts.join(' \u00B7 '),
                      style: BaselineTypography.body2.copyWith(
                        fontSize: 13,
                        color: BaselineColors.textSecondary,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    );
                  }),
                  const SizedBox(height: 4),

                  // DTG (Treatment 25).
                  _buildSubjectMeta(),
                  const SizedBox(height: 2),

                  // Code designation (Treatment 26a).
                  _buildCodeDesignationWidget(),
                  const SizedBox(height: 8),

                  // Activity badge (Treatment 27).
                  _buildActivityBadge(),
                  const SizedBox(height: 8),

                  // Category badge (Treatment 28).
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: BaselineColors.borderInactive,
                        width: 2,
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      figure.category.toUpperCase(),
                      style: BaselineTypography.dataSmall.copyWith(
                        color: BaselineColors.textSecondary,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),

                  // Statement count badge (Treatment 138).
                  if (_statementCount > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: BaselineColors.teal.atOpacity(0.08),
                          borderRadius: BaselineRadius.chipBorderRadius,
                        ),
                        child: Text(
                          '$_statementCount',
                          style: BaselineTypography.dataSmall.copyWith(
                            color: BaselineColors.teal,
                          ),
                        ),
                      ),
                    ),

                  // Classification triangle (Treatment 32).
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildAvatar(Figure figure) {
    return Stack(
      alignment: Alignment.center,
      children: [
        // Active pulse ring (Treatment 20).
        if (_activityDesignation == 'SURGING' ||
            _activityDesignation == 'ACTIVE')
          AnimatedBuilder(
            animation: _activePulseCurve,
            builder: (_, _) {
              return Container(
                width: _kAvatarSize + 8,
                height: _kAvatarSize + 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: BaselineColors.teal.atOpacity(
                      0.15 * (1.0 - _activePulseCurve.value),
                    ),
                    width: 2,
                  ),
                ),
              );
            },
          ),

        // Avatar circle (Treatment 18).
        Container(
          width: _kAvatarSize,
          height: _kAvatarSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: BaselineColors.teal, // LOCKED identity: 3px teal ring.
              width: 3,
            ),
          ),
          child: ClipOval(
            child: figure.imageUrl != null
                ? Image.network(
                    figure.imageUrl!,
                    fit: BoxFit.cover,
                    cacheWidth: 480,
                    cacheHeight: 480,
                    errorBuilder: (_, _, _) =>
                        _buildInitialsFallback(figure),
                  )
                : _buildInitialsFallback(figure),
          ),
        ),

        // Activity dot (Treatment 21).
        Positioned(
          bottom: 0,
          right: (_kAvatarSize / 2) - 8,
          child: Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: BaselineColors.scaffoldBg,
              border: Border.all(
                color: BaselineColors.scaffoldBg,
                width: 2,
              ),
            ),
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: BaselineColors.teal.atOpacity(_activityDotOpacity),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInitialsFallback(Figure figure) {
    final initials = figure.name
        .split(' ')
        .where((w) => w.isNotEmpty)
        .map((w) => w[0])
        .take(2)
        .join();
    return Container(
      color: BaselineColors.card,
      alignment: Alignment.center,
      child: Text(
        initials.toUpperCase(),
        style: BaselineTypography.h2.copyWith(
          color: BaselineColors.textSecondary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  // Cherry 140: Avatar measurement ticks.
  Widget _buildAvatarMeasurementTicks() {
    return ExcludeSemantics(
      child: SizedBox(
        width: _kAvatarSize + 20,
        height: 6,
        child: CustomPaint(
          painter: _AvatarTickPainter(
            color: BaselineColors.teal.atOpacity(0.03),
          ),
        ),
      ),
    );
  }

  Widget _buildSubjectMeta() {
    return Column(
      children: [
        if (_lastSeenDtg.isNotEmpty)
          ExcludeSemantics(
            child: Text(
              '$_lastSeenDtg $_lastSeenHuman',
              style: BaselineTypography.dataSmall.copyWith(
                color: BaselineColors.teal.atOpacity(0.12),
                letterSpacing: 0.5,
              ),
            ),
          ),
        const SizedBox(height: 2),
        if (_subjectId.isNotEmpty)
          ExcludeSemantics(
            child: Text(
              _subjectId,
              style: TextStyle(
                fontFamily: BaselineTypography.monoFontFamily,
                fontSize: 8,
                color: BaselineColors.textPrimary.atOpacity(0.2),
                letterSpacing: 0.5,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildCodeDesignationWidget() {
    if (_codeDesignation.isEmpty) return const SizedBox.shrink();
    return ExcludeSemantics(
      child: Text(
        _codeDesignation,
        style: TextStyle(
          fontFamily: BaselineTypography.monoFontFamily,
          fontSize: 8,
          color: BaselineColors.teal.atOpacity(0.08),
          letterSpacing: 1.0,
        ),
      ),
    );
  }

  Widget _buildActivityBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        border: Border.all(
          color: BaselineColors.teal.atOpacity(
            _activityDesignation == 'SURGING' ? 0.4 : 0.15,
          ),
          width: 1.5,
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _activityDot,
            style: TextStyle(
              color: BaselineColors.teal.atOpacity(_activityDotOpacity),
              fontSize: 10,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            _activityDesignation,
            style: BaselineTypography.dataSmall.copyWith(
              color: BaselineColors.teal.atOpacity(
                _activityDesignation == 'SILENT' ? 0.3 : 0.6,
              ),
              letterSpacing: 1.0,
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // ASSESSMENT GAUGE (Treatments 33–44b)
  // ═══════════════════════════════════════════════════════════

  Widget _buildAssessmentGauge() {
    return AnimatedBuilder(
      animation: _gaugeCurve,
      builder: (_, _) {
        final progress = _gaugeCurve.value;
        return Opacity(
          opacity: _entranceCtrl.isCompleted
              ? 1.0
              : (_entranceCurve.value * 1.5).clamp(0.0, 1.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Section label (Treatment 33).
              ExcludeSemantics(
                child: Text(
                  '(U) ASSESSMENT RATING',
                  style: BaselineTypography.dataSmall.copyWith(
                    color: BaselineColors.teal.atOpacity(0.15),
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // Gauge container (Treatment 35).
              Container(
                padding: BaselineInsets.allS,
                decoration: BoxDecoration(
                  color: BaselineColors.card,
                  border: Border.all(
                    color: BaselineColors.borderInactive,
                    width: 2,
                  ),
                  borderRadius: BaselineRadius.cardBorderRadius,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Gauge painter (Treatments 36–40). A2-M1: textScaler removed.
                    SizedBox(
                      height: 32,
                      child: CustomPaint(
                        painter: _AssessmentGaugePainter(
                          score: _baselineScore,
                          progress: progress,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Score readout (Treatment 41).
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Info button (Treatment 44). A2-C3: excludeSemantics.
                        Semantics(
                          button: true,
                          excludeSemantics: true,
                          label: 'How Baseline score works',
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () {
                              HapticUtil.light();
                              _resetIdleTimer();
                              InfoBottomSheet.show(context, key: 'baseline');
                            },
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '$_statementCount statements',
                                  style: BaselineTypography.dataSmall.copyWith(
                                    color: BaselineColors.textTertiary,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                BaselineIcon(
                                  BaselineIconType.info,
                                  size: 16,
                                  color: BaselineColors.teal.atOpacity(0.3),
                                ),
                              ],
                            ),
                          ),
                        ),
                        // Score (Treatment 41) + calibrating state.
                        if (_baselineScore == null && _statementCount < 5)
                          AnimatedBuilder(
                            animation: _calibrateCtrl,
                            builder: (context, child) {
                              return Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CustomPaint(
                                      painter: _CalibratingCirclePainter(
                                        rotation: _reduceMotion
                                            ? 0.0
                                            : _calibrateCtrl.value * 2 * math.pi,
                                        color: BaselineColors.teal.atOpacity(0.5),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'CALIBRATING',
                                    style: TextStyle(
                                      fontFamily: BaselineTypography.monoFontFamily,
                                      fontSize: 10,
                                      color: BaselineColors.teal.atOpacity(0.5),
                                      letterSpacing: 1.0,
                                    ),
                                  ),
                                ],
                              );
                            },
                          )
                        else
                          Text(
                            _baselineScore != null
                                ? 'BASELINE\u2122 ${(_baselineScore! * progress).toStringAsFixed(1)}'
                                : 'BASELINE\u2122 \u2014',
                            style: BaselineTypography.data.copyWith(
                              color: _baselineScore != null
                                  ? BaselineColors.teal
                                  : BaselineColors.textTertiary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ),

                    // Confidence bar (Treatment 44a-b).
                    _buildConfidenceBar(),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildConfidenceBar() {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 6,
            child: CustomPaint(
              painter: _ConfidenceBarPainter(
                fill: _confidenceFill,
                opacity: _confidenceOpacity,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Align(
            alignment: Alignment.centerRight,
            child: ExcludeSemantics(
              child: Text(
                'CONFIDENCE: $_confidenceLevel',
                style: TextStyle(
                  fontFamily: BaselineTypography.monoFontFamily,
                  fontSize: 8,
                  color: BaselineColors.teal.atOpacity(_confidenceOpacity),
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // INTEL DATA FIELDS (Treatments 45–56)
  // ═══════════════════════════════════════════════════════════

  Widget _buildIntelFields(Figure figure) {
    return AnimatedBuilder(
      animation: _countUpCurve,
      builder: (_, _) {
        final countProgress = _countUpCurve.value;
        final sectionOpacity = _entranceCtrl.isCompleted
            ? 1.0
            : (_entranceCurve.value * 2.0 - 0.6).clamp(0.0, 1.0);

        return Opacity(
          opacity: sectionOpacity,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ExcludeSemantics(
                child: Text(
                  '(U) INTELLIGENCE SUMMARY',
                  style: BaselineTypography.dataSmall.copyWith(
                    color: BaselineColors.teal.atOpacity(0.15),
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Semantics(
                button: true,
                excludeSemantics: true,
                label: 'Intelligence summary, tap for methodology',
                child: _PressScaleWidget(
                  scale: 0.98,
                  onTap: () {
                    HapticUtil.light();
                    _resetIdleTimer();
                    InfoBottomSheet.show(context, key: 'signal_pulse');
                  },
                  child: Container(
                    padding: BaselineInsets.allS,
                    decoration: BoxDecoration(
                      color: BaselineColors.card,
                      border: Border.all(
                        color: BaselineColors.borderInactive,
                        width: 2,
                      ),
                      borderRadius: BaselineRadius.cardBorderRadius,
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            // Statement count (Treatment 47–51).
                            Expanded(
                              child: _buildIntelColumn(
                                'STATEMENTS',
                                '${(_statementCount * countProgress).round()}',
                                isTeal: true,
                              ),
                            ),
                            // Hashmark divider (Treatment 50).
                            _buildHashmarkDivider(),
                            // Avg Signal Pulse (Treatment 52).
                            Expanded(
                              child: _buildIntelColumn(
                                'AVG PULSE',
                                (_profileData?.avgSignalPulse ?? _computedAvgPulse) != null
                                    ? ((_profileData?.avgSignalPulse ?? _computedAvgPulse!) * countProgress)
                                        .toStringAsFixed(1)
                                    : '\u2014',
                                isTeal: true,
                              ),
                            ),
                            _buildHashmarkDivider(),
                            // Top topic (Treatment 53).
                            Expanded(
                              child: _buildIntelColumn(
                                'PRIMARY TOPIC',
                                _topicDisplay(_profileData?.topTopic ?? _computedTopTopic ?? '\u2014'),
                                isTeal: false,
                                maxLines: 2,
                              ),
                            ),
                          ],
                        ),
                        // Cherry 143: Intel sparkline.
                        if (_sparklineData.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: SizedBox(
                              height: 16,
                              child: ExcludeSemantics(
                                child: CustomPaint(
                                  size: const Size(double.infinity, 16),
                                  painter: _IntelSparklinePainter(
                                    data: _sparklineData,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildIntelColumn(String label, String value, {required bool isTeal, int maxLines = 1}) {
    final valueWidget = Text(
      value,
      style: BaselineTypography.data.copyWith(
        color: isTeal ? BaselineColors.teal : BaselineColors.textPrimary,
        fontWeight: FontWeight.w600,
      ),
      textAlign: TextAlign.center,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
    );

    return Column(
      children: [
        Text(
          label,
          style: BaselineTypography.dataSmall.copyWith(
            color: BaselineColors.textTertiary,
            letterSpacing: 0.5,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        // FittedBox prevents text truncation for long topic names (#62).
        maxLines > 1
            ? FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.center,
                child: valueWidget,
              )
            : valueWidget,
      ],
    );
  }

  Widget _buildHashmarkDivider() {
    return ExcludeSemantics(
      child: SizedBox(
        width: 12,
        height: 40,
        child: CustomPaint(
          painter: _HashmarkDividerPainter(),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // BEHAVIORAL PROFILE (Treatments 57–66)
  // ═══════════════════════════════════════════════════════════

  Widget _buildBehavioralProfile(Figure figure) {
    final sectionOpacity = _entranceCtrl.isCompleted
        ? 1.0
        : (_entranceCurve.value * 2.0 - 0.8).clamp(0.0, 1.0);

    return Opacity(
      opacity: sectionOpacity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ExcludeSemantics(
            child: Text(
              '(U) BEHAVIORAL PROFILE \u00B7 FRAMING FINGERPRINT\u2122',
              style: BaselineTypography.dataSmall.copyWith(
                color: BaselineColors.teal.atOpacity(0.15),
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: BaselineInsets.allS,
            decoration: BoxDecoration(
              color: BaselineColors.card,
              border: Border.all(
                color: BaselineColors.borderInactive,
                width: 2,
              ),
              borderRadius: BaselineRadius.cardBorderRadius,
            ),
            child: Column(
              children: [
                // FG-1 profile (Treatment 59–60).
                if (_profileData?.framingDistribution != null)
                  Center(
                    child: Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: BaselineColors.borderInactive,
                          width: 2,
                        ),
                        borderRadius: BaselineRadius.cardBorderRadius,
                      ),
                      child: FramingFingerprint.profile(
                        values: FramingValues.fromJsonMap(_profileData!.framingDistribution!),
                      ),
                    ),
                  )
                else
                  // Null state (Treatment 65).
                  Center(
                    child: Column(
                      children: [
                        SizedBox(
                          width: 80,
                          height: 80,
                          child: CustomPaint(
                            painter: _DashedCirclePainter(),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'INSUFFICIENT DATA',
                          style: BaselineTypography.dataSmall.copyWith(
                            color: BaselineColors.textTertiary,
                            letterSpacing: 1.0,
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 8),

                // Dominant framing (Treatment 61).
                if (_profileData?.framingDistribution != null)
                  Text(
                    'PRIMARY: ${_dominantFraming(_profileData!.framingDistribution!)}',
                    style: BaselineTypography.dataSmall.copyWith(
                      color: BaselineColors.teal,
                      letterSpacing: 0.5,
                    ),
                  ),
                const SizedBox(height: 8),

                // Distribution bars (Treatment 62).
                if (_profileData?.framingDistribution != null)
                  _buildFramingDistributionBars(_profileData!.framingDistribution!),

                // Cherry 142: Fingerprint hash.
                if (_fingerprintHash.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: ExcludeSemantics(
                      child: Text(
                        _fingerprintHash,
                        style: TextStyle(
                          fontFamily: BaselineTypography.monoFontFamily,
                          fontSize: 8,
                          color: BaselineColors.teal.atOpacity(0.06),
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                  ),

                const SizedBox(height: 8),

                // Radar link (Treatment 63–64). Now Core - no gate.
                Semantics(
                  button: true,
                  excludeSemantics: true,
                  label: 'View Framing Radar',
                  child: _PressScaleWidget(
                    scale: 0.95,
                    onTap: () {
                      HapticUtil.selection();
                      _resetIdleTimer();
                      context.push(
                        AppRoutes.framingRadarPath(widget.figureId),
                      );
                    },
                    child: Text(
                      '\u2192 VIEW FRAMING RADAR\u2122',
                      style: BaselineTypography.dataSmall.copyWith(
                        color: BaselineColors.teal,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _dominantFraming(Map<String, double> dist) {
    if (dist.isEmpty) return 'UNKNOWN';
    final sorted = dist.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.first.key.toUpperCase();
  }

  Widget _buildFramingDistributionBars(Map<String, double> distribution) {
    final sorted = distribution.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Column(
      children: [
        for (final entry in sorted.take(5))
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                SizedBox(
                  width: 72,
                  child: Text(
                    entry.key.toUpperCase(),
                    style: BaselineTypography.dataSmall.copyWith(
                      color: BaselineColors.textTertiary,
                      letterSpacing: 0.3,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final barWidth = constraints.maxWidth *
                          entry.value.clamp(0.0, 1.0);
                      return Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          width: barWidth,
                          height: 3,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                BaselineColors.teal.atOpacity(0.15),
                                BaselineColors.teal.atOpacity(0.4),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(1.5),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════
  // RECENT STATEMENTS (Treatments 67–79)
  // ═══════════════════════════════════════════════════════════

  Widget _buildRecentStatements() {
    final sectionOpacity = _entranceCtrl.isCompleted
        ? 1.0
        : (_entranceCurve.value * 2.0 - 1.0).clamp(0.0, 1.0);

    return Opacity(
      opacity: sectionOpacity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              ExcludeSemantics(
                child: Text(
                  '(U) OBSERVED COMMUNICATIONS (RECENT)',
                  style: BaselineTypography.dataSmall.copyWith(
                    color: BaselineColors.teal.atOpacity(0.15),
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (_statementCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6, vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: BaselineColors.teal.atOpacity(0.06),
                    borderRadius: BaselineRadius.chipBorderRadius,
                  ),
                  child: Text(
                    '${_recentStatements.length} of $_statementCount',
                    style: BaselineTypography.dataSmall.copyWith(
                      color: BaselineColors.teal.atOpacity(0.5),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),

          if (_recentStatements.isEmpty)
            Text(
              'No statements observed in this period.',
              style: BaselineTypography.body2.copyWith(
                color: BaselineColors.textTertiary,
              ),
            )
          else
            // Timeline spine + cards (Treatments 70–78).
            Column(
              children: [
                for (var i = 0; i < _recentStatements.length && i < 5; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Timeline spine + dot (Treatments 70–71).
                        ExcludeSemantics(
                          child: SizedBox(
                            width: 16,
                            child: Column(
                              children: [
                                Container(
                                  width: 1,
                                  height: 8,
                                  color: i == 0
                                      ? Colors.transparent
                                      : BaselineColors.teal.atOpacity(0.12),
                                ),
                                Container(
                                  width: (_kTimelineDotMin +
                                      (_kTimelineDotMax - _kTimelineDotMin) *
                                          ((_recentStatements[i].signalRank ?? 0.5)
                                              .clamp(0.0, 1.0))),
                                  height: (_kTimelineDotMin +
                                      (_kTimelineDotMax - _kTimelineDotMin) *
                                          ((_recentStatements[i].signalRank ?? 0.5)
                                              .clamp(0.0, 1.0))),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: BaselineColors.teal.atOpacity(0.4),
                                  ),
                                ),
                                Container(
                                  width: 1,
                                  height: 40,
                                  color: BaselineColors.teal.atOpacity(0.12),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Compact card (Treatment 72).
                        Expanded(
                          child: Semantics(
                            button: true,
                            child: StatementCard.compact(
                              statement: _recentStatements[i],
                              onTap: () {
                                HapticUtil.selection();
                                _resetIdleTimer();
                                context.push(
                                  AppRoutes.statementDetailPath(
                                    _recentStatements[i].id,
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),

          // View all link (Treatment 76).
          // Navigate to explore screen filtered by this figure.
          if (_statementCount > 5)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Semantics(
                button: true,
                child: _PressScaleWidget(
                  scale: 0.95,
                  onTap: () {
                    HapticUtil.selection();
                    _resetIdleTimer();
                    context.push(
                      '${AppRoutes.explore}?figure=${widget.figureId}',
                    );
                  },
                  child: Text(
                    'View all $_statementCount statements \u2192',
                    style: BaselineTypography.dataSmall.copyWith(
                      color: BaselineColors.teal,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // ACCESS POINTS (Treatments 80–96)
  // ═══════════════════════════════════════════════════════════

  Widget _buildAccessPoints(Figure figure) {
    final sectionOpacity = _entranceCtrl.isCompleted
        ? 1.0
        : (_entranceCurve.value * 2.0 - 1.2).clamp(0.0, 1.0);

    final rows = <_NavRowData>[
      _NavRowData(
        title: 'Framing Radar\u2122',
        clearance: '[STANDARD]',
        route: AppRoutes.framingRadarPath(widget.figureId),
        isGated: false,
      ),
      if (figure.bioguideId != null)
        _NavRowData(
          title: 'Vote Record',
          clearance: '[STANDARD]',
          route: AppRoutes.voteRecordPath(widget.figureId),
          isGated: false,
        ),
      _NavRowData(
        title: 'Trends',
        clearance: '[PRO]',
        route: AppRoutes.trendsPath(widget.figureId),
        isGated: true,
        feature: AppFeature.trends,
      ),
      _NavRowData(
        title: 'Crossfire\u2122',
        clearance: '[PRO]',
        route: AppRoutes.crossfire,
        isGated: true,
        feature: AppFeature.crossfire,
      ),
      _NavRowData(
        title: 'Declassified Dossier\u2122',
        clearance: '[PRO+]',
        route: AppRoutes.dossierPath(widget.figureId),
        isGated: true,
        feature: AppFeature.dossier,
      ),
      _NavRowData(
        title: 'Narrative Sync\u2122',
        clearance: '[B2B]',
        route: AppRoutes.narrativeSync,
        isGated: true,
        feature: AppFeature.narrativeSync,
      ),
      if (_recentStatements.isNotEmpty)
        _NavRowData(
          title: 'Latest Statement',
          clearance: '[STANDARD]',
          route: AppRoutes.statementPath(_recentStatements.first.id),
          isGated: false,
        ),
      if (_recentStatements.isNotEmpty)
        _NavRowData(
          title: 'Lens Lab\u2122',
          clearance: '[PRO]',
          route: AppRoutes.lensLabPath(_recentStatements.first.id),
          isGated: true,
          feature: AppFeature.lensLab,
        ),
    ];

    final activeCount = rows.where((r) => !r.isGated).length;
    final totalCount = rows.length;

    return Opacity(
      opacity: sectionOpacity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ExcludeSemantics(
            child: Text(
              '(U) ACCESS POINTS',
              style: BaselineTypography.dataSmall.copyWith(
                color: BaselineColors.teal.atOpacity(0.15),
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(height: 8),

          for (var i = 0; i < rows.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _buildNavRow(rows[i], staggerIndex: i),
            ),

          // Access summary (Treatment 96).
          ExcludeSemantics(
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '$activeCount OF $totalCount CHANNELS AVAILABLE AT YOUR CLEARANCE LEVEL',
                style: BaselineTypography.dataSmall.copyWith(
                  color: BaselineColors.teal.atOpacity(0.15),
                  letterSpacing: 0.5,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavRow(_NavRowData data, {required int staggerIndex}) {
    Widget row = Container(
      height: 64,
      padding: BaselineInsets.horizontalM,
      decoration: BoxDecoration(
        color: BaselineColors.card,
        border: Border.all(
          color: BaselineColors.borderInactive,
          width: 2,
        ),
        borderRadius: BaselineRadius.cardBorderRadius,
      ),
      child: Row(
        children: [
          // Channel indicator dot (Treatment 92).
          Container(
            width: 4,
            height: 4,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: data.isGated
                  ? BaselineColors.textTertiary.atOpacity(0.3)
                  : BaselineColors.teal.atOpacity(0.5),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              data.title,
              style: BaselineTypography.body2.copyWith(
                color: BaselineColors.textPrimary,
              ),
            ),
          ),
          Text(
            data.clearance,
            style: BaselineTypography.dataSmall.copyWith(
              color: BaselineColors.teal.atOpacity(0.3),
              letterSpacing: 0.5,
            ),
          ),
          if (data.isGated) ...[
            const SizedBox(width: 8),
            TierBadge(tier: 'pro'),
          ],
          const SizedBox(width: 8),
          BaselineIcon(
            BaselineIconType.chevronRight,
            size: 16,
            color: BaselineColors.textTertiary,
          ),
        ],
      ),
    );

    // A2-C3: excludeSemantics on nav row Semantics.
    row = Semantics(
      button: true,
      excludeSemantics: true,
      label: data.title,
      child: _PressScaleWidget(
        scale: 0.98,
        onTap: () {
          HapticUtil.selection();
          _resetIdleTimer();
          context.push(data.route);
        },
        child: row,
      ),
    );

    if (data.isGated && data.feature != null) {
      row = FeatureGate(
        feature: data.feature!,
        child: row,
      );
    }

    return row;
  }

  // ═══════════════════════════════════════════════════════════
  // DOSSIER CTA (Treatments 97–107)
  // ═══════════════════════════════════════════════════════════

  Widget _buildDossierCTA() {
    final ctaOpacity = _entranceCtrl.isCompleted
        ? 1.0
        : (_entranceCurve.value * 2.0 - 1.6).clamp(0.0, 1.0);

    return Opacity(
      opacity: ctaOpacity,
      child: FeatureGate(
        feature: AppFeature.dossier,
        onDeclined: () {
          // I-78: Sequential popup gate. Fires on CTA decline.
          SoftPaywallPopup.maybeShow(context);
        },
        // A2-C3: excludeSemantics on dossier CTA Semantics.
        child: Semantics(
          button: true,
          excludeSemantics: true,
          label: 'View Declassified Dossier',
          child: _PressScaleWidget(
            scale: 0.95,
            onTap: () {
              HapticUtil.medium();
              _resetIdleTimer();
              context.push(
                AppRoutes.figureDossierPath(widget.figureId),
              );
            },
            child: Container(
              padding: BaselineInsets.allM,
              decoration: BoxDecoration(
                color: BaselineColors.card,
                border: Border.all(
                  color: BaselineColors.teal.atOpacity(0.15),
                  width: 2,
                ),
                borderRadius: BaselineRadius.cardBorderRadius,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Classification stripe (Treatment 99).
                  ExcludeSemantics(
                    child: Container(
                      height: 3,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(1.5),
                        gradient: LinearGradient(
                          colors: List.generate(10, (i) =>
                            i.isEven
                              ? BaselineColors.teal.atOpacity(0.15)
                              : Colors.transparent,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  Row(
                    children: [
                      // Lock icon (Treatment 107).
                      BaselineIcon(
                        BaselineIconType.lock,
                        size: 16,
                        color: BaselineColors.teal.atOpacity(0.2),
                      ),
                      const SizedBox(width: 8),
                      // "RESTRICTED ACCESS" (Treatment 98).
                      Text(
                        'RESTRICTED ACCESS',
                        style: BaselineTypography.dataSmall.copyWith(
                          color: BaselineColors.amber.atOpacity(0.4),
                          letterSpacing: 1.0,
                        ),
                      ),
                      const Spacer(),
                      TierBadge(tier: 'pro_plus'),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // CTA text (Treatment 100).
                  Text(
                    'View Declassified Dossier\u2122 \u2192',
                    style: BaselineTypography.body1.copyWith(
                      color: BaselineColors.teal,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Complete analytical profile. Every surface, one view.',
                    style: BaselineTypography.body2.copyWith(
                      color: BaselineColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Redacted preview lines (Treatment 106).
                  ExcludeSemantics(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final w in [0.3, 0.5, 0.4])
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: FractionallySizedBox(
                              widthFactor: w,
                              child: Container(
                                height: 2,
                                color: BaselineColors.teal.atOpacity(0.04),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // METHODOLOGY FOOTER (Treatments 133–136)
  // ═══════════════════════════════════════════════════════════

  Widget _buildMethodologyFooter() {
    return Column(
      children: [
        // A2-C3: excludeSemantics on methodology Semantics.
        Semantics(
          button: true,
          excludeSemantics: true,
          label: 'How Figure Profiles work',
          child: _PressScaleWidget(
            scale: 0.95,
            onTap: () {
              HapticUtil.light();
              _resetIdleTimer();
              InfoBottomSheet.show(context, key: 'figure_profile');
            },
            child: Text(
              'How Figure Profiles work \u2192',
              style: BaselineTypography.body2.copyWith(
                color: BaselineColors.teal,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        // Triple hairline close (Treatment 134).
        ExcludeSemantics(
          child: Column(
            children: [
              for (var i = 0; i < 3; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Container(
                    height: 1,
                    color: BaselineColors.teal.atOpacity(0.03),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════
  // BOOKMARK ICON (Treatment 137)
  // ═══════════════════════════════════════════════════════════

  Widget _buildBookmarkIcon() {
    return Positioned(
      top: _safePadding.top + 12,
      right: 60,
      child: Semantics(
        button: true,
        label: 'Save to bookmarks',
        child: FeatureGate(
          feature: AppFeature.annotations,
          child: _PressScaleWidget(
            scale: 0.95,
            onTap: () {
              HapticUtil.selection();
              _resetIdleTimer();
              // Annotation quick-save (note optional).
            },
            child: SizedBox(
              width: 44,
              height: 44,
              child: Center(
                child: BaselineIcon(
                  BaselineIconType.bookmark,
                  size: 24,
                  color: BaselineColors.teal.atOpacity(0.25),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // DOSSIER MODE (Treatments 108–132 + 144)
  // ═══════════════════════════════════════════════════════════

  Widget _buildDossierMode() {
    return Stack(
      children: [
        // Layer 1: Dossier chrome (I-79: isolated).
        RepaintBoundary(
          child: AnimatedBuilder(
            animation: Listenable.merge([_blurCurve, _pulseCtrl]),
            builder: (_, _) {
              return ExcludeSemantics(
                child: CustomPaint(
                  painter: _DossierChromePainter(
                    opacity: _blurCurve.value,
                    pulsePhase: _pulseCtrl.value,
                    figureId: widget.figureId,
                  ),
                  size: Size.infinite,
                ),
              );
            },
          ),
        ),

        // Layer 2: Content.
        Column(
          children: [
            _buildClassifiedAccessHeader(),
            Expanded(
              child: DossierPlate(
                figureId: widget.figureId,
                baselineScore: _baselineScore,
              ),
            ),
          ],
        ),

        // Layer 3: Clearance overlay (entrance).
        if (!_hasSeenDossierEntrance || _clearanceCtrl.isAnimating)
          _buildClearanceOverlay(),

        // Layer 4: Re-seal overlay (exit).
        if (_isResealing) _buildResealOverlay(),
      ],
    );
  }

  Widget _buildClassifiedAccessHeader() {
    return Container(
      padding: EdgeInsets.only(
        top: _safePadding.top + 8,
        left: 16,
        right: 16,
        bottom: 8,
      ),
      decoration: BoxDecoration(
        color: BaselineColors.nearBlack,
        border: Border(
          bottom: BorderSide(
            color: BaselineColors.teal.atOpacity(0.08),
            width: 1,
          ),
        ),
      ),
      child: Column(
        children: [
          // Row 1: Back + Classification + Session + Badge.
          Row(
            children: [
              // A2-C3: excludeSemantics on classified header back button.
              Semantics(
                button: true,
                excludeSemantics: true,
                label: 'Return to personnel file',
                child: _PressScaleWidget(
                  scale: 0.95,
                  onTap: _handleDossierBack,
                  child: SizedBox(
                    height: 44,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CustomPaint(
                            painter: _ReturnArrowPainter(),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'RETURN TO FILE',
                          style: BaselineTypography.dataSmall.copyWith(
                            color: BaselineColors.textSecondary,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const Spacer(),
              Flexible(
                child: ExcludeSemantics(
                  child: Text(
                    'CLASSIFICATION: DECLASSIFIED',
                    overflow: TextOverflow.ellipsis,
                    style: BaselineTypography.dataSmall.copyWith(
                      color: BaselineColors.teal.atOpacity(0.12),
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
              const Spacer(),
              Flexible(
                child: ExcludeSemantics(
                  child: Text(
                    'SESSION: $_sessionElapsed',
                    overflow: TextOverflow.ellipsis,
                    style: BaselineTypography.dataSmall.copyWith(
                      color: BaselineColors.teal.atOpacity(0.2),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6, vertical: 2,
                ),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: BaselineColors.teal.atOpacity(0.3),
                    width: 1,
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'PRO+',
                  style: BaselineTypography.dataSmall.copyWith(
                    color: BaselineColors.teal,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),

          // Row 2: Baseline™ + Pipeline + Session integrity (cherry 144).
          Row(
            children: [
              ExcludeSemantics(
                child: Text(
                  _baselineScore != null
                      ? 'BASELINE\u2122 ${_baselineScore!.toStringAsFixed(1)}'
                      : 'BASELINE\u2122 \u2014',
                  style: BaselineTypography.dataSmall.copyWith(
                    color: BaselineColors.teal.atOpacity(0.4),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              _buildPipelineDots(),
              const Spacer(),
              // Cherry 144: Session integrity.
              Flexible(
                child: ExcludeSemantics(
                  child: Text(
                    'SESSION INTEGRITY: VERIFIED',
                    overflow: TextOverflow.ellipsis,
                    style: BaselineTypography.dataSmall.copyWith(
                      color: BaselineColors.teal.atOpacity(0.08),
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),

          // Film perforation separator (Treatment 123).
          ExcludeSemantics(
            child: SizedBox(
              height: _kPerfHeight,
              child: CustomPaint(
                painter: _FilmPerforationPainter(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPipelineDots() {
    const pipelines = ['GP', 'CL', 'GR'];
    return ExcludeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < pipelines.length; i++) ...[
            if (i > 0)
              Text(
                ' \u00B7 ',
                style: BaselineTypography.dataSmall.copyWith(
                  color: BaselineColors.textTertiary.atOpacity(0.2),
                ),
              ),
            Text(
              pipelines[i],
              style: BaselineTypography.dataSmall.copyWith(
                color: BaselineColors.teal.atOpacity(0.3),
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(width: 2),
            Container(
              width: 4,
              height: 4,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: BaselineColors.teal.atOpacity(0.6),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildClearanceOverlay() {
    return AnimatedBuilder(
      animation: Listenable.merge([
        _clearanceCurve, _blurCurve, _stampCurve,
      ]),
      builder: (_, _) {
        final blurSigma = _kMaxBlurSigma * (1.0 - _blurCurve.value);

        return BackdropFilter(
          filter: ui.ImageFilter.blur(
            sigmaX: blurSigma, sigmaY: blurSigma,
          ),
          child: Container(
            color: BaselineColors.black.atOpacity(
              0.3 * (1.0 - _blurCurve.value),
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Verification bar (Treatment 108).
                  if (_clearanceCurve.value < 0.5)
                    Opacity(
                      opacity: (1.0 - _clearanceCurve.value * 2)
                          .clamp(0.0, 1.0),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: BaselineColors.teal.atOpacity(0.06),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'VERIFYING CLEARANCE',
                          style: BaselineTypography.dataSmall.copyWith(
                            color: BaselineColors.teal.atOpacity(0.5),
                            letterSpacing: 2.0,
                          ),
                        ),
                      ),
                    ),

                  // "ACCESS GRANTED" (Treatment 110).
                  if (_clearanceCurve.value >= 0.33 &&
                      _clearanceCurve.value < 0.85)
                    Transform.rotate(
                      angle: 0.05,
                      child: Opacity(
                        opacity: _clearanceCurve.value < 0.6
                            ? ((_clearanceCurve.value - 0.33) / 0.27)
                                .clamp(0.0, 1.0)
                            : ((0.85 - _clearanceCurve.value) / 0.25)
                                .clamp(0.0, 1.0),
                        child: Text(
                          'ACCESS GRANTED',
                          style: BaselineTypography.h2.copyWith(
                            color: BaselineColors.teal.atOpacity(0.15),
                            fontWeight: FontWeight.w600,
                            letterSpacing: 4.0,
                          ),
                        ),
                      ),
                    ),

                  // "DECLASSIFIED" (Treatment 112).
                  if (_stampCurve.value > 0.0)
                    Transform.rotate(
                      angle: -0.03,
                      child: Opacity(
                        opacity: (_stampCurve.value * 2).clamp(0.0, 1.0) *
                            (1.0 - _blurCurve.value).clamp(0.0, 1.0),
                        child: Text(
                          'DECLASSIFIED',
                          style: BaselineTypography.dataSmall.copyWith(
                            color: BaselineColors.teal.atOpacity(0.1),
                            letterSpacing: 3.0,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildResealOverlay() {
    return AnimatedBuilder(
      animation: _resealCurve,
      builder: (_, _) {
        final sigma = _kResealSigma * _resealCurve.value;
        return BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
          child: Container(
            color: BaselineColors.black.atOpacity(0.2 * _resealCurve.value),
            child: Center(
              child: Opacity(
                opacity: _resealCurve.value > 0.3
                    ? ((_resealCurve.value - 0.3) / 0.4).clamp(0.0, 1.0)
                    : 0.0,
                child: ExcludeSemantics(
                  child: Text(
                    'RECORD SEALED',
                    style: BaselineTypography.dataSmall.copyWith(
                      color: BaselineColors.teal.atOpacity(0.15),
                      letterSpacing: 3.0,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════
  // LOADING / ERROR
  // ═══════════════════════════════════════════════════════════

  Widget _buildLoading() {
    return Center(
      child: ShimmerLoading(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: BaselineColors.card,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              width: 160,
              height: 20,
              decoration: BoxDecoration(
                color: BaselineColors.card,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          BaselineIcon(
            BaselineIconType.error,
            size: 48,
            color: BaselineColors.amber, // I-58: amber, never red.
          ),
          const SizedBox(height: 16),
          Text(
            'Unable to load personnel file.',
            style: BaselineTypography.body1.copyWith(
              color: BaselineColors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          Semantics(
            button: true,
            child: _PressScaleWidget(
              scale: 0.95,
              onTap: () {
                HapticUtil.light();
                setState(() { _isLoading = true; _hasError = false; });
                ref.invalidate(figureProvider(widget.figureId));
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24, vertical: 12,
                ),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: BaselineColors.teal.atOpacity(0.3),
                    width: 2,
                  ),
                  borderRadius: BaselineRadius.cardBorderRadius,
                ),
                child: Text(
                  'RETRY',
                  style: BaselineTypography.data.copyWith(
                    color: BaselineColors.teal,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// HELPER DATA
// ═══════════════════════════════════════════════════════════

class _NavRowData {
  const _NavRowData({
    required this.title,
    required this.clearance,
    required this.route,
    this.isGated = false,
    this.feature,
  });

  final String title;
  final String clearance;
  final String route;
  final bool isGated;
  final AppFeature? feature;
}

// ═══════════════════════════════════════════════════════════
// _PressScaleWidget
// ═══════════════════════════════════════════════════════════

class _PressScaleWidget extends StatefulWidget {
  const _PressScaleWidget({
    required this.child,
    required this.onTap,
    this.scale = 0.98,
  });

  final Widget child;
  final VoidCallback onTap;
  final double scale;

  @override
  State<_PressScaleWidget> createState() => _PressScaleWidgetState();
}

class _PressScaleWidgetState extends State<_PressScaleWidget> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque, // I-62
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? widget.scale : 1.0,
        duration: const Duration(milliseconds: 100),
        child: widget.child,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// PAINTERS
// ═══════════════════════════════════════════════════════════

// ── _PersonnelFilePainter (9-layer, Treatments 1–14a + cherry 139) ──
// A2-C2: Receives pre-computed TextPainters for static text.
// A2-I2: Ambient pulse uses solid alpha math, no per-frame shader.

class _PersonnelFilePainter extends CustomPainter {
  _PersonnelFilePainter({
    required this.pulsePhase,
    required this.scanlinePhase,
    required this.ambientScanPhase,
    required this.monitorPulsePhase,
    required this.figureId,
    required this.textScaler,
    required this.safeTop,
    this.tpFileTab,
    this.tpHandling,
    this.tpSerial,
    this.tpAccessLog,
  })  : _perfPaint = Paint()
          ..color = BaselineColors.teal.atOpacity(0.04),
        _hairlinePaint = Paint()
          ..color = BaselineColors.teal.atOpacity(0.04)
          ..strokeWidth = 1.0,
        _busPaint = Paint()
          ..color = BaselineColors.teal.atOpacity(_kDataBusOpacity)
          ..strokeWidth = 1.0,
        _junctionPaint = Paint()
          ..color = BaselineColors.teal.atOpacity(0.08);

  final double pulsePhase;
  final double scanlinePhase;
  final double ambientScanPhase;
  final double monitorPulsePhase;
  final String figureId;
  final TextScaler textScaler;
  final double safeTop;

  // A2-C2: Pre-computed TextPainters (static, laid out in state).
  final TextPainter? tpFileTab;
  final TextPainter? tpHandling;
  final TextPainter? tpSerial;
  final TextPainter? tpAccessLog;

  // Paint finals (I-71).
  final Paint _perfPaint;
  final Paint _hairlinePaint;
  final Paint _busPaint;
  final Paint _junctionPaint;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Layer 1: File tab (Treatment 2). A2-C2: use pre-computed TP.
    _paintFileTab(canvas, w);

    // Layer 2: Classification hairlines (Treatment 3).
    canvas.drawLine(Offset(20, 40), Offset(w - 20, 40), _hairlinePaint);
    canvas.drawLine(Offset(20, 42), Offset(w - 20, 42), _hairlinePaint);

    // Layer 3: Hashmark ruler (Treatment 7).
    for (var i = 0; i < 7; i++) {
      final x = 30.0 + (w - 60) * i / 6;
      canvas.drawLine(
        Offset(x, 44), Offset(x, 48),
        _hairlinePaint,
      );
    }

    // Layer 4: Compound reticle corners (Treatment 4, I-51).
    _paintCompoundCorner(canvas, 6, 6, 1, 1);
    _paintCompoundCorner(canvas, w - 6, 6, -1, 1);
    _paintCompoundCorner(canvas, 6, h - 6, 1, -1);
    _paintCompoundCorner(canvas, w - 6, h - 6, -1, -1);

    // Layer 5: Film perforations - right edge (Treatment 5).
    for (var y = 50.0; y < h - 20; y += _kPerfSpacing + _kPerfHeight) {
      canvas.drawRect(
        Rect.fromLTWH(w - _kPerfWidth - 4, y, _kPerfWidth, _kPerfHeight),
        _perfPaint,
      );
    }

    // Layer 6: Intel dot grid (Treatment 6).
    for (var r = 0; r < 3; r++) {
      for (var c = 0; c < 3; c++) {
        canvas.drawCircle(
          Offset(16.0 + c * 6, h - 40.0 + r * 6),
          1.0,
          Paint()..color = BaselineColors.teal.atOpacity(0.03),
        );
      }
    }

    // Layer 7: Section data bus (Treatment 14).
    canvas.drawLine(
      Offset(12, 100), Offset(12, h - 100), _busPaint,
    );
    // Junction dots at section boundaries.
    for (final jy in [160.0, 280.0, 400.0, 520.0, 640.0]) {
      if (jy < h - 100) {
        canvas.drawCircle(
          Offset(12, jy), _kJunctionDotRadius, _junctionPaint,
        );
      }
    }

    // Layer 8: Ambient right-border pulse (Treatment 11).
    // A2-I2: Solid alpha math instead of per-frame gradient shader.
    if (pulsePhase > 0.0) {
      final pulseY = h * pulsePhase;
      final peakAlpha = 0.04;
      // Paint 3 segments simulating gradient fade: outer at 25%, inner at 100%.
      for (final seg in [
        _PulseSegment(pulseY - 30, pulseY - 10, peakAlpha * 0.25),
        _PulseSegment(pulseY - 10, pulseY + 10, peakAlpha),
        _PulseSegment(pulseY + 10, pulseY + 30, peakAlpha * 0.25),
      ]) {
        canvas.drawLine(
          Offset(w - 1, seg.y0),
          Offset(w - 1, seg.y1),
          Paint()
            ..color = BaselineColors.teal.atOpacity(seg.alpha)
            ..strokeWidth = 2.0
            ..style = PaintingStyle.stroke,
        );
      }
    }

    // Layer 8b: Ambient scanline (Treatment 13).
    if (ambientScanPhase > 0.0 && ambientScanPhase < 1.0) {
      final scanY = h * ambientScanPhase;
      canvas.drawLine(
        Offset(20, scanY),
        Offset(w - 20, scanY),
        Paint()
          ..color = BaselineColors.teal.atOpacity(0.02)
          ..strokeWidth = 1.0,
      );
    }

    // Layer 9: Handling mark + document serial (Treatments 8–10). A2-C2.
    _paintChromText(canvas, w, h);

    // Layer 9b: "● MONITORING ACTIVE" pulse (Treatment 14a).
    // Monitoring text: only dynamic TP (1 per frame, acceptable).
    _paintMonitoringText(canvas, w);

    // Cherry 139: File access log. A2-C2: pre-computed.
    _paintAccessLog(canvas, w, h);
  }

  void _paintFileTab(Canvas canvas, double w) {
    final tabRect = RRect.fromRectAndCorners(
      Rect.fromCenter(center: Offset(w / 2, 14), width: 140, height: 28),
      topLeft: const Radius.circular(6),
      topRight: const Radius.circular(6),
    );
    canvas.drawRRect(
      tabRect,
      Paint()..color = BaselineColors.teal.atOpacity(0.03),
    );
    // A2-C2: Use pre-computed TextPainter (no alloc/layout/dispose per frame).
    if (tpFileTab != null) {
      tpFileTab!.paint(canvas, Offset((w - tpFileTab!.width) / 2, 5));
    }
  }

  void _paintCompoundCorner(
    Canvas canvas, double x, double y, double dx, double dy,
  ) {
    final outer = Paint()
      ..color = BaselineColors.teal.atOpacity(0.06)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..strokeCap = StrokeCap.square;
    // Outer L (6px arm).
    canvas.drawLine(Offset(x, y), Offset(x + 6 * dx, y), outer);
    canvas.drawLine(Offset(x, y), Offset(x, y + 6 * dy), outer);
    // Inner tick (3px, offset 4px inward).
    final inner = Paint()
      ..color = BaselineColors.teal.atOpacity(0.04)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;
    final ix = x + 4 * dx;
    final iy = y + 4 * dy;
    canvas.drawLine(Offset(ix, iy), Offset(ix + 3 * dx, iy), inner);
    canvas.drawLine(Offset(ix, iy), Offset(ix, iy + 3 * dy), inner);
    // Corner dot.
    canvas.drawCircle(
      Offset(x + 2 * dx, y + 2 * dy),
      1.0,
      Paint()..color = BaselineColors.teal.atOpacity(0.08),
    );
  }

  void _paintChromText(Canvas canvas, double w, double h) {
    // Handling mark (Treatment 8). A2-C2: pre-computed.
    if (tpHandling != null) {
      tpHandling!.paint(canvas, Offset((w - tpHandling!.width) / 2, h - 30));
    }

    // Document serial (Treatment 9). A2-C2: pre-computed.
    if (tpSerial != null) {
      tpSerial!.paint(canvas, Offset(w - tpSerial!.width - 12, 50));
    }
  }

  void _paintMonitoringText(Canvas canvas, double w) {
    // Dynamic: opacity varies per frame. Single TP per frame (acceptable).
    final opacity = 0.04 * (0.5 + 0.5 * math.sin(monitorPulsePhase * math.pi));
    if (opacity < 0.001) return;
    final tp = TextPainter(
      text: TextSpan(
        text: '\u25CF MONITORING ACTIVE',
        style: TextStyle(
          fontFamily: BaselineTypography.monoFontFamily,
          fontSize: textScaler.scale(8),
          color: BaselineColors.teal.atOpacity(opacity),
          letterSpacing: 0.5,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset((w - tp.width) / 2, safeTop + 8));
    tp.dispose(); // I-23
  }

  void _paintAccessLog(Canvas canvas, double w, double h) {
    // A2-C2: Use pre-computed TextPainter.
    if (tpAccessLog != null) {
      tpAccessLog!.paint(canvas, Offset(16, h - 44));
    }
  }

  @override
  bool shouldRepaint(covariant _PersonnelFilePainter old) =>
      pulsePhase != old.pulsePhase ||
      scanlinePhase != old.scanlinePhase ||
      ambientScanPhase != old.ambientScanPhase ||
      monitorPulsePhase != old.monitorPulsePhase;
}

/// A2-I2: Helper for solid-segment pulse (replaces per-frame gradient).
class _PulseSegment {
  const _PulseSegment(this.y0, this.y1, this.alpha);
  final double y0;
  final double y1;
  final double alpha;
}

// ── _DossierChromePainter (elevated, Treatment 127) ──
// A2-I2: Gradient shaders replaced with solid alpha math.

class _DossierChromePainter extends CustomPainter {
  _DossierChromePainter({
    required this.opacity,
    required this.pulsePhase,
    required this.figureId,
  });

  final double opacity;
  final double pulsePhase;
  final String figureId;

  @override
  void paint(Canvas canvas, Size size) {
    if (opacity <= 0.0) return;
    final w = size.width;
    final h = size.height;

    // Elevated reticle corners (8px arms).
    _drawCorner(canvas, 6, 6, 1, 1, 8.0);
    _drawCorner(canvas, w - 6, 6, -1, 1, 8.0);
    _drawCorner(canvas, 6, h - 6, 1, -1, 8.0);
    _drawCorner(canvas, w - 6, h - 6, -1, -1, 8.0);

    // Film perforations BOTH edges.
    for (var y = 50.0; y < h - 20; y += _kPerfSpacing + _kPerfHeight) {
      final adjustedPaint = Paint()
        ..color = BaselineColors.teal.atOpacity(0.04 * opacity);
      canvas.drawRect(
        Rect.fromLTWH(4, y, _kPerfWidth, _kPerfHeight),
        adjustedPaint,
      );
      canvas.drawRect(
        Rect.fromLTWH(w - _kPerfWidth - 4, y, _kPerfWidth, _kPerfHeight),
        adjustedPaint,
      );
    }

    // A2-I2: Left teal border glow - solid segments instead of gradient.
    final leftAlpha = 0.06 * opacity;
    for (final seg in [
      _PulseSegment(h * 0.2, h * 0.35, leftAlpha * 0.3),
      _PulseSegment(h * 0.35, h * 0.65, leftAlpha),
      _PulseSegment(h * 0.65, h * 0.8, leftAlpha * 0.3),
    ]) {
      canvas.drawLine(
        Offset(1, seg.y0), Offset(1, seg.y1),
        Paint()
          ..color = BaselineColors.teal.atOpacity(seg.alpha)
          ..strokeWidth = 2.0
          ..style = PaintingStyle.stroke,
      );
    }

    // A2-I2: Right ambient pulse - solid segments.
    if (pulsePhase > 0.0) {
      final pulseY = h * pulsePhase;
      final peakAlpha = 0.06 * opacity;
      for (final seg in [
        _PulseSegment(pulseY - 30, pulseY - 10, peakAlpha * 0.25),
        _PulseSegment(pulseY - 10, pulseY + 10, peakAlpha),
        _PulseSegment(pulseY + 10, pulseY + 30, peakAlpha * 0.25),
      ]) {
        canvas.drawLine(
          Offset(w - 1, seg.y0), Offset(w - 1, seg.y1),
          Paint()
            ..color = BaselineColors.teal.atOpacity(seg.alpha)
            ..strokeWidth = 2.0
            ..style = PaintingStyle.stroke,
        );
      }
    }
  }

  void _drawCorner(Canvas canvas, double x, double y,
      double dx, double dy, double arm) {
    final p = Paint()
      ..color = BaselineColors.teal.atOpacity(0.06 * opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..strokeCap = StrokeCap.square;
    canvas.drawLine(Offset(x, y), Offset(x + arm * dx, y), p);
    canvas.drawLine(Offset(x, y), Offset(x, y + arm * dy), p);
    canvas.drawCircle(
      Offset(x + 1 * dx, y + 1 * dy), 1.0,
      Paint()..color = BaselineColors.teal.atOpacity(0.08 * opacity),
    );
  }

  @override
  bool shouldRepaint(covariant _DossierChromePainter old) =>
      opacity != old.opacity || pulsePhase != old.pulsePhase;
}

// ── _AssessmentGaugePainter (Treatments 36–40) ──
// A2-M1: textScaler removed (unused dead param).

class _AssessmentGaugePainter extends CustomPainter {
  _AssessmentGaugePainter({
    required this.score,
    required this.progress,
  })  : _trackPaint = Paint()
          ..color = BaselineColors.teal.atOpacity(0.08),
        _tickPaint = Paint()
          ..color = BaselineColors.teal.atOpacity(0.06)
          ..strokeWidth = 0.5;

  final double? score;
  final double progress;
  final Paint _trackPaint;
  final Paint _tickPaint;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final trackY = size.height / 2 - _kGaugeTrackHeight / 2;

    // Track (Treatment 37).
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, trackY, w, _kGaugeTrackHeight),
        const Radius.circular(2),
      ),
      _trackPaint,
    );

    // Hashmark ruler ticks.
    for (var i = 0; i <= 10; i++) {
      final x = w * i / 10;
      final tickH = i % 5 == 0 ? 6.0 : 3.0;
      canvas.drawLine(
        Offset(x, trackY - tickH),
        Offset(x, trackY),
        _tickPaint,
      );
    }

    if (score == null || progress <= 0.0) return;

    final normalizedScore = (score! / 100.0).clamp(0.0, 1.0);
    final fillWidth = w * normalizedScore * progress;

    // Fill (Treatment 38).
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, trackY, fillWidth, _kGaugeTrackHeight),
        const Radius.circular(2),
      ),
      Paint()
        ..shader = ui.Gradient.linear(
          Offset.zero, Offset(fillWidth, 0),
          [
            BaselineColors.teal.atOpacity(0.15),
            BaselineColors.teal.atOpacity(0.5),
          ],
        ),
    );

    // Needle (Treatment 39).
    final needleX = fillWidth;
    canvas.drawLine(
      Offset(needleX, trackY - 4),
      Offset(needleX, trackY + _kGaugeTrackHeight + 4),
      Paint()
        ..color = BaselineColors.teal
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round,
    );

    // Needle glow bloom (Treatment 40).
    canvas.drawCircle(
      Offset(needleX, trackY + _kGaugeTrackHeight / 2),
      6.0,
      Paint()
        ..color = BaselineColors.teal.atOpacity(0.2 * progress)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0),
    );
  }

  @override
  bool shouldRepaint(covariant _AssessmentGaugePainter old) =>
      score != old.score || progress != old.progress;
}

// ── _ConfidenceBarPainter (Treatments 44a–b) ──

class _ConfidenceBarPainter extends CustomPainter {
  _ConfidenceBarPainter({required this.fill, required this.opacity})
    : _trackPaint = Paint()..color = BaselineColors.teal.atOpacity(0.04),
      _tickPaint = Paint()
        ..color = BaselineColors.teal.atOpacity(0.06)
        ..strokeWidth = 0.5;

  final double fill;
  final double opacity;
  final Paint _trackPaint;
  final Paint _tickPaint;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Track.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 1, w, 2),
        const Radius.circular(1),
      ),
      _trackPaint,
    );

    // Fill.
    if (fill > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, 1, w * fill, 2),
          const Radius.circular(1),
        ),
        Paint()
          ..shader = ui.Gradient.linear(
            Offset.zero, Offset(w * fill, 0),
            [
              BaselineColors.teal.atOpacity(opacity * 0.5),
              BaselineColors.teal.atOpacity(opacity),
            ],
          ),
      );
    }

    // Threshold ticks at 5/20/50 (out of ~60 max).
    for (final threshold in [5.0 / 60, 20.0 / 60, 50.0 / 60]) {
      final x = w * threshold;
      canvas.drawLine(Offset(x, 0), Offset(x, h), _tickPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _ConfidenceBarPainter old) =>
      fill != old.fill || opacity != old.opacity;
}

// ── _CalibratingCirclePainter (calibrating state, rotating dashed circle) ──

class _CalibratingCirclePainter extends CustomPainter {
  _CalibratingCirclePainter({required this.rotation, required this.color});

  final double rotation;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 1;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..strokeCap = StrokeCap.round;

    const dashCount = 12;
    const gapFraction = 0.4;
    const dashSweep = (2 * math.pi / dashCount) * (1 - gapFraction);
    const gapSweep = (2 * math.pi / dashCount) * gapFraction;

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(rotation);
    canvas.translate(-center.dx, -center.dy);

    for (int i = 0; i < dashCount; i++) {
      final startAngle = i * (dashSweep + gapSweep) - math.pi / 2;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        dashSweep,
        false,
        paint,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CalibratingCirclePainter old) =>
      rotation != old.rotation || color != old.color;
}

// ── _ReturnArrowPainter (Treatment 117, unique to dossier) ──

class _ReturnArrowPainter extends CustomPainter {
  _ReturnArrowPainter()
    : _paint = Paint()
        ..color = BaselineColors.textSecondary
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

  final Paint _paint;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final path = Path()
      ..moveTo(w * 0.8, h * 0.3)
      ..quadraticBezierTo(w * 0.85, h * 0.6, w * 0.5, h * 0.65)
      ..lineTo(w * 0.2, h * 0.65);
    canvas.drawPath(path, _paint);
    final arrow = Path()
      ..moveTo(w * 0.35, h * 0.5)
      ..lineTo(w * 0.2, h * 0.65)
      ..lineTo(w * 0.35, h * 0.8);
    canvas.drawPath(arrow, _paint);
  }

  @override
  bool shouldRepaint(_ReturnArrowPainter old) => false;
}

// ── _HashmarkDividerPainter (Treatment 50) ──

class _HashmarkDividerPainter extends CustomPainter {
  _HashmarkDividerPainter()
    : _paint = Paint()
        ..color = BaselineColors.teal.atOpacity(0.06)
        ..strokeWidth = 0.5;

  final Paint _paint;

  @override
  void paint(Canvas canvas, Size size) {
    final x = size.width / 2;
    final h = size.height;
    canvas.drawLine(Offset(x, 4), Offset(x, h - 4), _paint);
    for (var i = 0; i < 3; i++) {
      final ty = 8.0 + (h - 16) * i / 2;
      canvas.drawLine(Offset(x - 2, ty), Offset(x + 2, ty), _paint);
    }
  }

  @override
  bool shouldRepaint(_HashmarkDividerPainter old) => false;
}

// ── _FilmPerforationPainter (Treatment 123) ──

class _FilmPerforationPainter extends CustomPainter {
  _FilmPerforationPainter()
    : _paint = Paint()..color = BaselineColors.teal.atOpacity(0.04);

  final Paint _paint;

  @override
  void paint(Canvas canvas, Size size) {
    final count = (size.width / (_kPerfWidth + 4)).floor();
    final totalWidth = count * (_kPerfWidth + 4) - 4;
    final startX = (size.width - totalWidth) / 2;
    for (var i = 0; i < count; i++) {
      canvas.drawRect(
        Rect.fromLTWH(
          startX + i * (_kPerfWidth + 4),
          0,
          _kPerfWidth,
          _kPerfHeight,
        ),
        _paint,
      );
    }
  }

  @override
  bool shouldRepaint(_FilmPerforationPainter old) => false;
}

// ── _DashedCirclePainter (Treatment 65) ──

class _DashedCirclePainter extends CustomPainter {
  _DashedCirclePainter()
    : _paint = Paint()
        ..color = BaselineColors.textTertiary.atOpacity(0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;

  final Paint _paint;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2 - 2;
    final c = Offset(size.width / 2, size.height / 2);
    const segments = 12;
    const gap = 0.15;
    for (var i = 0; i < segments; i++) {
      final startAngle = (2 * math.pi * i / segments) + gap;
      final sweepAngle = (2 * math.pi / segments) - 2 * gap;
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r),
        startAngle, sweepAngle, false, _paint,
      );
    }
  }

  @override
  bool shouldRepaint(_DashedCirclePainter old) => false;
}

// ── Cherry 140: _AvatarTickPainter ──

class _AvatarTickPainter extends CustomPainter {
  _AvatarTickPainter({required this.color})
    : _paint = Paint()
        ..color = color
        ..strokeWidth = 0.5;

  final Color color;
  final Paint _paint;

  @override
  void paint(Canvas canvas, Size size) {
    // 4 tiny hashmark ticks centered under avatar.
    final cx = size.width / 2;
    for (var i = -2; i <= 1; i++) {
      final x = cx + i * 12.0 + 6;
      canvas.drawLine(Offset(x, 0), Offset(x, 4), _paint);
    }
  }

  @override
  bool shouldRepaint(_AvatarTickPainter old) => color != old.color;
}

// ── Cherry 143: _IntelSparklinePainter ──

class _IntelSparklinePainter extends CustomPainter {
  _IntelSparklinePainter({required this.data})
    : _linePaint = Paint()
        ..color = BaselineColors.teal.atOpacity(0.2)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..strokeCap = StrokeCap.round,
      _fillPaint = Paint()
        ..color = BaselineColors.teal.atOpacity(0.04);

  final List<double> data;
  final Paint _linePaint;
  final Paint _fillPaint;

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;
    final w = size.width;
    final h = size.height;
    final stepX = w / (data.length - 1).clamp(1, 999);

    final path = Path();
    final fillPath = Path();
    fillPath.moveTo(0, h);

    for (var i = 0; i < data.length; i++) {
      final x = i * stepX;
      final y = h - (data[i].clamp(0.0, 1.0) * h * 0.8);
      if (i == 0) {
        path.moveTo(x, y);
        fillPath.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }

    fillPath.lineTo(w, h);
    fillPath.close();
    canvas.drawPath(fillPath, _fillPaint);
    canvas.drawPath(path, _linePaint);
  }

  @override
  bool shouldRepaint(covariant _IntelSparklinePainter old) =>
      data != old.data;
}
