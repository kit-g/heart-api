-- Two people on one program copy: a revision per session and per program, a history
-- that outlives what it describes, and what a device planned for a workout.

ALTER TABLE IF EXISTS programs
    DROP COLUMN IF EXISTS revision,
    ADD COLUMN IF NOT EXISTS revision INTEGER NOT NULL DEFAULT 0;

ALTER TABLE IF EXISTS templates
    DROP COLUMN IF EXISTS revision,
    ADD COLUMN IF NOT EXISTS revision INTEGER NOT NULL DEFAULT 0;

COMMENT ON COLUMN programs.revision IS 'How many times a coach''s copy''s own fields have changed; stays 0 on a person''s own program';
COMMENT ON COLUMN templates.revision IS 'How many times a session of a coach''s copy has changed; stays 0 elsewhere';

DROP TABLE IF EXISTS program_changes;

CREATE TABLE IF NOT EXISTS program_changes
(
    id         UUID                 DEFAULT uuidv7() PRIMARY KEY,
    program_id UUID        NOT NULL REFERENCES programs (id) ON DELETE CASCADE,
    session_id UUID,
    actor_id   TEXT REFERENCES profiles (id) ON DELETE SET NULL,
    kind       TEXT        NOT NULL,
    revision   INTEGER     NOT NULL,
    before     JSONB,
    after      JSONB,
    links      JSONB,
    stale      BOOLEAN     NOT NULL DEFAULT false,
    at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    xid        XID8        NOT NULL DEFAULT pg_current_xact_id(),
    CONSTRAINT program_changes_kind_check CHECK (kind IN ('edit', 'create', 'delete', 'revert', 'library_update'))
);

CREATE INDEX IF NOT EXISTS program_changes_order_idx ON program_changes (program_id, xid, id);
CREATE INDEX IF NOT EXISTS program_changes_subject_idx ON program_changes (program_id, session_id, revision);
CREATE INDEX IF NOT EXISTS program_changes_actor_idx ON program_changes (actor_id) WHERE actor_id IS NOT NULL;

COMMENT ON TABLE program_changes IS 'Who changed what on a coach''s copy of a program, with snapshots that outlive it';
COMMENT ON COLUMN program_changes.id IS 'Chosen by the device, so a retried save is one change';
COMMENT ON COLUMN program_changes.program_id IS 'The copy';
COMMENT ON COLUMN program_changes.session_id IS 'The session it touched; NULL for the program''s own fields. No reference, since it can name a session since deleted';
COMMENT ON COLUMN program_changes.actor_id IS 'Who made it; NULL once that account is gone';
COMMENT ON COLUMN program_changes.kind IS 'What happened';
COMMENT ON COLUMN program_changes.revision IS 'The session''s or program''s revision after it';
COMMENT ON COLUMN program_changes.before IS 'How it stood before; NULL for one just created';
COMMENT ON COLUMN program_changes.after IS 'How it stood after; NULL for one just deleted';
COMMENT ON COLUMN program_changes.links IS 'For a deleted session, the workouts and skips that named it, whose links a deletion clears';
COMMENT ON COLUMN program_changes.stale IS 'Written by a build that sends no revision, so it may have overwritten something it never saw';
COMMENT ON COLUMN program_changes.at IS 'When';
COMMENT ON COLUMN program_changes.xid IS 'The transaction that made it; what reading what changed goes by';
COMMENT ON CONSTRAINT program_changes_kind_check ON program_changes IS 'The ways a copy changes';
COMMENT ON INDEX program_changes_order_idx IS 'A copy''s history in stored order';
COMMENT ON INDEX program_changes_subject_idx IS 'Whether someone else changed a session since a revision';
COMMENT ON INDEX program_changes_actor_idx IS 'The SET NULL when an actor''s profile is deleted';

DROP TABLE IF EXISTS workout_plans;

CREATE TABLE IF NOT EXISTS workout_plans
(
    workout_id UUID PRIMARY KEY REFERENCES workouts (id) ON DELETE CASCADE,
    plan       JSONB       NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT workout_plans_plan_check CHECK (jsonb_typeof(plan) = 'object')
);

COMMENT ON TABLE workout_plans IS 'What a device planned for a workout, as it stood then; what was asked, beside what was done';
COMMENT ON COLUMN workout_plans.workout_id IS 'The workout; one without a row has nothing to compare with';
COMMENT ON COLUMN workout_plans.plan IS 'The planned session, lighter weeks and waves applied, and which set each planned set became';
COMMENT ON COLUMN workout_plans.created_at IS 'When it arrived';
COMMENT ON CONSTRAINT workout_plans_plan_check ON workout_plans IS 'A document';
