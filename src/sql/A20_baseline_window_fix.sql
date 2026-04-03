-- ========================================================================
-- A20 v1.0.0: Fix baseline_window ingestion_time comparison
--
-- BUG: get_baseline_window and backfill_baseline_delta used strict '<'
-- for ingestion_time comparison. When statements are bulk-ingested with
-- identical timestamps (persist_gemini_output batch), they can't see each
-- other in the baseline window. This prevents baseline_delta computation
-- for statements 29-38+ in a figure's history.
--
-- FIX: Change '<' to '<=' for ingestion_time. The statement_id <>
-- exclusion already prevents self-reference, so this is safe.
--
-- IMPACT: Unblocks ~77+ consensus computations that were stuck on
-- "baseline_delta is NULL" due to bulk ingestion timestamp collisions.
-- ========================================================================

-- Fix 1: get_baseline_window
CREATE OR REPLACE FUNCTION public.get_baseline_window(
  p_figure_id uuid,
  p_exclude_statement_id uuid,
  p_max_statements integer DEFAULT 50
)
RETURNS TABLE(statement_id uuid, embedding vector, ts timestamptz, time_weight numeric)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_limit INTEGER;
  v_count INTEGER;
  v_cutoff_ingestion TIMESTAMPTZ;
BEGIN
  IF auth.role() IS DISTINCT FROM 'service_role' THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  v_limit := LEAST(GREATEST(p_max_statements, 30), 50);

  SELECT s.ingestion_time INTO v_cutoff_ingestion
  FROM statements s
  WHERE s.statement_id = p_exclude_statement_id;

  IF v_cutoff_ingestion IS NULL THEN
    RETURN;
  END IF;

  -- A20 FIX: <= instead of < so bulk-ingested statements see peers
  SELECT COUNT(*) INTO v_count
  FROM statements s
  WHERE s.figure_id = p_figure_id
    AND s.statement_id <> p_exclude_statement_id
    AND s.embedding IS NOT NULL
    AND s.is_revoked = false
    AND s.ingestion_time <= v_cutoff_ingestion;

  IF v_count < 30 THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT
    s.statement_id,
    s.embedding,
    s.timestamp,
    1.0::NUMERIC AS time_weight
  FROM statements s
  WHERE s.figure_id = p_figure_id
    AND s.statement_id <> p_exclude_statement_id
    AND s.embedding IS NOT NULL
    AND s.is_revoked = false
    AND s.ingestion_time <= v_cutoff_ingestion
  ORDER BY s.timestamp DESC
  LIMIT v_limit;
END;
$function$;

-- Fix 2: backfill_baseline_delta
CREATE OR REPLACE FUNCTION public.backfill_baseline_delta(
  p_figure_id uuid,
  p_limit integer DEFAULT 50
)
RETURNS jsonb
LANGUAGE plpgsql
SET search_path TO 'public'
AS $function$
DECLARE
  v_updated_count INTEGER := 0;
  v_skipped_count INTEGER := 0;
  v_rowcount INTEGER := 0;
  v_statement RECORD;
  v_window_size INTEGER;
  v_avg_distance NUMERIC;
  v_baseline_delta NUMERIC;
BEGIN
  IF p_limit < 1 OR p_limit > 500 THEN
    RAISE EXCEPTION 'backfill_baseline_delta: limit must be between 1 and 500';
  END IF;

  FOR v_statement IN
    SELECT
      s.statement_id,
      s.figure_id,
      s.embedding,
      s.ingestion_time
    FROM statements s
    WHERE s.figure_id = p_figure_id
      AND s.baseline_delta IS NULL
      AND s.embedding IS NOT NULL
      AND s.is_revoked = false
    ORDER BY s.ingestion_time ASC
    LIMIT p_limit
  LOOP
    WITH baseline_window AS (
      -- A20 FIX: <= instead of < so bulk-ingested statements see peers
      SELECT s2.embedding
      FROM statements s2
      WHERE s2.figure_id = v_statement.figure_id
        AND s2.statement_id <> v_statement.statement_id
        AND s2.embedding IS NOT NULL
        AND s2.is_revoked = false
        AND s2.ingestion_time <= v_statement.ingestion_time
      ORDER BY s2.ingestion_time DESC
      LIMIT 50
    ),
    distances AS (
      SELECT (v_statement.embedding <=> bw.embedding) AS distance
      FROM baseline_window bw
    )
    SELECT
      COUNT(*)::integer,
      AVG(distance)
    INTO v_window_size, v_avg_distance
    FROM distances;

    IF v_window_size >= 30 THEN
      v_baseline_delta := ROUND(LEAST(100, GREATEST(0, v_avg_distance * 100))::numeric, 2);
      UPDATE statements
      SET baseline_delta = v_baseline_delta
      WHERE statement_id = v_statement.statement_id
        AND baseline_delta IS NULL;
      GET DIAGNOSTICS v_rowcount = ROW_COUNT;
      IF v_rowcount = 1 THEN
        v_updated_count := v_updated_count + 1;
      ELSE
        v_skipped_count := v_skipped_count + 1;
      END IF;
    ELSE
      v_skipped_count := v_skipped_count + 1;
    END IF;
  END LOOP;

  RETURN jsonb_build_object(
    'figure_id', p_figure_id,
    'updated_count', v_updated_count,
    'skipped_count', v_skipped_count,
    'message',
    CASE
      WHEN v_updated_count = 0 THEN 'No statements eligible for backfill'
      ELSE format('Backfilled %s statements, skipped %s', v_updated_count, v_skipped_count)
    END
  );
END;
$function$;
