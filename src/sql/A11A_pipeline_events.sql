-- ========================================================================
-- A11A v1.0.2: pipeline_events (Baseline V1.4)  - FINAL
-- File: migrations/create_pipeline_events.sql
--
-- Observability table for pipeline activity. Best-effort logging  -
-- failures never block pipeline execution.
--
-- FIXES APPLIED (V1.0.0 → V1.0.1):
-- B1: Column names aligned to what artifacts write (event_type, details)
-- B2: RPC signature aligned to artifact callers (or removed if unused)
-- B3: Write policy fixed (service_role bypasses RLS; remove dead policy)
-- H1: Stage enum values aligned to artifact constants
-- H2: Added security comment re: public read + metadata
-- H3: Added retention comment
-- M1: FK actions ON DELETE CASCADE → SET NULL (preserve events for debugging)
-- M2: Added FORCE ROW LEVEL SECURITY
--
-- FIXES APPLIED (V1.0.1 → V1.0.2  - RECONCILED FROM GPT + GROK AUDITS):
-- 1: Expanded event_type CHECK to cover all values artifacts emit
-- 2: Removed RPC entirely (artifacts use direct insert via service_role)
--
-- CROSS-ARTIFACT DEPENDENCIES:
-- A4 (generate-embedding): logPipelineEvent → direct insert (statement_id, stage,
-- event_type, details)
-- A6 (embedding choreographer): same pattern
-- A7A (analyze-statement): same pattern
-- A7B (compute-consensus): same pattern
--
-- SECURITY NOTE:
-- pipeline_events is publicly readable (MVP choice). Treat as public telemetry.
-- Do NOT log secrets, API keys, stack traces, or PII in the details JSONB.
-- If this policy changes, replace the anon SELECT policy with service-role only.
-- ========================================================================
CREATE TABLE IF NOT EXISTS pipeline_events (
event_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
statement_id UUID NULL REFERENCES statements(statement_id) ON DELETE SET NULL,
-- V1.0.1 FIX (B1): Column names match what artifacts actually write
stage TEXT NOT NULL CHECK (stage IN (
'INGESTION',
'STRUCTURING',
'PERSISTENCE',
'EMBEDDING',
'ANALYSIS',
'CONSENSUS',
'ORCHESTRATOR',
'VOTES',
'ROSTER_SYNC',
'DISTRIBUTION'
)),
-- V1.0.2 FIX (1): Expanded to cover all values artifacts emit
event_type TEXT NOT NULL CHECK (event_type IN (
'START', 'SUCCESS', 'ERROR', 'SKIP', 'INFO', 'WARN',
'KILLSWITCH', 'DEFERRED', 'NOT_READY'
)),
details JSONB DEFAULT '{}'::jsonb,
created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
-- ── Indexes──────────────────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_pipeline_events_recent_errors
ON pipeline_events (created_at DESC)
WHERE event_type = 'ERROR';
CREATE INDEX IF NOT EXISTS idx_pipeline_events_statement
ON pipeline_events (statement_id, created_at DESC)
WHERE statement_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_pipeline_events_stage
ON pipeline_events (stage, event_type, created_at DESC);
-- ── RLS──────────────────────────────────────────────────────────────────────
ALTER TABLE pipeline_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE pipeline_events FORCE ROW LEVEL SECURITY;
-- V1.0.1 FIX (B3): Service_role bypasses RLS entirely in Supabase.
-- No write policy needed  - Edge Functions use service_role key for inserts.
-- Public read for MVP observability:
DROP POLICY IF EXISTS pipeline_events_public_read ON pipeline_events;
CREATE POLICY pipeline_events_public_read
ON pipeline_events
FOR SELECT
TO anon, authenticated
USING (true);
-- V1.0.2 FIX (2): RPC removed. Artifacts use direct PostgREST insert via service_role.
-- Service_role bypasses RLS, so no write policy needed.
-- If an RPC is needed in future, use SECURITY INVOKER + grant to service_role only.
-- ── RETENTION NOTE───────────────────────────────────────────────────────────
-- pipeline_events will grow unbounded. For production:
-- Option A: Cron job to DELETE WHERE created_at < now() - INTERVAL '30 days'
-- Option B: pg_partman with monthly partitions
-- Not implemented in MVP; monitor row count via:
-- SELECT COUNT(*), pg_size_pretty(pg_total_relation_size('pipeline_events'))
-- FROM pipeline_events;
