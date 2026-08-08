import 'package:heart/core/response.dart';
import 'package:heart/routes/account.dart' as account;
import 'package:heart/routes/charts.dart' as charts;
import 'package:heart/routes/comments.dart' as comments;
import 'package:heart/routes/connections.dart' as connections;
import 'package:heart/routes/devices.dart' as devices;
import 'package:heart/routes/events.dart' as events;
import 'package:heart/routes/exercise_preferences.dart' as exercise_preferences;
import 'package:heart/routes/exercises.dart' as exercises;
import 'package:heart/routes/feedback.dart' as feedback;
import 'package:heart/routes/goals.dart' as goals;
import 'package:heart/routes/images.dart' as images;
import 'package:heart/routes/misc.dart' as version;
import 'package:heart/routes/template_folders.dart' as folders;
import 'package:heart/routes/templates.dart' as templates;
import 'package:heart/routes/workouts.dart' as workouts;
import 'package:relic/relic.dart';

final routes = <(String, Method), ModelHandler>{
  ('/accounts', .put): account.upsertAccount,
  ('/accounts', .delete): account.deleteAccount,
  ('/feedback', .post): feedback.submitFeedback,
  ('/accounts/:targetUserId/workouts', .get): workouts.getTargetUserWorkouts,
  ('/accounts/:targetUserId/goals', .get): goals.getTargetUserGoals,
  ('/accounts/:targetUserId/workouts/:workoutId', .get): workouts.getTargetUserWorkout,
  ('/accounts/:targetUserId/templates/:templateId', .post): templates.assignTemplateToUser,
  ('/accounts/:targetUserId/folders/:folderId', .post): folders.assignFolderToUser,
  ('/version', .get): version.getVersion,
  ('/charts', .get): charts.getChartPreferences,
  ('/charts', .post): charts.saveChartPreference,
  ('/charts/:preferenceId', .delete): charts.deleteChartPreference,
  ('/comments', .get): comments.listComments,
  ('/comments', .post): comments.createComment,
  ('/comments/:commentId', .put): comments.editComment,
  ('/comments/:commentId', .delete): comments.deleteComment,
  ('/connections', .get): connections.getConnections,
  ('/connections', .post): connections.createConnection,
  ('/connections/:connectionId', .delete): connections.deleteConnection,
  ('/connections/:connectionId', .put): connections.reactToConnection,
  ('/devices', .post): devices.registerDevice,
  ('/exercises', .get): exercises.getExercises,
  ('/exercises', .post): exercises.createExercise,
  ('/exercises/:exerciseId', .put): exercises.updateExercise,
  ('/exercise-preferences', .post): exercise_preferences.saveExercisePreference,
  ('/exercise-preferences/:exerciseId', .delete): exercise_preferences.deleteExercisePreference,
  ('/goals', .post): goals.createGoal,
  ('/goals/:goalId', .put): goals.updateGoal,
  ('/goals/:goalId', .delete): goals.deleteGoal,
  ('/goals/:goalId/stages/:stageId', .put): goals.markStageAchieved,
  ('/events', .post): events.handler,
  ('/template-folders', .get): folders.getMyFolders,
  ('/template-folders', .post): folders.createFolder,
  ('/template-folders/:folderId', .put): folders.updateFolder,
  ('/template-folders/:folderId', .delete): folders.deleteFolder,
  ('/templates', .get): templates.getMyTemplates,
  ('/templates/:templateId', .get): templates.getMyTemplate,
  ('/templates', .post): templates.createTemplate,
  ('/templates/shares', .get): templates.getMyTemplateShares,
  ('/templates/:templateId', .put): templates.updateTemplate,
  ('/templates/:templateId', .delete): templates.deleteMyTemplate,
  ('/templates/shares/:shareId', .delete): templates.deleteMyTemplateShare,
  ('/workouts', .post): workouts.createWorkout,
  ('/workouts/images', .get): images.getGallery,
  ('/workouts/:workoutId', .get): workouts.getWorkout,
  ('/workouts/:workoutId', .put): workouts.updateWorkout,
  ('/workouts/:workoutId', .patch): workouts.patchWorkout,
  ('/workouts/:workoutId', .delete): workouts.deleteWorkout,
  ('/workouts/:workoutId/images', .put): images.presignWorkoutImage,
  ('/workouts/:workoutId/images', .delete): images.deleteWorkoutImage,
};

const _publicRoutes = {'/version', '/events'};

bool isPublicRoute(Request request) => !_publicRoutes.contains(request.url.path);
