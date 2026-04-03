-- ========================================================================
-- BASELINE V1.4 — ANNOTATIONS SQL EXTENSION
-- A15A — V1.0.1
--
-- FIXES APPLIED (V1.0.0 → V1.0.1 — GPT + Grok audit reconciliation):
-- FIX1: Schema-qualify indexes and trigger target (public.annotations)
-- for consistency with project standards [Grok L1]
-- FIX2: Explicit updated_at = now() in delete_annotation. Trigger handles
-- this too, but explicit is clearer and defense-in-depth. [Grok M1]
--
-- PURPOSE:
-- Extends A1's annotations table with helper RPCs, additional indexes,
-- updated_at trigger, and soft-delete-aware upsert logic for A15B CRUD.
--
-- DEPENDENCIES:
-- - A1 V8.0 deployed (annotations table, RLS policies)
-- - A13A V1.0.2 deployed (user auth)
-- - A13B V1.0.1 deployed (check_feature_access for ENABLE_ANNOTATIONS)
--
-- WHAT THIS DOES NOT DO:
-- - Does not recreate the annotations table (A1 owns it)
-- - Does not modify A1's RLS policies or table grants
-- - Does not create the CRUD endpoint (A15B does that)
-- - Does not enforce rate limits (A17D handles that)
--
-- SOFT-DELETE + UNIQUE CONSTRAINT HANDLING:
-- A1 defines UNIQUE(user_id, statement_id) on annotations. With soft-delete,
-- a user who deletes their annotation cannot create a new one for the same
-- statement because the soft-deleted row still holds the unique slot.
--
-- Solution: The upsert RPC "un-deletes" and updates the existing row if a
-- soft-deleted annotation exists for the same user+statement. This preserves
-- the unique constraint while allowing re-annotation after delete.
--
-- Safety:
-- CREATE OR REPLACE FUNCTION — idempotent
-- CREATE INDEX IF NOT EXISTS — idempotent
-- DROP TRIGGER IF EXISTS — idempotent
-- ========================================================================
-- ========================================================================
-- INDEXES (beyond what A1 defines)
-- ========================================================================
-- V1.0.1 FIX1: Schema-qualified
-- Fast lookup: "my annotations" — filtered to active only
CREATE INDEX IF NOT EXISTS idx_annotations_user_active
ON public.annotations(user_id, created_at DESC)
WHERE is_deleted = false;
-- Fast lookup: "annotations for this statement" — filtered to active only
CREATE INDEX IF NOT EXISTS idx_annotations_statement_active
ON public.annotations(statement_id, created_at DESC)
WHERE is_deleted = false;
-- ========================================================================
-- AUTO-UPDATE updated_at TRIGGER
-- ========================================================================
CREATE OR REPLACE FUNCTION update_annotation_timestamp()
RETURNS TRIGGER AS $$
BEGIN
NEW.updated_at := now();
RETURN NEW;
END;
$$ LANGUAGE plpgsql;
-- V1.0.1 FIX1: Schema-qualified trigger target
DROP TRIGGER IF EXISTS trigger_annotation_timestamp ON public.annotations;
CREATE TRIGGER trigger_annotation_timestamp
BEFORE UPDATE ON public.annotations
FOR EACH ROW
EXECUTE FUNCTION update_annotation_timestamp();
-- ========================================================================
-- RPC: Upsert Annotation (create or un-delete + update)
-- ========================================================================
-- Creates a new annotation or, if a soft-deleted one exists for the same
-- user+statement, un-deletes it and updates the note.
--
-- SECURITY INVOKER: Runs as the calling user. RLS on annotations ensures
-- users can only affect their own rows. auth.uid() used for user_id.
--
-- Returns the annotation_id of the created/updated row.
-- ========================================================================
CREATE OR REPLACE FUNCTION upsert_annotation(
p_statement_id UUID,
p_note TEXT
)
RETURNS UUID
LANGUAGE plpgsql
VOLATILE
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $$
DECLARE
v_user_id UUID;
v_annotation_id UUID;
BEGIN
-- Get current user
v_user_id := auth.uid();
IF v_user_id IS NULL THEN
RAISE EXCEPTION 'Authentication required';
END IF;
-- Validate note
IF p_note IS NULL OR trim(p_note) = '' THEN
RAISE EXCEPTION 'Note cannot be empty';
END IF;
IF char_length(p_note) > 2000 THEN
RAISE EXCEPTION 'Note exceeds 2000 character limit';
END IF;
-- Validate statement exists and is visible
IF NOT EXISTS (
SELECT 1 FROM public.statements s
INNER JOIN public.figures f ON f.figure_id = s.figure_id
WHERE s.statement_id = p_statement_id
AND s.is_revoked = false
AND s.language = 'EN'
AND f.is_active = true
) THEN
RAISE EXCEPTION 'Statement not found or not accessible';
END IF;
-- Upsert: insert or un-delete + update
INSERT INTO public.annotations (user_id, statement_id, note)
VALUES (v_user_id, p_statement_id, trim(p_note))
ON CONFLICT (user_id, statement_id) DO UPDATE
SET note = trim(EXCLUDED.note),
is_deleted = false,
deleted_at = NULL,
updated_at = now()
RETURNING annotation_id INTO v_annotation_id;
RETURN v_annotation_id;
END;
$$;
-- ========================================================================
-- RPC: Update Annotation Note
-- ========================================================================
-- Updates the note text on an existing, non-deleted annotation.
-- Only the owning user can update (enforced by RLS + auth.uid() check).
--
-- Returns true on success.
-- ========================================================================
CREATE OR REPLACE FUNCTION update_annotation(
p_annotation_id UUID,
p_note TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
VOLATILE
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $$
DECLARE
v_user_id UUID;
v_rows INTEGER;
BEGIN
-- Get current user
v_user_id := auth.uid();
IF v_user_id IS NULL THEN
RAISE EXCEPTION 'Authentication required';
END IF;
-- Validate note
IF p_note IS NULL OR trim(p_note) = '' THEN
RAISE EXCEPTION 'Note cannot be empty';
END IF;
IF char_length(p_note) > 2000 THEN
RAISE EXCEPTION 'Note exceeds 2000 character limit';
END IF;
-- Update only if owned by user and not deleted
UPDATE public.annotations
SET note = trim(p_note)
WHERE annotation_id = p_annotation_id
AND user_id = v_user_id
AND is_deleted = false;
GET DIAGNOSTICS v_rows = ROW_COUNT;
IF v_rows = 0 THEN
RAISE EXCEPTION 'Annotation not found or not owned by user';
END IF;
RETURN true;
END;
$$;
-- ========================================================================
-- RPC: Soft-Delete Annotation
-- ========================================================================
-- Marks an annotation as deleted (is_deleted=true, deleted_at=now()).
-- Only the owning user can delete (enforced by RLS + auth.uid() check).
--
-- V1.0.1 FIX2: Explicit updated_at = now() for clarity. The trigger also
-- handles this, but being explicit makes intent clear and provides
-- defense-in-depth if the trigger is ever removed.
--
-- Returns true on success.
-- ========================================================================
CREATE OR REPLACE FUNCTION delete_annotation(
p_annotation_id UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
VOLATILE
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $$
DECLARE
v_user_id UUID;
v_rows INTEGER;
BEGIN
-- Get current user
v_user_id := auth.uid();
IF v_user_id IS NULL THEN
RAISE EXCEPTION 'Authentication required';
END IF;
-- V1.0.1 FIX2: Explicit updated_at alongside deleted_at
UPDATE public.annotations
SET is_deleted = true,
deleted_at = now(),
updated_at = now()
WHERE annotation_id = p_annotation_id
AND user_id = v_user_id
AND is_deleted = false;
GET DIAGNOSTICS v_rows = ROW_COUNT;
IF v_rows = 0 THEN
RAISE EXCEPTION 'Annotation not found or already deleted';
END IF;
RETURN true;
END;
$$;
-- ========================================================================
-- RPC: Get My Annotations (paginated)
-- ========================================================================
-- Returns the current user's non-deleted annotations, optionally filtered
-- by figure_id, with pagination.
--
-- SECURITY INVOKER: RLS ensures only own annotations returned.
--
-- Returns: annotation_id, statement_id, note, created_at, updated_at,
-- plus statement text and figure name for display context.
-- ========================================================================
CREATE OR REPLACE FUNCTION get_my_annotations(
p_figure_id UUID DEFAULT NULL,
p_limit INTEGER DEFAULT 20,
p_offset INTEGER DEFAULT 0
)
RETURNS TABLE (
annotation_id UUID,
statement_id UUID,
note TEXT,
created_at TIMESTAMPTZ,
updated_at TIMESTAMPTZ,
statement_text TEXT,
figure_name TEXT,
figure_id UUID
)
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $$
DECLARE
v_user_id UUID;
BEGIN
-- Get current user
v_user_id := auth.uid();
IF v_user_id IS NULL THEN
RAISE EXCEPTION 'Authentication required';
END IF;
-- Cap limit to prevent abuse
IF p_limit < 1 THEN
p_limit := 1;
ELSIF p_limit > 100 THEN
p_limit := 100;
END IF;
IF p_offset < 0 THEN
p_offset := 0;
END IF;
RETURN QUERY
SELECT
a.annotation_id,
a.statement_id,
a.note,
a.created_at,
a.updated_at,
s.text AS statement_text,
f.name AS figure_name,
f.figure_id
FROM public.annotations a
INNER JOIN public.statements s ON s.statement_id = a.statement_id
INNER JOIN public.figures f ON f.figure_id = s.figure_id
WHERE a.user_id = v_user_id
AND a.is_deleted = false
AND s.is_revoked = false
AND s.language = 'EN'
AND f.is_active = true
AND (p_figure_id IS NULL OR f.figure_id = p_figure_id)
ORDER BY a.created_at DESC
LIMIT p_limit
OFFSET p_offset;
END;
$$;
-- ========================================================================
-- RPC: Get Annotation Count
-- ========================================================================
-- Returns the count of active annotations for the current user.
-- Used by A15B to check against tier quota (max_annotations from A13B config).
-- ========================================================================
CREATE OR REPLACE FUNCTION get_my_annotation_count()
RETURNS INTEGER
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $$
SELECT count(*)::INTEGER
FROM public.annotations
WHERE user_id = auth.uid()
AND is_deleted = false;
$$;
-- ========================================================================
-- GRANTS
-- ========================================================================
-- All RPCs callable by authenticated users (SECURITY INVOKER + RLS).
-- Service_role for admin/support operations.
-- No anon or PUBLIC access.
-- ========================================================================
-- upsert_annotation
REVOKE ALL ON FUNCTION upsert_annotation(UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION upsert_annotation(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION upsert_annotation(UUID, TEXT) TO service_role;
-- update_annotation
REVOKE ALL ON FUNCTION update_annotation(UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION update_annotation(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION update_annotation(UUID, TEXT) TO service_role;
-- delete_annotation
REVOKE ALL ON FUNCTION delete_annotation(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION delete_annotation(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION delete_annotation(UUID) TO service_role;
-- get_my_annotations
REVOKE ALL ON FUNCTION get_my_annotations(UUID, INTEGER, INTEGER) FROM
PUBLIC;
GRANT EXECUTE ON FUNCTION get_my_annotations(UUID, INTEGER, INTEGER) TO
authenticated;
GRANT EXECUTE ON FUNCTION get_my_annotations(UUID, INTEGER, INTEGER) TO
service_role;
-- get_my_annotation_count
REVOKE ALL ON FUNCTION get_my_annotation_count() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION get_my_annotation_count() TO authenticated;
GRANT EXECUTE ON FUNCTION get_my_annotation_count() TO service_role;
-- Trigger function — no public access
REVOKE ALL ON FUNCTION update_annotation_timestamp() FROM PUBLIC;
-- ========================================================================
-- END A15A — V1.0.1
-- ========================================================================
