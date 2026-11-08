part of '../db.dart';

/// Its sessions name their coach as a shared template does, so anything that reads
/// a session knows the words are someone else's.
const _markProgramCopy = '''
WITH
_copy AS (
  UPDATE programs
  SET
    coach_id = @coachId,
    connection_id = @connectionId::uuid,
    library_program_id = @libraryProgramId::uuid,
    library_version = @libraryVersion,
    library_ids = @libraryIds::jsonb,
    waiting_since = CASE WHEN @waits::boolean THEN now() END
  WHERE id = @id::uuid
  RETURNING id
)
UPDATE templates
SET assigned_by = @coachId
WHERE program_id IN (SELECT id FROM _copy)
RETURNING id
''';

/// The columns `Program.fromRow` reads, from a row aliased `p`. `sessions` is
/// the program's templates in their order, the same `(order_index, id)` the
/// template list walks.
/// `joined` says when each one joined the program.
const _programColumns = '''
  p.id,
  p.name,
  p.note,
  p.source,
  p.per_week,
  p.days,
  p.weeks,
  p.rules,
  p.constraint_key,
  p.deload,
  p.phases,
  p.tests,
  p.archived,
  p.created_at,
  coalesce(
    (
      SELECT array_agg(t.id ORDER BY t.order_index, t.id)
      FROM templates t
      WHERE t.program_id = p.id
    ),
    '{}'
  ) AS sessions,
  (
    SELECT jsonb_object_agg(t.id, t.joined_program_at)
    FROM templates t
    WHERE t.program_id = p.id
  ) AS joined,
  p.coach_id,
  (SELECT username FROM profiles coach WHERE coach.id = p.coach_id) AS coach_name,
  p.waiting_since,
  p.revision,
  (
    SELECT jsonb_object_agg(t.id, t.revision)
    FROM templates t
    WHERE t.program_id = p.id
      AND p.coach_id IS NOT NULL
  ) AS session_revisions
''';

/// Archived ones included: the cap counts them, so the list stays small, and
/// the app needs both to sync.
const _listPrograms =
    '''
SELECT $_programColumns
FROM programs p
WHERE p.user_id = @userId
ORDER BY p.id
''';

const _getProgram =
    '''
SELECT $_programColumns
FROM programs p
WHERE p.id = @id::uuid
  AND p.user_id = @userId
''';

/// A user keeps at most this many programs, archived ones included. The ceiling
/// guards the table, not anyone's training.
const _maxPrograms = 100;

// Idempotent create, as `_createGoal`: an id the caller owns returns that
// program with `created = false` and never counts against the cap; an id owned
// by someone else reaches the INSERT and trips `programs_pkey` (403 id_taken)
// even at the cap. An empty result is the cap.
const _createProgram =
    '''
WITH
_by_id AS (
  SELECT id
  FROM programs
  WHERE id = @id::uuid
    AND user_id = @userId
),
_foreign AS (
  SELECT 1
  FROM programs
  WHERE id = @id::uuid
    AND user_id <> @userId
),
_ins AS (
  INSERT INTO programs (id, user_id, name, note, source, per_week, days, weeks, rules, constraint_key, deload, phases, tests)
  SELECT
    coalesce(@id::uuid, uuidv7()),
    @userId,
    @name,
    @note,
    @source,
    @perWeek::smallint,
    @days::smallint[],
    @weeks::smallint,
    @rules::jsonb,
    @constraintKey,
    @deload::jsonb,
    @phases::jsonb,
    @tests::jsonb
  WHERE NOT EXISTS (SELECT 1 FROM _by_id)
    AND (
      EXISTS (SELECT 1 FROM _foreign)
      OR (SELECT count(*) FROM programs WHERE user_id = @userId) < $_maxPrograms
    )
  RETURNING id
)
SELECT id, true AS created FROM _ins
UNION ALL
SELECT id, false AS created FROM _by_id
WHERE NOT EXISTS (SELECT 1 FROM _ins)
''';

/// Files the caller's own existing templates into a new program as its
/// sessions (heart-api#244): a program made from a folder keeps the templates
/// it was made of instead of copying them. `@sessions` is `[{id, order_index,
/// joined}]`, one entry per id. Each template takes its place, which is also
/// its place in its folder, since both orders are `order_index`; its name,
/// body, note and folder stay. One already in another program moves, as a
/// template edit naming the program would move it. A null `joined` leaves the
/// stamp to the database's clock. An id that isn't the caller's template
/// matches nothing and is left to the insert, which refuses a foreign one.
const _joinProgram = '''
UPDATE templates t
SET
  program_id = @programId::uuid,
  order_index = s.order_index,
  joined_program_at = s.joined
FROM jsonb_to_recordset(@sessions::jsonb) AS s(id uuid, order_index int, joined timestamptz)
WHERE t.id = s.id
  AND t.user_id = @userId
RETURNING t.id
''';

/// A full replace of the program's own fields. Its sessions are templates and
/// change through the template routes, never here.
const _replaceProgram =
    '''
WITH
_updated AS (
  UPDATE programs
  SET
    name = @name,
    note = @note,
    per_week = @perWeek::smallint,
    days = @days::smallint[],
    weeks = @weeks::smallint,
    rules = @rules::jsonb,
    constraint_key = @constraintKey,
    deload = @deload::jsonb,
    phases = @phases::jsonb,
    tests = @tests::jsonb,
    archived = @archived::boolean,
    updated_at = now()
  WHERE id = @id::uuid
    AND user_id = @userId
  RETURNING *
)
SELECT $_programColumns
FROM _updated p
''';

/// The other way out of deleting a program: its templates stay, as plain ones.
/// Run before `_deleteProgram`, in the same transaction.
const _detachProgramTemplates = '''
UPDATE templates
SET program_id = NULL
WHERE program_id = @id::uuid
  AND user_id = @userId
''';

/// Deleting a program deletes the templates still attached to it.
const _deleteProgram = '''
DELETE FROM programs
WHERE id = @id::uuid
  AND user_id = @userId
''';

/// A program's steps in the order they were taken. Someone else's program
/// reads as one with none.
const _listProgramActions = '''
SELECT id, program_id, kind, week, from_exercise, to_exercise, exercise_id, slot, stage, workout_id, at
FROM program_actions
WHERE program_id = @programId::uuid
  AND user_id = @userId
ORDER BY at, id
''';

/// A program keeps at most this many steps, and this many bases: years of use,
/// and a ceiling on what a fold reads.
const _maxProgramActions = 1000;

const _maxProgramBases = 5000;

// Idempotent on the id, as the other creates. A program that isn't the
// caller's trips program_actions_program_fk (404 unknown_program). An empty
// result is the cap, or an advance naming a workout the caller doesn't own:
// the db layer tells which.
const _createProgramAction =
    '''
WITH
_by_id AS (
  SELECT id, program_id, kind, week, from_exercise, to_exercise, exercise_id, slot, stage, workout_id, at
  FROM program_actions
  WHERE id = @id::uuid
    AND user_id = @userId
),
_ins AS (
  INSERT INTO program_actions (
    id, user_id, program_id, kind, week, from_exercise, to_exercise, exercise_id, slot, stage, workout_id, at
  )
  SELECT
    coalesce(@id::uuid, uuidv7()),
    @userId,
    @programId::uuid,
    @kind,
    @week::smallint,
    @from::uuid,
    @to::uuid,
    @exercise::uuid,
    @slot::uuid,
    @stage::smallint,
    @workoutId::uuid,
    @at::timestamptz
  WHERE NOT EXISTS (SELECT 1 FROM _by_id)
    AND (
      @workoutId::uuid IS NULL
      OR EXISTS (SELECT 1 FROM workouts WHERE id = @workoutId::uuid AND user_id = @userId)
    )
    AND (SELECT count(*) FROM program_actions WHERE program_id = @programId::uuid) < $_maxProgramActions
  RETURNING id, program_id, kind, week, from_exercise, to_exercise, exercise_id, slot, stage, workout_id, at
)
SELECT id, program_id, kind, week, from_exercise, to_exercise, exercise_id, slot, stage, workout_id, at, true AS created FROM _ins
UNION ALL
SELECT id, program_id, kind, week, from_exercise, to_exercise, exercise_id, slot, stage, workout_id, at, false AS created FROM _by_id
WHERE NOT EXISTS (SELECT 1 FROM _ins)
''';

/// Whether the caller owns a workout: why an advance or a stage wrote nothing, asked only
/// when it didn't.
const _ownsWorkout = '''
SELECT 1
FROM workouts
WHERE id = @workoutId::uuid
  AND user_id = @userId
''';

const _deleteProgramAction = '''
DELETE FROM program_actions
WHERE id = @id::uuid
  AND program_id = @programId::uuid
  AND user_id = @userId
''';

/// Every base of a program, oldest first: the latest per exercise is current.
const _listProgramBases = '''
SELECT id, program_id, exercise_id, slot, value, workout_id, action_id, at
FROM program_bases
WHERE program_id = @programId::uuid
  AND user_id = @userId
ORDER BY at, id
''';

/// A workout a coach may move a base by: one they logged, and can still read. Null
/// `@loggedBy` is the owner, who may use any of their own.
const _baseWorkoutByCoach = '''
@loggedBy::text IS NULL
OR EXISTS (
  SELECT 1
  FROM workouts w
  WHERE w.id = @workoutId::uuid
    AND w.logged_by = @loggedBy
    AND _readable_at(_relation(@loggedBy, @userId), w.started_at, w.hidden_at)
)''';

// Idempotent twice over: on the id, and on (exercise, workout), so a second
// device replaying the same bump gets the first one back. The exercise must be
// one the caller can see and the workout one they own; when either isn't, or
// the program is full, nothing is written and the db layer tells which. A coach
// writing for the owner (`@loggedBy`) moves bases only by a workout they logged
// and can read, and a replay answers only with a base of this program, so the
// route can't plant a base on the owner's own workout or read one it can't see.
const _createProgramBase =
    '''
WITH
_existing AS (
  SELECT id, program_id, exercise_id, slot, value, workout_id, action_id, at
  FROM program_bases
  WHERE user_id = @userId
    AND (
      id = @id::uuid
      OR (
        program_id = @programId::uuid
        AND exercise_id = @exerciseId::uuid
        AND slot IS NOT DISTINCT FROM @slot::uuid
        AND workout_id = @workoutId::uuid
      )
    )
    AND (
      @loggedBy::text IS NULL
      OR (
        program_id = @programId::uuid
        AND (
          program_bases.workout_id IS NULL
          OR EXISTS (
            SELECT 1
            FROM workouts w
            WHERE w.id = program_bases.workout_id
              AND _readable_at(_relation(@loggedBy, @userId), w.started_at, w.hidden_at)
          )
        )
      )
    )
  LIMIT 1
),
_ins AS (
  INSERT INTO program_bases (id, user_id, program_id, exercise_id, slot, value, workout_id, action_id, at)
  SELECT
    coalesce(@id::uuid, uuidv7()),
    @userId,
    @programId::uuid,
    @exerciseId::uuid,
    @slot::uuid,
    @value::real,
    @workoutId::uuid,
    @actionId::uuid,
    @at::timestamptz
  WHERE NOT EXISTS (SELECT 1 FROM _existing)
    AND EXISTS (
      SELECT 1
      FROM exercises
      WHERE id = @exerciseId::uuid
        AND (user_id IS NULL OR user_id = @userId)
    )
    AND (
      @workoutId::uuid IS NULL
      OR (
        EXISTS (SELECT 1 FROM workouts WHERE id = @workoutId::uuid AND user_id = @userId)
        AND ($_baseWorkoutByCoach)
      )
    )
    AND (SELECT count(*) FROM program_bases WHERE program_id = @programId::uuid) < $_maxProgramBases
  RETURNING id, program_id, exercise_id, slot, value, workout_id, action_id, at
)
SELECT id, program_id, exercise_id, slot, value, workout_id, action_id, at, true AS created FROM _ins
UNION ALL
SELECT id, program_id, exercise_id, slot, value, workout_id, action_id, at, false AS created FROM _existing
WHERE NOT EXISTS (SELECT 1 FROM _ins)
''';

/// Why `_createProgramBase` wrote nothing, asked only when it didn't.
const _diagnoseProgramBase =
    '''
SELECT
  EXISTS (
    SELECT 1
    FROM exercises
    WHERE id = @exerciseId::uuid
      AND (user_id IS NULL OR user_id = @userId)
  ) AS exercise_known,
  (
    @workoutId::uuid IS NULL
    OR (
      EXISTS (SELECT 1 FROM workouts WHERE id = @workoutId::uuid AND user_id = @userId)
      AND ($_baseWorkoutByCoach)
    )
  ) AS workout_known
''';

const _deleteProgramBase = '''
DELETE FROM program_bases
WHERE id = @id::uuid
  AND program_id = @programId::uuid
  AND user_id = @userId
''';

/// What a program's position is folded from besides its actions: its workouts,
/// at their start, and its skips.
const _listProgramMarks = '''
SELECT template_id, started_at AS at, true AS is_workout
FROM workouts
WHERE program_id = @programId::uuid
  AND user_id = @userId
  AND started_at IS NOT NULL
UNION ALL
SELECT template_id, at, false AS is_workout
FROM skips
WHERE program_id = @programId::uuid
  AND user_id = @userId
''';

/// A program's skips with what the user said, oldest first: its history read
/// back (heart-api#260).
const _listProgramSkips = '''
SELECT id, at, reason, weather, template_id, program_id
FROM skips
WHERE program_id = @programId::uuid
  AND user_id = @userId
ORDER BY at, id
''';

/// The session each of a program's workouts was, by workout id: a base a
/// workout caused reads as a test when the session is one.
const _listProgramWorkouts = '''
SELECT id, template_id
FROM workouts
WHERE program_id = @programId::uuid
  AND user_id = @userId
''';
