import 'package:heart/core/request.dart';
import 'package:heart/globals/globals.dart';
import 'package:heart/middleware/database.dart';
import 'package:heart_models/heart_models.dart';
import 'package:relic/relic.dart';

import '../models/errors.dart';

Future<ExercisePreference> saveExercisePreference(final Request req) async {
  try {
    final service = req.exercisePreferenceService;
    final body = await req.json();
    final input = ExercisePreference.fromRow(body);
    return service.saveUnitPreference(input, req.userId);
  } on ArgumentError catch (e) {
    throw BadRequest(reason: e.toString());
  }
}

Future<Model> deleteExercisePreference(final Request req) =>
    deleteExercisePreferenceById(req, req.rawPathParameters[#exerciseId]!);

Future<Model> deleteExercisePreferenceById(final Request req, final String exerciseId) async {
  final service = req.exercisePreferenceService;
  await service.deleteUnitPreference(exerciseId, req.userId);
  throw const NoContent();
}
