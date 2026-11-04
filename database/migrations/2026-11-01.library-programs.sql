-- A coach's library: programs kept as versioned documents, apart from their own
-- training, and a student's copy that knows where it came from.

DROP TABLE IF EXISTS library_program_versions;
DROP TABLE IF EXISTS library_programs CASCADE;

CREATE TABLE IF NOT EXISTS library_programs
(
    id         UUID PRIMARY KEY,
    coach_id   TEXT        NOT NULL REFERENCES profiles (id) ON DELETE CASCADE,
    name       TEXT        NOT NULL,
    version    INTEGER     NOT NULL DEFAULT 1,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT library_programs_name_check CHECK (length(trim(name)) BETWEEN 1 AND 100)
);

CREATE INDEX IF NOT EXISTS library_programs_coach_idx ON library_programs (coach_id, id);

COMMENT ON TABLE library_programs IS 'A program a coach sends to clients, apart from their own training';
COMMENT ON COLUMN library_programs.id IS 'Chosen by the device';
COMMENT ON COLUMN library_programs.coach_id IS 'Whose library';
COMMENT ON COLUMN library_programs.name IS 'Its name, 1 to 100 characters';
COMMENT ON COLUMN library_programs.version IS 'The current version; a change makes a new one and touches no copy';
COMMENT ON COLUMN library_programs.created_at IS 'When it was made';
COMMENT ON COLUMN library_programs.updated_at IS 'When it last changed';
COMMENT ON CONSTRAINT library_programs_name_check ON library_programs IS 'Between 1 and 100 characters';
COMMENT ON INDEX library_programs_coach_idx IS 'One coach''s library';

CREATE TABLE IF NOT EXISTS library_program_versions
(
    library_program_id UUID        NOT NULL REFERENCES library_programs (id) ON DELETE CASCADE,
    version            INTEGER     NOT NULL,
    body               JSONB       NOT NULL,
    created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (library_program_id, version),
    CONSTRAINT library_program_versions_body_check CHECK (jsonb_typeof(body) = 'object')
);

COMMENT ON TABLE library_program_versions IS 'Each version of a library program, as it stood';
COMMENT ON COLUMN library_program_versions.library_program_id IS 'The program';
COMMENT ON COLUMN library_program_versions.version IS 'Which version';
COMMENT ON COLUMN library_program_versions.body IS 'The program and its sessions, in the camelCase shape a program is created from';
COMMENT ON COLUMN library_program_versions.created_at IS 'When it was saved';
COMMENT ON CONSTRAINT library_program_versions_body_check ON library_program_versions IS 'A document';

ALTER TABLE IF EXISTS programs
    DROP COLUMN IF EXISTS coach_id,
    DROP COLUMN IF EXISTS connection_id,
    DROP COLUMN IF EXISTS library_program_id,
    DROP COLUMN IF EXISTS library_version,
    DROP COLUMN IF EXISTS library_ids,
    DROP COLUMN IF EXISTS waiting_since,
    ADD COLUMN IF NOT EXISTS coach_id TEXT REFERENCES profiles (id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS connection_id UUID REFERENCES connections (id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS library_program_id UUID REFERENCES library_programs (id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS library_version INTEGER,
    ADD COLUMN IF NOT EXISTS library_ids JSONB,
    ADD COLUMN IF NOT EXISTS waiting_since TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS programs_coach_idx ON programs (coach_id) WHERE coach_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS programs_connection_idx ON programs (connection_id) WHERE connection_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS programs_library_copy_key
    ON programs (user_id, library_program_id) WHERE library_program_id IS NOT NULL;

COMMENT ON COLUMN programs.coach_id IS 'The coach who sent this copy; NULL for the user''s own, or once they are gone';
COMMENT ON COLUMN programs.connection_id IS 'The relationship it came through, whose end ends the coach''s access to it';
COMMENT ON COLUMN programs.library_program_id IS 'The library program it was copied from; NULL once that is deleted';
COMMENT ON COLUMN programs.library_version IS 'The version of it this copy holds';
COMMENT ON COLUMN programs.library_ids IS 'Each id in the library program, as this copy''s own id, so an update can find its rows';
COMMENT ON COLUMN programs.waiting_since IS 'Sent while the student was on something else, and waiting for them to start it; NULL once started';
COMMENT ON INDEX programs_coach_idx IS 'The SET NULL when a coach''s profile is deleted';
COMMENT ON INDEX programs_connection_idx IS 'The SET NULL when a connection is deleted';
COMMENT ON INDEX programs_library_copy_key IS 'A student holds one copy of a library program';

ALTER TABLE IF EXISTS invitations
    DROP COLUMN IF EXISTS library_program_id,
    ADD COLUMN IF NOT EXISTS library_program_id UUID REFERENCES library_programs (id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS invitations_library_program_idx ON invitations (library_program_id)
    WHERE library_program_id IS NOT NULL;

COMMENT ON COLUMN invitations.library_program_id IS 'A program to start with, sent on acceptance';
COMMENT ON INDEX invitations_library_program_idx IS 'The SET NULL when a library program is deleted';
