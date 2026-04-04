-- ========================================================================
-- A10B v1.0.2: MIGRATION  - Orchestrator State Lock (Baseline V1.4)  - FINAL
-- File: migrations/create_system_orchestrator.sql
--
-- Purpose:
-- Durable singleton state row (pool-safe) for master orchestrator lock.
-- Prevents permanent lock jams in n8n (replaces session-scoped advisory locks).
--
-- FIXES APPLIED (V1.0.0 → V1.0.1):
-- B1: RLS enforced  - service_role only (anon/auth cannot touch this table)
-- H1: status CHECK constraint ('idle', 'running')
-- M1: Updated to V1.4
-- M2: Added updated_at column with auto-trigger
--
-- FIXES APPLIED (V1.0.1 → V1.0.2  - RECONCILED FROM GPT + GROK AUDITS):
-- 1: Added FORCE ROW LEVEL SECURITY (prevents table owner bypass)
-- 2: Added CHECK constraint for claimed_at/claimed_by vs status invariants
--
-- CROSS-ARTIFACT DEPENDENCIES:
-- A10A: Reads/writes this table (claim, heartbeat, release)
-- ========================================================================
CREATE TABLE IF NOT EXISTS system_orchestrator (
id INT PRIMARY KEY CHECK (id = 1),
status TEXT NOT NULL DEFAULT 'idle'
CHECK (status IN ('idle', 'running')),
last_heartbeat TIMESTAMPTZ NOT NULL DEFAULT now(),
claimed_at TIMESTAMPTZ,
claimed_by TEXT,
updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
-- V1.0.2 FIX (2): Enforce claimed state invariants
-- running → claimed_at and claimed_by must be set
-- idle → claimed_at and claimed_by must be null
CONSTRAINT chk_claimed_state CHECK (
(status = 'running' AND claimed_at IS NOT NULL AND claimed_by IS NOT NULL)
OR
(status = 'idle' AND claimed_at IS NULL AND claimed_by IS NULL)
)
);
-- Seed singleton row (idempotent)
INSERT INTO system_orchestrator (id, status)
VALUES (1, 'idle')
ON CONFLICT (id) DO NOTHING;
-- Auto-update updated_at on any change
CREATE OR REPLACE FUNCTION trg_system_orchestrator_updated_at()
RETURNS TRIGGER AS $$
BEGIN
NEW.updated_at = now();
RETURN NEW;
END;
$$ LANGUAGE plpgsql;
DROP TRIGGER IF EXISTS set_updated_at ON system_orchestrator;
CREATE TRIGGER set_updated_at
BEFORE UPDATE ON system_orchestrator
FOR EACH ROW
EXECUTE FUNCTION trg_system_orchestrator_updated_at();
-- V1.0.1 FIX (B1): RLS enforced  - service_role only
-- Anon/auth must NEVER touch orchestrator state
ALTER TABLE system_orchestrator ENABLE ROW LEVEL SECURITY;
-- V1.0.2 FIX (1): FORCE prevents table owner from bypassing RLS
ALTER TABLE system_orchestrator FORCE ROW LEVEL SECURITY;
REVOKE ALL ON system_orchestrator FROM anon, authenticated;
-- Service role bypasses RLS by default in Supabase.
-- No explicit policy needed  - only service_role can access.
