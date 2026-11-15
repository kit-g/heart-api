-- A library exercise named in a reader's language wherever a workout or a template
-- carries it, as the exercise list already does: the locale's own translation, then
-- its bare language's (es_MX, then es), then the exercise's own name. An own
-- exercise has no translations, so it keeps the name its owner wrote. A NULL locale
-- is the exercise's own name, which is what the archive keeps of a deleted workout.

CREATE OR REPLACE FUNCTION _exercise_name(_exercise_id UUID, _name TEXT, _locale TEXT) RETURNS TEXT AS
$$
SELECT coalesce(
  (
    SELECT t.name
    FROM exercise_translations t
    WHERE t.exercise_id = _exercise_id
      AND t.locale = _locale
  ),
  (
    SELECT t.name
    FROM exercise_translations t
    WHERE t.exercise_id = _exercise_id
      AND t.locale = split_part(_locale, '_', 1)
  ),
  _name
)
$$ LANGUAGE sql STABLE;

COMMENT ON FUNCTION _exercise_name(UUID, TEXT, TEXT) IS
    'An exercise''s name in a locale: its translation, its bare language''s, else the name given; NULL locale gives the name given';

-- A locale argument, defaulting to none, so the archive triggers' one-argument
-- calls read as before. The old one-argument functions go first: a new argument
-- list is a new function, and two would make every one-argument call ambiguous.
DROP FUNCTION IF EXISTS _workout_exercises(UUID);
CREATE OR REPLACE FUNCTION _workout_exercises(_workout_id UUID, _locale TEXT DEFAULT NULL) RETURNS JSONB AS
$$
SELECT COALESCE(
  jsonb_agg(
    jsonb_build_object(
      'id', we.id,
      'exercise', jsonb_build_object(
          'id',       e.id,
          'category', e.category,
          'target',   e.target,
          'name',     _exercise_name(e.id, e.name, _locale)
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

DROP FUNCTION IF EXISTS _template_exercises(UUID);
CREATE OR REPLACE FUNCTION _template_exercises(_template_id UUID, _locale TEXT DEFAULT NULL) RETURNS JSONB AS
$$
SELECT coalesce(
  jsonb_agg(
    jsonb_build_object(
      'id',             te.id,
      'exercise',       jsonb_build_object(
        'id',       e.id,
        'name',     _exercise_name(e.id, e.name, _locale),
        'category', e.category,
        'target',   e.target
      ),
      'exercise_order', te.exercise_order,
      'rest',           te.rest,
      'superset',       te.superset,
      'pattern',        te.pattern,
      'totalReps',      te.total_reps,
      'sets',           _template_exercise_sets(te.id)
    ) ORDER BY te.exercise_order
  ) FILTER (WHERE te.id IS NOT NULL),
  '[]'::jsonb
)
FROM template_exercises te
JOIN exercises e ON e.id = te.exercise_id
WHERE te.template_id = _template_id
$$ LANGUAGE sql;

COMMENT ON FUNCTION _workout_exercises(UUID, TEXT) IS
    'A workout''s exercises as JSONB, in order: each with its exercise named in the locale, its order, MET, note, superset and sets';
COMMENT ON FUNCTION _template_exercises(UUID, TEXT) IS
    'A template''s exercises as JSONB, in order: each with its exercise named in the locale, order, rest, superset, open-slot pattern, total reps and sets';
