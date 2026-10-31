import 'package:heart/core/openapi/endpoint.dart';
import 'package:heart/inputs/inputs.dart';
import 'package:heart/models/shape_overrides.dart';
import 'package:heart/models/shapes.g.dart';
import 'package:heart/routes/me.dart' as me;

/// Where the token-authenticated surface is attached.
const tokenPrefix = '/me';

/// The read surface for personal access tokens, relative to [tokenPrefix].
/// Published and additive-only, unlike the app's own table. Each route says
/// what it reads and answers, so this table is also the OpenAPI document
/// (`tool/openapi/spec.dart`). The shapes are generated from the models'
/// `toMap()`s: `make openapi`.
final EndpointTable meRoutes = {
  ('/', .get): .none(
    me.getMe,
    summary: 'Who the token acts as',
    description:
        'Your username, unit system, and how many workouts, templates, folders, goals, custom exercises and '
        'programs you have.',
    reply: .json(meProfileShape),
    errors: [const .notFound()],
  ),
  ('/workouts', .get): .of(
    me.getMyWorkouts,
    summary: 'Workouts, newest first',
    description: 'Your workouts, newest first, each with its exercises, sets, notes and image links.',
    input: PageQuery.read,
    reply: .json(.page('workouts', meWorkoutShape)),
  ),
  ('/workouts/changes', .get): .of(
    me.getMyWorkoutChanges,
    summary: 'What changed or was deleted since a cursor, oldest first',
    description: 'What changed since a cursor: see [Keeping a copy in sync](#polling).',
    input: ChangesQuery.read,
    reply: .json(meWorkoutChangesShape),
  ),
  ('/workouts/:workoutId', .get): .of(
    me.getMyWorkout,
    summary: 'One workout in full',
    description: 'One workout.',
    input: _id('workoutId'),
    reply: .json(meWorkoutShape),
    errors: [const .notFound()],
  ),
  ('/exercises', .get): .none(
    me.getMyExercises,
    summary: 'The user\'s own exercises',
    description: 'Your custom exercises.',
    reply: .json(customExercisesShape),
  ),
  ('/exercises/:exerciseId/history', .get): .of(
    me.getMyExerciseHistory,
    summary: 'One exercise\'s sessions, newest first',
    description:
        'Every session of one exercise, newest first, with its working sets and the values the app’s '
        'progress chart plots.',
    input: ExerciseHistoryQuery.read,
    reply: .json(.page('sessions', meExerciseSessionShape, extra: {'warnings': warningsShape})),
    errors: [const .notFound()],
  ),
  ('/templates', .get): .of(
    me.getMyTemplates,
    summary: 'Templates, in the user\'s order',
    description: 'Your templates, in your order; `?folder=` for one folder.',
    input: TemplateListQuery.read,
    reply: .json(.page('templates', templateShape)),
  ),
  ('/template-folders', .get): .none(
    me.getMyFolders,
    summary: 'Template folders',
    description: 'Your template folders.',
    reply: .json(templateFoldersResponseShape),
  ),
  ('/goals', .get): .of(
    me.getMyGoals,
    summary: 'Goal definitions',
    description:
        'Your goals. Goals backed by health data carry their definition only; their progress lives on your '
        'phone.',
    input: GoalsQuery.read,
    reply: .json(goalsResponseShape),
  ),
  ('/goals/progress', .get): .none(
    me.getMyGoalProgress,
    summary: 'Each live goal with where it stands now',
    description:
        'Each live goal with where it stands now, as the app’s goal card measures it: `current`, and '
        '`progress` through the current stage from 0 to 1. A weekly or monthly goal names its `period`.',
    reply: .json(meGoalProgressShape),
  ),
  ('/anomalies', .get): .of(
    me.getMyAnomalies,
    summary: 'Suspicious entries, newest found first',
    description:
        'Entries in your log that look suspicious (a workout left running, a weight far from the exercise’s '
        'usual, weight and reps swapped) and what you made of each: `pending`, `valid` or `invalid`. '
        'Nothing is corrected; invalid entries stay in your log and are left out of the counts. `?status=` '
        'for one kind. Volume, balance, records and goal progress name the pending ones they counted in '
        '`warnings`.',
    input: AnomaliesQuery.read,
    reply: .json(.page('anomalies', anomalyShape)),
  ),
  ('/programs', .get): .none(
    me.getMyPrograms,
    summary: 'The user\'s programs, each with where they stand in it',
    description:
        'Your programs, each with where you stand: the program week, the sessions done in the open cycle '
        'and the next one, whether it’s paused, and workouts this week. Worked out from what you logged, '
        'the way the app works it out; weeks here are ISO weeks in UTC.',
    reply: .json(meProgramsShape),
  ),
  ('/programs/:programId', .get): .of(
    me.getMyProgram,
    summary: 'One program, with the next session planned',
    description:
        'One program: its sessions and when each joined (`joined`), each exercise’s growth rule, its '
        'lighter weeks (`deload`), `phases` and test sessions (`tests`). Under `bases`, each exercise’s '
        'current base: the training max, working weight, duration or distance its rule raises. A lift used '
        'in two sessions can keep a base for each; that one is keyed by its `slot` and names its '
        '`exerciseId`. Under `nextSession`, the session up next as the app shows it: this week’s targets, '
        'and weights worked out from the bases (a share of a base, rounded down to the rule’s step, and '
        'lighter in a lighter week). It reads what’s stored and isn’t a forecast. A program you started '
        'from the library also has `research`: the claims behind it and their sources, each placed on the '
        'part of your copy it explains.',
    input: _id('programId'),
    reply: .json(meProgramShape),
    errors: [const .notFound('program_not_found')],
  ),
  ('/programs/:programId/history', .get): .of(
    me.getMyProgramHistory,
    summary: 'One program\'s sessions so far',
    description:
        'How the program got there, oldest first. Each base value has its `cause`: `workout` (a session '
        'raised it, or lowered it after misses), `test` (a test session set it), `action` (replaying a week '
        'set it) or `user`, and the value before it (`previous`). Also your `actions` (pauses, lighter '
        'weeks, repeats, replays, a variation moving up a step) and the sessions you skipped (`skips`), '
        'with the reason you gave.',
    input: _id('programId'),
    reply: .json(programHistoryShape),
    errors: [const .notFound('program_not_found')],
  ),
  ('/records', .get): .of(
    me.getMyRecords,
    summary: 'Personal records per exercise',
    description:
        'Personal records per exercise, the same ones the app shows, and when each exercise was last done '
        '(`lastTrained`); `?exerciseId=` for one.',
    input: RecordsQuery.read,
    reply: .json(meRecordsShape),
  ),
  ('/volume', .get): .of(
    me.getMyVolume,
    summary: 'Training volume by muscle and week',
    description:
        'Week by week: the finished workouts, their time in seconds, the weight moved (`totalVolume`, kg), '
        'and working sets and sessions per muscle group and per movement pattern, as the app’s weekly card '
        'counts them: a set counts fully for the muscles an exercise works first and partly (usually half) '
        'for the ones it works second, so sets per muscle can be fractional; `primarySets` is the direct '
        'part. `untrained` lists the muscle groups nothing reached. `?from=&to=` for a span of up to a '
        'year; without `from`, the 4 weeks ending this one.',
    input: LensQuery.read,
    reply: .json(meVolumeShape),
  ),
  ('/balance', .get): .of(
    me.getMyBalance,
    summary: 'Each balance pair\'s two sides set against each other',
    description:
        'Opposing movements set against each other, as the app’s balance view shows them (push against '
        'pull, hinge against squat, and so on): each side’s working sets and how many of the weeks either '
        'was trained. Counts only. Same span as `/me/volume`.',
    input: LensQuery.read,
    reply: .json(meBalanceShape),
  ),
  ('/library', .get): .of(
    me.searchMyLibrary,
    summary: 'Search the exercise library and the user\'s own exercises',
    description:
        'The exercise library and your own exercises, searched the way the app searches: word order free, '
        'abbreviations such as `db` or `rdl`, muscle words such as `lats`, one typo a word.',
    input: LibrarySearchQuery.read,
    reply: .json(meLibrarySearchShape),
  ),
  ('/library/programs', .get): .none(
    me.getMyLibraryPrograms,
    summary: 'The library\'s programs',
    description:
        'Heart’s ready-made programs, with what helps choose one: who it’s for (`audience`), the '
        '`equipment` it needs, days a week, minutes a session and weeks long. In your language where '
        'translated, otherwise English.',
    reply: .json(libraryProgramsShape),
  ),
  ('/library/programs/:key', .get): .of(
    me.getMyLibraryProgram,
    summary: 'One library program in full',
    description:
        'One ready-made program in full: what a week looks like, how it grows, its sessions and growth '
        'rules, its safety notes, and the research behind it. Each claim has its sources (title, authors, '
        'year, a link and the finding in plain words) and the part of the program it explains (`about`).',
    input: _key('key'),
    reply: .json(libraryProgramShape),
    errors: [const .notFound('library_program_not_found')],
  ),
  ('/export', .get): .of(
    me.exportMe,
    summary: 'The whole account in another app\'s format, once a day',
    input: ExportQuery.read,
    reply: .download(mimeType: 'text/csv'),
    errors: [const .tooManyRequests('export_limit', 'one export a day')],
  ),
};

/// A uuid path segment, raw: the handler turns a malformed one into its 404.
Input<String> _id(String name) =>
    (query) => query.path(name, format: 'uuid');

Input<String> _key(String name) =>
    (query) => query.path(name);
