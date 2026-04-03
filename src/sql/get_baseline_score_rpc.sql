-- ========================================================================
-- Baseline™ Score. SQL RPC Function. V1.2.0
--
-- Computes AVG(signal_rank) over the last 24 hours per figure.
-- Designed for batch calls from the get-baseline-score Edge Function.
--
-- Joins: statements → consensus (via statement_id, UNIQUE FK)
-- Filter: statements.timestamp >= NOW() - INTERVAL '24 hours'
-- Groups: by figure_id
-- Returns: figure_id, baseline_score (rounded to 2 decimal places),
--          statement_count
--
-- Performance: Uses idx_statements_figure_timestamp_recent composite
-- index (figure_id, timestamp DESC) for the WHERE clause.
-- Joins on indexed consensus.statement_id (UNIQUE index from A1).
-- 50-figure batch cap enforced at both Edge and SQL level.
--
-- Security: SECURITY INVOKER: relies on caller's permissions.
-- Edge Function calls via service-role client (bypasses RLS).
-- statements + consensus have public SELECT RLS. All data is public.
--
-- AUDIT FIXES (V1.1.0 → V1.2.0):
-- A2-C2: Null guard on baseline_score mapping (Number(null) = 0 fix)
-- A2-I1: Module-level Supabase client (no per-request allocation)
-- A2-M1: SQL array bounds guard (LANGUAGE sql → plpgsql)
-- A2-P1: Performance index deployed (not deferred)
-- ========================================================================

CREATE OR REPLACE FUNCTION get_baseline_score(p_figure_ids UUID[])
RETURNS TABLE (
  figure_id   UUID,
  baseline_score NUMERIC(5,2),
  statement_count INTEGER
)
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
BEGIN
  -- Defense in depth: bound array size even if Edge already validates.
  IF p_figure_ids IS NULL OR p_figure_ids = '{}' THEN
    RETURN;
  END IF;

  IF array_length(p_figure_ids, 1) > 50 THEN
    RAISE EXCEPTION '[get_baseline_score] Maximum 50 figure IDs per request';
  END IF;

  RETURN QUERY
  SELECT
    s.figure_id,
    ROUND(AVG(c.signal_rank), 2)  AS baseline_score,
    COUNT(*)::INTEGER              AS statement_count
  FROM statements s
  INNER JOIN consensus c
    ON c.statement_id = s.statement_id
  WHERE s.figure_id = ANY(p_figure_ids)
    AND s.timestamp >= NOW() - INTERVAL '24 hours'
  GROUP BY s.figure_id;
END;
$$;

-- Grant execute to anon + authenticated + service_role.
GRANT EXECUTE ON FUNCTION get_baseline_score(UUID[]) TO anon;
GRANT EXECUTE ON FUNCTION get_baseline_score(UUID[]) TO authenticated;
GRANT EXECUTE ON FUNCTION get_baseline_score(UUID[]) TO service_role;

-- ========================================================================
-- Performance index for feed-blocking aggregate (AUDIT FIX A2-P1)
-- Covers WHERE s.figure_id = ANY(...) AND s.timestamp >= threshold.
-- 48h window on partial index to account for index refresh lag.
-- ========================================================================
CREATE INDEX IF NOT EXISTS idx_statements_figure_timestamp_recent
  ON statements(figure_id, timestamp DESC);
