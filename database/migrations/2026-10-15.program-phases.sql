-- Phases and test sessions (heart-api#233). A program may run in blocks, each
-- with its own sessions for a number of weeks, and may name sessions as tests
-- that set its bases. Without either it is one repeating phase, as before.

ALTER TABLE IF EXISTS programs
    DROP COLUMN IF EXISTS phases,
    DROP COLUMN IF EXISTS tests,
    ADD COLUMN IF NOT EXISTS phases JSONB,
    ADD COLUMN IF NOT EXISTS tests JSONB;

ALTER TABLE IF EXISTS programs
    DROP CONSTRAINT IF EXISTS programs_phases_check,
    ADD CONSTRAINT programs_phases_check CHECK (
        phases IS NULL OR (jsonb_typeof(phases) = 'array' AND jsonb_array_length(phases) BETWEEN 1 AND 20)
    ),
    DROP CONSTRAINT IF EXISTS programs_tests_check,
    ADD CONSTRAINT programs_tests_check CHECK (tests IS NULL OR jsonb_typeof(tests) = 'object');

COMMENT ON COLUMN programs.phases IS
    'Blocks run in order, each {name?, sessions, cycles?}: its own template ids for that many weeks, the last repeating; NULL is one repeating phase';
COMMENT ON COLUMN programs.tests IS
    'Test sessions by template id, each {share}: a workout of one sets the tested exercises'' bases to that share of an estimated max';
COMMENT ON CONSTRAINT programs_phases_check ON programs IS 'One to twenty phases; the input layer checks each';
COMMENT ON CONSTRAINT programs_tests_check ON programs IS 'An object keyed by template id; the input layer checks each';
