-- What another app's history says about a set and a session beyond its numbers:
--
--   exercise_sets.set_type  warm-up / drop / failure as one letter (w / d / f,
--                           Strong's own); NULL is an ordinary working set, so
--                           the common case costs nothing.
--   exercise_sets.rpe       rate of perceived exertion, the lifter's own rating;
--                           REAL, since half steps are exact in binary.
--   workouts.note           a free-text note on the whole session.
--
-- A NULL set type is a normal set: every row older than this migration, every
-- writer that doesn't know the field, and every set nobody marked. RPE and the
-- note are NULL when there is none.
--
-- RPE is self-reported effort, not a body reading, so the device-only health
-- rule does not touch it. The columns validate, never restrict: any set of any
-- category may carry either field.
--
-- Dropped and rebuilt on a re-run while unshipped; once deployed they hold
-- user data, and changing them is a new migration.

ALTER TABLE exercise_sets
    DROP COLUMN IF EXISTS set_type,
    ADD COLUMN IF NOT EXISTS set_type CHAR(1),
    DROP COLUMN IF EXISTS rpe,
    ADD COLUMN IF NOT EXISTS rpe      REAL;

ALTER TABLE exercise_sets
    DROP CONSTRAINT IF EXISTS exercise_sets_set_type_check,
    DROP CONSTRAINT IF EXISTS exercise_sets_rpe_check,
    ADD CONSTRAINT exercise_sets_set_type_check
        CHECK (set_type IS NULL OR set_type IN ('w', 'd', 'f')),
    ADD CONSTRAINT exercise_sets_rpe_check
        CHECK (rpe IS NULL OR (rpe BETWEEN 1 AND 10 AND rpe * 2 = trunc(rpe * 2)));

COMMENT ON COLUMN exercise_sets.set_type IS
    'w(armup), d(rop) or f(ailure) — _set_type_name spells it out; NULL is an ordinary working set';
COMMENT ON COLUMN exercise_sets.rpe IS
    'Rate of perceived exertion as the lifter rated it, 1-10 in half steps; NULL when not rated';
COMMENT ON CONSTRAINT exercise_sets_set_type_check ON exercise_sets IS
    'The set types lifting apps share besides an ordinary working set, which is NULL.';
COMMENT ON CONSTRAINT exercise_sets_rpe_check ON exercise_sets IS
    'The RPE scale is 1-10 and is rated in whole or half points; anything finer is noise.';

ALTER TABLE workouts
    ADD COLUMN IF NOT EXISTS note TEXT;

ALTER TABLE workouts
    DROP CONSTRAINT IF EXISTS workouts_note_length_check;
ALTER TABLE workouts
    ADD CONSTRAINT workouts_note_length_check
        CHECK (note IS NULL OR char_length(note) BETWEEN 1 AND 1000);

COMMENT ON COLUMN workouts.note IS
    'Free-text note on the whole session (max 1000 chars); NULL when there is none. Per-exercise notes are workout_exercises.note.';
COMMENT ON CONSTRAINT workouts_note_length_check ON workouts IS
    'A note, not a journal: 1-1000 chars, or NULL for none.';

-- The one place a stored letter becomes the word the read shape carries.
CREATE OR REPLACE FUNCTION _set_type_name(_code CHAR) RETURNS TEXT
LANGUAGE SQL IMMUTABLE AS
$$
SELECT CASE _code
    WHEN 'w' THEN 'warmup'
    WHEN 'd' THEN 'drop'
    WHEN 'f' THEN 'failure'
    ELSE 'normal'
    END
$$;

COMMENT ON FUNCTION _set_type_name(CHAR) IS
    'exercise_sets.set_type''s letter as its word (normal, warmup, drop, failure); NULL is normal';

-- The set snapshot carries the new fields, so the archive of a deleted workout
-- keeps them through the same function.
DROP FUNCTION IF EXISTS _exercise_sets(_workout_exercise_id UUID);
CREATE OR REPLACE FUNCTION _exercise_sets(_workout_exercise_id UUID)
RETURNS JSONB
LANGUAGE SQL AS
$$
SELECT coalesce(
  jsonb_agg(
    jsonb_build_object(
      'id',           es.id,
      'weight',       es.weight,
      'reps',         es.reps,
      'duration',     es.duration,
      'distance',     es.distance,
      'completed',    es.completed,
      'started_at',   es.started_at,
      'completed_at', es.completed_at,
      'set_order',    es.set_order,
      'set_type',     _set_type_name(es.set_type),
      'rpe',          es.rpe
    ) ORDER BY es.set_order
  ) FILTER (WHERE es.id IS NOT NULL),
  '[]'::jsonb
)
FROM exercise_sets es
WHERE es.workout_exercise_id = _workout_exercise_id
$$;

-- The workout-level note is a scalar column, so the archive carries it
-- explicitly, as it does calories.
ALTER TABLE archive.deleted_workouts
    ADD COLUMN IF NOT EXISTS note TEXT;

COMMENT ON COLUMN archive.deleted_workouts.note IS
    'Free-text note on the whole session, as recorded at deletion time';

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
        _workout_exercises(OLD.id)
    );
    RETURN OLD;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION _archive_workout() IS 'Trigger function to archive workout data before deletion';
