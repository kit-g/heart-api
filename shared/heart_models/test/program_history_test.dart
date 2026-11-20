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
        (
          programId: program,
          actions: [
            ProgramAction(id: 'a1', programId: program, kind: .pause, at: at),
            ProgramAction(id: 'a2', programId: program, kind: .resume, at: at.add(const Duration(days: 1))),
          ],
          bases: [ProgramBase(id: 'b1', programId: program, exerciseId: exercise, value: 102.3, at: at)],
        ),
        (programId: other, actions: const [], bases: const []),
      ],
      cursor: 'MTIzfDAxOTA',
      hasMore: true,
    );

    test('a page round-trips, a program with no history too', () {
      expectRoundTrip(page, ProgramHistoryChanges.fromJson);
      final read = ProgramHistoryChanges.fromJson(wire(page));
      expect(read.programs.map((each) => each.programId), [program, other]);
      expect(read.programs.first.actions.map((action) => action.kind), <ProgramActionKind>[.pause, .resume]);
      expect(read.programs.first.bases.single.value, 102.3);
      expect(read.programs.last.actions, isEmpty);
      expect((read.cursor, read.hasMore), ('MTIzfDAxOTA', true));
    });

    test('a first read with nothing to report has no cursor', () {
      final read = ProgramHistoryChanges.fromJson({'programs': <Object>[], 'hasMore': false});
      expect(read.programs, isEmpty);
      expect((read.cursor, read.hasMore), (null, false));
      expect(wire(read), {'programs': <Object>[], 'hasMore': false});
    });

    test('a step or base this build cannot read is left out of its program, the rest stays', () {
      final json = wire(page);
      final first = (json['programs'] as List).first as Map;
      (first['actions'] as List).add({'id': 'a3', 'kind': 'pause'});
      (first['bases'] as List).add({'id': 'b2', 'value': 1});
      final read = ProgramHistoryChanges.fromJson(json);
      expect(read.programs.first.actions, hasLength(2));
      expect(read.programs.first.bases, hasLength(1));
    });
  });
}
