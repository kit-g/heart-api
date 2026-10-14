-- A workout names the template it was started from and the program it counts
-- toward (docs/2026-10-13.programs.md). Both are optional and go null when what
-- they name is deleted. The program is kept apart from the template so a
-- workout still counts toward its program after its session is gone.
--
-- No DROP before the ADD: the columns hold what users wrote.

ALTER TABLE IF EXISTS workouts
    ADD COLUMN IF NOT EXISTS template_id UUID,
    ADD COLUMN IF NOT EXISTS program_id UUID;

ALTER TABLE IF EXISTS workouts
    DROP CONSTRAINT IF EXISTS workouts_template_id_fkey,
    ADD CONSTRAINT workouts_template_id_fkey
        FOREIGN KEY (template_id) REFERENCES templates (id) ON DELETE SET NULL,
    DROP CONSTRAINT IF EXISTS workouts_program_id_fkey,
    ADD CONSTRAINT workouts_program_id_fkey
        FOREIGN KEY (program_id) REFERENCES programs (id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS workouts_template_id_idx ON workouts (template_id) WHERE template_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS workouts_program_id_idx ON workouts (program_id) WHERE program_id IS NOT NULL;

COMMENT ON COLUMN workouts.template_id IS
    'The template the workout was started from, if any; NULL once that template is deleted';
COMMENT ON COLUMN workouts.program_id IS
    'The program the workout counts toward, if any; outlives the session template, NULL once the program is deleted';
COMMENT ON INDEX workouts_template_id_idx IS 'A template''s workouts, and the SET NULL when it is deleted';
COMMENT ON INDEX workouts_program_id_idx IS 'A program''s workouts, which its position is computed from';

-- The archive carries both, as it does the note and the pauses.
ALTER TABLE IF EXISTS archive.deleted_workouts
    ADD COLUMN IF NOT EXISTS template_id UUID,
    ADD COLUMN IF NOT EXISTS program_id UUID;

COMMENT ON COLUMN archive.deleted_workouts.template_id IS
    'The template the session was started from, as recorded at deletion time; not a reference';
COMMENT ON COLUMN archive.deleted_workouts.program_id IS
    'The program the session counted toward, as recorded at deletion time; not a reference';

CREATE OR REPLACE FUNCTION _archive_workout() RETURNS TRIGGER AS
$$
BEGIN
    INSERT INTO archive.deleted_workouts (
        id,
        user_id,
        name,
        started_at,
        completed_at,
        created_at,
        calories,
        note,
        pauses,
        template_id,
        program_id,
        exercises
    ) VALUES (
        OLD.id,
        OLD.user_id,
        OLD.name,
        OLD.started_at,
        OLD.completed_at,
        OLD.created_at,
        OLD.calories,
        OLD.note,
        OLD.pauses,
        OLD.template_id,
        OLD.program_id,
        _workout_exercises(OLD.id)
    )
    ON CONFLICT (id) DO UPDATE
        SET user_id      = excluded.user_id,
            name         = excluded.name,
            started_at   = excluded.started_at,
            completed_at = excluded.completed_at,
            created_at   = excluded.created_at,
            calories     = excluded.calories,
            note         = excluded.note,
            pauses       = excluded.pauses,
            template_id  = excluded.template_id,
            program_id   = excluded.program_id,
            exercises    = excluded.exercises,
            deleted_at   = now(),
            deleted_xid  = pg_current_xact_id();
    RETURN OLD;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION _archive_workout() IS
    'BEFORE DELETE on workouts: snapshots the workout into archive.deleted_workouts; a re-deleted id replaces its older snapshot';
