part of '../db.dart';

const _recordProgramChange = '''
INSERT INTO program_changes (id, program_id, session_id, actor_id, kind, revision, before, after, links, stale)
VALUES (
  @id::uuid, @programId::uuid, @sessionId::uuid, @actorId, @kind, @revision, @before::jsonb, @after::jsonb, @links::jsonb, @stale
)
RETURNING id
''';

/// Holds a copy's session while it changes. No row means it isn't a session of a copy,
/// or of the program a coach named. The lock serializes writers, and leaves foreign
/// keys naming the row, such as a workout's, free to check it meanwhile. What the writer is up against is the next statement:
/// one that waited for this lock would still see the world from before it waited, and
/// miss the very write it queued behind.
const _lockCopySession = '''
SELECT t.program_id
FROM templates t
JOIN programs p ON p.id = t.program_id
WHERE t.id = @sessionId::uuid
  AND t.user_id = @ownerId
  AND p.coach_id IS NOT NULL
  AND (@programId::uuid IS NULL OR t.program_id = @programId::uuid)
FOR NO KEY UPDATE OF t
''';

/// Someone else having changed it since the writer's base is a conflict, and the writer's
/// own changes aren't, so two queued edits both land.
const _copySessionStanding = '''
SELECT
  t.revision,
  @changeId::uuid IS NOT NULL
    AND EXISTS (SELECT 1 FROM program_changes c WHERE c.id = @changeId::uuid) AS replayed,
  @baseRevision::int IS NOT NULL
    AND EXISTS (
      SELECT 1
      FROM program_changes c
      WHERE c.program_id = t.program_id
        AND c.session_id = t.id
        AND c.revision > @baseRevision::int
        AND c.actor_id IS DISTINCT FROM @actorId
    ) AS conflict
FROM templates t
WHERE t.id = @sessionId::uuid
''';

/// As for a session: the lock, then in a statement of its own what it's up against.
const _lockCopy = '''
SELECT p.id
FROM programs p
WHERE p.id = @programId::uuid
  AND p.user_id = @ownerId
  AND p.coach_id IS NOT NULL
FOR NO KEY UPDATE OF p
''';

const _copyStanding = '''
SELECT
  p.revision,
  @changeId::uuid IS NOT NULL
    AND EXISTS (SELECT 1 FROM program_changes c WHERE c.id = @changeId::uuid) AS replayed,
  @baseRevision::int IS NOT NULL
    AND EXISTS (
      SELECT 1
      FROM program_changes c
      WHERE c.program_id = p.id
        AND c.session_id IS NULL
        AND c.revision > @baseRevision::int
        AND c.actor_id IS DISTINCT FROM @actorId
    ) AS conflict
FROM programs p
WHERE p.id = @programId::uuid
''';

const _templateIdTaken = '''
SELECT 1 FROM templates WHERE id = @id::uuid
''';

/// A session put back or added over a base: someone else changed it since, a
/// deletion included, which leaves no session for [_copySessionStanding] to read.
const _goneSessionConflict = '''
SELECT max(c.revision)
FROM program_changes c
WHERE c.program_id = @programId::uuid
  AND c.session_id = @sessionId::uuid
  AND c.revision > @baseRevision::int
  AND c.actor_id IS DISTINCT FROM @actorId
''';

/// What a session says, without its revision or who it's quoted as: equal before
/// and after a write means the write changed nothing.
const _sessionContent = '''
SELECT ((to_jsonb(t) - 'revision' - 'assigned_by') || jsonb_build_object('exercises', _template_exercises(t.id)))::text
FROM templates t
WHERE t.id = @sessionId::uuid
''';

/// As [_sessionContent], for a program's own fields.
const _programContent = '''
SELECT (to_jsonb(p) - 'revision' - 'updated_at')::text
FROM programs p
WHERE p.id = @programId::uuid
''';

/// Someone else writing a session makes its words theirs too, so the assistant
/// reads them quoted even on a session the student added.
const _bumpSessionRevision = '''
UPDATE templates
SET
  revision = revision + 1,
  assigned_by = CASE WHEN user_id = @actorId THEN assigned_by ELSE coalesce(assigned_by, @actorId) END
WHERE id = @sessionId::uuid
RETURNING revision
''';

const _bumpProgramRevision = '''
UPDATE programs
SET revision = revision + 1
WHERE id = @programId::uuid
RETURNING revision
''';

/// A deletion clears these, so a snapshot has to say what they were.
const _sessionLinks = '''
SELECT jsonb_build_object(
  'workouts', coalesce((SELECT jsonb_agg(id) FROM workouts WHERE template_id = @sessionId::uuid AND user_id = @ownerId), '[]'::jsonb),
  'skips', coalesce((SELECT jsonb_agg(id) FROM skips WHERE template_id = @sessionId::uuid AND user_id = @ownerId), '[]'::jsonb)
)
''';

const _deleteSession = '''
DELETE FROM templates
WHERE id = @sessionId::uuid
  AND user_id = @ownerId
RETURNING id, program_id
''';

/// Links a session put back to what named it, and to the copy it left. Its revision
/// carries on from its history, which a write's base is compared against.
const _restoreSessionLinks = '''
WITH
_workouts AS (
  UPDATE workouts
  SET template_id = @sessionId::uuid
  WHERE id = ANY (@workouts::uuid[])
    AND user_id = @ownerId
  RETURNING 1
),
_skips AS (
  UPDATE skips
  SET template_id = @sessionId::uuid
  WHERE id = ANY (@skips::uuid[])
    AND user_id = @ownerId
  RETURNING 1
)
UPDATE templates t
SET
  assigned_by = p.coach_id,
  revision = 1 + coalesce(
    (
      SELECT max(c.revision)
      FROM program_changes c
      WHERE c.program_id = p.id
        AND c.session_id = t.id
    ),
    0
  )
FROM programs p
WHERE t.id = @sessionId::uuid
  AND p.id = @programId::uuid
RETURNING t.revision
''';

const _programChangeColumns = '''
  id, program_id, session_id, actor_id, kind, revision, before, after, stale, at, xid::text AS xid_text
''';

/// Stops short of the oldest transaction still running, as the workout feed does,
/// and like it refuses a cursor at or past the counter: one from before the
/// database moved to a cluster that counts from lower (the row with `stale_cursor`).
const _listProgramChanges =
    '''
WITH
_check AS (
  SELECT @xid::text IS NOT NULL
         AND @xid::text::xid8 >= pg_snapshot_xmax(pg_current_snapshot()) AS stale_cursor
),
_page AS (
  SELECT $_programChangeColumns
  FROM program_changes
  WHERE program_id = @programId::uuid
    AND EXISTS (SELECT 1 FROM programs p WHERE p.id = @programId::uuid AND p.user_id = @ownerId)
    AND xid < pg_snapshot_xmin(pg_current_snapshot())
    AND (@xid::text IS NULL OR (xid, id) > (@xid::text::xid8, @changeId::uuid))
  ORDER BY xid, id
  LIMIT 500
)
SELECT c.stale_cursor, p.*
FROM _check c
LEFT JOIN _page p ON NOT c.stale_cursor
ORDER BY p.xid_text::xid8, p.id
''';

const _getProgramChange =
    '''
SELECT $_programChangeColumns, links
FROM program_changes
WHERE id = @changeId::uuid
  AND program_id = @programId::uuid
  AND EXISTS (SELECT 1 FROM programs p WHERE p.id = @programId::uuid AND p.user_id = @ownerId)
''';

/// A coach reads what they sent while they hold a coach's view, paused included,
/// and writes only across the live connection it came through.
const _copyAccess = '''
WITH
_copy AS (
  SELECT connection_id
  FROM programs
  WHERE id = @programId::uuid
    AND user_id = @studentId
    AND coach_id = @coachId
)
SELECT
  EXISTS (SELECT 1 FROM _copy)
    AND (_relation(@coachId, @studentId)).scope IS NOT DISTINCT FROM 'coach' AS readable,
  EXISTS (
    SELECT 1
    FROM _copy p
    JOIN connections c ON c.id = p.connection_id
    WHERE c.status = 'active'
      AND NOT _blocked_between(@coachId, @studentId)
  ) AS writable
''';

const _listCopies =
    '''
SELECT $_programColumns
FROM programs p
WHERE p.user_id = @studentId
  AND p.coach_id = @coachId
  AND (_relation(@coachId, @studentId)).scope = 'coach'
ORDER BY p.id
''';

const _listVisibleMarks = '''
WITH _rel AS (
  SELECT _relation(@readerId, @ownerId) AS r
)
SELECT template_id, started_at AS at, true AS is_workout
FROM workouts
WHERE program_id = @programId::uuid
  AND user_id = @ownerId
  AND started_at IS NOT NULL
  AND _readable_at((SELECT r FROM _rel), started_at, hidden_at)
UNION ALL
SELECT template_id, at, false AS is_workout
FROM skips
WHERE program_id = @programId::uuid
  AND user_id = @ownerId
  AND _readable_at((SELECT r FROM _rel), at, NULL)
''';

const _getCopyIds = '''
SELECT library_ids
FROM programs
WHERE id = @programId::uuid
  AND user_id = @ownerId
''';

const _setCopyVersion = '''
UPDATE programs
SET library_version = @version, library_ids = @ids::jsonb
WHERE id = @programId::uuid
  AND user_id = @ownerId
RETURNING id
''';

/// Who to tell: the coach only while they still read the copy as its coach.
const _otherSideOf = '''
SELECT CASE WHEN user_id = @actorId THEN coach_id ELSE user_id END
FROM programs
WHERE id = @programId::uuid
  AND coach_id IS NOT NULL
  AND (_relation(coach_id, user_id)).scope IS NOT DISTINCT FROM 'coach'
''';

/// One row either way, saying whether the workout is theirs.
const _saveWorkoutPlan = '''
WITH
_workout AS (
  SELECT id
  FROM workouts
  WHERE id = @workoutId::uuid
    AND user_id = @userId
    AND (@loggedBy::text IS NULL OR logged_by = @loggedBy)
),
_saved AS (
  INSERT INTO workout_plans (workout_id, plan)
  SELECT id, @plan::jsonb
  FROM _workout
  ON CONFLICT (workout_id) DO NOTHING
  RETURNING 1
)
SELECT EXISTS (SELECT 1 FROM _workout)
''';

const _getWorkoutPlan = '''
SELECT p.plan
FROM workout_plans p
JOIN workouts w ON w.id = p.workout_id
WHERE w.id = @workoutId::uuid
  AND w.user_id = @ownerId
  AND _readable_at(_relation(@readerId, @ownerId), w.started_at, w.hidden_at)
''';

const _coachCanLog = '''
SELECT (r).scope IS NOT DISTINCT FROM 'coach' AND (r).active AS allowed
FROM (SELECT _relation(@coachId, @studentId) AS r) rel
''';
