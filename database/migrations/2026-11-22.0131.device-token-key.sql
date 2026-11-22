-- A push token is its own key: it is unique already, and nothing refers to a row
-- by anything else.

-- Every registration and push reads this table; waiting behind a long transaction
-- would hold all of them, so the change gives up instead and is run again.
SET LOCAL lock_timeout = '5s';

ALTER TABLE IF EXISTS device_tokens
    DROP CONSTRAINT IF EXISTS device_tokens_pkey,
    DROP CONSTRAINT IF EXISTS device_tokens_token_key,
    DROP COLUMN IF EXISTS id,
    ADD CONSTRAINT device_tokens_pkey PRIMARY KEY (token);

COMMENT ON COLUMN device_tokens.token IS 'FCM registration token, the row''s key; it rotates, and a replaced one stays until it is rejected or expires';
COMMENT ON CONSTRAINT device_tokens_pkey ON device_tokens IS 'One row per token';
