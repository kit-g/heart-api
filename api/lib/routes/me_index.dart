import 'package:heart/core/routing.dart';
import 'package:heart/routes/me.dart' as me;

/// Where the token-authenticated surface is attached.
const tokenPrefix = '/me';

/// The read surface for personal access tokens, relative to [tokenPrefix].
/// Published and additive-only, unlike the app's own table.
final RouteTable meRoutes = {
  ('/', .get): me.getMe,
  ('/workouts', .get): me.getMyWorkouts,
  ('/workouts/changes', .get): me.getMyWorkoutChanges,
  ('/workouts/:workoutId', .get): me.getMyWorkout,
  ('/exercises', .get): me.getMyExercises,
  ('/exercises/:exerciseId/history', .get): me.getMyExerciseHistory,
  ('/templates', .get): me.getMyTemplates,
  ('/template-folders', .get): me.getMyFolders,
  ('/goals', .get): me.getMyGoals,
  ('/records', .get): me.getMyRecords,
  ('/library', .get): me.searchMyLibrary,
  ('/export', .get): me.exportMe,
};
