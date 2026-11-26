-- Which of a client's copies they changed, each with its latest change by the rule
-- the changed reason keeps. A summary worked out before this column existed holds
-- none, so all are marked.

ALTER TABLE IF EXISTS client_summaries
    DROP COLUMN IF EXISTS changed_programs,
    ADD COLUMN IF NOT EXISTS changed_programs JSONB NOT NULL DEFAULT '{}'::jsonb;

COMMENT ON COLUMN client_summaries.changed_programs IS
    'Program id to when they last changed that copy, by the rule changed_at keeps; changed_at is the latest of these';

UPDATE client_summaries
SET dirty = true,
    generation = generation + 1;
