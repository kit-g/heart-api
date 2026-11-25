-- A removed device vouches for nothing: what it vouched for reads as never vouched
-- for, as when a device is deleted, and can be vouched for again by one in use.

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
    'AFTER UPDATE on crypto_devices: the devices one that was removed vouched for are vouched for by nobody';

DROP TRIGGER IF EXISTS crypto_devices_removed ON crypto_devices;
CREATE TRIGGER crypto_devices_removed
    AFTER UPDATE OF removed_at
    ON crypto_devices
    FOR EACH ROW
    WHEN (OLD.removed_at IS NULL AND NEW.removed_at IS NOT NULL)
EXECUTE FUNCTION _crypto_device_removed();

COMMENT ON TRIGGER crypto_devices_removed ON crypto_devices IS 'A device its owner removed';

UPDATE crypto_devices d
SET
    vouched_by = NULL,
    signature = NULL
FROM crypto_devices v
WHERE v.id = d.vouched_by
  AND v.removed_at IS NOT NULL;

COMMENT ON COLUMN crypto_devices.vouched_by IS 'The device that signed, while it is in use';
