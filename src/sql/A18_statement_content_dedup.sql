-- ========================================================================
-- A18  - Statement Content Dedup Index
-- ========================================================================
-- Defense-in-depth: prevents inserting the same verbatim statement text
-- for the same figure from different source URL variants.
-- This guards against scraper URL normalization failures that bypass
-- the (figure_id, source_url, source_hash, text) unique constraint.
--
-- Uses md5(text) to keep the index compact. Collision probability is
-- negligible for our scale (<1M statements).
--
-- Only applies to non-revoked statements  - revoked rows are kept for
-- audit trail and don't affect the active dataset.
-- ========================================================================

CREATE UNIQUE INDEX IF NOT EXISTS uq_statements_figure_text
ON statements(figure_id, md5(text))
WHERE is_revoked = false;
