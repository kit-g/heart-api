CREATE SCHEMA IF NOT EXISTS archive;

COMMENT ON SCHEMA archive IS 'Various archives of data';

DROP TABLE IF EXISTS archive.deleted_workouts;
CREATE TABLE IF NOT EXISTS archive.deleted_workouts
(
    id           UUID PRIMARY KEY,
    user_id      TEXT        NOT NULL,
    name         TEXT,
    started_at   TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    created_at   TIMESTAMPTZ,
    exercises    JSONB,
    deleted_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE archive.deleted_workouts IS 'Archive of workouts that have been deleted';
COMMENT ON COLUMN archive.deleted_workouts.id IS 'Deleted workout UUID (v7), sortable by creation time';
COMMENT ON COLUMN archive.deleted_workouts.user_id IS 'User who performed the workout';
COMMENT ON COLUMN archive.deleted_workouts.name IS 'Workout name or title';
COMMENT ON COLUMN archive.deleted_workouts.started_at IS 'Workout start timestamp';
COMMENT ON COLUMN archive.deleted_workouts.completed_at IS 'Workout completion timestamp';
COMMENT ON COLUMN archive.deleted_workouts.created_at IS 'Workout record creation timestamp';
COMMENT ON COLUMN archive.deleted_workouts.exercises IS 'JSON snapshot of exercises associated with the workout';
COMMENT ON COLUMN archive.deleted_workouts.deleted_at IS 'Timestamp when the workout was deleted';

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
        exercises
    ) VALUES (
        OLD.id,
        OLD.user_id,
        OLD.name,
        OLD.started_at,
        OLD.completed_at,
        OLD.created_at,
        _workout_exercises(OLD.id)
    );
    RETURN OLD;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION _archive_workout() IS 'Trigger function to archive workout data before deletion';

DROP TRIGGER IF EXISTS archive_workout_before_delete ON workouts;
CREATE TRIGGER archive_workout_before_delete
    BEFORE DELETE
    ON workouts
    FOR EACH ROW
EXECUTE FUNCTION _archive_workout();

COMMENT ON TRIGGER archive_workout_before_delete ON workouts IS 'Archives workout data to archive.deleted_workouts before deletion';