part of '../db.dart';

const _saveCoachProgram =
    '''
WITH
_count AS (
  SELECT count(*) AS n FROM library_programs WHERE coach_id = @coachId
),
_saved AS (
  INSERT INTO library_programs (id, coach_id, name)
  SELECT @id::uuid, @coachId, @name
  FROM _count
  WHERE n < $_maxCoachPrograms
     OR EXISTS (SELECT 1 FROM library_programs WHERE id = @id::uuid AND coach_id = @coachId)
  ON CONFLICT (id) DO UPDATE
  SET name = EXCLUDED.name, version = library_programs.version + 1, updated_at = now()
  WHERE library_programs.coach_id = EXCLUDED.coach_id
  RETURNING id, name, version, updated_at
),
_version AS (
  INSERT INTO library_program_versions (library_program_id, version, body)
  SELECT id, version, @body::jsonb
  FROM _saved
  RETURNING body
)
SELECT s.id, s.name, s.version, s.updated_at, v.body
FROM _saved s, _version v
''';

const _listCoachPrograms = '''
SELECT id, name, version, updated_at
FROM library_programs
WHERE coach_id = @coachId
  AND (@cursor::uuid IS NULL OR id < @cursor::uuid)
ORDER BY id DESC
LIMIT @limit
''';

const _getCoachProgram = '''
SELECT l.id, l.name, l.version, l.updated_at, v.body
FROM library_programs l
JOIN library_program_versions v ON v.library_program_id = l.id AND v.version = l.version
WHERE l.id = @id::uuid
  AND l.coach_id = @coachId
''';

const _deleteCoachProgram = '''
DELETE FROM library_programs
WHERE id = @id::uuid
  AND coach_id = @coachId
RETURNING id
''';

const _listCoachProgramHolders = '''
SELECT
  p.connection_id,
  p.user_id AS student_id,
  profile.username,
  profile.avatar_url,
  p.id AS program_id,
  p.library_version
FROM programs p
JOIN library_programs l ON l.id = p.library_program_id
JOIN profiles profile ON profile.id = p.user_id
WHERE l.id = @id::uuid
  AND l.coach_id = @coachId
ORDER BY profile.username
''';

/// A student is who's across an active coach row from this coach, under no block.
const _coachSendContext = '''
SELECT
  l.version,
  v.body,
  c.student_id,
  (
    SELECT p.id
    FROM programs p
    WHERE p.user_id = c.student_id
      AND p.library_program_id = l.id
  ) AS existing_id,
  EXISTS (
    SELECT 1
    FROM programs p
    WHERE p.user_id = c.student_id
      AND NOT p.archived
  ) AS on_something
FROM library_programs l
JOIN library_program_versions v ON v.library_program_id = l.id AND v.version = l.version
LEFT JOIN LATERAL (
  SELECT
    CASE WHEN x.initiator_id = @coachId THEN x.target_id ELSE x.initiator_id END AS student_id
  FROM connections x
  WHERE x.id = @connectionId::uuid
    AND x.status = 'active'
    AND (
      (x.initiator_id = @coachId AND x.initiator_role = 'COACH')
      OR (x.target_id = @coachId AND x.target_role = 'COACH')
    )
    AND NOT _blocked_between(x.initiator_id, x.target_id)
) c ON true
WHERE l.id = @id::uuid
  AND l.coach_id = @coachId
''';

/// Any exercise the body names, as the one the student has: their own by that name
/// first, then the library's, and otherwise a copy made for them. An id that isn't
/// an exercise, such as a session's, finds no row and stays out of the answer. So does
/// someone else's private exercise: a coach can pass on only what they can see.
const _matchExercisesForStudent = '''
WITH
_sources AS (
  SELECT e.*
  FROM exercises e
  WHERE e.id = ANY (@ids::uuid[])
    AND (e.user_id IS NULL OR e.user_id = @coachId)
),
_matched AS (
  SELECT
    s.id AS source_id,
    s.name,
    (
      SELECT e2.id FROM exercises e2
      WHERE e2.name = s.name
        AND (e2.user_id IS NULL OR e2.user_id = @studentId)
      ORDER BY e2.user_id NULLS LAST
      LIMIT 1
    ) AS resolved_id
  FROM _sources s
),
_copied AS (
  INSERT INTO exercises (name, category, target, instructions, asset, thumbnail, muscles, movement, health, user_id)
  SELECT DISTINCT ON (s.name)
    s.name, s.category, s.target, s.instructions, s.asset, s.thumbnail, s.muscles, s.movement, s.health, @studentId
  FROM _sources s
  JOIN _matched m ON m.source_id = s.id
  WHERE m.resolved_id IS NULL
  RETURNING id, name
)
SELECT m.source_id, coalesce(m.resolved_id, c.id) AS exercise_id
FROM _matched m
LEFT JOIN _copied c ON c.name = m.name AND m.resolved_id IS NULL
''';

const _invitationProgram = '''
SELECT library_program_id FROM invitations WHERE token_hash = @tokenHash
''';

const _attachInvitationProgram = '''
UPDATE invitations i
SET library_program_id = l.id
FROM library_programs l
WHERE i.id = @invitationId::uuid
  AND i.inviter_id = @coachId
  AND l.id = @programId::uuid
  AND l.coach_id = @coachId
RETURNING i.id
''';

const _startProgram = '''
UPDATE programs
SET waiting_since = NULL
WHERE id = @programId::uuid
  AND user_id = @userId
RETURNING id
''';
