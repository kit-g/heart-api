-- Client-computed energy expenditure from the wearable integration.
--
-- The device buckets HealthKit active-energy samples into time windows and
-- uploads two numbers; the server never sees body mass and cannot derive it:
--
--   workouts.calories      total active kilocalories for the whole session.
--   workout_exercises.met  measured MET (kcal / kg body mass / hour) over the
--                          exercise's window — first set start to next
--                          exercise's first set start. Body mass divides out,
--                          which is what makes the value both comparable
--                          across users (aggregable into a per-exercise
--                          intensity rating) and safe to store.
--
-- Both are observations, never targets, so template tables deliberately get
-- no counterpart columns.

ALTER TABLE workouts
    ADD COLUMN IF NOT EXISTS calories REAL;

ALTER TABLE workouts
    DROP CONSTRAINT IF EXISTS workouts_calories_nonnegative_check;
ALTER TABLE workouts
    ADD CONSTRAINT workouts_calories_nonnegative_check CHECK (calories IS NULL OR calories >= 0);

COMMENT ON COLUMN workouts.calories IS
    'Total active energy for the session in kilocalories, computed on device from wearable data; NULL when no wearable data was available';

ALTER TABLE workout_exercises
    ADD COLUMN IF NOT EXISTS met REAL;

ALTER TABLE workout_exercises
    DROP CONSTRAINT IF EXISTS workout_exercises_met_nonnegative_check;
ALTER TABLE workout_exercises
    ADD CONSTRAINT workout_exercises_met_nonnegative_check CHECK (met IS NULL OR met >= 0);

COMMENT ON COLUMN workout_exercises.met IS
    'Measured MET (kcal/kg/h) over this exercise''s time window, computed on device from wearable data; NULL when no wearable data was available';

-- Surface set completion time (column existed since the initial schema but was
-- never returned) so clients can separate work time from rest time.
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
      'set_order',    es.set_order
    ) ORDER BY es.set_order
  ) FILTER (WHERE es.id IS NOT NULL),
  '[]'::jsonb
)
FROM exercise_sets es
WHERE es.workout_exercise_id = _workout_exercise_id
$$;

DROP FUNCTION IF EXISTS _workout_exercises(_workout_id UUID);
CREATE OR REPLACE FUNCTION _workout_exercises(_workout_id UUID)
RETURNS JSONB
LANGUAGE SQL AS
$$
SELECT COALESCE(
  jsonb_agg(
    jsonb_build_object(
      'id', we.id,
      'exercise', jsonb_build_object(
          'id',       e.id,
          'category', e.category,
          'target',   e.target,
          'name',     e.name
      ),
      'exercise_order', we.exercise_order,
      'met',            we.met,
      'sets',           _exercise_sets(we.id)
    ) ORDER BY we.exercise_order
  ) FILTER (WHERE we.id IS NOT NULL),
  '[]'::JSONB
)
FROM workout_exercises we
LEFT JOIN exercises e ON e.id = we.exercise_id
WHERE we.workout_id = _workout_id
$$;

-- The archive's exercises snapshot picks up met via _workout_exercises, but
-- the workout-level total is a scalar column and must be carried explicitly.
ALTER TABLE archive.deleted_workouts
    ADD COLUMN IF NOT EXISTS calories REAL;

COMMENT ON COLUMN archive.deleted_workouts.calories IS
    'Total active energy for the session in kilocalories, as recorded at deletion time';

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
        exercises
    ) VALUES (
        OLD.id,
        OLD.user_id,
        OLD.name,
        OLD.started_at,
        OLD.completed_at,
        OLD.created_at,
        OLD.calories,
        _workout_exercises(OLD.id)
    );
    RETURN OLD;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION _archive_workout() IS 'Trigger function to archive workout data before deletion';