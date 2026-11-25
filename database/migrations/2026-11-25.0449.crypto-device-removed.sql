-- Which of an account's devices the server trusts, so that someone holding only the
-- password can't remove the ones its owner approved. Trust starts at the account's
-- first device and passes only through vouches by a trusted device; it outlives the
-- device that gave it. A vouch is something else: what the app checks, and a removed
-- device vouches for nothing.

ALTER TABLE IF EXISTS crypto_devices
    DROP COLUMN IF EXISTS trust,
    ADD COLUMN IF NOT EXISTS trust TEXT CONSTRAINT crypto_devices_trust_check CHECK (trust IN ('first', 'vouched'));

COMMENT ON COLUMN crypto_devices.trust IS
    'Why the server trusts it: the first of the account''s devices in use, or vouched for by a trusted one; NULL if neither';
COMMENT ON CONSTRAINT crypto_devices_trust_check ON crypto_devices IS 'first or vouched';
COMMENT ON COLUMN crypto_devices.vouched_by IS 'The device that signed, while it is in use';

-- A device published while the account has no trusted device in use is its first.
CREATE OR REPLACE FUNCTION _crypto_device_published() RETURNS trigger
    LANGUAGE plpgsql
AS
$$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM crypto_devices
        WHERE user_id = NEW.user_id
          AND removed_at IS NULL
          AND trust IS NOT NULL
    ) THEN
        NEW.trust := 'first';
    END IF;
    RETURN NEW;
END
$$;

COMMENT ON FUNCTION _crypto_device_published() IS
    'BEFORE INSERT on crypto_devices: the first device of an account with no trusted device in use is trusted';

DROP TRIGGER IF EXISTS crypto_devices_published ON crypto_devices;
CREATE TRIGGER crypto_devices_published
    BEFORE INSERT
    ON crypto_devices
    FOR EACH ROW
EXECUTE FUNCTION _crypto_device_published();

COMMENT ON TRIGGER crypto_devices_published ON crypto_devices IS 'A device published';

-- What a removed device vouched for is vouched for by nobody, as when a device is
-- deleted, and a device in use can vouch for it again. An account left with devices
-- in use and none of them trusted trusts the earliest published, as if it had been
-- published first.
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

    IF NOT EXISTS (
        SELECT 1
        FROM crypto_devices
        WHERE user_id = NEW.user_id
          AND removed_at IS NULL
          AND trust IS NOT NULL
    ) THEN
        UPDATE crypto_devices
        SET trust = 'first'
        WHERE id = (
            SELECT id
            FROM crypto_devices
            WHERE user_id = NEW.user_id
              AND removed_at IS NULL
            ORDER BY created_at, id
            LIMIT 1
        );
    END IF;
    RETURN NULL;
END
$$;

COMMENT ON FUNCTION _crypto_device_removed() IS
    'AFTER UPDATE on crypto_devices: a removed device vouches for nothing, and an account keeps a trusted device in use';

DROP TRIGGER IF EXISTS crypto_devices_removed ON crypto_devices;
CREATE TRIGGER crypto_devices_removed
    AFTER UPDATE OF removed_at
    ON crypto_devices
    FOR EACH ROW
    WHEN (OLD.removed_at IS NULL AND NEW.removed_at IS NOT NULL)
EXECUTE FUNCTION _crypto_device_removed();

COMMENT ON TRIGGER crypto_devices_removed ON crypto_devices IS 'A device its owner removed';

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
