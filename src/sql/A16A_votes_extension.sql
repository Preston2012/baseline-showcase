-- ========================================================================
-- A16A  - Votes SQL Extension
-- Version: V1.0.2
-- Depends on: A1 V8.0 (votes table, figures table, feature_flags table)
--
-- Adds serving + insertion RPCs on top of the A1 votes table.
-- All reads are feature-flag-gated (defense in depth).
-- All reads use SECURITY INVOKER (rely on A1 RLS).
-- All writes are service_role only (SECURITY DEFINER).
-- US Congress scope only (HOUSE / SENATE).
--
-- V1.0.2 CHANGELOG:
-- - BLOCKER: is_enabled → enabled (matches A1 feature_flags schema)
-- - BLOCKER: insert_vote() now idempotent (ON CONFLICT DO NOTHING + SELECT)
-- - BLOCKER: Batch UUID parsing wrapped with regex pre-validation
-- - SECURITY: Public read RPCs changed to SECURITY INVOKER
-- - Standardized role check: current_setting → auth.role()
-- - Offset clamped to >= 0
-- - Chamber filter validated when provided (non-null)
-- ========================================================================
--
-- ############################################################################
-- SECTION 1: INSERTION RPC
--
-- ############################################################################
-- ── insert_vote()──────────────────────────────────────────────────────────
-- Service-role only. Inserts a single vote record.
-- Returns the vote_id (new or existing if duplicate).
-- IDEMPOTENT: ON CONFLICT DO NOTHING  - safe for pipeline replays.
--
-- Validates:
-- 1. Feature flag ENABLE_VOTE_TRACKING is enabled
-- 2. figure_id exists in figures table
-- 3. vote enum is valid
-- 4. chamber enum is valid
-- 5. bill_id / bill_title / source_url non-empty
-- 6. source_url starts with http(s)://
-- 7. congress_session positive integer
-- ========================================================================
CREATE OR REPLACE FUNCTION insert_vote(
p_figure_id UUID,
p_bill_id TEXT,
p_bill_title TEXT,
p_vote TEXT,
p_vote_date DATE,
p_chamber TEXT,
p_congress_session INTEGER,
p_source_url TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
v_vote_id UUID;
v_flag_enabled BOOLEAN;
BEGIN
-- ── Guard: service_role only───────────────────────────────────────────
IF auth.role() IS DISTINCT FROM 'service_role' THEN
RAISE EXCEPTION '[insert_vote] Forbidden: requires service_role';
END IF;
-- ── Guard: feature flag────────────────────────────────────────────────
SELECT enabled INTO v_flag_enabled
FROM feature_flags
WHERE flag_name = 'ENABLE_VOTE_TRACKING';
IF v_flag_enabled IS NOT TRUE THEN
RAISE EXCEPTION '[insert_vote] ENABLE_VOTE_TRACKING is disabled';
END IF;
-- ── Guard: figure exists───────────────────────────────────────────────
IF NOT EXISTS (SELECT 1 FROM figures WHERE figure_id = p_figure_id) THEN
RAISE EXCEPTION '[insert_vote] figure_id % not found', p_figure_id;
END IF;
-- ── Guard: input validation────────────────────────────────────────────
IF p_vote NOT IN ('YEA', 'NAY', 'PRESENT', 'NOT_VOTING') THEN
RAISE EXCEPTION '[insert_vote] Invalid vote value: %', p_vote;
END IF;
IF p_chamber NOT IN ('HOUSE', 'SENATE') THEN
RAISE EXCEPTION '[insert_vote] Invalid chamber: %', p_chamber;
END IF;
IF p_bill_id IS NULL OR trim(p_bill_id) = '' THEN
RAISE EXCEPTION '[insert_vote] bill_id is required';
END IF;
IF p_bill_title IS NULL OR trim(p_bill_title) = '' THEN
RAISE EXCEPTION '[insert_vote] bill_title is required';
END IF;
IF p_source_url IS NULL OR trim(p_source_url) = '' THEN
RAISE EXCEPTION '[insert_vote] source_url is required';
END IF;
IF NOT (trim(p_source_url) ~ '^https?://') THEN
RAISE EXCEPTION '[insert_vote] source_url must start with http:// or https://: %',
p_source_url;
END IF;
IF p_vote_date IS NULL THEN
RAISE EXCEPTION '[insert_vote] vote_date is required';
END IF;
IF p_congress_session IS NULL OR p_congress_session < 1 THEN
RAISE EXCEPTION '[insert_vote] congress_session must be a positive integer';
END IF;
-- ── Insert (idempotent  - skip if duplicate) ────────────────────────────
INSERT INTO votes (
figure_id,
bill_id,
bill_title,
vote,
vote_date,
chamber,
congress_session,
source_url
) VALUES (
p_figure_id,
trim(p_bill_id),
trim(p_bill_title),
p_vote,
p_vote_date,
p_chamber,
p_congress_session,
trim(p_source_url)
)
ON CONFLICT (figure_id, bill_id) DO NOTHING
RETURNING vote_id INTO v_vote_id;
-- ── If duplicate, fetch existing vote_id ───────────────────────────────
IF v_vote_id IS NULL THEN
SELECT v.vote_id INTO v_vote_id
FROM votes v
WHERE v.figure_id = p_figure_id
AND v.bill_id = trim(p_bill_id);
RAISE LOG '[insert_vote] Duplicate skipped  - existing vote_id=% for figure=% bill=%',
v_vote_id, p_figure_id, p_bill_id;
ELSE
RAISE LOG '[insert_vote] Inserted vote_id=% for figure=% bill=%',
v_vote_id, p_figure_id, p_bill_id;
END IF;
RETURN v_vote_id;
END;
$$;
-- Restrict direct execution to service_role
REVOKE ALL ON FUNCTION insert_vote(UUID, TEXT, TEXT, TEXT, DATE, TEXT, INTEGER,
TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION insert_vote(UUID, TEXT, TEXT, TEXT, DATE, TEXT, INTEGER,
TEXT) FROM anon;
REVOKE ALL ON FUNCTION insert_vote(UUID, TEXT, TEXT, TEXT, DATE, TEXT, INTEGER,
TEXT) FROM authenticated;
GRANT EXECUTE ON FUNCTION insert_vote(UUID, TEXT, TEXT, TEXT, DATE, TEXT,
INTEGER, TEXT) TO service_role;
--
-- ############################################################################
-- SECTION 2: BATCH INSERTION RPC
--
-- ############################################################################
-- ── insert_votes_batch()───────────────────────────────────────────────────
-- Service-role only. Inserts multiple votes in a single transaction.
-- Accepts a JSONB array of vote objects.
-- Returns count of newly inserted rows (excludes duplicates).
-- Skips duplicates (ON CONFLICT DO NOTHING)  - idempotent for re-runs.
--
-- Expected JSONB shape per element:
-- {
-- "figure_id": "uuid",
-- "bill_id": "HR-1234-118",
-- "bill_title": "...",
-- "vote": "YEA",
-- "vote_date": "2025-01-15",
-- "chamber": "HOUSE",
-- "congress_session": 119,
-- "source_url": "https://congress.gov/..."
-- }
-- ========================================================================
CREATE OR REPLACE FUNCTION insert_votes_batch(
p_votes JSONB
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
v_count INTEGER := 0;
v_flag_enabled BOOLEAN;
v_elem JSONB;
v_figure_id_str TEXT;
v_vote TEXT;
v_chamber TEXT;
BEGIN
-- ── Guard: service_role only───────────────────────────────────────────
IF auth.role() IS DISTINCT FROM 'service_role' THEN
RAISE EXCEPTION '[insert_votes_batch] Forbidden: requires service_role';
END IF;
-- ── Guard: feature flag────────────────────────────────────────────────
SELECT enabled INTO v_flag_enabled
FROM feature_flags
WHERE flag_name = 'ENABLE_VOTE_TRACKING';
IF v_flag_enabled IS NOT TRUE THEN
RAISE EXCEPTION '[insert_votes_batch] ENABLE_VOTE_TRACKING is disabled';
END IF;
-- ── Guard: input is array──────────────────────────────────────────────
IF jsonb_typeof(p_votes) != 'array' THEN
RAISE EXCEPTION '[insert_votes_batch] p_votes must be a JSON array';
END IF;
IF jsonb_array_length(p_votes) = 0 THEN
RETURN 0;
END IF;
-- ── Guard: batch size limit (500 per call) ─────────────────────────────
IF jsonb_array_length(p_votes) > 500 THEN
RAISE EXCEPTION '[insert_votes_batch] Max 500 votes per batch (got %)',
jsonb_array_length(p_votes);
END IF;
-- ── Validate each element before inserting any ─────────────────────────
FOR v_elem IN SELECT * FROM jsonb_array_elements(p_votes)
LOOP
-- Safe UUID extraction: validate format before cast
v_figure_id_str := v_elem ->> 'figure_id';
IF v_figure_id_str IS NULL OR trim(v_figure_id_str) = '' THEN
RAISE EXCEPTION '[insert_votes_batch] Missing figure_id in element: %',
v_elem::TEXT;
END IF;
IF NOT (v_figure_id_str ~
'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') THEN
RAISE EXCEPTION '[insert_votes_batch] Invalid UUID format for figure_id: %',
v_figure_id_str;
END IF;
IF NOT EXISTS (SELECT 1 FROM figures WHERE figure_id = v_figure_id_str::UUID)
THEN
RAISE EXCEPTION '[insert_votes_batch] figure_id % not found', v_figure_id_str;
END IF;
v_vote := v_elem ->> 'vote';
v_chamber := v_elem ->> 'chamber';
IF v_vote IS NULL OR v_vote NOT IN ('YEA', 'NAY', 'PRESENT', 'NOT_VOTING') THEN
RAISE EXCEPTION '[insert_votes_batch] Invalid vote: %', v_vote;
END IF;
IF v_chamber IS NULL OR v_chamber NOT IN ('HOUSE', 'SENATE') THEN
RAISE EXCEPTION '[insert_votes_batch] Invalid chamber: %', v_chamber;
END IF;
IF (v_elem ->> 'bill_id') IS NULL OR trim(v_elem ->> 'bill_id') = '' THEN
RAISE EXCEPTION '[insert_votes_batch] Missing bill_id';
END IF;
IF (v_elem ->> 'bill_title') IS NULL OR trim(v_elem ->> 'bill_title') = '' THEN
RAISE EXCEPTION '[insert_votes_batch] Missing bill_title';
END IF;
IF (v_elem ->> 'source_url') IS NULL OR trim(v_elem ->> 'source_url') = '' THEN
RAISE EXCEPTION '[insert_votes_batch] Missing source_url';
END IF;
IF NOT (trim(v_elem ->> 'source_url') ~ '^https?://') THEN
RAISE EXCEPTION '[insert_votes_batch] source_url must start with http:// or https://';
END IF;
IF (v_elem ->> 'vote_date') IS NULL THEN
RAISE EXCEPTION '[insert_votes_batch] Missing vote_date';
END IF;
IF (v_elem ->> 'congress_session') IS NULL
OR trim(v_elem ->> 'congress_session') = ''
OR NOT (trim(v_elem ->> 'congress_session') ~ '^\d+$')
OR (v_elem ->> 'congress_session')::INTEGER < 1 THEN
RAISE EXCEPTION '[insert_votes_batch] Invalid congress_session';
END IF;
END LOOP;
-- ── Bulk insert (skip duplicates)──────────────────────────────────────
INSERT INTO votes (
figure_id,
bill_id,
bill_title,
vote,
vote_date,
chamber,
congress_session,
source_url
)
SELECT
(elem ->> 'figure_id')::UUID,
trim(elem ->> 'bill_id'),
trim(elem ->> 'bill_title'),
elem ->> 'vote',
(elem ->> 'vote_date')::DATE,
elem ->> 'chamber',
(elem ->> 'congress_session')::INTEGER,
trim(elem ->> 'source_url')
FROM jsonb_array_elements(p_votes) AS elem
ON CONFLICT (figure_id, bill_id) DO NOTHING;
GET DIAGNOSTICS v_count = ROW_COUNT;
RAISE LOG '[insert_votes_batch] Inserted % of % votes (% skipped as duplicates)',
v_count, jsonb_array_length(p_votes), jsonb_array_length(p_votes) - v_count;
RETURN v_count;
END;
$$;
REVOKE ALL ON FUNCTION insert_votes_batch(JSONB) FROM PUBLIC;
REVOKE ALL ON FUNCTION insert_votes_batch(JSONB) FROM anon;
REVOKE ALL ON FUNCTION insert_votes_batch(JSONB) FROM authenticated;
GRANT EXECUTE ON FUNCTION insert_votes_batch(JSONB) TO service_role;
--
-- ############################################################################
-- SECTION 3: PUBLIC READ RPCs (Flag-Gated, SECURITY INVOKER)
--
-- ############################################################################
-- ── get_votes_for_figure()─────────────────────────────────────────────────
-- Public read. Returns votes for a specific figure.
-- SECURITY INVOKER  - relies on A1 RLS policies for access control.
-- Feature-flag-gated: returns empty if ENABLE_VOTE_TRACKING is off.
-- Supports optional filters: chamber, congress_session, date range.
-- Ordered by vote_date DESC (most recent first).
-- Default limit 100, max 500.
-- ========================================================================
CREATE OR REPLACE FUNCTION get_votes_for_figure(
p_figure_id UUID,
p_chamber TEXT DEFAULT NULL,
p_congress_session INTEGER DEFAULT NULL,
p_from_date DATE DEFAULT NULL,
p_to_date DATE DEFAULT NULL,
p_limit INTEGER DEFAULT 100,
p_offset INTEGER DEFAULT 0
)
RETURNS TABLE (
vote_id UUID,
figure_id UUID,
bill_id TEXT,
bill_title TEXT,
vote TEXT,
vote_date DATE,
chamber TEXT,
congress_session INTEGER,
source_url TEXT,
created_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
STABLE
AS $$
DECLARE
v_flag_enabled BOOLEAN;
v_safe_limit INTEGER;
BEGIN
-- ── Guard: feature flag────────────────────────────────────────────────
SELECT enabled INTO v_flag_enabled
FROM feature_flags
WHERE flag_name = 'ENABLE_VOTE_TRACKING';
IF v_flag_enabled IS NOT TRUE THEN
-- Return empty result set  - feature not enabled
RETURN;
END IF;
-- ── Guard: chamber validation (if provided) ───────────────────────────
IF p_chamber IS NOT NULL AND p_chamber NOT IN ('HOUSE', 'SENATE') THEN
RAISE EXCEPTION '[get_votes_for_figure] Invalid chamber filter: %. Must be HOUSE or
SENATE.',
p_chamber;
END IF;
-- ── Clamp limit and offset─────────────────────────────────────────────
v_safe_limit := LEAST(GREATEST(COALESCE(p_limit, 100), 1), 500);
-- ── Query──────────────────────────────────────────────────────────────
RETURN QUERY
SELECT
v.vote_id,
v.figure_id,
v.bill_id,
v.bill_title,
v.vote,
v.vote_date,
v.chamber,
v.congress_session,
v.source_url,
v.created_at
FROM votes v
WHERE v.figure_id = p_figure_id
AND (p_chamber IS NULL OR v.chamber = p_chamber)
AND (p_congress_session IS NULL OR v.congress_session = p_congress_session)
AND (p_from_date IS NULL OR v.vote_date >= p_from_date)
AND (p_to_date IS NULL OR v.vote_date <= p_to_date)
ORDER BY v.vote_date DESC, v.created_at DESC
LIMIT v_safe_limit
OFFSET GREATEST(COALESCE(p_offset, 0), 0);
END;
$$;
-- Public read access
GRANT EXECUTE ON FUNCTION get_votes_for_figure(UUID, TEXT, INTEGER, DATE, DATE,
INTEGER, INTEGER) TO anon;
GRANT EXECUTE ON FUNCTION get_votes_for_figure(UUID, TEXT, INTEGER, DATE, DATE,
INTEGER, INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION get_votes_for_figure(UUID, TEXT, INTEGER, DATE, DATE,
INTEGER, INTEGER) TO service_role;
-- ── get_vote_summary_for_figure()──────────────────────────────────────────
-- Public read. Returns aggregated vote counts per figure.
-- SECURITY INVOKER  - relies on A1 RLS policies.
-- Grouped by chamber + congress_session.
-- Feature-flag-gated.
-- ========================================================================
CREATE OR REPLACE FUNCTION get_vote_summary_for_figure(
p_figure_id UUID,
p_chamber TEXT DEFAULT NULL,
p_congress_session INTEGER DEFAULT NULL
)
RETURNS TABLE (
chamber TEXT,
congress_session INTEGER,
yea_count BIGINT,
nay_count BIGINT,
present_count BIGINT,
not_voting_count BIGINT,
total_votes BIGINT
)
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
STABLE
AS $$
DECLARE
v_flag_enabled BOOLEAN;
BEGIN
-- ── Guard: feature flag────────────────────────────────────────────────
SELECT enabled INTO v_flag_enabled
FROM feature_flags
WHERE flag_name = 'ENABLE_VOTE_TRACKING';
IF v_flag_enabled IS NOT TRUE THEN
RETURN;
END IF;
-- ── Guard: chamber validation (if provided) ───────────────────────────
IF p_chamber IS NOT NULL AND p_chamber NOT IN ('HOUSE', 'SENATE') THEN
RAISE EXCEPTION '[get_vote_summary_for_figure] Invalid chamber filter: %. Must be
HOUSE or SENATE.',
p_chamber;
END IF;
-- ── Aggregation────────────────────────────────────────────────────────
RETURN QUERY
SELECT
v.chamber,
v.congress_session,
COUNT(*) FILTER (WHERE v.vote = 'YEA') AS yea_count,
COUNT(*) FILTER (WHERE v.vote = 'NAY') AS nay_count,
COUNT(*) FILTER (WHERE v.vote = 'PRESENT') AS present_count,
COUNT(*) FILTER (WHERE v.vote = 'NOT_VOTING') AS not_voting_count,
COUNT(*) AS total_votes
FROM votes v
WHERE v.figure_id = p_figure_id
AND (p_chamber IS NULL OR v.chamber = p_chamber)
AND (p_congress_session IS NULL OR v.congress_session = p_congress_session)
GROUP BY v.chamber, v.congress_session
ORDER BY v.congress_session DESC, v.chamber;
END;
$$;
GRANT EXECUTE ON FUNCTION get_vote_summary_for_figure(UUID, TEXT, INTEGER) TO
anon;
GRANT EXECUTE ON FUNCTION get_vote_summary_for_figure(UUID, TEXT, INTEGER) TO
authenticated;
GRANT EXECUTE ON FUNCTION get_vote_summary_for_figure(UUID, TEXT, INTEGER) TO
service_role;
--
-- ############################################################################
-- SECTION 4: BILL LOOKUP RPC
--
-- ############################################################################
-- ── get_votes_for_bill()───────────────────────────────────────────────────
-- Public read. Returns all tracked figures' votes on a specific bill.
-- SECURITY INVOKER  - relies on A1 RLS policies.
-- Useful for "how did everyone vote on X" queries.
-- Feature-flag-gated.
-- ========================================================================
CREATE OR REPLACE FUNCTION get_votes_for_bill(
p_bill_id TEXT
)
RETURNS TABLE (
vote_id UUID,
figure_id UUID,
figure_name TEXT,
vote TEXT,
vote_date DATE,
chamber TEXT,
congress_session INTEGER,
source_url TEXT
)
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
STABLE
AS $$
DECLARE
v_flag_enabled BOOLEAN;
BEGIN
-- ── Guard: feature flag────────────────────────────────────────────────
SELECT enabled INTO v_flag_enabled
FROM feature_flags
WHERE flag_name = 'ENABLE_VOTE_TRACKING';
IF v_flag_enabled IS NOT TRUE THEN
RETURN;
END IF;
IF p_bill_id IS NULL OR trim(p_bill_id) = '' THEN
RAISE EXCEPTION '[get_votes_for_bill] bill_id is required';
END IF;
RETURN QUERY
SELECT
v.vote_id,
v.figure_id,
f.name AS figure_name,
v.vote,
v.vote_date,
v.chamber,
v.congress_session,
v.source_url
FROM votes v
JOIN figures f ON f.figure_id = v.figure_id
WHERE v.bill_id = trim(p_bill_id)
ORDER BY v.chamber, f.name;
END;
$$;
GRANT EXECUTE ON FUNCTION get_votes_for_bill(TEXT) TO anon;
GRANT EXECUTE ON FUNCTION get_votes_for_bill(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION get_votes_for_bill(TEXT) TO service_role;
--
-- ############################################################################
-- SECTION 5: ADDITIONAL INDEXES
--
-- ############################################################################
-- Composite index for the common query pattern: figure + date range + chamber
-- Covers get_votes_for_figure() primary access pattern
CREATE INDEX IF NOT EXISTS idx_votes_figure_date_chamber
ON votes(figure_id, vote_date DESC, chamber);
-- Congress session lookup (for summary queries)
CREATE INDEX IF NOT EXISTS idx_votes_figure_session
ON votes(figure_id, congress_session DESC);
-- ========================================================================
-- END A16A  - Votes SQL Extension V1.0.2
-- ========================================================================
