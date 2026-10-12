-- What a template set aims for, per measure it records:
--
--   template_exercise_sets.target  {"reps": {"min": 6, "max": 10}, "duration": {"min": 30, "max": 30}}
--                                  min equal to max is an exact number, no max an open top ("8+");
--                                  NULL aims for nothing in particular.
--
-- A plan, not a record: workout sets have no such column. The shape inside is
-- the writer's to validate and grows with the target vocabulary, so the schema
-- holds only that it is an object with something in it.
--
-- No DROP before the ADD: the column holds what users wrote, which nothing can
-- reproduce.

ALTER TABLE IF EXISTS template_exercise_sets
    ADD COLUMN IF NOT EXISTS target JSONB;

ALTER TABLE IF EXISTS template_exercise_sets
    DROP CONSTRAINT IF EXISTS template_exercise_sets_target_check,
    ADD CONSTRAINT template_exercise_sets_target_check
        CHECK (target IS NULL OR (jsonb_typeof(target) = 'object' AND target <> '{}'::jsonb));

COMMENT ON COLUMN template_exercise_sets.target IS
    'What the set aims for, keyed by measure (reps, weight, duration, distance) in the set''s own units: {min, max?}, exact when equal, an open top without max; NULL is no target';
COMMENT ON CONSTRAINT template_exercise_sets_target_check ON template_exercise_sets IS
    'A target is an object naming at least one measure; no target at all is NULL, never {}.';

-- The template set snapshot carries the target.
CREATE OR REPLACE FUNCTION _template_exercise_sets(_template_exercise_id UUID)
RETURNS JSONB
LANGUAGE SQL AS
$$
SELECT coalesce(
    jsonb_agg(
        jsonb_build_object(
            'id', tes.id,
            'weight', tes.weight,
            'reps', tes.reps,
            'duration', tes.duration,
            'distance', tes.distance,
            'set_order', tes.set_order,
            'set_type', _set_type_name(tes.set_type),
            'target', tes.target
        ) ORDER BY tes.set_order
    ) FILTER (WHERE tes.id IS NOT NULL),
    '[]'::jsonb
)
FROM template_exercise_sets tes
WHERE tes.template_exercise_id = _template_exercise_id
$$;

COMMENT ON FUNCTION _template_exercise_sets(UUID) IS
    'A template exercise''s sets as JSON in set order, each with its set type spelled out and its target';
