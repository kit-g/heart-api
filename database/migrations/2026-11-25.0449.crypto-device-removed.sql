-- Which of an account's devices the server trusts, so that someone holding only the
-- password can't remove the ones its owner approved. Trust starts at the account's
-- very first device and passes only through vouches by a trusted device; it outlives
-- the device that gave it, and nothing else gives it: an account that lost every
-- trusted device has none until a way back exists, since a password could otherwise
-- make itself the one trusted. A vouch is something else: what the app checks, and a
-- removed device vouches for nothing.

ALTER TABLE IF EXISTS crypto_devices
    DROP COLUMN IF EXISTS trust,
    ADD COLUMN IF NOT EXISTS trust TEXT CONSTRAINT crypto_devices_trust_check CHECK (trust IN ('first', 'vouched'));

COMMENT ON COLUMN crypto_devices.trust IS
    'Why the server trusts it: the account''s first device, or vouched for by a trusted one; NULL if neither';
COMMENT ON CONSTRAINT crypto_devices_trust_check ON crypto_devices IS 'first or vouched';
COMMENT ON COLUMN crypto_devices.vouched_by IS 'The device that signed, while it is in use';

-- The first device an account ever publishes is trusted.
CREATE OR REPLACE FUNCTION _crypto_device_published() RETURNS trigger
    LANGUAGE plpgsql
AS
$$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM crypto_devices
        WHERE user_id = NEW.user_id
    ) THEN
        NEW.trust := 'first';
    END IF;
    RETURN NEW;
END
$$;

COMMENT ON FUNCTION _crypto_device_published() IS
    'BEFORE INSERT on crypto_devices: an account''s first device ever is trusted';

DROP TRIGGER IF EXISTS crypto_devices_published ON crypto_devices;
CREATE TRIGGER crypto_devices_published
    BEFORE INSERT
    ON crypto_devices
    FOR EACH ROW
EXECUTE FUNCTION _crypto_device_published();

COMMENT ON TRIGGER crypto_devices_published ON crypto_devices IS 'A device published';

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

-- A device that comes to be trusted passes it on to what it vouched for before, and
-- that in turn to its own, each vouch having been checked when it was made.
CREATE OR REPLACE FUNCTION _crypto_device_trusted() RETURNS trigger
    LANGUAGE plpgsql
AS
$$
BEGIN
    UPDATE crypto_devices
    SET trust = 'vouched'
    WHERE vouched_by = NEW.id
      AND removed_at IS NULL
      AND trust IS NULL;
    RETURN NULL;
END
$$;

COMMENT ON FUNCTION _crypto_device_trusted() IS
    'AFTER UPDATE on crypto_devices: a device newly trusted makes what it vouched for trusted';

DROP TRIGGER IF EXISTS crypto_devices_trusted ON crypto_devices;
CREATE TRIGGER crypto_devices_trusted
    AFTER UPDATE OF trust
    ON crypto_devices
    FOR EACH ROW
    WHEN (OLD.trust IS NULL AND NEW.trust IS NOT NULL AND NEW.removed_at IS NULL)
EXECUTE FUNCTION _crypto_device_trusted();

COMMENT ON TRIGGER crypto_devices_trusted ON crypto_devices IS 'A device the server came to trust';

-- What is there already: vouches by removed devices go, each account's earliest device
-- in use is its first, and trust follows the vouches left. Those vouches were never
-- checked by the server, which is taken on faith once.
UPDATE crypto_devices d
SET
    vouched_by = NULL,
    signature = NULL
FROM crypto_devices v
WHERE v.id = d.vouched_by
  AND v.removed_at IS NOT NULL;

UPDATE crypto_devices d
SET trust = 'first'
WHERE d.removed_at IS NULL
  AND NOT EXISTS (
    SELECT 1
    FROM crypto_devices o
    WHERE o.user_id = d.user_id
      AND o.removed_at IS NULL
      AND (o.created_at, o.id) < (d.created_at, d.id)
  );

WITH RECURSIVE _trusted AS (
    SELECT id
    FROM crypto_devices
    WHERE trust = 'first'
    UNION
    SELECT d.id
    FROM crypto_devices d
    JOIN _trusted t ON d.vouched_by = t.id
    WHERE d.removed_at IS NULL
)
UPDATE crypto_devices d
SET trust = 'vouched'
FROM _trusted t
WHERE d.id = t.id
  AND d.trust IS NULL;
