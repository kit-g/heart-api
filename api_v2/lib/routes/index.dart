import 'package:heart/core/response.dart';
import 'package:heart/routes/charts.dart' as charts;
import 'package:relic/relic.dart';

final routes = <(String, Method), ModelHandler>{
  ('/charts', .get): charts.getChartPreferences,
  ('/charts', .post): charts.saveChartPreference,
  ('/charts/:preferenceId', .delete): charts.deleteChartPreference,
};
