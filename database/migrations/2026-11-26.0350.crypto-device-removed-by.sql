-- Which device removed a device, so the account's devices can show a removal its owner
-- didn't make; and a removed device vouches for nothing, as a deleted one doesn't.

ALTER TABLE IF EXISTS crypto_devices
    DROP COLUMN IF EXISTS removed_by,
    ADD COLUMN IF NOT EXISTS removed_by UUID REFERENCES crypto_devices (id) ON DELETE SET NULL;

COMMENT ON COLUMN crypto_devices.removed_by IS
    'The device of the same owner that removed it; NULL while in use, and for removals from before it was recorded';
COMMENT ON COLUMN crypto_devices.vouched_by IS 'The device that signed, while it is in use';

CREATE INDEX IF NOT EXISTS crypto_devices_removed_by_idx ON crypto_devices (removed_by) WHERE removed_by IS NOT NULL;

COMMENT ON INDEX crypto_devices_removed_by_idx IS 'The SET NULL when a removing device is deleted';

-- What a removed device vouched for is vouched for by nobody, as when a device is
-- deleted, and a device in use can vouch for it again.
CREATE OR REPLACE FUNCTION _crypto_device_removed() RETURNS trigger
    LANGUAGE plpgsql
AS
$$
BEGIN
    UPDATE crypto_devices
    SET
        vouched_by = NULL,
        signature = NULL
    WHERE vouched_by = NEW.id;
    RETURN NULL;
END
$$;

COMMENT ON FUNCTION _crypto_device_removed() IS
    'AFTER UPDATE on crypto_devices: a removed device vouches for nothing';

DROP TRIGGER IF EXISTS crypto_devices_removed ON crypto_devices;
CREATE TRIGGER crypto_devices_removed
    AFTER UPDATE OF removed_at
    ON crypto_devices
    FOR EACH ROW
    WHEN (OLD.removed_at IS NULL AND NEW.removed_at IS NOT NULL)
EXECUTE FUNCTION _crypto_device_removed();

COMMENT ON TRIGGER crypto_devices_removed ON crypto_devices IS 'A device its owner removed';

-- Vouches by devices removed before this.
UPDATE crypto_devices d
SET
    vouched_by = NULL,
    signature = NULL
FROM crypto_devices v
WHERE v.id = d.vouched_by
  AND v.removed_at IS NOT NULL;
