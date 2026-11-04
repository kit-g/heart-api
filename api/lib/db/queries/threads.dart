part of '../db.dart';

/// Only for a connection that was accepted, and whichever person it was made by.
const _openThread = '''
WITH
_connection AS (
  SELECT id, initiator_id, target_id
  FROM connections
  WHERE id = @connectionId::uuid
    AND @userId IN (initiator_id, target_id)
    AND accepted_at IS NOT NULL
),
_opened AS (
  INSERT INTO threads (connection_id, person_a, person_b)
  SELECT id, initiator_id, target_id
  FROM _connection
  ON CONFLICT (connection_id) DO UPDATE
  SET connection_id = EXCLUDED.connection_id
  RETURNING id, connection_id, person_a, person_b, cleared_at, cleared_by
)
SELECT
  id, connection_id, cleared_at, cleared_by,
  CASE WHEN person_a = @userId THEN person_b ELSE person_a END AS other_id
FROM _opened
''';

const _threadParties = '''
SELECT CASE WHEN t.person_a = @senderId THEN t.person_b ELSE t.person_a END AS recipient_id
FROM threads t
JOIN connections c ON c.id = t.connection_id
WHERE t.id = @threadId::uuid
  AND @senderId IN (t.person_a, t.person_b)
  AND c.status = 'active'
  AND NOT _blocked_between(t.person_a, t.person_b)
''';

/// Writes only to a thread that can still take it, the same conditions the sender
/// was told about a moment ago, since a block could have landed in between.
const _threadItemColumns = '''
  id, thread_id, sender_id, kind, subject_type, subject_id, content, commitment, tag, tag_key, at, created_at, xid::text AS xid_text
''';

const _addThreadItem =
    '''
WITH
_open AS (
  SELECT t.id
  FROM threads t
  JOIN connections c ON c.id = t.connection_id
  WHERE t.id = @threadId::uuid
    AND @senderId IN (t.person_a, t.person_b)
    AND c.status = 'active'
    AND NOT _blocked_between(t.person_a, t.person_b)
),
_inserted AS (
  INSERT INTO thread_items
    (id, thread_id, sender_id, kind, subject_type, subject_id, content, commitment, tag, tag_key, at, created_at)
  SELECT
    @id::uuid, o.id, @senderId, @kind, @subjectType, @subjectId, @content, @commitment, @tag, @tagKey, @at, @createdAt
  FROM _open o
  ON CONFLICT (id) DO NOTHING
  RETURNING *
)
SELECT $_threadItemColumns, true AS created FROM _inserted
UNION ALL
SELECT $_threadItemColumns, false AS created
FROM thread_items
WHERE id = @id::uuid
  AND thread_id = @threadId::uuid
  AND sender_id = @senderId
  AND NOT EXISTS (SELECT 1 FROM _inserted)
''';

const _listThreads = '''
SELECT
  t.id,
  t.connection_id,
  t.cleared_at,
  t.cleared_by,
  other.id AS other_id,
  other.username AS other_name,
  other.avatar_url AS other_avatar,
  (SELECT max(i.at) FROM thread_items i WHERE i.thread_id = t.id) AS last_at,
  (
    SELECT count(*)
    FROM thread_items i
    LEFT JOIN thread_reads r ON r.thread_id = t.id AND r.user_id = @userId
    WHERE i.thread_id = t.id
      AND i.sender_id IS DISTINCT FROM @userId
      AND (r.user_id IS NULL OR (i.xid, i.id) > (r.read_xid, r.read_id))
  ) AS unread
FROM threads t
LEFT JOIN profiles other
  ON other.id = CASE WHEN t.person_a = @userId THEN t.person_b ELSE t.person_a END
WHERE @userId IN (t.person_a, t.person_b)
  AND NOT EXISTS (
    SELECT 1 FROM blocks b
    WHERE b.blocker_id = other.id
      AND b.blocked_id = @userId
      AND b.lifted_at IS NULL
  )
ORDER BY last_at DESC NULLS LAST, t.id DESC
''';

/// Someone the other person blocked can't read, and the blocker can.
const _threadReadable = '''
_readable AS (
  SELECT EXISTS (
    SELECT 1
    FROM threads t
    WHERE t.id = @threadId::uuid
      AND @userId IN (t.person_a, t.person_b)
      AND NOT EXISTS (
        SELECT 1 FROM blocks b
        WHERE b.blocker_id = CASE WHEN t.person_a = @userId THEN t.person_b ELSE t.person_a END
          AND b.blocked_id = @userId
          AND b.lifted_at IS NULL
      )
  ) AS readable
)
''';

/// Stops short of the oldest transaction still running, as the workout feed does:
/// past it, one still writing could land behind a reader who already moved on.
const _listThreadItemsForward =
    '''
WITH $_threadReadable
(
  SELECT $_threadItemColumns, false AS forbidden
  FROM thread_items
  WHERE thread_id = @threadId::uuid
    AND (SELECT readable FROM _readable)
    AND xid < pg_snapshot_xmin(pg_current_snapshot())
    AND (xid, id) > (@xid::text::xid8, @itemId::uuid)
    AND (@subjectType::text IS NULL OR subject_type = @subjectType)
    AND (@subjectId::text IS NULL OR subject_id = @subjectId)
  ORDER BY xid, id
  LIMIT @limit
)
UNION ALL
SELECT NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, true
FROM _readable
WHERE NOT readable
''';

/// The same horizon as going forward: a cursor taken from here is where a forward read
/// starts, and one past a transaction still writing would skip what it writes.
const _listThreadItemsBackward =
    '''
WITH $_threadReadable
(
  SELECT $_threadItemColumns, false AS forbidden
  FROM thread_items
  WHERE thread_id = @threadId::uuid
    AND (SELECT readable FROM _readable)
    AND xid < pg_snapshot_xmin(pg_current_snapshot())
    AND (@xid::text IS NULL OR (xid, id) < (@xid::text::xid8, @itemId::uuid))
    AND (@subjectType::text IS NULL OR subject_type = @subjectType)
    AND (@subjectId::text IS NULL OR subject_id = @subjectId)
  ORDER BY xid DESC, id DESC
  LIMIT @limit
)
UNION ALL
SELECT NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, true
FROM _readable
WHERE NOT readable
''';

const _markThreadRead = '''
INSERT INTO thread_reads (thread_id, user_id, read_xid, read_id)
SELECT t.id, @userId, @xid::text::xid8, @itemId::uuid
FROM threads t
WHERE t.id = @threadId::uuid
  AND @userId IN (t.person_a, t.person_b)
ON CONFLICT (thread_id, user_id) DO UPDATE
SET read_xid = EXCLUDED.read_xid, read_id = EXCLUDED.read_id
WHERE (EXCLUDED.read_xid, EXCLUDED.read_id) > (thread_reads.read_xid, thread_reads.read_id)
RETURNING thread_id
''';

/// Either person, whatever the connection's status, including across a block.
const _clearThread = '''
WITH
_cleared AS (
  UPDATE threads
  SET cleared_at = now(), cleared_by = @userId
  WHERE id = @threadId::uuid
    AND @userId IN (person_a, person_b)
  RETURNING id, CASE WHEN person_a = @userId THEN person_b ELSE person_a END AS other_id
),
_items AS (
  DELETE FROM thread_items
  WHERE thread_id IN (SELECT id FROM _cleared)
  RETURNING 1
),
_reads AS (
  DELETE FROM thread_reads
  WHERE thread_id IN (SELECT id FROM _cleared)
  RETURNING 1
)
SELECT id, other_id FROM _cleared
''';

/// A coach's own, on a client of theirs: the client has no way to know one exists.
const _saveNote = '''
INSERT INTO coach_notes (id, coach_id, connection_id, content)
SELECT @id::uuid, @coachId, c.id, @content
FROM connections c
WHERE c.id = @connectionId::uuid
  AND (
    (c.initiator_id = @coachId AND c.initiator_role = 'COACH')
    OR (c.target_id = @coachId AND c.target_role = 'COACH')
  )
ON CONFLICT (id) DO UPDATE
SET content = EXCLUDED.content, updated_at = now()
WHERE coach_notes.coach_id = EXCLUDED.coach_id
RETURNING id, connection_id, content, updated_at
''';

const _listNotes = '''
SELECT id, connection_id, content, updated_at
FROM coach_notes
WHERE coach_id = @coachId
  AND (@connectionId::uuid IS NULL OR connection_id = @connectionId::uuid)
  AND (@cursor::uuid IS NULL OR id < @cursor::uuid)
ORDER BY id DESC
LIMIT @limit
''';

const _deleteNote = '''
DELETE FROM coach_notes
WHERE id = @id::uuid
  AND coach_id = @coachId
RETURNING id
''';

const _fileReport = '''
INSERT INTO reports (reporter_id, reported_id, connection_id, reason, sealed, verified)
VALUES (@reporterId, @reportedId, @connectionId::uuid, @reason, @sealed, @verified)
RETURNING id
''';
