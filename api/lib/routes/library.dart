import 'package:heart/core/request.dart';
import 'package:heart/globals/config.dart';
import 'package:heart/globals/globals.dart';
import 'package:heart/middleware/s3.dart';
import 'package:heart/models/library.dart';
import 'package:relic/relic.dart';

/// The program library in the caller's locale, exercises named from their
/// library; null while none is published (heart-api#259).
Future<LibraryView?> libraryView(Request req) async {
  final content = await req.programLibrary.read();
  if (content == null) return null;
  final config = req.config;
  final locale = req.locale(config.supportedLocales, config.defaultLocale);
  final library = await req.exerciseService.getExercises(req.userId, locale: locale);
  return LibraryView(
    content,
    locale: locale,
    exercises: {
      for (final exercise in (library['exercises'] as List? ?? const []).whereType<Map>())
        if (exercise case {'key': final String key, 'id': final Object id, 'name': final String name})
          key: (id: '$id', name: name),
    },
  );
}
