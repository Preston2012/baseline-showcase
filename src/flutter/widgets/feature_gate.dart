///
/// Path: lib/widgets/feature_gate.dart
library;

// 1. Flutter
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

// 2. Third-party
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

// 3. Config
import 'package:baseline_app/config/constants.dart';
import 'package:baseline_app/config/routes.dart';
import 'package:baseline_app/config/theme.dart';
import 'package:baseline_app/config/tier_feature_map.dart';

// 4. Services + utils
import 'package:baseline_app/utils/gate_state_machine.dart';
import 'package:baseline_app/utils/haptic_util.dart';
import 'package:baseline_app/models/gate_types.dart';

// 5. Providers
import 'package:baseline_app/providers/tier_provider.dart';

// 6. Widgets
import 'package:baseline_app/widgets/info_bottom_sheet.dart';
import 'package:baseline_app/widgets/paywall_gate.dart';
import 'package:baseline_app/widgets/tier_badge.dart';

// ════════════════════════════════════════════════════════════════════════
// CONSTANTS
// ════════════════════════════════════════════════════════════════════════

/// Crossfade duration for locked/unlocked transition.
const Duration _kCrossfadeDuration = Duration(milliseconds: 200);

/// Teal shimmer opacity for Tap 2 "The Taste".
const double _kShimmerOpacity = 0.05;

/// Pro+ tagline: locked copy.
const String _kProPlusTagline = 'More signal. Less noise.';

// ════════════════════════════════════════════════════════════════════════
// FEATURE GATE WIDGET
// ════════════════════════════════════════════════════════════════════════

class FeatureGate extends ConsumerWidget {
  const FeatureGate({
    super.key,
    required this.feature,
    this.featureName = '',
    required this.child,
    this.teaserWidget,
    this.onUpgrade,
    this.onDeclined,
    this.onGateDeclined,
    this.fallback,
    this.infoSheetKey,
    this.surface,
    this.invertGate = false,
  });

  /// Which gated feature this gate protects.
  final GatedFeature feature;

  /// Human-readable feature name (e.g., "Framing Radar\u2122").
  final String featureName;

  /// The content to show when unlocked.
  final Widget child;

  /// G-3: Optional teaser widget: one real metric shown faded behind blur.
  final Widget? teaserWidget;

  /// Custom upgrade callback. Defaults to navigating to F4.16 paywall.
  final VoidCallback? onUpgrade;

  /// Callback when user declines the gate.
  final VoidCallback? onDeclined;

  /// Callback when user declines the gate (alias for onDeclined).
  final VoidCallback? onGateDeclined;

  /// Fallback widget when feature is gated.
  final Widget? fallback;

  /// Info sheet key for Tap 1 "The Glimpse". If null, uses featureName
  /// lowercased with spaces removed as lookup key.
  final String? infoSheetKey;

  /// Surface name for F2.18 contextualized field brief.
  final String? surface;

  /// When true, inverts the gate logic: shows child when feature is NOT available.
  final bool invertGate;

  /// Static convenience: check entitlement and run [onAllowed] immediately.
  /// Currently passes through (tier gating handled by widget tree).
  static Future<void> checkAndRun({
    required BuildContext context,
    required GatedFeature feature,
    required VoidCallback onAllowed,
  }) async {
    onAllowed();
  }

  /// Static convenience: guard an action behind feature entitlement.
  /// Currently passes through (tier gating handled by widget tree).
  static void guard(
    BuildContext context, {
    required GatedFeature feature,
    required VoidCallback onAllowed,
  }) {
    onAllowed();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tier = ref.watch(tierProvider.select((s) => s.tier));
    // BUG-3.5: In debug builds, bypass all tier checks so every feature
    // is accessible during development.
    final rawAccess = kDebugMode ? true : canAccessFeature(tier, feature);
    final hasAccess = invertGate ? !rawAccess : rawAccess;

    // Debug-mode coverage check (F6.3).
    assertFeatureGated(feature);

    return AnimatedSwitcher(
      duration: _kCrossfadeDuration,
      child: hasAccess
          ? KeyedSubtree(
              key: const ValueKey('unlocked'),
              child: child,
            )
          : invertGate
              // Inverted gate: user HAS the feature, so just hide the child.
              // Never show a paywall for inverted gates (e.g. ad banners).
              ? KeyedSubtree(
                  key: const ValueKey('inverted-hidden'),
                  child: fallback ?? const SizedBox.shrink(),
                )
              : KeyedSubtree(
                  key: const ValueKey('locked'),
                  child: _GateHandler(
                    feature: feature,
                    featureName: featureName,
                    teaserWidget: teaserWidget,
                    onUpgrade: onUpgrade,
                    infoSheetKey: infoSheetKey,
                    surface: surface,
                    currentTier: tier,
                    child: child,
                  ),
                ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════
// GATE HANDLER (stateful: async stage fetch)
// ════════════════════════════════════════════════════════════════════════

class _GateHandler extends StatefulWidget {
  const _GateHandler({
    required this.feature,
    required this.featureName,
    required this.child,
    required this.currentTier,
    this.teaserWidget,
    this.onUpgrade,
    this.infoSheetKey,
    this.surface,
  });

  final GatedFeature feature;
  final String featureName;
  final Widget child;
  final String currentTier;
  final Widget? teaserWidget;
  final VoidCallback? onUpgrade;
  final String? infoSheetKey;
  final String? surface;

  @override
  State<_GateHandler> createState() => _GateHandlerState();
}

class _GateHandlerState extends State<_GateHandler> {
  GateStage _stage = GateStage.glimpse;

  /// Synchronous guard against overlapping async advance() calls.
  /// Prevents double-tap race condition on SharedPreferences.
  bool _isAdvancing = false;

  @override
  void initState() {
    super.initState();
    _fetchStage();
  }

  Future<void> _fetchStage() async {
    final stage = GateStateMachine.peek();
    if (mounted) setState(() => _stage = stage);
  }

  Future<void> _onGateTap() async {
    if (_isAdvancing) return;
    _isAdvancing = true;

    try {
      HapticUtil.light();
      final result = await GateStateMachine.advance();
      if (!mounted) return;
      final stage = result.currentStage;
      setState(() => _stage = stage);

      switch (stage) {
        case GateStage.glimpse:
        case GateStage.cooldown:
          // Tap 1 (or cooldown): Show info sheet field brief.
          final key = widget.infoSheetKey ??
              widget.featureName
                  .replaceAll('\u2122', '')
                  .replaceAll(' ', '_')
                  .toLowerCase();
          InfoBottomSheet.show(
            context,
            key: key,
            surface: widget.surface,
          );

        case GateStage.taste:
          // Tap 2: Visual shimmer already shown via _stage.
          // No additional action needed: the UI reacts.
          break;

        case GateStage.drop:
          // Tap 3: Show upgrade dialog.
          await _showDropDialog();
      }
    } finally {
      _isAdvancing = false;
    }
  }

  Future<void> _showDropDialog() async {
    final requiredTier = requiredTierFor(widget.feature);
    final tierName = kTierDisplayNames[requiredTier] ?? 'Pro';
    final isProPlus =
        requiredTier == 'pro_plus' || requiredTier == 'b2b';

    final result = await showDialog<bool>(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: BaselineColors.card,
        elevation: 0,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(BaselineRadius.md),
          side: BorderSide(
            color: BaselineColors.teal,
            width: BaselineCardStyle.borderWidth,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(BaselineSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Feature name ──
              Text(
                widget.featureName,
                style: BaselineTypography.h2.copyWith(
                  color: BaselineColors.textPrimary,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: BaselineSpacing.xs),

              // ── Tier requirement ──
              TierBadge(tierKey: requiredTier),

              const SizedBox(height: BaselineSpacing.md),

              // ── Tagline (Pro+ only) ──
              if (isProPlus) ...[
                Text(
                  _kProPlusTagline,
                  style: BaselineTypography.dataSmall.copyWith(
                    color: BaselineColors.teal
                        .atOpacity(BaselineOpacity.moderate),
                    fontStyle: FontStyle.italic,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: BaselineSpacing.md),
              ],

              // ── CTA ──
              SizedBox(
                width: 260,
                height: 52,
                child: ElevatedButton(
                  onPressed: () {
                    HapticUtil.medium();
                    Navigator.of(context).pop(true);
                    if (widget.onUpgrade != null) {
                      widget.onUpgrade!();
                    } else {
                      context.push(AppRoutes.paywall);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: BaselineColors.teal,
                    foregroundColor: BaselineColors.background,
                    elevation: 0,
                    shadowColor: Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(BaselineRadius.sm),
                    ),
                    textStyle: BaselineTypography.body1.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  child: Text('View $tierName'),
                ),
              ),

              const SizedBox(height: BaselineSpacing.xs),

              // ── Trial reassurance ──
              Text(
                '7-day free trial. Cancel anytime.',
                style: BaselineTypography.dataSmall.copyWith(
                  color: BaselineColors.textSecondary
                      .atOpacity(BaselineOpacity.moderate),
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: BaselineSpacing.md),

              // ── Maybe Later ──
              TextButton(
                onPressed: () async {
                  await GateStateMachine.startCooldown(const Duration(days: 14));
                  if (mounted) {
                    Navigator.of(context).pop(false);
                    setState(() => _stage = GateStage.cooldown);
                  }
                },
                style: TextButton.styleFrom(
                  minimumSize: const Size(
                    BaselineTouchTarget.min,
                    BaselineTouchTarget.min,
                  ),
                  foregroundColor: BaselineColors.textSecondary,
                ),
                child: Text(
                  'Maybe Later',
                  style: BaselineTypography.body2.copyWith(
                    color: BaselineColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    // Backdrop/back-button dismissal (result == null): treat as "Maybe Later"
    // to prevent dialog spam on every subsequent tap.
    if (result == null && mounted) {
      await GateStateMachine.startCooldown(const Duration(days: 14));
      if (!mounted) return;
      setState(() => _stage = GateStage.cooldown);
    }
  }

  @override
  Widget build(BuildContext context) {
    final requiredTier = requiredTierFor(widget.feature);
    final tierName = kTierDisplayNames[requiredTier] ?? 'Pro';
    final isProPlus =
        requiredTier == 'pro_plus' || requiredTier == 'b2b';

    // Shimmer overlay for Taste stage.
    final showShimmer = _stage == GateStage.taste;

    return Semantics(
      button: true,
      excludeSemantics: true,
      label:
          '${widget.featureName} requires $tierName. Tap to learn more.',
      child: GestureDetector(
        onTap: _onGateTap,
        behavior: HitTestBehavior.opaque,
        child: Stack(
          children: [
            // ── F2.12 PaywallGate handles ALL visuals ──
            PaywallGate(
              featureName: widget.featureName,
              requiredTier: requiredTier,
              isProPlus: isProPlus,
              teaserWidget: widget.teaserWidget,
              onUpgrade: () {
                // Direct CTA tap bypasses the 3-tap and goes to paywall.
                HapticUtil.medium();
                if (widget.onUpgrade != null) {
                  widget.onUpgrade!();
                } else {
                  context.push(AppRoutes.paywall);
                }
              },
              child: widget.child,
            ),

            // ── Shimmer overlay (Taste stage only) ──
            if (showShimmer)
              Positioned.fill(
                child: ExcludeSemantics(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: BaselineColors.teal
                            .atOpacity(_kShimmerOpacity),
                        borderRadius:
                            BorderRadius.circular(BaselineCardStyle.radius),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

}
