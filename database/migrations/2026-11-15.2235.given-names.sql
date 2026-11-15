-- What one person calls another: a coach's own name for a client. Only the one who
-- gave it reads it. It belongs to the pair, not to one relationship between them, so
-- it outlives a relationship ending, and goes when either account does.

DROP TABLE IF EXISTS given_names;

CREATE TABLE IF NOT EXISTS given_names
(
    giver_id   TEXT        NOT NULL REFERENCES profiles (id) ON DELETE CASCADE,
    person_id  TEXT        NOT NULL REFERENCES profiles (id) ON DELETE CASCADE,
    name       TEXT        NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (giver_id, person_id),
    CONSTRAINT given_names_name_check CHECK (length(trim(name)) BETWEEN 1 AND 100),
    CONSTRAINT given_names_not_self CHECK (giver_id <> person_id)
);

CREATE INDEX IF NOT EXISTS given_names_person_idx ON given_names (person_id);

COMMENT ON TABLE given_names IS 'A name one person gave another; only the giver reads it';
COMMENT ON COLUMN given_names.giver_id IS 'Who gave the name, and the only one who reads it';
COMMENT ON COLUMN given_names.person_id IS 'Who it names';
COMMENT ON COLUMN given_names.name IS 'The name, as the giver wrote it';
COMMENT ON COLUMN given_names.updated_at IS 'When it was last set';
COMMENT ON CONSTRAINT given_names_name_check ON given_names IS 'Between 1 and 100 characters, as an invitation''s name';
COMMENT ON CONSTRAINT given_names_not_self ON given_names IS 'A name is for someone else';
COMMENT ON INDEX given_names_person_idx IS 'The cascade when a named person''s profile is deleted';

-- The name a giver set, or else the one they wrote on the last invitation of theirs
-- the person accepted. NULL when they gave neither.
CREATE OR REPLACE FUNCTION _given_name(_giver TEXT, _person TEXT) RETURNS TEXT
    LANGUAGE sql
    STABLE
AS
$$
SELECT coalesce(
    (
        SELECT g.name
        FROM given_names g
        WHERE g.giver_id = _giver
          AND g.person_id = _person
    ),
    (
        SELECT i.name
        FROM invitation_responses r
        JOIN invitations i ON i.id = r.invitation_id
        WHERE r.user_id = _person
          AND r.response = 'accepted'
          AND i.inviter_id = _giver
        ORDER BY r.at DESC
        LIMIT 1
    )
)
$$;

COMMENT ON FUNCTION _given_name(TEXT, TEXT) IS
    'What the first person calls the second: the name they set, else the one on their last invitation the second accepted';
