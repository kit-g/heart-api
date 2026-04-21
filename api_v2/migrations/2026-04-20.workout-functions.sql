DROP FUNCTION IF EXISTS _exercise_sets(_workout_exercise_id UUID);
CREATE OR REPLACE FUNCTION _exercise_sets(_workout_exercise_id UUID)
RETURNS JSONB
LANGUAGE SQL AS
$$
SELECT COALESCE(
  jsonb_agg(
    jsonb_build_object(
      'id',         es.id,
      'weight',     es.weight,
      'reps',       es.reps,
      'duration',   es.duration,
      'distance',   es.distance,
      'completed',  es.completed,
      'started_at', es.started_at,
      'set_order',  es.set_order
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
      'sets',           _exercise_sets(we.id)
    ) ORDER BY we.exercise_order
  ) FILTER (WHERE we.id IS NOT NULL),
  '[]'::JSONB
)
FROM workout_exercises we
LEFT JOIN exercises e ON e.id = we.exercise_id
WHERE we.workout_id = _workout_id
$$;
