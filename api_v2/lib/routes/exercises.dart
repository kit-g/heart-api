import 'package:heart/globals/config.dart';
import 'package:heart/globals/globals.dart';
import 'package:heart/middleware/s3.dart';
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
  final service = request.exerciseService;
  final userId = request.userId;
  final locale = _getLocale(
    request.headers.acceptLanguage?.languages,
    request.config.supportedLocales,
    request.config.defaultLocale,
  );
  final response = await service.getExercises(userId, locale: locale);
  return ExerciseResponse(exerciseLibrary: response);
}
