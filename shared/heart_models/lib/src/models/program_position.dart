import 'misc.dart';
import 'program.dart';
import 'skip.dart';
import 'uuid.dart';
import 'workout.dart';

/// One thing that happened in a program: a workout done, or a session skipped.
/// What a [ProgramPosition] is folded from, beside the program's actions.
final class ProgramMark {
  /// The session it was for; null when it named none, or its template is gone.
  final String? templateId;

  final DateTime at;

  /// A workout resumes a paused program; a skip doesn't.
  final bool isWorkout;

  const new({required this.templateId, required this.at, required this.isWorkout});

  /// A workout of the program, at its start.
  factory workout(Workout workout) {
    return ProgramMark(templateId: workout.templateId, at: workout.start, isWorkout: true);
  }

  factory skip(TrainingSkip skip) => ProgramMark(templateId: skip.templateId, at: skip.at, isWorkout: false);
}

/// Where the user stands in a program, worked out from its history and never
/// stored (`docs/2026-10-13.programs.md` in heart-api). The app, the developer
/// API and MCP all call [ProgramPosition.of], so they agree.
///
/// Two clocks, independent of each other. The program [week] moves when a cycle
/// is complete: every session in it done or skipped, in any order, on any day.
/// The calendar week only counts: [thisWeek] against [Program.perWeek].
abstract interface class ProgramPosition implements Model {
  /// The program week, from 1.
  int get week;

  /// The open cycle's sessions already done or skipped.
  Set<String> get done;

  /// The open cycle's sessions still to do, in program order.
  List<String> get remaining;

  /// The session to suggest: the first one remaining. Null when the program
  /// has no sessions, or is finished.
  String? get next;

  bool get paused;

  /// A program with a length is finished once its week passes it.
  bool get finished;

  /// Program workouts in the calendar week that holds `now`.
  int get thisWeek;

  /// Folds [marks] (the program's workouts and skips) and [actions] in time
  /// order. [now] sets the calendar week and its zone: a local `now` counts
  /// local weeks. [firstWeekday] is ISO, 1 Monday to 7 Sunday.
  ///
  /// The rules:
  /// - A cycle's sessions are fixed by its first mark: the program's sessions
  ///   created by then. One added later joins the next cycle, so adding a
  ///   session never undoes a past week. Before any mark, or when none is
  ///   older than it (a clock behind), all of them.
  /// - A mark completes its session in the open cycle; twice counts once. A
  ///   mark naming no current session moves nothing.
  /// - `repeat` with nothing in the open cycle goes back a week, to run the one
  ///   just finished again; otherwise it restarts the open cycle at its week.
  /// - `replay` opens a new cycle at its week.
  /// - `pause` holds until a `resume` or a program workout.
  factory of(
    Program program, {
    required Iterable<ProgramMark> marks,
    required Iterable<ProgramAction> actions,
    required DateTime now,
    int firstWeekday = DateTime.monday,
  }) {
    final sessions = program.sessions;
    DateTime? created(String id) => DateTime.tryParse(id) ?? timestampOfUuidV7(id);

    final events = <(DateTime, Object)>[
      for (final mark in marks) (mark.at, mark),
      for (final action in actions) (action.at, action),
    ]..sort((a, b) => a.$1.compareTo(b.$1));

    var week = 1;
    var paused = false;
    Set<String>? required;
    final done = <String>{};

    void open(int at) {
      week = at;
      required = null;
      done.clear();
    }

    for (final (at, event) in events) {
      switch (event) {
        case ProgramMark mark:
          if (mark.isWorkout) paused = false;
          if (required == null) {
            final existing = {
              for (final id in sessions)
                if (created(id) case final c when c == null || !c.isAfter(at)) id,
            };
            // none older than the mark is a clock that ran behind, not a cycle
            // that needs nothing: it would never complete
            required = existing.isEmpty ? sessions.toSet() : existing;
          }
          final cycle = required!;
          if (mark.templateId case final String id when cycle.contains(id)) done.add(id);
          if (cycle.isNotEmpty && done.containsAll(cycle)) open(week + 1);
        case ProgramAction(kind: .repeat):
          open(required == null && done.isEmpty && week > 1 ? week - 1 : week);
        case ProgramAction(kind: .replay, week: final int to):
          open(to);
        case ProgramAction(kind: .pause):
          paused = true;
        case ProgramAction(kind: .resume):
          paused = false;
        default:
          break;
      }
    }

    final cycle = required ?? sessions.toSet();
    final remaining = [
      for (final id in sessions)
        if (cycle.contains(id) && !done.contains(id)) id,
    ];
    final finished = switch (program.weeks) {
      final int weeks => week > weeks,
      null => false,
    };

    final start = _weekStart(now, firstWeekday);
    final thisWeek = marks.where((mark) {
      if (!mark.isWorkout) return false;
      final at = now.isUtc ? mark.at.toUtc() : mark.at.toLocal();
      return !at.isBefore(start) && at.isBefore(start.add(const Duration(days: 7)));
    }).length;

    return _ProgramPosition(
      week: week,
      done: {...done},
      remaining: remaining,
      next: finished ? null : remaining.firstOrNull,
      paused: paused,
      finished: finished,
      thisWeek: thisWeek,
    );
  }
}

/// Midnight starting the week that holds [now], in [now]'s zone.
DateTime _weekStart(DateTime now, int firstWeekday) {
  final back = (now.weekday - firstWeekday) % 7;
  return now.isUtc ? DateTime.utc(now.year, now.month, now.day - back) : DateTime(now.year, now.month, now.day - back);
}

/// The current base of each exercise: its latest value.
Map<String, ProgramBase> currentBases(Iterable<ProgramBase> bases) {
  final current = <String, ProgramBase>{};
  for (final base in bases) {
    final held = current[base.exerciseId];
    if (held == null || !base.at.isBefore(held.at)) current[base.exerciseId] = base;
  }
  return current;
}

class _ProgramPosition implements ProgramPosition {
  @override
  final int week;
  @override
  final Set<String> done;
  @override
  final List<String> remaining;
  @override
  final String? next;
  @override
  final bool paused;
  @override
  final bool finished;
  @override
  final int thisWeek;

  const new({
    required this.week,
    required this.done,
    required this.remaining,
    required this.next,
    required this.paused,
    required this.finished,
    required this.thisWeek,
  });

  @override
  Map<String, dynamic> toMap() {
    return {
      'week': week,
      'done': done.toList(),
      'remaining': remaining,
      'next': ?next,
      'paused': paused,
      'finished': finished,
      'thisWeek': thisWeek,
    };
  }
}
