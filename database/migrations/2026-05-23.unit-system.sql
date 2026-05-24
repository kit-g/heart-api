ALTER TABLE workout_exercises
    DROP COLUMN IF EXISTS unit_system,
    ADD COLUMN unit_system TEXT
        CHECK (unit_system IS NULL OR unit_system IN ('imperial', 'metric'));

ALTER TABLE template_exercises
    DROP COLUMN IF EXISTS unit_system,
    ADD COLUMN unit_system TEXT
        CHECK (unit_system IS NULL OR unit_system IN ('imperial', 'metric'));

COMMENT ON COLUMN workout_exercises.unit_system IS
    'Measurement unit override for this WorkoutExercise; NULL falls back to the device default';
COMMENT ON COLUMN template_exercises.unit_system IS
    'Measurement unit override for this TemplateExercise; NULL falls back to the device default';

-- Replace read helpers to surface unit_system to clients.
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
      'unit_system',    we.unit_system,
      'sets',           _exercise_sets(we.id)
    ) ORDER BY we.exercise_order
  ) FILTER (WHERE we.id IS NOT NULL),
  '[]'::JSONB
)
FROM workout_exercises we
LEFT JOIN exercises e ON e.id = we.exercise_id
WHERE we.workout_id = _workout_id
$$;

DROP FUNCTION IF EXISTS _template_exercises(_template_id UUID);
CREATE OR REPLACE FUNCTION _template_exercises(_template_id UUID)
RETURNS JSONB
LANGUAGE SQL AS
$$
SELECT coalesce(
  jsonb_agg(
    jsonb_build_object(
      'id',             te.id,
      'exercise',       jsonb_build_object(
        'id',       e.id,
        'name',     e.name,
        'category', e.category,
        'target',   e.target
      ),
      'exercise_order', te.exercise_order,
      'unit_system',    te.unit_system,
      'sets',           _template_exercise_sets(te.id)
    ) ORDER BY te.exercise_order
  ) FILTER (WHERE te.id IS NOT NULL),
  '[]'::jsonb
)
FROM template_exercises te
JOIN exercises e ON e.id = te.exercise_id
WHERE te.template_id = _template_id
$$;
