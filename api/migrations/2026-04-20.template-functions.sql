DROP FUNCTION IF EXISTS _template_exercise_sets(_template_exercise_id UUID);
CREATE OR REPLACE FUNCTION _template_exercise_sets(_template_exercise_id UUID)
RETURNS JSONB
LANGUAGE SQL AS
$$
SELECT coalesce(
  jsonb_agg(
    jsonb_build_object(
      'id',        tes.id,
      'weight',    tes.weight,
      'reps',      tes.reps,
      'duration',  tes.duration,
      'distance',  tes.distance,
      'set_order', tes.set_order
    ) ORDER BY tes.set_order
  ) FILTER (WHERE tes.id IS NOT NULL),
  '[]'::jsonb
)
FROM template_exercise_sets tes
WHERE tes.template_exercise_id = _template_exercise_id
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
        'id',       ex.id,
        'name',     ex.name,
        'category', ex.category,
        'target',   ex.target
      ),
      'exercise_order', te.exercise_order,
      'sets',           _template_exercise_sets(te.id)
    ) ORDER BY te.exercise_order
  ) FILTER (WHERE te.id IS NOT NULL),
  '[]'::jsonb
)
FROM template_exercises te
LEFT JOIN LATERAL (
  SELECT e.id, e.name, e.category, e.target
  FROM exercises e
  WHERE e.name = te.exercise_id
  ORDER BY e.user_id NULLS FIRST
  LIMIT 1
) ex ON true
WHERE te.template_id = _template_id
$$;