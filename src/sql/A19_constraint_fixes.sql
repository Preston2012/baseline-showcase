-- ========================================================================
-- A19  - Constraint Fixes for Workflow Compatibility
-- ========================================================================
-- Fixes CHECK constraints that reject valid values written by n8n workflows:
--
-- 1. cost_log.provider: A7C writes 'A7C' for poison pill entries → add 'ORCHESTRATOR'
-- 2. cost_log.operation: A6 writes 'EMBED_ERROR' → already has 'EMBEDDING_ERROR'
--    (workflow should be fixed to use correct value, but keep both for safety)
-- 3. pipeline_events.stage: A16B writes 'VOTES', A16D writes 'ROSTER_SYNC',
--    PM_TW1 writes 'DISTRIBUTION' → extend enum
--
-- All changes are idempotent (DROP + re-ADD pattern).
-- ========================================================================

-- 1. Extend cost_log.provider to include 'ORCHESTRATOR'
DO $$
BEGIN
  ALTER TABLE cost_log DROP CONSTRAINT IF EXISTS cost_log_provider_check;
  ALTER TABLE cost_log ADD CONSTRAINT cost_log_provider_check
    CHECK (provider IN ('GEMINI', 'OPENAI', 'ANTHROPIC', 'XAI', 'ORCHESTRATOR'));
EXCEPTION WHEN undefined_table THEN NULL;
END $$;

-- 2. Extend cost_log.operation to include 'EMBED_ERROR' (alias safety)
DO $$
BEGIN
  ALTER TABLE cost_log DROP CONSTRAINT IF EXISTS cost_log_operation_check;
  ALTER TABLE cost_log ADD CONSTRAINT cost_log_operation_check
    CHECK (operation IN (
      'INGESTION', 'ANALYSIS', 'EMBEDDING', 'CONSENSUS', 'BACKFILL',
      'ANALYSIS_ERROR', 'CONSENSUS_ERROR', 'EMBEDDING_ERROR', 'EMBED_ERROR'
    ));
EXCEPTION WHEN undefined_table THEN NULL;
END $$;

-- 3. Extend pipeline_events.stage to include workflow stages
DO $$
BEGIN
  ALTER TABLE pipeline_events DROP CONSTRAINT IF EXISTS pipeline_events_stage_check;
  ALTER TABLE pipeline_events ADD CONSTRAINT pipeline_events_stage_check
    CHECK (stage IN (
      'INGESTION', 'STRUCTURING', 'PERSISTENCE', 'EMBEDDING',
      'ANALYSIS', 'CONSENSUS', 'ORCHESTRATOR',
      'VOTES', 'ROSTER_SYNC', 'DISTRIBUTION'
    ));
EXCEPTION WHEN undefined_table THEN NULL;
END $$;
