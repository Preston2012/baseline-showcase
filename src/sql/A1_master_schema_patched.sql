-- ========================================================================
-- BASELINE V1.4  - SUPABASE SCHEMA (CANONICAL)
-- A1  - V8.0
--
-- CHANGES FROM V7.8 (audit reconciliation):
-- B1: Removed statement immutability trigger  - A12A owns canonical trigger
-- (trg_statements_immutable with NEW := OLD pattern)
-- B2: cost_log.operation enum extended (CONSENSUS, BACKFILL + error variants)
-- B3: get_receipt() changed to SECURITY INVOKER (RLS handles filtering)
-- B4: Column 'timestamp' KEPT as-is; A9A views alias it (micro-patch)
-- B5: Topic enum UPPER_SNAKE is canonical; A9B patches its constants
-- H1: Annotations: added is_deleted + deleted_at for soft-delete
-- H2: Added GRANT SELECT on framing_radar + war_room views
-- H3: consensus.baseline_delta_stddev KEPT (A7B writes it)
-- H4: RLS helper SECURITY DEFINER documented (correct for policy helpers)
--
-- POST-AUDIT FIX (from Grok reconciliation):
-- Annotations RLS: split FOR ALL into SELECT/INSERT/UPDATE (no DELETE policy)
-- Prevents hard DELETE  - enforces soft-delete-only for authenticated users
--
-- CROSS-ARTIFACT PATCHES REQUIRED AFTER DEPLOY:
-- A9A: Views must alias statements.timestamp (not source_timestamp)
-- A9B: VALID_TOPICS must use UPPER_SNAKE to match A1 enum
-- A12A: Deploys canonical immutability trigger on statements
--
-- V1.4 FEATURE COST IMPACT: $0.00 additional AI spend
-- - Topics extracted in same Gemini call (A2 prompt update)
-- - All other features are DB queries on existing data
--
-- GUARANTEES (LOCKED):
-- - Immutable statements + analyses + consensus (write-once; revoke instead)
-- - Revocation permanence (no un-revoke)
-- - Baseline window is "PRIOR ONLY" (ingestion_time cutoff prevents future leakage)
-- - Baseline delta scale consistent (cosine distance ~0..2 => 0..100)
-- - Deterministic, schema-validated metrics (0..100)
-- - Public-safe reads only (RLS)
-- - Service-only writes + RPCs (RLS + runtime guards)
--
-- IMPORTANT (LOCKED):
-- - Time-weighting beyond recency ordering is POST-MVP.
-- V8.0 uses UNIFORM weighting over a recency-ordered window.
-- - Statement immutability trigger is defined in A12A, NOT here.
-- A12A must be deployed alongside or after A1.
--
-- NOTE:
-- - Cost enforcement / degraded mode / budget caps are intentionally EXCLUDED
-- here and handled in a separate approved add-on patch.
-- - Allowlist enforcement is NOT implemented in DB.
-- Enforcement is REQUIRED at ingest (A5B) before any DB writes or AI calls.
--
-- Stack: Postgres 15+ with pgvector extension
-- ========================================================================
-- ========================================================================
-- EXTENSIONS
-- ========================================================================
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS vector;
-- ========================================================================
-- TOPIC VALIDATION (fixed enum, UPPER_SNAKE canonical)
-- ========================================================================
-- Topics are extracted by Gemini (A2), not analysis models.
-- UPPER_SNAKE is the canonical representation. All serving layers must match.
-- ========================================================================
CREATE OR REPLACE FUNCTION is_valid_topic(t TEXT)
RETURNS BOOLEAN
LANGUAGE sql
IMMUTABLE
AS $$
SELECT t IN (
'ECONOMY',
'IMMIGRATION',
'AI_TECHNOLOGY',
'FOREIGN_POLICY',
'HEALTHCARE',
'CLIMATE_ENVIRONMENT',
'CRIME_JUSTICE',
'ELECTIONS',
'MILITARY_DEFENSE',
'CULTURE_SOCIETY',
'OTHER'
);
$$;
CREATE OR REPLACE FUNCTION are_valid_topics(topics TEXT[])
RETURNS BOOLEAN
LANGUAGE sql
IMMUTABLE
AS $$
SELECT topics IS NULL
OR (
array_length(topics, 1) <= 3
AND NOT EXISTS (
SELECT 1 FROM unnest(topics) t WHERE NOT is_valid_topic(t)
)
);
$$;
-- ========================================================================
-- FIGURES
-- ========================================================================
CREATE TABLE IF NOT EXISTS figures (
figure_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
name TEXT NOT NULL,
category TEXT NOT NULL CHECK (category IN (
'US_POLITICS',
'GLOBAL_POLITICS',
'AI_TECH',
'CRYPTO',
'MEDIA_CULTURE',
'OFFICE'
)),
is_active BOOLEAN NOT NULL DEFAULT false,
activation_order INTEGER,
metadata JSONB DEFAULT '{}'::jsonb,
created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
-- Stable key linking to A0 allowlist figures[].id
-- Required for A5B V1.4.3 allowlist enforcement
allowlist_id TEXT,
UNIQUE(name)
);
CREATE INDEX IF NOT EXISTS idx_figures_active
ON figures(is_active) WHERE is_active = true;
CREATE INDEX IF NOT EXISTS idx_figures_activation
ON figures(activation_order) WHERE activation_order IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_figures_allowlist_id
ON figures(allowlist_id)
WHERE allowlist_id IS NOT NULL;
-- ========================================================================
-- STATEMENTS (IMMUTABLE CORE)
-- ========================================================================
-- IMPORTANT: The immutability trigger for this table is defined in A12A.
-- A12A owns the canonical trigger (trg_statements_immutable) which uses
-- the NEW := OLD pattern for schema-future-proof immutability enforcement.
-- Do NOT define statement immutability triggers here.
-- ========================================================================
CREATE TABLE IF NOT EXISTS statements (
statement_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
figure_id UUID NOT NULL REFERENCES figures(figure_id) ON DELETE CASCADE,
text TEXT NOT NULL,
-- Note: column is named 'timestamp'. A9A views alias this for public display.
timestamp TIMESTAMPTZ NOT NULL,
source_url TEXT NOT NULL,
source_hash TEXT NOT NULL,
ingestion_time TIMESTAMPTZ NOT NULL DEFAULT now(),
context_pre TEXT NOT NULL,
context_post TEXT NOT NULL,
extraction_metadata JSONB NOT NULL,
gemini_version TEXT NOT NULL,
prompt_version TEXT NOT NULL,
language TEXT NOT NULL DEFAULT 'EN' CHECK (language = 'EN'),
-- Topic tags extracted by Gemini (1-3 from fixed UPPER_SNAKE enum)
-- Zero additional AI cost  - same extraction call
topics TEXT[] CHECK (are_valid_topics(topics)),
embedding vector(1536),
baseline_delta NUMERIC(5,2) CHECK (baseline_delta >= 0 AND baseline_delta <= 100),
is_revoked BOOLEAN NOT NULL DEFAULT false,
revoked_at TIMESTAMPTZ,
revocation_reason TEXT,
source_last_checked TIMESTAMPTZ,
gemini_output_id UUID,
created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
UNIQUE(figure_id, source_url, source_hash, text)
);
-- Core access patterns
CREATE INDEX IF NOT EXISTS idx_statements_figure_time
ON statements(figure_id, timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_statements_figure_id
ON statements(figure_id);
CREATE INDEX IF NOT EXISTS idx_statements_source_hash
ON statements(source_hash);
CREATE INDEX IF NOT EXISTS idx_statements_ingestion
ON statements(ingestion_time DESC);
CREATE INDEX IF NOT EXISTS idx_statements_revoked
ON statements(is_revoked) WHERE is_revoked = true;
CREATE INDEX IF NOT EXISTS idx_statements_awaiting_embed
ON statements(figure_id)
WHERE embedding IS NULL AND is_revoked = false;
CREATE INDEX IF NOT EXISTS idx_statements_gemini_output
ON statements(gemini_output_id);
CREATE INDEX IF NOT EXISTS idx_statements_rls_cover
ON statements(figure_id, statement_id)
WHERE is_revoked = false AND language = 'EN';
CREATE INDEX IF NOT EXISTS idx_statements_topics
ON statements USING GIN (topics)
WHERE topics IS NOT NULL;
-- ========================================================================
-- IVFFLAT EMBEDDING INDEX
--
-- BUILD PROTOCOL (REQUIRED FOR PRODUCTION):
-- 1. Index should be created AFTER initial data load (needs rows to cluster)
-- 2. Run ANALYZE statements; after bulk inserts/backfill
-- 3. lists=100 is tuned for ~10k-100k vectors; adjust if scale changes
-- 4. For <1k vectors, consider using exact search (no index) initially
-- ========================================================================
CREATE INDEX IF NOT EXISTS idx_statements_embedding
ON statements
USING ivfflat (embedding vector_cosine_ops)
WITH (lists = 100)
WHERE embedding IS NOT NULL;
-- Required extraction metadata keys
DO $$
BEGIN
IF NOT EXISTS (
SELECT 1 FROM pg_constraint WHERE conname = 'validate_extraction_metadata'
) THEN
ALTER TABLE statements ADD CONSTRAINT validate_extraction_metadata
CHECK (
extraction_metadata ? 'total_source_length' AND
extraction_metadata ? 'statements_extracted' AND
extraction_metadata ? 'extraction_method'
);
END IF;
END $$;
-- Prevent unbounded statement text
DO $$
BEGIN
IF NOT EXISTS (
SELECT 1 FROM pg_constraint WHERE conname = 'statements_text_length_limit'
) THEN
ALTER TABLE statements ADD CONSTRAINT statements_text_length_limit
CHECK (char_length(text) <= 50000);
END IF;
END $$;
-- ========================================================================
-- NOTE ON STATEMENT IMMUTABILITY
-- ========================================================================
-- The immutability trigger + delete blocker for this table are defined in
-- artifact A12A (trg_statements_immutable). That trigger uses the NEW := OLD
-- pattern which is schema-future-proof: it captures incoming mutation values,
-- pins everything via NEW := OLD, then selectively allows only:
-- Path 1: Revocation (is_revoked, revoked_at, revocation_reason)
-- Path 2: Embedding write-once (embedding)
-- Path 3: baseline_delta write-once (baseline_delta)
-- Plus: source_last_checked is always mutable.
-- NOTE: topics is pinned by NEW := OLD (immutable after INSERT).
-- Topics must be set at INSERT time via Gemini extraction (A14A).
-- Pre-A14A statements will have topics = NULL (acceptable  - not filterable by topic).
--
-- A12A is the SINGLE SOURCE OF TRUTH for statement immutability.
-- Do NOT add immutability triggers here.
-- ========================================================================
-- ========================================================================
-- ANALYSES (PUBLIC-SAFE) + ANALYSES_AUDIT (PRIVATE RAW PAYLOADS)
-- ========================================================================
CREATE TABLE IF NOT EXISTS analyses (
analysis_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
statement_id UUID NOT NULL REFERENCES statements(statement_id) ON DELETE
CASCADE,
model_provider TEXT NOT NULL CHECK (model_provider IN ('OPENAI', 'ANTHROPIC',
'XAI')),
model_version TEXT NOT NULL,
prompt_version TEXT NOT NULL,
repetition NUMERIC(5,2) NOT NULL CHECK (repetition >= 0 AND repetition <= 100),
novelty NUMERIC(5,2) NOT NULL CHECK (novelty >= 0 AND novelty <= 100),
affective_language_rate NUMERIC(5,2) NOT NULL CHECK (affective_language_rate >= 0
AND affective_language_rate <= 100),
topic_entropy NUMERIC(5,2) NOT NULL CHECK (topic_entropy >= 0 AND topic_entropy <=
100),
framing TEXT NOT NULL CHECK (framing IN (
'Adversarial / Oppositional',
'Problem Identification',
'Commitment / Forward-Looking',
'Justification / Reactive',
'Imperative / Directive'
)),
analyzed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
UNIQUE(statement_id, model_provider)
);
CREATE INDEX IF NOT EXISTS idx_analyses_statement ON analyses(statement_id);
CREATE INDEX IF NOT EXISTS idx_analyses_provider ON analyses(model_provider);
-- Private raw payloads (no anon/authenticated access)
CREATE TABLE IF NOT EXISTS analyses_audit (
analysis_id UUID PRIMARY KEY REFERENCES analyses(analysis_id) ON DELETE
CASCADE,
raw_response JSONB NOT NULL,
created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
DO $$
BEGIN
IF NOT EXISTS (
SELECT 1 FROM pg_constraint WHERE conname = 'analyses_audit_payload_size_limit'
) THEN
ALTER TABLE analyses_audit ADD CONSTRAINT analyses_audit_payload_size_limit
CHECK (pg_column_size(raw_response) <= 1048576);
END IF;
END $$;
-- Generic immutability blocker for analyses/audit/consensus
CREATE OR REPLACE FUNCTION prevent_immutable_mutation()
RETURNS TRIGGER AS $$
BEGIN
IF (TG_OP = 'DELETE') THEN
RAISE EXCEPTION 'Deletions prohibited on % table.', TG_TABLE_NAME;
END IF;
RAISE EXCEPTION 'Updates prohibited on % table; records are immutable after insert.',
TG_TABLE_NAME;
END;
$$ LANGUAGE plpgsql;
DROP TRIGGER IF EXISTS trigger_analyses_immutability ON analyses;
CREATE TRIGGER trigger_analyses_immutability
BEFORE UPDATE OR DELETE ON analyses
FOR EACH ROW
EXECUTE FUNCTION prevent_immutable_mutation();
DROP TRIGGER IF EXISTS trigger_analyses_audit_immutability ON analyses_audit;
CREATE TRIGGER trigger_analyses_audit_immutability
BEFORE UPDATE OR DELETE ON analyses_audit
FOR EACH ROW
EXECUTE FUNCTION prevent_immutable_mutation();
-- ========================================================================
-- CONSENSUS
-- ========================================================================
CREATE TABLE IF NOT EXISTS consensus (
consensus_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
statement_id UUID NOT NULL REFERENCES statements(statement_id) ON DELETE
CASCADE UNIQUE,
repetition_avg NUMERIC(5,2) NOT NULL CHECK (repetition_avg >= 0 AND repetition_avg
<= 100),
novelty_avg NUMERIC(5,2) NOT NULL CHECK (novelty_avg >= 0 AND novelty_avg <=
100),
baseline_delta_avg NUMERIC(5,2) NOT NULL CHECK (baseline_delta_avg >= 0 AND
baseline_delta_avg <= 100),
affective_language_rate_avg NUMERIC(5,2) NOT NULL CHECK
(affective_language_rate_avg >= 0 AND affective_language_rate_avg <= 100),
topic_entropy_avg NUMERIC(5,2) NOT NULL CHECK (topic_entropy_avg >= 0 AND
topic_entropy_avg <= 100),
repetition_stddev NUMERIC(5,2) NOT NULL DEFAULT 0,
novelty_stddev NUMERIC(5,2) NOT NULL DEFAULT 0,
baseline_delta_stddev NUMERIC(5,2) NOT NULL DEFAULT 0,
affective_language_rate_stddev NUMERIC(5,2) NOT NULL DEFAULT 0,
topic_entropy_stddev NUMERIC(5,2) NOT NULL DEFAULT 0,
framing_consensus TEXT CHECK (framing_consensus IN (
'Adversarial / Oppositional',
'Problem Identification',
'Commitment / Forward-Looking',
'Justification / Reactive',
'Imperative / Directive'
)),
framing_agreement_count INTEGER NOT NULL CHECK (framing_agreement_count >= 1
AND framing_agreement_count <= 3),
framing_split JSONB,
signal_components JSONB NOT NULL,
signal_rank NUMERIC(5,2) NOT NULL CHECK (signal_rank >= 0 AND signal_rank <= 100),
model_versions JSONB NOT NULL,
model_count INTEGER NOT NULL CHECK (model_count >= 2 AND model_count <= 3),
models_included TEXT[] NOT NULL,
variance_detected BOOLEAN NOT NULL DEFAULT false,
computed_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_consensus_statement ON consensus(statement_id);
CREATE INDEX IF NOT EXISTS idx_consensus_signal_rank ON consensus(signal_rank
DESC NULLS LAST);
CREATE INDEX IF NOT EXISTS idx_consensus_variance ON consensus(variance_detected)
WHERE variance_detected = true;
CREATE INDEX IF NOT EXISTS idx_consensus_recent_high_signal
ON consensus(signal_rank DESC, computed_at DESC)
WHERE signal_rank >= 70;
CREATE INDEX IF NOT EXISTS idx_consensus_computed_at
ON consensus(computed_at DESC);
DO $$
BEGIN
IF NOT EXISTS (
SELECT 1 FROM pg_constraint WHERE conname = 'validate_signal_components'
) THEN
ALTER TABLE consensus ADD CONSTRAINT validate_signal_components
CHECK (
signal_components ? 'repetition' AND
signal_components ? 'novelty' AND
signal_components ? 'baseline_delta'
);
END IF;
END $$;
-- Strict framing_split validation (trigger-based, Postgres disallows subqueries in CHECK)
CREATE OR REPLACE FUNCTION validate_framing_split()
RETURNS TRIGGER AS $$
DECLARE
  k TEXT;
BEGIN
  IF NEW.framing_split IS NOT NULL THEN
    IF jsonb_typeof(NEW.framing_split) != 'object' THEN
      RAISE EXCEPTION 'framing_split must be a JSON object';
    END IF;
    FOR k IN SELECT jsonb_object_keys(NEW.framing_split)
    LOOP
      IF k NOT IN (
        'Adversarial / Oppositional',
        'Problem Identification',
        'Commitment / Forward-Looking',
        'Justification / Reactive',
        'Imperative / Directive'
      ) THEN
        RAISE EXCEPTION 'Invalid framing_split key: %', k;
      END IF;
    END LOOP;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_validate_framing_split ON consensus;
CREATE TRIGGER trigger_validate_framing_split
BEFORE INSERT OR UPDATE ON consensus
FOR EACH ROW
EXECUTE FUNCTION validate_framing_split();
DROP TRIGGER IF EXISTS trigger_consensus_immutability ON consensus;
CREATE TRIGGER trigger_consensus_immutability
BEFORE UPDATE OR DELETE ON consensus
FOR EACH ROW
EXECUTE FUNCTION prevent_immutable_mutation();
-- ========================================================================
-- SOURCE HASHES (MUTABLE BY DESIGN VIA TRIGGERS)
-- ========================================================================
CREATE TABLE IF NOT EXISTS source_hashes (
hash_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
figure_id UUID NOT NULL REFERENCES figures(figure_id) ON DELETE CASCADE,
source_url TEXT NOT NULL,
source_hash TEXT NOT NULL,
first_seen TIMESTAMPTZ NOT NULL DEFAULT now(),
statement_count INTEGER NOT NULL DEFAULT 0,
UNIQUE(figure_id, source_hash)
);
CREATE INDEX IF NOT EXISTS idx_source_hashes_lookup
ON source_hashes(figure_id, source_hash);
CREATE OR REPLACE FUNCTION bump_source_hash_count()
RETURNS TRIGGER AS $$
BEGIN
INSERT INTO source_hashes (figure_id, source_url, source_hash, statement_count)
VALUES (NEW.figure_id, NEW.source_url, NEW.source_hash, 1)
ON CONFLICT (figure_id, source_hash)
DO UPDATE SET statement_count = source_hashes.statement_count + 1;
RETURN NEW;
END;
$$ LANGUAGE plpgsql;
DROP TRIGGER IF EXISTS trigger_bump_source_hash_count ON statements;
CREATE TRIGGER trigger_bump_source_hash_count
AFTER INSERT ON statements
FOR EACH ROW
EXECUTE FUNCTION bump_source_hash_count();
CREATE OR REPLACE FUNCTION adjust_source_hash_on_revocation()
RETURNS TRIGGER AS $$
BEGIN
IF OLD.is_revoked = false AND NEW.is_revoked = true THEN
UPDATE source_hashes
SET statement_count = GREATEST(0, statement_count - 1)
WHERE figure_id = NEW.figure_id AND source_hash = NEW.source_hash;
END IF;
RETURN NEW;
END;
$$ LANGUAGE plpgsql;
DROP TRIGGER IF EXISTS trigger_revocation_count_adjust ON statements;
CREATE TRIGGER trigger_revocation_count_adjust
AFTER UPDATE OF is_revoked ON statements
FOR EACH ROW
EXECUTE FUNCTION adjust_source_hash_on_revocation();
-- ========================================================================
-- COST TRACKING (LOGGING ONLY  - ENFORCEMENT DEFERRED)
-- ========================================================================
-- V8.0 FIX (B2): Extended operation enum to include CONSENSUS, BACKFILL,
-- and error variants referenced by A10A and A7C.
-- ========================================================================
CREATE TABLE IF NOT EXISTS cost_log (
log_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
statement_id UUID REFERENCES statements(statement_id) ON DELETE SET NULL,
operation TEXT NOT NULL CHECK (operation IN (
'INGESTION',
'ANALYSIS',
'EMBEDDING',
'CONSENSUS',
'BACKFILL',
'ANALYSIS_ERROR',
'CONSENSUS_ERROR',
'EMBEDDING_ERROR',
'EMBED_ERROR'
)),
provider TEXT NOT NULL CHECK (provider IN ('GEMINI', 'OPENAI', 'ANTHROPIC', 'XAI', 'ORCHESTRATOR')),
model TEXT NOT NULL,
endpoint TEXT NOT NULL,
token_count INTEGER NOT NULL DEFAULT 0,
estimated_cost_usd NUMERIC(10,6) NOT NULL DEFAULT 0,
logged_at TIMESTAMPTZ NOT NULL DEFAULT now(),
logged_day DATE GENERATED ALWAYS AS ((logged_at AT TIME ZONE 'UTC')::date)
STORED
);
CREATE INDEX IF NOT EXISTS idx_cost_log_logged ON cost_log(logged_at DESC);
CREATE INDEX IF NOT EXISTS idx_cost_log_provider ON cost_log(provider, logged_at
DESC);
CREATE INDEX IF NOT EXISTS idx_cost_log_day ON cost_log(logged_day);
DROP TRIGGER IF EXISTS trigger_cost_log_immutability ON cost_log;
CREATE TRIGGER trigger_cost_log_immutability
BEFORE UPDATE OR DELETE ON cost_log
FOR EACH ROW
EXECUTE FUNCTION prevent_immutable_mutation();
-- ========================================================================
-- VOTES TABLE (Vote Tracking  - Congress votes, no AI cost)
-- ========================================================================
-- Public record data, batch ingested from congress.gov
-- No AI processing  - just structured public data
-- ========================================================================
CREATE TABLE IF NOT EXISTS votes (
vote_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
figure_id UUID NOT NULL REFERENCES figures(figure_id) ON DELETE CASCADE,
bill_id TEXT NOT NULL,
bill_title TEXT NOT NULL,
vote TEXT NOT NULL CHECK (vote IN ('YEA', 'NAY', 'PRESENT', 'NOT_VOTING')),
vote_date DATE NOT NULL,
chamber TEXT NOT NULL CHECK (chamber IN ('HOUSE', 'SENATE')),
congress_session INTEGER NOT NULL,
source_url TEXT NOT NULL,
created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
UNIQUE(figure_id, bill_id)
);
CREATE INDEX IF NOT EXISTS idx_votes_figure ON votes(figure_id);
CREATE INDEX IF NOT EXISTS idx_votes_date ON votes(vote_date DESC);
CREATE INDEX IF NOT EXISTS idx_votes_bill ON votes(bill_id);
CREATE INDEX IF NOT EXISTS idx_votes_chamber ON votes(chamber, vote_date DESC);
DROP TRIGGER IF EXISTS trigger_votes_immutability ON votes;
CREATE TRIGGER trigger_votes_immutability
BEFORE UPDATE OR DELETE ON votes
FOR EACH ROW
EXECUTE FUNCTION prevent_immutable_mutation();
-- ========================================================================
-- ANNOTATIONS TABLE (Private user notes  - no AI cost)
-- ========================================================================
-- User-only notes on statements.
-- RLS ensures users only see their own annotations.
-- V8.0 FIX (H1): Added soft-delete (is_deleted + deleted_at).
-- ========================================================================
CREATE TABLE IF NOT EXISTS annotations (
annotation_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
user_id UUID NOT NULL, -- from Supabase auth.uid()
statement_id UUID NOT NULL REFERENCES statements(statement_id) ON DELETE
CASCADE,
note TEXT NOT NULL CHECK (char_length(note) <= 2000),
is_deleted BOOLEAN NOT NULL DEFAULT false,
deleted_at TIMESTAMPTZ,
created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
UNIQUE(user_id, statement_id)
);
CREATE INDEX IF NOT EXISTS idx_annotations_user ON annotations(user_id);
CREATE INDEX IF NOT EXISTS idx_annotations_statement ON annotations(statement_id);
CREATE INDEX IF NOT EXISTS idx_annotations_active
ON annotations(user_id, statement_id)
WHERE is_deleted = false;
-- Auto-update updated_at on annotation changes
CREATE OR REPLACE FUNCTION update_annotation_timestamp()
RETURNS TRIGGER AS $$
BEGIN
NEW.updated_at := now();
-- Auto-set deleted_at when soft-deleting
IF NEW.is_deleted = true AND OLD.is_deleted = false THEN
NEW.deleted_at := now();
END IF;
RETURN NEW;
END;
$$ LANGUAGE plpgsql;
DROP TRIGGER IF EXISTS trigger_annotation_timestamp ON annotations;
CREATE TRIGGER trigger_annotation_timestamp
BEFORE UPDATE ON annotations
FOR EACH ROW
EXECUTE FUNCTION update_annotation_timestamp();
-- ========================================================================
-- FEATURE FLAGS TABLE (Feature toggles  - no AI cost)
-- ========================================================================
-- Simple key-value for feature toggles.
-- Service-role write, public read (frontend needs to check flags).
-- Phase 2 adds tier_features for per-tier gating (A18A).
-- ========================================================================
CREATE TABLE IF NOT EXISTS feature_flags (
flag_name TEXT PRIMARY KEY,
enabled BOOLEAN NOT NULL DEFAULT false,
description TEXT,
created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE OR REPLACE FUNCTION update_feature_flag_timestamp()
RETURNS TRIGGER AS $$
BEGIN
NEW.updated_at := now();
RETURN NEW;
END;
$$ LANGUAGE plpgsql;
DROP TRIGGER IF EXISTS trigger_feature_flag_timestamp ON feature_flags;
CREATE TRIGGER trigger_feature_flag_timestamp
BEFORE UPDATE ON feature_flags
FOR EACH ROW
EXECUTE FUNCTION update_feature_flag_timestamp();
-- Seed V1.4 feature flags (all disabled by default)
INSERT INTO feature_flags (flag_name, enabled, description) VALUES
('ENABLE_TOPIC_TAGGING', false, 'Show topic tags on statements'),
('ENABLE_RECEIPT', false, 'Show "The Receipt" historical matches'),
('ENABLE_FRAMING_RADAR', false, 'Show Framing Radar aggregation'),
('ENABLE_WAR_ROOM', false, 'Show War Room model disagreement'),
('ENABLE_VOTE_TRACKING', false, 'Show congressional vote records'),
('ENABLE_ANNOTATIONS', false, 'Allow private user annotations'),
('ENABLE_HISTORICAL_TRENDS', false, 'Show historical trends dashboard')
ON CONFLICT (flag_name) DO NOTHING;
-- ========================================================================
-- ROW-LEVEL SECURITY
-- ========================================================================
ALTER TABLE figures ENABLE ROW LEVEL SECURITY;
ALTER TABLE statements ENABLE ROW LEVEL SECURITY;
ALTER TABLE analyses ENABLE ROW LEVEL SECURITY;
ALTER TABLE analyses_audit ENABLE ROW LEVEL SECURITY;
ALTER TABLE consensus ENABLE ROW LEVEL SECURITY;
ALTER TABLE source_hashes ENABLE ROW LEVEL SECURITY;
ALTER TABLE cost_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE votes ENABLE ROW LEVEL SECURITY;
ALTER TABLE annotations ENABLE ROW LEVEL SECURITY;
ALTER TABLE feature_flags ENABLE ROW LEVEL SECURITY;
-- ========================================================================
-- RLS HELPER FUNCTIONS
-- ========================================================================
-- These use SECURITY DEFINER intentionally. RLS policy functions need elevated
-- privileges to check cross-table conditions (e.g., checking figures.is_active
-- when evaluating a policy on the statements table). The function owner has
-- the necessary permissions, and SET search_path = public prevents search_path
-- injection. REVOKE ALL + explicit GRANT limits who can call them.
-- ========================================================================
CREATE OR REPLACE FUNCTION is_figure_active(f_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
SELECT EXISTS (
SELECT 1 FROM figures
WHERE figure_id = f_id AND is_active = true
);
$$;
REVOKE ALL ON FUNCTION is_figure_active(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION is_figure_active(UUID) TO anon, authenticated;
CREATE OR REPLACE FUNCTION is_statement_visible(s_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
SELECT EXISTS (
SELECT 1 FROM statements s
JOIN figures f ON f.figure_id = s.figure_id
WHERE s.statement_id = s_id
AND s.is_revoked = false
AND s.language = 'EN'
AND f.is_active = true
);
$$;
REVOKE ALL ON FUNCTION is_statement_visible(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION is_statement_visible(UUID) TO anon, authenticated;
-- ========================================================================
-- RLS POLICIES  - Public reads
-- ========================================================================
DROP POLICY IF EXISTS figures_public_read ON figures;
CREATE POLICY figures_public_read ON figures
FOR SELECT TO anon, authenticated
USING (is_active = true);
DROP POLICY IF EXISTS statements_public_read ON statements;
CREATE POLICY statements_public_read ON statements
FOR SELECT TO anon, authenticated
USING (
is_figure_active(figure_id)
AND is_revoked = false
AND language = 'EN'
);
DROP POLICY IF EXISTS analyses_public_read ON analyses;
CREATE POLICY analyses_public_read ON analyses
FOR SELECT TO anon, authenticated
USING (is_statement_visible(statement_id));
DROP POLICY IF EXISTS consensus_public_read ON consensus;
CREATE POLICY consensus_public_read ON consensus
FOR SELECT TO anon, authenticated
USING (is_statement_visible(statement_id));
-- analyses_audit: service_role only
DROP POLICY IF EXISTS analyses_audit_service_select ON analyses_audit;
DROP POLICY IF EXISTS analyses_audit_service_insert ON analyses_audit;
DROP POLICY IF EXISTS analyses_audit_deny_public ON analyses_audit;
CREATE POLICY analyses_audit_service_select ON analyses_audit
FOR SELECT TO service_role USING (true);
CREATE POLICY analyses_audit_service_insert ON analyses_audit
FOR INSERT TO service_role WITH CHECK (true);
CREATE POLICY analyses_audit_deny_public ON analyses_audit
FOR ALL TO anon, authenticated
USING (false) WITH CHECK (false);
-- cost_log: service_role only
DROP POLICY IF EXISTS cost_log_service_only ON cost_log;
DROP POLICY IF EXISTS cost_log_deny_public ON cost_log;
CREATE POLICY cost_log_service_only ON cost_log
FOR ALL TO service_role USING (true) WITH CHECK (true);
CREATE POLICY cost_log_deny_public ON cost_log
FOR ALL TO anon, authenticated
USING (false) WITH CHECK (false);
-- source_hashes: service_role only
DROP POLICY IF EXISTS source_hashes_service_only ON source_hashes;
DROP POLICY IF EXISTS source_hashes_deny_public ON source_hashes;
CREATE POLICY source_hashes_service_only ON source_hashes
FOR ALL TO service_role USING (true) WITH CHECK (true);
CREATE POLICY source_hashes_deny_public ON source_hashes
FOR ALL TO anon, authenticated
USING (false) WITH CHECK (false);
-- votes: public read (public record), service_role write
DROP POLICY IF EXISTS votes_public_read ON votes;
DROP POLICY IF EXISTS votes_service_write ON votes;
CREATE POLICY votes_public_read ON votes
FOR SELECT TO anon, authenticated
USING (is_figure_active(figure_id));
CREATE POLICY votes_service_write ON votes
FOR ALL TO service_role USING (true) WITH CHECK (true);
-- annotations: user sees only their own active (not soft-deleted), authenticated only
-- V8.0 FIX: Split policies  - no DELETE policy enforces soft-delete-only
DROP POLICY IF EXISTS annotations_user_only ON annotations;
DROP POLICY IF EXISTS annotations_user_select ON annotations;
DROP POLICY IF EXISTS annotations_user_insert ON annotations;
DROP POLICY IF EXISTS annotations_user_update ON annotations;
DROP POLICY IF EXISTS annotations_deny_delete ON annotations;
DROP POLICY IF EXISTS annotations_service_all ON annotations;
-- Users can only SEE their own non-deleted annotations
CREATE POLICY annotations_user_select ON annotations
FOR SELECT TO authenticated
USING (auth.uid() = user_id AND is_deleted = false);
-- Users can only INSERT their own annotations
CREATE POLICY annotations_user_insert ON annotations
FOR INSERT TO authenticated
WITH CHECK (auth.uid() = user_id);
-- Users can only UPDATE their own annotations (including soft-delete)
CREATE POLICY annotations_user_update ON annotations
FOR UPDATE TO authenticated
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);
-- No DELETE policy for authenticated = hard deletes denied by RLS
-- Soft-delete via UPDATE SET is_deleted = true
-- Service role has full access (for admin cleanup)
CREATE POLICY annotations_service_all ON annotations
FOR ALL TO service_role USING (true) WITH CHECK (true);
-- feature_flags: public read, service_role write
DROP POLICY IF EXISTS feature_flags_public_read ON feature_flags;
DROP POLICY IF EXISTS feature_flags_service_write ON feature_flags;
CREATE POLICY feature_flags_public_read ON feature_flags
FOR SELECT TO anon, authenticated USING (true);
CREATE POLICY feature_flags_service_write ON feature_flags
FOR ALL TO service_role USING (true) WITH CHECK (true);
-- Service-role writes on core tables
DROP POLICY IF EXISTS figures_service_write ON figures;
CREATE POLICY figures_service_write ON figures
FOR ALL TO service_role USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS statements_service_write ON statements;
CREATE POLICY statements_service_write ON statements
FOR ALL TO service_role USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS analyses_service_write ON analyses;
CREATE POLICY analyses_service_write ON analyses
FOR ALL TO service_role USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS consensus_service_write ON consensus;
CREATE POLICY consensus_service_write ON consensus
FOR ALL TO service_role USING (true) WITH CHECK (true);
-- ========================================================================
-- SEED DATA
-- ========================================================================
INSERT INTO figures (name, category, is_active, activation_order, allowlist_id, metadata)
VALUES
('Donald Trump', 'US_POLITICS', true, 1, 'donald-trump',
'{"title": "45th & 47th President", "notes": "Handles/sources managed in A0 allowlist"}'::jsonb),
('Elon Musk', 'AI_TECH', false, 2, 'elon-musk',
'{"title": "CEO Tesla, SpaceX, xAI", "notes": "Handles/sources managed in A0 allowlist"}'::jsonb)
ON CONFLICT (name) DO UPDATE SET allowlist_id = EXCLUDED.allowlist_id;
-- ========================================================================
-- HELPER FUNCTIONS
-- ========================================================================
CREATE OR REPLACE FUNCTION cosine_similarity(a vector, b vector)
RETURNS NUMERIC AS $$
BEGIN
RETURN 1 - (a <=> b);
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT PARALLEL SAFE;
-- "PRIOR ONLY" baseline window
CREATE OR REPLACE FUNCTION get_baseline_window(
p_figure_id UUID,
p_exclude_statement_id UUID,
p_max_statements INTEGER DEFAULT 50
)
RETURNS TABLE(
statement_id UUID,
embedding vector,
ts TIMESTAMPTZ,
time_weight NUMERIC
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
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
SELECT COUNT(*) INTO v_count
FROM statements s
WHERE s.figure_id = p_figure_id
AND s.statement_id <> p_exclude_statement_id
AND s.embedding IS NOT NULL
AND s.is_revoked = false
AND s.ingestion_time < v_cutoff_ingestion;
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
AND s.ingestion_time < v_cutoff_ingestion
ORDER BY s.timestamp DESC
LIMIT v_limit;
END;
$$;
CREATE OR REPLACE FUNCTION compute_baseline_delta(
p_figure_id UUID,
p_exclude_statement_id UUID,
p_embedding vector
)
RETURNS NUMERIC
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
v_weighted_distance NUMERIC := 0;
v_total_weight NUMERIC := 0;
v_row RECORD;
v_distance NUMERIC;
BEGIN
IF auth.role() IS DISTINCT FROM 'service_role' THEN
RAISE EXCEPTION 'forbidden';
END IF;
FOR v_row IN
SELECT * FROM get_baseline_window(p_figure_id, p_exclude_statement_id, 50)
LOOP
v_distance := (p_embedding <=> v_row.embedding);
v_weighted_distance := v_weighted_distance + (v_distance * v_row.time_weight);
v_total_weight := v_total_weight + v_row.time_weight;
END LOOP;
IF v_total_weight = 0 THEN
RETURN NULL;
END IF;
IF v_weighted_distance <> v_weighted_distance OR v_total_weight <> v_total_weight THEN
RETURN 0;
END IF;
RETURN LEAST(100, GREATEST(0, ((v_weighted_distance / v_total_weight) / 2.0) * 100));
END;
$$;
-- IDEMPOTENT embedding set-once + baseline_delta compute
CREATE OR REPLACE FUNCTION set_statement_embedding(
p_statement_id UUID,
p_embedding float8[]
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
v_figure_id UUID;
v_vec vector(1536);
v_delta NUMERIC;
BEGIN
IF auth.role() IS DISTINCT FROM 'service_role' THEN
RAISE EXCEPTION 'forbidden';
END IF;
IF p_embedding IS NULL OR array_length(p_embedding, 1) IS DISTINCT FROM 1536
THEN
RAISE EXCEPTION 'invalid embedding length (expected 1536)';
END IF;
v_vec := p_embedding::vector;
SELECT s.figure_id INTO v_figure_id
FROM statements s
WHERE s.statement_id = p_statement_id
FOR UPDATE;
IF v_figure_id IS NULL THEN
RETURN;
END IF;
UPDATE statements
SET embedding = v_vec
WHERE statement_id = p_statement_id
AND embedding IS NULL
AND is_revoked = false;
IF NOT FOUND THEN
RETURN;
END IF;
v_delta := compute_baseline_delta(v_figure_id, p_statement_id, v_vec);
IF v_delta IS NOT NULL THEN
UPDATE statements
SET baseline_delta = v_delta
WHERE statement_id = p_statement_id
AND baseline_delta IS NULL;
END IF;
END;
$$;
-- ========================================================================
-- THE RECEIPT™  - Find nearest historical match
-- ========================================================================
-- V8.0 FIX (B3): Changed to SECURITY INVOKER. RLS policies on statements
-- already enforce is_active + is_revoked + language checks, so this function
-- only sees RLS-visible rows. No need for SECURITY DEFINER.
-- ========================================================================
CREATE OR REPLACE FUNCTION get_receipt(
p_statement_id UUID,
p_limit INTEGER DEFAULT 1
)
RETURNS TABLE(
matched_statement_id UUID,
similarity NUMERIC,
matched_text TEXT,
matched_timestamp TIMESTAMPTZ,
matched_source_url TEXT
)
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
v_figure_id UUID;
v_embedding vector;
v_statement_ts TIMESTAMPTZ;
BEGIN
-- Get the source statement's figure and embedding
-- RLS filters apply automatically (SECURITY INVOKER)
SELECT s.figure_id, s.embedding, s.timestamp
INTO v_figure_id, v_embedding, v_statement_ts
FROM statements s
WHERE s.statement_id = p_statement_id;
IF v_figure_id IS NULL OR v_embedding IS NULL THEN
RETURN;
END IF;
-- Find most similar historical statements from same figure
-- RLS ensures only visible statements are returned
RETURN QUERY
SELECT
s.statement_id,
(1 - (s.embedding <=> v_embedding))::NUMERIC AS similarity,
s.text,
s.timestamp,
s.source_url
FROM statements s
WHERE s.figure_id = v_figure_id
AND s.statement_id <> p_statement_id
AND s.embedding IS NOT NULL
AND s.timestamp < v_statement_ts -- Only OLDER statements
ORDER BY s.embedding <=> v_embedding ASC
LIMIT LEAST(p_limit, 5); -- Cap at 5 for safety
END;
$$;
-- ========================================================================
-- insert_analysis_single (explicit numeric range validation)
-- ========================================================================
CREATE OR REPLACE FUNCTION insert_analysis_single(
p_statement_id UUID,
p_model_provider TEXT,
p_model_version TEXT,
p_prompt_version TEXT,
p_result JSONB,
p_raw_response JSONB
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
v_analysis_id UUID;
v_framing TEXT;
v_repetition NUMERIC;
v_novelty NUMERIC;
v_affective NUMERIC;
v_entropy NUMERIC;
BEGIN
IF auth.role() IS DISTINCT FROM 'service_role' THEN
RAISE EXCEPTION 'forbidden';
END IF;
IF p_model_provider NOT IN ('OPENAI', 'ANTHROPIC', 'XAI') THEN
RAISE EXCEPTION 'Invalid model_provider: %', p_model_provider;
END IF;
v_framing := p_result->>'framing';
IF v_framing IS NULL THEN
RAISE EXCEPTION '% framing missing', p_model_provider;
END IF;
IF v_framing NOT IN (
'Adversarial / Oppositional',
'Problem Identification',
'Commitment / Forward-Looking',
'Justification / Reactive',
'Imperative / Directive'
) THEN
RAISE EXCEPTION '% framing invalid: "%"', p_model_provider, v_framing;
END IF;
IF (p_result->>'repetition') IS NULL OR
(p_result->>'novelty') IS NULL OR
(p_result->>'affective_language_rate') IS NULL OR
(p_result->>'topic_entropy') IS NULL THEN
RAISE EXCEPTION '% result missing required numeric fields', p_model_provider;
END IF;
BEGIN
v_repetition := (p_result->>'repetition')::numeric;
v_novelty := (p_result->>'novelty')::numeric;
v_affective := (p_result->>'affective_language_rate')::numeric;
v_entropy := (p_result->>'topic_entropy')::numeric;
EXCEPTION WHEN OTHERS THEN
RAISE EXCEPTION '% result contains non-numeric metric values', p_model_provider;
END;
IF v_repetition < 0 OR v_repetition > 100 THEN
RAISE EXCEPTION '% repetition out of range [0,100]: %', p_model_provider, v_repetition;
END IF;
IF v_novelty < 0 OR v_novelty > 100 THEN
RAISE EXCEPTION '% novelty out of range [0,100]: %', p_model_provider, v_novelty;
END IF;
IF v_affective < 0 OR v_affective > 100 THEN
RAISE EXCEPTION '% affective_language_rate out of range [0,100]: %',
p_model_provider, v_affective;
END IF;
IF v_entropy < 0 OR v_entropy > 100 THEN
RAISE EXCEPTION '% topic_entropy out of range [0,100]: %', p_model_provider,
v_entropy;
END IF;
INSERT INTO analyses(
statement_id, model_provider, model_version, prompt_version,
repetition, novelty, affective_language_rate, topic_entropy, framing
)
VALUES (
p_statement_id, p_model_provider, p_model_version, p_prompt_version,
v_repetition, v_novelty, v_affective, v_entropy, v_framing
)
ON CONFLICT (statement_id, model_provider) DO NOTHING;
SELECT analysis_id INTO v_analysis_id
FROM analyses
WHERE statement_id = p_statement_id
AND model_provider = p_model_provider;
IF v_analysis_id IS NULL THEN
RAISE EXCEPTION 'Failed to insert or find analysis for % / %', p_statement_id,
p_model_provider;
END IF;
INSERT INTO analyses_audit (analysis_id, raw_response)
VALUES (v_analysis_id, p_raw_response)
ON CONFLICT (analysis_id) DO NOTHING;
RETURN v_analysis_id;
END;
$$;
-- ========================================================================
-- insert_analyses_pair (NULL guard for XAI)
-- ========================================================================
CREATE OR REPLACE FUNCTION insert_analyses_pair(
p_statement_id UUID,
p_prompt_version TEXT,
p_openai_model_version TEXT,
p_openai_result JSONB,
p_openai_raw JSONB,
p_anthropic_model_version TEXT,
p_anthropic_result JSONB,
p_anthropic_raw JSONB,
p_xai_model_version TEXT DEFAULT NULL,
p_xai_result JSONB DEFAULT NULL,
p_xai_raw JSONB DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
IF auth.role() IS DISTINCT FROM 'service_role' THEN
RAISE EXCEPTION 'forbidden';
END IF;
PERFORM insert_analysis_single(
p_statement_id, 'OPENAI', p_openai_model_version, p_prompt_version,
p_openai_result, p_openai_raw
);
PERFORM insert_analysis_single(
p_statement_id, 'ANTHROPIC', p_anthropic_model_version, p_prompt_version,
p_anthropic_result, p_anthropic_raw
);
IF p_xai_model_version IS NOT NULL THEN
IF p_xai_result IS NULL OR p_xai_raw IS NULL THEN
RAISE EXCEPTION 'XAI result/raw required when xai_model_version is provided';
END IF;
PERFORM insert_analysis_single(
p_statement_id, 'XAI', p_xai_model_version, p_prompt_version,
p_xai_result, p_xai_raw
);
END IF;
END;
$$;
-- ========================================================================
-- insert_consensus (internal consistency validation)
-- ========================================================================
CREATE OR REPLACE FUNCTION insert_consensus(
p_statement_id UUID,
p_repetition_avg NUMERIC,
p_novelty_avg NUMERIC,
p_baseline_delta_avg NUMERIC,
p_affective_language_rate_avg NUMERIC,
p_topic_entropy_avg NUMERIC,
p_repetition_stddev NUMERIC,
p_novelty_stddev NUMERIC,
p_baseline_delta_stddev NUMERIC,
p_affective_language_rate_stddev NUMERIC,
p_topic_entropy_stddev NUMERIC,
p_framing_consensus TEXT,
p_framing_agreement_count INTEGER,
p_framing_split JSONB,
p_signal_components JSONB,
p_signal_rank NUMERIC,
p_model_versions JSONB,
p_model_count INTEGER,
p_models_included TEXT[],
p_variance_detected BOOLEAN
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
v_consensus_id UUID;
BEGIN
IF auth.role() IS DISTINCT FROM 'service_role' THEN
RAISE EXCEPTION 'forbidden';
END IF;
IF NOT EXISTS (
SELECT 1 FROM statements
WHERE statement_id = p_statement_id AND is_revoked = false
) THEN
RAISE EXCEPTION 'Statement % does not exist or is revoked', p_statement_id;
END IF;
IF p_model_count < 2 OR p_model_count > 3 THEN
RAISE EXCEPTION 'model_count must be 2 or 3, got %', p_model_count;
END IF;
IF array_length(p_models_included, 1) IS DISTINCT FROM p_model_count THEN
RAISE EXCEPTION 'models_included length (%) must equal model_count (%)',
array_length(p_models_included, 1), p_model_count;
END IF;
IF p_framing_agreement_count < 1 OR p_framing_agreement_count > p_model_count
THEN
RAISE EXCEPTION 'framing_agreement_count (%) must be between 1 and model_count
(%)',
p_framing_agreement_count, p_model_count;
END IF;
IF jsonb_typeof(p_model_versions) IS DISTINCT FROM 'object' THEN
RAISE EXCEPTION 'model_versions must be a JSON object, got %',
jsonb_typeof(p_model_versions);
END IF;
IF p_framing_consensus IS NOT NULL AND p_framing_consensus NOT IN (
'Adversarial / Oppositional',
'Problem Identification',
'Commitment / Forward-Looking',
'Justification / Reactive',
'Imperative / Directive'
) THEN
RAISE EXCEPTION 'Invalid framing_consensus: %', p_framing_consensus;
END IF;
IF NOT (
p_signal_components ? 'repetition' AND
p_signal_components ? 'novelty' AND
p_signal_components ? 'baseline_delta'
) THEN
RAISE EXCEPTION 'signal_components missing required keys';
END IF;
INSERT INTO consensus (
statement_id,
repetition_avg, novelty_avg, baseline_delta_avg,
affective_language_rate_avg, topic_entropy_avg,
repetition_stddev, novelty_stddev, baseline_delta_stddev,
affective_language_rate_stddev, topic_entropy_stddev,
framing_consensus, framing_agreement_count, framing_split,
signal_components, signal_rank, model_versions,
model_count, models_included, variance_detected
)
VALUES (
p_statement_id,
p_repetition_avg, p_novelty_avg, p_baseline_delta_avg,
p_affective_language_rate_avg, p_topic_entropy_avg,
COALESCE(p_repetition_stddev, 0), COALESCE(p_novelty_stddev, 0),
COALESCE(p_baseline_delta_stddev, 0), COALESCE(p_affective_language_rate_stddev,
0),
COALESCE(p_topic_entropy_stddev, 0),
p_framing_consensus, p_framing_agreement_count, p_framing_split,
p_signal_components, p_signal_rank, p_model_versions,
p_model_count, p_models_included, COALESCE(p_variance_detected, false)
)
ON CONFLICT (statement_id) DO NOTHING
RETURNING consensus_id INTO v_consensus_id;
IF v_consensus_id IS NULL THEN
SELECT consensus_id INTO v_consensus_id
FROM consensus WHERE statement_id = p_statement_id;
END IF;
RETURN v_consensus_id;
END;
$$;
-- ========================================================================
-- revoke_statement (safe revocation RPC)
-- ========================================================================
CREATE OR REPLACE FUNCTION revoke_statement(
p_statement_id UUID,
p_reason TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
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
revocation_reason = trim(p_reason)
WHERE statement_id = p_statement_id
AND is_revoked = false;
v_updated := FOUND;
RETURN v_updated;
END;
$$;
-- ========================================================================
-- activate_figure
-- ========================================================================
CREATE OR REPLACE FUNCTION activate_figure(p_name TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
IF auth.role() IS DISTINCT FROM 'service_role' THEN
RAISE EXCEPTION 'forbidden';
END IF;
UPDATE figures SET is_active = true WHERE name = p_name AND is_active = false;
RETURN FOUND;
END;
$$;
-- ========================================================================
-- ADVISORY LOCKS
-- ========================================================================
CREATE OR REPLACE FUNCTION acquire_embedding_lock(p_statement_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
v_lock_id BIGINT;
BEGIN
IF auth.role() IS DISTINCT FROM 'service_role' THEN
RAISE EXCEPTION 'forbidden';
END IF;
v_lock_id := ('x' || substring(md5(p_statement_id::text) from 1 for 15))::bit(60)::bigint;
RETURN pg_try_advisory_lock(v_lock_id);
END;
$$;
CREATE OR REPLACE FUNCTION release_embedding_lock(p_statement_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
v_lock_id BIGINT;
BEGIN
IF auth.role() IS DISTINCT FROM 'service_role' THEN
RAISE EXCEPTION 'forbidden';
END IF;
v_lock_id := ('x' || substring(md5(p_statement_id::text) from 1 for 15))::bit(60)::bigint;
RETURN pg_advisory_unlock(v_lock_id);
END;
$$;
-- ========================================================================
-- update_source_last_checked helper
-- ========================================================================
CREATE OR REPLACE FUNCTION update_source_last_checked(p_statement_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
IF auth.role() IS DISTINCT FROM 'service_role' THEN
RAISE EXCEPTION 'forbidden';
END IF;
UPDATE statements
SET source_last_checked = now()
WHERE statement_id = p_statement_id;
END;
$$;
-- ========================================================================
-- FRAMING RADAR™ VIEW
-- ========================================================================
-- Aggregates framing patterns per figure over time.
-- Zero AI cost  - pure SQL aggregation on existing data.
-- A15A adds a more flexible rolling-window version.
-- ========================================================================
CREATE OR REPLACE VIEW framing_radar AS
SELECT
f.figure_id,
f.name AS figure_name,
a.framing,
COUNT(*) AS framing_count,
date_trunc('month', s.timestamp) AS month
FROM analyses a
JOIN statements s ON s.statement_id = a.statement_id
JOIN figures f ON f.figure_id = s.figure_id
WHERE s.is_revoked = false
AND f.is_active = true
GROUP BY f.figure_id, f.name, a.framing, date_trunc('month', s.timestamp);
-- ========================================================================
-- WAR ROOM™ VIEW
-- ========================================================================
-- Surfaces model disagreement explicitly.
-- Zero AI cost  - queries existing analyses table.
-- ========================================================================
CREATE OR REPLACE VIEW war_room AS
SELECT
s.statement_id,
s.text,
s.timestamp,
s.figure_id,
f.name AS figure_name,
c.variance_detected,
c.framing_consensus,
c.framing_split,
c.repetition_stddev,
c.novelty_stddev,
c.baseline_delta_stddev,
jsonb_object_agg(
a.model_provider,
jsonb_build_object(
'repetition', a.repetition,
'novelty', a.novelty,
'affective_language_rate', a.affective_language_rate,
'topic_entropy', a.topic_entropy,
'framing', a.framing
)
) AS model_scores
FROM statements s
JOIN figures f ON f.figure_id = s.figure_id
JOIN consensus c ON c.statement_id = s.statement_id
JOIN analyses a ON a.statement_id = s.statement_id
WHERE s.is_revoked = false
AND f.is_active = true
GROUP BY
s.statement_id, s.text, s.timestamp, s.figure_id, f.name,
c.variance_detected, c.framing_consensus, c.framing_split,
c.repetition_stddev, c.novelty_stddev, c.baseline_delta_stddev;
-- ========================================================================
-- VIEW GRANTS
-- ========================================================================
-- V8.0 FIX (H2): Explicit grants on views for public access.
-- ========================================================================
GRANT SELECT ON framing_radar TO anon, authenticated;
GRANT SELECT ON war_room TO anon, authenticated;
-- ========================================================================
-- RPC EXECUTION LOCKDOWN
-- ========================================================================
REVOKE ALL ON FUNCTION get_baseline_window(UUID, UUID, INTEGER) FROM PUBLIC;
REVOKE ALL ON FUNCTION compute_baseline_delta(UUID, UUID, vector) FROM PUBLIC;
REVOKE ALL ON FUNCTION set_statement_embedding(UUID, float8[]) FROM PUBLIC;
REVOKE ALL ON FUNCTION insert_analysis_single(UUID, TEXT, TEXT, TEXT, JSONB,
JSONB) FROM PUBLIC;
REVOKE ALL ON FUNCTION insert_analyses_pair(UUID, TEXT, TEXT, JSONB, JSONB,
TEXT, JSONB, JSONB, TEXT, JSONB, JSONB) FROM PUBLIC;
REVOKE ALL ON FUNCTION insert_consensus(UUID, NUMERIC, NUMERIC, NUMERIC,
NUMERIC, NUMERIC, NUMERIC, NUMERIC, NUMERIC, NUMERIC, NUMERIC, TEXT,
INTEGER, JSONB, JSONB, NUMERIC, JSONB, INTEGER, TEXT[], BOOLEAN) FROM
PUBLIC;
REVOKE ALL ON FUNCTION revoke_statement(UUID, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION activate_figure(TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION acquire_embedding_lock(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION release_embedding_lock(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION update_source_last_checked(UUID) FROM PUBLIC;
-- get_receipt is PUBLIC (SECURITY INVOKER  - RLS filters automatically)
GRANT EXECUTE ON FUNCTION get_receipt(UUID, INTEGER) TO anon, authenticated;
-- Topic validation helpers (used by CHECK constraints)
GRANT EXECUTE ON FUNCTION is_valid_topic(TEXT) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION are_valid_topics(TEXT[]) TO anon, authenticated,
service_role;
-- Service-role RPCs
GRANT EXECUTE ON FUNCTION get_baseline_window(UUID, UUID, INTEGER) TO
service_role;
GRANT EXECUTE ON FUNCTION compute_baseline_delta(UUID, UUID, vector) TO
service_role;
GRANT EXECUTE ON FUNCTION set_statement_embedding(UUID, float8[]) TO service_role;
GRANT EXECUTE ON FUNCTION insert_analysis_single(UUID, TEXT, TEXT, TEXT, JSONB,
JSONB) TO service_role;
GRANT EXECUTE ON FUNCTION insert_analyses_pair(UUID, TEXT, TEXT, JSONB, JSONB,
TEXT, JSONB, JSONB, TEXT, JSONB, JSONB) TO service_role;
GRANT EXECUTE ON FUNCTION insert_consensus(UUID, NUMERIC, NUMERIC, NUMERIC,
NUMERIC, NUMERIC, NUMERIC, NUMERIC, NUMERIC, NUMERIC, NUMERIC, TEXT,
INTEGER, JSONB, JSONB, NUMERIC, JSONB, INTEGER, TEXT[], BOOLEAN) TO
service_role;
GRANT EXECUTE ON FUNCTION revoke_statement(UUID, TEXT) TO service_role;
GRANT EXECUTE ON FUNCTION activate_figure(TEXT) TO service_role;
GRANT EXECUTE ON FUNCTION acquire_embedding_lock(UUID) TO service_role;
GRANT EXECUTE ON FUNCTION release_embedding_lock(UUID) TO service_role;
GRANT EXECUTE ON FUNCTION update_source_last_checked(UUID) TO service_role;
-- ========================================================================
-- END A1  - V8.0
-- ========================================================================

