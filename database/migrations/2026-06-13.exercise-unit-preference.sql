-- Per-(user, exercise) preferences: merges chart_type and unit_system into one table,
-- replacing chart_preferences (charts is not live yet, so there is no data to migrate).
-- Also retires the dormant per-workout/per-template unit_system overrides and adds a
-- global per-user settings blob to profiles.

DROP TABLE IF EXISTS chart_preferences;
DROP TABLE IF EXISTS exercise_preferences;
CREATE TABLE IF NOT EXISTS exercise_preferences
(
    id          UUID                 DEFAULT uuidv7() PRIMARY KEY,
    user_id     TEXT        NOT NULL REFERENCES profiles (id) ON DELETE CASCADE,
    exercise_id UUID        NOT NULL REFERENCES exercises (id) ON DELETE CASCADE,
    chart_type  TEXT,
    unit_system TEXT CHECK (unit_system IS NULL OR unit_system IN ('imperial', 'metric')),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (user_id, exercise_id)
);

COMMENT ON TABLE exercise_preferences IS
    'Per-user, per-exercise display preferences';
COMMENT ON COLUMN exercise_preferences.chart_type IS
    'Preferred chart type for this exercise; NULL when unset';
COMMENT ON COLUMN exercise_preferences.unit_system IS
    'Preferred measurement unit for this exercise; NULL falls back to the user global setting';

-- Retire the dormant per-workout/per-template unit_system overrides (replaced by
-- exercise_preferences + the global profiles.settings default).
ALTER TABLE workout_exercises DROP COLUMN IF EXISTS unit_system;
ALTER TABLE template_exercises DROP COLUMN IF EXISTS unit_system;

-- Revert the read helpers to their pre-unit_system shape.
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
      'sets',           _template_exercise_sets(te.id)
    ) ORDER BY te.exercise_order
  ) FILTER (WHERE te.id IS NOT NULL),
  '[]'::jsonb
)
FROM template_exercises te
JOIN exercises e ON e.id = te.exercise_id
WHERE te.template_id = _template_id
$$;

-- Global per-user settings (unit-system default, theme mode, accent color, future toggles).
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS settings JSONB NOT NULL DEFAULT '{}'::jsonb;

COMMENT ON COLUMN profiles.settings IS
    'Global per-user preferences blob (unit-system default, theme mode, accent color, etc.)';
