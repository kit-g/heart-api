import 'package:heart/core/response.dart';
import 'package:heart/routes/charts.dart' as charts;
import 'package:heart/routes/connections.dart' as connections;
import 'package:heart/routes/exercises.dart' as exercises;
import 'package:heart/routes/templates.dart' as templates;
import 'package:heart/routes/workouts.dart' as workouts;
import 'package:heart/routes/misc.dart' as version;
import 'package:relic/relic.dart';

final routes = <(String, Method), ModelHandler>{
  ('/version', .get): version.getVersion,
  ('/charts', .get): charts.getChartPreferences,
  ('/charts', .post): charts.saveChartPreference,
  ('/charts/:preferenceId', .delete): charts.deleteChartPreference,
  ('/connections', .get): connections.getConnections,
  ('/connections', .post): connections.createConnection,
  ('/connections/:connectionId', .delete): connections.deleteConnection,
  ('/connections/:connectionId', .put): connections.reactToConnection,
  ('/exercises', .get): exercises.getExercises,
  ('/templates', .get): templates.getMyTemplates,
  ('/templates/shares', .get): templates.getMyTemplateShares,
  ('/templates/:templateId', .delete): templates.deleteMyTemplate,
  ('/templates/shares/:shareId', .delete): templates.deleteMyTemplateShare,
  ('/users/:targetUserId/workouts', .get): workouts.getTargetUserWorkouts,
  ('/users/:targetUserId/templates/:templateId', .post): templates.assignTemplateToUser,
};

const _publicRoutes = {'/version'};

bool isPublicRoute(Request request) => !_publicRoutes.contains(request.url.path);
