-- What a scheduled account deletion needs in order to also revoke the account's
-- Sign in with Apple grant when it fires.
--
-- Apple's authorization code is single-use and lives about five minutes, so it
-- cannot survive the days between the user confirming a deletion and the
-- schedule running. It is exchanged at confirmation for a long-lived refresh
-- token, and that is what these columns hold until the schedule fires or the
-- user cancels. Both are NULL for every account that never signed in with
-- Apple, and for every Apple account outside a pending deletion.
--
-- Rebuilt on a re-run rather than left alone. A token in flight cannot be
-- reproduced, but none exists when this runs: no account can hold one until
-- the feature these columns serve is live. Later changes to either column
-- will need a migration that adds without dropping.

ALTER TABLE profiles
    DROP COLUMN IF EXISTS apple_refresh_token,
    ADD COLUMN IF NOT EXISTS apple_refresh_token TEXT,
    DROP COLUMN IF EXISTS apple_client_id,
    ADD COLUMN IF NOT EXISTS apple_client_id TEXT;

COMMENT ON COLUMN profiles.apple_refresh_token IS
    'Sign in with Apple refresh token held for the pending deletion''s revoke call; NULL outside one, and for non-Apple accounts. A credential: never selected into a response.';

COMMENT ON COLUMN profiles.apple_client_id IS
    'The Apple client the refresh token was issued to - a bundle id for a native sign-in, a Services ID for the web one. Revocation is rejected without the matching client, and the value varies per platform, so it is stored rather than assumed.';
