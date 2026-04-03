-- A24: Fix HTML entities in statement text
-- ──────────────────────────────────────────
-- Fixes 266 rows containing HTML entities like &#8217; &#8220; etc.
-- The immutability trigger blocks text UPDATEs, so we must:
--   1. Disable the trigger
--   2. Run the UPDATE
--   3. Re-enable the trigger
--
-- RUN WITH CARE — this is a one-time data fix.
-- ──────────────────────────────────────────

BEGIN;

-- Step 1: Temporarily disable the immutability trigger
ALTER TABLE statements DISABLE TRIGGER trg_statements_immutable;

-- Step 2: Fix numeric HTML entities (&#8217; → ', &#8220; → ", etc.)
UPDATE statements
SET text = regexp_replace(
  regexp_replace(
    regexp_replace(
      regexp_replace(
        regexp_replace(
          regexp_replace(
            regexp_replace(
              regexp_replace(text,
                '&#8217;', E'\u2019', 'g'),  -- right single quote
              '&#8216;', E'\u2018', 'g'),    -- left single quote
            '&#8220;', E'\u201C', 'g'),      -- left double quote
          '&#8221;', E'\u201D', 'g'),        -- right double quote
        '&#8212;', E'\u2014', 'g'),          -- em dash
      '&#8211;', E'\u2013', 'g'),            -- en dash
    '&#8230;', E'\u2026', 'g'),              -- ellipsis
  '&#160;', ' ', 'g')                        -- non-breaking space
WHERE text ~ '&#\d+;';

-- Step 3: Re-enable the immutability trigger
ALTER TABLE statements ENABLE TRIGGER trg_statements_immutable;

COMMIT;
