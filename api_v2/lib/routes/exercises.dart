import 'package:heart/core/request.dart';
import 'package:heart/globals/config.dart';
import 'package:heart/globals/globals.dart';
import 'package:heart/middleware/s3.dart';
import 'package:heart/models/errors.dart';
import 'package:heart/models/exercises.dart';
import 'package:relic/relic.dart';

String _getLocale(
  final List<LanguageQuality>? requestLocales,
  final List<String> supportedLocales,
  String defaultLocale,
) {
  if (requestLocales == null) return defaultLocale;
  if (requestLocales.isEmpty) return defaultLocale;
  final sorted = List.of(requestLocales)..sort((one, two) => (two.quality ?? 0).compareTo(one.quality ?? 0));
  return sorted
      .map((l) => l.language.replaceAll('-', '_'))
      .firstWhere(supportedLocales.contains, orElse: () => defaultLocale);
}

Future<ExerciseResponse> getExercises(final Request request) async {
  final locale = _getLocale(
    request.headers.acceptLanguage?.languages,
    request.config.supportedLocales,
    request.config.defaultLocale,
  );
  final owned = request.queryParameters.raw['owned'] == 'true';
  final response = await request.exerciseService.getExercises(
    request.userId,
    locale: locale,
    owned: owned,
  );
  return ExerciseResponse(exerciseLibrary: response);
}

Future<ExerciseModel> createExercise(final Request request) async {
  final body = await request.json();
  final name = (body['name'] as String?)?.trim();
  final category = body['category'] as String?;
  final target = body['target'] as String?;

  if (name == null || name.isEmpty) {
    throw const BadRequest(reason: 'name is required');
  }
  if (category == null || category.isEmpty) {
    throw const BadRequest(reason: 'category is required');
  }
  if (target == null || target.isEmpty) {
    throw const BadRequest(reason: 'target is required');
  }

  final row = await request.exerciseService.createExercise(
    userId: request.userId,
    name: name,
    category: category,
    target: target,
    instructions: body['instructions'] as String?,
  );
  return ExerciseModel(row);
}

Future<ExerciseModel> updateExercise(final Request request) async {
  final exerciseId = request.pathParameters.raw[#exerciseId]!;
  final body = await request.json();

  final row = await request.exerciseService.updateExercise(
    userId: request.userId,
    exerciseId: exerciseId,
    category: body['category'] as String?,
    target: body['target'] as String?,
    instructions: body['instructions'] as String?,
    archived: body['archived'] as bool?,
  );
  return ExerciseModel(row);
}