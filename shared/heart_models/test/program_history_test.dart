import 'package:heart_models/heart_models.dart';
import 'package:test/test.dart';

import 'wire.dart';

void main() {
  const program = '01900000-0000-7000-8000-000000000002';
  const other = '01900000-0000-7000-8000-000000000004';
  const exercise = '01900000-0000-7000-8000-000000000005';
  final at = DateTime.utc(2026, 11, 1, 9, 30);

  group('every program\'s history in one read (heart-api#458)', () {
    final page = ProgramHistoryChanges(
      programs: [
        ProgramHistoryOf(
          programId: program,
          actions: [
            ProgramAction(id: 'a1', programId: program, kind: .pause, at: at),
            ProgramAction(id: 'a2', programId: program, kind: .resume, at: at.add(const Duration(days: 1))),
          ],
          bases: [ProgramBase(id: 'b1', programId: program, exerciseId: exercise, value: 102.3, at: at)],
        ),
        ProgramHistoryOf(programId: other),
      ],
      cursor: 'MTIzfDAxOTA',
      hasMore: true,
    );

    test('a page round-trips, a program with no history too', () {
      expectRoundTrip(page, ProgramHistoryChanges.fromJson);
      final read = ProgramHistoryChanges.fromJson(wire(page));
      expect(read.isWhole, isTrue);
      expect(read.programs.map((each) => each.programId), [program, other]);
      expect(read.programs.first.actions.map((action) => action.kind), <ProgramActionKind>[.pause, .resume]);
      expect(read.programs.first.bases.single.value, 102.3);
      expect(read.programs.last.actions, isEmpty);
      expect((read.cursor, read.hasMore), ('MTIzfDAxOTA', true));
    });

    test('each step and base leaves its programId to the program, and reads it back from there', () {
      final first = (wire(page)['programs'] as List).first as Map;
      expect((first['actions'] as List).first, isNot(contains('programId')));
      expect((first['bases'] as List).single, isNot(contains('programId')));
      final read = ProgramHistoryChanges.fromJson(wire(page)).programs.first;
      expect(read.actions.map((action) => action.programId), [program, program]);
      expect(read.bases.single.programId, program);
    });

    test('a first read with nothing to report has no cursor', () {
      final read = ProgramHistoryChanges.fromJson({'programs': <Object>[], 'hasMore': false});
      expect(read.programs, isEmpty);
      expect((read.cursor, read.hasMore), (null, false));
      expect(wire(read), {'programs': <Object>[], 'hasMore': false});
    });

    test('a step of a kind this build does not know is set aside and written back, not lost', () {
      final json = wire(page);
      final first = (json['programs'] as List).first as Map;
      final unknown = {'id': 'a3', 'kind': 'deload', 'week': 4, 'at': at.toIso8601String()};
      (first['actions'] as List).insert(1, unknown);
      final read = ProgramHistoryChanges.fromJson(json);
      final history = read.programs.first;
      expect(history.actions.map((action) => action.id), ['a1', 'a2']);
      expect(history.unreadActions, [unknown]);
      expect((history.isWhole, read.isWhole), (false, false));
      expect(read.programs.last.isWhole, isTrue);
      expect(wire(read), json, reason: 'written back where it sat');
    });

    test('a base this build cannot read is set aside the same way', () {
      final json = wire(page);
      final first = (json['programs'] as List).first as Map;
      final odd = {'id': 'b2', 'value': 'heavy'};
      (first['bases'] as List).add(odd);
      final history = ProgramHistoryChanges.fromJson(json).programs.first;
      expect(history.bases.map((base) => base.id), ['b1']);
      expect(history.unreadBases, [odd]);
      expect(history.isWhole, isFalse);
    });

    test('a program missing a list is set aside, never read as an emptied history', () {
      final json = wire(page);
      final first = (json['programs'] as List).first as Map..remove('actions');
      final read = ProgramHistoryChanges.fromJson(json);
      expect(read.programs.map((each) => each.programId), [other]);
      expect(read.unread, [first]);
      expect(read.isWhole, isFalse);
      expect(wire(read), json, reason: 'written back where it sat');
    });

    test('a program without an id is set aside, and the rest of the page still reads', () {
      final json = wire(page);
      (json['programs'] as List).add({'actions': <Object>[], 'bases': <Object>[]});
      final read = ProgramHistoryChanges.fromJson(json);
      expect(read.programs, hasLength(2));
      expect(read.unread, hasLength(1));
    });
  });
}
