import 'package:flutter/material.dart';

// ── F1.1 — COLOR PALETTE ────────────────────────────────────

/// Canonical color tokens for the Baseline design system.
/// Dark-theme only. Every color in the app traces back here.
class BaselineColors {
  BaselineColors._();

  // ── Backgrounds ────────────────────────────────────────
  static const Color background = Color(0xFF081017);
  static const Color scaffoldBackground = Color(0xFF081017);
  static const Color scaffoldBg = Color(0xFF081017);
  static const Color surface = Color(0xFF0E1921);
  static const Color card = Color(0xFF111D29);
  static const Color cardElevated = Color(0xFF1A2836);

  // ── Brand accent ───────────────────────────────────────
  static const Color teal = Color(0xFF00E0C6);
  static const Color tealMuted = Color(0x4D00E0C6); // 30%
  static const Color proGlow = Color(0x2600E0C6); // 15%

  // ── Semantic ───────────────────────────────────────────
  static const Color amber = Color(0xFFFFAB00);
  static const Color error = Color(0xFFFF5252);
  static const Color warning = Color(0xFFFFAB00);
  static const Color success = Color(0xFF00C853);
  static const Color info = Color(0xFF448AFF);

  // ── Text ───────────────────────────────────────────────
  static const Color textPrimary = Color(0xFFEDF2F7);
  static const Color textSecondary = Color(0xFF9EAAB5);
  static const Color textTertiary = Color(0xFF6B7A88);

  // ── Borders ────────────────────────────────────────────
  static const Color border = Color(0x2600E0C6); // teal 15%
  static const Color borderInactive = Color(0x1F9EAAB5); // textSecondary 12%

  // ── Shimmer ────────────────────────────────────────────
  static const Color shimmerBase = Color(0xFF162232);
  static const Color shimmerHighlight = Color(0xFF1F3044);

  // ── Vote ───────────────────────────────────────────────
  static const Color voteRecorded = Color(0xFF00C853);
  static const Color voteNotRecorded = Color(0xFF6B7A88);

  // ── Spectral Wavelengths (Lens Lab™ / Variance Strip / Dossier) ──
  static const Color spectralTeal = Color(0xFF2DD4BF);
  static const Color spectralCyan = Color(0xFF2DB4D4);
  static const Color spectralGreen = Color(0xFF2DD49F);

  // ── Threshold / Spending Amber ──────────────────────────
  static const Color amberMuted = Color(0xFFD4A72D);

  // ── Chamber / Political ────────────────────────────────
  static const Color chamberBlue = Color(0xFF4A90D9);
  static const Color chamberRed = Color(0xFFD94A4A);
  static const Color driftAmber = Color(0xFFE5A93D);

  // ── Neutrals ───────────────────────────────────────────
  static const Color black = Color(0xFF000000);
  static const Color nearBlack = Color(0xFF0A0A0A);
  static const Color white = Color(0xFFFFFFFF);
}

// ── F1.2 — SPACING SCALE ────────────────────────────────────

/// 9-step spacing scale used by every layout token.
class BaselineSpacing {
  BaselineSpacing._();

  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double m = 14;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;
}

// ── F1.3 — TYPOGRAPHY ───────────────────────────────────────

/// Typography tokens. Poppins for UI, JetBrains Mono for data.
class BaselineTypography {
  BaselineTypography._();

  // ── Font family strings ──────────────────────────────────
  static const String bodyFontFamily = 'Poppins';
  static const String monoFontFamily = 'JetBrains Mono';

  // ── Base TextStyle aliases (used with .copyWith) ────────
  static const TextStyle poppins = TextStyle(fontFamily: bodyFontFamily);
  static const TextStyle jbMono = TextStyle(fontFamily: monoFontFamily);
  static const String poppinsFamily = 'Poppins';
  static const String jbMonoFamily = 'JetBrains Mono';

  // ── Headings ───────────────────────────────────────────
  static const TextStyle h1 = TextStyle(
    fontFamily: bodyFontFamily,
    fontSize: 28,
    fontWeight: FontWeight.w700,
    color: BaselineColors.textPrimary,
    height: 1.2,
  );

  static const TextStyle headline1 = h1;

  static const TextStyle h2 = TextStyle(
    fontFamily: bodyFontFamily,
    fontSize: 22,
    fontWeight: FontWeight.w600,
    color: BaselineColors.textPrimary,
    height: 1.25,
  );

  static const TextStyle heading = h2;

  static const TextStyle h3 = TextStyle(
    fontFamily: bodyFontFamily,
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: BaselineColors.textPrimary,
    height: 1.3,
  );

  static const TextStyle h4 = TextStyle(
    fontFamily: bodyFontFamily,
    fontSize: 15,
    fontWeight: FontWeight.w600,
    color: BaselineColors.textPrimary,
    height: 1.35,
  );

  // ── Body ───────────────────────────────────────────────
  static const TextStyle body = TextStyle(
    fontFamily: bodyFontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: BaselineColors.textPrimary,
    height: 1.5,
  );

  static const TextStyle body1 = body;

  static const TextStyle body2 = TextStyle(
    fontFamily: bodyFontFamily,
    fontSize: 13,
    fontWeight: FontWeight.w400,
    color: BaselineColors.textSecondary,
    height: 1.45,
  );

  static const TextStyle bodyMedium = TextStyle(
    fontFamily: bodyFontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: BaselineColors.textPrimary,
    height: 1.5,
  );

  static const TextStyle bodySmall = TextStyle(
    fontFamily: bodyFontFamily,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: BaselineColors.textSecondary,
    height: 1.4,
  );

  // ── Button / Caption / Overline ────────────────────────
  static const TextStyle button = TextStyle(
    fontFamily: bodyFontFamily,
    fontSize: 15,
    fontWeight: FontWeight.w600,
    color: BaselineColors.textPrimary,
    letterSpacing: 0.3,
  );

  static const TextStyle caption = TextStyle(
    fontFamily: bodyFontFamily,
    fontSize: 11,
    fontWeight: FontWeight.w400,
    color: BaselineColors.textTertiary,
    height: 1.3,
  );

  static const TextStyle overline = TextStyle(
    fontFamily: bodyFontFamily,
    fontSize: 10,
    fontWeight: FontWeight.w600,
    color: BaselineColors.textSecondary,
    letterSpacing: 1.2,
  );

  // ── Data (monospace) ───────────────────────────────────
  static const TextStyle data = TextStyle(
    fontFamily: monoFontFamily,
    fontSize: 13,
    fontWeight: FontWeight.w400,
    color: BaselineColors.teal,
    height: 1.4,
  );

  static const TextStyle dataLarge = TextStyle(
    fontFamily: monoFontFamily,
    fontSize: 18,
    fontWeight: FontWeight.w500,
    color: BaselineColors.teal,
    height: 1.3,
  );

  static const TextStyle dataSmall = TextStyle(
    fontFamily: monoFontFamily,
    fontSize: 11,
    fontWeight: FontWeight.w400,
    color: BaselineColors.teal,
    height: 1.3,
  );
}

// ── F1.8 — INSETS ───────────────────────────────────────────

class BaselineInsets {
  BaselineInsets._();

  // ── Screen-level (horizontal margins) ─────────────────

  static const EdgeInsets screenH = EdgeInsets.symmetric(
    horizontal: BaselineSpacing.xl,
  );

  static const EdgeInsets screen = EdgeInsets.symmetric(
    horizontal: BaselineSpacing.xl,
    vertical: BaselineSpacing.md,
  );

  // ── Card-level ────────────────────────────────────────

  static const EdgeInsets card = EdgeInsets.all(BaselineSpacing.md);

  static const EdgeInsets cardCompact = EdgeInsets.all(BaselineSpacing.sm);

  static const EdgeInsets cardLarge = EdgeInsets.all(BaselineSpacing.lg);

  // ── Section gaps (vertical only) ──────────────────────

  static const EdgeInsets sectionSm = EdgeInsets.only(
    top: BaselineSpacing.xs,
  );

  static const EdgeInsets sectionMd = EdgeInsets.only(
    top: BaselineSpacing.md,
  );

  static const EdgeInsets sectionLg = EdgeInsets.only(
    top: BaselineSpacing.xl,
  );

  static const EdgeInsets sectionXl = EdgeInsets.only(
    top: BaselineSpacing.xxl,
  );

  // ── List/Feed scroll padding ──────────────────────────

  static const EdgeInsets listPadding = EdgeInsets.fromLTRB(
    BaselineSpacing.xl,
    BaselineSpacing.md,
    BaselineSpacing.xl,
    BaselineTabBar.height + BaselineSpacing.lg * 2,
  );

  // ── Row-level (inline items) ──────────────────────────

  static const EdgeInsets rowGapSm = EdgeInsets.symmetric(
    horizontal: BaselineSpacing.xxs,
  );

  static const EdgeInsets row = EdgeInsets.symmetric(
    horizontal: BaselineSpacing.md,
    vertical: BaselineSpacing.sm,
  );

  // ── Convenience aliases ───────────────────────────────

  static const EdgeInsets allM = EdgeInsets.all(BaselineSpacing.md);

  static const EdgeInsets allS = EdgeInsets.all(BaselineSpacing.sm);

  static const EdgeInsets horizontalM = EdgeInsets.symmetric(
    horizontal: BaselineSpacing.md,
  );

  // ── Zero ──────────────────────────────────────────────

  static const EdgeInsets none = EdgeInsets.zero;
}

// ── F1.9 — ANIMATION CONSTANTS ──────────────────────────────

class BaselineAnimation {
  BaselineAnimation._();

  static const Duration fast = Duration(milliseconds: 200);

  static const Duration medium = Duration(milliseconds: 300);

  static const Duration normal = Duration(milliseconds: 300);

  static const Duration standard = Duration(milliseconds: 300);

  static const Curve curve = Curves.easeOut;
}

// ── MOTION TOKENS ───────────────────────────────────────────

class BaselineMotion {
  BaselineMotion._();

  // ── Stagger (list fade-in animations) ─────────────────

  static const Duration staggerDelay = Duration(milliseconds: 40);

  static const double staggerSlide = 6.0;

  // ── Press scale (GestureDetector + AnimatedScale) ─────

  static const double pressScaleCard = 0.98;

  static const double pressScaleChip = 0.95;

  static const double pressScaleButton = 0.97;

  // ── Durations ─────────────────────────────────────────

  static const Duration fast = Duration(milliseconds: 200);

  static const Duration medium = Duration(milliseconds: 300);

  static const Duration normal = Duration(milliseconds: 300);

  static const Duration standard = Duration(milliseconds: 300);

  static const Duration scanline = Duration(milliseconds: 800);

  static const Duration cursorBlink = Duration(milliseconds: 530);

  static const Duration expand = Duration(milliseconds: 200);

  static const Duration micro = Duration(milliseconds: 180);

  static const Duration slow = Duration(milliseconds: 600);

  // ── Debounce / Throttle ───────────────────────────────

  static const Duration debounce = Duration(milliseconds: 300);

  static const Duration refreshCooldown = Duration(seconds: 2);

  // ── Curves ────────────────────────────────────────────

  static const Curve curveEnter = Curves.easeOutCubic;

  static const Curve curveSettle = Curves.easeOut;

  static const Curve curveSymmetric = Curves.easeInOut;

  static const Curve curveBounce = Curves.elasticOut;

  // ── Scroll physics ────────────────────────────────────

  static const ClampingScrollPhysics clampingPhysics =
      ClampingScrollPhysics();

  static const BouncingScrollPhysics bouncingPhysics =
      BouncingScrollPhysics();
}

// ── OPACITY TOKENS ──────────────────────────────────────────

class BaselineOpacity {
  BaselineOpacity._();

  static const double ghost = 0.05;
  static const double faint = 0.10;
  static const double subtle = 0.15;
  static const double muted = 0.30;
  static const double moderate = 0.50;
  static const double prominent = 0.70;
  static const double heavy = 0.80;
  static const double nearOpaque = 0.94;
}

// ── RADIUS TOKENS ───────────────────────────────────────────

class BaselineRadius {
  BaselineRadius._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 14;
  static const double xl = 20;
  static const double pill = 100;

  // Convenience aliases
  static const double card = lg;
  static const double chip = sm;

  static final BorderRadius cardBorderRadius = BorderRadius.circular(lg);
  static final BorderRadius buttonBorderRadius = BorderRadius.circular(md);
  static final BorderRadius chipBorderRadius = BorderRadius.circular(sm);
  static const BorderRadius sheetBorderRadius = BorderRadius.vertical(
    top: Radius.circular(lg),
  );

  /// Allow BaselineRadius values to be used directly as borderRadius: argument
  /// by providing implicit conversion through operator overloading.
  /// Files should use BaselineRadius.cardBorderRadius etc for explicit BorderRadius.
}

/// Extension to allow using double as borderRadius in BoxDecoration.
/// This makes `borderRadius: BaselineRadius.card` work by implicitly
/// wrapping the double in BorderRadius.circular().
extension DoubleToBorderRadius on double {
  BorderRadius get borderRadius => BorderRadius.circular(this);
}

// ── BORDER PRESETS ──────────────────────────────────────────

class BaselineBorder {
  BaselineBorder._();

  static const BorderSide standard = BorderSide(
    color: BaselineColors.border,
    width: 2,
  );

  static const BorderSide inactive = BorderSide(
    color: BaselineColors.borderInactive,
    width: 1,
  );

  static const BorderSide pro = BorderSide(
    color: BaselineColors.teal,
    width: 2,
  );

  static const BorderSide alert = BorderSide(
    color: BaselineColors.amber,
    width: 2,
  );

  static const BorderSide divider = BorderSide(
    color: BaselineColors.border,
    width: 1,
  );

  static const BorderSide none = BorderSide.none;
}

// ── F1.4 — CARD STYLE ──────────────────────────────────────

class BaselineCardStyle {
  BaselineCardStyle._();

  static const double radius = 14;
  static const double borderWidth = 2;

  static final BoxDecoration standard = BoxDecoration(
    color: BaselineColors.card,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: BaselineColors.border, width: borderWidth),
  );

  static final BoxDecoration proHighlight = BoxDecoration(
    color: BaselineColors.card,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: BaselineColors.teal, width: borderWidth),
  );

  static final BoxDecoration alertHighlight = BoxDecoration(
    color: BaselineColors.card,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: BaselineColors.amber, width: borderWidth),
  );

  static final BoxDecoration elevated = BoxDecoration(
    color: BaselineColors.cardElevated,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: BaselineColors.border, width: borderWidth),
  );

  static final BoxDecoration inactive = BoxDecoration(
    color: BaselineColors.card,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: BaselineColors.borderInactive, width: 1),
  );
}

// ── F1.5 — BUTTON STYLES ───────────────────────────────────

class BaselineButtonStyle {
  BaselineButtonStyle._();

  static const double height = 52;
  static const double radius = 12;

  static final ButtonStyle primary = ElevatedButton.styleFrom(
    backgroundColor: BaselineColors.teal,
    foregroundColor: BaselineColors.background,
    minimumSize: const Size(double.infinity, height),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
    ),
    elevation: 0,
    textStyle: BaselineTypography.button,
    splashFactory: NoSplash.splashFactory,
  );

  static final ButtonStyle secondary = OutlinedButton.styleFrom(
    foregroundColor: BaselineColors.teal,
    minimumSize: const Size(double.infinity, height),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
    ),
    side: const BorderSide(color: BaselineColors.teal, width: 1),
    textStyle: BaselineTypography.button,
    splashFactory: NoSplash.splashFactory,
  );

  static final ButtonStyle text = TextButton.styleFrom(
    foregroundColor: BaselineColors.teal,
    minimumSize: Size(0, BaselineTouchTarget.min),
    splashFactory: NoSplash.splashFactory,
  );
}

// ── F1.6 — TAB BAR CONSTANTS ───────────────────────────────

class BaselineTabBar {
  BaselineTabBar._();

  static const double height = 60;
  static const double blurSigma = 20;
  static const Color frostedColor = Color(0xCC081017);
  static const Color frostedFallback = Color(0xF0081017);
}

// ── F1.7 — TOUCH TARGET ENFORCEMENT ────────────────────────

class BaselineTouchTarget {
  BaselineTouchTarget._();

  static const double min = 44;
  static const double rowHeight = 60;
  static const double rowHeightMax = 70;
}

// ── CORNER RADIUS ALIASES ─────────────────────────────────

class BaselineCorners {
  BaselineCorners._();
  static const double sm = 8.0;
  static const double md = 12.0;
}

// ── EXTENSIONS — Color Manipulation ─────────────────────────

extension BaselineColorExtension on Color {
  /// Returns a copy of this color with the given [opacity] (0.0–1.0).
  Color atOpacity(double opacity) => withValues(alpha: opacity);
}


class BaselineTheme {
  BaselineTheme._();
  static ThemeData get dark => ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: BaselineColors.scaffoldBackground,
    colorScheme: const ColorScheme.dark(
      primary: BaselineColors.teal,
      surface: BaselineColors.surface,
      error: BaselineColors.error,
    ),
    fontFamily: BaselineTypography.bodyFontFamily,
  );
}


/// Extension to allow Interval.animate(controller) pattern.
extension IntervalAnimate on Interval {
  Animation<double> animate(AnimationController controller) {
    return CurvedAnimation(parent: controller, curve: this);
  }
}
