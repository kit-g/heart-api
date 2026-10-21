part of 'inputs.dart';

// Query inputs for the `/me` surface.

/// `GET /me/export?format=` — required, so a new default can never silently
/// change what an existing script downloads.
class ExportQuery {
  final ExportFormat format;

  const new _({required this.format});

  static ExportQuery read(Query q) {
    return ExportQuery._(
      format: q.choice('format', ExportFormat.values, (format) => format.name, description: 'The other app\'s format.'),
    );
  }
}

/// `GET /me/workouts/changes?since=&limit=` — no `since` starts from the
/// beginning; one that isn't a cursor from this feed is a 400, never a
/// silent restart.
class ChangesQuery {
  final ChangeCursor? since;
  final int limit;

  const new _({required this.since, required this.limit});

  static ChangesQuery read(Query q) {
    return ChangesQuery._(
      since: switch (q.stringOrNull(
        'since',
        description: 'The `cursor` of the last page read; none starts from the beginning.',
      )) {
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

  static RecordsQuery read(Query q) {
    final (:from, :to) = q.window();
    return RecordsQuery._(
      exerciseId: switch (q.stringOrNull('exerciseId', format: 'uuid', description: 'One exercise\'s records only.')) {
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

  static ExerciseHistoryQuery read(Query q) {
    final exerciseId = q.path('exerciseId', format: 'uuid');
    if (!isUuidV7(exerciseId)) throw NotFound(type: 'Exercise', id: exerciseId);
    final (:from, :to) = q.window();
    return ExerciseHistoryQuery._(
      exerciseId: exerciseId,
      cursor: switch (q.stringOrNull('cursor', description: 'The `cursor` of the last page.')) {
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

/// `GET /me/volume?from=&to=` and `GET /me/balance?from=&to=` — counts over
/// whole weeks; without `from`, the weeks ending with `to`'s, itself now when
/// absent. At most a year.
class LensQuery {
  final DateTime? from;
  final DateTime? to;

  const new _({required this.from, required this.to});

  static LensQuery read(Query q) {
    final (:from, :to) = q.window();
    if (from != null && (to ?? DateTime.timestamp()).difference(from) > LensWindow.longest) {
      throw const BadRequest(reason: 'from and to may be at most a year apart');
    }
    return LensQuery._(from: from, to: to);
  }
}

extension on Query {
  /// `from` and `to`: a window of workout start times, from inclusive and to
  /// exclusive, either open. Each is a date (`2026-01-01`, UTC) or an ISO
  /// moment.
  ({DateTime? from, DateTime? to}) window() {
    DateTime? edge(String key, String bound) {
      return switch (stringOrNull(
        key,
        description: 'Workouts started $bound: a date (2026-01-01, UTC) or an ISO moment.',
      )) {
        null => null,
        final String raw =>
          raw.toWindowEdge() ?? (throw BadRequest(reason: '$key must be a date (2026-01-01) or an ISO moment: $raw')),
      };
    }

    final (from, to) = (edge('from', 'at or after'), edge('to', 'before'));
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

  static const _qRequired = 'q is required: what to search for, up to 100 characters';

  /// [locale] is checked against the served ones by the route, which knows
  /// them.
  static LibrarySearchQuery read(Query q) {
    return LibrarySearchQuery._(
      query: switch (q.string('q', maxLength: 100, reason: _qRequired, description: 'What to search for.').trim()) {
        final String text when text.isNotEmpty => text,
        _ => throw const BadRequest(reason: _qRequired),
      },
      locale: q.stringOrNull('locale', description: 'A served locale; the request\'s Accept-Language when absent.'),
      limit: q.integer('limit', defaultValue: 20, min: 1, max: 50),
    );
  }
}
