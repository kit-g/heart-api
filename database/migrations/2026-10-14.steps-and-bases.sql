-- How the user steers a program, and what its growth rules grow
-- (docs/2026-10-13.programs.md). Both are history, never state: a program's
-- position and its current bases are read off them, and undoing a step is
-- deleting its row.

DROP TABLE IF EXISTS program_bases;
DROP TABLE IF EXISTS program_actions;

CREATE TABLE IF NOT EXISTS program_actions
(
    id         UUID                 DEFAULT uuidv7() PRIMARY KEY,
    user_id    TEXT        NOT NULL,
    program_id UUID        NOT NULL,
    kind       TEXT        NOT NULL,
    week       SMALLINT,
    at         TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT program_actions_id_user_key UNIQUE (id, user_id),
    CONSTRAINT program_actions_program_fk
        FOREIGN KEY (program_id, user_id) REFERENCES programs (id, user_id) ON DELETE CASCADE,
    CONSTRAINT program_actions_kind_check CHECK (kind IN ('repeat', 'pause', 'resume', 'replay')),
    CONSTRAINT program_actions_week_check CHECK (
        CASE
            WHEN kind = 'replay' THEN week IS NOT NULL AND week BETWEEN 1 AND 104
            ELSE week IS NULL
        END
    )
);

CREATE INDEX IF NOT EXISTS program_actions_program_idx ON program_actions (program_id, at);

COMMENT ON TABLE program_actions IS
    'Steps the user took in a program: repeat, pause, resume, replay. Undoing one deletes it';
COMMENT ON COLUMN program_actions.kind IS
    'repeat runs a cycle again at the same week; pause and resume step the program aside and back; replay goes back to week';
COMMENT ON COLUMN program_actions.week IS 'The week a replay goes back to, from 1; NULL for every other kind';
COMMENT ON COLUMN program_actions.at IS 'When the user took the step, by the device''s clock: the order a fold replays it in';
COMMENT ON CONSTRAINT program_actions_id_user_key ON program_actions IS
    'Target of program_bases_action_fk, so a base can only be caused by its own user''s action';
COMMENT ON CONSTRAINT program_actions_program_fk ON program_actions IS
    'Composite so an action can only belong to a program of the same user';
COMMENT ON CONSTRAINT program_actions_week_check ON program_actions IS
    'Only a replay names a week, within the longest program';
COMMENT ON INDEX program_actions_program_idx IS 'A program''s actions in the order they were taken';

CREATE TABLE IF NOT EXISTS program_bases
(
    id          UUID                 DEFAULT uuidv7() PRIMARY KEY,
    user_id     TEXT        NOT NULL,
    program_id  UUID        NOT NULL,
    exercise_id UUID        NOT NULL REFERENCES exercises (id) ON DELETE CASCADE,
    value       REAL        NOT NULL,
    workout_id  UUID REFERENCES workouts (id) ON DELETE CASCADE,
    action_id   UUID,
    at          TIMESTAMPTZ NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT program_bases_program_fk
        FOREIGN KEY (program_id, user_id) REFERENCES programs (id, user_id) ON DELETE CASCADE,
    CONSTRAINT program_bases_action_fk
        FOREIGN KEY (action_id, user_id) REFERENCES program_actions (id, user_id) ON DELETE CASCADE,
    CONSTRAINT program_bases_value_check CHECK (value > 0),
    CONSTRAINT program_bases_cause_check CHECK (num_nonnulls(workout_id, action_id) <= 1)
);

CREATE INDEX IF NOT EXISTS program_bases_program_idx ON program_bases (program_id, exercise_id, at);
CREATE UNIQUE INDEX IF NOT EXISTS program_bases_workout_idx
    ON program_bases (program_id, exercise_id, workout_id)
    WHERE workout_id IS NOT NULL;

COMMENT ON TABLE program_bases IS
    'Every value of what an exercise''s growth rule grows in a program, with its cause; the current base is the latest';
COMMENT ON COLUMN program_bases.value IS
    'A training max or working weight in kilograms, a duration in seconds, or a distance in kilometres, per the rule';
COMMENT ON COLUMN program_bases.workout_id IS
    'The workout whose result moved the base; deleting the workout deletes the move';
COMMENT ON COLUMN program_bases.action_id IS
    'The action that moved the base, such as a replay''s cut; deleting the action deletes the move';
COMMENT ON COLUMN program_bases.at IS 'When the base took this value, by the device''s clock';
COMMENT ON CONSTRAINT program_bases_program_fk ON program_bases IS
    'Composite so a base can only belong to a program of the same user';
COMMENT ON CONSTRAINT program_bases_action_fk ON program_bases IS
    'Composite so a base can only be caused by an action of the same user';
COMMENT ON CONSTRAINT program_bases_cause_check ON program_bases IS
    'A workout, an action, or neither (the user set it), never both';
COMMENT ON INDEX program_bases_program_idx IS 'An exercise''s bases in a program, in order';
COMMENT ON INDEX program_bases_workout_idx IS
    'One move per exercise per workout, so a second device replaying the same bump adds nothing';
