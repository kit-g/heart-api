-- Threads between two people, notes a coach keeps, and reports. Message and note
-- content is ciphertext the server cannot read. A report's words are sealed to a
-- key the server doesn't hold.

DROP TABLE IF EXISTS reports;
DROP TABLE IF EXISTS coach_notes;
DROP TABLE IF EXISTS thread_reads;
DROP TABLE IF EXISTS thread_items;
DROP TABLE IF EXISTS threads;

CREATE TABLE IF NOT EXISTS threads
(
    id            UUID                 DEFAULT uuidv7() PRIMARY KEY,
    connection_id UUID UNIQUE REFERENCES connections (id) ON DELETE SET NULL,
    person_a      TEXT REFERENCES profiles (id) ON DELETE SET NULL,
    person_b      TEXT REFERENCES profiles (id) ON DELETE SET NULL,
    cleared_at    TIMESTAMPTZ,
    cleared_by    TEXT REFERENCES profiles (id) ON DELETE SET NULL,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS threads_person_a_idx ON threads (person_a) WHERE person_a IS NOT NULL;
CREATE INDEX IF NOT EXISTS threads_person_b_idx ON threads (person_b) WHERE person_b IS NOT NULL;
CREATE INDEX IF NOT EXISTS threads_cleared_by_idx ON threads (cleared_by) WHERE cleared_by IS NOT NULL;

COMMENT ON TABLE threads IS 'One conversation per connection; it outlives the connection and either account';
COMMENT ON COLUMN threads.connection_id IS 'The connection it belongs to; NULL once that is gone';
COMMENT ON COLUMN threads.person_a IS 'One of the two people; NULL once that account is gone';
COMMENT ON COLUMN threads.person_b IS 'The other';
COMMENT ON COLUMN threads.cleared_at IS 'When either person last deleted the conversation for both; NULL if nobody has';
COMMENT ON COLUMN threads.cleared_by IS 'Who did';
COMMENT ON COLUMN threads.created_at IS 'When it was opened';
COMMENT ON INDEX threads_person_a_idx IS 'One person''s threads';
COMMENT ON INDEX threads_person_b_idx IS 'One person''s threads';
COMMENT ON INDEX threads_cleared_by_idx IS 'The SET NULL when that profile is deleted';

CREATE TABLE IF NOT EXISTS thread_items
(
    id           UUID PRIMARY KEY,
    thread_id    UUID        NOT NULL REFERENCES threads (id) ON DELETE CASCADE,
    sender_id    TEXT REFERENCES profiles (id) ON DELETE SET NULL,
    kind         TEXT        NOT NULL DEFAULT 'message',
    subject_type TEXT,
    subject_id   TEXT,
    content      TEXT        NOT NULL,
    commitment   TEXT        NOT NULL,
    tag          TEXT        NOT NULL,
    tag_key      TEXT        NOT NULL,
    at           TIMESTAMPTZ NOT NULL,
    xid          XID8        NOT NULL DEFAULT pg_current_xact_id(),
    created_at   TIMESTAMPTZ NOT NULL,
    CONSTRAINT thread_items_kind_check CHECK (kind ~ '^[a-z][a-z0-9_]{0,31}$'),
    CONSTRAINT thread_items_subject_check CHECK (
        (subject_type IS NULL) = (subject_id IS NULL)
            AND (subject_type IS NULL OR subject_type ~ '^[a-z][a-z0-9_]{0,31}$')
            AND (subject_id IS NULL OR char_length(subject_id) <= 64)
    ),
    CONSTRAINT thread_items_content_check CHECK (char_length(content) BETWEEN 1 AND 16384)
);

CREATE INDEX IF NOT EXISTS thread_items_order_idx ON thread_items (thread_id, xid, id);
CREATE INDEX IF NOT EXISTS thread_items_subject_idx
    ON thread_items (thread_id, subject_type, subject_id, xid, id) WHERE subject_type IS NOT NULL;
CREATE INDEX IF NOT EXISTS thread_items_sender_idx ON thread_items (sender_id) WHERE sender_id IS NOT NULL;

COMMENT ON TABLE thread_items IS 'What was said in a thread, stored once; every device of both people reads this copy';
COMMENT ON COLUMN thread_items.id IS 'Chosen by the sending device, so a retry cannot post twice';
COMMENT ON COLUMN thread_items.thread_id IS 'The thread';
COMMENT ON COLUMN thread_items.sender_id IS 'Who sent it; NULL once that account is gone';
COMMENT ON COLUMN thread_items.kind IS 'What it is, such as message';
COMMENT ON COLUMN thread_items.subject_type IS 'What it is about, such as exercise_set; NULL for nothing in particular';
COMMENT ON COLUMN thread_items.subject_id IS 'Which one; a link and not a reference, so a deleted set leaves the message standing';
COMMENT ON COLUMN thread_items.content IS 'Ciphertext, which nothing on the server can read';
COMMENT ON COLUMN thread_items.commitment IS 'The sender''s 32-byte commitment to the words, base64';
COMMENT ON COLUMN thread_items.tag IS 'The server''s tag over the commitment, the two people and the time, base64';
COMMENT ON COLUMN thread_items.tag_key IS 'Which of the server''s keys made the tag';
COMMENT ON COLUMN thread_items.at IS 'When the device says it was written';
COMMENT ON COLUMN thread_items.xid IS 'The transaction that stored it; the order reads go by, since a device''s clock and ids can be offline for days';
COMMENT ON COLUMN thread_items.created_at IS 'When it arrived, as the tag states it';
COMMENT ON CONSTRAINT thread_items_kind_check ON thread_items IS 'A snake_case word of at most 32 characters';
COMMENT ON CONSTRAINT thread_items_subject_check ON thread_items IS 'A type and an id together, or neither';
COMMENT ON CONSTRAINT thread_items_content_check ON thread_items IS 'At most 16 KB';
COMMENT ON INDEX thread_items_order_idx IS 'A thread in stored order';
COMMENT ON INDEX thread_items_subject_idx IS 'What was said about one thing';
COMMENT ON INDEX thread_items_sender_idx IS 'The SET NULL when a sender''s profile is deleted';

CREATE TABLE IF NOT EXISTS thread_reads
(
    thread_id UUID NOT NULL REFERENCES threads (id) ON DELETE CASCADE,
    user_id   TEXT NOT NULL REFERENCES profiles (id) ON DELETE CASCADE,
    read_xid  XID8 NOT NULL,
    read_id   UUID NOT NULL,
    PRIMARY KEY (thread_id, user_id)
);

CREATE INDEX IF NOT EXISTS thread_reads_user_idx ON thread_reads (user_id);

COMMENT ON TABLE thread_reads IS 'How far each person has read a thread';
COMMENT ON COLUMN thread_reads.thread_id IS 'The thread';
COMMENT ON COLUMN thread_reads.user_id IS 'The reader';
COMMENT ON COLUMN thread_reads.read_xid IS 'The stored order of the last item they read';
COMMENT ON COLUMN thread_reads.read_id IS 'Its id';
COMMENT ON INDEX thread_reads_user_idx IS 'The cascade when a reader''s profile is deleted';

CREATE OR REPLACE FUNCTION _drop_thread_with_nobody() RETURNS trigger
    LANGUAGE plpgsql
AS
$$
BEGIN
    DELETE FROM threads WHERE id = NEW.id;
    RETURN NULL;
END
$$;

COMMENT ON FUNCTION _drop_thread_with_nobody() IS 'A thread goes when neither person is left to read it';

DROP TRIGGER IF EXISTS threads_drop_with_nobody ON threads;
CREATE TRIGGER threads_drop_with_nobody
    AFTER UPDATE OF person_a, person_b
    ON threads
    FOR EACH ROW
    WHEN (NEW.person_a IS NULL AND NEW.person_b IS NULL)
EXECUTE FUNCTION _drop_thread_with_nobody();

COMMENT ON TRIGGER threads_drop_with_nobody ON threads IS 'Runs as each account''s deletion clears its side';

CREATE TABLE IF NOT EXISTS coach_notes
(
    id            UUID PRIMARY KEY,
    coach_id      TEXT        NOT NULL REFERENCES profiles (id) ON DELETE CASCADE,
    connection_id UUID REFERENCES connections (id) ON DELETE SET NULL,
    content       TEXT        NOT NULL,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT coach_notes_content_check CHECK (char_length(content) BETWEEN 1 AND 16384)
);

CREATE INDEX IF NOT EXISTS coach_notes_coach_idx ON coach_notes (coach_id, id);
CREATE INDEX IF NOT EXISTS coach_notes_connection_idx ON coach_notes (connection_id) WHERE connection_id IS NOT NULL;

COMMENT ON TABLE coach_notes IS 'A coach''s own notes on a client, as ciphertext only that coach''s devices can open';
COMMENT ON COLUMN coach_notes.id IS 'Chosen by the device';
COMMENT ON COLUMN coach_notes.coach_id IS 'Whose notes';
COMMENT ON COLUMN coach_notes.connection_id IS 'The client they are about; NULL once that connection is gone, and the note stays';
COMMENT ON COLUMN coach_notes.content IS 'Ciphertext';
COMMENT ON COLUMN coach_notes.created_at IS 'When it was written';
COMMENT ON COLUMN coach_notes.updated_at IS 'When it last changed';
COMMENT ON CONSTRAINT coach_notes_content_check ON coach_notes IS 'At most 16 KB';
COMMENT ON INDEX coach_notes_coach_idx IS 'One coach''s notes';
COMMENT ON INDEX coach_notes_connection_idx IS 'The SET NULL when a connection is deleted';

-- Plain ids and no foreign keys: a report outlives both people, until its deadline.
CREATE TABLE IF NOT EXISTS reports
(
    id            UUID                 DEFAULT uuidv7() PRIMARY KEY,
    reporter_id   TEXT        NOT NULL,
    reported_id   TEXT        NOT NULL,
    connection_id UUID,
    reason        TEXT        NOT NULL,
    sealed        TEXT        NOT NULL,
    verified      BOOLEAN     NOT NULL,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    closed_at     TIMESTAMPTZ,
    CONSTRAINT reports_reason_check CHECK (reason ~ '^[a-z][a-z0-9_]{0,31}$')
);

CREATE INDEX IF NOT EXISTS reports_open_idx ON reports (created_at) WHERE closed_at IS NULL;
CREATE INDEX IF NOT EXISTS reports_closed_idx ON reports (closed_at) WHERE closed_at IS NOT NULL;

COMMENT ON TABLE reports IS 'What someone reported about another person; the words are sealed and deleted by deadline';
COMMENT ON COLUMN reports.reporter_id IS 'Who reported';
COMMENT ON COLUMN reports.reported_id IS 'Who about';
COMMENT ON COLUMN reports.connection_id IS 'The connection, if there was one';
COMMENT ON COLUMN reports.reason IS 'A one-tap reason in the app''s words';
COMMENT ON COLUMN reports.sealed IS 'The words sent with the report, sealed to a key the server does not hold';
COMMENT ON COLUMN reports.verified IS 'Whether every message checked out as sent by who the report says';
COMMENT ON COLUMN reports.created_at IS 'When it was filed';
COMMENT ON COLUMN reports.closed_at IS 'When it was dealt with; NULL while open';
COMMENT ON CONSTRAINT reports_reason_check ON reports IS 'A snake_case word of at most 32 characters';
COMMENT ON INDEX reports_open_idx IS 'What needs reading, and the cleanup of what was never closed';
COMMENT ON INDEX reports_closed_idx IS 'The cleanup of what was closed';

CREATE OR REPLACE FUNCTION _clean_up_reports() RETURNS VOID
    LANGUAGE sql
AS
$$
DELETE FROM reports
WHERE closed_at < now() - INTERVAL '90 days'
   OR (closed_at IS NULL AND created_at < now() - INTERVAL '1 year')
$$;

COMMENT ON FUNCTION _clean_up_reports() IS 'Removes reports 90 days after closing, and any left open for a year';
