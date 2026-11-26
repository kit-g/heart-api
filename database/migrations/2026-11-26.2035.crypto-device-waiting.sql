-- A device that asked to publish while the account was full is still known: it holds no
-- place and nothing is sent to it, but it signs removals, and its day counts from when it
-- first asked. Without it, a new phone on a full account could never remove a stolen one.

ALTER TABLE IF EXISTS crypto_devices
    DROP COLUMN IF EXISTS waiting,
    ADD COLUMN IF NOT EXISTS waiting BOOLEAN NOT NULL DEFAULT false;

COMMENT ON COLUMN crypto_devices.waiting IS
    'Asked to publish while the account had no place for it: nothing is sent to it until it has one';
