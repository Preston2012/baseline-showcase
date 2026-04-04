-- ========================================================================
-- PM-ST.1  - Spending Scope™ SQL Schema  - LOCKED
--
-- Four tables powering Spending Scope™:
--   1. bill_spending_summary: Per-bill aggregate spending (CBO + extracted)
--   2. spending_data: Per-provision spending at a specific bill version
--   3. spending_comparisons: Spending deltas between two bill versions
--   4. spending_anomalies: Outsized / scope-mismatch spending flags
--
-- Plus one RPC for category aggregation (computed at query time).
--
-- DEPENDS ON:
--   - A1 V8.0: prevent_immutable_mutation() function, feature_flags table
--   - PM-MT.1: bill_versions table (version_id FK target)
--
-- DOES NOT:
--   - FK to statements, analyses, consensus, or bill_summaries
--   - Store embeddings (spending is dollar data, not semantic)
--   - Duplicate Provision Drift™ or Mutation data
--   - Compute mutation diffs (PM-MT.3 owns that, reads spending for crossover)
--
-- DOMAIN SEPARATION (LOCKED):
--   Drift = spatial (how far provisions stray from stated purpose)
--   Mutation = temporal (how provisions change across bill versions)
--   Spending = fiscal (dollar figures tied to provisions)
--   Same provision, multiple signals = ONE converged card in feed.
--
-- SAFETY:
--   All DDL idempotent. RLS + feature flag gated. Immutability enforced.
--   spending_data uses custom trigger allowing crossover flag backfill.
--   UPDATE/DELETE revoked from anon + authenticated.
--   View uses security_invoker = true + defense-in-depth flag check.
--   All read-path RPCs use SECURITY INVOKER.
-- ========================================================================


-- ########################################################################
-- SECTION 1: FEATURE FLAG
-- ########################################################################

INSERT INTO feature_flags (flag_name, enabled, description)
VALUES (
  'ENABLE_SPENDING_TRACKER',
  false,
  'Gates read access to spending_data, spending_comparisons, spending_anomalies, and bill_spending_summary tables. Requires PM-ST.2 ingestion pipeline active.'
)
ON CONFLICT (flag_name) DO NOTHING;


-- ########################################################################
-- SECTION 2: bill_spending_summary TABLE
-- ########################################################################

-- Per-bill aggregate spending figures.
-- One row per bill. Stores totals from CBO and/or extraction.
-- PM-ST.3 SpendingData top-level fields consume this.
-- Updated when new version spending is ingested (PM-ST.2 recalculates).

CREATE TABLE IF NOT EXISTS bill_spending_summary (

  -- Primary key
  summary_id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Bill identifier (matches bill_versions.bill_id, bill_summaries.bill_id)
  bill_id           TEXT NOT NULL UNIQUE,

  -- Bill title (denormalized for feed display)
  bill_title        TEXT NOT NULL,

  -- Aggregate CBO score (total across all provisions, latest version)
  -- NULL if no CBO data available
  total_cbo         NUMERIC,

  -- Aggregate extracted spending (from Gemini bill text parsing)
  -- NULL if extraction found no dollar figures
  total_extracted   NUMERIC,

  -- Which source is canonical for this bill
  source_type       TEXT NOT NULL CHECK (source_type IN ('cbo', 'extracted', 'both')),

  -- Chamber + session (denormalized for feed filtering)
  chamber           TEXT NOT NULL CHECK (chamber IN ('HOUSE', 'SENATE')),
  congress_session  INTEGER NOT NULL,

  -- Sponsor (denormalized for header display)
  sponsor           TEXT,

  -- Latest version this summary reflects
  latest_version_id UUID REFERENCES bill_versions(version_id) ON DELETE SET NULL,

  -- Aggregate feed columns (updated by PM-ST.2 ingestion + PM-MT.3 crossover)
  -- Hard columns avoid correlated subqueries in feed view.
  latest_delta      NUMERIC DEFAULT 0,
  anomaly_count     INTEGER NOT NULL DEFAULT 0,
  crossover_count   INTEGER NOT NULL DEFAULT 0,

  -- Metadata
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),

  -- Congress session positive
  CONSTRAINT spending_summary_session_positive
    CHECK (congress_session > 0),

  -- Source type must match which totals are populated
  CONSTRAINT spending_summary_source_validation
    CHECK (
      (source_type = 'cbo' AND total_cbo IS NOT NULL AND total_extracted IS NULL)
      OR (source_type = 'extracted' AND total_extracted IS NOT NULL AND total_cbo IS NULL)
      OR (source_type = 'both' AND total_cbo IS NOT NULL AND total_extracted IS NOT NULL)
    ),

  -- Aggregate counts non-negative
  CONSTRAINT spending_summary_counts_non_negative
    CHECK (anomaly_count >= 0 AND crossover_count >= 0)
);


-- ########################################################################
-- SECTION 3: bill_spending_summary INDEXES
-- ########################################################################

CREATE INDEX IF NOT EXISTS idx_spending_summary_bill
  ON bill_spending_summary(bill_id);

CREATE INDEX IF NOT EXISTS idx_spending_summary_total_cbo_desc
  ON bill_spending_summary(total_cbo DESC NULLS LAST)
  WHERE total_cbo IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_spending_summary_total_extracted_desc
  ON bill_spending_summary(total_extracted DESC NULLS LAST)
  WHERE total_extracted IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_spending_summary_chamber
  ON bill_spending_summary(chamber, updated_at DESC);

CREATE INDEX IF NOT EXISTS idx_spending_summary_session
  ON bill_spending_summary(congress_session DESC);


-- ########################################################################
-- SECTION 4: spending_data TABLE
-- ########################################################################

-- Per-provision spending at a specific bill version.
-- One row per provision per version. Core granular data.
-- PM-ST.3 ProvisionSpending.fromJson consumes these rows.

CREATE TABLE IF NOT EXISTS spending_data (

  -- Primary key (also serves as provision_id in Dart model)
  spending_id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Bill identifier (denormalized for direct queries)
  bill_id               TEXT NOT NULL,

  -- Which version this spending record belongs to
  version_id            UUID NOT NULL REFERENCES bill_versions(version_id) ON DELETE CASCADE,

  -- Provision identification
  provision_title       TEXT NOT NULL,
  provision_index       INTEGER NOT NULL,

  -- Dollar amount for this provision
  amount                NUMERIC NOT NULL DEFAULT 0,

  -- Data source
  source                TEXT NOT NULL CHECK (source IN ('cbo', 'extracted', 'both')),

  -- Provision category (matches PD1 provision categories)
  category              TEXT CHECK (category IN (
                          'defense', 'healthcare', 'education', 'infrastructure',
                          'agriculture', 'energy', 'commerce', 'technology',
                          'judiciary', 'social_services', 'environment',
                          'foreign_affairs', 'taxation', 'general'
                        )),

  -- Version delta fields (populated when comparing to prior version)
  -- NULL on first version (introduced), filled on subsequent versions
  spending_delta        NUMERIC,
  old_amount            NUMERIC,
  new_amount            NUMERIC,

  -- Convergence flag: does this provision also appear in mutation_diffs?
  -- Set by PM-MT.3 during diff computation
  has_mutation_crossover BOOLEAN NOT NULL DEFAULT false,

  -- Pre-computed percentage of bill's total spending
  -- Avoids recomputing at render time for sonar display
  percent_of_total      NUMERIC(5,4),

  -- Metadata
  created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),

  -- Provision index non-negative
  CONSTRAINT spending_provision_index_non_negative
    CHECK (provision_index >= 0),

  -- percent_of_total in valid range when set
  CONSTRAINT spending_percent_range
    CHECK (percent_of_total IS NULL OR (percent_of_total >= 0.0 AND percent_of_total <= 1.0)),

  -- One spending record per provision per version
  CONSTRAINT uq_spending_provision_version
    UNIQUE (version_id, provision_index)
);


-- ########################################################################
-- SECTION 5: spending_data INDEXES
-- ########################################################################

-- Primary lookup: all spending for a bill
CREATE INDEX IF NOT EXISTS idx_spending_data_bill
  ON spending_data(bill_id);

-- Version-specific lookup
CREATE INDEX IF NOT EXISTS idx_spending_data_version
  ON spending_data(version_id);

-- High-spend provisions (feed surfacing)
CREATE INDEX IF NOT EXISTS idx_spending_data_amount_desc
  ON spending_data(amount DESC)
  WHERE amount > 0;

-- Category filtering (ballast gauge breakdown)
CREATE INDEX IF NOT EXISTS idx_spending_data_category
  ON spending_data(category)
  WHERE category IS NOT NULL;

-- Crossover detection (provisions with both spending + mutation signals)
CREATE INDEX IF NOT EXISTS idx_spending_data_crossover
  ON spending_data(bill_id, amount DESC)
  WHERE has_mutation_crossover = true;

-- Delta detection (version-over-version spending changes)
CREATE INDEX IF NOT EXISTS idx_spending_data_delta
  ON spending_data(bill_id)
  WHERE spending_delta IS NOT NULL;


-- ########################################################################
-- SECTION 6: spending_comparisons TABLE
-- ########################################################################

-- Spending deltas between two bill versions (aggregate level).
-- One row per version pair per bill.
-- PM-ST.3 SpendingComparison.fromJson consumes these.
-- Provision-level deltas live on spending_data rows.

CREATE TABLE IF NOT EXISTS spending_comparisons (

  -- Primary key
  spending_comparison_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Bill identifier (denormalized)
  bill_id               TEXT NOT NULL,

  -- The two versions being compared
  from_version_id       UUID NOT NULL REFERENCES bill_versions(version_id) ON DELETE CASCADE,
  to_version_id         UUID NOT NULL REFERENCES bill_versions(version_id) ON DELETE CASCADE,

  -- Aggregate spending delta (dollars gained or lost between versions)
  total_delta           NUMERIC NOT NULL DEFAULT 0,

  -- Provision-level change counts (spending-specific)
  provisions_added      INTEGER NOT NULL DEFAULT 0,
  provisions_removed    INTEGER NOT NULL DEFAULT 0,
  provisions_changed    INTEGER NOT NULL DEFAULT 0,

  -- Metadata
  computed_at           TIMESTAMPTZ NOT NULL DEFAULT now(),

  -- One comparison per version pair
  CONSTRAINT uq_spending_comparison_pair
    UNIQUE (from_version_id, to_version_id),

  -- Versions must be different
  CONSTRAINT spending_different_versions
    CHECK (from_version_id != to_version_id),

  -- Change counts non-negative
  CONSTRAINT spending_change_counts_non_negative
    CHECK (
      provisions_added >= 0
      AND provisions_removed >= 0
      AND provisions_changed >= 0
    )
);


-- ########################################################################
-- SECTION 7: spending_comparisons INDEXES
-- ########################################################################

CREATE INDEX IF NOT EXISTS idx_spending_comparisons_bill
  ON spending_comparisons(bill_id);

CREATE INDEX IF NOT EXISTS idx_spending_comparisons_delta_desc
  ON spending_comparisons(total_delta DESC)
  WHERE total_delta != 0;

CREATE INDEX IF NOT EXISTS idx_spending_comparisons_computed
  ON spending_comparisons(computed_at DESC);

CREATE INDEX IF NOT EXISTS idx_spending_comparisons_from
  ON spending_comparisons(from_version_id);

CREATE INDEX IF NOT EXISTS idx_spending_comparisons_to
  ON spending_comparisons(to_version_id);


-- ########################################################################
-- SECTION 8: spending_anomalies TABLE
-- ########################################################################

-- Outsized or scope-mismatched spending provisions.
-- Detected by PM-ST.2 ingestion or PM-MT.3 crossover computation.
-- PM-ST.3 SpendingAnomaly.fromJson consumes these.

CREATE TABLE IF NOT EXISTS spending_anomalies (

  -- Primary key
  anomaly_id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Bill identifier (denormalized)
  bill_id               TEXT NOT NULL,

  -- The specific spending record that triggered the anomaly
  provision_id_ref      UUID NOT NULL REFERENCES spending_data(spending_id) ON DELETE CASCADE,

  -- Human-readable reason for anomaly flag
  -- e.g. "Exceeds scope threshold", "Outsized relative to bill total",
  --      "Cross-version spike: $1.2B to $3.8B"
  reason                TEXT NOT NULL DEFAULT 'Exceeds scope threshold',

  -- Severity magnitude (0.0 to 1.0, same scale as mutation magnitude)
  magnitude             NUMERIC(5,4) NOT NULL DEFAULT 0.0,

  -- Dollar amount of the anomalous provision
  amount                NUMERIC NOT NULL DEFAULT 0,

  -- Metadata
  created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),

  -- Magnitude in valid range
  CONSTRAINT anomaly_magnitude_range
    CHECK (magnitude >= 0.0 AND magnitude <= 1.0)
);


-- ########################################################################
-- SECTION 9: spending_anomalies INDEXES
-- ########################################################################

CREATE INDEX IF NOT EXISTS idx_spending_anomalies_bill
  ON spending_anomalies(bill_id);

CREATE INDEX IF NOT EXISTS idx_spending_anomalies_provision
  ON spending_anomalies(provision_id_ref);

CREATE INDEX IF NOT EXISTS idx_spending_anomalies_magnitude_desc
  ON spending_anomalies(magnitude DESC);

CREATE INDEX IF NOT EXISTS idx_spending_anomalies_amount_desc
  ON spending_anomalies(amount DESC);


-- ########################################################################
-- SECTION 10: IMMUTABILITY TRIGGERS
-- ########################################################################

-- spending_data: custom trigger allowing crossover flag backfill.
-- PM-MT.3 sets has_mutation_crossover AFTER spending data is written.
-- All other fields remain immutable.
DROP TRIGGER IF EXISTS trigger_spending_data_immutability ON spending_data;

CREATE OR REPLACE FUNCTION enforce_spending_data_immutability()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'spending_data rows cannot be deleted';
  END IF;
  -- UPDATE path: allow crossover flag backfill only
  IF NEW.spending_id != OLD.spending_id
    OR NEW.bill_id != OLD.bill_id
    OR NEW.version_id != OLD.version_id
    OR NEW.provision_title != OLD.provision_title
    OR NEW.provision_index != OLD.provision_index
    OR NEW.amount != OLD.amount
    OR NEW.source != OLD.source
    OR NEW.category IS DISTINCT FROM OLD.category
    OR NEW.spending_delta IS DISTINCT FROM OLD.spending_delta
    OR NEW.old_amount IS DISTINCT FROM OLD.old_amount
    OR NEW.new_amount IS DISTINCT FROM OLD.new_amount
    OR NEW.percent_of_total IS DISTINCT FROM OLD.percent_of_total
    OR NEW.created_at != OLD.created_at
  THEN
    RAISE EXCEPTION 'Only has_mutation_crossover may be updated on spending_data';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_spending_data_immutability ON spending_data;
CREATE TRIGGER trigger_spending_data_immutability
  BEFORE UPDATE OR DELETE ON spending_data
  FOR EACH ROW
  EXECUTE FUNCTION enforce_spending_data_immutability();

-- spending_comparisons: computed facts
DROP TRIGGER IF EXISTS trigger_spending_comparisons_immutability ON spending_comparisons;
CREATE TRIGGER trigger_spending_comparisons_immutability
  BEFORE UPDATE OR DELETE ON spending_comparisons
  FOR EACH ROW
  EXECUTE FUNCTION prevent_immutable_mutation();

-- spending_anomalies: computed flags
DROP TRIGGER IF EXISTS trigger_spending_anomalies_immutability ON spending_anomalies;
CREATE TRIGGER trigger_spending_anomalies_immutability
  BEFORE UPDATE OR DELETE ON spending_anomalies
  FOR EACH ROW
  EXECUTE FUNCTION prevent_immutable_mutation();

-- bill_spending_summary: EXCEPTION  - mutable.
-- Updated when new version spending is ingested. latest_version_id and
-- totals change as new data arrives. No immutability trigger.
-- UPDATE granted to service_role only (see Section 11).


-- ########################################################################
-- SECTION 11: ROW-LEVEL SECURITY
-- ########################################################################

-- All tables: RLS enabled + forced.
-- Read: gated by ENABLE_SPENDING_TRACKER feature flag.
-- Write: service_role only.

-- === bill_spending_summary ===

ALTER TABLE bill_spending_summary ENABLE ROW LEVEL SECURITY;
ALTER TABLE bill_spending_summary FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS bill_spending_summary_public_read ON bill_spending_summary;
CREATE POLICY bill_spending_summary_public_read
  ON bill_spending_summary
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM feature_flags
      WHERE flag_name = 'ENABLE_SPENDING_TRACKER'
        AND enabled = true
    )
  );

REVOKE INSERT ON bill_spending_summary FROM anon;
REVOKE INSERT ON bill_spending_summary FROM authenticated;
GRANT INSERT ON bill_spending_summary TO service_role;

-- Summary is mutable (updated on new version ingestion)
REVOKE UPDATE ON bill_spending_summary FROM anon;
REVOKE UPDATE ON bill_spending_summary FROM authenticated;
GRANT UPDATE ON bill_spending_summary TO service_role;

REVOKE DELETE ON bill_spending_summary FROM anon;
REVOKE DELETE ON bill_spending_summary FROM authenticated;

-- === spending_data ===

ALTER TABLE spending_data ENABLE ROW LEVEL SECURITY;
ALTER TABLE spending_data FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS spending_data_public_read ON spending_data;
CREATE POLICY spending_data_public_read
  ON spending_data
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM feature_flags
      WHERE flag_name = 'ENABLE_SPENDING_TRACKER'
        AND enabled = true
    )
  );

REVOKE INSERT ON spending_data FROM anon;
REVOKE INSERT ON spending_data FROM authenticated;
GRANT INSERT ON spending_data TO service_role;

REVOKE UPDATE ON spending_data FROM anon;
REVOKE UPDATE ON spending_data FROM authenticated;
-- Column-level UPDATE for crossover flag backfill (PM-MT.3 sets post-insert)
GRANT UPDATE (has_mutation_crossover) ON spending_data TO service_role;
REVOKE DELETE ON spending_data FROM anon;
REVOKE DELETE ON spending_data FROM authenticated;

-- === spending_comparisons ===

ALTER TABLE spending_comparisons ENABLE ROW LEVEL SECURITY;
ALTER TABLE spending_comparisons FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS spending_comparisons_public_read ON spending_comparisons;
CREATE POLICY spending_comparisons_public_read
  ON spending_comparisons
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM feature_flags
      WHERE flag_name = 'ENABLE_SPENDING_TRACKER'
        AND enabled = true
    )
  );

REVOKE INSERT ON spending_comparisons FROM anon;
REVOKE INSERT ON spending_comparisons FROM authenticated;
GRANT INSERT ON spending_comparisons TO service_role;

REVOKE UPDATE ON spending_comparisons FROM anon;
REVOKE UPDATE ON spending_comparisons FROM authenticated;
REVOKE DELETE ON spending_comparisons FROM anon;
REVOKE DELETE ON spending_comparisons FROM authenticated;

-- === spending_anomalies ===

ALTER TABLE spending_anomalies ENABLE ROW LEVEL SECURITY;
ALTER TABLE spending_anomalies FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS spending_anomalies_public_read ON spending_anomalies;
CREATE POLICY spending_anomalies_public_read
  ON spending_anomalies
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM feature_flags
      WHERE flag_name = 'ENABLE_SPENDING_TRACKER'
        AND enabled = true
    )
  );

REVOKE INSERT ON spending_anomalies FROM anon;
REVOKE INSERT ON spending_anomalies FROM authenticated;
GRANT INSERT ON spending_anomalies TO service_role;

REVOKE UPDATE ON spending_anomalies FROM anon;
REVOKE UPDATE ON spending_anomalies FROM authenticated;
REVOKE DELETE ON spending_anomalies FROM anon;
REVOKE DELETE ON spending_anomalies FROM authenticated;


-- ########################################################################
-- SECTION 12: FEED SURFACING VIEW
-- ########################################################################

-- High-spend bills for feed card surfacing.
-- Reads aggregate columns directly from bill_spending_summary.
-- No correlated subqueries: aggregates maintained by PM-ST.2 + PM-MT.3.

CREATE OR REPLACE VIEW spending_feed_candidates
  WITH (security_invoker = true)
AS
SELECT
  bss.summary_id,
  bss.bill_id,
  bss.bill_title,
  bss.chamber,
  bss.congress_session,
  bss.sponsor,
  bss.source_type,
  COALESCE(bss.total_cbo, bss.total_extracted, 0) AS canonical_total,
  bss.total_cbo,
  bss.total_extracted,
  bss.updated_at,
  bss.latest_delta,
  bss.anomaly_count,
  bss.crossover_count
FROM bill_spending_summary bss
WHERE COALESCE(bss.total_cbo, bss.total_extracted, 0) != 0
  -- Defense-in-depth: mirror table RLS feature flag check
  AND EXISTS (
    SELECT 1 FROM feature_flags
    WHERE flag_name = 'ENABLE_SPENDING_TRACKER'
      AND enabled = true
  )
ORDER BY ABS(COALESCE(bss.total_cbo, bss.total_extracted, 0)) DESC, bss.updated_at DESC;


-- ########################################################################
-- SECTION 13: CATEGORY AGGREGATION RPC
-- ########################################################################

-- Computes per-category spending breakdown for a bill at a specific version.
-- PM-ST.3's ballast gauge (CategorySpendingAggregate) consumes this.
-- Not stored: computed at query time (categories may change with re-extraction).

CREATE OR REPLACE FUNCTION get_spending_by_category(
  p_bill_id TEXT,
  p_version_id UUID DEFAULT NULL
)
RETURNS TABLE (
  category        TEXT,
  total_amount    NUMERIC,
  provision_count BIGINT,
  percent_of_total NUMERIC(5,4)
)
LANGUAGE sql
STABLE
SECURITY INVOKER
AS $$
  WITH version_filter AS (
    -- If version specified, use it. Otherwise use latest version for this bill.
    SELECT COALESCE(
      p_version_id,
      (
        SELECT bv.version_id
        FROM bill_versions bv
        WHERE bv.bill_id = p_bill_id
        ORDER BY bv.version_timestamp DESC
        LIMIT 1
      )
    ) AS vid
  ),
  provisions AS (
    SELECT
      COALESCE(sd.category, 'general') AS cat,
      sd.amount
    FROM spending_data sd, version_filter vf
    WHERE sd.bill_id = p_bill_id
      AND sd.version_id = vf.vid
      AND sd.amount > 0
  ),
  bill_total AS (
    SELECT NULLIF(SUM(amount), 0) AS total FROM provisions
  )
  SELECT
    p.cat AS category,
    SUM(p.amount) AS total_amount,
    COUNT(*) AS provision_count,
    CASE
      WHEN bt.total IS NULL THEN 0.0
      ELSE (SUM(p.amount) / bt.total)::NUMERIC(5,4)
    END AS percent_of_total
  FROM provisions p, bill_total bt
  GROUP BY p.cat, bt.total
  ORDER BY SUM(p.amount) DESC;
$$;


-- ########################################################################
-- SECTION 14: RECENT SPENDING ALERTS RPC
-- ########################################################################

-- Feed-facing RPC: returns recent high-spend bills for feed cards.
-- Mirrors PM-MT.1's get_recent_mutation_alerts() pattern.
-- Called by F3.3 FeedService for spending card type.
-- Tier gating at app layer (F6.3: spendingTracker feature flag).

CREATE OR REPLACE FUNCTION get_spending_rolling_average(
  p_lookback_days INTEGER DEFAULT 90
)
RETURNS NUMERIC
LANGUAGE sql
STABLE
AS $$
  SELECT
    CASE
      WHEN COUNT(*) < 5 THEN NULL  -- Cold start
      ELSE AVG(COALESCE(total_cbo, total_extracted, 0))
    END
  FROM bill_spending_summary
  WHERE updated_at >= now() - (p_lookback_days || ' days')::interval;
$$;

CREATE OR REPLACE FUNCTION get_recent_spending_alerts(
  p_lookback_days INTEGER DEFAULT 7,
  p_limit INTEGER DEFAULT 20
)
RETURNS TABLE (
  summary_id        UUID,
  bill_id           TEXT,
  bill_title        TEXT,
  chamber           TEXT,
  congress_session  INTEGER,
  sponsor           TEXT,
  source_type       TEXT,
  canonical_total   NUMERIC,
  total_cbo         NUMERIC,
  total_extracted   NUMERIC,
  latest_delta      NUMERIC,
  anomaly_count     BIGINT,
  crossover_count   BIGINT,
  updated_at        TIMESTAMPTZ
)
LANGUAGE sql
STABLE
SECURITY INVOKER
AS $$
  WITH rolling AS (
    SELECT get_spending_rolling_average(90) AS avg_spending
  )
  SELECT
    sfc.summary_id,
    sfc.bill_id,
    sfc.bill_title,
    sfc.chamber,
    sfc.congress_session,
    sfc.sponsor,
    sfc.source_type,
    sfc.canonical_total,
    sfc.total_cbo,
    sfc.total_extracted,
    sfc.latest_delta,
    sfc.anomaly_count,
    sfc.crossover_count,
    sfc.updated_at
  FROM spending_feed_candidates sfc, rolling r
  WHERE sfc.updated_at >= now() - (p_lookback_days || ' days')::interval
    AND (
      -- Cold start: surface anything with spending data
      r.avg_spending IS NULL
      -- Dynamic: above-average spending OR has anomalies OR has crossover
      OR sfc.canonical_total > r.avg_spending
      OR sfc.anomaly_count > 0
      OR sfc.crossover_count > 0
    )
  ORDER BY sfc.canonical_total DESC, sfc.updated_at DESC
  LIMIT p_limit;
$$;


-- ########################################################################
-- SECTION 15: GRANTS
-- ########################################################################

-- RPCs callable by anon + authenticated (RLS gates the underlying data)
GRANT EXECUTE ON FUNCTION get_spending_by_category(TEXT, UUID) TO anon;
GRANT EXECUTE ON FUNCTION get_spending_by_category(TEXT, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION get_spending_rolling_average(INTEGER) TO anon;
GRANT EXECUTE ON FUNCTION get_spending_rolling_average(INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION get_recent_spending_alerts(INTEGER, INTEGER) TO anon;
GRANT EXECUTE ON FUNCTION get_recent_spending_alerts(INTEGER, INTEGER) TO authenticated;

-- View access (underlying table RLS still applies)
GRANT SELECT ON spending_feed_candidates TO anon;
GRANT SELECT ON spending_feed_candidates TO authenticated;
