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
