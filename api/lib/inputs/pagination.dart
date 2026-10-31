part of 'inputs.dart';

/// Cursor-based pagination query for list endpoints: `?cursor=<opaque>&limit=N`.
///
/// The cursor is opaque to clients — it's whatever the previous page's response
/// returned, absent once the list is exhausted. [limit] is validated and
/// clamped so a client can't request an unbounded page.
class PageQuery {
  final String? cursor;
  final int limit;

  const new _({required this.cursor, required this.limit});

  static PageQuery fromRequest(Request req, {int defaultLimit = 30, int maxLimit = 100}) {
    return read(Query.of(req), defaultLimit: defaultLimit, maxLimit: maxLimit);
  }

  static PageQuery read(Query q, {int defaultLimit = 30, int maxLimit = 100}) {
    return PageQuery._(
      cursor: q.stringOrNull('cursor', description: 'The `cursor` of the last page.'),
      limit: q.integer('limit', defaultValue: defaultLimit, min: 1, max: maxLimit),
    );
  }
}
