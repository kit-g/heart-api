-- A workout a coach logged for a client, in person. It's the client's workout, and
-- this says who entered it.

ALTER TABLE IF EXISTS workouts
    DROP COLUMN IF EXISTS logged_by,
    ADD COLUMN IF NOT EXISTS logged_by TEXT REFERENCES profiles (id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS workouts_logged_by_idx ON workouts (logged_by) WHERE logged_by IS NOT NULL;

COMMENT ON COLUMN workouts.logged_by IS 'The coach who entered it for its owner; NULL for one they logged themselves, or once that coach is gone';
COMMENT ON INDEX workouts_logged_by_idx IS 'The SET NULL when a coach''s profile is deleted';
