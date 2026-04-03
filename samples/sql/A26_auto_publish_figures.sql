-- A26: Auto-publish figures based on statement count threshold
-- Figures with < 30 active statements are hidden from clients.
-- Pipeline continues collecting for them. When they hit 30, they auto-publish.
--
-- is_active  = pipeline control (should we scrape/analyze for this figure?)
-- is_published = client visibility (should users see this figure?)

BEGIN;

-- 1. Add is_published column
ALTER TABLE figures ADD COLUMN IF NOT EXISTS is_published BOOLEAN NOT NULL DEFAULT false;

-- 2. Set initial values based on current active statement counts
UPDATE figures f
SET is_published = true
WHERE is_active = true
  AND (
    SELECT COUNT(*)
    FROM statements s
    WHERE s.figure_id = f.figure_id
      AND s.is_revoked = false
  ) >= 30;

-- 3. Create is_figure_visible() for client-facing RLS
--    Checks both is_active AND is_published.
--    is_figure_active() remains unchanged for pipeline use.
CREATE OR REPLACE FUNCTION is_figure_visible(p_figure_id UUID)
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT EXISTS (
    SELECT 1 FROM figures
    WHERE figure_id = p_figure_id
      AND is_active = true
      AND is_published = true
  );
$$;

-- 4. Update is_statement_visible() to check is_published
CREATE OR REPLACE FUNCTION is_statement_visible(s_id UUID)
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT EXISTS (
    SELECT 1 FROM statements s
    JOIN figures f ON f.figure_id = s.figure_id
    WHERE s.statement_id = s_id
      AND s.is_revoked = false
      AND s.language = 'EN'
      AND f.is_active = true
      AND f.is_published = true
  );
$$;

-- 5. Update figures_public_read RLS policy
DROP POLICY IF EXISTS figures_public_read ON figures;
CREATE POLICY figures_public_read ON figures
  FOR SELECT TO anon, authenticated
  USING (is_active = true AND is_published = true);

-- 6. Update statements_public_read RLS to use is_figure_visible
DROP POLICY IF EXISTS statements_public_read ON statements;
CREATE POLICY statements_public_read ON statements
  FOR SELECT TO anon, authenticated
  USING (
    is_figure_visible(figure_id)
    AND is_revoked = false
    AND language = 'EN'
  );

-- 7. Update votes_public_read RLS to use is_figure_visible
DROP POLICY IF EXISTS votes_public_read ON votes;
CREATE POLICY votes_public_read ON votes
  FOR SELECT TO anon, authenticated
  USING (is_figure_visible(figure_id));

-- 8. Auto-publish trigger: flips is_published when crossing 30 threshold
CREATE OR REPLACE FUNCTION auto_publish_figure()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_figure_id UUID;
  v_count     INT;
  v_current   BOOLEAN;
  v_target    BOOLEAN;
BEGIN
  v_figure_id := COALESCE(NEW.figure_id, OLD.figure_id);

  SELECT COUNT(*) INTO v_count
  FROM statements
  WHERE figure_id = v_figure_id
    AND is_revoked = false;

  v_target := (v_count >= 30);

  SELECT is_published INTO v_current
  FROM figures
  WHERE figure_id = v_figure_id;

  -- Only update if state actually changed
  IF v_current IS DISTINCT FROM v_target THEN
    UPDATE figures
    SET is_published = v_target
    WHERE figure_id = v_figure_id;
  END IF;

  RETURN COALESCE(NEW, OLD);
END;
$$;

-- Fire on insert (new statement) or revocation changes
DROP TRIGGER IF EXISTS trg_auto_publish_figure ON statements;
CREATE TRIGGER trg_auto_publish_figure
  AFTER INSERT OR UPDATE OF is_revoked ON statements
  FOR EACH ROW
  EXECUTE FUNCTION auto_publish_figure();

-- 9. Update the RLS covering index to also benefit from is_published checks
--    (The existing idx_statements_rls_cover still works; figures lookup is the gate)

COMMIT;
