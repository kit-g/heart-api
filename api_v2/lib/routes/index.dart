import 'package:heart/core/response.dart';
import 'package:heart/routes/account.dart' as account;
import 'package:heart/routes/charts.dart' as charts;
import 'package:heart/routes/connections.dart' as connections;
import 'package:heart/routes/events.dart' as events;
import 'package:heart/routes/exercises.dart' as exercises;
import 'package:heart/routes/images.dart' as images;
import 'package:heart/routes/misc.dart' as version;
import 'package:heart/routes/templates.dart' as templates;
import 'package:heart/routes/workouts.dart' as workouts;
import 'package:relic/relic.dart';

final routes = <(String, Method), ModelHandler>{
  ('/accounts', .put): account.upsertAccount,
  ('/feedback', .post): feedback.submitFeedback,
  ('/accounts/:targetUserId/workouts', .get): workouts.getTargetUserWorkouts,
  ('/accounts/:targetUserId/workouts/:workoutId', .get): workouts.getTargetUserWorkout,
  ('/accounts/:targetUserId/templates/:templateId', .post): templates.assignTemplateToUser,
  ('/version', .get): version.getVersion,
  ('/charts', .get): charts.getChartPreferences,
  ('/charts', .post): charts.saveChartPreference,
  ('/charts/:preferenceId', .delete): charts.deleteChartPreference,
  ('/connections', .get): connections.getConnections,
  ('/connections', .post): connections.createConnection,
  ('/connections/:connectionId', .delete): connections.deleteConnection,
  ('/connections/:connectionId', .put): connections.reactToConnection,
  ('/exercises', .get): exercises.getExercises,
  ('/events', .post): events.handler,
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
  ('/workouts/:workoutId', .delete): workouts.deleteWorkout,
  ('/workouts/:workoutId/images', .put): images.presignWorkoutImage,
  ('/workouts/:workoutId/images', .delete): images.deleteWorkoutImage,
};

const _publicRoutes = {'/version', '/events'};

bool isPublicRoute(Request request) => !_publicRoutes.contains(request.url.path);
