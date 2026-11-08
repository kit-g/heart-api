-- A custom exercise that came with something a coach sent: its name and
-- instructions are the coach's words, though the row is the student's own.

ALTER TABLE IF EXISTS exercises
    DROP COLUMN IF EXISTS coach_id,
    ADD COLUMN IF NOT EXISTS coach_id TEXT REFERENCES profiles (id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS exercises_coach_idx ON exercises (coach_id) WHERE coach_id IS NOT NULL;

COMMENT ON COLUMN exercises.coach_id IS 'The coach whose exercise this custom was copied from; NULL for the user''s own, or once they are gone';
COMMENT ON INDEX exercises_coach_idx IS 'The SET NULL when a coach''s profile is deleted';
