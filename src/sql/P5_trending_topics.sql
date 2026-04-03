--═══════════════════════════════════════════════════════════════════════
-- P5 — TRENDING TOPICS RPC (FINAL)
-- Supabase migration: p5_trending_topics.sql
--
-- Aggregates topic frequency from statements.topics[] over a
-- configurable time window. Returns top N topics with statement
-- count and trend direction (rising/falling/stable vs previous
-- equivalent period).
--
-- Post-A17 auxiliary. Read-only on statements table.
-- Anon-callable via SECURITY INVOKER — A1's statements_public_read
-- RLS policy auto-filters to active figures.
--
-- DEPENDS ON:
-- A1: statements table, topics TEXT[] column, is_revoked column,
-- statements_public_read RLS policy (anon SELECT)
--
-- CONSUMED BY:
-- F3.14: search_service.dart (150.2 integration)
-- F7.5: search_provider.dart (replaces hardcoded fallback)
-- F4.14: search screen (topic chips)
--
-- CANONICAL TOPIC ENUM (A2/A5A — 11 values):
-- ECONOMY, IMMIGRATION, AI_TECHNOLOGY, FOREIGN_POLICY,
-- HEALTHCARE, CLIMATE_ENVIRONMENT, CRIME_JUSTICE, ELECTIONS,
-- MILITARY_DEFENSE, CULTURE_SOCIETY, OTHER
--═══════════════════════════════════════════════════════════════════════
-- ── Indexes─────────────────────────────────────────────────────────
-- Btree on created_at for time-window scans (primary driver of this RPC).
CREATE INDEX IF NOT EXISTS idx_statements_created_at
ON statements(created_at DESC);
-- GIN on topics for @> containment queries (used by other features;
-- also helps unnest scans on large tables).
CREATE INDEX IF NOT EXISTS idx_statements_topics_gin
ON statements USING gin (topics);
-- ── get_trending_topics RPC─────────────────────────────────────────
-- Returns a JSONB array of trending topics sorted by frequency.
--
-- Parameters:
-- p_days (INT, default 7) — Time window in days. Clamped 1-90.
-- p_limit (INT, default 10) — Max topics returned. Clamped 1-11.
--
-- Response shape (JSONB array):
-- [
-- {
-- "topic": "ECONOMY",
-- "statement_count": 42,
-- "previous_count": 31,
-- "trend": "rising"
-- },
-- ...
-- ]
--
-- Trend logic:
-- current > previous × 1.10 → "rising"
-- current < previous × 0.90 → "falling"
-- otherwise → "stable"
-- previous = 0 AND current > 0 → "rising"
-- both = 0 → excluded (no statements mentioning topic)
--
-- "OTHER" is excluded — it's a catch-all with no trending signal.
--
-- SECURITY: INVOKER (anon-callable via A1 statements_public_read RLS).
-- RLS auto-filters to active figures — trending counts only include
-- statements from public, active figures. is_revoked filtered explicitly
-- because RLS does not check revocation status.
-- VOLATILITY: STABLE (pure read, no side effects).
CREATE OR REPLACE FUNCTION get_trending_topics(
p_days INT DEFAULT 7,
p_limit INT DEFAULT 10
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $$
DECLARE
v_days INT;
v_limit INT;
v_now TIMESTAMPTZ;
v_current_start TIMESTAMPTZ;
v_prev_start TIMESTAMPTZ;
v_result JSONB;
BEGIN
-- ── Clamp parameters──────────────────────────────────────────────
v_days := GREATEST(1, LEAST(p_days, 90));
v_limit := GREATEST(1, LEAST(p_limit, 11));
v_now := now();
-- Current window: [now - v_days, now)
v_current_start := v_now - make_interval(days := v_days);
-- Previous window: [now - 2*v_days, now - v_days)
v_prev_start := v_now - make_interval(days := 2 * v_days);
-- ── Aggregate and compare─────────────────────────────────────────
WITH current_counts AS (
SELECT
t.topic,
COUNT(*)::INT AS statement_count
FROM statements s,
unnest(s.topics) AS t(topic)
WHERE s.created_at >= v_current_start
AND s.created_at < v_now
AND s.is_revoked = false
AND t.topic <> 'OTHER'
GROUP BY t.topic
),
previous_counts AS (
SELECT
t.topic,
COUNT(*)::INT AS statement_count
FROM statements s,
unnest(s.topics) AS t(topic)
WHERE s.created_at >= v_prev_start
AND s.created_at < v_current_start
AND s.is_revoked = false
AND t.topic <> 'OTHER'
GROUP BY t.topic
),
combined AS (
SELECT
COALESCE(c.topic, p.topic) AS topic,
COALESCE(c.statement_count, 0) AS current_count,
COALESCE(p.statement_count, 0) AS previous_count
FROM current_counts c
FULL OUTER JOIN previous_counts p ON c.topic = p.topic
-- Only include topics with at least 1 statement in current window
WHERE COALESCE(c.statement_count, 0) > 0
),
ranked AS (
SELECT
topic,
current_count AS statement_count,
previous_count,
CASE
WHEN previous_count = 0 AND current_count > 0 THEN 'rising'
WHEN current_count > (previous_count * 1.10) THEN 'rising'
WHEN current_count < (previous_count * 0.90) THEN 'falling'
ELSE 'stable'
END AS trend
FROM combined
ORDER BY current_count DESC, topic ASC
LIMIT v_limit
)
SELECT COALESCE(
jsonb_agg(
jsonb_build_object(
'topic', r.topic,
'statement_count', r.statement_count,
'previous_count', r.previous_count,
'trend', r.trend
)
),
'[]'::JSONB
)
INTO v_result
FROM ranked r;
RETURN v_result;
END;
$$;
-- ── Grant access to anon + authenticated roles ─────────────────────
-- PostgREST serves RPCs via these grants.
GRANT EXECUTE ON FUNCTION get_trending_topics(INT, INT) TO anon;
GRANT EXECUTE ON FUNCTION get_trending_topics(INT, INT) TO authenticated;
-- ── Comment for documentation───────────────────────────────────────
COMMENT ON FUNCTION get_trending_topics IS
'P5: Returns trending topics from statements.topics[] with frequency '
'counts and trend direction vs previous period. Anon-callable. '
'Tier gating is screen-layer (F7.5/F4.14).';
