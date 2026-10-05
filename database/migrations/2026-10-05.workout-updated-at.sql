-- When a workout last changed, as a whole: its own row, or any of its
-- exercises, sets or images (heart-api#114). Ordered with the deletion
-- archive, it is what an incremental feed reads from.
--
-- Child changes reach the workout through statement-level triggers with
-- transition tables, so a bulk import that writes thousands of sets touches
-- each of its workouts once, not once per set. Transition tables allow a
-- single event per trigger, hence three triggers per table sharing one
-- function.

ALTER TABLE IF EXISTS workouts
    DROP COLUMN IF EXISTS updated_at,
    ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT now();

-- Rows that predate the column changed last when they were created, as far
-- as anything can tell.
UPDATE workouts
SET updated_at = created_at;

COMMENT ON COLUMN workouts.updated_at IS
    'When the workout or anything in it (exercises, sets, images) last changed; created_at for rows that predate the column';

CREATE INDEX IF NOT EXISTS workouts_user_updated_idx ON workouts (user_id, updated_at, id);

COMMENT ON INDEX workouts_user_updated_idx IS
    'One account''s workouts in the order they last changed, ties broken by id';

CREATE OR REPLACE FUNCTION _stamp_workout() RETURNS trigger
    LANGUAGE plpgsql
AS
$$
BEGIN
    IF NEW.updated_at IS NOT DISTINCT FROM OLD.updated_at THEN
        NEW.updated_at := now();
    END IF;
    RETURN NEW;
END
$$;

COMMENT ON FUNCTION _stamp_workout() IS
    'BEFORE UPDATE on workouts: any change to the row is a change to the workout, unless the statement sets updated_at itself (the child triggers, a backfill)';

DROP TRIGGER IF EXISTS workouts_stamp ON workouts;
CREATE TRIGGER workouts_stamp
    BEFORE UPDATE
    ON workouts
    FOR EACH ROW
EXECUTE FUNCTION _stamp_workout();

COMMENT ON TRIGGER workouts_stamp ON workouts IS
    'Any edit to a workout row stamps its updated_at';

-- workout_exercises and workout_images carry workout_id directly.
CREATE OR REPLACE FUNCTION _stamp_workouts_by_workout_id() RETURNS trigger
    LANGUAGE plpgsql
AS
$$
BEGIN
    IF TG_OP IN ('INSERT', 'UPDATE') THEN
        UPDATE workouts SET updated_at = now() WHERE id IN (SELECT workout_id FROM new_rows);
    END IF;
    IF TG_OP IN ('UPDATE', 'DELETE') THEN
        UPDATE workouts SET updated_at = now() WHERE id IN (SELECT workout_id FROM old_rows);
    END IF;
    RETURN NULL;
END
$$;

COMMENT ON FUNCTION _stamp_workouts_by_workout_id() IS
    'Statement-level AFTER trigger on tables with a workout_id: bumps workouts.updated_at of every workout the statement touched';

-- exercise_sets reach their workout through workout_exercises.
CREATE OR REPLACE FUNCTION _stamp_workouts_by_set() RETURNS trigger
    LANGUAGE plpgsql
AS
$$
BEGIN
    IF TG_OP IN ('INSERT', 'UPDATE') THEN
        UPDATE workouts
        SET updated_at = now()
        WHERE id IN (SELECT we.workout_id
                     FROM workout_exercises we
                     WHERE we.id IN (SELECT workout_exercise_id FROM new_rows));
    END IF;
    IF TG_OP IN ('UPDATE', 'DELETE') THEN
        UPDATE workouts
        SET updated_at = now()
        WHERE id IN (SELECT we.workout_id
                     FROM workout_exercises we
                     WHERE we.id IN (SELECT workout_exercise_id FROM old_rows));
    END IF;
    RETURN NULL;
END
$$;

COMMENT ON FUNCTION _stamp_workouts_by_set() IS
    'Statement-level AFTER trigger on exercise_sets: bumps workouts.updated_at of every workout whose sets the statement touched';

DROP TRIGGER IF EXISTS workout_exercises_stamp_insert ON workout_exercises;
CREATE TRIGGER workout_exercises_stamp_insert
    AFTER INSERT
    ON workout_exercises
    REFERENCING NEW TABLE AS new_rows
    FOR EACH STATEMENT
EXECUTE FUNCTION _stamp_workouts_by_workout_id();

COMMENT ON TRIGGER workout_exercises_stamp_insert ON workout_exercises IS
    'Stamps updated_at on the workouts whose exercises a statement added';

DROP TRIGGER IF EXISTS workout_exercises_stamp_update ON workout_exercises;
CREATE TRIGGER workout_exercises_stamp_update
    AFTER UPDATE
    ON workout_exercises
    REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows
    FOR EACH STATEMENT
EXECUTE FUNCTION _stamp_workouts_by_workout_id();

COMMENT ON TRIGGER workout_exercises_stamp_update ON workout_exercises IS
    'Stamps updated_at on the workouts whose exercises a statement edited';

DROP TRIGGER IF EXISTS workout_exercises_stamp_delete ON workout_exercises;
CREATE TRIGGER workout_exercises_stamp_delete
    AFTER DELETE
    ON workout_exercises
    REFERENCING OLD TABLE AS old_rows
    FOR EACH STATEMENT
EXECUTE FUNCTION _stamp_workouts_by_workout_id();

COMMENT ON TRIGGER workout_exercises_stamp_delete ON workout_exercises IS
    'Stamps updated_at on the workouts whose exercises a statement removed';

DROP TRIGGER IF EXISTS workout_images_stamp_insert ON workout_images;
CREATE TRIGGER workout_images_stamp_insert
    AFTER INSERT
    ON workout_images
    REFERENCING NEW TABLE AS new_rows
    FOR EACH STATEMENT
EXECUTE FUNCTION _stamp_workouts_by_workout_id();

COMMENT ON TRIGGER workout_images_stamp_insert ON workout_images IS
    'Stamps updated_at on the workouts whose images a statement added';

DROP TRIGGER IF EXISTS workout_images_stamp_update ON workout_images;
CREATE TRIGGER workout_images_stamp_update
    AFTER UPDATE
    ON workout_images
    REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows
    FOR EACH STATEMENT
EXECUTE FUNCTION _stamp_workouts_by_workout_id();

COMMENT ON TRIGGER workout_images_stamp_update ON workout_images IS
    'Stamps updated_at on the workouts whose images a statement edited';

DROP TRIGGER IF EXISTS workout_images_stamp_delete ON workout_images;
CREATE TRIGGER workout_images_stamp_delete
    AFTER DELETE
    ON workout_images
    REFERENCING OLD TABLE AS old_rows
    FOR EACH STATEMENT
EXECUTE FUNCTION _stamp_workouts_by_workout_id();

COMMENT ON TRIGGER workout_images_stamp_delete ON workout_images IS
    'Stamps updated_at on the workouts whose images a statement removed';

DROP TRIGGER IF EXISTS exercise_sets_stamp_insert ON exercise_sets;
CREATE TRIGGER exercise_sets_stamp_insert
    AFTER INSERT
    ON exercise_sets
    REFERENCING NEW TABLE AS new_rows
    FOR EACH STATEMENT
EXECUTE FUNCTION _stamp_workouts_by_set();

COMMENT ON TRIGGER exercise_sets_stamp_insert ON exercise_sets IS
    'Stamps updated_at on the workouts whose sets a statement added';

DROP TRIGGER IF EXISTS exercise_sets_stamp_update ON exercise_sets;
CREATE TRIGGER exercise_sets_stamp_update
    AFTER UPDATE
    ON exercise_sets
    REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows
    FOR EACH STATEMENT
EXECUTE FUNCTION _stamp_workouts_by_set();

COMMENT ON TRIGGER exercise_sets_stamp_update ON exercise_sets IS
    'Stamps updated_at on the workouts whose sets a statement edited';

DROP TRIGGER IF EXISTS exercise_sets_stamp_delete ON exercise_sets;
CREATE TRIGGER exercise_sets_stamp_delete
    AFTER DELETE
    ON exercise_sets
    REFERENCING OLD TABLE AS old_rows
    FOR EACH STATEMENT
EXECUTE FUNCTION _stamp_workouts_by_set();

COMMENT ON TRIGGER exercise_sets_stamp_delete ON exercise_sets IS
    'Stamps updated_at on the workouts whose sets a statement removed';

-- The deletion half of the feed reads the archive by user, in order.
CREATE INDEX IF NOT EXISTS deleted_workouts_user_deleted_id_idx
    ON archive.deleted_workouts (user_id, deleted_at, id);

COMMENT ON INDEX archive.deleted_workouts_user_deleted_id_idx IS
    'One account''s deletions in the order they happened, ties broken by id';
