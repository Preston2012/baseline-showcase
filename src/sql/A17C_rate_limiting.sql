-- ========================================================================
-- BASELINE V1.4  - RATE LIMITING SQL PRIMITIVES
-- A17C  - V1.0.1
--
-- FIXES APPLIED (V1.0.0 → V1.0.1  - dual audit reconciliation):
-- FIX1: Added auth.role() = 'service_role' guard to check_rate_limit()
-- and record_rate_limit_hit(). Defense-in-depth: grants already
-- restrict to service_role, but explicit check prevents future
-- accidental grant from becoming a data leak.
-- [Audit 2 Critical Blocker #1]
-- FIX2: Fixed reset_at computation. Now always based on oldest entry
-- in the sliding window (MIN(created_at) + 1 hour). When no
-- entries exist, reset_at = now() (not now+1h). Prevents
-- misleading X-RateLimit-Reset headers.
-- [Audit 2 Critical Blocker #2]
-- FIX3: Added endpoint constraints on table  - max 64 chars, lowercase
-- alphanumeric + hyphens only. Prevents namespace injection and
-- cardinality abuse. A17D must normalize routes to canonical keys.
-- [Audit 2 High #4, Audit 1 Security]
-- FIX4: Switched sliding window boundary from > to >= for consistency.
-- [Audit 2 Medium #5]
-- FIX5: record_rate_limit_hit() now validates identity explicitly with
-- clear error message (not just opaque CHECK constraint failure).
-- [Audit 2 Medium #7]
-- FIX6: check_rate_limit() validates endpoint format before querying.
-- [Audit 1 Security  - endpoint TEXT no val]
--
-- PURPOSE:
-- Database layer for request rate limiting. Provides a sliding-window
-- counter table, check + record RPCs, and automatic cleanup.
-- Consumed by A17D (entitlement middleware Edge Function).
--
-- RATE LIMITS (Locked Decision #3  - from A13B):
-- free: 100 requests / hour
-- pro: 1,000 requests / hour
-- pro_plus: 5,000 requests / hour
-- b2b: 10,000 requests / hour
--
-- DESIGN DECISIONS:
-- 1. Sliding window (1-hour lookback)  - more accurate than fixed windows,
-- no sudden reset bursts. Trade-off: COUNT query per check.
-- 2. Dual key: user_id (authenticated) OR client_ip (anonymous/public).
-- Authenticated users rate-limited by user_id (tier-aware).
-- Anonymous requests rate-limited by IP (always free-tier cap).
-- 3. Endpoint-scoped: each endpoint has its own counter namespace.
-- e.g., 'get-receipt' and 'get-feed' have separate quotas.
-- 4. check_rate_limit returns remaining + reset info for response headers.
-- 5. Cleanup via expire_rate_limit_entries()  - called by cron.
-- 6. Hardcoded tier→limit map for MVP performance (no DB hit per check).
-- Migration path: swap get_tier_rate_limit() to read from
-- tier_features.config->>'rate_limit' when per-endpoint or dynamic
-- limits are needed. Both A13B seeds and this function update together.
--
-- DEPENDENCIES:
-- - A13A V1.0.2 deployed (user_profiles, get_my_tier())
-- - A13B V1.0.1 deployed (tier_features  - rate limit values hardcoded
-- here for MVP, config-driven migration documented above)
-- - Supabase Auth (auth.uid(), auth.role())
--
-- DOWNSTREAM CONSUMERS:
-- - A17D (entitlement middleware) → calls check_rate_limit(),
-- record_rate_limit_hit(). Must normalize endpoint to canonical keys
-- matching ^[a-z0-9-]+$ (e.g., 'get-receipt', 'get-feed').
-- - Cron job → calls expire_rate_limit_entries()
--
-- WHAT THIS DOES NOT DO:
-- - Does not create the middleware Edge Function (A17D does that)
-- - Does not modify tier_features config (A13B owns rate limit config)
-- - Does not handle DDoS (use Cloudflare/CDN for L7 protection)
-- - Does not implement token bucket (sliding window sufficient for MVP)
--
-- ========================================================================
-- ########################################################################
-- SECTION 1: RATE LIMIT ENTRIES TABLE
-- ########################################################################
-- One row per request. Lightweight: only fields needed for counting.
-- Rows older than 2 hours are cleaned by expire_rate_limit_entries().
-- Partitioning deferred (premature for MVP volume).
-- ########################################################################
CREATE TABLE IF NOT EXISTS rate_limit_entries (
entry_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
-- Authenticated user (NULL for anonymous)
user_id UUID,
-- Anonymous IP (NULL for authenticated  - user_id takes precedence)
client_ip INET,
-- Endpoint namespace (e.g., 'get-receipt', 'get-feed', 'annotations')
-- FIX3: Constrained to prevent namespace injection / cardinality abuse
endpoint TEXT NOT NULL
CONSTRAINT endpoint_length CHECK (char_length(endpoint) <= 64)
CONSTRAINT endpoint_format CHECK (endpoint ~ '^[a-z0-9-]+$'),
-- When the request occurred
created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
-- At least one identifier required
CONSTRAINT rate_limit_has_identity CHECK (
user_id IS NOT NULL OR client_ip IS NOT NULL
)
);
-- Primary query: count requests in sliding window by user
CREATE INDEX IF NOT EXISTS idx_rate_limit_user_endpoint
ON rate_limit_entries (user_id, endpoint, created_at DESC)
WHERE user_id IS NOT NULL;
-- Primary query: count requests in sliding window by IP
CREATE INDEX IF NOT EXISTS idx_rate_limit_ip_endpoint
ON rate_limit_entries (client_ip, endpoint, created_at DESC)
WHERE client_ip IS NOT NULL;
-- Cleanup: delete old entries efficiently
CREATE INDEX IF NOT EXISTS idx_rate_limit_created
ON rate_limit_entries (created_at);
-- ########################################################################
-- SECTION 2: TIER RATE LIMIT LOOKUP
-- ########################################################################
-- Pure function: tier → max requests per hour.
-- Matches A13B Locked Decision #3. Hardcoded for performance (no DB hit).
--
-- MIGRATION PATH: When per-endpoint or dynamic limits are needed, swap
-- this to: SELECT (config->>'rate_limit')::INTEGER FROM tier_features
-- WHERE tier = p_tier AND flag_name = p_endpoint_flag
-- Both A13B seeds and this function must update together.
-- ########################################################################
CREATE OR REPLACE FUNCTION get_tier_rate_limit(p_tier TEXT)
RETURNS INTEGER
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
SET search_path = pg_catalog, public
AS $$
SELECT CASE p_tier
WHEN 'free' THEN 100
WHEN 'pro' THEN 1000
WHEN 'pro_plus' THEN 5000
WHEN 'b2b' THEN 10000
ELSE 100 -- unknown tier → free cap (deny-by-default)
END;
$$;
-- ########################################################################
-- SECTION 3: CHECK RATE LIMIT
-- ########################################################################
-- Returns a JSONB object with: allowed, remaining, limit, reset_at, used.
-- Does NOT record the request (caller must also call record_rate_limit_hit
-- if proceeding). This separation lets middleware check-then-act.
--
-- For authenticated users: looks up tier via p_tier param (required for
-- service_role calls  - centralizes tier resolution in middleware/A17D).
-- For anonymous: uses free-tier cap (100/hr).
--
-- FIX1: service_role guard (defense-in-depth).
-- FIX2: reset_at based on oldest entry in window, not arbitrary now+1h.
-- FIX4: >= boundary for sliding window consistency.
-- FIX6: endpoint format validated before querying.
-- ########################################################################
CREATE OR REPLACE FUNCTION check_rate_limit(
p_endpoint TEXT,
p_user_id UUID DEFAULT NULL,
p_client_ip INET DEFAULT NULL,
p_tier TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
v_tier TEXT;
v_limit INTEGER;
v_used INTEGER;
v_remaining INTEGER;
v_window_start TIMESTAMPTZ;
v_reset_at TIMESTAMPTZ;
v_oldest TIMESTAMPTZ;
BEGIN
-- FIX1: Defense-in-depth role guard
IF auth.role() IS DISTINCT FROM 'service_role' THEN
RAISE EXCEPTION 'check_rate_limit: service_role only';
END IF;
-- Validate: at least one identifier
IF p_user_id IS NULL AND p_client_ip IS NULL THEN
RAISE EXCEPTION 'check_rate_limit: user_id or client_ip required';
END IF;
IF COALESCE(p_endpoint, '') = '' THEN
RAISE EXCEPTION 'check_rate_limit: endpoint required';
END IF;
-- FIX6: Validate endpoint format (mirrors table CHECK constraint)
IF p_endpoint !~ '^[a-z0-9-]+$' OR char_length(p_endpoint) > 64 THEN
RAISE EXCEPTION 'check_rate_limit: invalid endpoint format';
END IF;
-- Determine tier and limit
IF p_user_id IS NOT NULL THEN
-- Authenticated: use provided tier or look up from user_profiles
v_tier := COALESCE(p_tier, (
SELECT tier FROM public.user_profiles WHERE user_id = p_user_id
), 'free');
ELSE
-- Anonymous: always free-tier cap
v_tier := 'free';
END IF;
v_limit := public.get_tier_rate_limit(v_tier);
v_window_start := now() - interval '1 hour';
-- Count requests in sliding window (FIX4: >= boundary)
IF p_user_id IS NOT NULL THEN
SELECT COUNT(*)::INTEGER, MIN(created_at)
INTO v_used, v_oldest
FROM public.rate_limit_entries
WHERE user_id = p_user_id
AND endpoint = p_endpoint
AND created_at >= v_window_start;
ELSE
SELECT COUNT(*)::INTEGER, MIN(created_at)
INTO v_used, v_oldest
FROM public.rate_limit_entries
WHERE client_ip = p_client_ip
AND endpoint = p_endpoint
AND created_at >= v_window_start;
END IF;
v_remaining := GREATEST(0, v_limit - v_used);
-- FIX2: reset_at always based on oldest entry in window
-- When oldest entry expires (oldest + 1h), one slot opens up.
-- If no entries, reset_at = now (nothing to wait for).
IF v_used > 0 THEN
v_reset_at := v_oldest + interval '1 hour';
ELSE
v_reset_at := now();
END IF;
RETURN jsonb_build_object(
'allowed', v_remaining > 0,
'remaining', v_remaining,
'limit', v_limit,
'used', v_used,
'reset_at', v_reset_at,
'tier', v_tier,
'endpoint', p_endpoint
);
END;
$$;
-- ########################################################################
-- SECTION 4: RECORD RATE LIMIT HIT
-- ########################################################################
-- Inserts a single entry. Called by A17D AFTER check passes.
-- FIX1: service_role guard. FIX5: explicit identity validation.
-- ########################################################################
CREATE OR REPLACE FUNCTION record_rate_limit_hit(
p_endpoint TEXT,
p_user_id UUID DEFAULT NULL,
p_client_ip INET DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
-- FIX1: Defense-in-depth role guard
IF auth.role() IS DISTINCT FROM 'service_role' THEN
RAISE EXCEPTION 'record_rate_limit_hit: service_role only';
END IF;
-- FIX5: Explicit identity validation (clearer than opaque CHECK failure)
IF p_user_id IS NULL AND p_client_ip IS NULL THEN
RAISE EXCEPTION 'record_rate_limit_hit: user_id or client_ip required';
END IF;
IF COALESCE(p_endpoint, '') = '' THEN
RAISE EXCEPTION 'record_rate_limit_hit: endpoint required';
END IF;
INSERT INTO public.rate_limit_entries (user_id, client_ip, endpoint)
VALUES (p_user_id, p_client_ip, p_endpoint);
END;
$$;
-- ########################################################################
-- SECTION 5: CLEANUP OLD ENTRIES
-- ########################################################################
-- Deletes entries older than p_hours (default 2). Called by cron.
-- Batch-limited to prevent long-running transactions.
-- Service-role only.
-- ########################################################################
CREATE OR REPLACE FUNCTION expire_rate_limit_entries(
p_hours INTEGER DEFAULT 2
)
RETURNS JSONB
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
v_deleted INTEGER;
v_cutoff TIMESTAMPTZ;
BEGIN
IF auth.role() IS DISTINCT FROM 'service_role' THEN
RAISE EXCEPTION 'expire_rate_limit_entries: service_role only';
END IF;
IF p_hours < 1 OR p_hours > 168 THEN
RAISE EXCEPTION 'p_hours must be 1-168';
END IF;
v_cutoff := now() - make_interval(hours => p_hours);
-- Batch delete with LIMIT to avoid lock contention
WITH deleted AS (
DELETE FROM public.rate_limit_entries
WHERE entry_id IN (
SELECT entry_id FROM public.rate_limit_entries
WHERE created_at < v_cutoff
ORDER BY created_at ASC
LIMIT 10000
)
RETURNING entry_id
)
SELECT COUNT(*) INTO v_deleted FROM deleted;
RETURN jsonb_build_object(
'deleted_count', v_deleted,
'cutoff', v_cutoff,
'batch_limit', 10000
);
END;
$$;
-- ########################################################################
-- SECTION 6: ROW-LEVEL SECURITY
-- ########################################################################
-- rate_limit_entries is internal infrastructure. No direct user access.
-- All interaction through RPCs (SECURITY DEFINER).
ALTER TABLE rate_limit_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE rate_limit_entries FORCE ROW LEVEL SECURITY;
-- Service role: full access (RPCs run as service_role via SECURITY DEFINER)
DROP POLICY IF EXISTS rate_limit_service_all ON rate_limit_entries;
CREATE POLICY rate_limit_service_all ON rate_limit_entries
FOR ALL TO service_role
USING (true) WITH CHECK (true);
-- Deny everyone else
DROP POLICY IF EXISTS rate_limit_deny_anon ON rate_limit_entries;
CREATE POLICY rate_limit_deny_anon ON rate_limit_entries
FOR ALL TO anon
USING (false) WITH CHECK (false);
DROP POLICY IF EXISTS rate_limit_deny_auth ON rate_limit_entries;
CREATE POLICY rate_limit_deny_auth ON rate_limit_entries
FOR ALL TO authenticated
USING (false) WITH CHECK (false);
-- ########################################################################
-- SECTION 7: TABLE-LEVEL GRANTS
-- ########################################################################
REVOKE ALL ON TABLE rate_limit_entries FROM PUBLIC;
REVOKE ALL ON TABLE rate_limit_entries FROM anon;
REVOKE ALL ON TABLE rate_limit_entries FROM authenticated;
GRANT ALL ON TABLE rate_limit_entries TO service_role;
-- ########################################################################
-- SECTION 8: FUNCTION GRANTS
-- ########################################################################
-- get_tier_rate_limit (authenticated can read for UI display + service_role)
REVOKE ALL ON FUNCTION get_tier_rate_limit(TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION get_tier_rate_limit(TEXT) FROM anon;
GRANT EXECUTE ON FUNCTION get_tier_rate_limit(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION get_tier_rate_limit(TEXT) TO service_role;
-- check_rate_limit (service_role only  - called by middleware)
REVOKE ALL ON FUNCTION check_rate_limit(TEXT, UUID, INET, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION check_rate_limit(TEXT, UUID, INET, TEXT) FROM anon;
REVOKE ALL ON FUNCTION check_rate_limit(TEXT, UUID, INET, TEXT) FROM
authenticated;
GRANT EXECUTE ON FUNCTION check_rate_limit(TEXT, UUID, INET, TEXT) TO
service_role;
-- record_rate_limit_hit (service_role only)
REVOKE ALL ON FUNCTION record_rate_limit_hit(TEXT, UUID, INET) FROM PUBLIC;
REVOKE ALL ON FUNCTION record_rate_limit_hit(TEXT, UUID, INET) FROM anon;
REVOKE ALL ON FUNCTION record_rate_limit_hit(TEXT, UUID, INET) FROM authenticated;
GRANT EXECUTE ON FUNCTION record_rate_limit_hit(TEXT, UUID, INET) TO service_role;
-- expire_rate_limit_entries (service_role only  - cron)
REVOKE ALL ON FUNCTION expire_rate_limit_entries(INTEGER) FROM PUBLIC;
REVOKE ALL ON FUNCTION expire_rate_limit_entries(INTEGER) FROM anon;
REVOKE ALL ON FUNCTION expire_rate_limit_entries(INTEGER) FROM authenticated;
GRANT EXECUTE ON FUNCTION expire_rate_limit_entries(INTEGER) TO service_role;
-- ========================================================================
-- END A17C  - V1.0.1
-- ========================================================================
