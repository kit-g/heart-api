/// A service-layer page result.
///
/// [hasMore] is authoritative — the typical implementation fetches `limit + 1`
/// rows and reports whether the extra row appeared, so callers never have to
/// make a follow-up request to discover the list is exhausted.
///
/// [cursor] is an optional explicit next-page cursor, for endpoints whose
/// ordering key isn't a serialized field on [T] (e.g. template shares order by
/// an internal `share_uuid`). When it's null, the HTTP layer derives the cursor
/// from the last item instead.
class Page<T> with Iterable<T> {
  final List<T> items;
  final bool hasMore;
  final String? cursor;

  const Page({required this.items, required this.hasMore, this.cursor});

  static const Page<Never> empty = Page(items: [], hasMore: false);

  @override
  Iterator<T> get iterator => items.iterator;
}
