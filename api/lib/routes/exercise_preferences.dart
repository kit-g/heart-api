import 'package:heart/globals/globals.dart';
import 'package:heart/inputs/inputs.dart';
import 'package:heart/middleware/database.dart';
import 'package:heart_models/heart_models.dart';
import 'package:relic/relic.dart';

import '../models/errors.dart';
import '../models/exercise_preferences.dart';

Future<ExercisePreferenceResponse> getExercisePreferences(Request req) async {
  final service = req.exercisePreferenceService;
  final prefs = await service.getExercisePreferences(req.userId);
  return ExercisePreferenceResponse(preferences: prefs);
}

Future<ExercisePreference> saveExercisePreference(Request req) async {
  final input = await ExercisePreferenceSaveIn.fromRequest(req);
  return req.exercisePreferenceService.savePreference(input.preference, req.userId);
}

Future<Model> deleteExercisePreference(Request req) {
  final query = ExercisePreferenceDeleteQuery.fromRequest(req);
  return deleteExercisePreferenceById(req, req.rawPathParameters[#exerciseId]!, query.field);
}

Future<Model> deleteExercisePreferenceById(
  Request req,
  String exerciseId,
  ExercisePreferenceField field,
) async {
  final service = req.exercisePreferenceService;
  await service.clearPreference(exerciseId, req.userId, field);
  throw const NoContent();
}
