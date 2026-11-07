part of '../db.dart';

/// A [User] as every profile read and write answers it.
const _userColumns = '''
  id, email, username, avatar_url, scheduled_for_deletion_at, settings,
  (SELECT array_agg(entitlement ORDER BY entitlement) FROM entitlements WHERE user_id = profiles.id) AS entitlements
''';

const _updateAccount = '''
INSERT INTO profiles (id, email, username, avatar_url, settings, updated_at)
VALUES (@id, @email, @username, @avatar, @settings::jsonb, now())
ON CONFLICT (id)
DO UPDATE
SET
username = EXCLUDED.username,
email = EXCLUDED.email,
avatar_url = EXCLUDED.avatar_url,
settings = profiles.settings || EXCLUDED.settings,
updated_at = now()
RETURNING $_userColumns''';

const _scheduleAccountDeletion = '''
UPDATE profiles
SET 
  account_deletion_schedule = coalesce(@schedule, account_deletion_schedule), 
  scheduled_for_deletion_at = coalesce(@scheduledAt, scheduled_for_deletion_at),
  apple_refresh_token = coalesce(@appleRefreshToken, apple_refresh_token),
  apple_client_id = coalesce(@appleClientId, apple_client_id)
WHERE id = @userId
RETURNING $_userColumns''';

/// The Apple grant to revoke before the account goes.
///
/// Read on its own rather than taken from the profile delete's `RETURNING`:
/// the delete is the point of no return, and a handler that died between it
/// and the revoke would have nothing left to retry with. Reading first means
/// every attempt up to the delete still finds the token.
const _appleDeletionGrant = '''
SELECT apple_refresh_token, apple_client_id
FROM profiles
WHERE id = @userId
''';

const _updateAvatarUrl = '''
UPDATE profiles
SET 
  avatar_url = @avatarUrl, 
  updated_at = now()
WHERE id = @userId
RETURNING $_userColumns''';

const _undoAccountDeletion = '''
UPDATE profiles
SET
  account_deletion_schedule = NULL,
  scheduled_for_deletion_at = NULL,
  -- nothing was revoked and the account is staying, so the grant is a
  -- credential with no remaining purpose
  apple_refresh_token = NULL,
  apple_client_id = NULL
WHERE id = @userId
RETURNING $_userColumns''';

const _deleteAccount = '''
DELETE FROM profiles
WHERE id = @userId
''';

/// Per-collection totals for everything one account owns: the inventory a data
/// export has to match, so the app can compare it against its local mirror and
/// know the export is complete rather than assume it.
///
/// Fourteen independent counts in one round trip; the final cross join is
/// fourteen one-row relations. Most ride an existing index on their owner
/// column; `program_actions` and `program_bases` are indexed by program, not
/// owner, and scan like the two below. The exceptions are `comments` (no `author_id` index — the table's
/// indexes are all on the four target columns) and `goals` (`goals_user_id_idx`
/// is partial on `NOT archived`, and an export counts archived goals too), both
/// of which scan. Fine for a call made once before an export; the thing to
/// revisit first if this ever gets polled.
///
/// `latest` is the newest row's id. Ids are uuid v7, so `max()` is chronological
/// and the value doubles as a high-water mark: a mirror with the same count over
/// *different* rows reads as in-sync on the count alone and diverged on this.
/// The cast is *inside* `max()` because Postgres has no `max(uuid)` aggregate;
/// uuids render as canonical lowercase hex with the dashes at fixed positions,
/// so text order and uuid order are the same thing.
///
/// `connections` is the one collection without it: it had no id when this
/// summary was made, and its `latest` stays the typed NULL a reader already
/// knows, which also keeps every branch the same shape.
///
/// Scope notes: `custom_exercises` is the user's own rows only (a global library
/// row is not the account's to export); `template_shares` is the coach side,
/// because a share the account *received* is already counted as the copied
/// template it produced; `connections` counts both directions, matching
/// `_listConnections`. Device tokens are excluded — plumbing, not user data.
///
/// Nothing health-derived is countable here and nothing can be: the server
/// stores no health data at all (CLAUDE.md, the device-only health rule).
const _accountSummary = '''
WITH
  _custom_exercises AS (
    SELECT count(*) AS n, max(id::text) AS latest
    FROM exercises WHERE user_id = @userId
  ),
  _exercise_preferences AS (
    SELECT count(*) AS n, max(id::text) AS latest
    FROM exercise_preferences WHERE user_id = @userId
  ),
  _template_folders AS (
    SELECT count(*) AS n, max(id::text) AS latest
    FROM template_folders WHERE user_id = @userId
  ),
  _templates AS (
    SELECT count(*) AS n, max(id::text) AS latest
    FROM templates WHERE user_id = @userId
  ),
  _template_shares AS (
    SELECT count(*) AS n, max(id::text) AS latest
    FROM template_shares WHERE coach_id = @userId
  ),
  _workouts AS (
    SELECT count(*) AS n, max(id::text) AS latest
    FROM workouts WHERE user_id = @userId
  ),
  _workout_images AS (
    SELECT count(*) AS n, max(id::text) AS latest
    FROM workout_images WHERE user_id = @userId
  ),
  _goals AS (
    SELECT count(*) AS n, max(id::text) AS latest
    FROM goals WHERE user_id = @userId
  ),
  _comments AS (
    SELECT count(*) AS n, max(id::text) AS latest
    FROM comments WHERE author_id = @userId
  ),
  _connections AS (
    SELECT count(*) AS n, NULL::text AS latest
    FROM connections WHERE initiator_id = @userId OR target_id = @userId
  ),
  _programs AS (
    SELECT count(*) AS n, max(id::text) AS latest
    FROM programs WHERE user_id = @userId
  ),
  _program_actions AS (
    SELECT count(*) AS n, max(id::text) AS latest
    FROM program_actions WHERE user_id = @userId
  ),
  _program_bases AS (
    SELECT count(*) AS n, max(id::text) AS latest
    FROM program_bases WHERE user_id = @userId
  ),
  _skips AS (
    SELECT count(*) AS n, max(id::text) AS latest
    FROM skips WHERE user_id = @userId
  )
SELECT
  _custom_exercises.n         AS custom_exercises_count,
  _custom_exercises.latest    AS custom_exercises_latest,
  _exercise_preferences.n     AS exercise_preferences_count,
  _exercise_preferences.latest AS exercise_preferences_latest,
  _template_folders.n         AS template_folders_count,
  _template_folders.latest    AS template_folders_latest,
  _templates.n                AS templates_count,
  _templates.latest           AS templates_latest,
  _template_shares.n          AS template_shares_count,
  _template_shares.latest     AS template_shares_latest,
  _workouts.n                 AS workouts_count,
  _workouts.latest            AS workouts_latest,
  _workout_images.n           AS workout_images_count,
  _workout_images.latest      AS workout_images_latest,
  _goals.n                    AS goals_count,
  _goals.latest               AS goals_latest,
  _comments.n                 AS comments_count,
  _comments.latest            AS comments_latest,
  _connections.n              AS connections_count,
  _connections.latest         AS connections_latest,
  _programs.n                 AS programs_count,
  _programs.latest            AS programs_latest,
  _program_actions.n          AS program_actions_count,
  _program_actions.latest     AS program_actions_latest,
  _program_bases.n            AS program_bases_count,
  _program_bases.latest       AS program_bases_latest,
  _skips.n                    AS skips_count,
  _skips.latest               AS skips_latest
FROM _custom_exercises,
     _exercise_preferences,
     _template_folders,
     _templates,
     _template_shares,
     _workouts,
     _workout_images,
     _goals,
     _comments,
     _connections,
     _programs,
     _program_actions,
     _program_bases,
     _skips
''';

const _getProfile =
    '''
SELECT $_userColumns
FROM profiles
WHERE id = @userId
''';
