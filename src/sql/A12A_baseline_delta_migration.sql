-- ========================================================================
-- A12A v1.0.2: MIGRATION — Baseline Delta Backfill (Baseline V1.4) — FINAL
-- File: migrations/add_baseline_delta_backfill.sql
--
-- Allows retroactive computation of baseline_delta for statements embedded
-- before 30 prior statements existed. Opt-in only, service-role only.
--
-- FIXES APPLIED (V1.0.0 → V1.0.1):
-- B1: Added topics to pinned columns in both trigger paths
-- B2: This is the CANONICAL trigger definition — A1 should reference, not duplicate
-- B3: RPC changed to SECURITY INVOKER (service_role bypasses RLS already)
-- H1: v_backfill_candidates filters f.is_active = true
-- H3: Added pgvector extension guard
-- H4: Documented window size / threshold coupling with A4
--
-- FIXES APPLIED (V1.0.1 → V1.0.2 — RECONCILED FROM GPT + GROK AUDITS):
-- 1: Trigger rewritten using NEW := OLD pattern (schema-future-proof)
-- 2: baseline_delta precision documented (confirm column type against A1)
--
-- CROSS-ARTIFACT DEPENDENCIES:
-- A1: statements table, figures table (this migration owns trg_statements_immutable)
-- A4: generate-embedding uses same window=50, threshold=30 for baseline_delta
-- pgvector: Required for <=> cosine distance operator
--
-- FLAGS FOR A1 CONFIRMATION:
-- - Verify statements.extraction_metadata column name matches
-- - Verify baseline_delta column type (NUMERIC → ROUND(...,2) is correct;
-- if INTEGER, change to ROUND(...,0)::int)
--
-- SAFETY:
-- Immutability trigger uses NEW := OLD then selectively allows changes.
-- Any new column added to statements is automatically protected.
-- Backfill RPC is SECURITY INVOKER, REVOKE'd from PUBLIC.
-- Idempotent + concurrency-safe (UPDATE ... AND baseline_delta IS NULL).
-- ========================================================================
-- ── Step 0a: pgvector guard──────────────────────────────────────────────────
DO $$
BEGIN
IF NOT EXISTS (
SELECT 1 FROM pg_extension WHERE extname = 'vector'
) THEN
RAISE EXCEPTION 'pgvector extension required. Run: CREATE EXTENSION IF NOT
EXISTS vector;';
END IF;
END $$;
-- ── Step 0b: Range guard─────────────────────────────────────────────────────
DO $$
BEGIN
IF NOT EXISTS (
SELECT 1
FROM pg_constraint
WHERE conname = 'statements_baseline_delta_range'
) THEN
ALTER TABLE statements
ADD CONSTRAINT statements_baseline_delta_range
CHECK (baseline_delta IS NULL OR (baseline_delta >= 0 AND baseline_delta <= 100));
END IF;
END $$;
-- ── Step 1: CANONICAL immutability trigger───────────────────────────────────
-- V1.0.2 FIX (1): Uses NEW := OLD pattern. Any new column added to statements
-- is automatically pinned. Only explicitly allowed mutations pass through.
--
-- Allowed mutations:
-- 1. is_revoked flip (+ revoked_at, revocation_reason)
-- 2. embedding write-once (NULL → value)
-- 3. baseline_delta write-once (NULL → value)
-- Everything else is blocked by default via NEW := OLD.
DROP TRIGGER IF EXISTS trg_statements_immutable ON statements;
CREATE OR REPLACE FUNCTION prevent_statement_updates()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
-- Capture the incoming mutation requests BEFORE pinning
v_new_is_revoked BOOLEAN := NEW.is_revoked;
v_new_revoked_at TIMESTAMPTZ := NEW.revoked_at;
v_new_revocation_reason TEXT := NEW.revocation_reason;
v_new_embedding vector := NEW.embedding;
v_new_baseline_delta NUMERIC := NEW.baseline_delta;
BEGIN
-- Pin ALL columns to OLD values (schema-future-proof)
NEW := OLD;
-- ── Path 1: Revocation──────────────────────────────────────────────
IF OLD.is_revoked IS DISTINCT FROM v_new_is_revoked THEN
NEW.is_revoked := v_new_is_revoked;
NEW.revoked_at := v_new_revoked_at;
NEW.revocation_reason := v_new_revocation_reason;
RETURN NEW;
END IF;
-- ── Path 2: Embedding write-once (NULL → value) ─────────────────────
IF OLD.embedding IS NULL AND v_new_embedding IS NOT NULL THEN
NEW.embedding := v_new_embedding;
RETURN NEW;
END IF;
-- ── Path 3: Baseline delta backfill (NULL → value, write-once) ──────
IF OLD.baseline_delta IS NULL AND v_new_baseline_delta IS NOT NULL THEN
IF v_new_baseline_delta < 0 OR v_new_baseline_delta > 100 THEN
RAISE EXCEPTION 'baseline_delta must be between 0 and 100';
END IF;
NEW.baseline_delta := v_new_baseline_delta;
RETURN NEW;
END IF;
-- No allowed mutation matched
RAISE EXCEPTION 'statements table is immutable. Allowed: is_revoked flip, embedding
write-once (NULL→value), baseline_delta write-once (NULL→value)';
END;
$$;
DROP TRIGGER IF EXISTS trg_statements_immutable ON statements;
CREATE TRIGGER trg_statements_immutable
BEFORE UPDATE ON statements
FOR EACH ROW
EXECUTE FUNCTION prevent_statement_updates();
COMMENT ON FUNCTION prevent_statement_updates IS
'CANONICAL immutability trigger for statements. Uses NEW := OLD (schema-future-proof).
Allows: (1) is_revoked flip, (2) embedding write-once, (3) baseline_delta write-once. All other
columns/new columns are automatically pinned.';
-- ── Step 2: Backfill RPC─────────────────────────────────────────────────────
-- Window=50, threshold=30 — matches A4 generate-embedding.
-- If A4 changes these values, this RPC MUST be updated to match.
-- V1.0.2 FIX (2): baseline_delta ROUND(..., 2) assumes NUMERIC column type.
-- If column is INTEGER, change to ROUND(..., 0)::int. Confirm against A1.
CREATE OR REPLACE FUNCTION backfill_baseline_delta(
p_figure_id UUID,
p_limit INTEGER DEFAULT 50
)
RETURNS JSONB
LANGUAGE plpgsql
VOLATILE
SECURITY INVOKER
SET search_path = public
AS $$
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
statement_id,
figure_id,
embedding,
ingestion_time
FROM statements
WHERE figure_id = p_figure_id
AND baseline_delta IS NULL
AND embedding IS NOT NULL
AND is_revoked = false
ORDER BY ingestion_time ASC
LIMIT p_limit
LOOP
WITH baseline_window AS (
SELECT embedding
FROM statements
WHERE figure_id = v_statement.figure_id
AND statement_id <> v_statement.statement_id
AND embedding IS NOT NULL
AND is_revoked = false
AND ingestion_time < v_statement.ingestion_time
ORDER BY ingestion_time DESC
LIMIT 50
),
distances AS (
-- pgvector <=> cosine distance: 0-2 range (0=identical)
-- Normalized embeddings (OpenAI) produce 0-1 range
SELECT (v_statement.embedding <=> embedding) AS distance
FROM baseline_window
)
SELECT
COUNT(*)::integer,
AVG(distance)
INTO v_window_size, v_avg_distance
FROM distances;
IF v_window_size >= 30 THEN
v_baseline_delta := ROUND(LEAST(100, GREATEST(0, v_avg_distance *
100))::numeric, 2);
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
ELSE format('Backfilled %s statements, skipped %s', v_updated_count,
v_skipped_count)
END
);
END;
$$;
REVOKE ALL ON FUNCTION backfill_baseline_delta(UUID, INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION backfill_baseline_delta(UUID, INTEGER) TO service_role;
COMMENT ON FUNCTION backfill_baseline_delta IS
'Retroactively compute baseline_delta for embedded statements where baseline_delta IS
NULL. Write-once via trigger. Requires >=30 prior embedded statements. Window=50,
threshold=30 (coupled with A4).';
-- ── Step 3: Safety view──────────────────────────────────────────────────────
CREATE OR REPLACE VIEW v_backfill_candidates AS
SELECT
s.figure_id,
f.name AS figure_name,
COUNT(*) AS statements_missing_baseline,
MIN(s.ingestion_time) AS earliest_statement,
MAX(s.ingestion_time) AS latest_statement,
(
SELECT COUNT(*)
FROM statements s2
WHERE s2.figure_id = s.figure_id
AND s2.embedding IS NOT NULL
AND s2.is_revoked = false
) AS total_embedded_statements
FROM statements s
JOIN figures f ON f.figure_id = s.figure_id
AND f.is_active = true
WHERE s.baseline_delta IS NULL
AND s.embedding IS NOT NULL
AND s.is_revoked = false
GROUP BY s.figure_id, f.name
ORDER BY statements_missing_baseline DESC;
GRANT SELECT ON v_backfill_candidates TO service_role;
COMMENT ON VIEW v_backfill_candidates IS
'Active figures with embedded statements missing baseline_delta.';
-- ── Step 4: Perf index───────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_statements_backfill_scan
ON statements (figure_id, ingestion_time ASC)
WHERE baseline_delta IS NULL
AND embedding IS NOT NULL
AND is_revoked = false;
