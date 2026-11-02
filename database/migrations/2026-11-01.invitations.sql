-- Invitations: a link a coach makes for a named person. Accepting is what uses
-- it. max_uses and the separate responses leave room for a link many can ask
-- through, which this version doesn't offer.

DROP TABLE IF EXISTS invitation_responses;
DROP TABLE IF EXISTS invitations;

CREATE TABLE IF NOT EXISTS invitations
(
    id          UUID                 DEFAULT uuidv7() PRIMARY KEY,
    inviter_id  TEXT        NOT NULL REFERENCES profiles (id) ON DELETE CASCADE,
    role        TEXT        NOT NULL DEFAULT 'COACH',
    domain      TEXT        NOT NULL DEFAULT 'fitness',
    token_hash  BYTEA       NOT NULL UNIQUE,
    name        TEXT        NOT NULL,
    max_uses    SMALLINT    NOT NULL DEFAULT 1,
    expires_at  TIMESTAMPTZ NOT NULL,
    canceled_at TIMESTAMPTZ,
    renewed_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT invitations_role_check CHECK (role IN ('COACH', 'PEER')),
    CONSTRAINT invitations_name_check CHECK (length(trim(name)) BETWEEN 1 AND 100),
    CONSTRAINT invitations_max_uses_check CHECK (max_uses >= 1)
);

CREATE INDEX IF NOT EXISTS invitations_inviter_idx ON invitations (inviter_id, id);

COMMENT ON TABLE invitations IS 'A link one person makes to start a relationship with whoever accepts it';
COMMENT ON COLUMN invitations.inviter_id IS 'Who made the link';
COMMENT ON COLUMN invitations.role IS 'The role the inviter takes in the relationship';
COMMENT ON COLUMN invitations.domain IS 'The domain the relationship belongs to';
COMMENT ON COLUMN invitations.token_hash IS 'A hash of the link''s secret; the secret itself is never stored';
COMMENT ON COLUMN invitations.name IS 'The name the inviter wrote for the person it is for; only they see it';
COMMENT ON COLUMN invitations.max_uses IS 'How many people can answer the link';
COMMENT ON COLUMN invitations.expires_at IS 'When the link stops working';
COMMENT ON COLUMN invitations.canceled_at IS 'When the inviter withdrew it; NULL while it stands';
COMMENT ON COLUMN invitations.renewed_at IS 'When it last got a new secret; only answers since then count against it, and older ones stay as history';
COMMENT ON CONSTRAINT invitations_role_check ON invitations IS 'An inviter coaches or is a peer; a student is who accepts';
COMMENT ON CONSTRAINT invitations_name_check ON invitations IS 'Between 1 and 100 characters';
COMMENT ON CONSTRAINT invitations_max_uses_check ON invitations IS 'At least one person';
COMMENT ON INDEX invitations_inviter_idx IS 'One inviter''s links, newest first by id';

CREATE TABLE IF NOT EXISTS invitation_responses
(
    id            UUID        NOT NULL DEFAULT uuidv7() PRIMARY KEY,
    invitation_id UUID        NOT NULL REFERENCES invitations (id) ON DELETE CASCADE,
    user_id       TEXT REFERENCES profiles (id) ON DELETE SET NULL,
    response      TEXT        NOT NULL,
    at            TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT invitation_responses_response_check CHECK (response IN ('accepted', 'declined'))
);

CREATE UNIQUE INDEX IF NOT EXISTS invitation_responses_user_key ON invitation_responses (invitation_id, user_id);
CREATE INDEX IF NOT EXISTS invitation_responses_user_idx ON invitation_responses (user_id) WHERE user_id IS NOT NULL;

COMMENT ON TABLE invitation_responses IS 'Who answered a link, and how';
COMMENT ON COLUMN invitation_responses.invitation_id IS 'The link answered';
COMMENT ON COLUMN invitation_responses.user_id IS 'Who answered; NULL once that account is gone';
COMMENT ON COLUMN invitation_responses.response IS 'accepted or declined; a person can change their mind while the link is good';
COMMENT ON COLUMN invitation_responses.at IS 'When';
COMMENT ON CONSTRAINT invitation_responses_response_check ON invitation_responses IS 'The two answers';
COMMENT ON INDEX invitation_responses_user_key IS 'One answer per person per link';
COMMENT ON INDEX invitation_responses_user_idx IS 'The SET NULL when a responder''s profile is deleted';
