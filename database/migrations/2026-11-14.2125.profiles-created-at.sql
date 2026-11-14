-- When an account was made. Rows made from now on take the time they were inserted;
-- the rows that already exist stay NULL until they are backfilled from each
-- account's Firebase Auth creation time, which is the truth for every account,
-- the new ones included. NULL means not known, never "just now".
--
-- No DROP: a re-run must not throw away backfilled times, which only Firebase can
-- give back.

ALTER TABLE IF EXISTS profiles
    ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ;

ALTER TABLE IF EXISTS profiles
    ALTER COLUMN created_at SET DEFAULT now();

COMMENT ON COLUMN profiles.created_at IS
    'When the account was made: its Firebase Auth creation time, or the row''s insert time until that is known; NULL when neither is';
