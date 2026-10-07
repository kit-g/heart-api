-- A workout's place in the change feed is the transaction that last changed it.
-- A transaction id below the oldest one still running belongs to a finished
-- transaction, so a reader that stops there can't be passed by a change that
-- commits later. updated_at, a start time, can be. updated_at stays, as the time.

ALTER TABLE IF EXISTS workouts
    DROP COLUMN IF EXISTS changed_xid,
    ADD COLUMN IF NOT EXISTS changed_xid XID8 NOT NULL DEFAULT pg_current_xact_id();

COMMENT ON COLUMN workouts.changed_xid IS
    'The transaction that last changed the workout, its exercises, sets or images';

DROP INDEX IF EXISTS workouts_user_updated_idx;
CREATE INDEX IF NOT EXISTS workouts_user_changed_idx ON workouts (user_id, changed_xid, id);

COMMENT ON INDEX workouts_user_changed_idx IS
    'One account''s workouts in the order their changes finished, by transaction';

ALTER TABLE IF EXISTS archive.deleted_workouts
    DROP COLUMN IF EXISTS deleted_xid,
    ADD COLUMN IF NOT EXISTS deleted_xid XID8 NOT NULL DEFAULT pg_current_xact_id();

COMMENT ON COLUMN archive.deleted_workouts.deleted_xid IS
    'The transaction that deleted the workout; a re-delete moves it to the newer one';

CREATE INDEX IF NOT EXISTS deleted_workouts_user_xid_idx ON archive.deleted_workouts (user_id, deleted_xid, id);

COMMENT ON INDEX archive.deleted_workouts_user_xid_idx IS
    'One account''s deletions in the order they finished, by transaction';

-- Both stamps follow the same rule: set unless the update set them itself.
CREATE OR REPLACE FUNCTION _stamp_workout() RETURNS trigger
    LANGUAGE plpgsql
AS
$$
BEGIN
    IF NEW.updated_at IS NOT DISTINCT FROM OLD.updated_at THEN
        NEW.updated_at := now();
    END IF;
    IF NEW.changed_xid IS NOT DISTINCT FROM OLD.changed_xid THEN
        NEW.changed_xid := pg_current_xact_id();
    END IF;
    RETURN NEW;
END
$$;

COMMENT ON FUNCTION _stamp_workout() IS
    'BEFORE UPDATE on workouts: stamps updated_at and changed_xid, unless the update set them';

-- A workout already stamped by this transaction is left alone. Comparing the
-- transaction, not now(), keeps two transactions that started in the same
-- microsecond from each taking the other's stamp for their own.
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
        AND (changed_xid <> pg_current_xact_id() OR updated_at IS DISTINCT FROM now());
    ELSIF TG_OP = 'UPDATE' THEN
        UPDATE workouts
        SET updated_at = now()
        WHERE id IN (
            SELECT workout_id FROM new_rows
            UNION
            SELECT workout_id FROM old_rows
        )
        AND (changed_xid <> pg_current_xact_id() OR updated_at IS DISTINCT FROM now());
    ELSE
        UPDATE workouts
        SET updated_at = now()
        WHERE id IN (
            SELECT workout_id FROM old_rows
        )
        AND (changed_xid <> pg_current_xact_id() OR updated_at IS DISTINCT FROM now());
    END IF;
    RETURN NULL;
END
$$;

COMMENT ON FUNCTION _stamp_workouts_by_workout_id() IS
    'AFTER statement on workout_exercises and workout_images: stamps the workouts whose rows changed';

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
        AND (changed_xid <> pg_current_xact_id() OR updated_at IS DISTINCT FROM now());
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
        AND (changed_xid <> pg_current_xact_id() OR updated_at IS DISTINCT FROM now());
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
        AND (changed_xid <> pg_current_xact_id() OR updated_at IS DISTINCT FROM now());
    END IF;
    RETURN NULL;
END
$$;

COMMENT ON FUNCTION _stamp_workouts_by_set() IS
    'AFTER statement on exercise_sets: stamps the workouts whose sets changed';

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
    AND (changed_xid <> pg_current_xact_id() OR updated_at IS DISTINCT FROM now());
    RETURN NULL;
END
$$;

COMMENT ON FUNCTION _stamp_workouts_by_exercise() IS
    'AFTER statement on exercises: stamps the workouts using a custom exercise whose name, category or target changed';

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
            deleted_at   = now(),
            deleted_xid  = pg_current_xact_id();
    RETURN OLD;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION _archive_workout() IS
    'BEFORE DELETE on workouts: snapshots the workout into archive.deleted_workouts; a re-deleted id replaces its older snapshot';
