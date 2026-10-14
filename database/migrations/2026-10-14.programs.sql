-- Programs: the user's templates on a plan, with targets that grow
-- (docs/2026-10-13.programs.md). A program owns its sessions: they are templates
-- carrying its id. Where the user stands in it is computed from workouts, skips
-- and program actions, so nothing here is a position.

DROP TABLE IF EXISTS programs CASCADE;

CREATE TABLE IF NOT EXISTS programs
(
    id             UUID                 DEFAULT uuidv7() PRIMARY KEY,
    user_id        TEXT        NOT NULL REFERENCES profiles (id) ON DELETE CASCADE,
    name           TEXT        NOT NULL,
    note           TEXT,
    source         TEXT,
    per_week       SMALLINT,
    days           SMALLINT[]  NOT NULL DEFAULT '{}',
    weeks          SMALLINT,
    rules          JSONB       NOT NULL DEFAULT '{}',
    constraint_key TEXT,
    archived       BOOLEAN     NOT NULL DEFAULT false,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT programs_id_user_key UNIQUE (id, user_id),
    CONSTRAINT programs_name_check CHECK (length(trim(name)) BETWEEN 1 AND 100),
    CONSTRAINT programs_note_check CHECK (note IS NULL OR char_length(note) BETWEEN 1 AND 1000),
    CONSTRAINT programs_source_check CHECK (source IS NULL OR source ~ '^[a-z][a-z0-9_]{0,63}$'),
    CONSTRAINT programs_per_week_check CHECK (per_week IS NULL OR per_week BETWEEN 1 AND 28),
    CONSTRAINT programs_days_check CHECK (days <@ '{1,2,3,4,5,6,7}'::SMALLINT[]),
    CONSTRAINT programs_weeks_check CHECK (weeks IS NULL OR weeks BETWEEN 1 AND 104),
    CONSTRAINT programs_rules_check CHECK (jsonb_typeof(rules) = 'object'),
    CONSTRAINT programs_constraint_key_check CHECK (
        constraint_key IS NULL OR constraint_key ~ '^[a-z][a-z0-9_]{0,63}$'
    )
);

CREATE INDEX IF NOT EXISTS programs_user_id_idx ON programs (user_id, id);

COMMENT ON TABLE programs IS
    'A plan of the user''s templates with targets that grow; its sessions are templates carrying its id';
COMMENT ON COLUMN programs.name IS 'The program''s name, 1 to 100 characters';
COMMENT ON COLUMN programs.note IS 'What the program is for, in the user''s words or the library''s';
COMMENT ON COLUMN programs.source IS
    'The library program this one was copied from; a content id, not a reference, and the copy never follows it';
COMMENT ON COLUMN programs.per_week IS
    'Weekly target in sessions, not days, so two-a-days fit; offered, never enforced. NULL sets none';
COMMENT ON COLUMN programs.days IS
    'Preferred ISO weekdays (1 Monday to 7 Sunday): a hint for reminders and for the suggested session, never a gate';
COMMENT ON COLUMN programs.weeks IS 'Length in program weeks (completed cycles, not calendar weeks); NULL runs on';
COMMENT ON COLUMN programs.rules IS
    'Growth rule per exercise id, as {kind, ...parameters}; an exercise without one is done as written';
COMMENT ON COLUMN programs.constraint_key IS
    'A content key such as avoid_high_axial_load that filters suggestions inside the program';
COMMENT ON COLUMN programs.archived IS 'The user stopped following it; its history stays';
COMMENT ON CONSTRAINT programs_id_user_key ON programs IS
    'Target of templates_program_fk, so a template can only join a program of the same user';
COMMENT ON CONSTRAINT programs_days_check ON programs IS 'Every day is an ISO weekday';
COMMENT ON CONSTRAINT programs_weeks_check ON programs IS
    'Two years at most; a longer plan is an ongoing one';
COMMENT ON INDEX programs_user_id_idx IS 'The owner''s programs, in creation order';

-- No DROP before the ADD: the columns hold what users wrote.
ALTER TABLE IF EXISTS templates
    ADD COLUMN IF NOT EXISTS program_id UUID,
    ADD COLUMN IF NOT EXISTS note TEXT;

ALTER TABLE IF EXISTS templates
    DROP CONSTRAINT IF EXISTS templates_program_fk,
    ADD CONSTRAINT templates_program_fk
        FOREIGN KEY (program_id, user_id) REFERENCES programs (id, user_id) ON DELETE CASCADE,
    DROP CONSTRAINT IF EXISTS templates_note_check,
    ADD CONSTRAINT templates_note_check CHECK (note IS NULL OR char_length(note) BETWEEN 1 AND 1000);

CREATE INDEX IF NOT EXISTS templates_program_id_idx ON templates (program_id) WHERE program_id IS NOT NULL;

COMMENT ON COLUMN templates.program_id IS
    'The program this template is a session of; NULL for a plain template. Deleting the program deletes its sessions';
COMMENT ON COLUMN templates.note IS 'A line about the template, such as what a session is for';
COMMENT ON CONSTRAINT templates_program_fk ON templates IS
    'Composite so a template can only be a session of a program owned by the same user';
COMMENT ON CONSTRAINT templates_note_check ON templates IS 'At most 1000 characters, never empty';
COMMENT ON INDEX templates_program_id_idx IS 'A program''s sessions';
