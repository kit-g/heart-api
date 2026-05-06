CREATE SCHEMA IF NOT EXISTS archive;

COMMENT ON SCHEMA archive IS 'Various archives of data';

DROP TABLE IF EXISTS archive.deleted_workouts;
CREATE TABLE IF NOT EXISTS archive.deleted_workouts
(
    id           UUID PRIMARY KEY, -- the deleted workout id, it's UUID v7, so it's sortable and no index needed
    user_id      TEXT        NOT NULL,
    name         TEXT,
    started_at   TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    created_at   TIMESTAMPTZ,
    exercises    JSONB,
    deleted_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE archive.deleted_workouts IS 'Archive of workouts that have been deleted';

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

DROP TRIGGER IF EXISTS archive_workout_before_delete ON workouts;
CREATE TRIGGER archive_workout_before_delete
    BEFORE DELETE
    ON workouts
    FOR EACH ROW
EXECUTE FUNCTION _archive_workout();
