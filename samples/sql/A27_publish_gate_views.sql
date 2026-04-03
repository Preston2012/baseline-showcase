-- A27: Add is_published gate to public views and RPCs
-- Ensures unpublished figures (< 30 statements) are invisible
-- even when queried via service_role through views.
--
-- v_feed_ranked and v_statements_public get AND f.is_published = true
-- get_baseline_score RPC gets JOIN to figures with is_published check

BEGIN;

-- 1. Update v_feed_ranked
CREATE OR REPLACE VIEW v_feed_ranked
WITH (security_invoker = true)
AS
SELECT
  s.statement_id,
  s.figure_id,
  f.name AS figure_name,
  f.photo_url AS figure_photo_url,
  s.text AS statement_text,
  s.context_pre AS context_before,
  s.context_post AS context_after,
  s.source_url,
  s.timestamp AS stated_at,
  s.ingestion_time,
  s.baseline_delta,
  s.topics,
  CASE
    WHEN c.consensus_id IS NOT NULL THEN 'RANKED'
    WHEN s.baseline_delta IS NULL THEN 'UNRANKED_EARLY'
    ELSE 'UNRANKED_PENDING'
  END AS rank_status,
  c.signal_rank,
  c.variance_detected,
  c.novelty_avg,
  c.repetition_avg,
  c.affective_language_rate_avg,
  c.topic_entropy_avg,
  c.baseline_delta_avg,
  c.framing_consensus,
  c.model_count,
  c.computed_at AS consensus_computed_at
FROM statements s
JOIN figures f ON f.figure_id = s.figure_id
LEFT JOIN consensus c ON c.statement_id = s.statement_id
WHERE s.is_revoked = false
  AND f.is_active = true
  AND f.is_published = true;

-- 2. Update v_statements_public
CREATE OR REPLACE VIEW v_statements_public
WITH (security_invoker = true)
AS
SELECT
  s.statement_id,
  s.figure_id,
  f.name AS figure_name,
  s.text AS statement_text,
  s.context_pre AS context_before,
  s.context_post AS context_after,
  s.source_url,
  s.timestamp AS stated_at,
  s.ingestion_time,
  s.baseline_delta,
  s.topics,
  (s.embedding IS NOT NULL) AS embedding_present
FROM statements s
JOIN figures f ON f.figure_id = s.figure_id
WHERE s.is_revoked = false
  AND f.is_active = true
  AND f.is_published = true;

-- 3. Update get_baseline_score RPC to filter unpublished figures
CREATE OR REPLACE FUNCTION get_baseline_score(p_figure_ids UUID[])
RETURNS TABLE(figure_id UUID, baseline_score NUMERIC, statement_count INTEGER)
LANGUAGE plpgsql STABLE
SET search_path TO 'public'
AS $function$
BEGIN
  IF p_figure_ids IS NULL OR p_figure_ids = '{}' THEN
    RETURN;
  END IF;
  IF array_length(p_figure_ids, 1) > 50 THEN
    RAISE EXCEPTION '[get_baseline_score] Maximum 50 figure IDs per request';
  END IF;
  RETURN QUERY
  SELECT
    s.figure_id,
    ROUND(AVG(c.signal_rank), 2) AS baseline_score,
    COUNT(*)::INTEGER AS statement_count
  FROM statements s
  INNER JOIN consensus c ON c.statement_id = s.statement_id
  INNER JOIN figures f ON f.figure_id = s.figure_id
    AND f.is_active = true
    AND f.is_published = true
  WHERE s.figure_id = ANY(p_figure_ids)
    AND s.is_revoked = false
    AND s.timestamp >= NOW() - INTERVAL '24 hours'
  GROUP BY s.figure_id;
END;
$function$;

-- 4. Re-grant view permissions
GRANT SELECT ON v_statements_public TO anon, authenticated;
GRANT SELECT ON v_feed_ranked TO anon, authenticated;

COMMIT;
