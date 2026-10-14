-- Slots (heart-api#232). A base may belong to one occurrence of a lift, the
-- template exercise, so the same lift heavy on Monday and light on Thursday
-- keeps two. A template exercise may be an open slot: any exercise of a
-- movement pattern, with a total of reps across its sets.

ALTER TABLE IF EXISTS program_bases
    DROP COLUMN IF EXISTS slot,
    ADD COLUMN IF NOT EXISTS slot UUID;

-- one move per workout, now per slot as well: the two occurrences of a lift
-- each move their own base from the same workout
DROP INDEX IF EXISTS program_bases_workout_idx;
CREATE UNIQUE INDEX IF NOT EXISTS program_bases_workout_idx
    ON program_bases (program_id, exercise_id, coalesce(slot, '00000000-0000-0000-0000-000000000000'::UUID), workout_id)
    WHERE workout_id IS NOT NULL;

COMMENT ON COLUMN program_bases.slot IS
    'The template exercise this base belongs to when one lift has two in a program; NULL is the exercise''s own base. Not a reference: a session edit may drop it';
COMMENT ON INDEX program_bases_workout_idx IS
    'One move per exercise, slot and workout, so a second device replaying the same bump adds nothing';

ALTER TABLE IF EXISTS template_exercises
    DROP COLUMN IF EXISTS pattern,
    DROP COLUMN IF EXISTS total_reps,
    ADD COLUMN IF NOT EXISTS pattern TEXT,
    ADD COLUMN IF NOT EXISTS total_reps JSONB;

ALTER TABLE IF EXISTS template_exercises
    DROP CONSTRAINT IF EXISTS template_exercises_pattern_check,
    ADD CONSTRAINT template_exercises_pattern_check CHECK (pattern IS NULL OR pattern ~ '^[a-z][a-z0-9_]{0,63}$'),
    DROP CONSTRAINT IF EXISTS template_exercises_total_reps_check,
    ADD CONSTRAINT template_exercises_total_reps_check CHECK (
        total_reps IS NULL OR (jsonb_typeof(total_reps) = 'object' AND total_reps ? 'min')
    );

COMMENT ON COLUMN template_exercises.pattern IS
    'An open slot: any exercise of this movement pattern (a library key) will do, exercise_id being the one offered';
COMMENT ON COLUMN template_exercises.total_reps IS
    'Reps across all of this exercise''s sets, as a {min, max?} range: "50 to 100 reps of a pull"';
COMMENT ON CONSTRAINT template_exercises_pattern_check ON template_exercises IS
    'A snake_case library key; which keys exist is the library''s business';
COMMENT ON CONSTRAINT template_exercises_total_reps_check ON template_exercises IS
    'A range object with at least a min; the input layer checks the rest';

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

COMMENT ON FUNCTION _template_exercises(UUID) IS
    'A template''s exercises as JSONB, in order: each with its exercise, order, rest, superset, open-slot pattern, total reps and sets';
