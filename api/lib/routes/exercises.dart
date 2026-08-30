import 'package:heart/core/request.dart';
import 'package:heart/globals/config.dart';
import 'package:heart/globals/globals.dart';
import 'package:heart/inputs/inputs.dart';
import 'package:heart/middleware/s3.dart';
import 'package:heart/models/exercises.dart';
import 'package:relic/relic.dart';

Future<ExerciseResponse> getExercises(Request request) async {
  final locale = request.locale(request.config.supportedLocales, request.config.defaultLocale);
  final owned = request.queryParameters.raw['owned'] == 'true';
  final response = await request.exerciseService.getExercises(
    request.userId,
    locale: locale,
    owned: owned,
  );
  return ExerciseResponse(exerciseLibrary: response);
}

Future<ExerciseModel> createExercise(Request request) async {
  final input = await ExerciseCreateIn.fromRequest(request);
  final row = await request.exerciseService.createExercise(
    userId: request.userId,
    id: input.id,
    name: input.name,
    category: input.category,
    target: input.target,
    instructions: input.instructions,
  );
  return ExerciseModel(row);
}

Future<ExerciseModel> updateExercise(Request request) async {
  final exerciseId = request.pathParameters.raw[#exerciseId]!;
  final input = await ExerciseUpdateIn.fromRequest(request);

  final row = await request.exerciseService.updateExercise(
    userId: request.userId,
    exerciseId: exerciseId,
    category: input.category,
    target: input.target,
    instructions: input.instructions,
    archived: input.archived,
  );
  return ExerciseModel(row);
}
