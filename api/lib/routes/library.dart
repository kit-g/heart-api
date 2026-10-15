import 'package:heart/core/request.dart';
import 'package:heart/globals/config.dart';
import 'package:heart/globals/globals.dart';
import 'package:heart/middleware/s3.dart';
import 'package:heart/models/library.dart';
import 'package:relic/relic.dart';

/// The program library in the caller's locale; null while none is published
/// (heart-api#259).
///
/// [named] reads the caller's exercise library too, to name a program's
/// exercises and anchor a copy's research by id. A list of programs needs
/// neither. [library] is that library when the caller has already read it.
Future<LibraryView?> libraryView(Request req, {bool named = true, Map<String, dynamic>? library}) async {
  final content = await req.programLibrary.read();
  if (content == null) return null;
  final config = req.config;
  final locale = req.locale(config.supportedLocales, config.defaultLocale);
  final exercises = switch ((named, library)) {
    (false, _) => const <String, dynamic>{},
    (true, final Map<String, dynamic> library) => library,
    (true, null) => await req.exerciseService.getExercises(req.userId, locale: locale),
  };
  return LibraryView(
    content,
    locale: locale,
    exercises: {
      for (final exercise in (exercises['exercises'] as List? ?? const []).whereType<Map>())
        if (exercise case {'key': final String key, 'id': final Object id, 'name': final String name})
          key: (id: '$id', name: name),
    },
  );
}
