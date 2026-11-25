import 'package:heart_models/heart_models.dart';
import 'package:test/test.dart';

import 'wire.dart';

void main() {
  const connection = '01900000-0000-7000-8000-000000000001';
  const program = '01900000-0000-7000-8000-000000000002';
  const session = '01900000-0000-7000-8000-000000000003';
  final at = DateTime.utc(2026, 11, 1, 9, 30);
  final later = DateTime.utc(2026, 11, 2, 18);

  group('roster', () {
    final row = {
      'connection_id': connection,
      'student_id': 's1',
      'username': 'Sam',
      'avatar_url': 'https://cdn/s.png',
      'status': 'active',
      'accepted_at': at,
      'program_id': program,
      'program_name': 'Plan',
      'program_week': 2,
      'program_weeks': 8,
      'recent': [at, later],
      'last_trained_at': later,
      'reasons': ['lighter', 'gap'],
      'assistant': true,
    };

    test('ClientSummary round-trips', () {
      expectRoundTrip(ClientSummary.fromRow(row), ClientSummary.fromJson);
      expectRoundTrip(
        ClientSummary(connectionId: connection, studentId: 's2', status: 'active'),
        ClientSummary.fromJson,
      );
    });

    test("ClientSummary says whether the client shares with the coach's assistant, false when not said", () {
      expect(ClientSummary.fromRow(row).assistant, isTrue);
      expect(ClientSummary.fromJson(wire(ClientSummary.fromRow(row))).assistant, isTrue);
      expect(ClientSummary.fromJson({...wire(ClientSummary.fromRow(row))}..remove('assistant')).assistant, isFalse);
    });

    test('ClientSummary reads a roster page as the API sends it, a reason it does not know too', () {
      final page = {
        'clients': [
          wire(
            ClientSummary.fromRow({
              ...row,
              'reasons': ['lighter', 'something_new'],
            }),
          ),
          // `GET /coach/clients` in api/test/routes/roster_test.dart
          wire(ClientSummary(connectionId: session, studentId: 's2', status: 'active')),
        ],
      };
      final read = readEach(page['clients']!, ClientSummary.fromJson);
      expect(read.unread, isEmpty);
      expect(read.items.first.recent, [at, later]);
      expect(read.items.first.reasons, ['lighter', 'something_new']);
      expect(read.items.first.programWeek, 2);
      expect(read.items.last.acceptedAt, isNull);
      expect(read.items.last.recent, isEmpty);
    });

    final item = CoachFeedItem.fromRow({
      'kind': 'workout',
      'id': 'w1',
      'student_id': 's1',
      'username': 'Sam',
      'avatar_url': null,
      'at': at,
      'title': 'Push day',
    }, cursor: 'opaque');

    test('CoachFeedItem round-trips', () => expectRoundTrip(item, CoachFeedItem.fromJson));

    test('which copies changed, read from a row and round-tripped, and one this build can\'t read left out', () {
      final changed = ClientSummary.fromRow({
        ...row,
        'changed_programs': [
          {'program_id': 'p2', 'at': '2026-01-03T00:00:00+00:00'},
          {'program_id': 'p1', 'at': '2026-01-02T00:00:00+00:00'},
        ],
      });
      expect(changed.changedPrograms, [
        ChangedProgram('p2', DateTime.utc(2026, 1, 3)),
        ChangedProgram('p1', DateTime.utc(2026, 1, 2)),
      ]);
      expectRoundTrip(changed, ClientSummary.fromJson);

      final odd = {
        ...wire(changed),
        'changedPrograms': [
          {'programId': 'p1', 'changedAt': 'not a time'},
          {'programId': 7},
          {'programId': 'p3', 'changedAt': '2026-01-04T00:00:00.000Z'},
        ],
      };
      expect(ClientSummary.fromJson(odd).changedPrograms, [ChangedProgram('p3', DateTime.utc(2026, 1, 4))]);
      expect(ClientSummary.fromJson({...wire(changed)}..remove('changedPrograms')).changedPrograms, isEmpty);
    });

    test('a name the coach gave says so, in the roster and the feed, false when not said', () {
      final summary = ClientSummary.fromRow({...row, 'named_by_you': true});
      expect(summary.namedByYou, isTrue);
      expectRoundTrip(summary, ClientSummary.fromJson);
      expect(ClientSummary.fromRow(row).namedByYou, isFalse);
      expect(ClientSummary.fromJson({...wire(summary)}..remove('namedByYou')).namedByYou, isFalse);

      final set = ClientSummary.fromRow({
        ...row,
        'named_by_you': true,
        'name_set_by_you': true,
        'fallback_name': 'Sam from the gym',
      });
      expect((set.nameSetByYou, set.fallbackName), (true, 'Sam from the gym'));
      expectRoundTrip(set, ClientSummary.fromJson);
      final unsaid = {...wire(summary)}
        ..remove('nameSetByYou')
        ..remove('fallbackName');
      expect((ClientSummary.fromJson(unsaid).nameSetByYou, ClientSummary.fromJson(unsaid).fallbackName), (false, null));

      final named = CoachFeedItem.fromRow({
        'kind': 'skip',
        'id': 'k1',
        'student_id': 's1',
        'at': at,
        'named_by_you': true,
      });
      expect(named.namedByYou, isTrue);
      expect(CoachFeedItem.fromJson(wire(named)).namedByYou, isTrue);
      expect(item.namedByYou, isFalse);
    });

    test('CoachFeedItem reads a feed page as the API sends it, a kind it does not know too', () {
      final page = {
        'items': [
          wire(item),
          {...wire(item), 'kind': 'milestone', 'id': 'x'},
        ],
        'cursor': 'opaque',
      };
      final read = readEach(page['items']! as List, CoachFeedItem.fromJson);
      expect(read.items.map((item) => item.kind), ['workout', 'milestone']);
      expect(read.items.first.at, at);
      // the page's cursor is the one to pass back; the items carry none
      expect(read.items.first.cursor, isNull);
    });
  });
}
