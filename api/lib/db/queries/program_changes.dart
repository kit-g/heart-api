part of '../db.dart';

const _recordProgramChange = '''
INSERT INTO program_changes (id, program_id, session_id, actor_id, kind, revision, before, after, links, stale)
VALUES (
  @id::uuid, @programId::uuid, @sessionId::uuid, @actorId, @kind, @revision, @before::jsonb, @after::jsonb, @links::jsonb, @stale
)
RETURNING id
''';

/// Holds a copy's session while it changes. No row means it isn't a session of a copy,
/// or of the program a coach named. What the writer is up against is the next statement:
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
FOR UPDATE OF t
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
FOR UPDATE OF p
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

const _bumpSessionRevision = '''
UPDATE templates
SET revision = revision + 1
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
RETURNING id
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

/// Stops short of the oldest transaction still running, as the workout feed does.
const _listProgramChanges =
    '''
SELECT $_programChangeColumns
FROM program_changes
WHERE program_id = @programId::uuid
  AND EXISTS (SELECT 1 FROM programs p WHERE p.id = @programId::uuid AND p.user_id = @ownerId)
  AND xid < pg_snapshot_xmin(pg_current_snapshot())
  AND (@xid::text IS NULL OR (xid, id) > (@xid::text::xid8, @changeId::uuid))
ORDER BY xid, id
LIMIT 500
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

const _otherSideOf = '''
SELECT CASE WHEN user_id = @actorId THEN coach_id ELSE user_id END
FROM programs
WHERE id = @programId::uuid
  AND coach_id IS NOT NULL
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
