import 'package:heart/core/request.dart';
import 'package:heart/globals/globals.dart';
import 'package:heart/middleware/database.dart';
import 'package:heart/models/charts.dart';
import 'package:heart_models/heart_models.dart';
import 'package:relic/relic.dart';

import '../models/errors.dart';

Future<ChartPreferenceResponse> getChartPreferences(final Request req) async {
  final service = req.chartPreferenceService;
  final prefs = await service.getPreferences(req.userId);
  return ChartPreferenceResponse(preferences: prefs);
}

Future<ChartPreference> saveChartPreference(final Request req) async {
  try {
    final service = req.chartPreferenceService;
    final body = await req.json();
    final input = ChartPreference.fromRow(body);
    return service.saveChartPreference(input, req.userId);
  } on ArgumentError catch (e) {
    throw BadRequest(reason: e.toString());
  }
}

Future<Model> deleteChartPreference(final Request req) async {
  final service = req.chartPreferenceService;
  final preferenceId = req.rawPathParameters[#preferenceId]!;
  await service.deleteChartPreference(preferenceId, req.userId);
  throw const NoContent();
}
