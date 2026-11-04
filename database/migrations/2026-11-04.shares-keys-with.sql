-- Having had a relationship is having accepted one, whatever the row says now: a
-- severed peer row asked again goes back to pending, or on to declined, and the
-- history it left still needs its keys.

CREATE OR REPLACE FUNCTION _shares_keys_with(_reader TEXT, _owner TEXT) RETURNS BOOLEAN
    LANGUAGE sql
    STABLE
AS
$$
SELECT _reader = _owner OR (
    NOT _blocked_between(_reader, _owner)
    AND EXISTS (
        SELECT 1
        FROM connections
        WHERE (initiator_id, target_id) IN ((_reader, _owner), (_owner, _reader))
          AND accepted_at IS NOT NULL
    )
)
$$;

COMMENT ON FUNCTION _shares_keys_with(TEXT, TEXT) IS
    'Whether a reader may see an owner''s keys: yourself, or anyone you have a relationship with or had one, under no block. A thread outlives its connection, and a new device still has to ask for its keys';
