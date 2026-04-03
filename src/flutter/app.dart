/// F5.1 — GoRouter Config + App Widget
///
/// Production router replacing F0.6 scaffold. Defines the route tree,
/// tab shell configuration, and the root MaterialApp.
///
/// ROUTE ARCHITECTURE:
/// - Full-screen: Splash, Onboarding (4), Auth, Paywall, Features,
///   Methodology, Notification Preferences
/// - Tab shell: Today / Figures / Explore / Bills / Settings
/// - Drill-down: Statement, Figure, Receipt, Radar, Lens Lab,
///   Vote Record, Trends, Crossfire, Mutation Timeline, Spending Detail
///   (all push above tab bar via root navigator)
/// - Deep link: /s/:id -> redirects to /statement/:id (150.24)
/// - Deep link: /figure/:id/dossier -> redirects to /figure/:id?mode=dossier
///   (dossier is in-page mode, query param preserves intent)
///
/// REDIRECT STUBS (wired by later artifacts):
/// - F5.4: Onboarding completion check
/// - F5.5: Auth gate for personal-action routes
/// - Feature-level gating is F6.4 (widget-level, NOT route-level)
///
/// TRANSITION NOTE:
/// F5.3 defines BaselineTransitions (route_transitions.dart).
/// builder: -> pageBuilder: swap deferred to Phase 2 sweep when
/// F5.3 completes marathon audit.
///
/// Path: lib/app.dart
library;

// 1. Flutter
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

// 2. Third-party packages
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

// 3. Project — config
import 'package:baseline_app/config/constants.dart';
import 'package:baseline_app/config/routes.dart';
import 'package:baseline_app/config/route_transitions.dart';

// 3b. Project — guards
import 'package:baseline_app/providers/auth_provider.dart';
import 'package:baseline_app/providers/onboarding_provider.dart';
import 'package:baseline_app/config/theme.dart';

// 4. Project — screens
import 'package:baseline_app/screens/auth_screen.dart';
import 'package:baseline_app/screens/crossfire_screen.dart';
import 'package:baseline_app/screens/features_guide_screen.dart';
import 'package:baseline_app/screens/figure_profile.dart';
import 'package:baseline_app/screens/figures_tab.dart';
import 'package:baseline_app/screens/framing_radar.dart';
import 'package:baseline_app/screens/lens_lab.dart';
import 'package:baseline_app/screens/methodology_screen.dart';
import 'package:baseline_app/screens/mutation_timeline_screen.dart';
import 'package:baseline_app/screens/narrative_sync_screen.dart';
import 'package:baseline_app/screens/notification_preferences_screen.dart';
import 'package:baseline_app/screens/onboarding_brand.dart';
import 'package:baseline_app/screens/onboarding_extraction.dart';
import 'package:baseline_app/screens/onboarding_features.dart';
import 'package:baseline_app/screens/onboarding_pipeline.dart';
import 'package:baseline_app/screens/paywall_screen.dart';
import 'package:baseline_app/screens/receipt_screen.dart';
import 'package:baseline_app/screens/bills_tab.dart';
import 'package:baseline_app/screens/explore_screen.dart';
import 'package:baseline_app/screens/settings_screen.dart';
import 'package:baseline_app/screens/spending_detail_screen.dart';
import 'package:baseline_app/screens/splash_screen.dart';
import 'package:baseline_app/screens/statement_detail.dart';
import 'package:baseline_app/screens/threshold_settings_screen.dart';
import 'package:baseline_app/screens/today_feed.dart';
import 'package:baseline_app/screens/trends_screen.dart';
import 'package:baseline_app/screens/vote_record.dart';

// 5. Project — widgets
import 'package:baseline_app/widgets/tab_shell.dart';

// ═══════════════════════════════════════════
// NAVIGATION KEYS
// ═══════════════════════════════════════════

/// Root navigator — owns full-screen routes and drill-downs above tabs.
final _rootNavigatorKey = GlobalKey<NavigatorState>();

/// Per-tab navigator keys — preserve tab state independently.
final _todayNavigatorKey =
    GlobalKey<NavigatorState>(debugLabel: 'today');
final _figuresNavigatorKey =
    GlobalKey<NavigatorState>(debugLabel: 'figures');
final _exploreNavigatorKey =
    GlobalKey<NavigatorState>(debugLabel: 'explore');
final _billsNavigatorKey =
    GlobalKey<NavigatorState>(debugLabel: 'bills');
final _settingsNavigatorKey =
    GlobalKey<NavigatorState>(debugLabel: 'settings');

// ═══════════════════════════════════════════
// ROUTER
// ═══════════════════════════════════════════

final router = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: AppRoutes.splash,
  debugLogDiagnostics: kDebugMode,

  // ── Redirect guard ─────────────────────────────────────
  redirect: (context, state) {
    final location = state.uri.path;

    // F5.4: Onboarding completion check.
    // If onboarding isn't complete, redirect to resume point —
    // unless already on an onboarding or splash route.
    if (!OnboardingGuard.isComplete) {
      final isOnboardingRoute = location.startsWith('/onboarding');
      final isSplash = location == AppRoutes.splash;
      final isAuth = location == AppRoutes.auth;
      if (!isOnboardingRoute && !isSplash && !isAuth) {
        return OnboardingGuard.resumeRoute;
      }
    }

    // F5.5: Auth gate for personal-action routes.
    // If user isn't authenticated and tries to access a protected
    // route, redirect to auth screen.
    if (!AuthGuard.isAuthenticated && isAuthRequired(location)) {
      return AppRoutes.auth;
    }

    // NOTE: Tier gating (Pro/Pro+/B2B) is widget-level via F6.4
    // FeatureGate. Route-level tier checks would break guest browsing.

    return null;
  },

  // ── Error page ─────────────────────────────────────────
  errorBuilder: (context, state) => Scaffold(
    backgroundColor: BaselineColors.background,
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Page not found.',
            style: BaselineTypography.body.copyWith(
              color: BaselineColors.textSecondary,
            ),
          ),
          const SizedBox(height: BaselineSpacing.md),
          TextButton(
            onPressed: () => context.go(AppRoutes.today),
            child: Text(
              'Go to Today',
              style: BaselineTypography.body2.copyWith(
                color: BaselineColors.teal,
              ),
            ),
          ),
        ],
      ),
    ),
  ),

  // ── Route tree ─────────────────────────────────────────
  routes: [
    // ┌─────────────────────────────────────┐
    // │ FULL-SCREEN ROUTES (no tab bar)     │
    // └─────────────────────────────────────┘

    GoRoute(
      path: AppRoutes.splash,
      parentNavigatorKey: _rootNavigatorKey,
      pageBuilder: (context, state) => BaselineTransitions.none(
        key: state.pageKey,
        child: const SplashScreen(),
      ),
    ),
    GoRoute(
      path: AppRoutes.onboardingBrand,
      parentNavigatorKey: _rootNavigatorKey,
      pageBuilder: (context, state) => BaselineTransitions.horizontalSwipe(
        context: context,
        key: state.pageKey,
        child: const OnboardingBrand(),
      ),
    ),
    GoRoute(
      path: AppRoutes.onboardingPipeline,
      parentNavigatorKey: _rootNavigatorKey,
      pageBuilder: (context, state) => BaselineTransitions.horizontalSwipe(
        context: context,
        key: state.pageKey,
        child: const OnboardingPipeline(),
      ),
    ),
    GoRoute(
      path: AppRoutes.onboardingExtraction,
      parentNavigatorKey: _rootNavigatorKey,
      pageBuilder: (context, state) => BaselineTransitions.horizontalSwipe(
        context: context,
        key: state.pageKey,
        child: const OnboardingExtraction(),
      ),
    ),
    GoRoute(
      path: AppRoutes.onboardingFeatures,
      parentNavigatorKey: _rootNavigatorKey,
      pageBuilder: (context, state) => BaselineTransitions.horizontalSwipe(
        context: context,
        key: state.pageKey,
        child: const OnboardingFeatures(),
      ),
    ),
    GoRoute(
      path: AppRoutes.auth,
      parentNavigatorKey: _rootNavigatorKey,
      pageBuilder: (context, state) => BaselineTransitions.fadeScale(
        context: context,
        key: state.pageKey,
        child: const AuthScreen(),
      ),
    ),
    GoRoute(
      path: AppRoutes.paywall,
      parentNavigatorKey: _rootNavigatorKey,
      pageBuilder: (context, state) => BaselineTransitions.fadeScale(
        context: context,
        key: state.pageKey,
        child: const PaywallScreen(),
      ),
    ),
    GoRoute(
      path: AppRoutes.features,
      parentNavigatorKey: _rootNavigatorKey,
      pageBuilder: (context, state) => BaselineTransitions.drillDown(
        context: context,
        key: state.pageKey,
        child: const FeaturesGuideScreen(),
      ),
    ),
    GoRoute(
      path: AppRoutes.methodology,
      parentNavigatorKey: _rootNavigatorKey,
      pageBuilder: (context, state) => BaselineTransitions.drillDown(
        context: context,
        key: state.pageKey,
        child: const MethodologyScreen(),
      ),
    ),
    GoRoute(
      path: AppRoutes.notificationPreferences,
      parentNavigatorKey: _rootNavigatorKey,
      pageBuilder: (context, state) => BaselineTransitions.drillDown(
        context: context,
        key: state.pageKey,
        child: const NotificationPreferencesScreen(),
      ),
    ),

    // ┌─────────────────────────────────────┐
    // │ DEEP LINKS — Redirects              │
    // └─────────────────────────────────────┘

    // 150.24: /s/:id -> /statement/:id
    GoRoute(
      path: AppRoutes.statementPermalink,
      parentNavigatorKey: _rootNavigatorKey,
      redirect: (context, state) {
        final id = state.pathParameters['id'];
        if (id == null || id.isEmpty) return AppRoutes.today;
        return AppRoutes.statementPath(id);
      },
    ),

    // FG-8a: /figure/:id/dossier -> /figure/:id?mode=dossier
    // The figure profile screen reads the query parameter to auto-expand
    // dossier mode when navigated via this deep link.
    GoRoute(
      path: AppRoutes.dossier,
      parentNavigatorKey: _rootNavigatorKey,
      redirect: (context, state) {
        final id = state.pathParameters['id'];
        if (id == null || id.isEmpty) return AppRoutes.figures;
        return '${AppRoutes.figureProfilePath(id)}?mode=dossier';
      },
    ),

    // Legacy /search → /explore redirect
    GoRoute(
      path: AppRoutes.search,
      parentNavigatorKey: _rootNavigatorKey,
      redirect: (context, state) => AppRoutes.explore,
    ),

    // ┌─────────────────────────────────────┐
    // │ TAB SHELL (5 tabs)                  │
    // └─────────────────────────────────────┘

    StatefulShellRoute.indexedStack(
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state, navigationShell) =>
          TabShell(navigationShell: navigationShell),
      branches: [
        // Tab 0: Today
        StatefulShellBranch(
          navigatorKey: _todayNavigatorKey,
          routes: [
            GoRoute(
              path: AppRoutes.today,
              builder: (context, state) => const TodayFeed(),
            ),
          ],
        ),

        // Tab 1: Figures
        StatefulShellBranch(
          navigatorKey: _figuresNavigatorKey,
          routes: [
            GoRoute(
              path: AppRoutes.figures,
              builder: (context, state) => const FiguresTab(),
            ),
          ],
        ),

        // Tab 2: Explore
        StatefulShellBranch(
          navigatorKey: _exploreNavigatorKey,
          routes: [
            GoRoute(
              path: AppRoutes.explore,
              builder: (context, state) => const ExploreScreen(),
            ),
          ],
        ),

        // Tab 3: Bills
        StatefulShellBranch(
          navigatorKey: _billsNavigatorKey,
          routes: [
            GoRoute(
              path: AppRoutes.bills,
              builder: (context, state) => const BillsTab(),
            ),
          ],
        ),

        // Tab 4: Settings
        StatefulShellBranch(
          navigatorKey: _settingsNavigatorKey,
          routes: [
            GoRoute(
              path: AppRoutes.settings,
              builder: (context, state) => const SettingsScreen(),
            ),
          ],
        ),
      ],
    ),

    // ┌─────────────────────────────────────┐
    // │ DRILL-DOWN ROUTES (above tab bar)   │
    // └─────────────────────────────────────┘

    // Statement Detail
    GoRoute(
      path: AppRoutes.statement,
      parentNavigatorKey: _rootNavigatorKey,
      pageBuilder: (context, state) {
        final id = state.pathParameters['id'] ?? '';
        return BaselineTransitions.drillDown(
          context: context,
          key: state.pageKey,
          child: StatementDetailScreen(statementId: id),
        );
      },
    ),

    // Figure Profile
    GoRoute(
      path: AppRoutes.figureProfile,
      parentNavigatorKey: _rootNavigatorKey,
      pageBuilder: (context, state) {
        final id = state.pathParameters['id'] ?? '';
        final isDossier =
            state.uri.queryParameters['mode'] == 'dossier';
        return BaselineTransitions.drillDown(
          context: context,
          key: state.pageKey,
          child: FigureProfileScreen(
            figureId: id,
            isDossierMode: isDossier,
          ),
        );
      },
    ),

    // The Receipt — circuit trace (analysis screen)
    GoRoute(
      path: AppRoutes.receipt,
      parentNavigatorKey: _rootNavigatorKey,
      pageBuilder: (context, state) {
        final id = state.pathParameters['id'] ?? '';
        return BaselineTransitions.circuitTrace(
          context: context,
          key: state.pageKey,
          child: ReceiptScreen(statementId: id),
        );
      },
    ),

    // Framing Radar — circuit trace (analysis screen)
    GoRoute(
      path: AppRoutes.framingRadar,
      parentNavigatorKey: _rootNavigatorKey,
      pageBuilder: (context, state) {
        final id = state.pathParameters['id'] ?? '';
        return BaselineTransitions.circuitTrace(
          context: context,
          key: state.pageKey,
          child: FramingRadarScreen(figureId: id),
        );
      },
    ),

    // The Lens Lab — circuit trace (analysis screen)
    GoRoute(
      path: AppRoutes.lensLab,
      parentNavigatorKey: _rootNavigatorKey,
      pageBuilder: (context, state) {
        final id = state.pathParameters['id'] ?? '';
        return BaselineTransitions.circuitTrace(
          context: context,
          key: state.pageKey,
          child: LensLabScreen(statementId: id),
        );
      },
    ),

    // Vote Record
    GoRoute(
      path: AppRoutes.voteRecord,
      parentNavigatorKey: _rootNavigatorKey,
      pageBuilder: (context, state) {
        final id = state.pathParameters['id'] ?? '';
        return BaselineTransitions.drillDown(
          context: context,
          key: state.pageKey,
          child: VoteRecordScreen(figureId: id),
        );
      },
    ),

    // Historical Trends
    GoRoute(
      path: AppRoutes.trends,
      parentNavigatorKey: _rootNavigatorKey,
      pageBuilder: (context, state) {
        final id = state.pathParameters['id'] ?? '';
        return BaselineTransitions.drillDown(
          context: context,
          key: state.pageKey,
          child: TrendsScreen(figureId: id),
        );
      },
    ),

    // Narrative Sync (B2B)
    GoRoute(
      path: AppRoutes.narrativeSync,
      parentNavigatorKey: _rootNavigatorKey,
      pageBuilder: (context, state) => BaselineTransitions.drillDown(
        context: context,
        key: state.pageKey,
        child: const NarrativeSyncScreen(),
      ),
    ),

    // Crossfire (no pair — shows latest pairs)
    GoRoute(
      path: AppRoutes.crossfire,
      parentNavigatorKey: _rootNavigatorKey,
      pageBuilder: (context, state) => BaselineTransitions.drillDown(
        context: context,
        key: state.pageKey,
        child: const CrossfireScreen(),
      ),
    ),

    // Crossfire (specific pair)
    GoRoute(
      path: AppRoutes.crossfirePair,
      parentNavigatorKey: _rootNavigatorKey,
      pageBuilder: (context, state) => BaselineTransitions.drillDown(
        context: context,
        key: state.pageKey,
        child: CrossfireScreen(
          pairId: state.pathParameters['pairId'],
        ),
      ),
    ),

    // Mutation Timeline (Pro+)
    GoRoute(
      path: AppRoutes.mutationTimeline,
      parentNavigatorKey: _rootNavigatorKey,
      pageBuilder: (context, state) {
        final billId = state.pathParameters['billId'] ?? '';
        return BaselineTransitions.drillDown(
          context: context,
          key: state.pageKey,
          child: MutationTimelineScreen(billId: billId),
        );
      },
    ),

    // Spending Scope (Pro+)
    GoRoute(
      path: AppRoutes.spendingDetail,
      parentNavigatorKey: _rootNavigatorKey,
      pageBuilder: (context, state) {
        final billId = state.pathParameters['billId'] ?? '';
        return BaselineTransitions.drillDown(
          context: context,
          key: state.pageKey,
          child: SpendingDetailScreen(billId: billId),
        );
      },
    ),

    // Threshold Settings (N-3)
    GoRoute(
      path: AppRoutes.thresholdSettings,
      parentNavigatorKey: _rootNavigatorKey,
      pageBuilder: (context, state) => BaselineTransitions.drillDown(
        context: context,
        key: state.pageKey,
        child: const ThresholdSettingsScreen(),
      ),
    ),
  ],
);

// ═══════════════════════════════════════════
// APP WIDGET
// ═══════════════════════════════════════════

/// Root app widget.
///
/// Wraps MaterialApp.router with ProviderScope (Riverpod) and
/// applies the global dark theme. This is the entry point
/// referenced by main.dart (F0.5).
class BaselineApp extends StatelessWidget {
  const BaselineApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      child: MaterialApp.router(
        title: kAppName,
        debugShowCheckedModeBanner: false,
        theme: BaselineTheme.dark,
        routerConfig: router,
      ),
    );
  }
}
