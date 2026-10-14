-- Lighter weeks (heart-api#229): a program may schedule one every N cycles, and
-- the user may take one on demand as a program action. Deloads reduce, never
-- stop: nothing moves and nothing counts as a miss in one.

ALTER TABLE IF EXISTS programs
    DROP COLUMN IF EXISTS deload,
    ADD COLUMN IF NOT EXISTS deload JSONB;

ALTER TABLE IF EXISTS programs
    DROP CONSTRAINT IF EXISTS programs_deload_check,
    ADD CONSTRAINT programs_deload_check CHECK (
        deload IS NULL OR (jsonb_typeof(deload) = 'object' AND deload ? 'every')
    );

COMMENT ON COLUMN programs.deload IS
    'A lighter week every N cycles: {every, load, volume}, the shares of weight and sets the sheet keeps; NULL schedules none';
COMMENT ON CONSTRAINT programs_deload_check ON programs IS
    'An object naming how often; the input layer checks the rest';

ALTER TABLE IF EXISTS program_actions
    DROP CONSTRAINT IF EXISTS program_actions_kind_check,
    ADD CONSTRAINT program_actions_kind_check CHECK (kind IN ('repeat', 'pause', 'resume', 'replay', 'lighter'));

COMMENT ON COLUMN program_actions.kind IS
    'repeat runs a cycle again at the same week; pause and resume step the program aside and back; replay goes back to week; lighter makes the open cycle a lighter one';
