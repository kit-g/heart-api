-- When a template joined its program (heart-api#227). A program's position
-- fixes a cycle's sessions by when they joined, so a template filed into a
-- program long after it was made joins the next cycle, not the first one.
-- The device says when, so a session filed offline joins when it was filed,
-- not when it synced; the database stamps its own clock only when nobody said.

-- the trigger depends on the column, so it goes first
DROP TRIGGER IF EXISTS templates_stamp_program_join ON templates;

ALTER TABLE IF EXISTS templates
    DROP COLUMN IF EXISTS joined_program_at,
    ADD COLUMN IF NOT EXISTS joined_program_at TIMESTAMPTZ;

UPDATE templates
SET joined_program_at = created_at
WHERE program_id IS NOT NULL
  AND joined_program_at IS NULL;

CREATE OR REPLACE FUNCTION _stamp_program_join() RETURNS TRIGGER AS
$$
BEGIN
    IF NEW.program_id IS NULL THEN
        NEW.joined_program_at := NULL;
    ELSIF TG_OP = 'INSERT' OR NEW.program_id IS DISTINCT FROM OLD.program_id THEN
        -- a time carried over from the previous program says nothing about this one
        IF NEW.joined_program_at IS NULL
            OR (TG_OP = 'UPDATE' AND NEW.joined_program_at IS NOT DISTINCT FROM OLD.joined_program_at)
        THEN
            NEW.joined_program_at := now();
        END IF;
    END IF;
    -- a clock running ahead would keep a session out of the cycle it is in
    IF NEW.joined_program_at > now() THEN
        NEW.joined_program_at := now();
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER templates_stamp_program_join
    BEFORE INSERT OR UPDATE OF program_id, joined_program_at
    ON templates
    FOR EACH ROW
EXECUTE FUNCTION _stamp_program_join();

COMMENT ON COLUMN templates.joined_program_at IS
    'When the template joined its program, as the device saw it; NULL outside one. The database stamps its own clock when a write moves the template into a program without saying when, and never lets it run past now';
COMMENT ON FUNCTION _stamp_program_join() IS
    'BEFORE INSERT or UPDATE OF program_id, joined_program_at on templates: stamps now() when the program changes and no new time was given, clears it when the template leaves, caps it at now()';
COMMENT ON TRIGGER templates_stamp_program_join ON templates IS
    'Keeps joined_program_at in step with program_id';
