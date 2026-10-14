-- Rest between sets as a template plans it (heart-api#230): 2–3 minutes for a
-- compound lift, 60–90 seconds for isolation work. NULL leaves it to the user's
-- own timer.

ALTER TABLE IF EXISTS template_exercises
    DROP COLUMN IF EXISTS rest,
    ADD COLUMN IF NOT EXISTS rest INTEGER;

ALTER TABLE IF EXISTS template_exercises
    DROP CONSTRAINT IF EXISTS template_exercises_rest_check,
    ADD CONSTRAINT template_exercises_rest_check CHECK (rest IS NULL OR rest BETWEEN 0 AND 1800);

COMMENT ON COLUMN template_exercises.rest IS
    'Seconds of rest between sets the template plans; NULL leaves it to the user''s own timer';
COMMENT ON CONSTRAINT template_exercises_rest_check ON template_exercises IS
    'Up to 30 minutes';

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
      'sets',           _template_exercise_sets(te.id)
    ) ORDER BY te.exercise_order
  ) FILTER (WHERE te.id IS NOT NULL),
  '[]'::jsonb
)
FROM template_exercises te
JOIN exercises e ON e.id = te.exercise_id
WHERE te.template_id = _template_id
$$ LANGUAGE sql;

COMMENT ON FUNCTION _template_exercises(UUID) IS
    'A template''s exercises as JSONB, in order: each with its exercise, its order, its rest and its sets';
