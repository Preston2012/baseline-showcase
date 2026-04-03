-- ========================================================================
-- get_mutation_timeline: Assembles the full mutation timeline for a bill.
-- Returns the JSON shape that PM-MT.4 MutationTimeline.fromJson() expects.
--
-- Called by: Dart frontend (via mutation_timeline_service, Edge Function,
-- or direct PostgREST RPC depending on data access doctrine decision).
--
-- Auth: anon/authenticated. Executes as INVOKER so RLS policies on
-- underlying tables are enforced (feature flag gating, tier checks).
-- ========================================================================

CREATE OR REPLACE FUNCTION get_mutation_timeline(p_bill_id TEXT)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
AS $$
DECLARE
  v_result JSONB;
  v_versions JSONB;
  v_comparisons JSONB;
BEGIN
  -- Build versions array
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

  -- Early exit: no versions found
  IF v_versions = '[]'::jsonb THEN
    RETURN NULL;
  END IF;

  -- Build comparisons array with nested diffs
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

  -- Assemble final result matching MutationTimeline.fromJson shape
  SELECT jsonb_build_object(
    'bill_id', p_bill_id,
    'bill_title', COALESCE(
      (SELECT bv.bill_title FROM bill_versions bv WHERE bv.bill_id = p_bill_id LIMIT 1),
      ''
    ),
    'versions', v_versions,
    'comparisons', v_comparisons,
    'sponsor', (SELECT bv.sponsor FROM bill_versions bv WHERE bv.bill_id = p_bill_id LIMIT 1),
    'chamber', (SELECT bv.chamber FROM bill_versions bv WHERE bv.bill_id = p_bill_id LIMIT 1),
    'congress_session', (SELECT bv.congress_session::text FROM bill_versions bv WHERE bv.bill_id = p_bill_id LIMIT 1)
  )
  INTO v_result;

  RETURN v_result;
END;
$$;

-- Grant to anon + authenticated (RLS on underlying tables enforced via SECURITY INVOKER)
GRANT EXECUTE ON FUNCTION get_mutation_timeline(TEXT) TO anon;
GRANT EXECUTE ON FUNCTION get_mutation_timeline(TEXT) TO authenticated;


-- ========================================================================
-- get_spending_detail: Assembles the full spending data for a bill.
-- Returns the JSON shape that PM-ST.3 SpendingData.fromJson() expects.
--
-- Auth: anon/authenticated. Executes as INVOKER so RLS policies on
-- underlying tables are enforced.
--
-- Dependencies (from PM-ST.1):
--   bill_spending_summary: VIEW over spending_data
--   get_spending_by_category(): aggregation function
-- ========================================================================

CREATE OR REPLACE FUNCTION get_spending_detail(p_bill_id TEXT)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
AS $$
DECLARE
  v_result JSONB;
  v_summary RECORD;
  v_versions JSONB;
  v_provisions JSONB;
  v_comparisons JSONB;
  v_anomalies JSONB;
  v_category_breakdown JSONB;
BEGIN
  -- Get summary
  SELECT * INTO v_summary
  FROM bill_spending_summary
  WHERE bill_id = p_bill_id;

  IF v_summary IS NULL THEN
    RETURN NULL;
  END IF;

  -- Versions (reuse from bill_versions)
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
        WHEN 'introduced' THEN 0 WHEN 'committee' THEN 1
        WHEN 'engrossed' THEN 2 WHEN 'enrolled' THEN 3 ELSE 99
      END
  ), '[]'::jsonb)
  INTO v_versions
  FROM bill_versions bv WHERE bv.bill_id = p_bill_id;

  -- Provisions (latest version)
  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'provision_id', sd.spending_id,
      'provision_title', sd.provision_title,
      'provision_index', sd.provision_index,
      'amount', sd.amount,
      'source', sd.source,
      'category', sd.category,
      'spending_delta', sd.spending_delta,
      'old_amount', sd.old_amount,
      'new_amount', sd.new_amount,
      'has_mutation_crossover', sd.has_mutation_crossover,
      'percent_of_total', sd.percent_of_total
    ) ORDER BY sd.amount DESC
  ), '[]'::jsonb)
  INTO v_provisions
  FROM spending_data sd
  WHERE sd.version_id = v_summary.latest_version_id;

  -- Comparisons (with stage ordering to match get_mutation_timeline)
  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'from_version', jsonb_build_object(
        'id', bv_from.version_id, 'bill_id', bv_from.bill_id,
        'stage', bv_from.stage, 'timestamp', bv_from.version_timestamp,
        'provision_count', bv_from.provision_count, 'label', bv_from.label
      ),
      'to_version', jsonb_build_object(
        'id', bv_to.version_id, 'bill_id', bv_to.bill_id,
        'stage', bv_to.stage, 'timestamp', bv_to.version_timestamp,
        'provision_count', bv_to.provision_count, 'label', bv_to.label
      ),
      'total_delta', sc.total_delta,
      'provisions_added', sc.provisions_added,
      'provisions_removed', sc.provisions_removed,
      'provisions_changed', sc.provisions_changed,
      'provisions', COALESCE((
        SELECT jsonb_agg(
          jsonb_build_object(
            'provision_id', sd2.spending_id,
            'provision_title', sd2.provision_title,
            'provision_index', sd2.provision_index,
            'amount', sd2.amount,
            'source', sd2.source,
            'category', sd2.category,
            'spending_delta', sd2.spending_delta,
            'old_amount', sd2.old_amount,
            'new_amount', sd2.new_amount,
            'has_mutation_crossover', sd2.has_mutation_crossover,
            'percent_of_total', sd2.percent_of_total
          ) ORDER BY sd2.amount DESC
        )
        FROM spending_data sd2
        WHERE sd2.version_id = bv_to.version_id
          AND sd2.spending_delta IS NOT NULL
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
  FROM spending_comparisons sc
  JOIN bill_versions bv_from ON bv_from.version_id = sc.from_version_id
  JOIN bill_versions bv_to ON bv_to.version_id = sc.to_version_id
  WHERE sc.bill_id = p_bill_id;

  -- Anomalies
  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'provision_id', sa.provision_id_ref,
      'reason', sa.reason,
      'magnitude', sa.magnitude,
      'amount', sa.amount
    ) ORDER BY sa.magnitude DESC
  ), '[]'::jsonb)
  INTO v_anomalies
  FROM spending_anomalies sa WHERE sa.bill_id = p_bill_id;

  -- Category breakdown (computed, not stored)
  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'category', cat.category,
      'total_amount', cat.total_amount,
      'provision_count', cat.provision_count,
      'percent_of_total', cat.percent_of_total
    ) ORDER BY cat.total_amount DESC
  ), '[]'::jsonb)
  INTO v_category_breakdown
  FROM get_spending_by_category(p_bill_id, v_summary.latest_version_id) cat;

  -- Assemble
  v_result := jsonb_build_object(
    'bill_id', p_bill_id,
    'bill_title', v_summary.bill_title,
    'total_cbo', v_summary.total_cbo,
    'total_extracted', v_summary.total_extracted,
    'source_type', v_summary.source_type,
    'provisions', v_provisions,
    'category_breakdown', v_category_breakdown,
    'versions', v_versions,
    'comparisons', v_comparisons,
    'anomalies', v_anomalies,
    'sponsor', v_summary.sponsor,
    'chamber', v_summary.chamber,
    'congress_session', v_summary.congress_session::text
  );

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION get_spending_detail(TEXT) TO anon;
GRANT EXECUTE ON FUNCTION get_spending_detail(TEXT) TO authenticated;
