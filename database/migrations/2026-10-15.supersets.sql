-- Supersets and circuits (heart-api#234): exercises of one template or workout
-- that share a number are done back to back. NULL stands alone. The number
-- means nothing outside its session.

ALTER TABLE IF EXISTS template_exercises
    DROP COLUMN IF EXISTS superset,
    ADD COLUMN IF NOT EXISTS superset SMALLINT;

ALTER TABLE IF EXISTS template_exercises
    DROP CONSTRAINT IF EXISTS template_exercises_superset_check,
    ADD CONSTRAINT template_exercises_superset_check CHECK (superset IS NULL OR superset BETWEEN 1 AND 50);

ALTER TABLE IF EXISTS workout_exercises
    DROP COLUMN IF EXISTS superset,
    ADD COLUMN IF NOT EXISTS superset SMALLINT;

ALTER TABLE IF EXISTS workout_exercises
    DROP CONSTRAINT IF EXISTS workout_exercises_superset_check,
    ADD CONSTRAINT workout_exercises_superset_check CHECK (superset IS NULL OR superset BETWEEN 1 AND 50);

COMMENT ON COLUMN template_exercises.superset IS
    'Exercises of the template sharing this number are done back to back; NULL stands alone';
COMMENT ON COLUMN workout_exercises.superset IS
    'Exercises of the workout sharing this number were done back to back; NULL stands alone';
COMMENT ON CONSTRAINT template_exercises_superset_check ON template_exercises IS
    'A small number within one template';
COMMENT ON CONSTRAINT workout_exercises_superset_check ON workout_exercises IS
    'A small number within one workout';

CREATE OR REPLACE FUNCTION _template_exercises(_template_id UUID) RETURNS JSONB AS
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
      'rest',           te.rest,
      'superset',       te.superset,
      'sets',           _template_exercise_sets(te.id)
    ) ORDER BY te.exercise_order
  ) FILTER (WHERE te.id IS NOT NULL),
  '[]'::jsonb
)
FROM template_exercises te
JOIN exercises e ON e.id = te.exercise_id
WHERE te.template_id = _template_id
$$ LANGUAGE sql;

CREATE OR REPLACE FUNCTION _workout_exercises(_workout_id UUID) RETURNS JSONB AS
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
      'note',           we.note,
      'superset',       we.superset,
      'sets',           _exercise_sets(we.id)
    ) ORDER BY we.exercise_order
  ) FILTER (WHERE we.id IS NOT NULL),
  '[]'::JSONB
)
FROM workout_exercises we
LEFT JOIN exercises e ON e.id = we.exercise_id
WHERE we.workout_id = _workout_id
$$ LANGUAGE sql;

COMMENT ON FUNCTION _template_exercises(UUID) IS
    'A template''s exercises as JSONB, in order: each with its exercise, its order, its rest, its superset and its sets';
COMMENT ON FUNCTION _workout_exercises(UUID) IS
    'A workout''s exercises as JSONB, in order: each with its exercise, its order, MET, note, superset and sets';
