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

/// A connection's status as one side reads it: one the other side ([other]) blocked
/// reads as ended, so the one blocked can't tell. [row] names the `connections` row,
/// or a CTE with its `status` and `status_by`. Every read of a status and every write
/// that checks one goes through this, so they agree on what the caller sees.
String _statusSeen(String row, {required String other}) {
  return "CASE WHEN $row.status = 'blocked' AND $row.status_by = $other THEN 'severed' ELSE $row.status END";
}

/// Who the other side of connection `c` is, for `@userId`: their name and photo as
/// their profile says now, to someone they asked or who they accepted, never to
/// someone who only asked them, and never to someone they blocked. A name
/// `@userId` gave them ([_given_name]) goes first, on the same terms, so a block
/// still reads as an ending without a name. Its status is
/// [_statusSeen] by `@userId`. `c` needs `target_id` (the other person),
/// `initiator_id`, `status`, `status_by`, `accepted_at` and the rest of a
/// connection's columns.
final _connectionOther =
    '''
SELECT
  c.connection_id,
  c.target_id,
  c.role,
  c.domain,
  ${_statusSeen('c', other: 'c.target_id')} AS status,
  c.created_at,
  c.accepted_at,
  c.shares,
  coalesce(given.name, nullif(trim(p.username), '')) AS username,
  given.name IS NOT NULL AS named_by_you,
  p.avatar_url
FROM _side c
LEFT JOIN blocks b
  ON b.blocker_id = c.target_id
  AND b.blocked_id = @userId
  AND b.lifted_at IS NULL
LEFT JOIN profiles p
  ON p.id = c.target_id
  AND b.id IS NULL
  AND (
    c.accepted_at IS NOT NULL
    OR c.initiator_id = c.target_id
    OR (c.status = 'pending' AND c.status_by = c.target_id)
  )
LEFT JOIN LATERAL (SELECT _given_name(@userId, c.target_id) AS name) given ON p.id IS NOT NULL
''';

/// Every connection of the caller's, both directions, as [_connectionOther] says it.
final _listConnections =
    '''
WITH _side AS (
  SELECT
    id AS connection_id,
    target_id,
    initiator_id,
    initiator_role AS role,
    domain,
    status,
    status_by,
    created_at,
    accepted_at,
    shares
  FROM connections
  WHERE initiator_id = @userId
    AND (@role::text IS NULL OR initiator_role = @role)
  UNION ALL
  SELECT
    id AS connection_id,
    initiator_id AS target_id,
    initiator_id,
    target_role AS role,
    domain,
    status,
    status_by,
    created_at,
    accepted_at,
    shares
  FROM connections
  WHERE target_id = @userId
    AND (@role::text IS NULL OR target_role = @role)
)
$_connectionOther
ORDER BY c.created_at DESC
''';

/// One connection, as `@userId` reads it ([_statusSeen]).
final _getConnection =
    '''
SELECT
  id AS connection_id,
  CASE WHEN initiator_id = @userId THEN target_id ELSE initiator_id END AS target_id,
  CASE WHEN initiator_id = @userId THEN initiator_role ELSE target_role END AS role,
  domain,
  ${_statusSeen('connections', other: '@targetId')} AS status,
  created_at,
  accepted_at,
  shares
FROM connections
WHERE domain = @domain
  AND (
    (initiator_id = @userId AND target_id = @targetId AND initiator_role = @role)
    OR (initiator_id = @targetId AND target_id = @userId AND target_role = @role)
  )
''';

/// Either side's view of one connection, by its identity, as [_connectionOther]
/// says it: the routes that change one answer with who the other person is.
final _getConnectionById =
    '''
WITH _side AS (
  SELECT
    id AS connection_id,
    CASE WHEN initiator_id = @userId THEN target_id ELSE initiator_id END AS target_id,
    initiator_id,
    CASE WHEN initiator_id = @userId THEN initiator_role ELSE target_role END AS role,
    domain,
    status,
    status_by,
    created_at,
    accepted_at,
    shares
  FROM connections
  WHERE id = @connectionId::uuid
    AND @userId IN (initiator_id, target_id)
)
$_connectionOther
''';

/// Ending is either party's call — except while a block stands, when only the
/// blocker may. The row stays, because "this person was a client" outlives it,
/// and one already ended stays as it ended, by whom it ended.
///
/// One the other person blocked is left as it is: it reads as ended to the one
/// blocked ([_statusSeen]), and ending it again changes nothing, as it would if
/// it had ended.
const _endConnection = '''
UPDATE connections
SET status = 'severed', status_by = @actorId
WHERE (initiator_id, target_id, domain) IN (
  (@actorId, @targetId, @domain),
  (@targetId, @actorId, @domain)
)
AND status <> 'severed'
AND (status <> 'blocked' OR status_by = @actorId)
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
/// - the one blocked reads the row as ended ([_statusSeen]) and can block back
///   from it, as from any ended one: their own block is set, and the row is
///   theirs, so each side reads it as the other's block would show.
///
/// `@expectedStatus` makes the write optimistic-locked against the status the
/// caller read, so a concurrent change loses rather than silently overwriting.
final _updateConnectionStatus =
    '''
WITH
_blocked_back AS (
  INSERT INTO blocks (blocker_id, blocked_id)
  SELECT @actorId, @targetId
  FROM connections
  WHERE (initiator_id, target_id, domain) IN (
    (@actorId, @targetId, @domain),
    (@targetId, @actorId, @domain)
  )
  AND status = 'blocked'
  AND status_by = @targetId
  AND @newStatus = 'blocked'
  AND @expectedStatus = 'severed'
  ON CONFLICT DO NOTHING
)
UPDATE connections
SET status = @newStatus, status_by = @actorId
WHERE (initiator_id, target_id, domain) IN (
  (@actorId, @targetId, @domain),
  (@targetId, @actorId, @domain)
)
AND ${_statusSeen('connections', other: '@targetId')} = @expectedStatus
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
AND (status <> 'blocked' OR status_by = @actorId OR @newStatus = 'blocked')
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

/// The person `@userId` names through connection `@connectionId`: their client, now
/// or before, across a connection that was accepted once and no block stands on.
const _namedPerson = '''
_person AS (
  SELECT CASE WHEN c.initiator_id = @userId THEN c.target_id ELSE c.initiator_id END AS person_id
  FROM connections c
  WHERE c.id = @connectionId::uuid
    AND c.accepted_at IS NOT NULL
    AND (
      (c.initiator_id = @userId AND c.initiator_role = 'COACH')
      OR (c.target_id = @userId AND c.target_role = 'COACH')
    )
    AND NOT _blocked_between(c.initiator_id, c.target_id)
)''';

/// One row when the name was given, none when [_namedPerson] finds nobody.
const _giveName =
    '''
WITH
$_namedPerson
INSERT INTO given_names (giver_id, person_id, name)
SELECT @userId, person_id, @name
FROM _person
ON CONFLICT (giver_id, person_id) DO UPDATE
SET
  name = EXCLUDED.name,
  updated_at = now()
RETURNING person_id
''';

/// One row when [_namedPerson] finds someone, whether or not a name was there to go.
const _takeNameBack =
    '''
WITH
$_namedPerson,
_gone AS (
  DELETE FROM given_names g
  USING _person p
  WHERE g.giver_id = @userId
    AND g.person_id = p.person_id
  RETURNING g.person_id
)
SELECT person_id FROM _person
''';
