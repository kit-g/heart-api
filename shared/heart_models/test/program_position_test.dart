import 'package:heart_models/heart_models.dart';
import 'package:test/test.dart';

/// A v7 id minted at [at], with a fixed tail: the fold reads the creation time
/// off the id.
var _seq = 0;
String _v7(DateTime at) {
  final ms = at.millisecondsSinceEpoch.toRadixString(16).padLeft(12, '0');
  final tail = (_seq++).toRadixString(16).padLeft(12, '0');
  return '${ms.substring(0, 8)}-${ms.substring(8)}-7000-8000-$tail';
}

void main() {
  // v7 ids carry their creation time; sessions A, B, C were made on Oct 1
  final a = _v7(DateTime.utc(2026, 10, 1));
  final b = _v7(DateTime.utc(2026, 10, 1, 0, 0, 1));
  final c = _v7(DateTime.utc(2026, 10, 1, 0, 0, 2));
  final program = Program(name: 'Getting stronger', sessions: [a, b, c], perWeek: 3, weeks: 4);
  final now = DateTime.utc(2026, 10, 30, 12); // a Friday

  ProgramMark done(String id, int day) => ProgramMark(templateId: id, at: DateTime.utc(2026, 10, day), isWorkout: true);
  ProgramMark skipped(String id, int day) =>
      ProgramMark(templateId: id, at: DateTime.utc(2026, 10, day), isWorkout: false);
  ProgramAction act(ProgramActionKind kind, int day, {int? week}) =>
      ProgramAction(kind: kind, week: week, at: DateTime.utc(2026, 10, day, 12));

  ProgramPosition fold(List<ProgramMark> marks, [List<ProgramAction> actions = const []]) {
    return ProgramPosition.of(program, marks: marks, actions: actions, now: now);
  }

  test('a new program is week 1, everything remaining, the first session next', () {
    final position = fold([]);
    expect(position.week, 1);
    expect(position.remaining, [a, b, c]);
    expect(position.next, a);
    expect(position.paused, isFalse);
  });

  test('any order, any day: a cycle is complete when every session is done or skipped', () {
    final position = fold([done(c, 2), skipped(a, 5), done(b, 9)]);
    expect(position.week, 2);
    expect(position.done, isEmpty);
    expect(position.next, a);
  });

  test('doing a session twice counts once', () {
    final position = fold([done(a, 2), done(a, 3), done(b, 4)]);
    expect(position.week, 1);
    expect(position.remaining, [c]);
    expect(position.next, c);
  });

  test('a mark naming no current session moves nothing', () {
    final position = fold([
      ProgramMark(templateId: null, at: DateTime.utc(2026, 10, 2), isWorkout: true),
      ProgramMark(templateId: 'gone', at: DateTime.utc(2026, 10, 3), isWorkout: true),
    ]);
    expect(position.done, isEmpty);
    expect(position.week, 1);
  });

  test('a session added later joins the next cycle, never undoes the past', () {
    final d = _v7(DateTime.utc(2026, 10, 3));
    final grown = Program(name: 'p', sessions: [a, b, c, d]);
    final position = ProgramPosition.of(
      grown,
      marks: [done(a, 2), done(b, 4), done(c, 6)],
      actions: const [],
      now: now,
    );
    expect(position.week, 2, reason: 'D was added after the first cycle opened');
    expect(position.remaining, [a, b, c, d]);
  });

  test('marks older than every session, a clock behind, still complete a cycle', () {
    final late = Program(name: 'p', sessions: [_v7(DateTime.utc(2026, 11)), _v7(DateTime.utc(2026, 11))]);
    final position = ProgramPosition.of(
      late,
      marks: [
        ProgramMark(templateId: late.sessions.first, at: DateTime.utc(2026, 10, 2), isWorkout: true),
        ProgramMark(templateId: late.sessions.last, at: DateTime.utc(2026, 10, 3), isWorkout: true),
      ],
      actions: const [],
      now: now,
    );
    expect(position.week, 2);
  });

  test('an old template filed into the program later joins when it was filed, not when it was made', () {
    final old = _v7(DateTime.utc(2025, 1, 1));
    final filed = Program(
      name: 'p',
      sessions: [a, b, c, old],
      joined: {old: DateTime.utc(2026, 10, 3)},
    );
    final position = ProgramPosition.of(
      filed,
      marks: [done(a, 2), done(b, 4), done(c, 6)],
      actions: const [],
      now: now,
    );
    expect(position.week, 2, reason: 'the old template joined after the first cycle opened');
  });

  test('a paused or finished program has no weekly target; the count stays a fact', () {
    expect(fold([done(a, 26)]).target, 3);
    final paused = fold([done(a, 26)], [act(.pause, 27)]);
    expect(paused.target, isNull);
    expect(paused.thisWeek, 1);
  });

  test('repeat right after a cycle runs that week again', () {
    final position = fold([done(a, 2), done(b, 3), done(c, 4)], [act(.repeat, 4)]);
    expect(position.week, 1);
    expect(position.remaining, [a, b, c]);
  });

  test('repeat mid-cycle restarts the open cycle at its week', () {
    final position = fold([done(a, 2), done(b, 3), done(c, 4), done(a, 6)], [act(.repeat, 6)]);
    expect(position.week, 2);
    expect(position.done, isEmpty);
  });

  test('replay goes back to its week', () {
    final marks = [
      for (var day = 2; day < 11; day += 3) ...[done(a, day), done(b, day), done(c, day)],
    ];
    final position = fold(marks, [act(.replay, 11, week: 1)]);
    expect(position.week, 1);
  });

  test('pause holds until a resume or a program workout; a skip keeps it paused', () {
    expect(fold([], [act(.pause, 2)]).paused, isTrue);
    expect(fold([], [act(.pause, 2), act(.resume, 3)]).paused, isFalse);
    expect(fold([skipped(a, 3)], [act(.pause, 2)]).paused, isTrue);
    expect(fold([done(a, 3)], [act(.pause, 2)]).paused, isFalse);
  });

  test('a program with a length finishes; then nothing is next', () {
    final marks = [
      for (var week = 0; week < 4; week++) ...[done(a, 2 + week * 3), done(b, 2 + week * 3), done(c, 2 + week * 3)],
    ];
    final position = fold(marks);
    expect(position.week, 5);
    expect(position.finished, isTrue);
    expect(position.next, isNull);
  });

  test('this week counts program workouts since the first weekday, not skips', () {
    final marks = [done(a, 25), done(b, 26), done(c, 27), skipped(a, 28), done(b, 31)];
    expect(fold(marks).thisWeek, 3, reason: 'Mon 26, Tue 27 and Sat 31; Sun 25 is the week before');
    final sundays = ProgramPosition.of(
      program,
      marks: marks,
      actions: const [],
      now: now,
      firstWeekday: DateTime.sunday,
    );
    expect(sundays.thisWeek, 4);
  });

  test('the position goes over the wire', () {
    expect(fold([done(a, 2)]).toMap(), {
      'week': 1,
      'done': [a],
      'remaining': [b, c],
      'next': b,
      'paused': false,
      'lighter': false,
      'finished': false,
      'thisWeek': 0,
      'target': 3,
    });
  });

  test('the current base is the latest', () {
    final bases = currentBases([
      ProgramBase(exerciseId: 'e1', value: 100, at: DateTime.utc(2026, 10, 1)),
      ProgramBase(exerciseId: 'e1', value: 102.5, at: DateTime.utc(2026, 10, 8)),
      ProgramBase(exerciseId: 'e2', value: 60, at: DateTime.utc(2026, 10, 1)),
    ]);
    expect(bases['e1']?.value, 102.5);
    expect(bases['e2']?.value, 60);
  });

  group('a share of the base as a set target', () {
    test('reads and writes share beside the measures', () {
      final target = SetTarget.fromJson(const {
        'share': 0.85,
        'reps': {'min': 5},
      });
      expect(target.share, 0.85);
      expect(target[TargetMeasure.reps], const TargetRange(min: 5));
      expect(target.toMap(), {
        'reps': {'min': 5},
        'share': 0.85,
      });
      expect(target.withShare(null).toMap().containsKey('share'), isFalse);
      expect(SetTarget(const {}, share: 0.7).isEmpty, isFalse);
    });
  });

  group('lighter weeks (heart-api#229)', () {
    test('a program schedules every Nth cycle lighter', () {
      final scheduled = Program(name: 'p', sessions: [a, b, c], deload: const Deload(every: 2));
      List<ProgramMark> cycle(int day) => [done(a, day), done(b, day), done(c, day)];
      ProgramPosition at(List<ProgramMark> marks) =>
          ProgramPosition.of(scheduled, marks: marks, actions: const [], now: now);
      expect(at([]).lighter, isFalse, reason: 'week 1');
      expect(at(cycle(2)).lighter, isTrue, reason: 'week 2');
      expect(at([...cycle(2), ...cycle(5)]).lighter, isFalse, reason: 'week 3');
    });

    test('the user can take one on demand, and it ends with its cycle', () {
      expect(fold([done(a, 2)], [act(.lighter, 2)]).lighter, isTrue);
      expect(fold([done(a, 2), done(b, 3), done(c, 4)], [act(.lighter, 2)]).lighter, isFalse);
    });

    test('a deload round-trips on a program, and is checked', () {
      final program = Program.fromJson(const {
        'name': 'p',
        'deload': {'every': 6, 'load': 0.9, 'volume': 0.5},
      });
      expect(program.deload, const Deload(every: 6));
      expect(program.toMap()['deload'], {'every': 6, 'load': 0.9, 'volume': 0.5});
      expect(program.without({.deload}).deload, isNull);
      expect(() => Deload.fromJson(const {'every': 1}), throwsArgumentError);
      expect(() => Deload.fromJson(const {'every': 4, 'load': 0}), throwsArgumentError);
    });
  });
}
