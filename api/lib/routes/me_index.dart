import 'package:heart/core/openapi/endpoint.dart';
import 'package:heart/core/openapi/query.dart';
import 'package:heart/inputs/inputs.dart';
import 'package:heart/models/changes.dart';
import 'package:heart/models/shape_overrides.dart';
import 'package:heart/models/shapes.g.dart';
import 'package:heart/routes/me.dart' as me;
import 'package:heart/routes/me_coaching.dart' as coaching;

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
  ('/coaching/clients', .get): .of(
    coaching.getMyClients,
    summary: 'The people you coach, those who need a word first',
    description:
        'The people you coach: `clientId`, name, `status` (`active`, `paused`, or `severed` for a former client), '
        'since when, and whether they share their training with your apps and assistants '
        '(`sharesWithAssistant`), which the client turns on in the app. Only those who share can be read here: '
        'for them, the program they are on and its week, the days they trained in the last 14 (`recent`), when '
        'they last trained, and why they need a word (`reasons`: `lighter`, a workout fell short of its plan; '
        '`note`, they left a note; `gap`, a week without training; `ending`, their program is in its last week; '
        '`changed`, they changed a program you sent). '
        'One who doesn\'t share is named, with their status and since when, and nothing more. `?former=true` '
        'lists former clients.',
    input: RosterQuery.read,
    reply: .json(.page('clients', meCoachingClientShape)),
    scope: .readCoaching,
  ),
  ('/coaching/feed', .get): .of(
    coaching.getMyCoachFeed,
    summary: 'What your clients did lately, newest first',
    description:
        'What the clients who share with your apps and assistants did lately, newest first: a workout finished '
        '(`id` is the workout\'s), a session skipped, a program in its last week.',
    input: CoachFeedQuery.read,
    reply: .json(.page('items', meCoachFeedItemShape)),
    scope: .readCoaching,
  ),
  ('/coaching/clients/:clientId/workouts', .get): .of(
    coaching.getClientWorkouts,
    summary: 'A client\'s workouts, newest first',
    description:
        'One client\'s workouts, newest first, as `/me/workouts` gives your own, and `loggedByYou` on one you '
        'logged for them. Only what you can read as their coach: from when coaching began (earlier only if they '
        'share their history), nothing they hid, nothing from a pause.',
    input: (query) => (clientId: _client(query), page: PageQuery.read(query)),
    reply: .json(.page('workouts', meClientWorkoutShape)),
    errors: [_notShared],
    scope: .readCoaching,
  ),
  ('/coaching/clients/:clientId/workouts/:workoutId', .get): .of(
    coaching.getClientWorkout,
    summary: 'One of a client\'s workouts in full',
    description: 'One of a client\'s workouts.',
    input: (query) => (clientId: _client(query), workoutId: _id('workoutId')(query)),
    reply: .json(meClientWorkoutShape),
    errors: [_notShared, const .notFound()],
    scope: .readCoaching,
  ),
  ('/coaching/clients/:clientId/programs', .get): .of(
    coaching.getClientPrograms,
    summary: 'The programs you sent a client',
    description:
        'The programs you sent one client, as they hold them: name, whether archived, and how many sessions. '
        'Empty for a client who doesn\'t share with your apps and assistants.',
    input: _client,
    reply: .json(meClientProgramsShape),
    errors: [_notShared],
    scope: .readCoaching,
  ),
  ('/coaching/clients/:clientId/programs/:programId', .get): .of(
    coaching.getClientProgram,
    summary: 'One program you sent a client, as they hold it now',
    description:
        'One program you sent a client, as they hold it now: its sessions in order, as `/me/templates` gives a '
        'template, with which are `done` in the open cycle and `sentByYou` on one you sent or wrote into; and '
        'where they stand (`position`): the program week, the next session, whether it is paused or finished, '
        'and workouts this week. Worked out from what you can read as their coach, so a workout they hid leaves '
        'its session undone here.',
    input: (query) => (clientId: _client(query), programId: _id('programId')(query)),
    reply: .json(meClientProgramShape),
    errors: [_notShared, const .notFound('program_not_found'), const .notFound()],
    scope: .readCoaching,
  ),
  ('/coaching/clients/:clientId/programs/:programId/changes', .get): .of(
    coaching.getClientProgramChanges,
    summary: 'What changed in a program you sent a client, since a cursor, oldest first',
    description:
        'What changed in a program you sent a client, oldest first: who made each change (`by`: `you` or '
        '`client`), what kind (`edit`, `create`, `delete`, `revert`, or `library_update`: you sent a new '
        'version), which session (`sessionId`; none for the program itself), and how it stood `before` and '
        '`after`. A feed like [`/me/workouts/changes`](#polling): without `since` it starts from the '
        'beginning; after that, pass back the `cursor` you were given, while `hasMore` is true straight away. '
        'When nothing changed you get an empty list and the same cursor.',
    input: (query) => (
      clientId: _client(query),
      programId: _id('programId')(query),
      since: switch (query.stringOrNull(
        'since',
        description: 'The `cursor` of the last page read; none starts from the beginning.',
      )) {
        // a cursor that can't be one is the caller's mistake, never a fresh start
        final String raw => ChangeCursor.parse(raw).toString(),
        null => null,
      },
    ),
    reply: .json(meClientProgramChangesShape),
    errors: [
      _notShared,
      const .notFound('program_not_found'),
      const .badRequest('stale_cursor', 'a cursor from before the database moved: start again without `since`'),
    ],
    scope: .readCoaching,
  ),
  ('/coaching/clients/:clientId/goals', .get): .of(
    coaching.getClientGoals,
    summary: 'A client\'s goals',
    description:
        'One client\'s goals, as `/me/goals` gives your own, when they share their goals with you as well as '
        'their training with your apps and assistants.',
    input: (query) => (clientId: _client(query), query: GoalsQuery.read(query)),
    reply: .json(goalsResponseShape),
    errors: [_notShared],
    scope: .readCoaching,
  ),
  ('/coaching/library', .get): .of(
    coaching.getMyCoachingLibrary,
    summary: 'Your coaching library, newest first',
    description:
        'The programs in your own coaching library, the ones you send to clients: name, version and when it last '
        'changed. Not Heart\'s library, which is `/me/library/programs`.',
    input: PageQuery.read,
    reply: .json(.page('programs', meLibraryEntryShape)),
    scope: .readCoaching,
  ),
  ('/coaching/library/:programId', .get): .of(
    coaching.getMyCoachingLibraryProgram,
    summary: 'One program of your coaching library in full',
    description: 'One program of your coaching library, its current version in full, as you saved it.',
    input: _id('programId'),
    reply: .json(meLibraryProgramShape),
    errors: [const .notFound('program_not_found')],
    scope: .readCoaching,
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

/// A client, by the `clientId` `/me/coaching/clients` gives.
String _client(Query query) => query.path('clientId', description: 'A `clientId` from `/me/coaching/clients`.');

/// Anyone who isn't a client sharing what a route reads with the user's apps and
/// assistants.
const _notShared = Failure.forbidden(
  'not_shared',
  'not a client who shares it with your apps and assistants (`/me/coaching/clients` says who does)',
);
