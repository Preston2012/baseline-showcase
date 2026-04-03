-- ========================================================================
-- MIGRATION: Statement Quality Gate — A17 V1.0.0
-- File: A17_statement_quality.sql
-- ========================================================================
--
-- Creates:
--   1. sanitize_statement_text()  — IMMUTABLE text cleaner for views
--   2. statement_quality_score()  — returns quality score 0-100
--   3. revoke_low_quality_statements() — batch auto-revoke
--   4. Updated v_statements_public / v_feed_ranked with sanitizer
--
-- The statements table is IMMUTABLE (A12A trigger). We cannot modify text
-- in place. Strategy:
--   - Sanitize at READ time via views (safety net, always-on)
--   - Revoke truly bad statements (is_revoked is the only allowed flip)
--   - Future: sanitize BEFORE INSERT in pipeline code
--
-- Safety:
--   CREATE OR REPLACE — idempotent
--   Only modifies views (no table schema changes)
--   revoke function requires explicit call (not a trigger)
-- ========================================================================

-- ════════════════════════════════════════════════════════════════════════
-- 1. TEXT SANITIZER
-- ════════════════════════════════════════════════════════════════════════
-- IMMUTABLE + PARALLEL SAFE so it can be used in views and indexes.
-- Handles: HTML entities, mojibake (UTF-8 as Latin-1), zero-width chars,
-- excessive whitespace, stray HTML tags, common encoding artifacts.

CREATE OR REPLACE FUNCTION sanitize_statement_text(raw_text TEXT)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE STRICT PARALLEL SAFE
AS $$
DECLARE
  t TEXT := raw_text;
BEGIN
  -- ── Phase 1: Fix mojibake (UTF-8 bytes misread as Windows-1252) ─────
  -- These are the literal character sequences stored when double-encoding occurs.
  t := REPLACE(t, E'\u00E2\u0080\u0099', E'\u2019');  -- ' right single quote
  t := REPLACE(t, E'\u00E2\u0080\u0098', E'\u2018');  -- ' left single quote
  t := REPLACE(t, E'\u00E2\u0080\u009C', E'\u201C');  -- " left double quote
  t := REPLACE(t, E'\u00E2\u0080\u009D', E'\u201D');  -- " right double quote
  t := REPLACE(t, E'\u00E2\u0080\u0094', E'\u2014');  -- — em dash
  t := REPLACE(t, E'\u00E2\u0080\u0093', E'\u2013');  -- – en dash
  t := REPLACE(t, E'\u00E2\u0080\u00A6', E'\u2026');  -- … ellipsis
  t := REPLACE(t, E'\u00C2\u00A0', ' ');               -- non-breaking space artifact

  -- ── Phase 2: Fix HTML entities ──────────────────────────────────────
  t := REPLACE(t, '&amp;', '&');
  t := REPLACE(t, '&lt;', '<');
  t := REPLACE(t, '&gt;', '>');
  t := REPLACE(t, '&quot;', '"');
  t := REPLACE(t, '&#39;', '''');
  t := REPLACE(t, '&#x27;', '''');
  t := REPLACE(t, '&nbsp;', ' ');
  t := REPLACE(t, '&#8217;', E'\u2019');  -- '
  t := REPLACE(t, '&#8216;', E'\u2018');  -- '
  t := REPLACE(t, '&#8220;', E'\u201C');  -- "
  t := REPLACE(t, '&#8221;', E'\u201D');  -- "
  t := REPLACE(t, '&#8211;', E'\u2013');  -- –
  t := REPLACE(t, '&#8212;', E'\u2014');  -- —
  t := REPLACE(t, '&#8230;', E'\u2026');  -- …

  -- ── Phase 3: Normalize smart punctuation to ASCII ───────────────────
  -- This ensures consistent display across all platforms/fonts.
  t := REPLACE(t, E'\u2018', '''');   -- ' → '
  t := REPLACE(t, E'\u2019', '''');   -- ' → '
  t := REPLACE(t, E'\u201C', '"');    -- " → "
  t := REPLACE(t, E'\u201D', '"');    -- " → "
  t := REPLACE(t, E'\u2013', '-');    -- – → -
  t := REPLACE(t, E'\u2014', ' - '); -- — → -
  t := REPLACE(t, E'\u2026', '...');  -- … → ...
  t := REPLACE(t, E'\u00A0', ' ');    -- non-breaking space → space

  -- ── Phase 4: Remove zero-width and control characters ──────────────
  t := REPLACE(t, E'\uFEFF', '');   -- BOM
  t := REPLACE(t, E'\u200B', '');   -- zero-width space
  t := REPLACE(t, E'\u200C', '');   -- zero-width non-joiner
  t := REPLACE(t, E'\u200D', '');   -- zero-width joiner
  t := REPLACE(t, E'\u2060', '');   -- word joiner
  t := REPLACE(t, E'\uFFFD', '');   -- replacement character
  -- Strip C0 control chars except tab/newline
  t := REGEXP_REPLACE(t, E'[\\x00-\\x08\\x0B\\x0C\\x0E-\\x1F\\x7F]', '', 'g');

  -- ── Phase 5: Strip stray HTML tags ─────────────────────────────────
  t := REGEXP_REPLACE(t, '<[^>]{1,100}>', '', 'g');

  -- ── Phase 6: Normalize whitespace ──────────────────────────────────
  t := REGEXP_REPLACE(t, '\s+', ' ', 'g');
  t := TRIM(t);

  RETURN t;
END;
$$;

COMMENT ON FUNCTION sanitize_statement_text IS
'IMMUTABLE text sanitizer. Fixes mojibake, HTML entities, smart punctuation, '
'zero-width chars, stray HTML tags, and excessive whitespace. '
'Safe for use in views and indexes. Phase 3 normalizes all smart quotes/dashes '
'to ASCII for consistent cross-platform display.';

-- ════════════════════════════════════════════════════════════════════════
-- 2. QUALITY SCORER
-- ════════════════════════════════════════════════════════════════════════
-- Returns a quality score from 0 (garbage) to 100 (excellent).
-- Deductions for various quality issues. Used by the auto-revoke function
-- and can be called ad-hoc for analysis.

CREATE OR REPLACE FUNCTION statement_quality_score(
  statement_text TEXT,
  context_pre TEXT DEFAULT NULL,
  context_post TEXT DEFAULT NULL
)
RETURNS INTEGER
LANGUAGE plpgsql
IMMUTABLE PARALLEL SAFE
AS $$
DECLARE
  score INTEGER := 100;
  clean TEXT;
  word_count INTEGER;
  alpha_ratio NUMERIC;
  total_len INTEGER;
BEGIN
  IF statement_text IS NULL OR LENGTH(TRIM(statement_text)) = 0 THEN
    RETURN 0;
  END IF;

  clean := sanitize_statement_text(statement_text);
  total_len := LENGTH(clean);
  word_count := ARRAY_LENGTH(STRING_TO_ARRAY(TRIM(clean), ' '), 1);

  -- ── Length checks ──────────────────────────────────────────────────
  -- Too short to be a meaningful quote
  IF total_len < 15 THEN RETURN 0; END IF;
  IF total_len < 30 THEN score := score - 40; END IF;
  IF total_len < 50 THEN score := score - 20; END IF;

  -- Suspiciously long (possible scraping artifact — full article dumped)
  IF total_len > 1800 THEN score := score - 10; END IF;

  -- ── Word count ─────────────────────────────────────────────────────
  IF word_count IS NULL OR word_count < 3 THEN RETURN 5; END IF;
  IF word_count < 5 THEN score := score - 30; END IF;

  -- ── Encoding artifact detection ────────────────────────────────────
  -- Check ORIGINAL text (before sanitization) for mojibake patterns
  IF statement_text ~ E'[\u00C2\u00C3][\u0080-\u00BF]' THEN
    score := score - 30;  -- mojibake detected
  END IF;
  IF statement_text ~ '&(amp|lt|gt|quot|nbsp|#\d{2,5});' THEN
    score := score - 20;  -- unresolved HTML entities
  END IF;
  IF statement_text ~ E'\\uFFFD' THEN
    score := score - 40;  -- replacement characters
  END IF;

  -- ── Boilerplate detection ──────────────────────────────────────────
  -- Common navigation/UI text that sneaks in via scraping
  IF clean ~* '^\s*(read more|click here|subscribe|sign up|share this|follow us|copyright|all rights reserved|terms of (use|service)|privacy policy|cookie|disclaimer)\s*$' THEN
    RETURN 0;
  END IF;
  IF clean ~* '(subscribe to our newsletter|sign up for updates|follow us on|share on twitter|share on facebook|powered by)' THEN
    score := score - 40;
  END IF;
  -- Press release boilerplate
  IF clean ~* '^(for immediate release|media contact|press release|###|about [A-Z])' THEN
    score := score - 30;
  END IF;

  -- ── Content quality ────────────────────────────────────────────────
  -- Ratio of alphabetic characters (low ratio = too many numbers/symbols)
  alpha_ratio := LENGTH(REGEXP_REPLACE(clean, '[^a-zA-Z]', '', 'g'))::NUMERIC / GREATEST(total_len, 1);
  IF alpha_ratio < 0.4 THEN score := score - 30; END IF;  -- mostly numbers/symbols
  IF alpha_ratio < 0.2 THEN RETURN 5; END IF;              -- essentially not text

  -- All caps (shouting or header text)
  IF clean = UPPER(clean) AND total_len > 20 THEN
    score := score - 15;
  END IF;

  -- Contains a URL (likely scraped link text, not a quote)
  IF clean ~ 'https?://' THEN
    score := score - 10;
  END IF;

  -- Looks like a date/byline rather than content
  IF clean ~* '^\s*\w+\s+\d{1,2},?\s+\d{4}\s*$' THEN
    RETURN 5;  -- just a date
  END IF;
  IF clean ~* '^\s*by\s+[A-Z]' AND word_count < 8 THEN
    score := score - 25;  -- byline
  END IF;

  -- ── Truncation detection ───────────────────────────────────────────
  -- Ends mid-sentence (no terminal punctuation and last char isn't quote)
  IF NOT (RIGHT(clean, 1) = ANY(ARRAY['.','!','?','"','''',')'])) AND total_len > 100 THEN
    score := score - 10;
  END IF;

  -- Clamp to 0-100
  RETURN GREATEST(0, LEAST(100, score));
END;
$$;

COMMENT ON FUNCTION statement_quality_score IS
'Returns quality score 0-100 for a statement. Checks: length, encoding '
'artifacts, boilerplate patterns, content ratio, truncation. Used by '
'revoke_low_quality_statements() and available for ad-hoc analysis.';

-- ════════════════════════════════════════════════════════════════════════
-- 3. BATCH AUTO-REVOKE
-- ════════════════════════════════════════════════════════════════════════
-- Revokes all active statements below the quality threshold.
-- Default threshold: 30 (keeps anything scored 30+).
-- Returns count of revoked statements.

CREATE OR REPLACE FUNCTION revoke_low_quality_statements(
  p_threshold INTEGER DEFAULT 30,
  p_dry_run BOOLEAN DEFAULT false
)
RETURNS TABLE(
  revoked_count BIGINT,
  sample_revoked JSONB
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_count BIGINT;
  v_samples JSONB;
BEGIN
  -- Find candidates
  CREATE TEMP TABLE _quality_candidates ON COMMIT DROP AS
  SELECT
    s.statement_id,
    s.figure_id,
    f.name AS figure_name,
    s.text,
    statement_quality_score(s.text, s.context_pre, s.context_post) AS quality_score
  FROM statements s
  JOIN figures f ON f.figure_id = s.figure_id
  WHERE s.is_revoked = false
  AND statement_quality_score(s.text, s.context_pre, s.context_post) < p_threshold;

  SELECT count(*) INTO v_count FROM _quality_candidates;

  -- Sample for review
  SELECT COALESCE(jsonb_agg(row_to_json(sub)::jsonb), '[]'::jsonb)
  INTO v_samples
  FROM (
    SELECT figure_name, quality_score,
           LEFT(text, 100) AS text_preview
    FROM _quality_candidates
    ORDER BY quality_score ASC
    LIMIT 20
  ) sub;

  IF NOT p_dry_run AND v_count > 0 THEN
    UPDATE statements s
    SET is_revoked = true,
        revoked_at = NOW(),
        revocation_reason = 'auto_quality_gate_v1: score=' || qc.quality_score || ' threshold=' || p_threshold
    FROM _quality_candidates qc
    WHERE s.statement_id = qc.statement_id;
  END IF;

  RETURN QUERY SELECT v_count, v_samples;
END;
$$;

COMMENT ON FUNCTION revoke_low_quality_statements IS
'Batch auto-revoke for statements below quality threshold. '
'Use p_dry_run=true to preview without revoking. Returns count + sample.';

-- ════════════════════════════════════════════════════════════════════════
-- 4. QUALITY REPORT VIEW
-- ════════════════════════════════════════════════════════════════════════
-- Shows quality distribution for active statements.

CREATE OR REPLACE VIEW v_statement_quality_report
WITH (security_invoker = false)  -- service_role only
AS
SELECT
  f.name AS figure_name,
  count(*) AS total_statements,
  count(*) FILTER (WHERE statement_quality_score(s.text) >= 70) AS high_quality,
  count(*) FILTER (WHERE statement_quality_score(s.text) BETWEEN 30 AND 69) AS medium_quality,
  count(*) FILTER (WHERE statement_quality_score(s.text) < 30) AS low_quality,
  ROUND(AVG(statement_quality_score(s.text)), 1) AS avg_quality_score
FROM statements s
JOIN figures f ON f.figure_id = s.figure_id
WHERE s.is_revoked = false AND f.is_active = true
GROUP BY f.name
ORDER BY low_quality DESC, avg_quality_score ASC;

COMMENT ON VIEW v_statement_quality_report IS
'Quality distribution per figure. Use to identify figures with data quality issues.';

-- ════════════════════════════════════════════════════════════════════════
-- 5. UPDATE PUBLIC VIEWS WITH SANITIZER
-- ════════════════════════════════════════════════════════════════════════
-- Wraps statement_text, context_before, context_after with sanitizer.
-- This is the final safety net — no matter what's in the DB, the user
-- sees clean text.

CREATE OR REPLACE VIEW v_statements_public
WITH (security_invoker = true)
AS
SELECT
  s.statement_id,
  s.figure_id,
  f.name AS figure_name,
  sanitize_statement_text(s.text) AS statement_text,
  sanitize_statement_text(s.context_pre) AS context_before,
  sanitize_statement_text(s.context_post) AS context_after,
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
'Text sanitized via sanitize_statement_text() for clean user-facing display. '
'security_invoker=true to enforce RLS for anon/auth callers.';

CREATE OR REPLACE VIEW v_feed_ranked
WITH (security_invoker = true)
AS
SELECT
  s.statement_id,
  s.figure_id,
  f.name AS figure_name,
  sanitize_statement_text(s.text) AS statement_text,
  sanitize_statement_text(s.context_pre) AS context_before,
  sanitize_statement_text(s.context_post) AS context_after,
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
'Text sanitized via sanitize_statement_text() for clean user-facing display. '
'Revoked + inactive figures excluded. '
'security_invoker=true to enforce RLS for anon/auth callers.';

-- ── Re-grant permissions ──────────────────────────────────────────────
GRANT SELECT ON v_statements_public TO anon, authenticated;
GRANT SELECT ON v_feed_ranked TO anon, authenticated;
GRANT SELECT ON v_statement_quality_report TO service_role;

-- ════════════════════════════════════════════════════════════════════════
-- END A17 — V1.0.0
-- ════════════════════════════════════════════════════════════════════════
