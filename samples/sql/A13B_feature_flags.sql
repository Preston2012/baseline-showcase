-- ========================================================================
-- BASELINE V1.4 — FEATURE FLAGS TIER GATING
-- A13B — V1.0.1
--
-- FIXES APPLIED (V1.0.0 → V1.0.1 — GPT + Grok audit reconciliation):
-- FIX1: Seed comment corrected — tier entitlements are pre-enabled;
-- global flags remain OFF until launch (was "all disabled") [Grok C1]
-- FIX2: RLS policy renamed tier_features_authenticated_read + comment
-- corrected (was labeled "public read" but is authenticated) [Grok C2+H2]
-- FIX3: FK schema-qualified: public.feature_flags(flag_name) [Grok H1]
-- FIX4: check_feature_access() rewritten as EXISTS with explicit
-- tf.enabled = true AND ff.enabled = true [Grok M1]
-- FIX5: config JSONB object-type CHECK constraint added (consistent
-- with A13A FIX5 preferences pattern) [Grok M2 + GPT]
--
-- PURPOSE:
-- Creates tier_features mapping table and access-check RPCs.
-- Implements the two-layer feature gating model:
-- Layer 1: feature_flags (A1 V8.0) — global kill switches
-- Layer 2: tier_features (this artifact) — per-tier entitlements
-- A feature is accessible only when BOTH layers are enabled.
--
-- DEPENDENCIES:
-- - A1 V8.0 deployed (feature_flags table must exist with seed data)
-- - A13A V1.0.2 deployed (user_profiles.tier, get_my_tier() RPC)
--
-- WHAT THIS DOES NOT DO:
-- - Does not modify feature_flags table (A1 owns it)
-- - Does not create subscriptions (deferred to A18A)
-- - Does not enforce rate limits (deferred to A18C)
-- - Does not create middleware (deferred to A18D)
--
-- TWO-LAYER GATING LOGIC:
-- access = feature_flags.enabled AND tier_features.enabled
-- If global flag is OFF → nobody gets the feature (maintenance/rollout)
-- If global flag is ON → only tiers with tier_features.enabled = true
--
-- RATE LIMITS (Locked Decision #3):
-- free: 100 requests/hr
-- pro: 1,000 requests/hr
-- pro_plus: 5,000 requests/hr
-- b2b: 10,000 requests/hr (custom terms)
-- Stored in tier_features.config for A18C/A18D to consume.
--
-- Safety:
-- CREATE TABLE IF NOT EXISTS — idempotent
-- CREATE OR REPLACE FUNCTION — idempotent
-- DROP TRIGGER IF EXISTS — idempotent
-- INSERT ... ON CONFLICT DO NOTHING — idempotent seed data
-- ========================================================================
-- ========================================================================
-- TIER FEATURES MAPPING TABLE
-- ========================================================================
CREATE TABLE IF NOT EXISTS tier_features (
-- Composite PK: one row per tier+feature combination
tier TEXT NOT NULL CHECK (tier IN ('free', 'pro', 'pro_plus', 'b2b')),
-- V1.0.1 FIX3: Schema-qualified FK reference
flag_name TEXT NOT NULL REFERENCES public.feature_flags(flag_name) ON DELETE
CASCADE,
-- Is this feature enabled for this tier?
enabled BOOLEAN NOT NULL DEFAULT false,
-- Tier-specific configuration (rate limits, quotas, etc.)
-- Example: { "max_results": 5, "max_annotations": 100 }
config JSONB NOT NULL DEFAULT '{}'::jsonb,
-- Timestamps
created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
PRIMARY KEY (tier, flag_name),
-- V1.0.1 FIX5: Ensure config is always a JSON object (not array/string)
CONSTRAINT tier_features_config_is_object CHECK (jsonb_typeof(config) = 'object')
);
-- ── INDEXES──────────────────────────────────────────────────────────────────
-- Lookup by flag_name (e.g., "which tiers have ENABLE_RECEIPT?")
CREATE INDEX IF NOT EXISTS idx_tier_features_flag
ON tier_features(flag_name);
-- ── AUTO-UPDATE updated_at───────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION update_tier_features_timestamp()
RETURNS TRIGGER AS $$
BEGIN
NEW.updated_at := now();
RETURN NEW;
END;
$$ LANGUAGE plpgsql;
DROP TRIGGER IF EXISTS trigger_tier_features_timestamp ON tier_features;
CREATE TRIGGER trigger_tier_features_timestamp
BEFORE UPDATE ON tier_features
FOR EACH ROW
EXECUTE FUNCTION update_tier_features_timestamp();
-- ========================================================================
-- ROW-LEVEL SECURITY
-- ========================================================================
ALTER TABLE tier_features ENABLE ROW LEVEL SECURITY;
-- V1.0.1 FIX2: Renamed from "public_read" — policy is authenticated, not public.
-- Authenticated read: clients need to know what tiers unlock (for UI upgrade prompts)
-- No PII exposed — just tier+feature mappings.
DROP POLICY IF EXISTS tier_features_public_read ON tier_features;
DROP POLICY IF EXISTS tier_features_authenticated_read ON tier_features;
CREATE POLICY tier_features_authenticated_read ON tier_features
FOR SELECT TO authenticated
USING (true);
-- Service role: full access (admin config changes)
DROP POLICY IF EXISTS tier_features_service_all ON tier_features;
CREATE POLICY tier_features_service_all ON tier_features
FOR ALL TO service_role
USING (true)
WITH CHECK (true);
-- No INSERT/UPDATE/DELETE for authenticated — service_role only
-- ========================================================================
-- TABLE-LEVEL GRANTS
-- ========================================================================
REVOKE ALL ON TABLE tier_features FROM PUBLIC;
REVOKE ALL ON TABLE tier_features FROM anon;
REVOKE ALL ON TABLE tier_features FROM authenticated;
-- Authenticated: read-only (feature discovery for UI)
GRANT SELECT ON TABLE tier_features TO authenticated;
-- Service role: full access
GRANT ALL ON TABLE tier_features TO service_role;
-- ========================================================================
-- RPC: Check if current user has access to a feature
-- ========================================================================
-- Combines both layers:
-- 1. Global flag must be enabled (feature_flags.enabled = true)
-- 2. User's tier must have access (tier_features.enabled = true)
-- Returns false if either layer blocks, or if flag/tier doesn't exist.
--
-- V1.0.1 FIX4: Rewritten as EXISTS with explicit tf.enabled = true
-- for clarity and future-proofing. No ambiguity between NULL and false.
--
-- SECURITY INVOKER: Runs as calling user. RLS on tier_features allows
-- authenticated SELECT. get_my_tier() handles user context.
-- ========================================================================
CREATE OR REPLACE FUNCTION check_feature_access(p_flag_name TEXT)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $$
SELECT COALESCE(
EXISTS (
SELECT 1
FROM public.tier_features tf
INNER JOIN public.feature_flags ff ON ff.flag_name = tf.flag_name
WHERE tf.flag_name = p_flag_name
AND tf.tier = public.get_my_tier()
AND tf.enabled = true
AND ff.enabled = true
),
false
);
$$;
-- Grant to authenticated (primary consumer) + service_role (entitlement checks)
REVOKE ALL ON FUNCTION check_feature_access(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION check_feature_access(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION check_feature_access(TEXT) TO service_role;
-- ========================================================================
-- RPC: Get feature config for current user's tier
-- ========================================================================
-- Returns the config JSONB for a specific feature+tier, or NULL if no access.
-- Used by A18C/A18D to read rate limits, quotas, etc.
-- ========================================================================
CREATE OR REPLACE FUNCTION get_feature_config(p_flag_name TEXT)
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $$
SELECT tf.config
FROM public.tier_features tf
INNER JOIN public.feature_flags ff ON ff.flag_name = tf.flag_name
WHERE tf.flag_name = p_flag_name
AND tf.tier = public.get_my_tier()
AND ff.enabled = true
AND tf.enabled = true;
$$;
-- Grant to authenticated + service_role
REVOKE ALL ON FUNCTION get_feature_config(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION get_feature_config(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION get_feature_config(TEXT) TO service_role;
-- ========================================================================
-- SEED DATA
-- ========================================================================
-- Maps all 7 features × 4 tiers = 28 rows.
-- Rate limits and quotas stored in config (Locked Decision #3).
--
-- V1.0.1 FIX1: Tier entitlements may be pre-enabled here; global flags
-- in A1 remain OFF until launch. The two-layer model means a feature is
-- only accessible when BOTH feature_flags.enabled = true AND
-- tier_features.enabled = true. Pre-enabling tier entitlements lets us
-- configure access before flipping the global switch.
-- ========================================================================
-- ── ENABLE_TOPIC_TAGGING─────────────────────────────────────────────────────
INSERT INTO tier_features (tier, flag_name, enabled, config) VALUES
('free', 'ENABLE_TOPIC_TAGGING', true, '{}'),
('pro', 'ENABLE_TOPIC_TAGGING', true, '{}'),
('pro_plus', 'ENABLE_TOPIC_TAGGING', true, '{}'),
('b2b', 'ENABLE_TOPIC_TAGGING', true, '{}')
ON CONFLICT (tier, flag_name) DO NOTHING;
-- ── ENABLE_RECEIPT───────────────────────────────────────────────────────────
INSERT INTO tier_features (tier, flag_name, enabled, config) VALUES
('free', 'ENABLE_RECEIPT', true, '{"max_results": 3}'),
('pro', 'ENABLE_RECEIPT', true, '{"max_results": 5}'),
('pro_plus', 'ENABLE_RECEIPT', true, '{"max_results": 5}'),
('b2b', 'ENABLE_RECEIPT', true, '{"max_results": 5}')
ON CONFLICT (tier, flag_name) DO NOTHING;
-- ── ENABLE_FRAMING_RADAR─────────────────────────────────────────────────────
INSERT INTO tier_features (tier, flag_name, enabled, config) VALUES
('free', 'ENABLE_FRAMING_RADAR', false, '{}'),
('pro', 'ENABLE_FRAMING_RADAR', true, '{}'),
('pro_plus', 'ENABLE_FRAMING_RADAR', true, '{}'),
('b2b', 'ENABLE_FRAMING_RADAR', true, '{}')
ON CONFLICT (tier, flag_name) DO NOTHING;
-- ── ENABLE_WAR_ROOM─────────────────────────────────────────────────────────
INSERT INTO tier_features (tier, flag_name, enabled, config) VALUES
('free', 'ENABLE_WAR_ROOM', false, '{}'),
('pro', 'ENABLE_WAR_ROOM', true, '{}'),
('pro_plus', 'ENABLE_WAR_ROOM', true, '{}'),
('b2b', 'ENABLE_WAR_ROOM', true, '{}')
ON CONFLICT (tier, flag_name) DO NOTHING;
-- ── ENABLE_VOTE_TRACKING─────────────────────────────────────────────────────
INSERT INTO tier_features (tier, flag_name, enabled, config) VALUES
('free', 'ENABLE_VOTE_TRACKING', false, '{}'),
('pro', 'ENABLE_VOTE_TRACKING', true, '{}'),
('pro_plus', 'ENABLE_VOTE_TRACKING', true, '{}'),
('b2b', 'ENABLE_VOTE_TRACKING', true, '{}')
ON CONFLICT (tier, flag_name) DO NOTHING;
-- ── ENABLE_ANNOTATIONS───────────────────────────────────────────────────────
INSERT INTO tier_features (tier, flag_name, enabled, config) VALUES
('free', 'ENABLE_ANNOTATIONS', false, '{"max_annotations": 5}'),
('pro', 'ENABLE_ANNOTATIONS', true, '{"max_annotations": 100}'),
('pro_plus', 'ENABLE_ANNOTATIONS', true, '{"max_annotations": 500}'),
('b2b', 'ENABLE_ANNOTATIONS', true, '{"max_annotations": 1000}')
ON CONFLICT (tier, flag_name) DO NOTHING;
-- ── ENABLE_HISTORICAL_TRENDS─────────────────────────────────────────────────
INSERT INTO tier_features (tier, flag_name, enabled, config) VALUES
('free', 'ENABLE_HISTORICAL_TRENDS', false, '{}'),
('pro', 'ENABLE_HISTORICAL_TRENDS', true, '{}'),
('pro_plus', 'ENABLE_HISTORICAL_TRENDS', true, '{}'),
('b2b', 'ENABLE_HISTORICAL_TRENDS', true, '{}')
ON CONFLICT (tier, flag_name) DO NOTHING;
-- ========================================================================
-- FUNCTION GRANTS (trigger function — no public access)
-- ========================================================================
REVOKE ALL ON FUNCTION update_tier_features_timestamp() FROM PUBLIC;
-- ========================================================================
-- END A13B — V1.0.1
-- ========================================================================
