-- Whether a device of the account's holds one of its places, or asked to publish while
-- there was none and waits for one.

ALTER TABLE IF EXISTS crypto_devices
    DROP COLUMN IF EXISTS waiting,
    ADD COLUMN IF NOT EXISTS waiting BOOLEAN NOT NULL DEFAULT false;

COMMENT ON COLUMN crypto_devices.waiting IS
    'Asked to publish while the account had no place for it: nothing is sent to it until it has one';
