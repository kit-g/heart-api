-- A block and a new relationship between the same two people are ordered by a lock on the pair,
-- so whichever commits second sees the first. Lifting one row's block leaves a block another row
-- still stands on. A rewritten relationship gets an event even when its status stays the same.

CREATE OR REPLACE FUNCTION _lock_pair(_a TEXT, _b TEXT) RETURNS VOID
    LANGUAGE sql
AS
$$
SELECT pg_advisory_xact_lock(hashtextextended(least(_a, _b) || ' ' || greatest(_a, _b), 0))
$$;

COMMENT ON FUNCTION _lock_pair(TEXT, TEXT) IS
    'Holds the pair until the transaction ends, whichever way round they are named';

CREATE OR REPLACE FUNCTION _end_connections_on_block() RETURNS trigger
    LANGUAGE plpgsql
AS
$$
BEGIN
    -- the pair's lock first: a relationship being made now commits before this looks, or
    -- waits for the block and sees it
    PERFORM _lock_pair(NEW.blocker_id, NEW.blocked_id);
    UPDATE connections
    SET status = 'severed',
        status_by = NEW.blocker_id
    WHERE (initiator_id, target_id) IN ((NEW.blocker_id, NEW.blocked_id), (NEW.blocked_id, NEW.blocker_id))
      AND status IN ('active', 'paused', 'pending');
    RETURN NULL;
END
$$;

COMMENT ON FUNCTION _end_connections_on_block() IS
    'A block ends everything live between the two people, in every domain, so lifting it restores nothing without a new yes';

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
          AND lifted_at IS NULL
          AND NOT EXISTS (
            SELECT 1
            FROM connections c
            WHERE (c.initiator_id, c.target_id) IN ((NEW.status_by, _other), (_other, NEW.status_by))
              AND c.status = 'blocked'
              AND c.status_by = NEW.status_by
          );
    END IF;
    RETURN NEW;
END
$$;

COMMENT ON FUNCTION _sync_block_with_connection() IS
    'A connection moving to blocked sets a block on the pair; the last of the pair''s rows moving out of it lifts that block';

DROP TRIGGER IF EXISTS connections_log_status_update ON connections;
CREATE TRIGGER connections_log_status_update
    AFTER UPDATE OF status, accepted_at
    ON connections
    FOR EACH ROW
    WHEN (OLD.status IS DISTINCT FROM NEW.status OR OLD.accepted_at IS DISTINCT FROM NEW.accepted_at)
EXECUTE FUNCTION _log_connection_status();

COMMENT ON TRIGGER connections_log_status_update ON connections IS
    'Each later move, and a relationship started again over the same row';

COMMENT ON COLUMN invitations.created_at IS 'When the link was first made';
