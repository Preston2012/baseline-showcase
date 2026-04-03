-- ========================================================================
-- BASELINE V1.4 — A5A MANUAL POC INGESTION LAYER (FINAL / DEPLOY-READY v1.4.4)
--
-- Changes from v1.4.3:
-- - TOPICS SUPPORT: Extract topics TEXT[] from A2 output per statement
-- - TOPICS VALIDATION: 1-3 items, must match A1 enum (fail-fast before insert)
-- - Insert topics into statements.topics column
--
-- Changes from v1.4.2:
-- - BLOCKER FIX: SELECT requires status='processing' only (state machine fix)
-- - BLOCKER FIX: quote_position validated against A2 enum {beginning,middle,end}
-- - BLOCKER FIX: Advisory lock uses md5→bigint pattern (matches A1, stable)
-- - Added detected_language to staging CHECK constraint (A2 contract)
-- - Use j.source_hash instead of recomputing (avoid drift)
-- - non-EN content: 'skipped' with reason (not 'failed')
--
-- Creates:
-- - raw_ingestion_jobs (queue with status/retry tracking)
-- - gemini_structured_output (immutable staging of Gemini JSON)
-- - FK: statements.gemini_output_id -> gemini_structured_output.gemini_output_id
-- - immutability triggers
-- - service-role-only RLS (+ explicit deny for anon/auth)
-- - validate_source_url() = SANITY-ONLY (no DB allowlist; allowlist lives in A0/A5B)
-- - persist_gemini_output(gemini_output_id) RPC
--
-- DESIGN DECISIONS:
-- - Dedupe is SOURCE-DEDUPE: (figure_id, source_url, source_hash). Same content
-- from different URLs is allowed (mirrors). Content-dedupe would be (figure_id, source_hash).
-- - source_type enum here vs A0 ingestion_mode: A5C orchestrator maps X posts → 'verified_social'
--
-- A5C/A5D INTEGRATION NOTES:
-- - quote_position: Per-statement field from A2. Must be {beginning,middle,end}.
-- - is_multi_temporal: Batch-level field from A2. Preserved in extraction_metadata.
-- - detected_language: Required in staging. Validated for EN; non-EN → 'skipped'.
-- - topics: Per-statement TEXT[] from A2. 1-3 values from fixed enum.
-- - Orchestrator must set status='processing' BEFORE calling persist RPC.
--
-- Assumes:
-- - pgcrypto enabled for digest()
-- - A1 V7.8+ deployed (statements.topics column exists)
-- ========================================================================
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Immutable wrapper for digest() so it can be used in triggers/indexes
CREATE OR REPLACE FUNCTION immutable_sha256_hex(p_text TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE STRICT
AS $$
  SELECT encode(digest(convert_to(p_text, 'utf8'), 'sha256'), 'hex');
$$;

-- ========================================================================
-- 1) QUEUE: raw_ingestion_jobs
-- ========================================================================
CREATE TABLE IF NOT EXISTS raw_ingestion_jobs (
job_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
figure_id UUID NOT NULL REFERENCES figures(figure_id),
source_url TEXT NOT NULL,
source_type TEXT NOT NULL CHECK (source_type IN (
'official_site', 'verified_social', 'transcript', 'clip'
)),
raw_text TEXT NOT NULL,
-- Document-level stable hash (defense-in-depth dedupe key)
-- NOTE: This is SOURCE-DEDUPE, not content-dedupe. Same content from
-- different URLs will create separate jobs (intentional for mirrors).
source_hash TEXT,
submitted_by TEXT,
submitted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN (
'pending', 'processing', 'completed', 'failed', 'skipped'
)),
gemini_output_id UUID,
error_log TEXT,
retry_count INTEGER NOT NULL DEFAULT 0,
max_retries INTEGER NOT NULL DEFAULT 3,
last_retry_at TIMESTAMPTZ,
source_timestamp TIMESTAMPTZ,
CONSTRAINT check_retry_limit CHECK (retry_count <= max_retries)
);

-- Auto-compute source_hash on insert/update (replaces GENERATED ALWAYS AS)
CREATE OR REPLACE FUNCTION trg_compute_source_hash()
RETURNS TRIGGER
LANGUAGE plpgsql
IMMUTABLE
AS $fn$
BEGIN
  NEW.source_hash := immutable_sha256_hex(NEW.raw_text);
  RETURN NEW;
END;
$fn$;
DROP TRIGGER IF EXISTS trg_raw_ingestion_jobs_source_hash ON raw_ingestion_jobs;
CREATE TRIGGER trg_raw_ingestion_jobs_source_hash
  BEFORE INSERT OR UPDATE OF raw_text ON raw_ingestion_jobs
  FOR EACH ROW
  EXECUTE FUNCTION trg_compute_source_hash();

DO $$
BEGIN
IF NOT EXISTS (
SELECT 1 FROM pg_constraint WHERE conname =
'raw_ingestion_jobs_raw_text_length_limit'
) THEN
ALTER TABLE raw_ingestion_jobs ADD CONSTRAINT
raw_ingestion_jobs_raw_text_length_limit
CHECK (char_length(raw_text) <= 50000);
END IF;
END $$;
CREATE INDEX IF NOT EXISTS idx_ingestion_jobs_status_pending
ON raw_ingestion_jobs(status, submitted_at)
WHERE status = 'pending';
CREATE INDEX IF NOT EXISTS idx_ingestion_jobs_figure_status
ON raw_ingestion_jobs(figure_id, status);
CREATE INDEX IF NOT EXISTS idx_ingestion_retries
ON raw_ingestion_jobs(retry_count DESC)
WHERE retry_count > 0;
-- SOURCE-DEDUPE: allows same content from different URLs
DROP INDEX IF EXISTS uq_raw_ingestion_jobs_figure_source;
CREATE UNIQUE INDEX IF NOT EXISTS uq_raw_ingestion_jobs_dedupe
ON raw_ingestion_jobs(figure_id, source_url, source_hash);
-- ========================================================================
-- 2) STAGING: gemini_structured_output (IMMUTABLE)
-- ========================================================================
CREATE TABLE IF NOT EXISTS gemini_structured_output (
gemini_output_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
job_id UUID NOT NULL REFERENCES raw_ingestion_jobs(job_id),
figure_id UUID NOT NULL REFERENCES figures(figure_id),
statements JSONB NOT NULL,
extraction_metadata JSONB NOT NULL,
model_version TEXT NOT NULL,
prompt_version TEXT NOT NULL,
created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
-- A2 contract: require all extraction_metadata fields including detected_language
CONSTRAINT validate_gemini_extraction_metadata CHECK (
extraction_metadata ? 'total_source_length' AND
extraction_metadata ? 'statements_extracted' AND
extraction_metadata ? 'extraction_method' AND
extraction_metadata ? 'extraction_note' AND
extraction_metadata ? 'detected_language'
)
);
CREATE INDEX IF NOT EXISTS idx_gemini_output_job
ON gemini_structured_output(job_id);
CREATE INDEX IF NOT EXISTS idx_gemini_output_figure
ON gemini_structured_output(figure_id);
CREATE INDEX IF NOT EXISTS idx_gemini_output_created
ON gemini_structured_output(created_at DESC);
-- ========================================================================
-- 3) FK: statements.gemini_output_id → gemini_structured_output.gemini_output_id
-- ========================================================================
DO $$
BEGIN
IF NOT EXISTS (
SELECT 1 FROM pg_constraint WHERE conname = 'fk_statements_gemini_output'
) THEN
ALTER TABLE statements
ADD CONSTRAINT fk_statements_gemini_output
FOREIGN KEY (gemini_output_id)
REFERENCES gemini_structured_output(gemini_output_id)
ON DELETE RESTRICT;
END IF;
END $$;
-- ========================================================================
-- 4) IMMUTABILITY TRIGGERS
-- ========================================================================
CREATE OR REPLACE FUNCTION prevent_update_delete()
RETURNS TRIGGER AS $$
BEGIN
IF TG_OP = 'UPDATE' THEN
RAISE EXCEPTION 'updates are prohibited on %.%', TG_TABLE_SCHEMA,
TG_TABLE_NAME;
END IF;
IF TG_OP = 'DELETE' THEN
RAISE EXCEPTION 'deletes are prohibited on %.%', TG_TABLE_SCHEMA,
TG_TABLE_NAME;
END IF;
RETURN NEW;
END;
$$ LANGUAGE plpgsql;
DROP TRIGGER IF EXISTS trig_gemini_structured_output_immutable ON
gemini_structured_output;
CREATE TRIGGER trig_gemini_structured_output_immutable
BEFORE UPDATE OR DELETE ON gemini_structured_output
FOR EACH ROW EXECUTE FUNCTION prevent_update_delete();
CREATE OR REPLACE FUNCTION prevent_delete_only()
RETURNS TRIGGER AS $$
BEGIN
IF TG_OP = 'DELETE' THEN
RAISE EXCEPTION 'deletes are prohibited on %.%', TG_TABLE_SCHEMA,
TG_TABLE_NAME;
END IF;
RETURN OLD;
END;
$$ LANGUAGE plpgsql;
DROP TRIGGER IF EXISTS trig_raw_ingestion_jobs_no_delete ON raw_ingestion_jobs;
CREATE TRIGGER trig_raw_ingestion_jobs_no_delete
BEFORE DELETE ON raw_ingestion_jobs
FOR EACH ROW EXECUTE FUNCTION prevent_delete_only();
-- ========================================================================
-- 5) RLS: Service-role only
-- ========================================================================
ALTER TABLE raw_ingestion_jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE gemini_structured_output ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS raw_ingestion_jobs_service_only ON raw_ingestion_jobs;
CREATE POLICY raw_ingestion_jobs_service_only
ON raw_ingestion_jobs
FOR ALL TO public
USING (auth.role() = 'service_role')
WITH CHECK (auth.role() = 'service_role');
DROP POLICY IF EXISTS gemini_structured_output_service_only ON
gemini_structured_output;
CREATE POLICY gemini_structured_output_service_only
ON gemini_structured_output
FOR ALL TO public
USING (auth.role() = 'service_role')
WITH CHECK (auth.role() = 'service_role');
DROP POLICY IF EXISTS raw_ingestion_jobs_deny_public ON raw_ingestion_jobs;
CREATE POLICY raw_ingestion_jobs_deny_public
ON raw_ingestion_jobs
FOR ALL TO anon, authenticated
USING (false)
WITH CHECK (false);
DROP POLICY IF EXISTS gemini_structured_output_deny_public ON
gemini_structured_output;
CREATE POLICY gemini_structured_output_deny_public
ON gemini_structured_output
FOR ALL TO anon, authenticated
USING (false)
WITH CHECK (false);
-- ========================================================================
-- 6) validate_source_url (SANITY-ONLY)
-- ========================================================================
CREATE OR REPLACE FUNCTION validate_source_url(p_figure_id UUID, p_source_url
TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
IF auth.role() IS DISTINCT FROM 'service_role' THEN
RAISE EXCEPTION 'forbidden';
END IF;
IF p_source_url IS NULL OR btrim(p_source_url) = '' THEN
RETURN false;
END IF;
IF char_length(p_source_url) > 2048 THEN
RETURN false;
END IF;
IF p_source_url !~* '^https://'
OR p_source_url ~* '^(https?://)(localhost|127\.0\.0\.1|0\.0\.0\.0)'
THEN
RETURN false;
END IF;
IF NOT EXISTS (SELECT 1 FROM figures WHERE figure_id = p_figure_id) THEN
RETURN false;
END IF;
RETURN true;
END;
$$;
REVOKE ALL ON FUNCTION validate_source_url(UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION validate_source_url(UUID, TEXT) TO service_role;
-- ========================================================================
-- 6b) TOPICS VALIDATION HELPER (V1.4.4)
-- ========================================================================
-- Validates a JSONB array of topics against the A1 enum.
-- Returns NULL if valid, or error message if invalid.
-- ========================================================================
CREATE OR REPLACE FUNCTION validate_topics_jsonb(p_topics JSONB)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
v_topic TEXT;
v_count INTEGER;
v_valid_topics TEXT[] := ARRAY[
'ECONOMY', 'IMMIGRATION', 'AI_TECHNOLOGY', 'FOREIGN_POLICY',
'HEALTHCARE', 'CLIMATE_ENVIRONMENT', 'CRIME_JUSTICE', 'ELECTIONS',
'MILITARY_DEFENSE', 'CULTURE_SOCIETY', 'OTHER'
];
BEGIN
-- NULL or missing is OK (topics are optional for backward compat during migration)
IF p_topics IS NULL THEN
RETURN NULL;
END IF;
-- Must be an array
IF jsonb_typeof(p_topics) <> 'array' THEN
RETURN 'topics must be a JSON array';
END IF;
v_count := jsonb_array_length(p_topics);
-- Empty array is invalid per A2 schema (minItems: 1)
IF v_count = 0 THEN
RETURN 'topics array cannot be empty';
END IF;
-- Max 3 topics per A1/A2 contract
IF v_count > 3 THEN
RETURN format('topics array has %s items (max 3)', v_count);
END IF;
-- Each topic must be a valid enum value
FOR v_topic IN SELECT jsonb_array_elements_text(p_topics)
LOOP
IF v_topic IS NULL OR v_topic = '' THEN
RETURN 'topics array contains null or empty value';
END IF;
IF NOT (v_topic = ANY(v_valid_topics)) THEN
RETURN format('invalid topic: %s', v_topic);
END IF;
END LOOP;
RETURN NULL; -- Valid
END;
$$;
-- ========================================================================
-- 6c) JSONB array to TEXT[] conversion helper
-- ========================================================================
CREATE OR REPLACE FUNCTION jsonb_array_to_text_array(p_jsonb JSONB)
RETURNS TEXT[]
LANGUAGE sql
IMMUTABLE
AS $$
SELECT CASE
WHEN p_jsonb IS NULL THEN NULL
WHEN jsonb_typeof(p_jsonb) <> 'array' THEN NULL
ELSE ARRAY(SELECT jsonb_array_elements_text(p_jsonb))
END;
$$;
-- ========================================================================
-- 7) ATOMIC PERSISTENCE RPC: persist_gemini_output
--
-- STATE MACHINE CONTRACT:
-- - Orchestrator MUST set status='processing' before calling this RPC
-- - RPC only operates on jobs with status='processing'
-- - On success: status → 'completed'
-- - On duplicate: status → 'skipped'
-- - On non-EN: status → 'skipped' (not 'failed')
-- - On error: status → 'failed' (via orchestrator or exception)
--
-- RETRY POLICY (CONTRACT):
-- - max_retries defaults to 3
-- - retry_count + last_retry_at MUST be incremented by orchestrator on each retry
-- - Jobs exceeding max_retries should be set status='failed' by orchestrator
-- - This RPC does NOT increment retry_count (orchestrator responsibility)
--
-- A2 FIELD HANDLING:
-- - quote_position: Per-statement, MUST be {beginning,middle,end}. Reject otherwise.
-- - is_multi_temporal: Batch-level field. Preserved in extraction_metadata.
-- - detected_language: Required in staging. non-EN → 'skipped'.
-- - topics: Per-statement TEXT[] from A2. 1-3 values from fixed enum. (V1.4.4)
-- ========================================================================
CREATE OR REPLACE FUNCTION persist_gemini_output(p_gemini_output_id UUID)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
v_row RECORD;
v_inserted INTEGER := 0;
v_expected_count INTEGER;
v_actual_count INTEGER;
v_total_source_length INTEGER;
v_detected_language TEXT;
v_is_multi_temporal BOOLEAN;
v_bad_indices INTEGER[];
v_lock_id BIGINT;
v_topics_error TEXT;
BEGIN
IF auth.role() IS DISTINCT FROM 'service_role' THEN
RAISE EXCEPTION 'forbidden';
END IF;
-- Advisory lock: md5→bigint pattern (matches A1, stable across PG versions)
v_lock_id := ('x' || substring(md5(p_gemini_output_id::text) from 1 for 15))::bit(60)::bigint;
IF NOT pg_try_advisory_lock(v_lock_id) THEN
RAISE EXCEPTION 'Another worker is already persisting gemini_output_id %',
p_gemini_output_id;
END IF;
BEGIN
-- STATE MACHINE: Only operate on 'processing' jobs
SELECT
g.gemini_output_id,
g.figure_id,
g.statements,
g.extraction_metadata,
g.model_version,
g.prompt_version,
j.job_id,
j.source_url,
j.source_timestamp,
j.source_hash, -- Use existing hash, don't recompute
j.status
INTO v_row
FROM gemini_structured_output g
JOIN raw_ingestion_jobs j ON j.job_id = g.job_id
WHERE g.gemini_output_id = p_gemini_output_id
AND j.status = 'processing'; -- STRICT: processing only
IF v_row.gemini_output_id IS NULL THEN
PERFORM pg_advisory_unlock(v_lock_id);
RAISE EXCEPTION 'gemini_output_id not found or job not in processing status';
END IF;
IF NOT validate_source_url(v_row.figure_id, v_row.source_url) THEN
UPDATE raw_ingestion_jobs
SET status = 'failed',
error_log = 'source_url failed validate_source_url() sanity check'
WHERE job_id = v_row.job_id;
PERFORM pg_advisory_unlock(v_lock_id);
RAISE EXCEPTION 'source_url failed sanity check';
END IF;
IF v_row.source_timestamp IS NULL THEN
PERFORM pg_advisory_unlock(v_lock_id);
RAISE EXCEPTION 'source_timestamp is NULL — cannot persist statements';
END IF;
IF v_row.source_timestamp > now() + interval '1 day' THEN
PERFORM pg_advisory_unlock(v_lock_id);
RAISE EXCEPTION 'source_timestamp is in future: % (now: %)',
v_row.source_timestamp, now();
END IF;
IF v_row.source_timestamp < '1900-01-01'::timestamptz THEN
PERFORM pg_advisory_unlock(v_lock_id);
RAISE EXCEPTION 'source_timestamp is suspiciously old: %',
v_row.source_timestamp;
END IF;
IF jsonb_typeof(v_row.statements) <> 'array' THEN
PERFORM pg_advisory_unlock(v_lock_id);
RAISE EXCEPTION 'statements payload is not a JSON array';
END IF;
v_actual_count := jsonb_array_length(v_row.statements);
BEGIN
v_expected_count :=
COALESCE((v_row.extraction_metadata->>'statements_extracted')::int, -1);
EXCEPTION WHEN others THEN
PERFORM pg_advisory_unlock(v_lock_id);
RAISE EXCEPTION 'extraction_metadata.statements_extracted is not a valid integer';
END;
IF v_expected_count <> v_actual_count THEN
PERFORM pg_advisory_unlock(v_lock_id);
RAISE EXCEPTION 'statements_extracted mismatch: expected %, got %',
v_expected_count, v_actual_count;
END IF;
IF v_actual_count > 10 THEN
PERFORM pg_advisory_unlock(v_lock_id);
RAISE EXCEPTION 'statements exceed max 10 (got %)', v_actual_count;
END IF;
BEGIN
v_total_source_length :=
COALESCE((v_row.extraction_metadata->>'total_source_length')::int, 0);
EXCEPTION WHEN others THEN
PERFORM pg_advisory_unlock(v_lock_id);
RAISE EXCEPTION 'extraction_metadata.total_source_length is not a valid integer';
END;
-- Language check: non-EN → 'skipped' (not 'failed')
v_detected_language :=
upper(COALESCE(NULLIF(v_row.extraction_metadata->>'detected_language',''), 'EN'));
IF v_detected_language IS NOT NULL AND v_detected_language <> 'EN' THEN
UPDATE raw_ingestion_jobs
SET status = 'skipped',
gemini_output_id = p_gemini_output_id,
error_log = format('NON_ENGLISH_SKIPPED: detected_language=%s. Only EN
allowed in V1.', v_detected_language)
WHERE job_id = v_row.job_id;
PERFORM pg_advisory_unlock(v_lock_id);
RETURN 0; -- Not an error, just skipped
END IF;
v_is_multi_temporal :=
COALESCE((v_row.extraction_metadata->>'is_multi_temporal')::boolean, false);
-- Validate: no empty text
SELECT array_agg(idx) INTO v_bad_indices
FROM jsonb_array_elements(v_row.statements) WITH ORDINALITY AS s(obj, idx)
WHERE COALESCE(NULLIF(btrim(obj->>'text'), ''), '') = '';
IF array_length(v_bad_indices, 1) > 0 THEN
PERFORM pg_advisory_unlock(v_lock_id);
RAISE EXCEPTION 'statement(s) at index % have missing/empty text', v_bad_indices;
END IF;
-- Validate: min 10 chars
SELECT array_agg(idx) INTO v_bad_indices
FROM jsonb_array_elements(v_row.statements) WITH ORDINALITY AS s(obj, idx)
WHERE char_length(btrim(obj->>'text')) < 10;
IF array_length(v_bad_indices, 1) > 0 THEN
PERFORM pg_advisory_unlock(v_lock_id);
RAISE EXCEPTION 'statement(s) at index % are under 10 characters', v_bad_indices;
END IF;
-- Validate: max 2000 chars (verbatim guarantee)
SELECT array_agg(idx) INTO v_bad_indices
FROM jsonb_array_elements(v_row.statements) WITH ORDINALITY AS s(obj, idx)
WHERE char_length(obj->>'text') > 2000;
IF array_length(v_bad_indices, 1) > 0 THEN
PERFORM pg_advisory_unlock(v_lock_id);
RAISE EXCEPTION 'statement(s) at index % exceed 2000 chars', v_bad_indices;
END IF;
-- Validate: context_pre/context_post max 1000 chars (A2 contract)
SELECT array_agg(idx) INTO v_bad_indices
FROM jsonb_array_elements(v_row.statements) WITH ORDINALITY AS s(obj, idx)
WHERE char_length(COALESCE(obj->>'context_pre', '')) > 1000
OR char_length(COALESCE(obj->>'context_post', '')) > 1000;
IF array_length(v_bad_indices, 1) > 0 THEN
PERFORM pg_advisory_unlock(v_lock_id);
RAISE EXCEPTION 'statement(s) at index % have context exceeding 1000 chars',
v_bad_indices;
END IF;
-- Validate: quote_position must be {beginning,middle,end} (A2 enum contract)
SELECT array_agg(idx) INTO v_bad_indices
FROM jsonb_array_elements(v_row.statements) WITH ORDINALITY AS s(obj, idx)
WHERE COALESCE(obj->>'quote_position', 'middle') NOT IN ('beginning', 'middle', 'end');
IF array_length(v_bad_indices, 1) > 0 THEN
PERFORM pg_advisory_unlock(v_lock_id);
RAISE EXCEPTION 'statement(s) at index % have invalid quote_position (must be
beginning|middle|end)', v_bad_indices;
END IF;
-- V1.4.4: Validate topics for each statement (if present)
SELECT array_agg(idx), string_agg(validate_topics_jsonb(obj->'topics'), '; ')
INTO v_bad_indices, v_topics_error
FROM jsonb_array_elements(v_row.statements) WITH ORDINALITY AS s(obj, idx)
WHERE validate_topics_jsonb(obj->'topics') IS NOT NULL;
IF array_length(v_bad_indices, 1) > 0 THEN
PERFORM pg_advisory_unlock(v_lock_id);
RAISE EXCEPTION 'statement(s) at index % have invalid topics: %', v_bad_indices,
v_topics_error;
END IF;
-- V1.4.4: Extract topics and insert into statements.topics column
WITH elems AS (
SELECT
(s->>'text')::text AS text,
COALESCE((s->>'context_pre')::text, '') AS context_pre,
COALESCE((s->>'context_post')::text, '') AS context_post,
COALESCE((s->>'quote_position')::text, 'middle') AS quote_position,
jsonb_array_to_text_array(s->'topics') AS topics
FROM jsonb_array_elements(v_row.statements) s
),
ins AS (
INSERT INTO statements (
figure_id, text, timestamp, source_url, source_hash,
context_pre, context_post, gemini_output_id,
extraction_metadata, gemini_version, prompt_version, language,
topics -- V1.4.4: topics column
)
SELECT
v_row.figure_id,
e.text,
v_row.source_timestamp,
v_row.source_url,
v_row.source_hash, -- Use existing hash from job row
e.context_pre,
e.context_post,
v_row.gemini_output_id,
jsonb_build_object(
'total_source_length', v_total_source_length,
'statements_extracted', v_expected_count,
'extraction_method',
COALESCE(v_row.extraction_metadata->>'extraction_method', 'gemini_extraction'),
'extraction_note', COALESCE(v_row.extraction_metadata->>'extraction_note', ''),
'detected_language', 'EN',
'is_multi_temporal', v_is_multi_temporal,
'quote_position', e.quote_position
),
v_row.model_version,
v_row.prompt_version,
'EN',
e.topics -- V1.4.4: topics value
FROM elems e
ON CONFLICT DO NOTHING
RETURNING 1
)
SELECT COUNT(*) INTO v_inserted FROM ins;
IF v_inserted = 0 AND v_expected_count > 0 THEN
RAISE WARNING 'Zero statements inserted (expected %). All likely duplicates. job_id:
%', v_expected_count, v_row.job_id;
UPDATE raw_ingestion_jobs
SET status = 'skipped',
gemini_output_id = p_gemini_output_id,
error_log = COALESCE(error_log, 'All extracted statements were duplicates')
WHERE job_id = v_row.job_id AND status = 'processing';
PERFORM pg_advisory_unlock(v_lock_id);
RETURN 0;
END IF;
UPDATE raw_ingestion_jobs
SET status = 'completed', gemini_output_id = p_gemini_output_id
WHERE job_id = v_row.job_id AND status = 'processing';
PERFORM pg_advisory_unlock(v_lock_id);
RETURN v_inserted;
EXCEPTION
WHEN OTHERS THEN
PERFORM pg_advisory_unlock(v_lock_id);
RAISE;
END;
END;
$$;
REVOKE ALL ON FUNCTION persist_gemini_output(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION persist_gemini_output(UUID) TO service_role;
-- Grant helper functions to service_role
REVOKE ALL ON FUNCTION validate_topics_jsonb(JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION validate_topics_jsonb(JSONB) TO service_role;
REVOKE ALL ON FUNCTION jsonb_array_to_text_array(JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION jsonb_array_to_text_array(JSONB) TO service_role;
-- ========================================================================
-- END A5A — V1.4.4
-- ========================================================================
