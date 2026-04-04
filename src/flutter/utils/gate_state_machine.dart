import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:baseline_app/models/gate_types.dart';

/// Paywall funnel state machine.
///
/// Tracks user taps on gated features and advances through stages:
/// glimpse -> taste -> drop (paywall).
const int _kMaxFeatureLength = 64;

const Duration _kDebounceWindow = Duration(milliseconds: 500);
const int _kMaxJourneyFeatures = 50;
const Duration _kMaybeLaterCooldown = Duration(days: 14);

class GateStateMachine {
  static bool get isInCooldown {
    if (_cooldownUntilMs == null) return false;
    return DateTime.now().millisecondsSinceEpoch < _cooldownUntilMs!;
  }
  static Duration? get cooldownRemaining {
    if (_cooldownUntilMs == null) return null;
    final remaining = _cooldownUntilMs! - DateTime.now().millisecondsSinceEpoch;
    if (remaining <= 0) return null;
    return Duration(milliseconds: remaining);
  }
  static final _eventController = StreamController<GateFunnelEvent>.broadcast();
  static Stream<GateFunnelEvent> get onEvent => _eventController.stream;

  static Future<void> startCooldown(Duration duration) async {
    _cooldownUntilMs = DateTime.now().add(duration).millisecondsSinceEpoch;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kCooldownKey, _cooldownUntilMs!);
    } catch (_) {}
  }

  static GateStage peek() => _currentStage;

  GateStateMachine._();

  static bool _initialized = false;
  static int _tapCount = 0;
  static GateStage _currentStage = GateStage.glimpse;
  static int? _cooldownUntilMs;
  static int? _firstTapMs;
  static List<String> _journey = [];

  // SharedPreferences keys
  static const String _kTapCountKey = 'gate_tap_count';
  static const String _kCooldownKey = 'gate_cooldown_until';
  static const String _kFirstTapKey = 'gate_first_tap';
  static const String _kJourneyKey = 'gate_journey';
  static const Duration _kPrefsTimeout = Duration(seconds: 3);
  static DateTime? _lastAdvanceTime;
  static final _stageController = StreamController<GateStage>.broadcast();

  static void _ensureInit() {
    if (!_initialized) {
      throw StateError('GateStateMachine.init() must be called before use');
    }
  }

  static GateStage _stageFromCount(int count) {
    if (count <= 0) return GateStage.glimpse;
    if (count == 1) return GateStage.taste;
    return GateStage.drop;
  }

  static void _emitEvent(GateFunnelEvent event) {
    if (kDebugMode) debugPrint(event.toString());
    if (!_eventController.isClosed) {
      try { _eventController.add(event); } catch (_) {}
    }
  }

  static GateStage get currentStage {
    _ensureInit();
    return _currentStage;
  }

  static int get tapCount {
    _ensureInit();
    return _tapCount;
  }

static List<String> get journeyFeatures {
_ensureInit();
return List.unmodifiable(_journey);
}
/// Time elapsed since the first tap in this funnel cycle.
///
/// Returns null if no taps recorded in this cycle.
static Duration? get funnelVelocity {
if (_firstTapMs == null) return null;
return DateTime.now().difference(
DateTime.fromMillisecondsSinceEpoch(_firstTapMs!),
);
}
// ── Init ───────────────────────────────────────────
/// Loads persisted state from SharedPreferences.
///
/// Call once at app startup (F0.5 main.dart).
/// All reads are synchronous after this point.
/// Safe to call multiple times - subsequent calls no-op (A2-2).
static Future<void> init() async {
// Guard double-init (A2-2).
if (_initialized) return;
try {
final prefs = await SharedPreferences.getInstance()
.timeout(_kPrefsTimeout);
// Load cooldown.
_cooldownUntilMs = prefs.getInt(_kCooldownKey);
if (_cooldownUntilMs != null) {
final cooldownUntil =
DateTime.fromMillisecondsSinceEpoch(_cooldownUntilMs!);
if (DateTime.now().isBefore(cooldownUntil)) {
_tapCount = 0;
_currentStage = GateStage.glimpse;
_journey = [];
_firstTapMs = null;
_initialized = true;
if (kDebugMode) {
final remaining = cooldownUntil.difference(DateTime.now());
debugPrint(
'GateStateMachine.init: cooldown '
'(${remaining.inDays}d ${remaining.inHours % 24}h left) '
'→ glimpse',
);
}
return;
}
// Cooldown expired - clean up.
_cooldownUntilMs = null;
await prefs.remove(_kCooldownKey);
}
_tapCount = (prefs.getInt(_kTapCountKey) ?? 0).clamp(0, 2);
_currentStage = _stageFromCount(_tapCount);
_firstTapMs = prefs.getInt(_kFirstTapKey);
// Load journey.
final journeyJson = prefs.getString(_kJourneyKey);
if (journeyJson != null) {
try {
final decoded = jsonDecode(journeyJson);
if (decoded is List) {
_journey = decoded.cast<String>().toList();
}
} catch (_) {
_journey = [];
}
} else {
_journey = [];
}
_initialized = true;
if (kDebugMode) {
debugPrint(
'GateStateMachine.init: count=$_tapCount '
'→ ${_currentStage.name}, '
'journey=${_journey.length} features, '
'velocity=${funnelVelocity?.inSeconds ?? '?'}s',
);
}
} catch (e) {
_tapCount = 0;
_currentStage = GateStage.glimpse;
_cooldownUntilMs = null;
_firstTapMs = null;
_journey = [];
_initialized = true;
if (kDebugMode) {
debugPrint('GateStateMachine.init: failed ($e) → glimpse');
}
}
}
// ── Advance ────────────────────────────────────────
/// Records a gate tap and advances the state machine.
///
/// [feature] must be a stable, lowercase identifier
/// (e.g., 'framing_radar'). Trimmed and capped at 60 chars.
/// Empty strings are rejected.
static Future<GateAdvanceResult> advance({
String? feature,
}) async {
_ensureInit();
final now = DateTime.now();
// Sanitize feature ID (A1-X2, A2-5).
final sanitizedFeature = _sanitizeFeature(feature);
// ── Expired cooldown auto-clean ──────────────────
if (_cooldownUntilMs != null && !isInCooldown) {
_cooldownUntilMs = null;
try {
final prefs = await SharedPreferences.getInstance()
.timeout(_kPrefsTimeout);
await prefs.remove(_kCooldownKey);
} catch (_) {}
}
// ── Cooldown check ───────────────────────────────
if (isInCooldown) {
if (kDebugMode) {
debugPrint(
'GateStateMachine.advance: cooldown-blocked '
'(${cooldownRemaining?.inDays}d left)',
);
}
_emitEvent(GateFunnelEvent(
action: GateFunnelAction.cooldownBlocked,
stage: _currentStage,
feature: sanitizedFeature,
tapCount: _tapCount,
timestamp: now,
));
return GateAdvanceResult(
stageAtTap: _currentStage,
currentStage: _currentStage,
wasDebounced: false,
wasCooldownBlocked: true,
feature: sanitizedFeature,
);
}
// ── Debounce guard ───────────────────────────────
if (_lastAdvanceTime != null &&
now.difference(_lastAdvanceTime!) < _kDebounceWindow) {
if (kDebugMode) {
debugPrint(
'GateStateMachine.advance: debounced '
'(${now.difference(_lastAdvanceTime!).inMilliseconds}ms)',
);
}
_emitEvent(GateFunnelEvent(
action: GateFunnelAction.debounced,
stage: _currentStage,
feature: sanitizedFeature,
tapCount: _tapCount,
timestamp: now,
));
return GateAdvanceResult(
stageAtTap: _currentStage,
currentStage: _currentStage,
wasDebounced: true,
wasCooldownBlocked: false,
feature: sanitizedFeature,
);
}
_lastAdvanceTime = now;
// ── Record journey + velocity ────────────────────
if (sanitizedFeature != null &&
_journey.length < _kMaxJourneyFeatures) {
// Case-insensitive dedup (A1-L3).
final lower = sanitizedFeature.toLowerCase();
final isDuplicate = _journey.any((f) => f.toLowerCase() == lower);
if (!isDuplicate) {
_journey.add(sanitizedFeature);
}
}
// First tap in cycle - record start time.
_firstTapMs ??= now.millisecondsSinceEpoch;
// ── Advance stage ────────────────────────────────
final stageAtTap = _currentStage;
if (_currentStage != GateStage.drop) {
_tapCount = (_tapCount + 1).clamp(0, 2); // A1-L1
_currentStage = _stageFromCount(_tapCount);
}
// ── Persist everything ───────────────────────────
try {
final prefs = await SharedPreferences.getInstance()
.timeout(_kPrefsTimeout);
await prefs.setInt(_kTapCountKey, _tapCount);
await prefs.setInt(_kFirstTapKey, _firstTapMs!);
await prefs.setString(_kJourneyKey, jsonEncode(_journey));
} catch (e) {
if (kDebugMode) {
debugPrint(
'GateStateMachine.advance: persist failed ($e)',
);
}
}
// Emit stage change on stream (A1-S3: guarded).
if (_currentStage != stageAtTap) {
_emitStageChange(_currentStage);
}
if (kDebugMode) {
debugPrint(
'GateStateMachine.advance: '
'${stageAtTap.name} → ${_currentStage.name} '
'(count=$_tapCount, feature=$sanitizedFeature, '
'journey=${_journey.join(', ')}, '
'velocity=${funnelVelocity?.inSeconds}s)',
);
}
_emitEvent(GateFunnelEvent(
action: GateFunnelAction.advanced,
stage: _currentStage,
previousStage: stageAtTap,
feature: sanitizedFeature,
tapCount: _tapCount,
timestamp: now,
funnelDuration: funnelVelocity,
journeyFeatures: List.unmodifiable(_journey),
));
return GateAdvanceResult(
stageAtTap: stageAtTap,
currentStage: _currentStage,
wasDebounced: false,
wasCooldownBlocked: false,
feature: sanitizedFeature,
);
}
// ── Maybe Later ────────────────────────────────────
/// User pressed "Maybe Later" on the Drop modal.
///
/// Resets counter, starts 14-day cooldown, clears journey
/// and velocity. Captures pre-clear state in the event.
static Future<void> maybeLater() async {
_ensureInit();
final previousStage = _currentStage;
final velocity = funnelVelocity;
final journey = List<String>.from(_journey);
_tapCount = 0;
_currentStage = GateStage.glimpse;
_journey = [];
_firstTapMs = null;
final cooldownUntil = DateTime.now().add(_kMaybeLaterCooldown);
_cooldownUntilMs = cooldownUntil.millisecondsSinceEpoch;
try {
final prefs = await SharedPreferences.getInstance()
.timeout(_kPrefsTimeout);
await prefs.setInt(_kTapCountKey, 0);
await prefs.setInt(_kCooldownKey, _cooldownUntilMs!);
await prefs.remove(_kJourneyKey);
await prefs.remove(_kFirstTapKey);
} catch (e) {
if (kDebugMode) {
debugPrint(
'GateStateMachine.maybeLater: persist failed ($e)',
);
}
}
_emitStageChange(_currentStage);
_emitEvent(GateFunnelEvent(
action: GateFunnelAction.maybeLater,
stage: _currentStage,
previousStage: previousStage,
tapCount: 0,
timestamp: DateTime.now(),
funnelDuration: velocity,
journeyFeatures: journey,
));
if (kDebugMode) {
debugPrint(
'GateStateMachine.maybeLater: '
'${previousStage.name} → glimpse, '
'velocity=${velocity?.inSeconds}s, '
'journey=$journey, '
'14d cooldown → $cooldownUntil',
);
}
}
// ── Reset ──────────────────────────────────────────
/// Resets the funnel completely.
///
/// Pass [reason]:
/// - [GateFunnelAction.purchaseReset]: F6.2 after upgrade
/// - [GateFunnelAction.signOutReset]: F5.5 on sign-out
static Future<void> reset({
GateFunnelAction reason = GateFunnelAction.purchaseReset,
}) async {
_ensureInit();
assert(
reason == GateFunnelAction.purchaseReset ||
reason == GateFunnelAction.signOutReset,
'reset() reason must be purchaseReset or signOutReset',
);
final previousStage = _currentStage;
final velocity = funnelVelocity;
final journey = List<String>.from(_journey);
_tapCount = 0;
_currentStage = GateStage.glimpse;
_lastAdvanceTime = null;
_cooldownUntilMs = null;
_firstTapMs = null;
_journey = [];
try {
final prefs = await SharedPreferences.getInstance()
.timeout(_kPrefsTimeout);
await prefs.remove(_kTapCountKey);
await prefs.remove(_kCooldownKey);
await prefs.remove(_kJourneyKey);
await prefs.remove(_kFirstTapKey);
} catch (e) {
if (kDebugMode) {
debugPrint('GateStateMachine.reset: persist failed ($e)');
}
}
_emitStageChange(_currentStage);
_emitEvent(GateFunnelEvent(
action: reason,
stage: _currentStage,
previousStage: previousStage,
tapCount: 0,
timestamp: DateTime.now(),
funnelDuration: velocity,
journeyFeatures: journey,
));
if (kDebugMode) {
debugPrint(
'GateStateMachine.reset(${reason.name}): '
'${previousStage.name} → glimpse, '
'velocity=${velocity?.inSeconds}s',
);
}
}
// ── Force Drop (Phase 7) ───────────────────────────
/// Forces the machine to Drop stage.
///
/// Phase 7: "30-day-as-Pro" path triggers Drop directly.
/// Not wired at MVP - infrastructure only.
static Future<void> forceDrop() async {
_ensureInit();
final now = DateTime.now();
final previousStage = _currentStage;
_tapCount = 2;
_currentStage = GateStage.drop;
_cooldownUntilMs = null;
// Ensure velocity is meaningful even from glimpse (A1-L7).
_firstTapMs ??= now.millisecondsSinceEpoch;
try {
final prefs = await SharedPreferences.getInstance()
.timeout(_kPrefsTimeout);
await prefs.setInt(_kTapCountKey, _tapCount);
await prefs.remove(_kCooldownKey);
await prefs.setInt(_kFirstTapKey, _firstTapMs!);
} catch (e) {
if (kDebugMode) {
debugPrint(
'GateStateMachine.forceDrop: persist failed ($e)',
);
}
}
_emitStageChange(_currentStage);
_emitEvent(GateFunnelEvent(
action: GateFunnelAction.forcedDrop,
stage: _currentStage,
previousStage: previousStage,
tapCount: _tapCount,
timestamp: now,
funnelDuration: funnelVelocity,
journeyFeatures: List.unmodifiable(_journey),
));
if (kDebugMode) {
debugPrint(
'GateStateMachine.forceDrop: '
'${previousStage.name} → drop',
);
}
}
// ── Testing ────────────────────────────────────────
/// Resets all in-memory state without touching SharedPreferences.
///
/// Tests only. Isolates between test cases without mocking prefs.
@visibleForTesting
static void resetForTest() {
_tapCount = 0;
_currentStage = GateStage.glimpse;
_lastAdvanceTime = null;
_cooldownUntilMs = null;
_firstTapMs = null;
_journey = [];
_initialized = true;
}
/// Closes the stream controller.
///
/// **Tests only - do not call in production.** The stream
/// controller lives for the app's lifetime. Closing it
/// permanently breaks all listeners with no recovery.
@visibleForTesting
static Future<void> disposeForTest() async {
await _stageController.close();
}
// ── Internals ──────────────────────────────────────
/// Maps tap count → stage. Single source of truth.

/// Sanitizes a feature identifier (A1-X2, A2-5).
///
/// Trims whitespace, caps at 60 chars, rejects empty strings.
/// Returns null if input is null or empty after trimming.
static String? _sanitizeFeature(String? raw) {
if (raw == null) return null;
final trimmed = raw.trim();
if (trimmed.isEmpty) return null;
if (trimmed.length > _kMaxFeatureLength) {
return trimmed.substring(0, _kMaxFeatureLength);
}
return trimmed;
}
/// Safely emits a stage change on the stream (A1-S3).
static void _emitStageChange(GateStage stage) {
if (_stageController.isClosed) return;
try {
_stageController.add(stage);
} catch (e) {
if (kDebugMode) {
debugPrint('GateStateMachine: stream emit failed ($e)');
}
}
}
/// Emits a funnel event to the [onEvent] callback.

}
