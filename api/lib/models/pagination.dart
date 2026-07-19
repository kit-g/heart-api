import 'package:heart_models/heart_models.dart';

/// HTTP-layer paginated response. Emits a `cursor` field only when there's
/// actually a next page — clients shouldn't have to make a wasted round trip
/// to discover the list is exhausted. Pair with [Page] from heart_models on
/// the service side.
class Paginated<T extends Model> with Iterable<T> implements Model {
  final Iterable<T> items;
  final String itemsKey;
  final String? cursor;

  const Paginated({required this.items, required this.itemsKey, this.cursor});

  /// Builds a [Paginated] from a service [Page]. The next-page cursor is only
  /// emitted when `page.hasMore` is true. Its value is [Page.cursor] when the
  /// service supplied one explicitly (the ordering key isn't a serialized item
  /// field), otherwise it's derived from the last item via [cursorOf].
  factory Paginated.from(
    Page<T> page, {
    required String itemsKey,
    String Function(T)? cursorOf,
  }) {
    final hasNext = page.hasMore && page.items.isNotEmpty;
    return Paginated(
      items: page,
      itemsKey: itemsKey,
      cursor: hasNext ? (page.cursor ?? cursorOf?.call(page.items.last)) : null,
    );
  }

  @override
  Map<String, dynamic> toMap() {
    return {
      itemsKey: map((i) => i.toMap()).toList(),
      'cursor': ?cursor,
    };
  }

  @override
  Iterator<T> get iterator => items.iterator;
}
