/// A service-layer page result.
///
/// [hasMore] is authoritative — the typical implementation fetches `limit + 1`
/// rows and reports whether the extra row appeared, so callers never have to
/// make a follow-up request to discover the list is exhausted.
class Page<T> with Iterable<T> {
  final List<T> items;
  final bool hasMore;

  const Page({required this.items, required this.hasMore});

  static const Page<Never> empty = Page(items: [], hasMore: false);

  @override
  Iterator<T> get iterator => items.iterator;
}
