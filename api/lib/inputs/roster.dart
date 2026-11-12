part of 'inputs.dart';

/// `GET /coach/feed?cursor=&limit=`. The cursor is the last item's time and id.
class CoachFeedQuery {
  final FeedCursor? cursor;
  final int limit;

  const new _({this.cursor, required this.limit});

  static CoachFeedQuery fromRequest(Request req) {
    final page = PageQuery.fromRequest(req, defaultLimit: 50);
    return CoachFeedQuery._(
      cursor: switch (page.cursor) {
        null => null,
        final raw => cursorOf(raw) ?? (throw const BadRequest(reason: 'cursor is not one from this feed')),
      },
      limit: page.limit,
    );
  }

  /// [raw] as a cursor of this feed's, or null if it can't be one.
  static FeedCursor? cursorOf(String raw) {
    return switch (raw.split('|')) {
      [final at, final id] when DateTime.tryParse(at) != null && id.isNotEmpty => (at: DateTime.parse(at), id: id),
      _ => null,
    };
  }
}

/// `GET /coach/clients?reason=&former=&cursor=&limit=`. The cursor is the last
/// client's rank, 0 for those who need a word and 1 for the rest, and connection id.
class RosterQuery {
  final String? reason;
  final bool former;
  final OrderedCursor? cursor;
  final int limit;

  const new _({this.reason, required this.former, this.cursor, required this.limit});

  static RosterQuery fromRequest(Request req) {
    final query = Query.of(req);
    final page = PageQuery.read(query, defaultLimit: 50);
    return RosterQuery._(
      reason: query.stringOrNull('reason'),
      former: query.boolean('former'),
      cursor: switch (page.cursor) {
        null => null,
        final raw => cursorOf(raw) ?? (throw const BadRequest(reason: 'cursor is not one from this list')),
      },
      limit: page.limit,
    );
  }

  /// [raw] as a cursor of this list's, or null if it can't be one.
  static OrderedCursor? cursorOf(String raw) {
    return switch (OrderedCursor.tryParse(raw)) {
      final OrderedCursor cursor when (cursor.order == 0 || cursor.order == 1) && isUuidV7(cursor.id) => cursor,
      _ => null,
    };
  }
}

/// `PUT /coach/clients/:connectionId/reviewed` — a JSON body, `{}` or `{at}` by the
/// device's clock.
class ClientReviewedIn {
  final String connectionId;
  final DateTime? at;

  const new _(this.connectionId, this.at);

  static Future<ClientReviewedIn> fromRequest(Request req) async {
    // an id that can't be one is no such client, not a database error
    final connectionId = switch (req.rawPathParameters[#connectionId]) {
      final String id when isUuidV7(id) => id,
      final id => throw NotFound(type: 'Client', id: id ?? ''),
    };
    final json = await req.json();
    return ClientReviewedIn._(connectionId, json.dateOrNull('at'));
  }
}
