-- A sender's items by when they arrived, so counting the last minute's reads only
-- that minute. It still serves the SET NULL when a sender's profile is deleted.

DROP INDEX IF EXISTS thread_items_sender_idx;
CREATE INDEX IF NOT EXISTS thread_items_sender_idx ON thread_items (sender_id, created_at) WHERE sender_id IS NOT NULL;

COMMENT ON INDEX thread_items_sender_idx IS 'A sender''s items by arrival, and the SET NULL when a sender''s profile is deleted';
