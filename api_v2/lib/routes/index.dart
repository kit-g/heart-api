import 'package:heart/core/response.dart';
import 'package:heart/routes/charts.dart' as charts;
import 'package:heart/routes/connections.dart' as connections;
import 'package:heart/routes/exercises.dart' as exercises;
import 'package:heart/routes/misc.dart' as version;
import 'package:relic/relic.dart';

final routes = <(String, Method), ModelHandler>{
  ('/version', .get): version.getVersion,
  ('/charts', .get): charts.getChartPreferences,
  ('/charts', .post): charts.saveChartPreference,
  ('/charts/:preferenceId', .delete): charts.deleteChartPreference,
  ('/exercises', .get): exercises.getExercises,
  ('/connections', .get): connections.getConnections,
  ('/connections', .post): connections.createConnection,
  ('/connections/:targetId', .delete): connections.deleteConnection,
};

const _publicRoutes = {'/version'};

bool isPublicRoute(Request request) => !_publicRoutes.contains(request.url.path);
