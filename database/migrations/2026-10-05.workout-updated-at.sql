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

-- The child stamps skip workouts already stamped by this transaction: an
-- import writes a workout, then its exercises, then its sets, and without the
-- guard each step would rewrite every workout row again.
--
-- A transition table can only be read in the event that defines it, hence
-- one branch per event.

-- workout_exercises and workout_images carry workout_id directly.
CREATE OR REPLACE FUNCTION _stamp_workouts_by_workout_id() RETURNS trigger
    LANGUAGE plpgsql
AS
$$
BEGIN
    IF TG_OP = 'INSERT' THEN
        UPDATE workouts
        SET updated_at = now()
        WHERE id IN (
            SELECT workout_id FROM new_rows
        )
        AND updated_at IS DISTINCT FROM now();
    ELSIF TG_OP = 'UPDATE' THEN
        UPDATE workouts
        SET updated_at = now()
        WHERE id IN (
            SELECT workout_id FROM new_rows
            UNION
            SELECT workout_id FROM old_rows
        )
        AND updated_at IS DISTINCT FROM now();
    ELSE
        UPDATE workouts
        SET updated_at = now()
        WHERE id IN (
            SELECT workout_id FROM old_rows
        )
        AND updated_at IS DISTINCT FROM now();
    END IF;
    RETURN NULL;
END
$$;

COMMENT ON FUNCTION _stamp_workouts_by_workout_id() IS
    'Statement-level AFTER trigger on tables with a workout_id: stamps updated_at on every workout the statement touched, once per transaction';

-- exercise_sets reach their workout through workout_exercises.
CREATE OR REPLACE FUNCTION _stamp_workouts_by_set() RETURNS trigger
    LANGUAGE plpgsql
AS
$$
BEGIN
    IF TG_OP = 'INSERT' THEN
        UPDATE workouts
        SET updated_at = now()
        WHERE id IN (
            SELECT we.workout_id
            FROM workout_exercises we
            WHERE we.id IN (
                SELECT workout_exercise_id FROM new_rows
            )
        )
        AND updated_at IS DISTINCT FROM now();
    ELSIF TG_OP = 'UPDATE' THEN
        UPDATE workouts
        SET updated_at = now()
        WHERE id IN (
            SELECT we.workout_id
            FROM workout_exercises we
            WHERE we.id IN (
                SELECT workout_exercise_id FROM new_rows
                UNION
                SELECT workout_exercise_id FROM old_rows
            )
        )
        AND updated_at IS DISTINCT FROM now();
    ELSE
        UPDATE workouts
        SET updated_at = now()
        WHERE id IN (
            SELECT we.workout_id
            FROM workout_exercises we
            WHERE we.id IN (
                SELECT workout_exercise_id FROM old_rows
            )
        )
        AND updated_at IS DISTINCT FROM now();
    END IF;
    RETURN NULL;
END
$$;

COMMENT ON FUNCTION _stamp_workouts_by_set() IS
    'Statement-level AFTER trigger on exercise_sets: stamps updated_at on every workout whose sets the statement touched, once per transaction';

-- A workout embeds its exercises' name, category and target, so editing one
-- changes every workout that uses it. Only the user's own exercises: a
-- catalog edit would rewrite every account's history at once, and catalog
-- content reaches clients through the library, not through workouts.
CREATE OR REPLACE FUNCTION _stamp_workouts_by_exercise() RETURNS trigger
    LANGUAGE plpgsql
AS
$$
BEGIN
    UPDATE workouts
    SET updated_at = now()
    WHERE id IN (
        SELECT we.workout_id
        FROM workout_exercises we
        JOIN new_rows n ON n.id = we.exercise_id
        JOIN old_rows o ON o.id = n.id
        WHERE n.user_id IS NOT NULL
        AND (n.name, n.category, n.target) IS DISTINCT FROM (o.name, o.category, o.target)
    )
    AND updated_at IS DISTINCT FROM now();
    RETURN NULL;
END
$$;

COMMENT ON FUNCTION _stamp_workouts_by_exercise() IS
    'Statement-level AFTER UPDATE on exercises: stamps updated_at on the workouts using a user''s own exercise whose name, category or target changed';

DROP TRIGGER IF EXISTS exercises_stamp_update ON exercises;
CREATE TRIGGER exercises_stamp_update
    AFTER UPDATE
    ON exercises
    REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows
    FOR EACH STATEMENT
EXECUTE FUNCTION _stamp_workouts_by_exercise();

COMMENT ON TRIGGER exercises_stamp_update ON exercises IS
    'Stamps updated_at on the workouts whose embedded copy of a user''s own exercise a statement changed';

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

-- A workout deleted, created again under the same id (a replayed create),
-- then deleted again must archive again instead of failing on the archive's
-- key: the newer snapshot replaces the older one.
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
            exercises    = excluded.exercises,
            deleted_at   = now();
    RETURN OLD;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION _archive_workout() IS
    'BEFORE DELETE on workouts: snapshots the workout into archive.deleted_workouts; a re-deleted id replaces its older snapshot';
