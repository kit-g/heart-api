import 'package:heart_models/heart_models.dart';

/// HTTP-layer paginated response. Emits a `cursor` field only when there's
/// actually a next page — clients shouldn't have to make a wasted round trip
/// to discover the list is exhausted. Pair with [Page] from heart_models on
/// the service side.
class Paginated<T extends Model> with Iterable<T> implements Model {
  final Iterable<T> items;
  final String itemsKey;
  final String? cursor;

  const new({required this.items, required this.itemsKey, this.cursor});

  /// Builds a [Paginated] from a service [Page]. [cursorOf] extracts the
  /// cursor value from the last item when `page.hasMore` is true.
  factory from(
    Page<T> page, {
    required String itemsKey,
    required String Function(T) cursorOf,
  }) {
    return Paginated(
      items: page,
      itemsKey: itemsKey,
      cursor: page.hasMore && page.items.isNotEmpty ? cursorOf(page.items.last) : null,
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
