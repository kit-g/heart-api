import 'package:heart_models/heart_models.dart';
import 'package:test/test.dart';

import 'wire.dart';

void main() {
  const connection = '01900000-0000-7000-8000-000000000001';
  final at = DateTime.utc(2026, 11, 1, 9, 30);
  final later = DateTime.utc(2026, 11, 2, 18);

  group('threads', () {
    final row = {
      'id': 't1',
      'connection_id': connection,
      'other_id': 'u2',
      'other_name': 'Alex',
      'other_avatar': 'https://cdn/a.png',
      'unread': 3,
      'last_at': at,
      'cleared_at': later,
      'cleared_by': 'u2',
    };

    test('Thread round-trips', () => expectRoundTrip(Thread.fromRow(row), Thread.fromJson));

    test('ThreadList round-trips, with the unread it adds up', () {
      final list = ThreadList([
        Thread.fromRow(row),
        Thread.fromRow({'id': 't2', 'unread': 2}),
      ]);
      expectRoundTrip(list, ThreadList.fromJson);
      expect(wire(list)['unread'], 5);
    });

    test('ThreadList reads an inbox as the API sends it, someone gone too', () {
      final read = ThreadList.fromJson(
        wire(
          ThreadList([
            Thread.fromRow(row),
            Thread.fromRow({'id': 't2', 'connection_id': null, 'other_id': null, 'unread': null}),
          ]),
        ),
      );
      expect(read.threads.first.lastAt, at);
      expect(read.threads.first.clearedAt, later);
      expect(read.threads.last.otherId, isNull);
      expect(read.threads.last.unread, 0);
    });

    final note = CoachNote.fromRow({'id': 'n1', 'connection_id': connection, 'content': 'sealed', 'updated_at': at});

    test('CoachNote round-trips', () => expectRoundTrip(note, CoachNote.fromJson));

    test('CoachNote reads a page of notes as the API sends it', () {
      final page = {
        'notes': [
          wire(note),
          wire(CoachNote.fromRow({'id': 'n2', 'content': 'x', 'updated_at': later})),
        ],
        'cursor': 'n2',
      };
      final read = readEach(page['notes']! as List, CoachNote.fromJson);
      expect(read.items.map((note) => note.id), ['n1', 'n2']);
      expect(read.items.first.connectionId, connection);
      expect(read.items.last.connectionId, isNull);
      expect(read.unread, isEmpty);
    });
  });
}
