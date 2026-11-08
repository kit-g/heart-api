part of '../db.dart';

const _invitationStatus = '''
  CASE
    WHEN EXISTS (SELECT 1 FROM invitation_responses r WHERE r.invitation_id = i.id AND r.response = 'accepted') THEN 'accepted'
    WHEN EXISTS (SELECT 1 FROM invitation_responses r WHERE r.invitation_id = i.id AND r.at >= i.renewed_at) THEN 'declined'
    WHEN i.canceled_at IS NOT NULL THEN 'canceled'
    WHEN i.expires_at <= now() THEN 'expired'
    ELSE 'pending'
  END
''';

/// What stops an inviter making a link, or sending one again. A link being sent
/// again isn't counted against itself.
const _invitationLoad =
    '''
SELECT
  EXISTS (SELECT 1 FROM entitlements WHERE user_id = @inviterId AND entitlement = 'coach') AS entitled,
  (
    SELECT count(*)
    FROM invitations i
    WHERE i.inviter_id = @inviterId
      AND i.id IS DISTINCT FROM @invitationId::uuid
      AND i.canceled_at IS NULL
      AND i.expires_at > now()
      AND NOT EXISTS (SELECT 1 FROM invitation_responses r WHERE r.invitation_id = i.id AND r.at >= i.renewed_at)
  ) < $_maxPendingInvitations
  AND (
    SELECT count(*)
    FROM invitation_responses r
    JOIN invitations i ON i.id = r.invitation_id
    WHERE i.inviter_id = @inviterId
      AND r.response = 'declined'
      AND r.at > now() - INTERVAL '30 days'
  ) < $_maxRecentDeclines AS within
''';

const _createInvitation =
    '''
WITH
_load AS (
  $_invitationLoad
),
_inserted AS (
  INSERT INTO invitations (inviter_id, domain, token_hash, name, expires_at)
  SELECT @inviterId, @domain, @tokenHash, @name, @expiresAt
  FROM _load
  WHERE entitled
    AND within
  RETURNING id, name, role, domain, expires_at, created_at
)
SELECT l.entitled, n.id, n.name, n.role, n.domain, n.expires_at, n.created_at, 'pending' AS status
FROM _load l
LEFT JOIN _inserted n ON true
''';

const _listInvitations =
    '''
SELECT i.id, i.name, i.role, i.domain, i.expires_at, i.created_at, $_invitationStatus AS status
FROM invitations i
WHERE i.inviter_id = @inviterId
  AND (@cursor::uuid IS NULL OR i.id < @cursor::uuid)
ORDER BY i.id DESC
LIMIT @limit
''';

const _cancelInvitation = '''
UPDATE invitations i
SET canceled_at = now()
WHERE i.id = @invitationId::uuid
  AND i.inviter_id = @inviterId
  AND i.canceled_at IS NULL
  AND NOT EXISTS (SELECT 1 FROM invitation_responses r WHERE r.invitation_id = i.id AND r.response = 'accepted')
RETURNING id
''';

/// Sending a link again is making one, so it answers to the same limits.
const _renewInvitation =
    '''
WITH
_load AS (
  $_invitationLoad
),
_invitation AS (
  SELECT i.id
  FROM invitations i
  WHERE i.id = @invitationId::uuid
    AND i.inviter_id = @inviterId
    AND NOT EXISTS (SELECT 1 FROM invitation_responses r WHERE r.invitation_id = i.id AND r.response = 'accepted')
),
_renewed AS (
  UPDATE invitations i
  SET token_hash = @tokenHash, expires_at = @expiresAt, canceled_at = NULL, renewed_at = now()
  FROM _load l
  WHERE i.id IN (SELECT id FROM _invitation)
    AND l.entitled
    AND l.within
  RETURNING i.id, i.name, i.role, i.domain, i.expires_at, i.created_at
)
SELECT
  EXISTS (SELECT 1 FROM _invitation) AS found,
  l.entitled,
  n.id, n.name, n.role, n.domain, n.expires_at, n.created_at, 'pending' AS status
FROM _load l
LEFT JOIN _renewed n ON true
''';

/// Whether a link can still be accepted. Someone who declined can change their
/// mind, so only accepting uses it up here; [_acceptInvitation] holds the rest.
/// Who made a link that is no longer good is nobody's to read.
const _previewInvitation = '''
WITH
_preview AS (
  SELECT
    p.username,
    p.avatar_url,
    (
      i.canceled_at IS NULL
      AND i.expires_at > now()
      AND (
        SELECT count(*) FROM invitation_responses r
        WHERE r.invitation_id = i.id AND r.response = 'accepted'
      ) < i.max_uses
    ) AS good
  FROM invitations i
  JOIN profiles p ON p.id = i.inviter_id
  WHERE i.token_hash = @tokenHash
)
SELECT
  CASE WHEN good THEN username END AS username,
  CASE WHEN good THEN avatar_url END AS avatar_url,
  good
FROM _preview
''';

/// Whether `i` can still be answered by `@userId`: it stands, and nobody else's
/// answer has used it up. An acceptance uses it up for good, a decline until the
/// link is sent again.
const _invitationOpen = '''
(
  i.canceled_at IS NULL
  AND i.expires_at > now()
  AND (
    SELECT count(*) FROM invitation_responses r
    WHERE r.invitation_id = i.id
      AND r.user_id IS DISTINCT FROM @userId
      AND (r.at >= i.renewed_at OR r.response = 'accepted')
  ) < i.max_uses
)
''';

/// Someone can answer on the web, with an account made a moment ago and away from
/// any device, so answering makes their profile if need be. Reads `_answering`.
const _answeringPerson = '''
INSERT INTO profiles (id, email, username)
SELECT @userId, @email, @name
FROM _answering
ON CONFLICT (id) DO NOTHING
RETURNING id
''';

/// Holds the invitation for [_acceptInvitation], which runs next in the same
/// transaction. They can't be one statement: one that waited for this lock would still
/// count answers as they stood before it waited, so two people racing would both get in.
/// The pair's lock does the same for a block between the two being set meanwhile.
const _lockInvitation = '''
SELECT id, _lock_pair(inviter_id, @userId)
FROM invitations
WHERE token_hash = @tokenHash
FOR UPDATE
''';

/// A row the pair already holds in this domain is rewritten: the new relationship reads
/// from now, and shares only what was said just now. One the same coach already holds
/// live is left alone, and the link is answered all the same.
const _acceptInvitation =
    '''
WITH
_standing AS (
  SELECT
    i.*,
    i.inviter_id = @userId AS own,
    EXISTS (
      SELECT 1 FROM invitation_responses r
      WHERE r.invitation_id = i.id AND r.user_id = @userId AND r.response = 'accepted'
    ) AS repeated,
    (
      $_invitationOpen
      AND NOT _blocked_between(i.inviter_id, @userId)
      AND (
        SELECT count(*)
        FROM connections c
        WHERE c.status IN ('active', 'paused')
          AND (
            (c.initiator_id = i.inviter_id AND c.initiator_role = 'COACH')
            OR (c.target_id = i.inviter_id AND c.target_role = 'COACH')
          )
      ) < $_maxClients
    ) AS good
  FROM invitations i
  WHERE i.token_hash = @tokenHash
),
_live AS (
  SELECT c.id
  FROM connections c, _standing s
  WHERE c.initiator_id = s.inviter_id
    AND c.target_id = @userId
    AND c.domain = s.domain
    AND c.initiator_role = s.role
    AND c.status IN ('active', 'paused')
),
_answering AS (
  SELECT *
  FROM _standing
  WHERE good
    AND NOT own
    AND NOT repeated
),
_go AS (
  SELECT * FROM _answering WHERE NOT EXISTS (SELECT 1 FROM _live)
),
_connection AS (
  INSERT INTO connections
    (initiator_id, target_id, initiator_role, target_role, domain, status, status_by, accepted_at, shares)
  SELECT
    inviter_id,
    @userId,
    role,
    CASE role WHEN 'COACH' THEN 'STUDENT' ELSE role END,
    domain,
    'active',
    @userId,
    now(),
    CASE role WHEN 'COACH' THEN @shares::text[] ELSE '{}'::text[] END
  FROM _go
  ON CONFLICT (least(initiator_id, target_id), greatest(initiator_id, target_id), domain) DO UPDATE
  SET
    initiator_id = EXCLUDED.initiator_id,
    target_id = EXCLUDED.target_id,
    initiator_role = EXCLUDED.initiator_role,
    target_role = EXCLUDED.target_role,
    status = 'active',
    status_by = EXCLUDED.status_by,
    accepted_at = EXCLUDED.accepted_at,
    shares = EXCLUDED.shares
  RETURNING id, initiator_id, target_id, target_role, domain, status, created_at, accepted_at, shares
),
_response AS (
  INSERT INTO invitation_responses (invitation_id, user_id, response)
  SELECT id, @userId, 'accepted'
  FROM _answering
  ON CONFLICT (invitation_id, user_id) DO UPDATE
  SET response = 'accepted', at = now()
  RETURNING 1
),
-- Someone can accept on the web, with an account made a moment ago and away from
-- any device, so this makes their profile if need be, and records the answer the
-- app would have, in the shape it syncs, beside whatever else that feature keeps.
_person AS (
  INSERT INTO profiles (id, email, username, settings)
  SELECT
    @userId,
    @email,
    @name,
    jsonb_build_object('features', jsonb_build_object('yourCoach', jsonb_build_object('on', true, 'at', to_jsonb(now()))))
  FROM _go
  ON CONFLICT (id) DO UPDATE
  SET settings = jsonb_set(
    profiles.settings,
    '{features}',
    coalesce(profiles.settings -> 'features', '{}'::jsonb)
      || jsonb_build_object(
        'yourCoach',
        CASE jsonb_typeof(profiles.settings -> 'features' -> 'yourCoach')
          WHEN 'object' THEN profiles.settings -> 'features' -> 'yourCoach'
          ELSE '{}'::jsonb
        END
          || (EXCLUDED.settings -> 'features' -> 'yourCoach')
      )
  )
  RETURNING id
),
_row AS (
  SELECT id, initiator_id AS other_id, target_role AS role, domain, status, created_at, accepted_at, shares, true AS fresh
  FROM _connection
  UNION ALL
  SELECT
    c.id,
    CASE WHEN c.initiator_id = @userId THEN c.target_id ELSE c.initiator_id END,
    CASE WHEN c.initiator_id = @userId THEN c.initiator_role ELSE c.target_role END,
    c.domain, c.status, c.created_at, c.accepted_at, c.shares, false
  FROM connections c, _standing s
  WHERE (s.repeated OR EXISTS (SELECT 1 FROM _live))
    AND c.domain = s.domain
    AND c.status IN ('active', 'paused')
    AND (c.initiator_id, c.target_id) IN ((s.inviter_id, @userId), (@userId, s.inviter_id))
)
SELECT
  s.own,
  r.id AS connection_id,
  r.other_id AS target_id,
  r.role,
  r.domain,
  r.status,
  r.created_at,
  r.accepted_at,
  r.shares,
  r.fresh
FROM _standing s
LEFT JOIN _row r ON NOT s.own
''';

/// A person can decline and later accept the same link, and someone it is not
/// for finds it answered. A link that is no longer theirs to answer takes nothing.
const _declineInvitation =
    '''
WITH
_invitation AS (
  SELECT i.id, i.inviter_id = @userId AS own, $_invitationOpen AS open
  FROM invitations i
  WHERE i.token_hash = @tokenHash
),
_answering AS (
  SELECT id FROM _invitation WHERE open AND NOT own
),
_person AS (
  $_answeringPerson
),
_response AS (
  INSERT INTO invitation_responses (invitation_id, user_id, response)
  SELECT id, @userId, 'declined'
  FROM _answering
  ON CONFLICT (invitation_id, user_id) DO UPDATE
  SET response = 'declined', at = now()
  WHERE invitation_responses.response <> 'accepted'
  RETURNING 1
)
SELECT own FROM _invitation
''';

/// A block is against the person, so any link of theirs sets one. It counts as an
/// answer only where declining would.
const _blockInviter =
    '''
WITH
_invitation AS (
  SELECT i.id, i.inviter_id, i.inviter_id = @userId AS own, $_invitationOpen AS open
  FROM invitations i
  WHERE i.token_hash = @tokenHash
),
_answering AS (
  SELECT id, inviter_id, open FROM _invitation WHERE NOT own
),
_person AS (
  $_answeringPerson
),
_block AS (
  INSERT INTO blocks (blocker_id, blocked_id)
  SELECT @userId, inviter_id
  FROM _answering
  ON CONFLICT DO NOTHING
  RETURNING 1
),
_response AS (
  INSERT INTO invitation_responses (invitation_id, user_id, response)
  SELECT id, @userId, 'declined'
  FROM _answering
  WHERE open
  ON CONFLICT (invitation_id, user_id) DO UPDATE
  SET response = 'declined', at = now()
  WHERE invitation_responses.response <> 'accepted'
  RETURNING 1
)
SELECT own FROM _invitation
''';

const _listBlocks = '''
SELECT b.blocked_id, b.created_at, p.username, p.avatar_url
FROM blocks b
JOIN profiles p ON p.id = b.blocked_id
WHERE b.blocker_id = @userId
  AND b.lifted_at IS NULL
  AND (@cursor::text IS NULL OR b.blocked_id < @cursor)
ORDER BY b.blocked_id DESC
LIMIT @limit
''';

/// A block ended what was live when it was set, so lifting one restores nothing. A row
/// left at `blocked` moves to `severed`, as lifting it there would.
const _liftBlock = '''
WITH
_lifted AS (
  UPDATE blocks
  SET lifted_at = now()
  WHERE blocker_id = @userId
    AND blocked_id = @blockedId
    AND lifted_at IS NULL
  RETURNING 1
)
UPDATE connections
SET status = 'severed', status_by = @userId
WHERE (initiator_id, target_id) IN ((@userId, @blockedId), (@blockedId, @userId))
  AND status = 'blocked'
  AND status_by = @userId
RETURNING id
''';
