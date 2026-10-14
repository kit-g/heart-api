-- When a template joined its program (heart-api#227). A program's position
-- fixes a cycle's sessions by when they joined, so a template filed into a
-- program long after it was made joins the next cycle, not the first one.
-- The database stamps it: a client never says when.
--
-- No DROP before the ADD: the column belongs to rows users wrote.

ALTER TABLE IF EXISTS templates
    ADD COLUMN IF NOT EXISTS joined_program_at TIMESTAMPTZ;

UPDATE templates
SET joined_program_at = created_at
WHERE program_id IS NOT NULL
  AND joined_program_at IS NULL;

CREATE OR REPLACE FUNCTION _stamp_program_join() RETURNS TRIGGER AS
$$
BEGIN
    IF TG_OP = 'INSERT' OR NEW.program_id IS DISTINCT FROM OLD.program_id THEN
        NEW.joined_program_at := CASE WHEN NEW.program_id IS NULL THEN NULL ELSE now() END;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS templates_stamp_program_join ON templates;
CREATE TRIGGER templates_stamp_program_join
    BEFORE INSERT OR UPDATE OF program_id
    ON templates
    FOR EACH ROW
EXECUTE FUNCTION _stamp_program_join();

COMMENT ON COLUMN templates.joined_program_at IS
    'When the template joined its program; NULL outside one. Stamped by the database, never written by a client';
COMMENT ON FUNCTION _stamp_program_join() IS
    'BEFORE INSERT or UPDATE OF program_id on templates: stamps joined_program_at when the program changes, clears it when it leaves';
COMMENT ON TRIGGER templates_stamp_program_join ON templates IS
    'Keeps joined_program_at in step with program_id';
