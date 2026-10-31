import 'package:heart/core/openapi/endpoint.dart';
import 'package:heart/inputs/inputs.dart';
import 'package:heart/models/shapes.g.dart';
import 'package:heart/routes/me.dart' as me;

/// Where the token-authenticated surface is attached.
const tokenPrefix = '/me';

/// The read surface for personal access tokens, relative to [tokenPrefix].
/// Published and additive-only, unlike the app's own table. Each route says
/// what it reads and answers, so this table is also `openapi.json`. The
/// shapes are generated from the models' `toMap()`s (`tool/openapi/shapes.dart`).
final EndpointTable meRoutes = {
  ('/', .get): .none(
    me.getMe,
    summary: 'Who the token acts as',
    reply: .json(meProfileShape),
    errors: [const .notFound()],
  ),
  ('/workouts', .get): .of(
    me.getMyWorkouts,
    summary: 'Workouts, newest first',
    input: PageQuery.read,
    reply: .json(.page('workouts', meWorkoutShape)),
  ),
  ('/workouts/changes', .get): .of(
    me.getMyWorkoutChanges,
    summary: 'What changed or was deleted since a cursor, oldest first',
    input: ChangesQuery.read,
    reply: .json(meWorkoutChangesShape),
  ),
  ('/workouts/:workoutId', .get): .of(
    me.getMyWorkout,
    summary: 'One workout in full',
    input: _id('workoutId'),
    reply: .json(meWorkoutShape),
    errors: [const .notFound()],
  ),
  ('/exercises', .get): .none(
    me.getMyExercises,
    summary: 'The user\'s own exercises',
    reply: .json(.unknown('`exercises`: the user\'s own, as the database writes them')),
  ),
  ('/exercises/:exerciseId/history', .get): .of(
    me.getMyExerciseHistory,
    summary: 'One exercise\'s sessions, newest first',
    input: ExerciseHistoryQuery.read,
    reply: .json(.page('sessions', meExerciseSessionShape, extra: {'warnings': warningsShape})),
    errors: [const .notFound()],
  ),
  ('/templates', .get): .of(
    me.getMyTemplates,
    summary: 'Templates, in the user\'s order',
    input: TemplateListQuery.read,
    reply: .json(.page('templates', templateShape)),
  ),
  ('/template-folders', .get): .none(
    me.getMyFolders,
    summary: 'Template folders',
    reply: .json(templateFoldersResponseShape),
  ),
  ('/goals', .get): .of(
    me.getMyGoals,
    summary: 'Goal definitions',
    input: GoalsQuery.read,
    reply: .json(goalsResponseShape),
  ),
  ('/goals/progress', .get): .none(
    me.getMyGoalProgress,
    summary: 'Each live goal with where it stands now',
    reply: .json(meGoalProgressShape),
  ),
  ('/anomalies', .get): .of(
    me.getMyAnomalies,
    summary: 'Suspicious entries, newest found first',
    input: AnomaliesQuery.read,
    reply: .json(.page('anomalies', anomalyShape)),
  ),
  ('/programs', .get): .none(
    me.getMyPrograms,
    summary: 'The user\'s programs, each with where they stand in it',
    reply: .json(meProgramsShape),
  ),
  ('/programs/:programId', .get): .of(
    me.getMyProgram,
    summary: 'One program, with the next session planned',
    input: _id('programId'),
    reply: .json(meProgramShape),
    errors: [const .notFound('program_not_found')],
  ),
  ('/programs/:programId/history', .get): .of(
    me.getMyProgramHistory,
    summary: 'One program\'s sessions so far',
    input: _id('programId'),
    reply: .json(programHistoryShape),
    errors: [const .notFound('program_not_found')],
  ),
  ('/records', .get): .of(
    me.getMyRecords,
    summary: 'Personal records per exercise',
    input: RecordsQuery.read,
    reply: .json(meRecordsShape),
  ),
  ('/volume', .get): .of(
    me.getMyVolume,
    summary: 'Training volume by muscle and week',
    input: LensQuery.read,
    reply: .json(meVolumeShape),
  ),
  ('/balance', .get): .of(
    me.getMyBalance,
    summary: 'Each balance pair\'s two sides set against each other',
    input: LensQuery.read,
    reply: .json(meBalanceShape),
  ),
  ('/library', .get): .of(
    me.searchMyLibrary,
    summary: 'Search the exercise library and the user\'s own exercises',
    input: LibrarySearchQuery.read,
    reply: .json(meLibrarySearchShape),
  ),
  ('/library/programs', .get): .none(
    me.getMyLibraryPrograms,
    summary: 'The library\'s programs',
    reply: .json(.unknown('the library\'s programs as the content publishes them')),
  ),
  ('/library/programs/:key', .get): .of(
    me.getMyLibraryProgram,
    summary: 'One library program in full',
    input: _key('key'),
    reply: .json(.unknown('a library program as the content publishes it')),
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
