part of '../db.dart';

const _createConnection = '''
-- A block reads as no such person, so a request can't test for one.
WITH target_exists AS (
  SELECT 1 FROM profiles WHERE id = @targetId AND NOT _blocked_between(@initiatorId, @targetId)
),
-- An ended peer relationship can be asked for again, and the one asking is
-- then the one who can't answer. A coach's only restarts from an invitation.
-- It's accepted again when it's answered again.
reopened AS (
  UPDATE connections
  SET status = 'pending', status_by = @initiatorId, accepted_at = NULL
  WHERE domain = @domain
    AND status = 'severed'
    AND initiator_role = 'PEER'
    AND @initiatorRole = 'PEER'
    AND exists(SELECT 1 FROM target_exists)
    AND (initiator_id, target_id) IN ((@initiatorId, @targetId), (@targetId, @initiatorId))
  RETURNING
    id AS connection_id,
    CASE WHEN initiator_id = @initiatorId THEN target_id ELSE initiator_id END AS target_id,
    initiator_role AS "role", domain, status, created_at, accepted_at, shares
),
inserted AS (
  INSERT INTO connections (initiator_id, target_id, initiator_role, target_role, domain, status_by)
  SELECT @initiatorId, @targetId, @initiatorRole, @targetRole, @domain, @initiatorId
  WHERE exists(SELECT 1 FROM target_exists)
    AND NOT exists(SELECT 1 FROM reopened)
  ON CONFLICT DO NOTHING
  RETURNING id AS connection_id, target_id, initiator_role AS "role", domain, status, created_at, accepted_at, shares
)
SELECT connection_id, target_id, "role", domain, status, created_at, accepted_at, shares FROM reopened
UNION ALL
SELECT connection_id, target_id, "role", domain, status, created_at, accepted_at, shares FROM inserted
UNION ALL
SELECT
  id AS connection_id,
  CASE WHEN initiator_id = @initiatorId THEN target_id ELSE initiator_id END AS target_id,
  CASE WHEN initiator_id = @initiatorId THEN initiator_role ELSE target_role END AS role,
  domain,
  status,
  created_at,
  accepted_at,
  shares
FROM connections
WHERE domain = @domain
  AND exists(SELECT 1 FROM target_exists)
  AND NOT exists(SELECT 1 FROM inserted)
  AND NOT exists(SELECT 1 FROM reopened)
  AND (
    (initiator_id = @initiatorId AND target_id = @targetId)
    OR
    (initiator_id = @targetId AND target_id = @initiatorId)
  )
''';

const _listConnections = '''
SELECT
  id AS connection_id,
  target_id,
  initiator_role AS role,
  domain,
  status,
  created_at,
  accepted_at,
  shares
FROM connections
WHERE initiator_id = @userId
  AND (@role::text IS NULL OR initiator_role = @role)
UNION ALL
SELECT id AS connection_id, initiator_id AS target_id, target_role AS role, domain, status, created_at, accepted_at, shares
FROM connections
WHERE target_id = @userId
  AND (@role::text IS NULL OR target_role = @role)
ORDER BY created_at DESC
''';

const _getConnection = '''
SELECT
  id AS connection_id,
  CASE WHEN initiator_id = @userId THEN target_id ELSE initiator_id END AS target_id,
  CASE WHEN initiator_id = @userId THEN initiator_role ELSE target_role END AS role,
  domain, status, created_at, accepted_at, shares
FROM connections
WHERE domain = @domain
  AND (
    (initiator_id = @userId AND target_id = @targetId AND initiator_role = @role)
    OR (initiator_id = @targetId AND target_id = @userId AND target_role = @role)
  )
''';

/// Ending is either party's call — except while a block stands, when only the
/// blocker may. The row stays, because "this person was a client" outlives it,
/// and one already ended stays as it ended, by whom it ended.
///
/// Returns one row either way: `refused` is the block guard; anything else not
/// ended was nothing to end, a no-op as it has always been.
const _endConnection = '''
WITH
_pair AS (
  SELECT status, status_by FROM connections
  WHERE (initiator_id, target_id, domain) IN (
    (@actorId, @targetId, @domain),
    (@targetId, @actorId, @domain)
  )
),
_ended AS (
  UPDATE connections
  SET status = 'severed', status_by = @actorId
  WHERE (initiator_id, target_id, domain) IN (
    (@actorId, @targetId, @domain),
    (@targetId, @actorId, @domain)
  )
  AND status <> 'severed'
  AND EXISTS (SELECT 1 FROM _pair WHERE status <> 'blocked' OR status_by = @actorId)
  RETURNING 1
)
SELECT EXISTS (SELECT 1 FROM _pair WHERE status = 'blocked' AND status_by IS DISTINCT FROM @actorId) AS refused
''';

/// The rules that turn on *which* side is asking, enforced here rather than in
/// Dart so they cannot be raced past:
///
/// - whoever put a request in front of the other person can't answer it, which
///   `status_by` says even after a row went back to pending. The author of a
///   request must not be able to approve their own, and neither may the other
///   side of a severed row by reopening it.
/// - a coach's row becomes pending or active from a request only by invitation.
/// - only the student resumes a paused coach's row.
/// - only whoever set a block may lift it.
/// - nothing starts again while a block stands, from either side.
///
/// `@expectedStatus` makes the write optimistic-locked against the status the
/// caller read, so a concurrent change loses rather than silently overwriting.
const _updateConnectionStatus = '''
UPDATE connections
SET status = @newStatus, status_by = @actorId
WHERE (initiator_id, target_id, domain) IN (
  (@actorId, @targetId, @domain),
  (@targetId, @actorId, @domain)
)
AND status = @expectedStatus
AND (@newStatus NOT IN ('active', 'declined') OR status <> 'pending' OR coalesce(status_by, initiator_id) <> @actorId)
AND (
  initiator_role = 'PEER'
  OR NOT (@newStatus = 'pending' OR (status = 'pending' AND @newStatus = 'active'))
)
AND (
  initiator_role = 'PEER'
  OR status <> 'paused'
  OR @newStatus <> 'active'
  OR (initiator_id = @actorId AND initiator_role = 'STUDENT')
  OR (target_id = @actorId AND target_role = 'STUDENT')
)
AND (status <> 'blocked' OR status_by = @actorId)
AND (@newStatus NOT IN ('pending', 'active', 'paused') OR NOT _blocked_between(@actorId, @targetId))
RETURNING
  id AS connection_id,
  CASE WHEN initiator_id = @actorId THEN target_id ELSE initiator_id END AS target_id,
  CASE WHEN initiator_id = @actorId THEN initiator_role ELSE target_role END AS role,
  domain, status, created_at, accepted_at, shares
''';

const _updateConnectionShares = '''
UPDATE connections
SET shares = @shares::text[]
WHERE (
  (initiator_id = @actorId AND target_id = @targetId AND initiator_role = 'STUDENT')
  OR (initiator_id = @targetId AND target_id = @actorId AND target_role = 'STUDENT')
)
AND domain = @domain
AND status IN ('active', 'paused')
RETURNING
  id AS connection_id,
  CASE WHEN initiator_id = @actorId THEN target_id ELSE initiator_id END AS target_id,
  CASE WHEN initiator_id = @actorId THEN initiator_role ELSE target_role END AS role,
  domain, status, created_at, accepted_at, shares
''';

const _areConnected = '''
SELECT 1 FROM connections
WHERE status = 'active'
  AND NOT _blocked_between(@userA, @userB)
  AND (
    (initiator_id = @userA AND target_id = @userB)
    OR
    (initiator_id = @userB AND target_id = @userA)
  )
LIMIT 1
''';
