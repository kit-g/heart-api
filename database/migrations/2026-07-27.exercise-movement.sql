-- Movement pattern + load attributes per exercise, sourced from
-- content/exercise_library.yml and pushed by scripts/library_locales.py.
--
-- Two exercises are mutually replaceable when they share a `groups` entry --
-- that is what lets a client offer a substitution ("swap the barbell squat for
-- a hack squat"). The remaining keys are objective properties of the movement,
-- never recommendations, so the client can rank or exclude candidates itself
-- (a lifter protecting their back drops axialLoad = 'high'). Keep it that way:
-- the moment a preference becomes a column, every new one costs a re-annotation
-- of the whole library.

ALTER TABLE exercises
    ADD COLUMN IF NOT EXISTS movement JSONB;

COMMENT ON COLUMN exercises.movement IS
    'Movement pattern and load attributes: {groups, axialLoad, stability, unilateral, impact, skill}. NULL when the library offers no substitute for the exercise';

-- Substitution lookup is "exercises sharing any of these groups", i.e. the jsonb
-- ?| operator against the groups array. Must be default jsonb_ops: jsonb_path_ops
-- does not support the existence operators (? / ?| / ?&).
CREATE INDEX IF NOT EXISTS exercises_movement_groups_idx
    ON exercises USING GIN ((movement -> 'groups'));
