import 'package:heart_models/heart_models.dart';
import 'package:test/test.dart';

import 'wire.dart';

void main() {
  const program = '01900000-0000-7000-8000-000000000002';
  const session = '01900000-0000-7000-8000-000000000003';
  final at = DateTime.utc(2026, 11, 1, 9, 30);
  final later = DateTime.utc(2026, 11, 2, 18);

  group('program changes', () {
    final row = {
      'id': 'ch1',
      'program_id': program,
      'session_id': session,
      'actor_id': 'coach',
      'kind': 'edit',
      'revision': 4,
      'before': {'name': 'Day'},
      'after': {'name': 'Day 1'},
      'stale': true,
      'at': at,
    };

    test('ProgramChange round-trips, stale and not', () {
      expectRoundTrip(ProgramChange.fromRow(row, cursor: 'c1'), ProgramChange.fromJson);
      expectRoundTrip(
        ProgramChange.fromRow({...row, 'session_id': null, 'before': null, 'stale': false}),
        ProgramChange.fromJson,
      );
    });

    test('ProgramChanges reads what changed as the API sends it, a kind it does not know too', () {
      final changes = ProgramChanges([
        ProgramChange.fromRow(row, cursor: 'c1'),
        ProgramChange.fromRow({...row, 'id': 'ch2', 'kind': 'merge', 'stale': null}, cursor: 'c2'),
      ]);
      expectRoundTrip(changes, ProgramChanges.fromJson);
      final read = ProgramChanges.fromJson(wire(changes));
      expect(read.changes.first.stale, isTrue);
      expect(read.changes.first.after, {'name': 'Day 1'});
      expect(read.changes.last.kind, 'merge');
      expect(read.changes.last.stale, isFalse);
      expect(read.changes.last.cursor, 'c2');
    });

    test('WorkoutPlan round-trips and reads the API body', () {
      final plan = const WorkoutPlan({
        'templateId': session,
        'exercises': [
          {'exercise': 'Squat', 'sets': 3},
        ],
      });
      expectRoundTrip(plan, WorkoutPlan.fromJson);
      expect(WorkoutPlan.fromJson(wire(plan)).plan['templateId'], session);
    });

    // what `getCopy` builds: a coach's copy, its sessions, and its position folded
    // as the route folds it
    final copy = Program(
      id: program,
      name: 'Plan',
      sessions: [session],
      perWeek: 3,
      weeks: 4,
      coachId: 'coach',
      coachName: 'Coach',
      revision: 2,
      sessionRevisions: {session: 1},
    );
    final view = CoachProgramView(
      program: copy,
      sessions: [
        Template.fromJson(const {'id': session, 'name': 'Day', 'order': 0, 'programId': program}),
      ],
      position: ProgramPosition.of(copy, marks: const [], actions: const [], now: later).toMap(),
    );

    test('CoachProgramView round-trips', () => expectRoundTrip(view, CoachProgramView.fromJson));

    test('CoachProgramView reads a copy as the API sends it', () {
      final read = CoachProgramView.fromJson(wire(view));
      expect(read.program.coachId, 'coach');
      expect(read.program.revision, 2);
      expect(read.program.sessionRevisions, {session: 1});
      expect(read.sessions.single.id, session);
      expect(read.position['week'], 1);
      expect(read.position['next'], session);
    });
  });
}
