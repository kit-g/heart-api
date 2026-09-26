-- A template set's type, so a template can lay out its warm-ups:
--
--   template_exercise_sets.set_type  w / d / f as on exercise_sets; NULL is an
--                                    ordinary working set.
--
-- A template carries no RPE. What a program prescribes is a target, often a
-- range, not a rating of effort, and it is a different field when it comes.
--
-- _set_type_code is _set_type_name's reverse: writers send the word, and the
-- letter lives only in the database.

ALTER TABLE template_exercise_sets
    DROP COLUMN IF EXISTS set_type,
    ADD COLUMN IF NOT EXISTS set_type CHAR(1);

ALTER TABLE template_exercise_sets
    DROP CONSTRAINT IF EXISTS template_exercise_sets_set_type_check,
    ADD CONSTRAINT template_exercise_sets_set_type_check
        CHECK (set_type IS NULL OR set_type IN ('w', 'd', 'f'));

COMMENT ON COLUMN template_exercise_sets.set_type IS
    'w(armup), d(rop) or f(ailure) — _set_type_name spells it out; NULL is an ordinary working set';
COMMENT ON CONSTRAINT template_exercise_sets_set_type_check ON template_exercise_sets IS
    'The set types lifting apps share besides an ordinary working set, which is NULL.';

-- plpgsql rather than SQL so an unknown word raises instead of storing a
-- normal set: the only way one arrives is a writer out of step with the enum.
CREATE OR REPLACE FUNCTION _set_type_code(_name TEXT) RETURNS CHAR
LANGUAGE plpgsql IMMUTABLE AS
$$
BEGIN
    IF _name IS NULL OR _name = 'normal' THEN
        RETURN NULL;
    END IF;
    CASE _name
        WHEN 'warmup' THEN RETURN 'w';
        WHEN 'drop' THEN RETURN 'd';
        WHEN 'failure' THEN RETURN 'f';
        ELSE RAISE EXCEPTION 'unknown set type: %', _name USING ERRCODE = 'invalid_parameter_value';
        END CASE;
END;
$$;

COMMENT ON FUNCTION _set_type_code(TEXT) IS
    'A set type''s word as the letter set_type stores (warmup w, drop d, failure f); normal and NULL are NULL';

-- The template set snapshot carries the type, read back as its word.
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
      'set_order', tes.set_order,
      'set_type',  _set_type_name(tes.set_type)
    ) ORDER BY tes.set_order
  ) FILTER (WHERE tes.id IS NOT NULL),
  '[]'::jsonb
)
FROM template_exercise_sets tes
WHERE tes.template_exercise_id = _template_exercise_id
$$;

COMMENT ON FUNCTION _template_exercise_sets(UUID) IS
    'A template exercise''s sets as JSON in set order, each with its set type spelled out';
