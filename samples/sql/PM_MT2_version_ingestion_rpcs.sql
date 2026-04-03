-- Returns bill_ids we should check for new versions.
-- Sources: bills already in bill_versions + bills in votes table.
-- Used by n8n workflow to know which bills to poll Congress API for.
--
-- SECURITY DEFINER rationale: Called by service_role only (n8n workflow).
-- Reads from bill_versions + votes which have RLS. DEFINER ensures
-- the RPC can read regardless of RLS state. GRANT restricted to
-- service_role only. No client exposure.

CREATE OR REPLACE FUNCTION get_tracked_bills(
  p_congress_session INTEGER DEFAULT 119
)
RETURNS TABLE (
  bill_id          TEXT,
  bill_number      TEXT,
  chamber_code     TEXT,
  congress_session INTEGER,
  has_versions     BOOLEAN
)
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  WITH bills_from_versions AS (
    SELECT DISTINCT bill_id
    FROM bill_versions
    WHERE congress_session = p_congress_session
  ),
  bills_from_votes AS (
    SELECT DISTINCT bill_id
    FROM votes
    WHERE congress_session = p_congress_session
  ),
  all_bills AS (
    SELECT bill_id FROM bills_from_versions
    UNION
    SELECT bill_id FROM bills_from_votes
  )
  SELECT
    ab.bill_id,
    -- Extract bill number: "H.R. 1234" -> "1234", "S. 567" -> "567"
    regexp_replace(ab.bill_id, '^(H\.R\.|S\.|H\.Res\.|S\.Res\.|H\.J\.Res\.|S\.J\.Res\.)\s*', '') AS bill_number,
    -- Map to Congress API chamber code: "H.R." -> "hr", "S." -> "s"
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
    EXISTS (SELECT 1 FROM bills_from_versions bfv WHERE bfv.bill_id = ab.bill_id) AS has_versions
  FROM all_bills ab
  ORDER BY ab.bill_id;
$$;

-- Service-role only. No client access.
REVOKE ALL ON FUNCTION get_tracked_bills(INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION get_tracked_bills(INTEGER) TO service_role;
