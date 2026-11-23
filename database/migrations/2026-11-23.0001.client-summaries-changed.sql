-- A client changing a program their coach sent is a reason of its own. A summary
-- worked out before this column existed doesn't know of one, so all are marked.

ALTER TABLE IF EXISTS client_summaries
    DROP COLUMN IF EXISTS changed_at,
    ADD COLUMN IF NOT EXISTS changed_at TIMESTAMPTZ;

COMMENT ON COLUMN client_summaries.changed_at IS
    'When they last changed a program the coach sent; NULL if they never have';

UPDATE client_summaries
SET dirty = true,
    generation = generation + 1;
