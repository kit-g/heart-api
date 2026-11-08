part of '../db.dart';

/// One thread as one of its people sees it, `t` being the thread: who the other is,
/// when something last arrived, and what's unread. A reaction arrives but isn't
/// something to read. The last arrival is the newest
/// item in stored order, since a device's own time can be days old or years ahead.
const _threadAsSeen = '''
SELECT
  t.id,
  t.connection_id,
  t.cleared_at,
  t.cleared_by,
  other.id AS other_id,
  other.username AS other_name,
  other.avatar_url AS other_avatar,
  (
    SELECT i.created_at
    FROM thread_items i
    WHERE i.thread_id = t.id
    ORDER BY i.xid DESC, i.id DESC
    LIMIT 1
  ) AS last_at,
  (
    SELECT count(*)
    FROM thread_items i
    LEFT JOIN thread_reads r ON r.thread_id = t.id AND r.user_id = @userId
    WHERE i.thread_id = t.id
      AND i.sender_id IS DISTINCT FROM @userId
      AND i.kind <> 'reaction'
      AND (r.user_id IS NULL OR (i.xid, i.id) > (r.read_xid, r.read_id))
  ) AS unread
''';

const _threadOther = '''
LEFT JOIN profiles other
  ON other.id = CASE WHEN t.person_a = @userId THEN t.person_b ELSE t.person_a END
''';

/// Only for a connection that was accepted, whichever person it was made by, and
/// not for someone the other person blocked, who can't read one either. A thread
/// that exists is read rather than written: the insert's conflict clause is only
/// for two devices opening it at once.
const _openThread =
    '''
WITH
_connection AS (
  SELECT c.id, c.initiator_id, c.target_id
  FROM connections c
  WHERE c.id = @connectionId::uuid
    AND @userId IN (c.initiator_id, c.target_id)
    AND c.accepted_at IS NOT NULL
    AND NOT EXISTS (
      SELECT 1 FROM blocks b
      WHERE b.blocker_id = CASE WHEN c.initiator_id = @userId THEN c.target_id ELSE c.initiator_id END
        AND b.blocked_id = @userId
        AND b.lifted_at IS NULL
    )
),
_existing AS (
  SELECT t.*
  FROM threads t
  WHERE t.connection_id = (SELECT id FROM _connection)
),
_opened AS (
  INSERT INTO threads (connection_id, person_a, person_b)
  SELECT id, initiator_id, target_id
  FROM _connection
  WHERE NOT EXISTS (SELECT 1 FROM _existing)
  ON CONFLICT (connection_id) DO UPDATE
  SET connection_id = EXCLUDED.connection_id
  RETURNING *
)
$_threadAsSeen
FROM (
  SELECT * FROM _existing
  UNION ALL
  SELECT * FROM _opened
) t
$_threadOther
''';

const _threadParties = '''
SELECT
  CASE WHEN t.person_a = @senderId THEN t.person_b ELSE t.person_a END AS recipient_id,
  t.connection_id
FROM threads t
JOIN connections c ON c.id = t.connection_id
WHERE t.id = @threadId::uuid
  AND @senderId IN (t.person_a, t.person_b)
  AND c.status IN ('active', 'paused')
  AND NOT _blocked_between(t.person_a, t.person_b)
''';

const _threadItemColumns = '''
  id, thread_id, sender_id, kind, subject_type, subject_id, content, commitment, tag, tag_key, at, created_at, xid::text AS xid_text
''';

/// What stands in for [_threadItemColumns] in a row that only says something.
const _noThreadItem = 'NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL';

/// Writes only to a thread that can still take it, the same conditions the sender
/// was told about a moment ago, since a block could have landed in between, and
/// only under the sender's per-minute guard. When nothing was written or found,
/// the last row says which of those stopped it. With neither, the id is someone
/// else's, or a request still running is storing the same one.
const _addThreadItem =
    '''
WITH
_open AS (
  SELECT t.id
  FROM threads t
  JOIN connections c ON c.id = t.connection_id
  WHERE t.id = @threadId::uuid
    AND @senderId IN (t.person_a, t.person_b)
    AND c.status IN ('active', 'paused')
    AND NOT _blocked_between(t.person_a, t.person_b)
),
_recent AS (
  SELECT count(*) AS sent
  FROM thread_items
  WHERE sender_id = @senderId
    AND created_at > @createdAt::timestamptz - INTERVAL '1 minute'
),
_inserted AS (
  INSERT INTO thread_items
    (id, thread_id, sender_id, kind, subject_type, subject_id, content, commitment, tag, tag_key, at, created_at)
  SELECT
    @id::uuid, o.id, @senderId, @kind, @subjectType, @subjectId, @content, @commitment, @tag, @tagKey, @at, @createdAt
  FROM _open o
  WHERE (SELECT sent FROM _recent) < @perMinute
  ON CONFLICT (id) DO NOTHING
  RETURNING *
),
_stored AS (
  SELECT $_threadItemColumns, true AS created FROM _inserted
  UNION ALL
  SELECT $_threadItemColumns, false AS created
  FROM thread_items
  WHERE id = @id::uuid
    AND thread_id = @threadId::uuid
    AND sender_id = @senderId
    AND NOT EXISTS (SELECT 1 FROM _inserted)
)
SELECT *, NULL::boolean AS open, NULL::bigint AS sent FROM _stored
UNION ALL
SELECT $_noThreadItem, NULL, EXISTS (SELECT 1 FROM _open), (SELECT sent FROM _recent)
WHERE NOT EXISTS (SELECT 1 FROM _stored)
''';

const _listThreads =
    '''
$_threadAsSeen
FROM threads t
$_threadOther
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

/// A cursor at or past the transaction counter can't have come from this database:
/// it moved, and its new counter started lower. The cursor is stale.
const _cursorStale = '''
_cursor AS (
  SELECT coalesce(@xid::text::xid8 >= pg_snapshot_xmax(pg_current_snapshot()), false) AS stale
)
''';

/// Reads stop short of the oldest transaction still running, as the workout feed
/// does: past it, one still writing could land behind a reader who already moved on.
/// Going back keeps the same horizon, since a cursor taken there is where a forward
/// read starts. The last row stands alone when the thread isn't the reader's, or the
/// cursor is stale.
String _listThreadItems({required bool forward}) {
  final (after, order) = switch (forward) {
    true => ('(xid, id) > (@xid::text::xid8, @itemId::uuid)', 'xid, id'),
    false => ('(@xid::text IS NULL OR (xid, id) < (@xid::text::xid8, @itemId::uuid))', 'xid DESC, id DESC'),
  };
  return '''
WITH
$_threadReadable,
$_cursorStale
(
  SELECT $_threadItemColumns, false AS forbidden, false AS stale
  FROM thread_items
  WHERE thread_id = @threadId::uuid
    AND (SELECT readable FROM _readable)
    AND NOT (SELECT stale FROM _cursor)
    AND xid < pg_snapshot_xmin(pg_current_snapshot())
    AND $after
    AND (@subjectType::text IS NULL OR subject_type = @subjectType)
    AND (@subjectId::text IS NULL OR subject_id = @subjectId)
  ORDER BY $order
  LIMIT @limit
)
UNION ALL
SELECT $_noThreadItem, NOT r.readable, c.stale
FROM _readable r, _cursor c
WHERE NOT r.readable OR c.stale
''';
}

final _listThreadItemsForward = _listThreadItems(forward: true);

final _listThreadItemsBackward = _listThreadItems(forward: false);

/// Whoever can read the thread moves their position, as a read does. The one row
/// says whether they couldn't, or the cursor was stale, and then nothing moved.
const _markThreadRead =
    '''
WITH
$_threadReadable,
$_cursorStale,
_read AS (
  INSERT INTO thread_reads (thread_id, user_id, read_xid, read_id)
  SELECT @threadId::uuid, @userId, @xid::text::xid8, @itemId::uuid
  WHERE (SELECT readable FROM _readable)
    AND NOT (SELECT stale FROM _cursor)
  ON CONFLICT (thread_id, user_id) DO UPDATE
  SET read_xid = EXCLUDED.read_xid, read_id = EXCLUDED.read_id
  WHERE (EXCLUDED.read_xid, EXCLUDED.read_id) > (thread_reads.read_xid, thread_reads.read_id)
  RETURNING thread_id
)
SELECT NOT r.readable AS forbidden, c.stale
FROM _readable r, _cursor c
''';

/// Either person, whatever the connection's status, including across a block. No
/// row when the thread isn't the caller's.
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
/// A note the coach already holds is edited whatever became of its connection, so
/// one about a client who deleted their account still changes. The last row stands
/// alone when the id is another coach's.
const _saveNote = '''
WITH
_edited AS (
  UPDATE coach_notes
  SET content = @content, updated_at = now()
  WHERE id = @id::uuid
    AND coach_id = @coachId
  RETURNING id, connection_id, content, updated_at
),
_written AS (
  INSERT INTO coach_notes (id, coach_id, connection_id, content)
  SELECT @id::uuid, @coachId, c.id, @content
  FROM connections c
  WHERE c.id = @connectionId::uuid
    AND (
      (c.initiator_id = @coachId AND c.initiator_role = 'COACH')
      OR (c.target_id = @coachId AND c.target_role = 'COACH')
    )
    AND NOT EXISTS (SELECT 1 FROM _edited)
  ON CONFLICT (id) DO UPDATE
  SET content = EXCLUDED.content, updated_at = now()
  WHERE coach_notes.coach_id = EXCLUDED.coach_id
  RETURNING id, connection_id, content, updated_at
)
SELECT id, connection_id, content, updated_at, false AS taken FROM _edited
UNION ALL
SELECT id, connection_id, content, updated_at, false AS taken FROM _written
UNION ALL
SELECT NULL, NULL, NULL, NULL, true
WHERE NOT EXISTS (SELECT 1 FROM _edited)
  AND NOT EXISTS (SELECT 1 FROM _written)
  AND EXISTS (SELECT 1 FROM coach_notes WHERE id = @id::uuid AND coach_id <> @coachId)
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
