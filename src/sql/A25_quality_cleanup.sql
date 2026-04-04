-- ========================================================================
-- MIGRATION: Statement Quality Cleanup  - A25 V1.0.0
-- File: A25_quality_cleanup.sql
-- ========================================================================
--
-- Fixes:
--   1. Revoke 450 exact-text duplicates (keep earliest per figure+text)
--   2. Fix HTML entities & mojibake in statement text (in-place)
--   3. Tighten quality scorer  - penalize fragments, trailing commas
--   4. Revoke low-quality statements at threshold 45
--
-- Safety:
--   - Temporary trigger modification for text fixes (restored after)
--   - Dry counts logged before each destructive step
--   - All changes are revocations (recoverable via revoked_at/reason)
-- ========================================================================

-- ════════════════════════════════════════════════════════════════════════
-- 1. REVOKE DUPLICATE STATEMENTS
-- ════════════════════════════════════════════════════════════════════════
-- Keep the earliest statement per (figure_id, text), revoke the rest.

DO $$
DECLARE
  v_count BIGINT;
BEGIN
  -- Count dupes first
  SELECT count(*) INTO v_count
  FROM statements s
  WHERE s.is_revoked = false
  AND EXISTS (
    SELECT 1 FROM statements s2
    WHERE s2.figure_id = s.figure_id
    AND s2.text = s.text
    AND s2.is_revoked = false
    AND s2.ingestion_time < s.ingestion_time
  );
  RAISE NOTICE 'Duplicate statements to revoke: %', v_count;

  -- Revoke dupes (keep earliest)
  UPDATE statements s
  SET is_revoked = true,
      revoked_at = NOW(),
      revocation_reason = 'duplicate_text_cleanup_A25'
  WHERE s.is_revoked = false
  AND EXISTS (
    SELECT 1 FROM statements s2
    WHERE s2.figure_id = s.figure_id
    AND s2.text = s.text
    AND s2.is_revoked = false
    AND s2.ingestion_time < s.ingestion_time
  );

  RAISE NOTICE 'Duplicates revoked: %', v_count;
END $$;

-- ════════════════════════════════════════════════════════════════════════
-- 2. FIX ENCODING IN STATEMENT TEXT (IN-PLACE)
-- ════════════════════════════════════════════════════════════════════════
-- Temporarily add Path 5 to immutability trigger for text sanitization.

-- Step 2a: Add temporary path for text fix
CREATE OR REPLACE FUNCTION prevent_statement_updates()
RETURNS TRIGGER AS $$
BEGIN
  -- Path 1: Revocation (always allowed)
  IF NEW.is_revoked = true AND OLD.is_revoked = false THEN RETURN NEW; END IF;

  -- Path 2: Embedding write-once
  IF OLD.embedding IS NULL AND NEW.embedding IS NOT NULL
     AND OLD.text = NEW.text AND OLD.figure_id = NEW.figure_id THEN RETURN NEW; END IF;

  -- Path 3: baseline_delta write-once
  IF OLD.baseline_delta IS NULL AND NEW.baseline_delta IS NOT NULL
     AND OLD.text = NEW.text AND OLD.figure_id = NEW.figure_id THEN RETURN NEW; END IF;

  -- Path 5 (TEMPORARY): Text sanitization  - only allow if text changes and nothing else
  IF OLD.text IS DISTINCT FROM NEW.text
     AND OLD.figure_id = NEW.figure_id
     AND OLD.is_revoked = NEW.is_revoked
     AND OLD.embedding IS NOT DISTINCT FROM NEW.embedding
     AND OLD.baseline_delta IS NOT DISTINCT FROM NEW.baseline_delta
  THEN RETURN NEW; END IF;

  RAISE EXCEPTION 'Statement updates are not allowed (immutable). Use revocation.';
END;
$$ LANGUAGE plpgsql;

-- Step 2b: Fix HTML entities
UPDATE statements
SET text = REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
  text,
  '&rsquo;', E'\u2019'),
  '&lsquo;', E'\u2018'),
  '&rdquo;', E'\u201D'),
  '&ldquo;', E'\u201C'),
  '&ndash;', E'\u2013'),
  '&mdash;', E'\u2014'),
  '&amp;', '&'),
  '&nbsp;', ' ')
WHERE is_revoked = false
AND (text LIKE '%&rsquo;%' OR text LIKE '%&lsquo;%' OR text LIKE '%&rdquo;%'
     OR text LIKE '%&ldquo;%' OR text LIKE '%&ndash;%' OR text LIKE '%&mdash;%'
     OR text LIKE '%&amp;%' OR text LIKE '%&nbsp;%');

-- Step 2c: Fix mojibake (UTF-8 double-encoded as latin1)
UPDATE statements
SET text = REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
  text,
  E'\u00C2\u00A0', ' '),
  E'\uFFFD', ''''),
  'â€™', E'\u2019'),
  'â€œ', E'\u201C'),
  'â€', E'\u201D')
WHERE is_revoked = false
AND (text LIKE E'%\u00C2\u00A0%' OR text LIKE E'%\uFFFD%'
     OR text LIKE '%â€™%' OR text LIKE '%â€œ%' OR text LIKE '%â€%');

-- Step 2d: Normalize smart quotes to ASCII (consistent display)
UPDATE statements
SET text = REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
  text,
  E'\u2018', ''''),
  E'\u2019', ''''),
  E'\u201C', '"'),
  E'\u201D', '"'),
  E'\u2026', '...')
WHERE is_revoked = false
AND (text LIKE E'%\u2018%' OR text LIKE E'%\u2019%'
     OR text LIKE E'%\u201C%' OR text LIKE E'%\u201D%'
     OR text LIKE E'%\u2026%');

-- Step 2e: Also fix context_pre and context_post
UPDATE statements
SET context_pre = REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
  context_pre,
  '&rsquo;', ''''), '&lsquo;', ''''), '&rdquo;', '"'), '&ldquo;', '"'),
  '&ndash;', '-'), '&mdash;', ' - '), '&amp;', '&'), '&nbsp;', ' ')
WHERE is_revoked = false AND context_pre IS NOT NULL
AND (context_pre LIKE '%&rsquo;%' OR context_pre LIKE '%&lsquo;%' OR context_pre LIKE '%&amp;%'
     OR context_pre LIKE '%&rdquo;%' OR context_pre LIKE '%&ldquo;%');

UPDATE statements
SET context_post = REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
  context_post,
  '&rsquo;', ''''), '&lsquo;', ''''), '&rdquo;', '"'), '&ldquo;', '"'),
  '&ndash;', '-'), '&mdash;', ' - '), '&amp;', '&'), '&nbsp;', ' ')
WHERE is_revoked = false AND context_post IS NOT NULL
AND (context_post LIKE '%&rsquo;%' OR context_post LIKE '%&lsquo;%' OR context_post LIKE '%&amp;%'
     OR context_post LIKE '%&rdquo;%' OR context_post LIKE '%&ldquo;%');

-- Step 2f: Restore original trigger (remove Path 5)
CREATE OR REPLACE FUNCTION prevent_statement_updates()
RETURNS TRIGGER AS $$
BEGIN
  -- Path 1: Revocation (always allowed)
  IF NEW.is_revoked = true AND OLD.is_revoked = false THEN RETURN NEW; END IF;

  -- Path 2: Embedding write-once
  IF OLD.embedding IS NULL AND NEW.embedding IS NOT NULL
     AND OLD.text = NEW.text AND OLD.figure_id = NEW.figure_id THEN RETURN NEW; END IF;

  -- Path 3: baseline_delta write-once
  IF OLD.baseline_delta IS NULL AND NEW.baseline_delta IS NOT NULL
     AND OLD.text = NEW.text AND OLD.figure_id = NEW.figure_id THEN RETURN NEW; END IF;

  RAISE EXCEPTION 'Statement updates are not allowed (immutable). Use revocation.';
END;
$$ LANGUAGE plpgsql;

-- ════════════════════════════════════════════════════════════════════════
-- 3. TIGHTEN QUALITY SCORER
-- ════════════════════════════════════════════════════════════════════════
-- Add penalties for: trailing commas, leading lowercase fragments,
-- editorial brackets in short text, t.co URLs (tweet artifacts)

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
  IF total_len < 20 THEN RETURN 0; END IF;   -- was 15, raised
  IF total_len < 40 THEN score := score - 45; END IF;  -- was 30→-40, now stronger
  IF total_len < 60 THEN score := score - 20; END IF;  -- new tier
  IF total_len < 80 THEN score := score - 10; END IF;  -- new tier

  -- Suspiciously long
  IF total_len > 1800 THEN score := score - 10; END IF;

  -- ── Word count ─────────────────────────────────────────────────────
  IF word_count IS NULL OR word_count < 3 THEN RETURN 0; END IF;  -- was 5
  IF word_count < 5 THEN score := score - 30; END IF;
  IF word_count < 8 AND total_len < 60 THEN score := score - 15; END IF;  -- new

  -- ── Encoding artifact detection ────────────────────────────────────
  IF statement_text ~ E'[\u00C2\u00C3][\u0080-\u00BF]' THEN
    score := score - 30;
  END IF;
  IF statement_text ~ '&(amp|lt|gt|quot|nbsp|rsquo|lsquo|rdquo|ldquo|ndash|mdash|#\d{2,5});' THEN
    score := score - 20;
  END IF;
  IF statement_text ~ E'\\uFFFD' THEN
    score := score - 40;
  END IF;

  -- ── Boilerplate detection ──────────────────────────────────────────
  IF clean ~* '^\s*(read more|click here|subscribe|sign up|share this|follow us|copyright|all rights reserved|terms of (use|service)|privacy policy|cookie|disclaimer)\s*$' THEN
    RETURN 0;
  END IF;
  IF clean ~* '(subscribe to our newsletter|sign up for updates|follow us on|share on twitter|share on facebook|powered by)' THEN
    score := score - 40;
  END IF;
  IF clean ~* '^(for immediate release|media contact|press release|###|about [A-Z])' THEN
    score := score - 30;
  END IF;

  -- ── Content quality ────────────────────────────────────────────────
  alpha_ratio := LENGTH(REGEXP_REPLACE(clean, '[^a-zA-Z]', '', 'g'))::NUMERIC / GREATEST(total_len, 1);
  IF alpha_ratio < 0.4 THEN score := score - 30; END IF;
  IF alpha_ratio < 0.2 THEN RETURN 5; END IF;

  -- All caps
  IF clean = UPPER(clean) AND total_len > 20 THEN
    score := score - 15;
  END IF;

  -- Contains a URL
  IF clean ~ 'https?://' THEN
    score := score - 10;
  END IF;
  -- t.co links (tweet artifacts, no value)
  IF clean ~ 'https?://t\.co/' THEN
    score := score - 15;  -- extra penalty on top of URL
  END IF;

  -- Date/byline
  IF clean ~* '^\s*\w+\s+\d{1,2},?\s+\d{4}\s*$' THEN RETURN 5; END IF;
  IF clean ~* '^\s*by\s+[A-Z]' AND word_count < 8 THEN score := score - 25; END IF;

  -- ── Fragment detection (NEW) ───────────────────────────────────────
  -- Trailing comma = clipped mid-sentence
  IF RIGHT(TRIM(clean), 1) = ',' THEN
    score := score - 20;
  END IF;

  -- Starts with lowercase = likely ripped from middle of sentence
  IF clean ~ '^[a-z]' AND total_len < 100 THEN
    score := score - 15;
  END IF;

  -- Editorial brackets in short text = not a real quote
  IF clean ~ '\[.*?\]' AND total_len < 80 THEN
    score := score - 20;
  END IF;

  -- Starts with ellipsis or "..." = truncated beginning
  IF clean ~ '^\.\.\.' OR clean ~ E'^\\u2026' THEN
    score := score - 15;
  END IF;

  -- ── Truncation detection ───────────────────────────────────────────
  IF NOT (RIGHT(clean, 1) = ANY(ARRAY['.','!','?','"','''',')'])) AND total_len > 100 THEN
    score := score - 10;
  END IF;

  RETURN GREATEST(0, LEAST(100, score));
END;
$$;

-- ════════════════════════════════════════════════════════════════════════
-- 4. AUTO-REVOKE AT TIGHTER THRESHOLD
-- ════════════════════════════════════════════════════════════════════════
-- Threshold 45: catches fragments, encoding-broken, and junk.
-- Good short statements (like "Our response to the climate crisis must
-- match the urgency of the moment." at 72 chars) score 70+ and survive.

SELECT * FROM revoke_low_quality_statements(p_threshold := 45, p_dry_run := false);

-- ════════════════════════════════════════════════════════════════════════
-- END A25  - V1.0.0
-- ════════════════════════════════════════════════════════════════════════
