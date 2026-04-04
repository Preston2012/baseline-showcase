/// P7-patched - Baseline app entry point.
///
/// Initializes all platform services before running the app.
/// Order: Widgets → Supabase → RevenueCat → AdMob → Firebase (FCM)
/// → NotificationService → OnboardingGuard → AuthGuard
/// → GateStateMachine → runApp.
///
/// Path: lib/main.dart
library;
// Dart SDK
import 'dart:async';
// Flutter
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
// Third-party
import 'package:firebase_core/firebase_core.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
// Config
import 'package:baseline_app/config/env.dart';
import 'package:baseline_app/config/firebase_options.dart';
// Services
import 'package:baseline_app/services/supabase_client.dart';
// Providers (guards)
import 'package:baseline_app/providers/onboarding_provider.dart';
import 'package:baseline_app/providers/auth_provider.dart';
// Utils
import 'package:baseline_app/utils/gate_state_machine.dart';
import 'package:baseline_app/services/notification_service.dart';
// App
import 'package:baseline_app/app.dart';
Future<void> main() async {
// Required before any plugin calls.
WidgetsFlutterBinding.ensureInitialized();
// Lock to portrait (premium feel, consistent layout).
await SystemChrome.setPreferredOrientations([
DeviceOrientation.portraitUp,
]);
// Status bar: transparent with light icons (dark background).
SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
statusBarColor: Colors.transparent,
statusBarIconBrightness: Brightness.light,
statusBarBrightness: Brightness.dark,
));
// --- Initialize services (sequential - order matters) ---
// 1. Supabase (backend + auth - everything depends on this)
await initSupabase();
// 2. RevenueCat (subscriptions - Env.revenueCatKey auto-selects iOS/Android)
// Non-fatal: app runs without subscriptions if RevenueCat fails.
try {
await Purchases.configure(
PurchasesConfiguration(Env.revenueCatKey),
);
} catch (e) {
if (kDebugMode) {
debugPrint('RevenueCat init failed (subscriptions disabled): $e');
}
}
// 3. AdMob (Core tier only - initializing here is fine, ads render later)
// Non-fatal: app runs without ads if AdMob fails.
try {
await MobileAds.instance.initialize();
} catch (e) {
if (kDebugMode) {
debugPrint('AdMob init failed (ads disabled): $e');
}
}
// 4. Firebase (FCM push notifications only - 150.6)
// Non-fatal: if Firebase fails, app runs without push notifications.
// P8 notification_service checks Firebase availability before use.
try {
await Firebase.initializeApp(
options: DefaultFirebaseOptions.currentPlatform,
);
} catch (e) {
if (kDebugMode) {
debugPrint('Firebase init failed (push notifications disabled): $e');
}
}
// 5. NotificationService (FCM handlers - must come after Firebase init)
// Non-fatal: gracefully handles missing Firebase.
await NotificationService.init();
// 6. OnboardingGuard (SharedPreferences - must complete before routing)
await OnboardingGuard.init();
// 7. AuthGuard (sync read of current session)
AuthGuard.init();
// 8. GateStateMachine (SharedPreferences - paywall funnel state)
// Non-fatal: if init fails, defaults to glimpse stage.
await GateStateMachine.init();
// --- Launch app (ProviderScope is inside BaselineApp) ---
runApp(const BaselineApp());
}
