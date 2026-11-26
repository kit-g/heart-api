-- When a device last showed it's in use, so a device nobody has heard from in a long while
-- stops holding one of the account's places: an account whose devices are all wiped or lost
-- can add a new one, which then removes them.

ALTER TABLE IF EXISTS crypto_devices
    DROP COLUMN IF EXISTS seen_at,
    ADD COLUMN IF NOT EXISTS seen_at TIMESTAMPTZ NOT NULL DEFAULT now();

COMMENT ON COLUMN crypto_devices.seen_at IS
    'When the device last published itself or read what waits for it, to within an hour';
