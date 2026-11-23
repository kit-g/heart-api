-- A client changing a program their coach sent is a reason of its own. A summary
-- worked out before this column existed doesn't know of one, so all are marked.

ALTER TABLE IF EXISTS client_summaries
    DROP COLUMN IF EXISTS changed_at,
    ADD COLUMN IF NOT EXISTS changed_at TIMESTAMPTZ;

COMMENT ON COLUMN client_summaries.changed_at IS
    'When they last changed a program the coach sent; NULL while the coach can read no such change';

-- A ladder's step up is written by the person's device as edits: the rule moves to
-- the next exercise, and so does that exercise's place in each session.
CREATE OR REPLACE FUNCTION _change_is_advance(_before JSONB, _after JSONB, _from UUID, _to UUID) RETURNS BOOLEAN
    LANGUAGE sql
    IMMUTABLE
AS
$$
WITH
_session AS (
    SELECT
        ARRAY(
            SELECT e -> 'exercise' ->> 'id'
            FROM jsonb_array_elements(_before -> 'exercises') WITH ORDINALITY t(e, n)
            ORDER BY n
        ) AS was,
        ARRAY(
            SELECT e -> 'exercise' ->> 'id'
            FROM jsonb_array_elements(_after -> 'exercises') WITH ORDINALITY t(e, n)
            ORDER BY n
        ) AS became
    WHERE jsonb_typeof(_before -> 'exercises') = 'array'
      AND jsonb_typeof(_after -> 'exercises') = 'array'
),
_rules AS (
    SELECT jsonb_object_agg(CASE WHEN key = _from::text THEN _to::text ELSE key END, value) AS moved
    FROM jsonb_each(CASE WHEN jsonb_typeof(_before -> 'rules') = 'object' THEN _before -> 'rules' ELSE '{}' END)
)
SELECT coalesce(
    (
        SELECT _from::text = ANY (was)
            AND array_replace(was, _from::text, _to::text) = became
            AND _before - 'exercises' - 'folder' - 'assignedBy' = _after - 'exercises' - 'folder' - 'assignedBy'
        FROM _session
    )
    OR (
        SELECT (_before -> 'rules') ? _from::text
            AND moved = _after -> 'rules'
            AND _before - 'rules' - 'revision' - 'sessionRevisions' = _after - 'rules' - 'revision' - 'sessionRevisions'
        FROM _rules
    ),
    FALSE
)
$$;

COMMENT ON FUNCTION _change_is_advance(JSONB, JSONB, UUID, UUID) IS
    'Whether two snapshots of a session or a program differ only as a ladder''s step from one exercise to the next makes them';

UPDATE client_summaries
SET dirty = true,
    generation = generation + 1;
