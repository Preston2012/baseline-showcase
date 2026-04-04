/// F1.10 - App-wide constants for Baseline.
///
/// Single source of truth for: disclaimer text, methodology URL,
/// tier configuration, brand strings, feature flags, ad placement,
/// export assets, bill analysis copy, and info sheet copy (tap-to-explain).
///
/// No constant may be duplicated or hardcoded elsewhere.
/// If you need a string/value that appears on multiple screens, add it here.
///
/// Path: lib/config/constants.dart
library;

// ═══════════════════════════════════════════
// BRAND
// ═══════════════════════════════════════════

const String kAppName = 'Baseline';

/// Static tagline fallback. Used for exports, share text, meta tags,
/// and anywhere the morph animation cannot run.
const String kTagline = 'Language You Can Measure.';

/// Morph words for the hero tagline cycler (F4.1 splash, F4.2 brand).
/// Teal-colored cycling word + white static " You Can Measure."
/// Order matters: cycle proceeds top to bottom, loops.
const List<String> kTaglineWords = [
  'Speech',
  'Patterns',
  'Signals',
  'Language',
];

/// App URL for watermark and share text.
const String kBaselineUrl = 'baselineapp.co';

/// Path to the BASELINE wordmark asset (white, transparent BG).
/// Used by P6 export watermark (Canvas-drawn).
const String kWordmarkAsset = 'assets/images/baseline_wordmark.png';

/// Pre-filled share text for 150.14 "Share app link" in Settings.
const String kShareAppText =
    'Check out BASELINE: Language You Can Measure.';

/// App Store / Play Store URLs.
const String kAppStoreUrl = 'https://apps.apple.com/app/baseline/[STORE_ID_REDACTED]';
const String kPlayStoreUrl =
    'https://play.google.com/store/apps/details?id=co.baselineapp';

// ═══════════════════════════════════════════
// SUPPORT
// ═══════════════════════════════════════════

const String kSupportEmail = 'support@baseline.marketing';
const String kSupportEmailSubject = 'Baseline App: Support Request';
const String kSupportPhone = '541-551-0731';
const String kWebsiteUrl = 'https://baseline.marketing';

// ═══════════════════════════════════════════
// LEGAL -- DISCLAIMER (locked text, do not modify)
// ═══════════════════════════════════════════

/// Appears on: Receipt™, Statement Detail ONLY (subtle).
/// All other screens: "How [X] works →" link to methodology.
/// Rendered by disclaimer_footer.dart widget.
const String kDisclaimerText = 'Observational analysis only. Not a fact-check.';
const String kDisclaimerLearnMore = 'Learn more';

/// Bill-specific disclaimer for F4.12 Vote Record / Bill Overview.
const String kBillDisclaimerText =
    'Automated categorization only. Not an evaluation. '
    'Review original bill text for full context.';

// ═══════════════════════════════════════════
// LEGAL -- URLS
// These MUST resolve or "Learn more" / Settings links will 404.
// ═══════════════════════════════════════════

const String kMethodologyUrl = 'https://baseline.marketing/methodology';
const String kPrivacyUrl = 'https://baseline.marketing/privacy';
const String kTermsUrl = 'https://baseline.marketing/terms';
const String kSupportUrl = 'https://baseline.marketing/support';

// ═══════════════════════════════════════════
// "MISCAT? REPORT" (F4.12 - bill provision reporting)
// ═══════════════════════════════════════════

const String kMiscatReportEmail = 'support@baseline.app';
const String kMiscatReportSubject = 'Baseline: Provision Categorization Report';

// ═══════════════════════════════════════════
// AI MODEL LABELS (brand-neutral)
// ═══════════════════════════════════════════

/// Short labels used in Lens Toggle, metric bars, and Lens Lab.
/// NEVER say "OpenAI thinks..." - say "GP analysis:" or just show "GP".
const String kLabelGP = 'GP';
const String kLabelCL = 'CL';
const String kLabelGR = 'GR';
const String kLabelAll = 'ALL';

/// Full labels for tooltips / accessibility only.
const String kLabelGPFull = 'GP analysis';
const String kLabelCLFull = 'CL analysis';
const String kLabelGRFull = 'GR analysis';

// ═══════════════════════════════════════════
// TIERS
// ═══════════════════════════════════════════

/// Display names for tier badges and paywall.
/// Raw backend values: 'free', 'pro', 'pro_plus', 'b2b'
const Map<String, String> kTierDisplayNames = {
  'free': 'Core',
  'pro': 'Pro',
  'pro_plus': 'Pro+',
  'b2b': 'B2B',
};

// ═══════════════════════════════════════════
// PRICING -- shown on paywall screen (F4.16)
// Patched per Expansion Plan §7 pricing update.
// ═══════════════════════════════════════════

const String kProMonthly = '\$7.99/mo';
const String kProIntroMonthly = '\$5.99/mo';
const String kProYearly = '\$59.99/yr';
const String kProPlusMonthly = '\$24.99/mo';
const String kProPlusYearly = '\$199.99/yr';
const String kB2BMonthly = '\$499.99/mo';
const String kB2BYearly = '\$3,999.99/yr';
const String kTrialDuration = '7-day free trial';
const String kLaunchWindow = '60 days';

/// Pro+ collapsed card tagline (F4.16 paywall).
const String kProPlusTagline = 'More signal. Less noise.';

// ═══════════════════════════════════════════
// TOPICS (UPPERCASE -- must match A1 + A9B)
// ═══════════════════════════════════════════

const List<String> kTopics = [
  'ECONOMY',
  'IMMIGRATION',
  'AI_TECHNOLOGY',
  'FOREIGN_POLICY',
  'HEALTHCARE',
  'CLIMATE_ENVIRONMENT',
  'CRIME_JUSTICE',
  'ELECTIONS',
  'MILITARY_DEFENSE',
  'CULTURE_SOCIETY',
  'OTHER',
];

/// Display-friendly topic names for UI chips.
const Map<String, String> kTopicDisplayNames = {
  'ECONOMY': 'Economy',
  'IMMIGRATION': 'Immigration',
  'AI_TECHNOLOGY': 'AI & Technology',
  'FOREIGN_POLICY': 'Foreign Policy',
  'HEALTHCARE': 'Healthcare',
  'CLIMATE_ENVIRONMENT': 'Climate & Environment',
  'CRIME_JUSTICE': 'Crime & Justice',
  'ELECTIONS': 'Elections',
  'MILITARY_DEFENSE': 'Military & Defense',
  'CULTURE_SOCIETY': 'Culture & Society',
  'OTHER': 'Other',
};

// ═══════════════════════════════════════════
// FRAMING LABELS (must match A1 + A3 + A14A)
// ═══════════════════════════════════════════

/// 5 axes only. NEVER 6. Pentagon, not hexagon.
const List<String> kFramingLabels = [
  'Adversarial / Oppositional',
  'Problem Identification',
  'Commitment / Forward-Looking',
  'Justification / Reactive',
  'Imperative / Directive',
];

// ═══════════════════════════════════════════
// PROVISION DRIFT™ -- THRESHOLD LABELS
// ═══════════════════════════════════════════
//
// Client-side quartile thresholds for drift score display.
// Matches P4 BillProvision.driftLabel getter exactly.
// Used by F4.12 vote record + A-10 drift waterfall + A-11 league table.

/// Drift threshold boundaries (upper inclusive).
const Map<String, double> kDriftThresholds = {
  'low': 0.25,
  'moderate': 0.50,
  'high': 0.75,
  'very_high': 1.00,
};

/// Display labels for drift score ranges.
const Map<String, String> kDriftThresholdLabels = {
  'low': 'Low',
  'moderate': 'Moderate',
  'high': 'High',
  'very_high': 'Very High',
};

// ═══════════════════════════════════════════
// FEED / PAGINATION
// ═══════════════════════════════════════════

/// Maximum followed figures for Core (free) tier.
/// Unlimited for Pro and above (enforced by TierLimits.followedFiguresCap).
const int kMaxFollowedFiguresFree = 10;

const int kFeedPageSize = 50;
const int kFeedMaxPageSize = 200;
const int kReceiptPreviewLimit = 3;

// ═══════════════════════════════════════════
// EMPTY STATE MESSAGES (neutral, observational)
// ═══════════════════════════════════════════

const String kEmptyFeed = 'No statements available.';
const String kEmptyTrends = 'Trends not available.';
const String kEmptyReceipt = 'No matching statements found.';
const String kEmptyVotes = 'No vote records available.';
const String kEmptySearch = 'No results found.';
const String kEmptyAnalysis = 'Analysis not available.';
const String kEmptyFigureStatements = 'No statements recorded for this figure.';
const String kEmptyBillOverview = 'Bill overview not available.';
const String kEmptyFollowed = 'No followed figures.';
const String kEmptyFigures = 'No figures available.';
const String kEmptyCrossfire = 'No comparison data available.';

// ═══════════════════════════════════════════
// DATA READINESS STATES (collecting / calibrating)
// ═══════════════════════════════════════════

const String kCalibratingBaseline =
    'Calibrating baseline. Measurements in progress.';
const String kCollectingStatements =
    'Collecting statements. Signal acquisition active.';
const String kInsufficientData =
    'Insufficient data for full analysis.';
const String kAwaitingAnalysis =
    'Analysis models processing. Collection active.';
const String kMinStatementsRequired =
    'Minimum statement threshold not reached.';
const String kBaselineNotReady =
    'Baseline score requires additional measurements.';
const String kRadarNotReady =
    'Framing data insufficient for radar display.';
const String kTrendsNotReady =
    'Trend data requires additional data points.';
const String kReceiptNotReady =
    'Receipt requires more statements on record.';
const String kLensLabNotReady =
    'Lens Lab requires multi-model analysis data.';

// ═══════════════════════════════════════════
// PARTIAL FAILURE
// ═══════════════════════════════════════════

const String kPartialFailureMessage = 'Some data not available.';

// ═══════════════════════════════════════════
// REVOKED STATEMENT
// ═══════════════════════════════════════════

const String kRevokedAnalysisSealed = 'Analysis sealed. Source retracted.';
const String kRevokedStampLabel = 'SOURCE RETRACTED';

// ═══════════════════════════════════════════
// "WHY AM I SEEING THIS?" (150.25)
// ═══════════════════════════════════════════

/// Body text for the "Why this?" info sheet on feed items.
/// Explains signal rank / novelty / recency basis.
const String kWhyThisBody =
    'Statements are ranked by a combination of recency, signal '
    'strength, and novelty. Newer statements with higher measurement '
    'activity appear first. This ranking is observational. It '
    'reflects data volume, not editorial selection.';

// ═══════════════════════════════════════════
// AD PLACEMENT
// ═══════════════════════════════════════════

/// AdMob config lives in env.dart (Env.admobBannerId).
/// Do NOT duplicate ad unit IDs here.

// ═══════════════════════════════════════════
// FEATURE FLAGS (client-side defaults)
// ═══════════════════════════════════════════

/// Client-side defaults. Overridden by backend feature_flags table.
const bool kDefaultEnableWarRoom = true;
const bool kDefaultEnableAnnotations = true;
const bool kDefaultEnableVoteTracking = true;

// ═══════════════════════════════════════════
// RATE APP PROMPT
// ═══════════════════════════════════════════

const int kRateAppViewThreshold = 5;

// ═══════════════════════════════════════════
// ROUTES -- FIGURE PROFILE / DOSSIER / NARRATIVE SYNC
// ═══════════════════════════════════════════

/// Route path segments for Figure Profile and Dossier screens.
/// Consumed by F5.1 GoRouter + F4.15 navigation + FG-8 dossier links.
const String kFigureProfilePath = '/figure';
const String kDossierPath = '/dossier';
const String kNarrativeSyncPath = '/narrative-sync';

// ═══════════════════════════════════════════
// CHANGELOG -- "WHAT'S NEW" (150.22)
// ═══════════════════════════════════════════
//
// Keyed by version string. Shown in Settings via modal bottom sheet.
// Version-gated via package_info_plus. Only shows on version change.
// Most recent version FIRST.

const Map<String, List<String>> kChangelog = {
  '1.0.0': [
    'Launch. Language You Can Measure.',
    'Multiple independent AI models analyze every statement.',
    'The Receipt™: track what they said before.',
    'Framing Radar™: five-axis rhetorical mapping.',
    'Lens Lab™: compare how models scored it.',
    'Vote Record with Bill Overview & Provision Drift™.',
    'Crossfire™: side-by-side figure comparison.',
    'Declassified Dossier™: full intelligence profile.',
  ],
};

// ═══════════════════════════════════════════
// INFO SHEET COPY -- TAP-TO-EXPLAIN (CANONICAL)
// ═══════════════════════════════════════════
//
// Used by InfoBottomSheet (F2.18). Keyed by surface identifier.
// Every complex section/metric/header MUST have an entry here.
// Copy rules:
//   - Observational language only
//   - 2-3 sentences max
//   - Explains WHAT the metric measures, not what the score "means"
//   - No forbidden words (truth, lie, bias, fact-check)
//

/// Info sheet entries: { key: { 'title': ..., 'body': ... } }
const Map<String, Map<String, String>> kInfoSheetCopy = {
  // ── Brand Metric ───────────────────────────────────────────────
  'baseline': {
    'title': 'Baseline™',
    'body':
        'A figure-level aggregate that reflects overall measurement '
        'activity over the last 24 hours. Calculated from signal rank '
        'values across all recent statements. Updated on a rolling basis.',
  },

  // ── 12 ™ Feature Titles ────────────────────────────────────────
  'receipt': {
    'title': 'The Receipt™',
    'body':
        'The Receipt surfaces past statements by the same figure on the '
        'same topic, ranked by semantic similarity. It shows how language '
        'on a subject has shifted or stayed consistent over time.',
  },
  'framing_radar': {
    'title': 'Framing Radar™',
    'body':
        'The Framing Radar maps how a statement\'s language is structured '
        'across five framing categories. Each axis represents a rhetorical '
        'pattern identified independently by the AI models. '
        'Available to all tiers. Tap axis detail requires Pro.',
  },
  'lens_lab': {
    'title': 'Lens Lab™',
    'body':
        'The Lens Lab compares how multiple independent AI models scored '
        'the same statement across measurement axes. Each model processes '
        'the statement separately. None can see the others\' results.',
  },
  'provision_drift': {
    'title': 'Provision Drift™',
    'body':
        'Measures the thematic distance between a bill\'s provisions '
        'and its stated purpose. Each provision is scored by multiple AI '
        'models independently. Higher drift = greater distance. '
        'Read-only view available to all tiers.',
  },
  'signal_pulse': {
    'title': 'Signal Pulse™',
    'body':
        'Signal Pulse measures the volume and frequency of a figure\'s '
        'public statements. The pulsing ring on their avatar reflects '
        'how actively they\'re speaking. Faster pulse, higher output.',
  },
  'crossfire': {
    'title': 'Crossfire™',
    'body':
        'Crossfire pairs two figures who spoke on the same topic within '
        '72 hours and places their analyses side by side. Each model '
        'scores independently. The comparison surfaces on its own.',
  },
  'split_microscope': {
    'title': 'Split Microscope™',
    'body':
        'When the AI models disagree on a score, Split Microscope '
        'breaks down exactly where the variance occurs. Which axes '
        'diverged, by how much, and in which direction.',
  },
  'intersections': {
    'title': 'Intersections Panel™',
    'body':
        'Cross-links statements from different figures that share '
        'topics, framing patterns, or temporal proximity. Surfaces '
        'connections that aren\'t obvious from individual profiles.',
  },
  'framing_fingerprint': {
    'title': 'Framing Fingerprint™',
    'body':
        'Each public figure develops a unique rhetorical signature. '
        'The patterns in how they frame issues, the language structures '
        'they return to. Framing Fingerprint visualizes this identity.',
  },
  'constellation_nav': {
    'title': 'Constellation Nav™',
    'body':
        'Data-infused navigation dots where each point encodes signal '
        'density. Brighter dots indicate higher measurement activity, '
        'giving you density context as you browse.',
  },
  'dossier': {
    'title': 'Declassified Dossier™',
    'body':
        'A comprehensive intelligence profile consolidating all available '
        'measurement data for a single figure. Eight exhibit folders cover '
        'framing, activity, trends, votes, and shift detection.',
  },
  'narrative_sync': {
    'title': 'Narrative Sync™',
    'body':
        'Cross-organization pattern detection that identifies when '
        'multiple figures adopt similar language or framing within a '
        'defined time window. B2B feature.',
  },

  // ── Metric Headers ─────────────────────────────────────────────
  'repetition': {
    'title': 'Repetition',
    'body':
        'Repetition measures how closely this statement\'s language mirrors '
        'the figure\'s prior statements on the same topic. Higher values '
        'indicate greater linguistic similarity to past language.',
  },
  'novelty': {
    'title': 'Novelty',
    'body':
        'Novelty measures how much new language or framing this statement '
        'introduces compared to the figure\'s prior statements. Higher '
        'values indicate more departure from established patterns.',
  },
  'affect': {
    'title': 'Affect',
    'body':
        'Affect measures the rate of emotionally charged language in the '
        'statement. This includes intensity markers, urgency signals, and '
        'sentiment-loaded phrasing identified by each model independently.',
  },
  'entropy': {
    'title': 'Entropy',
    'body':
        'Entropy measures the topical spread of the statement. Higher '
        'values indicate the statement covers multiple subjects; lower '
        'values indicate tight focus on a single topic.',
  },
  'baseline_delta': {
    'title': 'Baseline Δ',
    'body':
        'The change in a figure\'s Baseline™ score over the selected time '
        'range. Positive values indicate increasing measurement activity; '
        'negative values indicate decreasing activity.',
  },
  'signal_rank': {
    'title': 'Signal Rank',
    'body':
        'A composite ranking that reflects how much measurement activity '
        'a statement generated. Combines recency, model agreement, and '
        'signal volume into a single sortable value.',
  },

  // ── Consensus & Signals ────────────────────────────────────────
  'lens_convergence': {
    'title': 'Lens Convergence',
    'body':
        'Lens Convergence shows how closely the AI models produced '
        'similar measurements for this statement. Higher convergence means '
        'the models independently reached comparable results.',
  },
  'variance_detected': {
    'title': 'Variance Detected',
    'body':
        'This banner appears when the AI models produced notably different '
        'measurements for this statement. This is observational. It flags '
        'divergence, not which model is more or less reliable.',
  },
  'signal_chips': {
    'title': 'Signal Overview',
    'body':
        'Signal chips summarize the key measurement values for this '
        'statement at a glance. Tap any metric section header for a '
        'detailed explanation of what that measurement captures.',
  },

  // ── Framing Axes ───────────────────────────────────────────────
  'framing_adversarial': {
    'title': 'Adversarial / Oppositional',
    'body':
        'Measures language that positions the speaker against a target. '
        'Criticism, blame, or opposition framing. This axis captures '
        'confrontational rhetorical structure.',
  },
  'framing_problem': {
    'title': 'Problem Identification',
    'body':
        'Measures language focused on defining or highlighting a problem, '
        'challenge, or threat. This axis captures diagnostic rhetorical '
        'structure without implying a solution.',
  },
  'framing_commitment': {
    'title': 'Commitment / Forward-Looking',
    'body':
        'Measures language oriented toward future action, promises, or '
        'plans. This axis captures forward-looking rhetorical structure '
        'and stated intentions.',
  },
  'framing_justification': {
    'title': 'Justification / Reactive',
    'body':
        'Measures language that defends, explains, or responds to prior '
        'events or criticism. This axis captures reactive rhetorical '
        'structure and self-positioning.',
  },
  'framing_imperative': {
    'title': 'Imperative / Directive',
    'body':
        'Measures language that issues commands, calls to action, or '
        'directives. This axis captures authoritative rhetorical '
        'structure and urgency framing.',
  },

  // ── Analysis Surfaces ──────────────────────────────────────────
  'vote_record': {
    'title': 'Vote Record',
    'body':
        'Recorded positions on legislation from official roll call data. '
        'Displays how a figure voted, not what they said about it. '
        'Sourced from congressional records.',
  },
  'bill_overview': {
    'title': 'Bill Overview',
    'body':
        'An automated summary of the bill\'s stated purpose and notable '
        'provisions, categorized by structural type. Generated by AI. '
        'Review original bill text for full context.',
  },
  'provision_categories': {
    'title': 'Provision Categories',
    'body':
        'Each provision is classified by its structural role within the '
        'bill: spending, regulatory, procedural, or other. Classification '
        'is automated. Review original text for full context.',
  },
  'trends': {
    'title': 'Historical Trends',
    'body':
        'Tracks how a figure\'s measurement values have changed over '
        'time. Each data point represents an aggregated period. Trend '
        'direction is mathematical, not editorial.',
  },
  'measured_by': {
    'title': 'Measured By',
    'body':
        'Shows which AI models contributed measurements to this '
        'statement. Each model processes the statement independently. '
        'None can see the others\' results.',
  },
  'shift_detected': {
    'title': 'Shift Detected',
    'body':
        'A shift is flagged when a figure\'s measurement values change '
        'beyond the threshold compared to their rolling average. This '
        'is a statistical observation, not an interpretation.',
  },
  'shift_thresholds': {
    'title': 'Shift Thresholds',
    'body':
        'Controls how sensitive shift detection is for each followed '
        'figure. Lower sigma values trigger alerts on smaller changes. '
        'Cooldown sets the minimum time between notifications.',
  },
  'drift_waterfall': {
    'title': 'Drift Waterfall',
    'body':
        'Visualizes how each provision\'s drift score cascades through '
        'the bill\'s structure. Provisions are sorted by drift magnitude '
        'to reveal the overall legislative coherence pattern.',
  },
  'drift_league': {
    'title': 'Drift League Table',
    'body':
        'Ranks all provisions by their drift score from the bill\'s '
        'stated purpose. Higher-ranked provisions show greater thematic '
        'distance from the bill\'s original intent.',
  },
  'first_visit': {
    'title': 'Welcome to Statement Detail',
    'body':
        'This screen shows how multiple independent AI models measured '
        'a single public statement. Tap any section header for an '
        'explanation of what that measurement captures.',
  },

  // ── Feed ───────────────────────────────────────────────────────
  'why_this': {
    'title': 'Why am I seeing this?',
    'body':
        'Statements are ranked by a combination of recency, signal '
        'strength, and novelty. Newer statements with higher measurement '
        'activity appear first. This ranking is observational. It '
        'reflects data volume, not editorial selection.',
  },

  // ── Core Features (ungated) ─────────────────────────────────
  'feed_sort': {
    'title': 'Feed Sorting',
    'body':
        'Sort your feed by novelty, recency, or signal strength. '
        'Available to all tiers. Sorting does not alter content, '
        'only display order.',
  },
  'bills_browse': {
    'title': 'Bills',
    'body':
        'Browse active legislation tracked by Baseline. Each bill card '
        'shows status, sponsor, and provision count. Available to all '
        'tiers. Bill Overview and mutations require Pro+.',
  },
  'followed_figures': {
    'title': 'Followed Figures',
    'body':
        'Follow figures to filter your feed and get updates. Core users '
        'can follow up to 10 figures. Pro and above get unlimited follows.',
  },
};

// ═══════════════════════════════════════════
// LENS IDENTIFIERS
// ═══════════════════════════════════════════

const String kLensAll = 'ALL';
const String kLensGP = 'GP';
const String kLensCL = 'CL';
const String kLensGR = 'GR';

const double kTabBarBottomPadding = 100.0;

const String kHapticPrefKey = 'haptic_enabled';
const String kChangelogLastSeenKey = 'changelog_last_seen';

const String kAppStoreId = '[STORE_ID_REDACTED]';
const String kShareText = kShareAppText;
const String kProLaunchMonthly = kProIntroMonthly;
