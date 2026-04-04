-- ========================================================================
-- MIGRATION: Public Read Views (Baseline V1.4)  - A9A V1.0.2
-- File: migrations/create_public_read_views.sql
-- Creates read-only views for the serving layer. No embeddings, no raw LLM
-- responses, no internal audit fields exposed.
--
-- FIXES APPLIED (V1.0.0 → V1.0.1):
-- B1: v_statements_public filters is_revoked + joins figures for is_active + figure_name
-- B2: v_feed_ranked filters is_revoked (revoked = gone from public APIs)
-- B3: Column aliases match API contract (statement_text, context_before, etc.)
-- H1: v_statement_analysis includes analysis_id
-- H2: v_statement_consensus includes consensus_id
-- H3: Removed baseline_delta_stddev (A7B doesn't write it)
-- H4: Added topics column to v_statements_public
-- M1: Updated to V1.4
-- M2: v_feed_ranked joins figures for figure_name
-- M3: topics exposed in v_statements_public and v_feed_ranked
--
-- FIXES APPLIED (V1.0.1 → V1.0.2  - A1 V8.0 reconciliation):
-- FIX1: s.source_type removed (column does not exist in A1 V8.0)
-- FIX2: s.source_timestamp → s.timestamp (A1 V8.0 column name)
-- FIX3: a.created_at → a.analyzed_at (A1 V8.0 column name)
-- FIX4: c.created_at → c.computed_at (A1 V8.0 column name)
--
-- CRITICAL SECURITY NOTE:
-- Views MUST use security_invoker=true to ensure RLS is enforced for anon/auth.
-- Without this, a view owned by a privileged role can bypass RLS.
--
-- Safety:
-- CREATE OR REPLACE VIEW  - idempotent
-- No table modifications
-- No data writes
-- ========================================================================
-- ── v_statements_public──────────────────────────────────────────────────────
-- Filters is_revoked + is_active at view layer.
-- Aliases match API contract (statement_text, context_before, etc.)
-- Includes topics, figure_name via JOIN.
-- V1.0.2: Removed source_type, fixed timestamp column name.
--─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE VIEW v_statements_public
WITH (security_invoker = true)
AS
SELECT
s.statement_id,
s.figure_id,
f.name AS figure_name,
s.text AS statement_text,
s.context_pre AS context_before,
s.context_post AS context_after,
s.source_url,
s.timestamp AS stated_at,
s.ingestion_time,
s.baseline_delta,
s.topics,
(s.embedding IS NOT NULL) AS embedding_present
FROM statements s
JOIN figures f ON f.figure_id = s.figure_id
WHERE s.is_revoked = false
AND f.is_active = true;
COMMENT ON VIEW v_statements_public IS
'Public statement view. Filters revoked + inactive figures. '
'Aliases match API contract. No embedding vector, no extraction metadata. '
'security_invoker=true to enforce RLS for anon/auth callers.';
-- ── v_statement_analysis─────────────────────────────────────────────────────
-- Per-provider analysis scores. Excludes raw API responses (analyses_audit).
-- V1.0.2: Fixed analyzed_at column name (was incorrectly aliased from created_at).
--─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE VIEW v_statement_analysis
WITH (security_invoker = true)
AS
SELECT
a.analysis_id,
a.statement_id,
a.model_provider,
a.model_version,
a.prompt_version,
a.repetition,
a.novelty,
a.affective_language_rate,
a.topic_entropy,
a.framing,
a.analyzed_at
FROM analyses a;
COMMENT ON VIEW v_statement_analysis IS
'Per-provider analysis scores. Excludes raw API responses (analyses_audit). '
'security_invoker=true to enforce RLS for anon/auth callers.';
-- ── v_statement_consensus────────────────────────────────────────────────────
-- Aggregated consensus metrics.
-- V1.0.2: Fixed computed_at column name (was incorrectly aliased from created_at).
--─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE VIEW v_statement_consensus
WITH (security_invoker = true)
AS
SELECT
c.consensus_id,
c.statement_id,
c.repetition_avg,
c.repetition_stddev,
c.novelty_avg,
c.novelty_stddev,
c.affective_language_rate_avg,
c.affective_language_rate_stddev,
c.topic_entropy_avg,
c.topic_entropy_stddev,
c.baseline_delta_avg,
c.signal_rank,
c.variance_detected,
c.framing_consensus,
c.framing_agreement_count,
c.framing_split,
c.models_included,
c.model_count,
c.model_versions,
c.signal_components,
c.computed_at
FROM consensus c;
COMMENT ON VIEW v_statement_consensus IS
'Aggregated consensus metrics. Only exists for statements with baseline_delta. '
'Statements 1-29 per figure have no consensus row. '
'security_invoker=true to enforce RLS for anon/auth callers.';
-- ── v_feed_ranked────────────────────────────────────────────────────────────
-- Feed view with rank status categorization.
-- V1.0.2: Removed source_type, fixed timestamp + computed_at column names.
--─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE VIEW v_feed_ranked
WITH (security_invoker = true)
AS
SELECT
s.statement_id,
s.figure_id,
f.name AS figure_name,
f.photo_url AS figure_photo_url,
s.text AS statement_text,
s.context_pre AS context_before,
s.context_post AS context_after,
s.source_url,
s.timestamp AS stated_at,
s.ingestion_time,
s.baseline_delta,
s.topics,
CASE
WHEN c.consensus_id IS NOT NULL THEN 'RANKED'
WHEN s.baseline_delta IS NULL THEN 'UNRANKED_EARLY'
ELSE 'UNRANKED_PENDING'
END AS rank_status,
c.signal_rank,
c.variance_detected,
c.novelty_avg,
c.repetition_avg,
c.affective_language_rate_avg,
c.topic_entropy_avg,
c.baseline_delta_avg,
c.framing_consensus,
c.model_count,
c.computed_at AS consensus_computed_at
FROM statements s
JOIN figures f ON f.figure_id = s.figure_id
LEFT JOIN consensus c ON c.statement_id = s.statement_id
WHERE s.is_revoked = false
AND f.is_active = true;
COMMENT ON VIEW v_feed_ranked IS
'Feed view with rank status categorization. '
'RANKED = has consensus, UNRANKED_EARLY = baseline_delta NULL (statements 1-29), '
'UNRANKED_PENDING = eligible for consensus but not yet computed. '
'Revoked + inactive figures excluded. '
'security_invoker=true to enforce RLS for anon/auth callers.';
-- ── GRANTS───────────────────────────────────────────────────────────────────
GRANT SELECT ON v_statements_public TO anon, authenticated;
GRANT SELECT ON v_statement_analysis TO anon, authenticated;
GRANT SELECT ON v_statement_consensus TO anon, authenticated;
GRANT SELECT ON v_feed_ranked TO anon, authenticated;
-- ========================================================================
-- END A9A  - V1.0.2
-- ========================================================================

