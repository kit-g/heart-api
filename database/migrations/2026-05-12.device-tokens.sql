DROP TABLE IF EXISTS device_tokens;
CREATE TABLE IF NOT EXISTS device_tokens
(
    id           UUID        NOT NULL PRIMARY KEY DEFAULT uuidv7(),
    profile_id   TEXT        NOT NULL REFERENCES profiles ON DELETE CASCADE,
    platform     TEXT        NOT NULL,
    token        TEXT        NOT NULL UNIQUE,
    locale       TEXT        NOT NULL             DEFAULT 'en',
    settings     JSONB       NOT NULL             DEFAULT '{}'::jsonb,
    created_at   TIMESTAMPTZ NOT NULL             DEFAULT now(),
    last_seen_at TIMESTAMPTZ NOT NULL             DEFAULT now(),
    CONSTRAINT device_tokens_platform_check CHECK (platform IN ('ios', 'android', 'web'))
);

CREATE INDEX IF NOT EXISTS device_tokens_profile_idx ON device_tokens (profile_id);

COMMENT ON TABLE device_tokens IS 'FCM tokens registered per device for push notifications';
COMMENT ON COLUMN device_tokens.profile_id IS 'Owner of the device';
COMMENT ON COLUMN device_tokens.platform IS 'Device platform (ios, android, web)';
COMMENT ON COLUMN device_tokens.token IS 'FCM registration token; unique across the table';
COMMENT ON COLUMN device_tokens.locale IS 'Recipient locale (BCP-47 with underscore, e.g. en, en_CA, ru). Set from the Accept-Language header at registration. Drives notification copy rendering server-side.';
COMMENT ON COLUMN device_tokens.settings IS 'Client-reported push settings; freeform JSON (e.g. {"authorized":true,"alert":"enabled","badge":"enabled","sound":"enabled","banner":"enabled"}). Shape mirrors what the device platform exposes (iOS UNNotificationSettings, Android NotificationManagerCompat, etc.).';
COMMENT ON COLUMN device_tokens.last_seen_at IS 'Updated on every login/refresh to track stale tokens';
