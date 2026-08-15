/// A service-layer page result.
///
/// [hasMore] is authoritative — the typical implementation fetches `limit + 1`
/// rows and reports whether the extra row appeared, so callers never have to
/// make a follow-up request to discover the list is exhausted.
class Page<T> with Iterable<T> {
  final List<T> items;
  final bool hasMore;

  const new({required this.items, required this.hasMore});

  static const Page<Never> empty = Page(items: [], hasMore: false);

  @override
  Iterator<T> get iterator => items.iterator;
}

/// A keyset cursor for a list ordered by `(order, id)` rather than by `id` alone.
///
/// Most list endpoints here page on the item's id, which works because uuidv7 is
/// chronological. A list the user has *arranged* cannot: `order` is not unique,
/// so the id rides along as the tie-break and the pair is what the query
/// compares. Templates are the one such list today.
///
/// The wire form is `<order>:<id>` and is opaque to clients — they only ever
/// echo back what the previous page returned.
class OrderedCursor {
  final int order;
  final String id;

  const new({required this.order, required this.id});

  @override
  String toString() => '$order:$id';

  /// Returns null for a cursor that is absent *or* unparseable, leaving the
  /// caller to decide which of those is an error — an absent cursor means "first
  /// page", a malformed one means the client made it up.
  static OrderedCursor? tryParse(String? raw) {
    if (raw == null) return null;
    final separator = raw.indexOf(':');
    if (separator <= 0 || separator == raw.length - 1) return null;
    final order = int.tryParse(raw.substring(0, separator));
    return order == null ? null : OrderedCursor(order: order, id: raw.substring(separator + 1));
  }
}
