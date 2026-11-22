-- A push token is its own key: it is unique already, and nothing refers to a row
-- by anything else.

ALTER TABLE IF EXISTS device_tokens
    DROP CONSTRAINT IF EXISTS device_tokens_pkey,
    DROP CONSTRAINT IF EXISTS device_tokens_token_key,
    DROP COLUMN IF EXISTS id,
    ADD CONSTRAINT device_tokens_pkey PRIMARY KEY (token);

COMMENT ON COLUMN device_tokens.token IS 'FCM registration token, the row''s key; one per app install, and it rotates';
