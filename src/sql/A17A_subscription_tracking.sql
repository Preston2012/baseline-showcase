-- ========================================================================
-- BASELINE V1.4  - SUBSCRIPTION TRACKING + LIFECYCLE
-- A17A  - V1.0.1
--
-- FIXES APPLIED (V1.0.0 → V1.0.1  - dual audit reconciliation):
-- FIX1: Removed tier_features table, feature access RPCs, and seed data.
-- A13B V1.0.1 is canonical owner of tier_features,
-- check_feature_access(), get_feature_config(). No double-owner.
-- FIX2: map_product_to_tier() now recognizes *_admin and *_promotional
-- product IDs. Prevents admin_set_tier()-granted users from being
-- silently downgraded to 'free' on next sync_subscription_tier().
-- [Audit 2 Critical Blocker #2  - hard correctness bug]
-- FIX3: get_my_subscription() now always returns 'tier' field by calling
-- get_my_tier(). Consistent response shape. [Audit 2 High Issue]
-- FIX4: tier_features anon read removed (was in V1.0.0). A13B uses
-- authenticated-only read. No policy conflict. [Audit 2 Blocker #4]
-- FIX5: Removed redundant tier_features trigger/grants/RLS (A13B owns).
--
-- PURPOSE:
-- Subscription lifecycle data layer:
-- 1. subscriptions table (RevenueCat state per user, one row per user)
-- 2. subscription_events table (immutable audit log)
-- 3. map_product_to_tier()  - RevenueCat product → Baseline tier mapping
-- 4. sync_subscription_tier()  - sync user_profiles.tier from sub state
-- 5. upsert_subscription()  - insert/update sub + log event + sync tier
-- 6. get_my_subscription()  - authenticated user reads own sub
-- 7. expire_lapsed_subscriptions()  - cron safety net for missed webhooks
-- 8. admin_set_tier()  - manual tier override for B2B/support/promos
--
-- DEPENDENCIES:
-- - A1 V8.0 deployed (feature_flags table)
-- - A13A V1.0.2 deployed (user_profiles, get_my_tier(), protect_user_tier)
-- - A13B V1.0.1 deployed (tier_features, check_feature_access, get_feature_config)
-- - Supabase Auth (auth.users, auth.uid(), auth.role())
--
-- DOWNSTREAM CONSUMERS:
-- - A17B (RevenueCat webhook) → calls upsert_subscription()
-- - A17D (entitlement middleware) → reads user_profiles.tier (synced here)
-- - Cron job → calls expire_lapsed_subscriptions()
--
-- WHAT THIS DOES NOT DO:
-- - Does not create/manage tier_features (A13B owns that)
-- - Does not create feature access RPCs (A13B owns those)
-- - Does not create the webhook endpoint (A17B does that)
-- - Does not create rate limit primitives (A17C does that)
-- - Does not modify user_profiles schema (A13A owns that)
-- - Does not write to pipeline_events (avoids stage enum coupling)
--
-- SUBSCRIPTION STATUSES:
-- 'active'  - Current and paid
-- 'trialing'  - Free trial period
-- 'grace_period'  - Payment failed, within grace
-- 'billing_issue'  - Payment failed, past grace
-- 'expired'  - Ended (renewal failed or cancelled)
-- 'cancelled'  - User cancelled, active until period_end
-- 'refunded'  - Refund processed, access revoked
-- 'paused'  - Play Store pause feature
-- 'promotional'  - Admin/promo grant
--
-- STORE VALUES: 'app_store', 'play_store', 'stripe', 'promotional'
--
-- PRODUCT → TIER MAPPING (LOCKED):
-- baseline_pro_monthly, baseline_pro_annual → 'pro'
-- baseline_pro_admin, baseline_pro_promotional → 'pro'
-- baseline_pro_plus_monthly, baseline_pro_plus_annual → 'pro_plus'
-- baseline_pro_plus_admin, baseline_pro_plus_promotional → 'pro_plus'
-- baseline_b2b, baseline_b2b_admin → 'b2b'
-- Unknown / expired / no subscription → 'free'
--
-- Safety: All DDL is idempotent. All RPCs REVOKE'd from PUBLIC.
-- ========================================================================
-- ########################################################################
-- SECTION 1: SUBSCRIPTIONS TABLE
-- ########################################################################
-- One row per user. Updated on each webhook event.
-- History preserved in subscription_events.
-- UNIQUE(user_id): plan changes update the row, not duplicate it.
-- Free-tier users simply have no row here.
-- ########################################################################
CREATE TABLE IF NOT EXISTS subscriptions (
subscription_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
user_id UUID NOT NULL UNIQUE
REFERENCES auth.users(id) ON DELETE CASCADE,
-- RevenueCat identifiers
revenuecat_app_user_id TEXT,
revenuecat_original_app_user_id TEXT,
entitlement_id TEXT,
-- Product/plan
product_id TEXT NOT NULL,
plan_type TEXT NOT NULL CHECK (plan_type IN (
'monthly', 'annual', 'lifetime', 'promotional'
)),
-- State
status TEXT NOT NULL DEFAULT 'active' CHECK (status IN (
'active', 'trialing', 'grace_period', 'billing_issue',
'expired', 'cancelled', 'refunded', 'paused', 'promotional'
)),
-- Billing periods
current_period_start TIMESTAMPTZ,
current_period_end TIMESTAMPTZ,
original_purchase_date TIMESTAMPTZ,
-- Store
store TEXT NOT NULL CHECK (store IN (
'app_store', 'play_store', 'stripe', 'promotional'
)),
environment TEXT NOT NULL DEFAULT 'production' CHECK (
environment IN ('production', 'sandbox')
),
-- Cancellation
cancellation_date TIMESTAMPTZ,
unsubscribe_detected_at TIMESTAMPTZ,
grace_period_expires_at TIMESTAMPTZ,
-- Auto-renewal
auto_renew_enabled BOOLEAN DEFAULT true,
-- Timestamps
created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
-- UNIQUE(user_id) creates index; only add supplemental indexes
CREATE INDEX IF NOT EXISTS idx_subscriptions_status
ON subscriptions(status)
WHERE status IN ('active', 'trialing', 'cancelled', 'grace_period');
CREATE INDEX IF NOT EXISTS idx_subscriptions_period_end
ON subscriptions(current_period_end)
WHERE status NOT IN ('expired', 'refunded');
CREATE INDEX IF NOT EXISTS idx_subscriptions_revenuecat
ON subscriptions(revenuecat_app_user_id)
WHERE revenuecat_app_user_id IS NOT NULL;
-- Updated_at trigger
CREATE OR REPLACE FUNCTION update_subscription_timestamp()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = pg_catalog, public
AS $$
BEGIN
NEW.updated_at := now();
RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trigger_subscription_timestamp ON subscriptions;
CREATE TRIGGER trigger_subscription_timestamp
BEFORE UPDATE ON subscriptions
FOR EACH ROW
EXECUTE FUNCTION update_subscription_timestamp();
-- ########################################################################
-- SECTION 2: SUBSCRIPTION_EVENTS TABLE (Immutable audit log)
-- ########################################################################
-- Every webhook/lifecycle event logged here. Never updated, never deleted.
-- Used for debugging, analytics, and dispute resolution.
-- ########################################################################
CREATE TABLE IF NOT EXISTS subscription_events (
event_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
subscription_id UUID REFERENCES subscriptions(subscription_id) ON DELETE SET
NULL,
-- Event metadata
event_type TEXT NOT NULL CHECK (event_type IN (
'INITIAL_PURCHASE', 'RENEWAL', 'CANCELLATION',
'UNCANCELLATION', 'BILLING_ISSUE_DETECTED',
'BILLING_ISSUE_RESOLVED', 'PRODUCT_CHANGE',
'REFUND', 'EXPIRATION', 'TRANSFER',
'GRACE_PERIOD_ENTERED', 'GRACE_PERIOD_EXPIRED',
'PAUSE', 'UNPAUSE', 'PROMOTIONAL_GRANT',
'PROMOTIONAL_REVOKE', 'TIER_SYNC',
'ADMIN_OVERRIDE', 'LAPSED_EXPIRY'
)),
-- RevenueCat raw event data (full payload minus sensitive fields)
raw_event JSONB NOT NULL DEFAULT '{}'::jsonb,
-- Extracted fields for queryability
product_id TEXT,
store TEXT,
environment TEXT,
old_status TEXT,
new_status TEXT,
old_tier TEXT,
new_tier TEXT,
-- Timestamps
event_timestamp TIMESTAMPTZ NOT NULL DEFAULT now(),
created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_sub_events_user
ON subscription_events(user_id);
CREATE INDEX IF NOT EXISTS idx_sub_events_subscription
ON subscription_events(subscription_id);
CREATE INDEX IF NOT EXISTS idx_sub_events_type
ON subscription_events(event_type);
CREATE INDEX IF NOT EXISTS idx_sub_events_timestamp
ON subscription_events(event_timestamp DESC);
-- Immutability trigger
CREATE OR REPLACE FUNCTION prevent_sub_event_mutation()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = pg_catalog, public
AS $$
BEGIN
RAISE EXCEPTION 'subscription_events is append-only: % not allowed', TG_OP;
END;
$$;
DROP TRIGGER IF EXISTS trigger_sub_events_immutable ON subscription_events;
CREATE TRIGGER trigger_sub_events_immutable
BEFORE UPDATE OR DELETE ON subscription_events
FOR EACH ROW
EXECUTE FUNCTION prevent_sub_event_mutation();
-- ########################################################################
-- SECTION 3: PRODUCT → TIER MAPPING
-- ########################################################################
-- V1.0.1 FIX2: Recognizes *_admin and *_promotional product IDs so that
-- admin_set_tier()-granted subscriptions don't get mapped to 'free' on
-- the next sync_subscription_tier() call.
-- ########################################################################
CREATE OR REPLACE FUNCTION map_product_to_tier(p_product_id TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
SET search_path = pg_catalog, public
AS $$
SELECT CASE
WHEN p_product_id IN (
'baseline_pro_monthly', 'baseline_pro_annual',
'baseline_pro_admin', 'baseline_pro_promotional'
) THEN 'pro'
WHEN p_product_id IN (
'baseline_pro_plus_monthly', 'baseline_pro_plus_annual',
'baseline_pro_plus_admin', 'baseline_pro_plus_promotional'
) THEN 'pro_plus'
WHEN p_product_id IN (
'baseline_b2b', 'baseline_b2b_admin'
) THEN 'b2b'
ELSE 'free'
END;
$$;
-- ########################################################################
-- SECTION 4: SUBSCRIPTION LIFECYCLE RPCs
-- ########################################################################
-- ── sync_subscription_tier──────────────────────────────────────────────
-- Reads user's subscription, maps product→tier, updates user_profiles.tier.
-- B2B is admin-managed: never downgraded by subscription sync.
-- SECURITY DEFINER + auth.role() guard: service_role only.
-- protect_user_tier (A13A) recognizes service_role as authorized.
CREATE OR REPLACE FUNCTION sync_subscription_tier(p_user_id UUID)
RETURNS TEXT
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
v_current_tier TEXT;
v_new_tier TEXT;
v_product_id TEXT;
v_status TEXT;
v_sub_id UUID;
BEGIN
IF auth.role() IS DISTINCT FROM 'service_role' THEN
RAISE EXCEPTION 'sync_subscription_tier: service_role only';
END IF;
SELECT s.product_id, s.status, s.subscription_id
INTO v_product_id, v_status, v_sub_id
FROM public.subscriptions s
WHERE s.user_id = p_user_id;
IF NOT FOUND THEN
v_new_tier := 'free';
ELSIF v_status IN ('active', 'trialing', 'cancelled', 'grace_period', 'promotional') THEN
v_new_tier := public.map_product_to_tier(v_product_id);
ELSE
v_new_tier := 'free';
END IF;
SELECT tier INTO v_current_tier
FROM public.user_profiles
WHERE user_id = p_user_id;
IF v_current_tier IS DISTINCT FROM v_new_tier THEN
-- B2B is admin-managed; never downgrade via subscription sync
IF v_current_tier = 'b2b' AND v_new_tier != 'b2b' THEN
RAISE LOG 'A17A sync: skip B2B downgrade user=%, would=%',
p_user_id, v_new_tier;
RETURN v_current_tier;
END IF;
UPDATE public.user_profiles
SET tier = v_new_tier
WHERE user_id = p_user_id;
RAISE LOG 'A17A sync: user=% tier % → %',
p_user_id, v_current_tier, v_new_tier;
INSERT INTO public.subscription_events (
user_id, subscription_id, event_type,
old_tier, new_tier, raw_event
) VALUES (
p_user_id, v_sub_id, 'TIER_SYNC',
v_current_tier, v_new_tier,
jsonb_build_object(
'source', 'sync_subscription_tier',
'product_id', v_product_id,
'sub_status', v_status,
'timestamp', now()
)
);
END IF;
RETURN v_new_tier;
END;
$$;
-- ── upsert_subscription─────────────────────────────────────────────────
-- Idempotent. Inserts or updates user's subscription row.
-- Logs event in subscription_events. Calls sync_subscription_tier().
-- Called by A17B webhook. Service-role only.
CREATE OR REPLACE FUNCTION upsert_subscription(
p_user_id UUID,
p_event_type TEXT,
p_product_id TEXT,
p_plan_type TEXT,
p_status TEXT,
p_store TEXT,
p_environment TEXT DEFAULT 'production',
p_current_period_start TIMESTAMPTZ DEFAULT NULL,
p_current_period_end TIMESTAMPTZ DEFAULT NULL,
p_original_purchase_date TIMESTAMPTZ DEFAULT NULL,
p_revenuecat_app_user_id TEXT DEFAULT NULL,
p_revenuecat_original_id TEXT DEFAULT NULL,
p_entitlement_id TEXT DEFAULT NULL,
p_cancellation_date TIMESTAMPTZ DEFAULT NULL,
p_unsubscribe_detected_at TIMESTAMPTZ DEFAULT NULL,
p_grace_period_expires_at TIMESTAMPTZ DEFAULT NULL,
p_auto_renew_enabled BOOLEAN DEFAULT true,
p_raw_event JSONB DEFAULT '{}'::jsonb
)
RETURNS JSONB
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
v_sub_id UUID;
v_old_status TEXT;
v_new_tier TEXT;
BEGIN
IF auth.role() IS DISTINCT FROM 'service_role' THEN
RAISE EXCEPTION 'upsert_subscription: service_role only';
END IF;
IF p_user_id IS NULL THEN
RAISE EXCEPTION 'upsert_subscription: p_user_id required';
END IF;
IF COALESCE(p_product_id, '') = '' THEN
RAISE EXCEPTION 'upsert_subscription: p_product_id required';
END IF;
IF COALESCE(p_status, '') = '' THEN
RAISE EXCEPTION 'upsert_subscription: p_status required';
END IF;
IF COALESCE(p_store, '') = '' THEN
RAISE EXCEPTION 'upsert_subscription: p_store required';
END IF;
-- Get current status for event logging
SELECT status, subscription_id
INTO v_old_status, v_sub_id
FROM public.subscriptions
WHERE user_id = p_user_id;
-- Upsert (ON CONFLICT user_id)
INSERT INTO public.subscriptions (
user_id, product_id, plan_type, status, store, environment,
current_period_start, current_period_end, original_purchase_date,
revenuecat_app_user_id, revenuecat_original_app_user_id,
entitlement_id, cancellation_date, unsubscribe_detected_at,
grace_period_expires_at, auto_renew_enabled
) VALUES (
p_user_id, p_product_id, p_plan_type, p_status, p_store,
p_environment, p_current_period_start, p_current_period_end,
p_original_purchase_date, p_revenuecat_app_user_id,
p_revenuecat_original_id, p_entitlement_id, p_cancellation_date,
p_unsubscribe_detected_at, p_grace_period_expires_at,
p_auto_renew_enabled
)
ON CONFLICT (user_id) DO UPDATE SET
product_id = EXCLUDED.product_id,
plan_type = EXCLUDED.plan_type,
status = EXCLUDED.status,
store = EXCLUDED.store,
environment = EXCLUDED.environment,
current_period_start = EXCLUDED.current_period_start,
current_period_end = EXCLUDED.current_period_end,
revenuecat_app_user_id = EXCLUDED.revenuecat_app_user_id,
revenuecat_original_app_user_id = EXCLUDED.revenuecat_original_app_user_id,
entitlement_id = EXCLUDED.entitlement_id,
cancellation_date = EXCLUDED.cancellation_date,
unsubscribe_detected_at = EXCLUDED.unsubscribe_detected_at,
grace_period_expires_at = EXCLUDED.grace_period_expires_at,
auto_renew_enabled = EXCLUDED.auto_renew_enabled
-- original_purchase_date preserved across plan changes
-- updated_at handled by trigger
RETURNING subscription_id INTO v_sub_id;
-- Log event (immutable)
INSERT INTO public.subscription_events (
user_id, subscription_id, event_type, raw_event,
product_id, store, environment, old_status, new_status
) VALUES (
p_user_id, v_sub_id, p_event_type, p_raw_event,
p_product_id, p_store, p_environment, v_old_status, p_status
);
-- Sync tier to user_profiles
v_new_tier := public.sync_subscription_tier(p_user_id);
RETURN jsonb_build_object(
'subscription_id', v_sub_id,
'user_id', p_user_id,
'status', p_status,
'tier', v_new_tier,
'product_id', p_product_id,
'event_logged', true
);
END;
$$;
-- ── get_my_subscription─────────────────────────────────────────────────
-- Authenticated user reads own subscription. Returns NULL-sub + tier
-- if no subscription row. Always includes tier from get_my_tier().
-- V1.0.1 FIX3: tier field returned consistently in both branches.
-- SECURITY INVOKER: uses auth.uid() + RLS for row filtering.
CREATE OR REPLACE FUNCTION get_my_subscription()
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $$
DECLARE
v_result JSONB;
v_tier TEXT;
BEGIN
IF auth.uid() IS NULL THEN
RAISE EXCEPTION 'get_my_subscription: not authenticated';
END IF;
v_tier := public.get_my_tier();
SELECT jsonb_build_object(
'subscription_id', s.subscription_id,
'product_id', s.product_id,
'plan_type', s.plan_type,
'status', s.status,
'store', s.store,
'current_period_start', s.current_period_start,
'current_period_end', s.current_period_end,
'auto_renew_enabled', s.auto_renew_enabled,
'cancellation_date', s.cancellation_date,
'environment', s.environment,
'tier', v_tier
) INTO v_result
FROM public.subscriptions s
WHERE s.user_id = auth.uid();
IF v_result IS NULL THEN
RETURN jsonb_build_object(
'subscription_id', NULL,
'status', 'none',
'tier', v_tier
);
END IF;
RETURN v_result;
END;
$$;
-- ── expire_lapsed_subscriptions─────────────────────────────────────────
-- Safety net: catches subs where period_end passed but no webhook arrived.
-- Called by cron. Service-role only. Batch-limited to 100 per run.
CREATE OR REPLACE FUNCTION expire_lapsed_subscriptions(
p_grace_hours INTEGER DEFAULT 24
)
RETURNS JSONB
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
v_count INTEGER := 0;
v_sub RECORD;
v_cutoff TIMESTAMPTZ;
BEGIN
IF auth.role() IS DISTINCT FROM 'service_role' THEN
RAISE EXCEPTION 'expire_lapsed_subscriptions: service_role only';
END IF;
IF p_grace_hours < 0 OR p_grace_hours > 168 THEN
RAISE EXCEPTION 'grace_hours must be 0-168 (0-7 days)';
END IF;
v_cutoff := now() - make_interval(hours => p_grace_hours);
FOR v_sub IN
SELECT subscription_id, user_id, status, product_id,
current_period_end
FROM public.subscriptions
WHERE status IN ('active', 'trialing', 'grace_period', 'cancelled')
AND current_period_end IS NOT NULL
AND current_period_end < v_cutoff
AND environment = 'production'
ORDER BY current_period_end ASC
LIMIT 100
LOOP
-- Optimistic lock: only update if status hasn't changed
UPDATE public.subscriptions
SET status = 'expired'
WHERE subscription_id = v_sub.subscription_id
AND status = v_sub.status;
INSERT INTO public.subscription_events (
user_id, subscription_id, event_type, product_id,
old_status, new_status, raw_event
) VALUES (
v_sub.user_id, v_sub.subscription_id, 'LAPSED_EXPIRY',
v_sub.product_id, v_sub.status, 'expired',
jsonb_build_object(
'source', 'expire_lapsed_subscriptions',
'period_end', v_sub.current_period_end,
'cutoff', v_cutoff,
'grace_hours', p_grace_hours
)
);
PERFORM public.sync_subscription_tier(v_sub.user_id);
v_count := v_count + 1;
END LOOP;
RETURN jsonb_build_object(
'expired_count', v_count,
'cutoff', v_cutoff,
'grace_hours', p_grace_hours
);
END;
$$;
-- ── admin_set_tier──────────────────────────────────────────────────────
-- Direct tier override for B2B onboarding, support, promos.
-- Creates/updates a promotional subscription row for consistency.
-- V1.0.1 FIX2: product_id uses *_admin suffix which map_product_to_tier()
-- now correctly maps, preventing silent downgrade on next sync.
-- Service-role only.
CREATE OR REPLACE FUNCTION admin_set_tier(
p_user_id UUID,
p_tier TEXT,
p_reason TEXT DEFAULT 'admin_override'
)
RETURNS JSONB
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
v_old_tier TEXT;
v_sub_id UUID;
BEGIN
IF auth.role() IS DISTINCT FROM 'service_role' THEN
RAISE EXCEPTION 'admin_set_tier: service_role only';
END IF;
IF p_tier NOT IN ('free', 'pro', 'pro_plus', 'b2b') THEN
RAISE EXCEPTION 'admin_set_tier: invalid tier "%"', p_tier;
END IF;
SELECT tier INTO v_old_tier
FROM public.user_profiles
WHERE user_id = p_user_id;
IF NOT FOUND THEN
RAISE EXCEPTION 'admin_set_tier: user_id % not found', p_user_id;
END IF;
-- Update tier directly (service_role passes protect_user_tier)
UPDATE public.user_profiles
SET tier = p_tier
WHERE user_id = p_user_id;
-- Create/update promotional subscription for consistency
-- FIX2: product_id = 'baseline_{tier}_admin' is recognized by
-- map_product_to_tier(), so sync won't clobber this.
IF p_tier != 'free' THEN
INSERT INTO public.subscriptions (
user_id, product_id, plan_type, status, store,
environment, auto_renew_enabled
) VALUES (
p_user_id,
'baseline_' || p_tier || '_admin',
'promotional',
'promotional',
'promotional',
'production',
false
)
ON CONFLICT (user_id) DO UPDATE SET
product_id = EXCLUDED.product_id,
plan_type = EXCLUDED.plan_type,
status = EXCLUDED.status,
store = EXCLUDED.store
RETURNING subscription_id INTO v_sub_id;
ELSE
-- Downgrading to free: expire the subscription
UPDATE public.subscriptions
SET status = 'expired'
WHERE user_id = p_user_id
AND status NOT IN ('expired', 'refunded')
RETURNING subscription_id INTO v_sub_id;
END IF;
-- Log event
INSERT INTO public.subscription_events (
user_id, subscription_id, event_type,
old_tier, new_tier, raw_event
) VALUES (
p_user_id, v_sub_id,
CASE WHEN p_tier = 'free'
THEN 'PROMOTIONAL_REVOKE'
ELSE 'ADMIN_OVERRIDE'
END,
v_old_tier, p_tier,
jsonb_build_object(
'source', 'admin_set_tier',
'reason', p_reason,
'timestamp', now()
)
);
RAISE LOG 'A17A admin_set_tier: user=% % → % reason=%',
p_user_id, v_old_tier, p_tier, p_reason;
RETURN jsonb_build_object(
'user_id', p_user_id,
'old_tier', v_old_tier,
'new_tier', p_tier,
'reason', p_reason
);
END;
$$;
-- ########################################################################
-- SECTION 5: ROW-LEVEL SECURITY
-- ########################################################################
ALTER TABLE subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE subscription_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE subscriptions FORCE ROW LEVEL SECURITY;
ALTER TABLE subscription_events FORCE ROW LEVEL SECURITY;
-- subscriptions: user reads own, service_role all, deny anon
DROP POLICY IF EXISTS subscriptions_user_select ON subscriptions;
CREATE POLICY subscriptions_user_select ON subscriptions
FOR SELECT TO authenticated
USING (auth.uid() = user_id);
DROP POLICY IF EXISTS subscriptions_service_all ON subscriptions;
CREATE POLICY subscriptions_service_all ON subscriptions
FOR ALL TO service_role
USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS subscriptions_deny_anon ON subscriptions;
CREATE POLICY subscriptions_deny_anon ON subscriptions
FOR ALL TO anon
USING (false) WITH CHECK (false);
-- subscription_events: user reads own, service_role all, deny anon
DROP POLICY IF EXISTS sub_events_user_select ON subscription_events;
CREATE POLICY sub_events_user_select ON subscription_events
FOR SELECT TO authenticated
USING (auth.uid() = user_id);
DROP POLICY IF EXISTS sub_events_service_all ON subscription_events;
CREATE POLICY sub_events_service_all ON subscription_events
FOR ALL TO service_role
USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS sub_events_deny_anon ON subscription_events;
CREATE POLICY sub_events_deny_anon ON subscription_events
FOR ALL TO anon
USING (false) WITH CHECK (false);
-- ########################################################################
-- SECTION 6: TABLE-LEVEL GRANTS
-- ########################################################################
REVOKE ALL ON TABLE subscriptions FROM PUBLIC;
REVOKE ALL ON TABLE subscriptions FROM anon;
REVOKE ALL ON TABLE subscriptions FROM authenticated;
GRANT SELECT ON TABLE subscriptions TO authenticated;
GRANT ALL ON TABLE subscriptions TO service_role;
REVOKE ALL ON TABLE subscription_events FROM PUBLIC;
REVOKE ALL ON TABLE subscription_events FROM anon;
REVOKE ALL ON TABLE subscription_events FROM authenticated;
GRANT SELECT ON TABLE subscription_events TO authenticated;
GRANT ALL ON TABLE subscription_events TO service_role;
-- ########################################################################
-- SECTION 7: FUNCTION GRANTS
-- ########################################################################
-- map_product_to_tier (service_role only  - internal mapping)
REVOKE ALL ON FUNCTION map_product_to_tier(TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION map_product_to_tier(TEXT) FROM anon;
REVOKE ALL ON FUNCTION map_product_to_tier(TEXT) FROM authenticated;
GRANT EXECUTE ON FUNCTION map_product_to_tier(TEXT) TO service_role;
-- sync_subscription_tier (service_role only)
REVOKE ALL ON FUNCTION sync_subscription_tier(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION sync_subscription_tier(UUID) FROM anon;
REVOKE ALL ON FUNCTION sync_subscription_tier(UUID) FROM authenticated;
GRANT EXECUTE ON FUNCTION sync_subscription_tier(UUID) TO service_role;
-- upsert_subscription (service_role only)
REVOKE ALL ON FUNCTION upsert_subscription(
UUID, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT,
TIMESTAMPTZ, TIMESTAMPTZ, TIMESTAMPTZ,
TEXT, TEXT, TEXT,
TIMESTAMPTZ, TIMESTAMPTZ, TIMESTAMPTZ,
BOOLEAN, JSONB
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION upsert_subscription(
UUID, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT,
TIMESTAMPTZ, TIMESTAMPTZ, TIMESTAMPTZ,
TEXT, TEXT, TEXT,
TIMESTAMPTZ, TIMESTAMPTZ, TIMESTAMPTZ,
BOOLEAN, JSONB
) TO service_role;
-- get_my_subscription (authenticated + service_role)
REVOKE ALL ON FUNCTION get_my_subscription() FROM PUBLIC;
REVOKE ALL ON FUNCTION get_my_subscription() FROM anon;
GRANT EXECUTE ON FUNCTION get_my_subscription() TO authenticated;
GRANT EXECUTE ON FUNCTION get_my_subscription() TO service_role;
-- expire_lapsed_subscriptions (service_role only  - cron)
REVOKE ALL ON FUNCTION expire_lapsed_subscriptions(INTEGER) FROM PUBLIC;
REVOKE ALL ON FUNCTION expire_lapsed_subscriptions(INTEGER) FROM anon;
REVOKE ALL ON FUNCTION expire_lapsed_subscriptions(INTEGER) FROM authenticated;
GRANT EXECUTE ON FUNCTION expire_lapsed_subscriptions(INTEGER) TO service_role;
-- admin_set_tier (service_role only)
REVOKE ALL ON FUNCTION admin_set_tier(UUID, TEXT, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION admin_set_tier(UUID, TEXT, TEXT) FROM anon;
REVOKE ALL ON FUNCTION admin_set_tier(UUID, TEXT, TEXT) FROM authenticated;
GRANT EXECUTE ON FUNCTION admin_set_tier(UUID, TEXT, TEXT) TO service_role;
-- Trigger helpers: no public access
REVOKE ALL ON FUNCTION update_subscription_timestamp() FROM PUBLIC;
REVOKE ALL ON FUNCTION update_subscription_timestamp() FROM anon;
REVOKE ALL ON FUNCTION update_subscription_timestamp() FROM authenticated;
REVOKE ALL ON FUNCTION prevent_sub_event_mutation() FROM PUBLIC;
REVOKE ALL ON FUNCTION prevent_sub_event_mutation() FROM anon;
REVOKE ALL ON FUNCTION prevent_sub_event_mutation() FROM authenticated;
-- ========================================================================
-- END A17A  - V1.0.1
-- ========================================================================
