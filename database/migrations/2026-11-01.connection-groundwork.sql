-- Groundwork for coaching (docs/2026-11-01.coaching.md): connections gain an id,
-- a history and an acceptance date; a block belongs to a pair across domains; a
-- student chooses what opens to a coach and can hide a workout; and one function
-- answers what a reader may see of an owner.

-- A pair holds one row per domain, whichever of them started it.
DELETE FROM connections a
USING connections b
WHERE a.domain = b.domain
  AND a.initiator_id = b.target_id
  AND a.target_id = b.initiator_id
  AND (a.created_at, a.initiator_id) < (b.created_at, b.initiator_id);

DROP INDEX IF EXISTS connections_pair_domain_key;
CREATE UNIQUE INDEX IF NOT EXISTS connections_pair_domain_key
    ON connections (least(initiator_id, target_id), greatest(initiator_id, target_id), domain);

ALTER TABLE IF EXISTS connections
    DROP COLUMN IF EXISTS id,
    DROP COLUMN IF EXISTS accepted_at,
    DROP COLUMN IF EXISTS shares,
    ADD COLUMN IF NOT EXISTS id UUID NOT NULL DEFAULT uuidv7() UNIQUE,
    ADD COLUMN IF NOT EXISTS accepted_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS shares TEXT[] NOT NULL DEFAULT '{}';

-- The best anyone can say of a live row older than this column.
UPDATE connections
SET accepted_at = created_at
WHERE status IN ('active', 'paused');

COMMENT ON COLUMN connections.id IS 'The relationship''s identity, the same from both sides';
COMMENT ON COLUMN connections.accepted_at IS 'When this relationship last became active from a request; NULL until then';
COMMENT ON COLUMN connections.shares IS
    'What the student chose to open to their coach beyond the default, such as history or goals';
COMMENT ON INDEX connections_pair_domain_key IS 'One row per pair and domain, in either direction';

DROP TABLE IF EXISTS connection_events;

CREATE TABLE IF NOT EXISTS connection_events
(
    id            UUID                 DEFAULT uuidv7() PRIMARY KEY,
    connection_id UUID        NOT NULL REFERENCES connections (id) ON DELETE CASCADE,
    status        TEXT        NOT NULL,
    actor_id      TEXT REFERENCES profiles (id) ON DELETE SET NULL,
    at            TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp()
);

CREATE INDEX IF NOT EXISTS connection_events_connection_idx ON connection_events (connection_id, id);
CREATE INDEX IF NOT EXISTS connection_events_actor_idx ON connection_events (actor_id) WHERE actor_id IS NOT NULL;

COMMENT ON TABLE connection_events IS 'Every status a connection has held, in order; append-only';
COMMENT ON COLUMN connection_events.connection_id IS 'The connection that moved';
COMMENT ON COLUMN connection_events.status IS 'The status it moved to';
COMMENT ON COLUMN connection_events.actor_id IS 'Who moved it; NULL once that account is gone, or when nobody recorded it';
COMMENT ON COLUMN connection_events.at IS 'When it moved';
COMMENT ON INDEX connection_events_connection_idx IS 'One connection''s history in order';
COMMENT ON INDEX connection_events_actor_idx IS 'The SET NULL when the actor''s profile is deleted';

INSERT INTO connection_events (connection_id, status, actor_id, at)
SELECT id, status, status_by, created_at
FROM connections;

DROP TABLE IF EXISTS blocks;

CREATE TABLE IF NOT EXISTS blocks
(
    id         UUID                 DEFAULT uuidv7() PRIMARY KEY,
    blocker_id TEXT        NOT NULL REFERENCES profiles (id) ON DELETE CASCADE,
    blocked_id TEXT        NOT NULL REFERENCES profiles (id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    lifted_at  TIMESTAMPTZ,
    CONSTRAINT blocks_no_self_check CHECK (blocker_id <> blocked_id)
);

CREATE UNIQUE INDEX IF NOT EXISTS blocks_live_key ON blocks (blocker_id, blocked_id) WHERE lifted_at IS NULL;
CREATE INDEX IF NOT EXISTS blocks_blocked_idx ON blocks (blocked_id);

COMMENT ON TABLE blocks IS 'Blocks between two people, across every domain; a lifted one stays as history';
COMMENT ON COLUMN blocks.blocker_id IS 'Who blocked';
COMMENT ON COLUMN blocks.blocked_id IS 'Who is blocked';
COMMENT ON COLUMN blocks.created_at IS 'When the block was set';
COMMENT ON COLUMN blocks.lifted_at IS 'When the blocker lifted it; NULL while it stands';
COMMENT ON CONSTRAINT blocks_no_self_check ON blocks IS 'Nobody blocks themselves';
COMMENT ON INDEX blocks_live_key IS 'At most one standing block per direction';
COMMENT ON INDEX blocks_blocked_idx IS 'The cascade when a blocked profile is deleted, and blocks against a person';

INSERT INTO blocks (blocker_id, blocked_id)
SELECT status_by, CASE WHEN status_by = initiator_id THEN target_id ELSE initiator_id END
FROM connections
WHERE status = 'blocked'
  AND status_by IS NOT NULL
ON CONFLICT DO NOTHING;

CREATE OR REPLACE FUNCTION _stamp_connection_accepted() RETURNS trigger
    LANGUAGE plpgsql
AS
$$
BEGIN
    IF NEW.status = 'active' AND NEW.accepted_at IS NULL THEN
        NEW.accepted_at := now();
    END IF;
    RETURN NEW;
END
$$;

COMMENT ON FUNCTION _stamp_connection_accepted() IS
    'Dates a connection''s acceptance the first time it is active without one';

DROP TRIGGER IF EXISTS connections_stamp_accepted ON connections;
CREATE TRIGGER connections_stamp_accepted
    BEFORE INSERT OR UPDATE OF status
    ON connections
    FOR EACH ROW
EXECUTE FUNCTION _stamp_connection_accepted();

COMMENT ON TRIGGER connections_stamp_accepted ON connections IS 'Keeps accepted_at set on every active row';

CREATE OR REPLACE FUNCTION _log_connection_status() RETURNS trigger
    LANGUAGE plpgsql
AS
$$
BEGIN
    INSERT INTO connection_events (connection_id, status, actor_id)
    VALUES (NEW.id, NEW.status, NEW.status_by);
    RETURN NEW;
END
$$;

COMMENT ON FUNCTION _log_connection_status() IS 'Appends a connection''s new status to its history';

DROP TRIGGER IF EXISTS connections_log_status_insert ON connections;
CREATE TRIGGER connections_log_status_insert
    AFTER INSERT
    ON connections
    FOR EACH ROW
EXECUTE FUNCTION _log_connection_status();

DROP TRIGGER IF EXISTS connections_log_status_update ON connections;
CREATE TRIGGER connections_log_status_update
    AFTER UPDATE OF status
    ON connections
    FOR EACH ROW
    WHEN (OLD.status IS DISTINCT FROM NEW.status)
EXECUTE FUNCTION _log_connection_status();

COMMENT ON TRIGGER connections_log_status_insert ON connections IS 'A new connection''s first status';
COMMENT ON TRIGGER connections_log_status_update ON connections IS 'Each later move';

CREATE OR REPLACE FUNCTION _sync_block_with_connection() RETURNS trigger
    LANGUAGE plpgsql
AS
$$
DECLARE
    _other TEXT := CASE WHEN NEW.status_by = NEW.initiator_id THEN NEW.target_id ELSE NEW.initiator_id END;
BEGIN
    IF NEW.status = 'blocked' THEN
        INSERT INTO blocks (blocker_id, blocked_id)
        VALUES (NEW.status_by, _other)
        ON CONFLICT DO NOTHING;
    ELSE
        UPDATE blocks
        SET lifted_at = now()
        WHERE blocker_id = NEW.status_by
          AND blocked_id = _other
          AND lifted_at IS NULL;
    END IF;
    RETURN NEW;
END
$$;

COMMENT ON FUNCTION _sync_block_with_connection() IS
    'A connection moving to blocked sets a block on the pair; moving out of it lifts that block';

DROP TRIGGER IF EXISTS connections_sync_block ON connections;
CREATE TRIGGER connections_sync_block
    AFTER UPDATE OF status
    ON connections
    FOR EACH ROW
    WHEN (OLD.status IS DISTINCT FROM NEW.status AND 'blocked' IN (OLD.status, NEW.status))
EXECUTE FUNCTION _sync_block_with_connection();

COMMENT ON TRIGGER connections_sync_block ON connections IS 'Keeps blocks in step with a blocked status';

ALTER TABLE IF EXISTS workouts
    DROP COLUMN IF EXISTS hidden_at,
    ADD COLUMN IF NOT EXISTS hidden_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS workouts_hidden_idx ON workouts (user_id, hidden_at) WHERE hidden_at IS NOT NULL;

COMMENT ON COLUMN workouts.hidden_at IS
    'When the owner hid this workout from their connections; NULL while it is visible to them';
COMMENT ON INDEX workouts_hidden_idx IS 'One account''s hidden workouts';

DROP TABLE IF EXISTS entitlements;

CREATE TABLE IF NOT EXISTS entitlements
(
    user_id     TEXT        NOT NULL REFERENCES profiles (id) ON DELETE CASCADE,
    entitlement TEXT        NOT NULL,
    granted_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, entitlement),
    CONSTRAINT entitlements_name_check CHECK (entitlement ~ '^[a-z][a-z0-9_]{0,31}$')
);

COMMENT ON TABLE entitlements IS 'What an account has been granted beyond the free app';
COMMENT ON COLUMN entitlements.user_id IS 'The account';
COMMENT ON COLUMN entitlements.entitlement IS 'What it was granted, such as coach';
COMMENT ON COLUMN entitlements.granted_at IS 'When';
COMMENT ON CONSTRAINT entitlements_name_check ON entitlements IS 'A snake_case name of at most 32 characters';

DROP FUNCTION IF EXISTS _relation(TEXT, TEXT);
DROP FUNCTION IF EXISTS _readable_at(relation, TIMESTAMPTZ, TIMESTAMPTZ);
DROP TYPE IF EXISTS relation;

CREATE TYPE relation AS
(
    scope  TEXT,
    active BOOLEAN,
    since  TIMESTAMPTZ,
    shares TEXT[],
    pauses TSTZMULTIRANGE
);

COMMENT ON TYPE relation IS
    'What a reader may see of an owner: scope is self, coach, peer or NULL for nothing; active is false while paused; since, shares and pauses limit a coach';

CREATE OR REPLACE FUNCTION _blocked_between(_a TEXT, _b TEXT) RETURNS BOOLEAN
    LANGUAGE sql
    STABLE
AS
$$
SELECT EXISTS (
    SELECT 1
    FROM blocks
    WHERE (blocker_id, blocked_id) IN ((_a, _b), (_b, _a))
      AND lifted_at IS NULL
)
$$;

COMMENT ON FUNCTION _blocked_between(TEXT, TEXT) IS 'Whether a block stands between two people, in either direction';

-- Workouts carry no domain, so a pair's rows fold into one answer per direction.
-- A coach's view wins over a peer's, and a pause on any coach row stops it.
CREATE OR REPLACE FUNCTION _relation(_reader TEXT, _owner TEXT) RETURNS relation
    LANGUAGE plpgsql
    STABLE
AS
$$
DECLARE
    _result relation;
BEGIN
    IF _reader = _owner THEN
        RETURN ROW ('self', TRUE, NULL, '{}', NULL)::relation;
    END IF;

    IF _blocked_between(_reader, _owner) THEN
        RETURN ROW (NULL, FALSE, NULL, '{}', NULL)::relation;
    END IF;

    SELECT 'coach',
           bool_and(status = 'active'),
           min(accepted_at),
           coalesce(
               (
                   SELECT array_agg(DISTINCT share)
                   FROM connections c, unnest(c.shares) AS share
                   WHERE c.status = 'active'
                     AND (
                       (c.initiator_id = _reader AND c.target_id = _owner AND c.initiator_role = 'COACH')
                       OR (c.initiator_id = _owner AND c.target_id = _reader AND c.target_role = 'COACH')
                     )
               ),
               '{}'
           ),
           (
               SELECT range_agg(tstzrange(at, next_at))
               FROM (
                   SELECT e.status, e.at, lead(e.at) OVER (PARTITION BY e.connection_id ORDER BY e.id) AS next_at
                   FROM connection_events e
                   JOIN connections c ON c.id = e.connection_id
                   WHERE (c.initiator_id = _reader AND c.target_id = _owner AND c.initiator_role = 'COACH')
                      OR (c.initiator_id = _owner AND c.target_id = _reader AND c.target_role = 'COACH')
               ) moves
               WHERE moves.status = 'paused'
           )
    INTO _result.scope, _result.active, _result.since, _result.shares, _result.pauses
    FROM connections
    WHERE status IN ('active', 'paused')
      AND (
        (initiator_id = _reader AND target_id = _owner AND initiator_role = 'COACH')
        OR (initiator_id = _owner AND target_id = _reader AND target_role = 'COACH')
      )
    HAVING count(*) > 0;

    IF _result.scope IS NOT NULL THEN
        RETURN _result;
    END IF;

    IF EXISTS (
        SELECT 1
        FROM connections
        WHERE status = 'active'
          AND (
            (initiator_id = _reader AND target_id = _owner AND initiator_role = 'PEER')
            OR (initiator_id = _owner AND target_id = _reader AND target_role = 'PEER')
          )
    ) THEN
        RETURN ROW ('peer', TRUE, NULL, '{}', NULL)::relation;
    END IF;

    RETURN ROW (NULL, FALSE, NULL, '{}', NULL)::relation;
END
$$;

COMMENT ON FUNCTION _relation(TEXT, TEXT) IS
    'What a reader may see of an owner, folded from every row between them; a standing block answers nothing';

CREATE OR REPLACE FUNCTION _readable_at(_relation relation, _at TIMESTAMPTZ, _hidden_at TIMESTAMPTZ) RETURNS BOOLEAN
    LANGUAGE sql
    IMMUTABLE
AS
$$
SELECT CASE (_relation).scope
    WHEN 'self' THEN TRUE
    WHEN 'peer' THEN _hidden_at IS NULL
    WHEN 'coach' THEN _hidden_at IS NULL
        AND (_at >= (_relation).since OR 'history' = ANY ((_relation).shares))
        AND NOT coalesce((_relation).pauses @> _at, FALSE)
    ELSE FALSE
END
$$;

COMMENT ON FUNCTION _readable_at(relation, TIMESTAMPTZ, TIMESTAMPTZ) IS
    'Whether something dated _at, and hidden at _hidden_at if at all, is readable under a relation';
