/// Subscription model for Baseline.
///
/// Represents the user's subscription state from Supabase
/// `get_my_subscription()` RPC (A17A V1.0.1).
///
/// This is the SERVER-SIDE view. RevenueCat is source of truth for
/// purchase receipts; backend syncs tier via A17B → A17A.
///
/// Path: lib/models/subscription.dart
library;
import 'package:flutter/foundation.dart';
//
// ════════════════════════════════════════════════════════════
// ════════════
// SUBSCRIPTION STATUS
//
// ════════════════════════════════════════════════════════════
// ════════════
/// Canonical subscription statuses (A17A CHECK constraint).
///
/// Status lifecycle:
/// none → active (purchase)
/// active → cancelled (user cancels, active until period_end)
/// active → billing_issue → grace_period → expired
/// active → refunded (access revoked immediately)
/// cancelled → expired (period_end reached)
/// cancelled → active (uncancellation / renewal)
/// any → promotional (admin_set_tier)
enum SubscriptionStatus {
/// No subscription row exists (free tier).
none('none'),
/// Current and paid — full access.
active('active'),
/// Free trial period — full access.
trialing('trialing'),
/// Payment failed, within grace period — full access continues.
gracePeriod('grace_period'),
/// Payment failed, past grace — access may be restricted.
billingIssue('billing_issue'),
/// Subscription ended (renewal failed or period expired).
expired('expired'),
/// User cancelled — active until current_period_end.
cancelled('cancelled'),
/// Refund processed — access revoked immediately.
refunded('refunded'),
/// Play Store pause feature.
paused('paused'),
/// Admin/promo grant via admin_set_tier().
promotional('promotional');
const SubscriptionStatus(this.value);
/// Raw string value matching backend CHECK constraint.
final String value;
/// Parses from backend string. Defaults to [none] for unknown values.
/// Logs unknown values in debug mode to catch A17A schema changes.
static SubscriptionStatus fromString(String? raw) {
if (raw == null || raw.isEmpty) return none;
for (final status in values) {
if (status.value == raw) return status;
}
if (kDebugMode) {
debugPrint('SubscriptionStatus: unknown status "$raw" → defaulting to none');
}
return none;
}
/// Whether this status grants active access to paid features.
///
/// Active statuses: active, trialing, cancelled (until period_end),
/// grace_period, promotional.
/// These match A17A's sync_subscription_tier() logic.
bool get grantsAccess {
switch (this) {
case active:
case trialing:
case cancelled: // Active until period_end
case gracePeriod:
case promotional:
return true;
case none:
case billingIssue:
case expired:
case refunded:
case paused:
return false;
}
}
}
//
// ════════════════════════════════════════════════════════════
// ════════════
// PLAN TYPE
//
// ════════════════════════════════════════════════════════════
// ════════════
/// Subscription plan duration (A17A CHECK constraint).
enum PlanType {
monthly('monthly'),
annual('annual'),
lifetime('lifetime'),
promotional('promotional');
const PlanType(this.value);
final String value;
/// Parses from backend string. Returns null for unknown/missing values.
static PlanType? fromString(String? raw) {
if (raw == null || raw.isEmpty) return null;
for (final plan in values) {
if (plan.value == raw) return plan;
}
if (kDebugMode) {
debugPrint('PlanType: unknown plan_type "$raw" → returning null');
}
return null;
}
}
//
// ════════════════════════════════════════════════════════════
// ════════════
// SUBSCRIPTION MODEL
//
// ════════════════════════════════════════════════════════════
// ════════════
/// User's subscription state from Supabase.
///
/// Returned by `get_my_subscription()` (A17A).
/// Response shape:
///


class Subscription {
  const Subscription({
    required this.userId,
    required this.status,
    required this.planType,
    this.expiresAt,
    this.trialEndsAt,
    this.tier = 'free',
  });

  final String userId;
  final SubscriptionStatus status;
  final PlanType planType;
  final DateTime? expiresAt;
  final DateTime? trialEndsAt;
  final String tier;

  bool get isActive => status.grantsAccess;
  bool get isPro => tier == 'pro' || tier == 'pro_plus' || tier == 'b2b';
  bool get isProPlus => tier == 'pro_plus' || tier == 'b2b';
  bool get isB2B => tier == 'b2b';
  String get displayName => switch (tier) {
    'pro' => 'Pro',
    'pro_plus' => 'Pro+',
    'b2b' => 'B2B',
    _ => 'Free',
  };

  bool get isCancelledButActive => status == SubscriptionStatus.cancelled && isActive;
  bool get hasBillingIssue => status == SubscriptionStatus.billingIssue;
  bool get autoRenewEnabled => isActive && status == SubscriptionStatus.active;
  DateTime? get currentPeriodEnd => expiresAt;
  DateTime? get currentPeriodStart => null;
  String? get store => null;
  bool get isSandbox => false;
  static const free = Subscription(userId: '', status: SubscriptionStatus.none, planType: PlanType.monthly, tier: 'free');
  factory Subscription.fromJson(Map<String, dynamic> json) {
    final expiresRaw = json['expires_at'] as String?;
    final trialRaw = json['trial_ends_at'] as String?;
    return Subscription(
      userId: json['user_id'] as String? ?? '',
      status: SubscriptionStatus.fromString(json['status'] as String?),
      planType: PlanType.fromString(json['plan_type'] as String?) ?? PlanType.monthly,
      tier: json['tier'] as String? ?? 'free',
      expiresAt: expiresRaw != null ? DateTime.tryParse(expiresRaw)?.toUtc() : null,
      trialEndsAt: trialRaw != null ? DateTime.tryParse(trialRaw)?.toUtc() : null,
    );
  }
}
