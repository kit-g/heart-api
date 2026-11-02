part of 'inputs.dart';

/// A page whose cursor isn't an id, as a feed sorted by time has.
class PageTokenQuery {
  final String? cursor;
  final int limit;

  const new _({this.cursor, required this.limit});

  static PageTokenQuery fromRequest(Request req) {
    final query = req.url.queryParameters;
    final limit = switch (query['limit']) {
      null => 50,
      final String raw => switch (int.tryParse(raw)) {
        final int limit when limit >= 1 => limit > 100 ? 100 : limit,
        _ => throw const BadRequest(reason: 'limit must be a positive integer'),
      },
    };
    return PageTokenQuery._(cursor: query['cursor'], limit: limit);
  }
}

/// `GET /coach/clients?reason=&former=&cursor=&limit=`.
class RosterQuery {
  final String? reason;
  final bool former;
  final String? cursor;
  final int limit;

  const new _({this.reason, required this.former, this.cursor, required this.limit});

  static RosterQuery fromRequest(Request req) {
    final query = req.url.queryParameters;
    final page = PageTokenQuery.fromRequest(req);
    return RosterQuery._(
      reason: query['reason'],
      former: query['former'] == 'true',
      cursor: page.cursor,
      limit: page.limit,
    );
  }
}

/// `PUT /coach/clients/:connectionId/reviewed` — optionally `{at}`, by the device's clock.
class ClientReviewedIn {
  final DateTime? at;

  const new _(this.at);

  static Future<ClientReviewedIn> fromRequest(Request req) async {
    final json = await req.json();
    return ClientReviewedIn._(
      switch (json['at']) {
        null => null,
        final String at when DateTime.tryParse(at) != null => DateTime.parse(at),
        _ => throw const BadRequest(reason: 'at must be an ISO-8601 time'),
      },
    );
  }
}
