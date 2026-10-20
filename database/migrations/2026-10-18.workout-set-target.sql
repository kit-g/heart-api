-- What a workout set aimed for, beside what was done:
--
--   exercise_sets.target  {"reps": {"min": 6, "max": 10}, "rir": 2}
--                         the shape template_exercise_sets.target holds, as the
--                         template or program the session came from set it;
--                         NULL aims for nothing in particular.
--
-- A plan kept beside the record, never part of it: the set's own weight, reps,
-- duration and distance stay what was done. The shape inside is the writer's
-- to validate and grows with the target vocabulary, so the schema holds only
-- that it is an object with something in it.
--
-- No DROP before the ADD: the column holds what users wrote, which nothing can
-- reproduce.

ALTER TABLE IF EXISTS exercise_sets
    ADD COLUMN IF NOT EXISTS target JSONB;

ALTER TABLE IF EXISTS exercise_sets
    DROP CONSTRAINT IF EXISTS exercise_sets_target_check,
    ADD CONSTRAINT exercise_sets_target_check
        CHECK (target IS NULL OR (jsonb_typeof(target) = 'object' AND target <> '{}'::jsonb));

COMMENT ON COLUMN exercise_sets.target IS
    'What the set aimed for, keyed by measure (reps, weight, duration, distance) in the set''s own units, as template_exercise_sets.target: {min, max?}, exact when equal, an open top without max; NULL is no target';
COMMENT ON CONSTRAINT exercise_sets_target_check ON exercise_sets IS
    'A target is an object naming at least one measure; no target at all is NULL, never {}.';

-- The set snapshot carries the target, so the archive of a deleted workout
-- keeps it through the same function.
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
      'rpe',          es.rpe,
      'target',       es.target
    ) ORDER BY es.set_order
  ) FILTER (WHERE es.id IS NOT NULL),
  '[]'::jsonb
)
FROM exercise_sets es
WHERE es.workout_exercise_id = _workout_exercise_id
$$;

COMMENT ON FUNCTION _exercise_sets(UUID) IS
    'A workout exercise''s sets as JSON in set order, each with its set type spelled out, its RPE and its target';
