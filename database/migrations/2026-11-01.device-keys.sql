-- What end-to-end encryption needs of the server: each device's public keys, and
-- a queue of sealed items for each device. Nothing here can open anything.

DROP TABLE IF EXISTS device_queue;
DROP TABLE IF EXISTS one_time_keys;
DROP TABLE IF EXISTS key_claims;
DROP TABLE IF EXISTS crypto_devices;

CREATE TABLE IF NOT EXISTS crypto_devices
(
    id           UUID PRIMARY KEY,
    user_id      TEXT        NOT NULL REFERENCES profiles (id) ON DELETE CASCADE,
    identity_key TEXT        NOT NULL,
    signing_key  TEXT        NOT NULL,
    fallback_key TEXT        NOT NULL,
    signature    TEXT,
    vouched_by   UUID REFERENCES crypto_devices (id) ON DELETE SET NULL,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    removed_at   TIMESTAMPTZ,
    CONSTRAINT crypto_devices_keys_check CHECK (
        char_length(identity_key) <= 128 AND char_length(signing_key) <= 128 AND char_length(fallback_key) <= 128
    ),
    CONSTRAINT crypto_devices_signature_check CHECK (signature IS NULL OR char_length(signature) <= 256)
);

CREATE INDEX IF NOT EXISTS crypto_devices_user_idx ON crypto_devices (user_id);
CREATE INDEX IF NOT EXISTS crypto_devices_vouched_by_idx ON crypto_devices (vouched_by) WHERE vouched_by IS NOT NULL;

COMMENT ON TABLE crypto_devices IS 'A device''s public keys; apart from push tokens, which rotate where a key identity must not';
COMMENT ON COLUMN crypto_devices.id IS 'Chosen by the device';
COMMENT ON COLUMN crypto_devices.user_id IS 'Whose device';
COMMENT ON COLUMN crypto_devices.identity_key IS 'Public key that identifies the device';
COMMENT ON COLUMN crypto_devices.signing_key IS 'Public key the device signs with';
COMMENT ON COLUMN crypto_devices.fallback_key IS 'Public key answered once its single-use keys run out';
COMMENT ON COLUMN crypto_devices.signature IS 'A signature from another device of the owner; NULL if nobody vouched for this one';
COMMENT ON COLUMN crypto_devices.vouched_by IS 'The device that signed';
COMMENT ON COLUMN crypto_devices.created_at IS 'When it was published';
COMMENT ON COLUMN crypto_devices.removed_at IS 'When its owner removed it; NULL while in use';
COMMENT ON CONSTRAINT crypto_devices_keys_check ON crypto_devices IS 'Keys are about 43 characters; this is a guard';
COMMENT ON CONSTRAINT crypto_devices_signature_check ON crypto_devices IS 'A guard on what a signature can hold';
COMMENT ON INDEX crypto_devices_user_idx IS 'One person''s devices';
COMMENT ON INDEX crypto_devices_vouched_by_idx IS 'The SET NULL when a vouching device is deleted';

CREATE TABLE IF NOT EXISTS one_time_keys
(
    device_id UUID NOT NULL REFERENCES crypto_devices (id) ON DELETE CASCADE,
    key_id    TEXT NOT NULL,
    key       TEXT NOT NULL,
    PRIMARY KEY (device_id, key_id),
    CONSTRAINT one_time_keys_size_check CHECK (char_length(key_id) <= 64 AND char_length(key) <= 128)
);

COMMENT ON TABLE one_time_keys IS 'A device''s single-use public keys; handing one out deletes it, so none goes out twice';
COMMENT ON COLUMN one_time_keys.device_id IS 'Whose key';
COMMENT ON COLUMN one_time_keys.key_id IS 'The device''s name for it';
COMMENT ON COLUMN one_time_keys.key IS 'The public key';
COMMENT ON CONSTRAINT one_time_keys_size_check ON one_time_keys IS 'A guard on what a key can hold';

CREATE TABLE IF NOT EXISTS key_claims
(
    claimer_id   TEXT        NOT NULL REFERENCES profiles (id) ON DELETE CASCADE,
    owner_id     TEXT        NOT NULL REFERENCES profiles (id) ON DELETE CASCADE,
    window_start TIMESTAMPTZ NOT NULL DEFAULT now(),
    claims       INTEGER     NOT NULL DEFAULT 1,
    PRIMARY KEY (claimer_id, owner_id)
);

CREATE INDEX IF NOT EXISTS key_claims_owner_idx ON key_claims (owner_id);

COMMENT ON TABLE key_claims IS 'How many times one person took another''s single-use keys lately, so nobody can drain them';
COMMENT ON COLUMN key_claims.claimer_id IS 'Who took them';
COMMENT ON COLUMN key_claims.owner_id IS 'Whose they were';
COMMENT ON COLUMN key_claims.window_start IS 'When this hour''s count began';
COMMENT ON COLUMN key_claims.claims IS 'How many times since then';
COMMENT ON INDEX key_claims_owner_idx IS 'The cascade when an owner''s profile is deleted';

CREATE TABLE IF NOT EXISTS device_queue
(
    seq                 BIGSERIAL PRIMARY KEY,
    id                  UUID        NOT NULL UNIQUE,
    recipient_device_id UUID        NOT NULL REFERENCES crypto_devices (id) ON DELETE CASCADE,
    sender_device_id    UUID REFERENCES crypto_devices (id) ON DELETE SET NULL,
    kind                TEXT        NOT NULL,
    content             TEXT        NOT NULL,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT device_queue_kind_check CHECK (kind ~ '^[a-z][a-z0-9_]{0,31}$'),
    CONSTRAINT device_queue_content_check CHECK (char_length(content) BETWEEN 1 AND 1024)
);

CREATE INDEX IF NOT EXISTS device_queue_recipient_idx ON device_queue (recipient_device_id, seq);
CREATE INDEX IF NOT EXISTS device_queue_sender_idx ON device_queue (sender_device_id) WHERE sender_device_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS device_queue_created_idx ON device_queue (created_at);

COMMENT ON TABLE device_queue IS 'Sealed items waiting for one device, in the order sent; a confirmed one is gone';
COMMENT ON COLUMN device_queue.seq IS 'The order sent; order is firm for these, and two ids minted in one millisecond can tie';
COMMENT ON COLUMN device_queue.id IS 'Chosen by the sending device, so a retry cannot deliver twice';
COMMENT ON COLUMN device_queue.recipient_device_id IS 'The one device it is sealed for';
COMMENT ON COLUMN device_queue.sender_device_id IS 'The device that sent it; NULL once that device is deleted';
COMMENT ON COLUMN device_queue.kind IS 'What the item is, in the app''s words';
COMMENT ON COLUMN device_queue.content IS 'Ciphertext, which nothing on the server can read';
COMMENT ON COLUMN device_queue.created_at IS 'When it arrived; unconfirmed items go after 90 days';
COMMENT ON CONSTRAINT device_queue_kind_check ON device_queue IS 'A snake_case word of at most 32 characters';
COMMENT ON CONSTRAINT device_queue_content_check ON device_queue IS 'An item is under 1 KB';
COMMENT ON INDEX device_queue_recipient_idx IS 'What waits for a device, in order';
COMMENT ON INDEX device_queue_sender_idx IS 'The SET NULL when a sending device is deleted';
COMMENT ON INDEX device_queue_created_idx IS 'The daily cleanup';

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
          AND status IN ('active', 'paused', 'severed')
    )
)
$$;

COMMENT ON FUNCTION _shares_keys_with(TEXT, TEXT) IS
    'Whether a reader may see an owner''s keys: yourself, or anyone you have a relationship with or had one, under no block. A thread outlives its connection, and a new device still has to ask for its keys';

CREATE OR REPLACE FUNCTION _clean_up_device_queue() RETURNS VOID
    LANGUAGE sql
AS
$$
DELETE FROM device_queue
WHERE created_at < now() - INTERVAL '90 days'
$$;

COMMENT ON FUNCTION _clean_up_device_queue() IS 'Removes items left unconfirmed for 90 days';
