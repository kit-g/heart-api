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

/// `GET /me/records?exerciseId=&from=&to=` — every exercise's records, or
/// one's; within a window of workout start times when one is given.
class RecordsQuery {
  final String? exerciseId;
  final DateTime? from;
  final DateTime? to;

  const new _({required this.exerciseId, required this.from, required this.to});

  static RecordsQuery fromRequest(Request req) {
    final q = req.url.queryParameters;
    final (:from, :to) = q.window();
    return RecordsQuery._(
      exerciseId: switch (q.stringOrNull('exerciseId')) {
        null => null,
        final String id when isUuidV7(id) => id,
        final String id => throw BadRequest(reason: 'exerciseId is not an exercise id: $id'),
      },
      from: from,
      to: to,
    );
  }
}

/// `GET /me/exercises/:exerciseId/history?cursor=&limit=&from=&to=` — one
/// exercise's sessions, newest first. The cursor is a workout id from the
/// last page.
class ExerciseHistoryQuery {
  final String exerciseId;
  final String? cursor;
  final int limit;
  final DateTime? from;
  final DateTime? to;

  const new _({
    required this.exerciseId,
    required this.cursor,
    required this.limit,
    required this.from,
    required this.to,
  });

  static ExerciseHistoryQuery fromRequest(Request req, {required String exerciseId}) {
    if (!isUuidV7(exerciseId)) throw NotFound(type: 'Exercise', id: exerciseId);
    final q = req.url.queryParameters;
    final (:from, :to) = q.window();
    return ExerciseHistoryQuery._(
      exerciseId: exerciseId,
      cursor: switch (q.stringOrNull('cursor')) {
        null => null,
        final String id when isUuidV7(id) => id,
        final String id => throw BadRequest(reason: 'cursor is not one this list returned: $id'),
      },
      limit: q.integer('limit', defaultValue: 20, min: 1, max: 100),
      from: from,
      to: to,
    );
  }
}

extension on Map<String, String> {
  /// `from` and `to`: a window of workout start times, from inclusive and to
  /// exclusive, either open. Each is a date (`2026-01-01`, UTC) or an ISO
  /// moment.
  ({DateTime? from, DateTime? to}) window() {
    DateTime? edge(String key) {
      return switch (stringOrNull(key)) {
        null => null,
        final String raw =>
          raw.toWindowEdge() ?? (throw BadRequest(reason: '$key must be a date (2026-01-01) or an ISO moment: $raw')),
      };
    }

    final (from, to) = (edge('from'), edge('to'));
    if (from != null && to != null && !from.isBefore(to)) throw const BadRequest(reason: 'from must be before to');
    return (from: from, to: to);
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
