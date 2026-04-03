/// F5.1 — Route Paths
///
/// Single source of truth for all route paths in the app.
/// Lives in config/ to avoid circular imports — app.dart imports this,
/// and screens import this. Neither imports the other.
///
/// Path: lib/config/routes.dart
library;

/// All route path constants and helper methods.
///
/// Screens use [AppRoutes.xyz] for navigation. Never hardcode
/// path strings — always reference this class.
class AppRoutes {
  AppRoutes._();

  // ── Full-screen routes (no tab bar) ──────────────────────

  /// Splash screen — app entry point.
  static const splash = '/splash';

  /// Onboarding carousel — 4 screens, shown once per install.
  static const onboardingBrand = '/onboarding/brand';
  static const onboardingPipeline = '/onboarding/pipeline';
  static const onboardingExtraction = '/onboarding/extraction';
  static const onboardingFeatures = '/onboarding/features';

  /// Authentication — triggered on first personal action, not at launch.
  static const auth = '/auth';

  /// Paywall — subscription upgrade screen.
  static const paywall = '/paywall';

  /// Features Guide — in-app TM museum (I-24).
  static const features = '/features';

  /// Methodology — "How BASELINE Works" explainer (I-25).
  static const methodology = '/methodology';

  /// Notification Preferences — COMMS Array (F4.18).
  static const notificationPreferences = '/notifications';

  // ── Tab routes ───────────────────────────────────────────

  static const today = '/today';
  static const figures = '/figures';
  static const search = '/search';
  static const explore = '/explore';
  static const bills = '/bills';
  static const settings = '/settings';

  // ── Drill-down routes (parameterized) ────────────────────

  /// Statement detail — `/statement/:id`
  static const statement = '/statement/:id';

  /// Figure profile — `/figure/:id`
  static const figureProfile = '/figure/:id';

  /// The Receipt — `/statement/:id/receipt`
  static const receipt = '/statement/:id/receipt';

  /// Framing Radar — `/figure/:id/radar`
  static const framingRadar = '/figure/:id/radar';

  /// The Lens Lab — `/statement/:id/lens-lab`
  static const lensLab = '/statement/:id/lens-lab';

  /// Vote Record — `/figure/:id/votes`
  static const voteRecord = '/figure/:id/votes';

  /// Historical Trends — `/figure/:id/trends`
  static const trends = '/figure/:id/trends';

  /// Declassified Dossier — `/figure/:id/dossier`
  /// Redirects to figure profile with `?mode=dossier` query param.
  static const dossier = '/figure/:id/dossier';

  /// Narrative Sync — `/narrative-sync` (B2B)
  static const narrativeSync = '/narrative-sync';

  /// Crossfire — `/crossfire`
  static const crossfire = '/crossfire';

  /// Crossfire pair — `/crossfire/:pairId`
  static const crossfirePair = '/crossfire/:pairId';

  /// Mutation Timeline — `/mutation-timeline/:billId`
  static const mutationTimeline = '/mutation-timeline/:billId';

  /// Spending Scope — `/spending-detail/:billId`
  static const spendingDetail = '/spending-detail/:billId';

  // ── Deep link (150.24) ───────────────────────────────────

  /// Short permalink for statement sharing: `/s/:id`
  /// Redirects to `/statement/:id` at router level.
  static const statementPermalink = '/s/:id';

  // ── Path helpers ─────────────────────────────────────────
  // Use these in screens instead of manual string interpolation.
  // Prevents typos and keeps route construction in one place.

  /// `/statement/{id}`
  static String statementPath(String id) => '/statement/$id';

  /// `/figure/{id}`
  static String figureProfilePath(String id) => '/figure/$id';

  /// `/statement/{id}/receipt`
  static String receiptPath(String statementId) =>
      '/statement/$statementId/receipt';

  /// `/figure/{id}/radar`
  static String framingRadarPath(String figureId) =>
      '/figure/$figureId/radar';

  /// `/statement/{id}/lens-lab`
  static String lensLabPath(String statementId) =>
      '/statement/$statementId/lens-lab';

  /// `/figure/{id}/votes`
  static String voteRecordPath(String figureId) =>
      '/figure/$figureId/votes';

  /// `/figure/{id}/trends`
  static String trendsPath(String figureId) =>
      '/figure/$figureId/trends';

  /// `/figure/{id}/dossier` — deep link to dossier mode on figure profile
  static String dossierPath(String figureId) =>
      '/figure/$figureId/dossier';

  /// `/crossfire/{pairId}`
  static String crossfirePath(String pairId) =>
      '/crossfire/$pairId';

  /// `/mutation-timeline/{billId}`
  static String mutationTimelinePath(String billId) =>
      '/mutation-timeline/$billId';

  /// `/spending-detail/{billId}`
  static String spendingDetailPath(String billId) =>
      '/spending-detail/$billId';

  /// `/s/{id}` — shareable permalink (150.24)
  static String permalinkPath(String statementId) =>
      '/s/$statementId';

  static String statementDetailPath(String id) => '/statement/$id';
  static String figureDossierPath(String id) => '/figure/$id/dossier';
  static const thresholdSettings = '/settings/thresholds';
}
