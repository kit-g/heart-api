import 'package:heart/core/openapi/endpoint.dart';
import 'package:heart/inputs/inputs.dart';
import 'package:heart/models/anomalies.dart';
import 'package:heart/models/me.dart';
import 'package:heart/routes/me.dart' as me;

/// Where the token-authenticated surface is attached.
const tokenPrefix = '/me';

/// The read surface for personal access tokens, relative to [tokenPrefix].
/// Published and additive-only, unlike the app's own table. Each route says
/// what it reads and answers, so this table is also `openapi.json`.
final EndpointTable meRoutes = {
  ('/', .get): .none(
    me.getMe,
    summary: 'Who the token acts as',
    reply: .json(MeProfile.shape),
    errors: [const .notFound()],
  ),
  ('/workouts', .get): .of(
    me.getMyWorkouts,
    summary: 'Workouts, newest first',
    input: PageQuery.read,
    reply: .json(.page('workouts', MeWorkout.shape)),
  ),
  ('/workouts/changes', .get): .of(
    me.getMyWorkoutChanges,
    summary: 'What changed or was deleted since a cursor, oldest first',
    input: ChangesQuery.read,
    reply: .json(MeWorkoutChanges.shape),
  ),
  ('/workouts/:workoutId', .get): .of(
    me.getMyWorkout,
    summary: 'One workout in full',
    input: _id('workoutId'),
    reply: .json(MeWorkout.shape),
    errors: [const .notFound()],
  ),
  ('/exercises', .get): .undeclared(me.getMyExercises),
  ('/exercises/:exerciseId/history', .get): .of(
    me.getMyExerciseHistory,
    summary: 'One exercise\'s sessions, newest first',
    input: ExerciseHistoryQuery.read,
    reply: .json(.page('sessions', MeExerciseSession.shape, extra: {'warnings': warningsShape})),
    errors: [const .notFound()],
  ),
  ('/templates', .get): .undeclared(me.getMyTemplates),
  ('/template-folders', .get): .undeclared(me.getMyFolders),
  ('/goals', .get): .undeclared(me.getMyGoals),
  ('/goals/progress', .get): .undeclared(me.getMyGoalProgress),
  ('/anomalies', .get): .undeclared(me.getMyAnomalies),
  ('/programs', .get): .undeclared(me.getMyPrograms),
  ('/programs/:programId', .get): .undeclared(me.getMyProgram),
  ('/programs/:programId/history', .get): .undeclared(me.getMyProgramHistory),
  ('/records', .get): .of(
    me.getMyRecords,
    summary: 'Personal records per exercise',
    input: RecordsQuery.read,
    reply: .json(MeRecords.shape),
  ),
  ('/volume', .get): .undeclared(me.getMyVolume),
  ('/balance', .get): .undeclared(me.getMyBalance),
  ('/library', .get): .of(
    me.searchMyLibrary,
    summary: 'Search the exercise library and the user\'s own exercises',
    input: LibrarySearchQuery.read,
    reply: .json(MeLibrarySearch.shape),
  ),
  ('/library/programs', .get): .undeclared(me.getMyLibraryPrograms),
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
