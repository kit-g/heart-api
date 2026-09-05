library;

import 'dart:convert';

import 'package:heart/models/exercises.dart';

/// Sentinel caller id for the CDN publish: guaranteed never to match a real
/// `profiles.id` (Firebase uids don't look like this), so the list query's
/// `user_id IS NULL OR user_id = @userId` serves library rows only — `own`
/// is false throughout and the per-user preference join (`unit_system`,
/// `rest_timer`) comes back null for every row, exactly what an anonymous
/// caller should see.
const anonymousUserId = '00000000-0000-0000-0000-000000000000';

/// The rendered CDN objects for one publish run: one encoded JSON body per
/// locale file, plus the manifest. Kept as plain strings (rather than maps)
/// so the byte-for-byte content that gets written to disk is exactly what
/// this function produced, with no re-encoding step in between that could
/// drift from it.
typedef LibraryPublication = ({Map<String, String> localeFiles, String manifest});

/// Builds every object `static/exercises/` ships, by calling the same
/// [ExerciseService.getExercises] the `GET /v1/exercises` route calls — one
/// request per locale, under the anonymous sentinel — so the file content is
/// provably the API's own projection, not a second copy of it.
///
/// [locales] must include `en`: it is the manifest-driven resolution chain's
/// terminal fallback (exact tag, then bare language, then any supported
/// regional variant, then `en` — see `Request.locale`), so an `en.json` file
/// must always exist for the app to fall back to, even though any *other*
/// single locale already resolves correctly per-row without it (the query's
/// own COALESCE ladder ends at the master columns regardless).
Future<LibraryPublication> renderLibraryPublication({
  required ExerciseService service,
  required List<String> locales,
  required String version,
  required DateTime generatedAt,
}) async {
  if (!locales.contains('en')) {
    throw ArgumentError.value(locales, 'locales', 'must include "en", the app\'s terminal locale fallback');
  }

  final localeFiles = <String, String>{};
  for (final locale in locales) {
    final body = await service.getExercises(anonymousUserId, locale: locale);
    localeFiles[locale] = jsonEncode(body);
  }

  final manifest = jsonEncode(
    {
      'version': version,
      'generated_at': generatedAt.toIso8601String(),
      'locales': locales,
    },
  );

  return (localeFiles: localeFiles, manifest: manifest);
}
