-- ========================================================================
-- BASELINE V1.4 — FRAMING RADAR + HISTORICAL TRENDS
-- A14A — V1.0.1
--
-- FIXES APPLIED (V1.0.0 → V1.0.1 — GPT + Grok audit reconciliation):
-- FIX1: Week bucket comment corrected — uses date_trunc('week', timestamp),
-- not "ISO week boundaries" as previously claimed [Grok M1]
-- FIX2: Removed unused v_bucket_interval variable from
-- get_framing_over_time [Grok M2]
-- FIX3: Added date range validation — RAISE EXCEPTION if
-- start >= end to prevent silent inverted-range queries [GPT]
--
-- PURPOSE:
-- Parameterized RPCs for Framing Radar and Historical Trends.
-- A1 V8.0 has a static framing_radar view (monthly, all-time). These RPCs
-- add configurable date ranges and time bucketing for the A14C endpoint.
--
-- DEPENDENCIES:
-- - A1 V8.0 deployed (consensus, analyses, statements, figures tables)
-- - Statements with consensus data populated
--
-- WHAT THIS DOES NOT DO:
-- - Does not modify A1's existing framing_radar or war_room views
-- - Does not create endpoints (A14C serves these)
-- - Does not gate by tier (A17D middleware handles that)
-- - Does not require any AI compute ($0.00 cost)
--
-- DESIGN DECISIONS:
-- - RPCs over views: views can't accept parameters; RPCs let A14C pass
-- figure_id, date range, and bucket size without client-side filtering.
-- - SECURITY INVOKER: All data is public-readable via existing RLS on
-- consensus/analyses/statements/figures. No escalation needed.
-- - Bucket options: 'week' and 'month'. Daily is too noisy for trends;
-- quarterly is too coarse. Week bucket uses date_trunc('week', timestamp).
-- - Topic RPCs included: topics column exists in A1 V8.0 (statements.topics
-- TEXT[]). RPCs return empty results until ingestion populates topics.
--
-- Safety:
-- CREATE OR REPLACE FUNCTION — idempotent
-- ========================================================================
-- ========================================================================
-- RPC: Framing Distribution for a Figure
-- ========================================================================
-- Returns framing label counts and percentages for a figure within a date
-- range. Groups by framing_consensus from the consensus table.
--
-- If no date range provided, defaults to last 90 days.
-- Null framing_consensus rows (no majority) are included as 'No Consensus'.
--
-- Returns: framing_label, statement_count, percentage (0-100)
-- ========================================================================
CREATE OR REPLACE FUNCTION get_framing_distribution(
p_figure_id UUID,
p_start_date TIMESTAMPTZ DEFAULT NULL,
p_end_date TIMESTAMPTZ DEFAULT NULL
)
RETURNS TABLE (
framing_label TEXT,
statement_count BIGINT,
percentage NUMERIC(5,2)
)
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $$
DECLARE
v_start TIMESTAMPTZ;
v_end TIMESTAMPTZ;
v_total BIGINT;
BEGIN
-- Default to last 90 days if no range provided
v_end := COALESCE(p_end_date, now());
v_start := COALESCE(p_start_date, v_end - INTERVAL '90 days');
-- V1.0.1 FIX3: Validate date range
IF v_start >= v_end THEN
RAISE EXCEPTION 'Invalid date range: start (%) must be before end (%)', v_start, v_end;
END IF;
-- Validate figure exists and is active
IF NOT EXISTS (
SELECT 1 FROM public.figures f
WHERE f.figure_id = p_figure_id AND f.is_active = true
) THEN
RETURN;
END IF;
-- Get total for percentage calculation
SELECT count(*) INTO v_total
FROM public.statements s
INNER JOIN public.consensus c ON c.statement_id = s.statement_id
WHERE s.figure_id = p_figure_id
AND s.is_revoked = false
AND s.language = 'EN'
AND s.timestamp >= v_start
AND s.timestamp < v_end;
-- Return empty if no data
IF v_total = 0 THEN
RETURN;
END IF;
RETURN QUERY
SELECT
COALESCE(c.framing_consensus, 'No Consensus') AS framing_label,
count(*) AS statement_count,
round((count(*)::NUMERIC / v_total) * 100, 2) AS percentage
FROM public.statements s
INNER JOIN public.consensus c ON c.statement_id = s.statement_id
WHERE s.figure_id = p_figure_id
AND s.is_revoked = false
AND s.language = 'EN'
AND s.timestamp >= v_start
AND s.timestamp < v_end
GROUP BY COALESCE(c.framing_consensus, 'No Consensus')
ORDER BY count(*) DESC;
END;
$$;
-- ========================================================================
-- RPC: Framing Radar Over Time (bucketed)
-- ========================================================================
-- Returns framing distribution bucketed by time period for a figure.
-- Used by the Framing Radar™ UI to show how rhetorical framing shifts.
--
-- p_bucket: 'week' or 'month' (default 'month')
-- Week bucket uses date_trunc('week', timestamp).
-- Returns: period (bucket start), framing_label, statement_count
-- ========================================================================
CREATE OR REPLACE FUNCTION get_framing_over_time(
p_figure_id UUID,
p_start_date TIMESTAMPTZ DEFAULT NULL,
p_end_date TIMESTAMPTZ DEFAULT NULL,
p_bucket TEXT DEFAULT 'month'
)
RETURNS TABLE (
period TIMESTAMPTZ,
framing_label TEXT,
statement_count BIGINT
)
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $$
DECLARE
v_start TIMESTAMPTZ;
v_end TIMESTAMPTZ;
BEGIN
-- Default to last 12 months if no range provided
v_end := COALESCE(p_end_date, now());
v_start := COALESCE(p_start_date, v_end - INTERVAL '12 months');
-- V1.0.1 FIX3: Validate date range
IF v_start >= v_end THEN
RAISE EXCEPTION 'Invalid date range: start (%) must be before end (%)', v_start, v_end;
END IF;
-- Validate bucket
IF p_bucket NOT IN ('week', 'month') THEN
RAISE EXCEPTION 'Invalid bucket: %. Must be week or month.', p_bucket;
END IF;
-- Validate figure exists and is active
IF NOT EXISTS (
SELECT 1 FROM public.figures f
WHERE f.figure_id = p_figure_id AND f.is_active = true
) THEN
RETURN;
END IF;
RETURN QUERY
SELECT
date_trunc(p_bucket, s.timestamp) AS period,
COALESCE(c.framing_consensus, 'No Consensus') AS framing_label,
count(*) AS statement_count
FROM public.statements s
INNER JOIN public.consensus c ON c.statement_id = s.statement_id
WHERE s.figure_id = p_figure_id
AND s.is_revoked = false
AND s.language = 'EN'
AND s.timestamp >= v_start
AND s.timestamp < v_end
GROUP BY date_trunc(p_bucket, s.timestamp),
COALESCE(c.framing_consensus, 'No Consensus')
ORDER BY period ASC, statement_count DESC;
END;
$$;
-- ========================================================================
-- RPC: Historical Trends (consensus metric averages over time)
-- ========================================================================
-- Returns time-bucketed averages of all consensus metrics for a figure.
-- Powers the Historical Trends dashboard.
--
-- p_bucket: 'week' or 'month' (default 'month')
-- Returns: period, statement_count, plus avg for each metric + signal_rank
-- ========================================================================
CREATE OR REPLACE FUNCTION get_historical_trends(
p_figure_id UUID,
p_start_date TIMESTAMPTZ DEFAULT NULL,
p_end_date TIMESTAMPTZ DEFAULT NULL,
p_bucket TEXT DEFAULT 'month'
)
RETURNS TABLE (
period TIMESTAMPTZ,
statement_count BIGINT,
avg_repetition NUMERIC(5,2),
avg_novelty NUMERIC(5,2),
avg_affective_language_rate NUMERIC(5,2),
avg_topic_entropy NUMERIC(5,2),
avg_baseline_delta NUMERIC(5,2),
avg_signal_rank NUMERIC(5,2)
)
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $$
DECLARE
v_start TIMESTAMPTZ;
v_end TIMESTAMPTZ;
BEGIN
-- Default to last 12 months if no range provided
v_end := COALESCE(p_end_date, now());
v_start := COALESCE(p_start_date, v_end - INTERVAL '12 months');
-- V1.0.1 FIX3: Validate date range
IF v_start >= v_end THEN
RAISE EXCEPTION 'Invalid date range: start (%) must be before end (%)', v_start, v_end;
END IF;
-- Validate bucket
IF p_bucket NOT IN ('week', 'month') THEN
RAISE EXCEPTION 'Invalid bucket: %. Must be week or month.', p_bucket;
END IF;
-- Validate figure exists and is active
IF NOT EXISTS (
SELECT 1 FROM public.figures f
WHERE f.figure_id = p_figure_id AND f.is_active = true
) THEN
RETURN;
END IF;
RETURN QUERY
SELECT
date_trunc(p_bucket, s.timestamp) AS period,
count(*) AS statement_count,
round(avg(c.repetition_avg), 2) AS avg_repetition,
round(avg(c.novelty_avg), 2) AS avg_novelty,
round(avg(c.affective_language_rate_avg), 2) AS avg_affective_language_rate,
round(avg(c.topic_entropy_avg), 2) AS avg_topic_entropy,
round(avg(c.baseline_delta_avg), 2) AS avg_baseline_delta,
round(avg(c.signal_rank), 2) AS avg_signal_rank
FROM public.statements s
INNER JOIN public.consensus c ON c.statement_id = s.statement_id
WHERE s.figure_id = p_figure_id
AND s.is_revoked = false
AND s.language = 'EN'
AND s.timestamp >= v_start
AND s.timestamp < v_end
GROUP BY date_trunc(p_bucket, s.timestamp)
ORDER BY period ASC;
END;
$$;
-- ========================================================================
-- RPC: Topic Distribution for a Figure
-- ========================================================================
-- Returns topic counts and percentages for a figure within a date range.
-- Since topics is TEXT[] (1-3 per statement), we unnest and count.
-- Column exists in A1 V8.0; returns empty until ingestion populates topics.
--
-- Returns: topic, statement_count, percentage (0-100)
-- ========================================================================
CREATE OR REPLACE FUNCTION get_topic_distribution(
p_figure_id UUID,
p_start_date TIMESTAMPTZ DEFAULT NULL,
p_end_date TIMESTAMPTZ DEFAULT NULL
)
RETURNS TABLE (
topic TEXT,
statement_count BIGINT,
percentage NUMERIC(5,2)
)
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $$
DECLARE
v_start TIMESTAMPTZ;
v_end TIMESTAMPTZ;
v_total BIGINT;
BEGIN
-- Default to last 90 days if no range provided
v_end := COALESCE(p_end_date, now());
v_start := COALESCE(p_start_date, v_end - INTERVAL '90 days');
-- V1.0.1 FIX3: Validate date range
IF v_start >= v_end THEN
RAISE EXCEPTION 'Invalid date range: start (%) must be before end (%)', v_start, v_end;
END IF;
-- Validate figure exists and is active
IF NOT EXISTS (
SELECT 1 FROM public.figures f
WHERE f.figure_id = p_figure_id AND f.is_active = true
) THEN
RETURN;
END IF;
-- Total statements (not total topic tags) for percentage base
SELECT count(*) INTO v_total
FROM public.statements s
WHERE s.figure_id = p_figure_id
AND s.is_revoked = false
AND s.language = 'EN'
AND s.topics IS NOT NULL
AND s.timestamp >= v_start
AND s.timestamp < v_end;
IF v_total = 0 THEN
RETURN;
END IF;
-- Unnest topics array, count per topic
-- Percentage is relative to total statements (not total tags)
-- so a statement tagged [ECONOMY, IMMIGRATION] adds 1 to each
RETURN QUERY
SELECT
t.topic,
count(DISTINCT s.statement_id) AS statement_count,
round((count(DISTINCT s.statement_id)::NUMERIC / v_total) * 100, 2) AS percentage
FROM public.statements s,
unnest(s.topics) AS t(topic)
WHERE s.figure_id = p_figure_id
AND s.is_revoked = false
AND s.language = 'EN'
AND s.topics IS NOT NULL
AND s.timestamp >= v_start
AND s.timestamp < v_end
GROUP BY t.topic
ORDER BY count(DISTINCT s.statement_id) DESC;
END;
$$;
-- ========================================================================
-- RPC: Topic Trends Over Time (bucketed)
-- ========================================================================
-- Returns topic distribution bucketed by time period for a figure.
-- Shows how a figure's focus shifts across topics over time.
--
-- Returns: period, topic, statement_count
-- ========================================================================
CREATE OR REPLACE FUNCTION get_topic_over_time(
p_figure_id UUID,
p_start_date TIMESTAMPTZ DEFAULT NULL,
p_end_date TIMESTAMPTZ DEFAULT NULL,
p_bucket TEXT DEFAULT 'month'
)
RETURNS TABLE (
period TIMESTAMPTZ,
topic TEXT,
statement_count BIGINT
)
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $$
DECLARE
v_start TIMESTAMPTZ;
v_end TIMESTAMPTZ;
BEGIN
-- Default to last 12 months if no range provided
v_end := COALESCE(p_end_date, now());
v_start := COALESCE(p_start_date, v_end - INTERVAL '12 months');
-- V1.0.1 FIX3: Validate date range
IF v_start >= v_end THEN
RAISE EXCEPTION 'Invalid date range: start (%) must be before end (%)', v_start, v_end;
END IF;
-- Validate bucket
IF p_bucket NOT IN ('week', 'month') THEN
RAISE EXCEPTION 'Invalid bucket: %. Must be week or month.', p_bucket;
END IF;
-- Validate figure exists and is active
IF NOT EXISTS (
SELECT 1 FROM public.figures f
WHERE f.figure_id = p_figure_id AND f.is_active = true
) THEN
RETURN;
END IF;
RETURN QUERY
SELECT
date_trunc(p_bucket, s.timestamp) AS period,
t.topic,
count(DISTINCT s.statement_id) AS statement_count
FROM public.statements s,
unnest(s.topics) AS t(topic)
WHERE s.figure_id = p_figure_id
AND s.is_revoked = false
AND s.language = 'EN'
AND s.topics IS NOT NULL
AND s.timestamp >= v_start
AND s.timestamp < v_end
GROUP BY date_trunc(p_bucket, s.timestamp), t.topic
ORDER BY period ASC, count(DISTINCT s.statement_id) DESC;
END;
$$;
-- ========================================================================
-- GRANTS
-- ========================================================================
-- All RPCs are public-readable (SECURITY INVOKER + existing RLS).
-- Authenticated users and service_role can call them.
-- No anon or PUBLIC access.
-- ========================================================================
-- get_framing_distribution
REVOKE ALL ON FUNCTION get_framing_distribution(UUID, TIMESTAMPTZ,
TIMESTAMPTZ) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION get_framing_distribution(UUID, TIMESTAMPTZ,
TIMESTAMPTZ) TO authenticated;
GRANT EXECUTE ON FUNCTION get_framing_distribution(UUID, TIMESTAMPTZ,
TIMESTAMPTZ) TO service_role;
-- get_framing_over_time
REVOKE ALL ON FUNCTION get_framing_over_time(UUID, TIMESTAMPTZ, TIMESTAMPTZ,
TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION get_framing_over_time(UUID, TIMESTAMPTZ,
TIMESTAMPTZ, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION get_framing_over_time(UUID, TIMESTAMPTZ,
TIMESTAMPTZ, TEXT) TO service_role;
-- get_historical_trends
REVOKE ALL ON FUNCTION get_historical_trends(UUID, TIMESTAMPTZ, TIMESTAMPTZ,
TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION get_historical_trends(UUID, TIMESTAMPTZ,
TIMESTAMPTZ, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION get_historical_trends(UUID, TIMESTAMPTZ,
TIMESTAMPTZ, TEXT) TO service_role;
-- get_topic_distribution
REVOKE ALL ON FUNCTION get_topic_distribution(UUID, TIMESTAMPTZ, TIMESTAMPTZ)
FROM PUBLIC;
GRANT EXECUTE ON FUNCTION get_topic_distribution(UUID, TIMESTAMPTZ,
TIMESTAMPTZ) TO authenticated;
GRANT EXECUTE ON FUNCTION get_topic_distribution(UUID, TIMESTAMPTZ,
TIMESTAMPTZ) TO service_role;
-- get_topic_over_time
REVOKE ALL ON FUNCTION get_topic_over_time(UUID, TIMESTAMPTZ, TIMESTAMPTZ,
TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION get_topic_over_time(UUID, TIMESTAMPTZ,
TIMESTAMPTZ, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION get_topic_over_time(UUID, TIMESTAMPTZ,
TIMESTAMPTZ, TEXT) TO service_role;
-- ========================================================================
-- END A14A — V1.0.1
-- ========================================================================
