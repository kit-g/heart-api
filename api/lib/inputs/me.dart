part of 'inputs.dart';

// Query inputs for the `/me` surface.

/// `GET /me/export?format=` — required, so a new default can never silently
/// change what an existing script downloads.
class ExportQuery {
  final ExportFormat format;

  const new _({required this.format});

  static ExportQuery fromRequest(Request req) {
    final q = req.url.queryParameters;
    return ExportQuery._(format: q.parsed('format', ExportFormat.fromString));
  }
}

/// `GET /me/workouts/changes?since=&limit=` — no `since` starts from the
/// beginning; one that isn't a cursor from this feed is a 400, never a
/// silent restart.
class ChangesQuery {
  final ChangeCursor? since;
  final int limit;

  const new _({required this.since, required this.limit});

  static ChangesQuery fromRequest(Request req) {
    final q = req.url.queryParameters;
    return ChangesQuery._(
      since: switch (q.stringOrNull('since')) {
        final String raw => ChangeCursor.parse(raw),
        null => null,
      },
      limit: q.integer('limit', defaultValue: 100, min: 1, max: 100),
    );
  }
}

/// `GET /me/records?exerciseId=` — every exercise's records, or one's.
class RecordsQuery {
  final String? exerciseId;

  const new _({required this.exerciseId});

  static RecordsQuery fromRequest(Request req) {
    return RecordsQuery._(
      exerciseId: switch (req.url.queryParameters.stringOrNull('exerciseId')) {
        null => null,
        final String id when isUuidV7(id) => id,
        final String id => throw BadRequest(reason: 'exerciseId is not an exercise id: $id'),
      },
    );
  }
}

/// `GET /me/exercises/:exerciseId/history?cursor=&limit=` — one exercise's
/// sessions, newest first. The cursor is a workout id from the last page.
class ExerciseHistoryQuery {
  final String exerciseId;
  final String? cursor;
  final int limit;

  const new _({required this.exerciseId, required this.cursor, required this.limit});

  static ExerciseHistoryQuery fromRequest(Request req, {required String exerciseId}) {
    if (!isUuidV7(exerciseId)) throw NotFound(type: 'Exercise', id: exerciseId);
    final q = req.url.queryParameters;
    return ExerciseHistoryQuery._(
      exerciseId: exerciseId,
      cursor: switch (q.stringOrNull('cursor')) {
        null => null,
        final String id when isUuidV7(id) => id,
        final String id => throw BadRequest(reason: 'cursor is not one this list returned: $id'),
      },
      limit: q.integer('limit', defaultValue: 20, min: 1, max: 100),
    );
  }
}

/// `GET /me/library?q=&locale=&limit=` — the exercise library and the
/// user's own exercises, searched the way the app searches. [locale] is a
/// served locale, or null for the request's `Accept-Language`.
class LibrarySearchQuery {
  final String query;
  final String? locale;
  final int limit;

  const new _({required this.query, required this.locale, required this.limit});

  static LibrarySearchQuery fromRequest(Request req, {required List<String> supportedLocales}) {
    final q = req.url.queryParameters;
    return LibrarySearchQuery._(
      query: switch (q.stringOrNull('q')?.trim()) {
        final String text when text.isNotEmpty && text.length <= 100 => text,
        _ => throw const BadRequest(reason: 'q is required: what to search for, up to 100 characters'),
      },
      locale: switch (q.stringOrNull('locale')) {
        null => null,
        final String locale when supportedLocales.contains(locale) => locale,
        final String locale => throw BadRequest(
          reason: 'locale must be one of ${supportedLocales.join(', ')}: $locale',
        ),
      },
      limit: q.integer('limit', defaultValue: 20, min: 1, max: 50),
    );
  }
}
