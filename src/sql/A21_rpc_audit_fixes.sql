-- ========================================================================
-- A21 v1.0.0: RPC Audit Fixes
--
-- Fixes from comprehensive audit of all 56 custom database functions.
--
-- 1. get_baseline_score: Added missing is_revoked=false filter
--    (revoked statements were polluting baseline scores)
-- 2. revoke_statement: Added revoked_at = NOW()
--    (was NULL, inconsistent with revoke_low_quality_statements)
-- 3. revoke_low_quality_statements: Added search_path + service_role gate
--    (SECURITY DEFINER with no restrictions = privilege escalation)
-- 4. get_tracked_bills: Changed to SECURITY INVOKER + added search_path
--    (DEFINER not needed for read-only, was bypassing RLS)
-- 5. count_todays_tweets: Added SET search_path
-- 6. get_mutation_timeline: Added search_path + ORDER BY to LIMIT 1
--    (non-deterministic metadata from bill_versions without ORDER BY)
-- ========================================================================

-- FIX 1: get_baseline_score
CREATE OR REPLACE FUNCTION public.get_baseline_score(p_figure_ids uuid[])
RETURNS TABLE(figure_id uuid, baseline_score numeric, statement_count integer)
LANGUAGE plpgsql
STABLE
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
  WHERE s.figure_id = ANY(p_figure_ids)
    AND s.is_revoked = false
    AND s.timestamp >= NOW() - INTERVAL '24 hours'
  GROUP BY s.figure_id;
END;
$function$;

GRANT EXECUTE ON FUNCTION get_baseline_score(uuid[]) TO anon, authenticated, service_role;

-- FIX 2: revoke_statement
CREATE OR REPLACE FUNCTION public.revoke_statement(p_statement_id uuid, p_reason text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_updated BOOLEAN;
BEGIN
  IF auth.role() IS DISTINCT FROM 'service_role' THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  IF p_reason IS NULL OR trim(p_reason) = '' THEN
    RAISE EXCEPTION 'revocation_reason is required';
  END IF;
  UPDATE statements
  SET is_revoked = true,
      revoked_at = NOW(),
      revocation_reason = trim(p_reason)
  WHERE statement_id = p_statement_id
    AND is_revoked = false;
  v_updated := FOUND;
  RETURN v_updated;
END;
$function$;

-- FIX 3: revoke_low_quality_statements
CREATE OR REPLACE FUNCTION public.revoke_low_quality_statements(
  p_threshold integer DEFAULT 30,
  p_dry_run boolean DEFAULT false
)
RETURNS TABLE(revoked_count bigint, sample_revoked jsonb)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_count BIGINT;
  v_samples JSONB;
BEGIN
  IF auth.role() IS DISTINCT FROM 'service_role' THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  CREATE TEMP TABLE _quality_candidates ON COMMIT DROP AS
  SELECT
    s.statement_id,
    s.figure_id,
    f.name AS figure_name,
    s.text,
    statement_quality_score(s.text, s.context_pre, s.context_post) AS quality_score
  FROM statements s
  JOIN figures f ON f.figure_id = s.figure_id
  WHERE s.is_revoked = false
    AND statement_quality_score(s.text, s.context_pre, s.context_post) < p_threshold;

  SELECT count(*) INTO v_count FROM _quality_candidates;

  SELECT COALESCE(jsonb_agg(row_to_json(sub)::jsonb), '[]'::jsonb)
  INTO v_samples
  FROM (
    SELECT figure_name, quality_score, LEFT(text, 100) AS text_preview
    FROM _quality_candidates
    ORDER BY quality_score ASC
    LIMIT 20
  ) sub;

  IF NOT p_dry_run AND v_count > 0 THEN
    UPDATE statements s
    SET is_revoked = true,
        revoked_at = NOW(),
        revocation_reason = 'auto_quality_gate_v1: score=' || qc.quality_score || ' threshold=' || p_threshold
    FROM _quality_candidates qc
    WHERE s.statement_id = qc.statement_id;
  END IF;

  RETURN QUERY SELECT v_count, v_samples;
END;
$function$;

-- FIX 4: get_tracked_bills  - SECURITY INVOKER (was DEFINER unnecessarily)
CREATE OR REPLACE FUNCTION public.get_tracked_bills(p_congress_session integer DEFAULT 119)
RETURNS TABLE(bill_id text, bill_number text, chamber_code text, congress_session integer, has_versions boolean)
LANGUAGE sql
STABLE
SET search_path TO 'pg_catalog', 'public'
AS $function$
  WITH bills_from_versions AS (
    SELECT DISTINCT bv.bill_id
    FROM bill_versions bv
    WHERE bv.congress_session = p_congress_session
  ),
  bills_from_votes AS (
    SELECT DISTINCT v.bill_id
    FROM votes v
    WHERE v.congress_session = p_congress_session
  ),
  all_bills AS (
    SELECT bfv2.bill_id FROM bills_from_versions bfv2
    UNION
    SELECT bfv3.bill_id FROM bills_from_votes bfv3
  )
  SELECT
    ab.bill_id,
    regexp_replace(ab.bill_id, '^(H\.R\.|S\.|H\.Res\.|S\.Res\.|H\.J\.Res\.|S\.J\.Res\.)\s*', '') AS bill_number,
    CASE
      WHEN ab.bill_id LIKE 'H.R.%' THEN 'hr'
      WHEN ab.bill_id LIKE 'H.Res.%' THEN 'hres'
      WHEN ab.bill_id LIKE 'H.J.Res.%' THEN 'hjres'
      WHEN ab.bill_id LIKE 'S.%' AND ab.bill_id NOT LIKE 'S.Res.%' AND ab.bill_id NOT LIKE 'S.J.Res.%' THEN 's'
      WHEN ab.bill_id LIKE 'S.Res.%' THEN 'sres'
      WHEN ab.bill_id LIKE 'S.J.Res.%' THEN 'sjres'
      ELSE 'hr'
    END AS chamber_code,
    p_congress_session AS congress_session,
    EXISTS (SELECT 1 FROM bills_from_versions bfv4 WHERE bfv4.bill_id = ab.bill_id) AS has_versions
  FROM all_bills ab
  ORDER BY ab.bill_id;
$function$;

GRANT EXECUTE ON FUNCTION get_tracked_bills(integer) TO anon, authenticated, service_role;

-- FIX 5: count_todays_tweets  - add search_path
CREATE OR REPLACE FUNCTION public.count_todays_tweets()
RETURNS integer
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT COUNT(*)::INTEGER
  FROM posted_tweets
  WHERE status = 'posted'
    AND posted_at::date = CURRENT_DATE;
$function$;

-- FIX 6: get_mutation_timeline  - add search_path + ORDER BY to LIMIT 1
CREATE OR REPLACE FUNCTION public.get_mutation_timeline(p_bill_id text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path TO 'public'
AS $function$
DECLARE
  v_result JSONB;
  v_versions JSONB;
  v_comparisons JSONB;
BEGIN
  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'id', bv.version_id,
      'bill_id', bv.bill_id,
      'stage', bv.stage,
      'timestamp', bv.version_timestamp,
      'provision_count', bv.provision_count,
      'label', bv.label
    ) ORDER BY
      CASE bv.stage
        WHEN 'introduced' THEN 0
        WHEN 'committee' THEN 1
        WHEN 'engrossed' THEN 2
        WHEN 'enrolled' THEN 3
        ELSE 99
      END
  ), '[]'::jsonb)
  INTO v_versions
  FROM bill_versions bv
  WHERE bv.bill_id = p_bill_id;

  IF v_versions = '[]'::jsonb THEN
    RETURN NULL;
  END IF;

  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'from_version', jsonb_build_object(
        'id', bv_from.version_id,
        'bill_id', bv_from.bill_id,
        'stage', bv_from.stage,
        'timestamp', bv_from.version_timestamp,
        'provision_count', bv_from.provision_count,
        'label', bv_from.label
      ),
      'to_version', jsonb_build_object(
        'id', bv_to.version_id,
        'bill_id', bv_to.bill_id,
        'stage', bv_to.stage,
        'timestamp', bv_to.version_timestamp,
        'provision_count', bv_to.provision_count,
        'label', bv_to.label
      ),
      'aggregate_mutation', vc.aggregate_mutation,
      'provisions_added', vc.provisions_added,
      'provisions_removed', vc.provisions_removed,
      'provisions_modified', vc.provisions_modified,
      'total_provisions', vc.total_provisions,
      'diffs', COALESCE((
        SELECT jsonb_agg(
          jsonb_build_object(
            'id', md.diff_id,
            'provision_title', md.provision_title,
            'provision_index', md.provision_index,
            'type', md.diff_type,
            'magnitude', md.magnitude,
            'category', md.category,
            'old_text', md.old_text,
            'new_text', md.new_text,
            'spending_delta', md.spending_delta,
            'old_spending', md.old_spending,
            'new_spending', md.new_spending
          ) ORDER BY md.magnitude DESC
        )
        FROM mutation_diffs md
        WHERE md.comparison_id = vc.comparison_id
      ), '[]'::jsonb)
    ) ORDER BY
      CASE bv_from.stage
        WHEN 'introduced' THEN 0
        WHEN 'committee' THEN 1
        WHEN 'engrossed' THEN 2
        WHEN 'enrolled' THEN 3
        ELSE 99
      END
  ), '[]'::jsonb)
  INTO v_comparisons
  FROM version_comparisons vc
  JOIN bill_versions bv_from ON bv_from.version_id = vc.from_version_id
  JOIN bill_versions bv_to ON bv_to.version_id = vc.to_version_id
  WHERE vc.bill_id = p_bill_id;

  SELECT jsonb_build_object(
    'bill_id', p_bill_id,
    'bill_title', COALESCE(
      (SELECT bv.bill_title FROM bill_versions bv WHERE bv.bill_id = p_bill_id ORDER BY bv.version_timestamp DESC LIMIT 1),
      ''
    ),
    'versions', v_versions,
    'comparisons', v_comparisons,
    'sponsor', (SELECT bv.sponsor FROM bill_versions bv WHERE bv.bill_id = p_bill_id ORDER BY bv.version_timestamp DESC LIMIT 1),
    'chamber', (SELECT bv.chamber FROM bill_versions bv WHERE bv.bill_id = p_bill_id ORDER BY bv.version_timestamp DESC LIMIT 1),
    'congress_session', (SELECT bv.congress_session::text FROM bill_versions bv WHERE bv.bill_id = p_bill_id ORDER BY bv.version_timestamp DESC LIMIT 1)
  )
  INTO v_result;

  RETURN v_result;
END;
$function$;
