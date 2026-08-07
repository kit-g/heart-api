import 'package:heart/globals/globals.dart';
import 'package:heart/inputs/inputs.dart';
import 'package:heart/middleware/database.dart';
import 'package:heart_models/heart_models.dart';
import 'package:relic/relic.dart';

import '../models/errors.dart';

Future<ExercisePreference> saveExercisePreference(final Request req) async {
  final input = await ExercisePreferenceSaveIn.fromRequest(req);
  return req.exercisePreferenceService.savePreference(input.preference, req.userId);
}

Future<Model> deleteExercisePreference(final Request req) {
  final query = ExercisePreferenceDeleteQuery.fromRequest(req);
  return deleteExercisePreferenceById(req, req.rawPathParameters[#exerciseId]!, query.field);
}

Future<Model> deleteExercisePreferenceById(
  final Request req,
  final String exerciseId,
  final ExercisePreferenceField field,
) async {
  final service = req.exercisePreferenceService;
  await service.clearPreference(exerciseId, req.userId, field);
  throw const NoContent();
}
