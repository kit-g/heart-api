/// Reading data from a newer vocabulary than this build knows.
///
/// A shipped app stays installed for months, and the server adds values — a
/// category, a set type, a goal metric — on its own schedule. One unknown word
/// must not fail the response that carries it, and an older build must never
/// delete or rewrite what it could not read. Two moves follow. A list is read
/// item by item and the items this build cannot read are set aside, [readEach].
/// A container — [Workout], [Template], [WorkoutExercise] — keeps its unread
/// children as the raw JSON they arrived as and writes them back in place on
/// `toMap`, so a save by an older build carries them untouched.
///
/// The strict `fromString` parsers are deliberately not part of this: they are
/// what the server validates input with, and a bad word in a request is a 400.
library;

import 'dart:math';

/// A list read item by item: what this build could read, and the raw items it
/// could not, each in its original order.
class ReadList<T> with Iterable<T> {
  final List<T> items;

  /// The items [readEach] could not read, as they arrived.
  final List<Map> unread;

  const new({required this.items, required this.unread});

  @override
  Iterator<T> get iterator => items.iterator;
}

/// Reads each of [items] with [read]. An item [read] rejects — an unknown word
/// ([ArgumentError]), a field of a shape this build predates ([TypeError]), a
/// malformed date or number ([FormatException]) — is set aside in
/// [ReadList.unread] instead of failing the whole list. Anything else [read]
/// throws is a bug, not a vocabulary, and propagates; so does an item that is
/// not a JSON object at all.
ReadList<T> readEach<T>(Iterable items, T Function(Map) read) {
  final indexed = readIndexed(items, read);
  return ReadList(items: indexed.items, unread: [for (final (_, json) in indexed.unread) json]);
}

/// [readEach] that remembers where each unread item sat, so a container can
/// write it back in place with [splice]. Anything but a list reads as empty.
/// Package-internal.
({List<T> items, List<(int, Map)> unread}) readIndexed<T>(Object? items, T Function(Map) read) {
  final out = <T>[];
  final unread = <(int, Map)>[];
  if (items is! Iterable) return (items: out, unread: unread);
  for (final (index, item) in items.indexed) {
    if (item is! Map) throw ArgumentError.value(item, 'items', 'not a JSON object');
    try {
      out.add(read(item));
    } on ArgumentError {
      unread.add((index, item));
    } on TypeError {
      unread.add((index, item));
    } on FormatException {
      unread.add((index, item));
    }
  }
  return (items: out, unread: unread);
}

/// [unread] items put back where they sat among [readable], for a write that
/// carries what this build could not read. A position is approximate once the
/// readable items were reordered or removed; the items themselves are
/// untouched. Package-internal.
List<Map> splice(List<Map> readable, List<(int, Map)> unread) {
  final out = [...readable];
  for (final (index, json) in unread) {
    out.insert(min(index, out.length), json);
  }
  return out;
}
