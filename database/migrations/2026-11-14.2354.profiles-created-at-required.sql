-- Every account now has the time it was made: prod and dev were backfilled from
-- Firebase Auth with none left over, and new rows take their insert time. So the
-- column is required from here on.
--
-- A local database's test accounts have no Firebase account to backfill from; they
-- take their last update, so the constraint applies there too. Where the backfill
-- ran, nothing matches.

UPDATE profiles
SET
    created_at = updated_at
WHERE created_at IS NULL;

ALTER TABLE IF EXISTS profiles
    ALTER COLUMN created_at SET NOT NULL;

COMMENT ON COLUMN profiles.created_at IS
    'When the account was made: its Firebase Auth creation time, or the row''s insert time';
