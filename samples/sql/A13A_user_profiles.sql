-- ========================================================================
-- BASELINE V1.4 — USER PROFILES + AUTH FOUNDATION
-- A13A — V1.0.2
--
-- FIXES APPLIED (V1.0.0 → V1.0.1 — GPT + Grok audit reconciliation):
-- FIX1: handle_new_user null-safe for OAuth/phone auth (no email)
-- Added NULLIF+trim on metadata, 'user_' || id as final fallback [GPT]
-- FIX2: handle_new_user exception handler uses RAISE LOG (not pipeline_events)
-- Avoids A11A stage enum dependency. Signup never blocked. [GPT+Grok]
-- FIX3: get_my_tier() returns 'free' via COALESCE (not NULL) [GPT]
-- FIX4: protect_user_tier: RAISE EXCEPTION on non-service tier change
-- (was silent pin — caused UX confusion) [Grok C3]
-- FIX5: preferences JSONB must be object type CHECK constraint [GPT]
-- FIX6: Schema-qualify all tables in SECURITY DEFINER functions [Grok C2]
-- FIX7: Column-level UPDATE grants (authenticated can only change
-- display_name, avatar_url, preferences — not tier/timestamps) [Grok H1]
-- FIX8: Explicit REVOKE/GRANT on table (don't rely on Supabase defaults) [Grok H5]
-- FIX9: Tier change audit via RAISE LOG (not pipeline_events) [Grok C1]
--
-- FIXES APPLIED (V1.0.1 → V1.0.2 — Final audit reconciliation):
-- FIX10: REVOKE get_my_tier() FROM PUBLIC (Postgres default execute hole) [Grok C1]
-- FIX11: REVOKE ALL ON TABLE user_profiles FROM PUBLIC [Grok H1]
-- FIX12: SECURITY DEFINER search_path = pg_catalog, public [Grok C2]
-- FIX13: GRANT EXECUTE get_my_tier() TO service_role [GPT]
-- FIX14: Log unauthorized tier change attempts before RAISE EXCEPTION [GPT]
--
-- PURPOSE:
-- Creates user_profiles table linked to Supabase auth.users.
-- Foundation for: annotations (A16B), monetization (A18A-D),
-- feature flag tier gating, and personalized UI.
--
-- DEPENDENCIES:
-- - Supabase Auth enabled (auth.users table must exist)
-- - A1 V8.0 deployed (annotations.user_id references auth.uid())
--
-- WHAT THIS DOES NOT DO:
-- - Does not create auth.users (Supabase manages this)
-- - Does not configure OAuth providers (Supabase Dashboard task)
-- - Does not create tier_features (deferred to A18A)
-- - Does not create subscriptions (deferred to A18A)
-- - Does not write to pipeline_events (avoids A11A stage enum coupling)
--
-- SUPABASE AUTH CONFIGURATION (Dashboard settings — not SQL):
-- 1. Enable Email/Password auth (Settings → Auth → Providers)
-- 2. Enable Google OAuth (optional, recommended for mobile)
-- 3. Enable Apple OAuth (required for iOS App Store)
-- 4. Set JWT expiry to 3600s (1 hour)
-- 5. Enable email confirmation (Settings → Auth → Email)
-- 6. Set site URL and redirect URLs for your app domain
-- 7. Disable signup if you want invite-only during beta
--
-- TIER DEFINITIONS:
-- 'free' — default, ad-supported, limited features
-- 'pro' — paid, no ads, full features
-- 'pro_plus' — paid, no ads, full features + priority
-- 'b2b' — enterprise, custom terms
--
-- Safety:
-- CREATE TABLE IF NOT EXISTS — idempotent
-- CREATE OR REPLACE FUNCTION — idempotent
-- DROP TRIGGER IF EXISTS — idempotent
-- ========================================================================
-- ========================================================================
-- USER PROFILES TABLE
-- ========================================================================
CREATE TABLE IF NOT EXISTS user_profiles (
-- Primary key matches auth.users.id exactly
user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
-- Display info (user-editable via column-level grants)
display_name TEXT CHECK (char_length(display_name) <= 100),
avatar_url TEXT CHECK (char_length(avatar_url) <= 500),
-- Tier (managed by service_role via A18B RevenueCat webhook)
-- Users cannot change tier — protected by trigger + column-level grants
tier TEXT NOT NULL DEFAULT 'free' CHECK (tier IN ('free', 'pro', 'pro_plus', 'b2b')),
-- Preferences (user-editable, flexible JSONB)
-- Example: { "theme": "dark", "default_figure": "uuid", "notifications": true }
preferences JSONB NOT NULL DEFAULT '{}'::jsonb,
-- Timestamps
created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
-- Constraints
CONSTRAINT preferences_size_limit CHECK (pg_column_size(preferences) <= 16384),
-- V1.0.1 FIX5: Ensure preferences is always a JSON object (not array/string)
CONSTRAINT preferences_is_object CHECK (jsonb_typeof(preferences) = 'object')
);
-- ── INDEXES──────────────────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_user_profiles_tier
ON user_profiles(tier);
CREATE INDEX IF NOT EXISTS idx_user_profiles_created
ON user_profiles(created_at DESC);
-- ── AUTO-UPDATE updated_at───────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION update_user_profile_timestamp()
RETURNS TRIGGER AS $$
BEGIN
NEW.updated_at := now();
RETURN NEW;
END;
$$ LANGUAGE plpgsql;
DROP TRIGGER IF EXISTS trigger_user_profile_timestamp ON user_profiles;
CREATE TRIGGER trigger_user_profile_timestamp
BEFORE UPDATE ON user_profiles
FOR EACH ROW
EXECUTE FUNCTION update_user_profile_timestamp();
-- ========================================================================
-- AUTO-CREATE PROFILE ON SIGNUP
-- ========================================================================
-- Trigger fires AFTER INSERT on auth.users (managed by Supabase).
-- Creates a user_profiles row with defaults. Tier starts at 'free'.
--
-- SECURITY: This function runs as SECURITY DEFINER because it needs to
-- insert into user_profiles during the auth signup flow, where the user's
-- RLS context is not yet fully established.
--
-- V1.0.1 FIX1: Null-safe display_name for OAuth/phone auth
-- V1.0.1 FIX2: Exception handler uses RAISE LOG (not pipeline_events)
-- V1.0.1 FIX6: All table references schema-qualified
-- V1.0.2 FIX12: search_path = pg_catalog, public (hardened SECURITY DEFINER)
-- ========================================================================
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
v_display_name TEXT;
BEGIN
-- V1.0.1 FIX1: Null-safe display_name extraction
-- Handles OAuth (no email), phone auth, and missing metadata
v_display_name := COALESCE(
NULLIF(trim(NEW.raw_user_meta_data->>'display_name'), ''),
NULLIF(trim(NEW.raw_user_meta_data->>'full_name'), ''),
NULLIF(trim(NEW.raw_user_meta_data->>'name'), ''),
CASE WHEN NEW.email IS NOT NULL AND NEW.email <> ''
THEN split_part(NEW.email, '@', 1)
ELSE NULL
END,
'user_' || left(NEW.id::text, 8)
);
-- V1.0.1 FIX6: Schema-qualified table reference
INSERT INTO public.user_profiles (user_id, display_name)
VALUES (NEW.id, v_display_name)
ON CONFLICT (user_id) DO NOTHING;
RETURN NEW;
EXCEPTION WHEN OTHERS THEN
-- V1.0.1 FIX2: Log failure via RAISE LOG (visible in Postgres server logs)
-- Does NOT write to pipeline_events (avoids A11A stage enum dependency)
-- Profile creation failure must not block auth signup
RAISE LOG 'A13A handle_new_user FAILED for user_id=%, error=%', NEW.id, SQLERRM;
RETURN NEW;
END;
$$;
-- Trigger on auth.users (Supabase-managed table)
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
AFTER INSERT ON auth.users
FOR EACH ROW
EXECUTE FUNCTION handle_new_user();
-- ========================================================================
-- ROW-LEVEL SECURITY
-- ========================================================================
ALTER TABLE user_profiles ENABLE ROW LEVEL SECURITY;
-- ── Users can read their own profile─────────────────────────────────────────
DROP POLICY IF EXISTS profiles_user_select ON user_profiles;
CREATE POLICY profiles_user_select ON user_profiles
FOR SELECT TO authenticated
USING (auth.uid() = user_id);
-- ── Users can update their own profile (column-level grants restrict WHICH columns)
DROP POLICY IF EXISTS profiles_user_update ON user_profiles;
CREATE POLICY profiles_user_update ON user_profiles
FOR UPDATE TO authenticated
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);
-- ── No INSERT policy for authenticated — profiles are auto-created by trigger
-- ── No DELETE policy for authenticated — users cannot delete their profile
-- ── Service role has full access (for admin, webhooks, tier updates) ─────────
DROP POLICY IF EXISTS profiles_service_all ON user_profiles;
CREATE POLICY profiles_service_all ON user_profiles
FOR ALL TO service_role
USING (true)
WITH CHECK (true);
-- ========================================================================
-- TABLE-LEVEL GRANTS
-- ========================================================================
-- V1.0.1 FIX7 + FIX8: Explicit grants, don't rely on Supabase defaults.
-- Column-level UPDATE restricts authenticated to safe fields only.
-- Even with RLS, this prevents tier/timestamp manipulation.
-- V1.0.2 FIX11: Explicit REVOKE FROM PUBLIC (defense-in-depth).
-- ========================================================================
REVOKE ALL ON TABLE user_profiles FROM PUBLIC;
REVOKE ALL ON TABLE user_profiles FROM anon;
REVOKE ALL ON TABLE user_profiles FROM authenticated;
-- Authenticated: read own profile + update only safe columns
GRANT SELECT ON TABLE user_profiles TO authenticated;
GRANT UPDATE (display_name, avatar_url, preferences) ON TABLE user_profiles TO
authenticated;
-- Service role: full access (admin, webhooks, tier updates)
GRANT ALL ON TABLE user_profiles TO service_role;
-- ========================================================================
-- TIER PROTECTION TRIGGER
-- ========================================================================
-- V1.0.1 FIX4: RAISE EXCEPTION instead of silent pin (Grok C3).
-- Non-service tier change attempts fail explicitly — no silent revert.
-- V1.0.1 FIX6: Schema-qualified references.
-- V1.0.1 FIX9: Tier change audit via RAISE LOG (not pipeline_events).
-- V1.0.2 FIX12: search_path = pg_catalog, public (hardened SECURITY DEFINER).
-- V1.0.2 FIX14: Log unauthorized tier change attempts for audit trail.
-- ========================================================================
CREATE OR REPLACE FUNCTION protect_user_tier()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
-- Service role can change anything
IF auth.role() = 'service_role' THEN
-- V1.0.1 FIX9: Log tier changes for audit trail
IF NEW.tier IS DISTINCT FROM OLD.tier THEN
RAISE LOG 'A13A tier_change: user_id=%, old=%, new=%',
NEW.user_id, OLD.tier, NEW.tier;
END IF;
RETURN NEW;
END IF;
-- V1.0.2 FIX14: Log unauthorized tier change attempts before rejecting
IF NEW.tier IS DISTINCT FROM OLD.tier THEN
RAISE LOG 'A13A UNAUTHORIZED tier_change_attempt: user_id=%, attempted=%,
current=%',
NEW.user_id, NEW.tier, OLD.tier;
-- V1.0.1 FIX4: Explicit failure instead of silent pin
-- Column-level grants (FIX7) already prevent this at the grant layer,
-- but this trigger is defense-in-depth in case grants are misconfigured.
RAISE EXCEPTION 'tier is read-only; only service_role can modify tier';
END IF;
RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trigger_protect_user_tier ON user_profiles;
CREATE TRIGGER trigger_protect_user_tier
BEFORE UPDATE ON user_profiles
FOR EACH ROW
EXECUTE FUNCTION protect_user_tier();
-- ========================================================================
-- HELPER RPC: Get current user's tier (for Edge Functions + frontend)
-- ========================================================================
-- V1.0.1 FIX3: COALESCE to 'free' if no profile exists yet
-- V1.0.2 FIX10: REVOKE FROM PUBLIC (Postgres default execute hole)
-- V1.0.2 FIX13: Explicit grant to service_role for consistency
-- ========================================================================
CREATE OR REPLACE FUNCTION get_my_tier()
RETURNS TEXT
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $$
SELECT COALESCE(
(SELECT tier FROM public.user_profiles WHERE user_id = auth.uid()),
'free'
);
$$;
-- V1.0.2 FIX10: Revoke from PUBLIC first (Postgres grants execute by default)
REVOKE ALL ON FUNCTION get_my_tier() FROM PUBLIC;
REVOKE ALL ON FUNCTION get_my_tier() FROM anon;
-- Authenticated + service_role only
GRANT EXECUTE ON FUNCTION get_my_tier() TO authenticated;
-- V1.0.2 FIX13: Service role needs tier access for entitlement checks (A18D)
GRANT EXECUTE ON FUNCTION get_my_tier() TO service_role;
-- ========================================================================
-- FUNCTION GRANTS
-- ========================================================================
-- handle_new_user + protect_user_tier are trigger-only, no public access
REVOKE ALL ON FUNCTION handle_new_user() FROM PUBLIC;
REVOKE ALL ON FUNCTION protect_user_tier() FROM PUBLIC;
-- ========================================================================
-- SEED DATA (none — profiles are auto-created on signup)
-- ========================================================================
-- ========================================================================
-- END A13A — V1.0.2
-- ========================================================================
