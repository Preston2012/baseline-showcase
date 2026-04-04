-- ========================================================================
-- PM-MT.1  - Bill Mutation Timeline™ SQL Schema  - LOCKED
--
-- Three tables powering Mutation Timeline™:
--   1. bill_versions: Snapshot of a bill at each legislative stage
--   2. version_comparisons: Aggregate diff stats between two versions
--   3. mutation_diffs: Provision-level changes with magnitude scores
--
-- DEPENDS ON:
--   - A1 V8.0: prevent_immutable_mutation() function
--   - A1 V8.0: feature_flags table (for ENABLE_BILL_MUTATION flag)
--
-- DOES NOT:
--   - FK to statements, analyses, consensus, or bill_summaries
--   - Store embeddings (transient, discarded after magnitude computation)
--   - Duplicate Provision Drift™ data (Drift = vote-time snapshot in PD1,
--     Mutation = temporal diff across versions here. Never cross copy.)
--   - Compute dynamic thresholds (PM-MT.3 RPC handles rolling averages)
--
-- SAFETY:
--   All DDL is idempotent (IF NOT EXISTS / OR REPLACE / IF EXISTS).
--   RLS enforced + feature-flag gated at RLS level.
--   Immutability triggers block updates + deletes on bill_versions +
--     version_comparisons. mutation_diffs uses custom trigger allowing
--     spending-only backfill (CBO scores lag bill text).
--   UPDATE/DELETE privileges revoked from anon + authenticated.
--   View uses security_invoker = true + defense-in-depth flag check.
--
-- DOMAIN SEPARATION (LOCKED):
--   Drift = spatial (how far provisions stray from stated purpose)
--   Mutation = temporal (how provisions change across bill versions)
--   Spending = fiscal (dollar figures tied to provisions)
--   Same provision appearing in multiple signals = ONE converged card.
-- ========================================================================


-- ########################################################################
-- SECTION 1: FEATURE FLAG
-- ########################################################################

-- Register the feature flag for Mutation Timeline™.
-- Starts disabled. Enabled after PM-MT.2 ingestion pipeline is validated.
INSERT INTO feature_flags (flag_name, enabled, description)
VALUES (
  'ENABLE_BILL_MUTATION',
  false,
  'Gates read access to bill_versions, version_comparisons, and mutation_diffs tables. Requires PM-MT.2 ingestion pipeline active.'
)
ON CONFLICT (flag_name) DO NOTHING;


-- ########################################################################
-- SECTION 2: bill_versions TABLE
-- ########################################################################

-- A snapshot of a bill at a specific legislative stage.
-- Congress API provides text at: introduced, committee, engrossed, enrolled.
-- One row per bill per stage. Re-ingestion is idempotent.

CREATE TABLE IF NOT EXISTS bill_versions (

  -- Primary key (UUID for consistency with all BASELINE tables)
  version_id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Bill identifier (matches votes.bill_id + bill_summaries.bill_id TEXT pattern)
  bill_id           TEXT NOT NULL,

  -- Human-readable bill title (denormalized for display without joins)
  bill_title        TEXT NOT NULL,

  -- Legislative stage this snapshot represents
  stage             TEXT NOT NULL CHECK (stage IN (
                      'introduced', 'committee', 'engrossed', 'enrolled'
                    )),

  -- When this version was published/detected
  version_timestamp TIMESTAMPTZ NOT NULL,

  -- Number of provisions extracted at this stage
  provision_count   INTEGER NOT NULL DEFAULT 0,

  -- Optional human-readable label (e.g. "H.Amdt.123 applied")
  label             TEXT,

  -- Full extracted provisions snapshot for this version.
  -- Same JSONB shape as PD1 bill_summaries.provisions:
  --   [{ "title": "...", "description": "...", "category": "...", "drift_score": 0.0 }]
  -- Stored so diff computation (PM-MT.3) can compare without re-calling Gemini.
  provisions_text   JSONB NOT NULL DEFAULT '[]'::jsonb,

  -- Chamber: HOUSE or SENATE (denormalized for feed filtering)
  chamber           TEXT NOT NULL CHECK (chamber IN ('HOUSE', 'SENATE')),

  -- Congress session number (e.g. 119)
  congress_session  INTEGER NOT NULL,

  -- Sponsor name (denormalized for header display)
  sponsor           TEXT,

  -- Link to original bill text at this version stage
  source_url        TEXT NOT NULL,

  -- Ingestion metadata
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),

  -- One version per bill per stage
  CONSTRAINT uq_bill_version_stage UNIQUE (bill_id, stage),

  -- provision_count must match actual JSONB array length
  CONSTRAINT provision_count_matches_jsonb
    CHECK (provision_count = jsonb_array_length(provisions_text)),

  -- provisions_text must be a JSON array (not object/scalar)
  CONSTRAINT provisions_text_is_array
    CHECK (jsonb_typeof(provisions_text) = 'array'),

  -- congress_session must be positive
  CONSTRAINT congress_session_positive
    CHECK (congress_session > 0),

  -- provision_count non-negative
  CONSTRAINT provision_count_non_negative
    CHECK (provision_count >= 0)
);


-- ########################################################################
-- SECTION 3: bill_versions INDEXES
-- ########################################################################

-- Primary lookup by bill (all versions for a bill)
CREATE INDEX IF NOT EXISTS idx_bill_versions_bill
  ON bill_versions(bill_id);

-- Sort by timestamp (most recent versions first for feed)
CREATE INDEX IF NOT EXISTS idx_bill_versions_timestamp
  ON bill_versions(version_timestamp DESC);

-- Feed filtering: chamber + recent
CREATE INDEX IF NOT EXISTS idx_bill_versions_chamber
  ON bill_versions(chamber, version_timestamp DESC);

-- Feed filtering: congress session
CREATE INDEX IF NOT EXISTS idx_bill_versions_session
  ON bill_versions(congress_session DESC);

-- Stage lookup (all bills at a specific stage)
CREATE INDEX IF NOT EXISTS idx_bill_versions_stage
  ON bill_versions(stage, version_timestamp DESC);


-- ########################################################################
-- SECTION 4: version_comparisons TABLE
-- ########################################################################

-- Aggregate mutation statistics between two adjacent bill versions.
-- Computed by PM-MT.3 RPC. One row per version pair.
-- Stores the numbers PM-MT.4's VersionComparison.fromJson expects.

CREATE TABLE IF NOT EXISTS version_comparisons (

  -- Primary key
  comparison_id       UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Bill identifier (denormalized for direct feed queries without joining bill_versions)
  bill_id             TEXT NOT NULL,

  -- The two versions being compared
  from_version_id     UUID NOT NULL REFERENCES bill_versions(version_id) ON DELETE CASCADE,
  to_version_id       UUID NOT NULL REFERENCES bill_versions(version_id) ON DELETE CASCADE,

  -- Aggregate mutation score: percentage of bill that changed (0.0 to 1.0)
  aggregate_mutation  NUMERIC(5,4) NOT NULL DEFAULT 0.0,

  -- Provision-level change counts
  provisions_added    INTEGER NOT NULL DEFAULT 0,
  provisions_removed  INTEGER NOT NULL DEFAULT 0,
  provisions_modified INTEGER NOT NULL DEFAULT 0,
  total_provisions    INTEGER NOT NULL DEFAULT 0,

  -- Computation metadata
  computed_at         TIMESTAMPTZ NOT NULL DEFAULT now(),

  -- One comparison per version pair
  CONSTRAINT uq_version_comparison_pair UNIQUE (from_version_id, to_version_id),

  -- Versions must be different
  CONSTRAINT different_versions
    CHECK (from_version_id != to_version_id),

  -- Aggregate mutation in valid range
  CONSTRAINT aggregate_mutation_range
    CHECK (aggregate_mutation >= 0.0 AND aggregate_mutation <= 1.0),

  -- Change counts non-negative
  CONSTRAINT change_counts_non_negative
    CHECK (
      provisions_added >= 0
      AND provisions_removed >= 0
      AND provisions_modified >= 0
      AND total_provisions >= 0
    ),

  -- Total changes cannot exceed total provisions
  -- (added provisions are new, so they add to total, not limited by it)
  CONSTRAINT removed_within_total
    CHECK (provisions_removed <= total_provisions),

  -- Modified cannot exceed total provisions
  CONSTRAINT modified_within_total
    CHECK (provisions_modified <= total_provisions)
);


-- ########################################################################
-- SECTION 5: version_comparisons INDEXES
-- ########################################################################

-- Feed query: high-mutation comparisons for a bill
CREATE INDEX IF NOT EXISTS idx_comparisons_bill
  ON version_comparisons(bill_id);

-- Feed surfacing: highest mutation first (dynamic threshold queries)
CREATE INDEX IF NOT EXISTS idx_comparisons_mutation_desc
  ON version_comparisons(aggregate_mutation DESC)
  WHERE aggregate_mutation > 0.0;

-- Time-based feed: most recently computed
CREATE INDEX IF NOT EXISTS idx_comparisons_computed
  ON version_comparisons(computed_at DESC);

-- Join optimization: from_version lookup
CREATE INDEX IF NOT EXISTS idx_comparisons_from_version
  ON version_comparisons(from_version_id);

-- Join optimization: to_version lookup
CREATE INDEX IF NOT EXISTS idx_comparisons_to_version
  ON version_comparisons(to_version_id);


-- ########################################################################
-- SECTION 6: mutation_diffs TABLE
-- ########################################################################

-- Provision-level mutation between two bill versions.
-- One row per provision change. Linked to a version_comparison.
-- Stores the fields PM-MT.4's MutationDiff.fromJson expects.

CREATE TABLE IF NOT EXISTS mutation_diffs (

  -- Primary key
  diff_id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Parent comparison this diff belongs to
  comparison_id       UUID NOT NULL REFERENCES version_comparisons(comparison_id) ON DELETE CASCADE,

  -- Bill identifier (denormalized for direct queries)
  bill_id             TEXT NOT NULL,

  -- Provision identification
  provision_title     TEXT NOT NULL,
  provision_index     INTEGER NOT NULL,

  -- Type of change
  diff_type           TEXT NOT NULL CHECK (diff_type IN ('added', 'removed', 'modified')),

  -- Semantic distance magnitude (0.0 to 1.0)
  -- For 'added': always 1.0 (entirely new content)
  -- For 'removed': always 1.0 (entirely gone)
  -- For 'modified': cosine distance between old and new embeddings
  magnitude           NUMERIC(5,4) NOT NULL DEFAULT 0.0,

  -- Provision category (from Gemini extraction: e.g. "healthcare", "defense")
  category            TEXT,

  -- Text snapshots for display (nullable: may be redacted at lower tiers)
  old_text            TEXT,
  new_text            TEXT,

  -- Spending crossover fields (denormalized from spending_data for convergence)
  -- Populated by PM-MT.3 RPC when spending data exists for this provision.
  -- Enables "provision added AND carries $2.3B" feed moments.
  spending_delta      NUMERIC,
  old_spending        NUMERIC,
  new_spending        NUMERIC,

  -- Computation metadata
  created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),

  -- Magnitude in valid range
  CONSTRAINT magnitude_range
    CHECK (magnitude >= 0.0 AND magnitude <= 1.0),

  -- Provision index non-negative
  CONSTRAINT provision_index_non_negative
    CHECK (provision_index >= 0),

  -- Spending amounts non-negative (delta can be negative: spending decreased)
  CONSTRAINT spending_amounts_non_negative
    CHECK (
      (old_spending IS NULL OR old_spending >= 0)
      AND (new_spending IS NULL OR new_spending >= 0)
    ),

  -- Added provisions must have new_text, removed must have old_text,
  -- modified must have both
  CONSTRAINT text_consistency
    CHECK (
      (diff_type = 'added' AND new_text IS NOT NULL)
      OR (diff_type = 'removed' AND old_text IS NOT NULL)
      OR (diff_type = 'modified' AND old_text IS NOT NULL AND new_text IS NOT NULL)
    ),

  -- Added = magnitude 1.0, removed = magnitude 1.0
  CONSTRAINT added_removed_magnitude
    CHECK (
      (diff_type IN ('added', 'removed') AND magnitude = 1.0)
      OR diff_type = 'modified'
    )
);


-- ########################################################################
-- SECTION 7: mutation_diffs INDEXES
-- ########################################################################

-- Primary lookup: all diffs for a comparison
CREATE INDEX IF NOT EXISTS idx_diffs_comparison
  ON mutation_diffs(comparison_id);

-- Composite: anomaly subquery optimization (comparison + magnitude filter)
CREATE INDEX IF NOT EXISTS idx_diffs_comparison_magnitude
  ON mutation_diffs(comparison_id, magnitude DESC);

-- Direct bill lookup (feed queries)
CREATE INDEX IF NOT EXISTS idx_diffs_bill
  ON mutation_diffs(bill_id);

-- High-magnitude diffs (anomaly detection, feed surfacing)
CREATE INDEX IF NOT EXISTS idx_diffs_magnitude_desc
  ON mutation_diffs(magnitude DESC)
  WHERE magnitude >= 0.40;

-- Spending crossover detection (convergence feed moments)
CREATE INDEX IF NOT EXISTS idx_diffs_spending_crossover
  ON mutation_diffs(bill_id, magnitude DESC)
  WHERE spending_delta IS NOT NULL;

-- Type filtering
CREATE INDEX IF NOT EXISTS idx_diffs_type
  ON mutation_diffs(diff_type);


-- ########################################################################
-- SECTION 8: IMMUTABILITY TRIGGERS
-- ########################################################################

-- Bill versions are immutable public records.
-- Diffs and comparisons are computed facts.
-- Once written, never changed.

DROP TRIGGER IF EXISTS trigger_bill_versions_immutability ON bill_versions;
CREATE TRIGGER trigger_bill_versions_immutability
  BEFORE UPDATE OR DELETE ON bill_versions
  FOR EACH ROW
  EXECUTE FUNCTION prevent_immutable_mutation();

DROP TRIGGER IF EXISTS trigger_version_comparisons_immutability ON version_comparisons;
CREATE TRIGGER trigger_version_comparisons_immutability
  BEFORE UPDATE OR DELETE ON version_comparisons
  FOR EACH ROW
  EXECUTE FUNCTION prevent_immutable_mutation();

DROP TRIGGER IF EXISTS trigger_mutation_diffs_immutability ON mutation_diffs;
-- Custom trigger: allows spending-field-only updates (CBO backfill).
-- CBO scores frequently arrive days/weeks after bill text ingestion.
-- PM-ST.2 must be able to backfill spending_delta/old_spending/new_spending
-- without violating immutability on all other columns.
CREATE OR REPLACE FUNCTION enforce_mutation_diff_immutability()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'mutation_diffs rows cannot be deleted';
  END IF;
  -- UPDATE path: allow spending-only backfill
  IF NEW.diff_id != OLD.diff_id
    OR NEW.comparison_id != OLD.comparison_id
    OR NEW.bill_id != OLD.bill_id
    OR NEW.provision_title != OLD.provision_title
    OR NEW.provision_index != OLD.provision_index
    OR NEW.diff_type != OLD.diff_type
    OR NEW.magnitude != OLD.magnitude
    OR NEW.category IS DISTINCT FROM OLD.category
    OR NEW.old_text IS DISTINCT FROM OLD.old_text
    OR NEW.new_text IS DISTINCT FROM OLD.new_text
    OR NEW.created_at != OLD.created_at
  THEN
    RAISE EXCEPTION 'Only spending fields may be updated on mutation_diffs';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_mutation_diffs_immutability ON mutation_diffs;
CREATE TRIGGER trigger_mutation_diffs_immutability
  BEFORE UPDATE OR DELETE ON mutation_diffs
  FOR EACH ROW
  EXECUTE FUNCTION enforce_mutation_diff_immutability();


-- ########################################################################
-- SECTION 9: ROW-LEVEL SECURITY
-- ########################################################################

-- All three tables: RLS enabled + forced.
-- Read: gated by ENABLE_BILL_MUTATION feature flag.
-- Write: service_role only (PM-MT.2 ingestion + PM-MT.3 RPC).

-- === bill_versions ===

ALTER TABLE bill_versions ENABLE ROW LEVEL SECURITY;
ALTER TABLE bill_versions FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS bill_versions_public_read ON bill_versions;
CREATE POLICY bill_versions_public_read
  ON bill_versions
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM feature_flags
      WHERE flag_name = 'ENABLE_BILL_MUTATION'
        AND enabled = true
    )
  );

REVOKE INSERT ON bill_versions FROM anon;
REVOKE INSERT ON bill_versions FROM authenticated;
GRANT INSERT ON bill_versions TO service_role;

REVOKE UPDATE ON bill_versions FROM anon;
REVOKE UPDATE ON bill_versions FROM authenticated;
REVOKE DELETE ON bill_versions FROM anon;
REVOKE DELETE ON bill_versions FROM authenticated;

-- === version_comparisons ===

ALTER TABLE version_comparisons ENABLE ROW LEVEL SECURITY;
ALTER TABLE version_comparisons FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS version_comparisons_public_read ON version_comparisons;
CREATE POLICY version_comparisons_public_read
  ON version_comparisons
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM feature_flags
      WHERE flag_name = 'ENABLE_BILL_MUTATION'
        AND enabled = true
    )
  );

REVOKE INSERT ON version_comparisons FROM anon;
REVOKE INSERT ON version_comparisons FROM authenticated;
GRANT INSERT ON version_comparisons TO service_role;

REVOKE UPDATE ON version_comparisons FROM anon;
REVOKE UPDATE ON version_comparisons FROM authenticated;
REVOKE DELETE ON version_comparisons FROM anon;
REVOKE DELETE ON version_comparisons FROM authenticated;

-- === mutation_diffs ===

ALTER TABLE mutation_diffs ENABLE ROW LEVEL SECURITY;
ALTER TABLE mutation_diffs FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS mutation_diffs_public_read ON mutation_diffs;
CREATE POLICY mutation_diffs_public_read
  ON mutation_diffs
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM feature_flags
      WHERE flag_name = 'ENABLE_BILL_MUTATION'
        AND enabled = true
    )
  );

REVOKE INSERT ON mutation_diffs FROM anon;
REVOKE INSERT ON mutation_diffs FROM authenticated;
GRANT INSERT ON mutation_diffs TO service_role;

REVOKE UPDATE ON mutation_diffs FROM anon;
REVOKE UPDATE ON mutation_diffs FROM authenticated;
-- Column-level UPDATE for spending backfill (CBO scores lag bill text)
GRANT UPDATE (spending_delta, old_spending, new_spending) ON mutation_diffs TO service_role;
REVOKE DELETE ON mutation_diffs FROM anon;
REVOKE DELETE ON mutation_diffs FROM authenticated;


-- ########################################################################
-- SECTION 10: FEED SURFACING VIEWS
-- ########################################################################

-- Materialized-view-style helper for feed queries.
-- Not a materialized view (Supabase free tier limitations) but a regular
-- view that PM-MT.3 and F3.3 can query for high-mutation feed cards.

CREATE OR REPLACE VIEW mutation_feed_candidates
  WITH (security_invoker = true)
AS
SELECT
  vc.comparison_id,
  vc.bill_id,
  bv_from.bill_title,
  bv_from.chamber,
  bv_from.congress_session,
  bv_from.sponsor,
  bv_from.stage AS from_stage,
  bv_to.stage AS to_stage,
  vc.aggregate_mutation,
  vc.provisions_added,
  vc.provisions_removed,
  vc.provisions_modified,
  vc.total_provisions,
  vc.computed_at,
  bv_to.version_timestamp AS latest_version_timestamp,
  -- Anomaly count: diffs with magnitude >= 0.60 in this comparison
  (
    SELECT COUNT(*)
    FROM mutation_diffs md
    WHERE md.comparison_id = vc.comparison_id
      AND md.magnitude >= 0.60
  ) AS anomaly_count,
  -- Spending crossover count: diffs with spending data
  (
    SELECT COUNT(*)
    FROM mutation_diffs md
    WHERE md.comparison_id = vc.comparison_id
      AND md.spending_delta IS NOT NULL
  ) AS spending_crossover_count
FROM version_comparisons vc
JOIN bill_versions bv_from ON bv_from.version_id = vc.from_version_id
JOIN bill_versions bv_to ON bv_to.version_id = vc.to_version_id
WHERE vc.aggregate_mutation > 0.0
  -- Defense-in-depth: mirror table RLS feature flag check
  AND EXISTS (
    SELECT 1 FROM feature_flags
    WHERE flag_name = 'ENABLE_BILL_MUTATION'
      AND enabled = true
  )
ORDER BY vc.aggregate_mutation DESC, vc.computed_at DESC;


-- ########################################################################
-- SECTION 11: ROLLING AVERAGE SUPPORT
-- ########################################################################

-- Helper function for dynamic threshold computation.
-- Returns the rolling average mutation score across all comparisons
-- within a lookback window. PM-MT.3 RPC uses this to determine
-- whether a new comparison's mutation score is "above normal."
--
-- Cold start: returns NULL when fewer than 5 comparisons exist,
-- signaling PM-MT.3 to use static fallback thresholds.

CREATE OR REPLACE FUNCTION get_mutation_rolling_average(
  p_lookback_days INTEGER DEFAULT 90
)
RETURNS NUMERIC(5,4)
LANGUAGE sql
STABLE
AS $$
  SELECT
    CASE
      WHEN COUNT(*) < 5 THEN NULL  -- Cold start: not enough data
      ELSE AVG(aggregate_mutation)::NUMERIC(5,4)
    END
  FROM version_comparisons
  WHERE computed_at >= now() - (p_lookback_days || ' days')::interval;
$$;


-- ########################################################################
-- SECTION 12: RECENT MUTATION ALERTS RPC
-- ########################################################################

-- Feed-facing RPC: returns recent high-mutation comparisons for feed cards.
-- Mirrors PD1's get_recent_drift_alerts() pattern.
-- Called by F3.3 FeedService for mutation card type.
-- Tier gating at app layer (F6.3: billMutation feature flag).

CREATE OR REPLACE FUNCTION get_recent_mutation_alerts(
  p_lookback_days INTEGER DEFAULT 7,
  p_limit INTEGER DEFAULT 20
)
RETURNS TABLE (
  comparison_id       UUID,
  bill_id             TEXT,
  bill_title          TEXT,
  chamber             TEXT,
  congress_session    INTEGER,
  sponsor             TEXT,
  from_stage          TEXT,
  to_stage            TEXT,
  aggregate_mutation  NUMERIC(5,4),
  provisions_added    INTEGER,
  provisions_removed  INTEGER,
  provisions_modified INTEGER,
  total_provisions    INTEGER,
  anomaly_count       BIGINT,
  spending_crossover_count BIGINT,
  computed_at         TIMESTAMPTZ
)
LANGUAGE sql
STABLE
SECURITY INVOKER
AS $$
  WITH rolling AS (
    SELECT get_mutation_rolling_average(90) AS avg_mutation
  ),
  threshold AS (
    SELECT
      CASE
        -- Cold start: use static fallback (15% aggregate mutation)
        WHEN r.avg_mutation IS NULL THEN 0.15
        -- Dynamic: anything above rolling average is noteworthy
        ELSE GREATEST(r.avg_mutation, 0.10)
      END AS min_mutation
    FROM rolling r
  )
  SELECT
    mfc.comparison_id,
    mfc.bill_id,
    mfc.bill_title,
    mfc.chamber,
    mfc.congress_session,
    mfc.sponsor,
    mfc.from_stage,
    mfc.to_stage,
    mfc.aggregate_mutation,
    mfc.provisions_added,
    mfc.provisions_removed,
    mfc.provisions_modified,
    mfc.total_provisions,
    mfc.anomaly_count,
    mfc.spending_crossover_count,
    mfc.computed_at
  FROM mutation_feed_candidates mfc, threshold t
  WHERE mfc.aggregate_mutation >= t.min_mutation
    AND mfc.latest_version_timestamp >= now() - (p_lookback_days || ' days')::interval
  ORDER BY mfc.aggregate_mutation DESC, mfc.computed_at DESC
  LIMIT p_limit;
$$;


-- ########################################################################
-- SECTION 13: CLEANUP / SAFETY
-- ########################################################################

-- Grant RPC execution to anon + authenticated (RLS still gates the data)
GRANT EXECUTE ON FUNCTION get_mutation_rolling_average(INTEGER) TO anon;
GRANT EXECUTE ON FUNCTION get_mutation_rolling_average(INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION get_recent_mutation_alerts(INTEGER, INTEGER) TO anon;
GRANT EXECUTE ON FUNCTION get_recent_mutation_alerts(INTEGER, INTEGER) TO authenticated;

-- Grant view access (RLS on underlying tables still applies)
GRANT SELECT ON mutation_feed_candidates TO anon;
GRANT SELECT ON mutation_feed_candidates TO authenticated;
