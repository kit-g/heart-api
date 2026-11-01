-- Push settings: what a person changed about a topic, and what waits for their
-- evening. A topic's defaults are not stored, so a new topic needs no migration.

DROP TABLE IF EXISTS push_preferences;

CREATE TABLE IF NOT EXISTS push_preferences
(
    id            UUID                 DEFAULT uuidv7() PRIMARY KEY,
    user_id       TEXT        NOT NULL REFERENCES profiles (id) ON DELETE CASCADE,
    topic         TEXT        NOT NULL,
    connection_id UUID REFERENCES connections (id) ON DELETE CASCADE,
    delivery      TEXT        NOT NULL,
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT push_preferences_topic_check CHECK (topic ~ '^[a-z][a-z0-9_.]{0,63}$'),
    CONSTRAINT push_preferences_delivery_check CHECK (delivery ~ '^[a-z][a-z0-9_]{0,31}$')
);

CREATE UNIQUE INDEX IF NOT EXISTS push_preferences_topic_key
    ON push_preferences (user_id, topic) WHERE connection_id IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS push_preferences_person_key
    ON push_preferences (user_id, topic, connection_id) WHERE connection_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS push_preferences_connection_idx
    ON push_preferences (connection_id) WHERE connection_id IS NOT NULL;

COMMENT ON TABLE push_preferences IS 'What a person changed about a push topic; a topic nobody changed has no row';
COMMENT ON COLUMN push_preferences.user_id IS 'Whose preference';
COMMENT ON COLUMN push_preferences.topic IS 'The push topic, such as coaching.message';
COMMENT ON COLUMN push_preferences.connection_id IS 'The one relationship this applies to; NULL for the whole topic';
COMMENT ON COLUMN push_preferences.delivery IS 'How the topic reaches them, such as instant, daily or off';
COMMENT ON COLUMN push_preferences.updated_at IS 'When they said so';
COMMENT ON CONSTRAINT push_preferences_topic_check ON push_preferences IS 'A dotted lowercase key of at most 64 characters';
COMMENT ON CONSTRAINT push_preferences_delivery_check ON push_preferences IS 'A snake_case word of at most 32 characters';
COMMENT ON INDEX push_preferences_topic_key IS 'One answer per person and topic';
COMMENT ON INDEX push_preferences_person_key IS 'One answer per person, topic and relationship';
COMMENT ON INDEX push_preferences_connection_idx IS 'The cascade when a connection is deleted';

DROP TABLE IF EXISTS push_digests;

CREATE TABLE IF NOT EXISTS push_digests
(
    user_id    TEXT        NOT NULL REFERENCES profiles (id) ON DELETE CASCADE,
    topic      TEXT        NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, topic)
);

COMMENT ON TABLE push_digests IS 'A daily push owed to a person; one per person and topic, however much happened';
COMMENT ON COLUMN push_digests.user_id IS 'Who it is owed to';
COMMENT ON COLUMN push_digests.topic IS 'The push topic';
COMMENT ON COLUMN push_digests.created_at IS 'When the first thing it covers happened';

ALTER TABLE IF EXISTS device_tokens
    DROP COLUMN IF EXISTS utc_offset_minutes,
    ADD COLUMN IF NOT EXISTS utc_offset_minutes SMALLINT,
    DROP CONSTRAINT IF EXISTS device_tokens_utc_offset_check,
    ADD CONSTRAINT device_tokens_utc_offset_check
        CHECK (utc_offset_minutes IS NULL OR utc_offset_minutes BETWEEN -720 AND 840);

COMMENT ON COLUMN device_tokens.utc_offset_minutes IS 'The device''s offset from UTC when it last registered; NULL if it never said';
COMMENT ON CONSTRAINT device_tokens_utc_offset_check ON device_tokens IS 'From UTC-12 to UTC+14';

CREATE OR REPLACE FUNCTION _clean_up_device_tokens() RETURNS VOID
    LANGUAGE sql
AS
$$
DELETE FROM device_tokens
WHERE last_seen_at < now() - INTERVAL '270 days'
$$;

COMMENT ON FUNCTION _clean_up_device_tokens() IS
    'Removes tokens not seen for 270 days, the point at which Firebase treats a token as expired';
