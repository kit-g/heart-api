import 'dart:math';

import 'exercise_set.dart';
import 'program.dart';
import 'set_target.dart';

/// What one session did to an exercise's base under its growth rule.
///
/// The device turns a [Grow] or a [Cut] into a stored base caused by the
/// workout, and an [Advance] into a swap; [Hold] and [Missed] store nothing.
/// The streak a [Missed] reports is read back next time from the sessions
/// themselves ([Progression.streak]), so nothing about a miss is stored.
sealed class ProgressionStep {
  const new();
}

/// The base moves up to [value].
final class Grow extends ProgressionStep {
  final num value;

  const new(this.value);

  @override
  bool operator ==(Object other) => other is Grow && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'Grow($value)';
}

/// The base stays: the session neither missed nor earned a step.
final class Hold extends ProgressionStep {
  const new();

  @override
  bool operator ==(Object other) => other is Hold;

  @override
  int get hashCode => 0;

  @override
  String toString() => 'Hold';
}

/// A miss: the base holds, and this is the [streak]th in a row.
final class Missed extends ProgressionStep {
  final int streak;

  const new(this.streak);

  @override
  bool operator ==(Object other) => other is Missed && other.streak == streak;

  @override
  int get hashCode => streak.hashCode;

  @override
  String toString() => 'Missed($streak)';
}

/// The base drops to [value]: enough misses in a row, or an AMRAP table that
/// says so.
final class Cut extends ProgressionStep {
  final num value;

  const new(this.value);

  @override
  bool operator ==(Object other) => other is Cut && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'Cut($value)';
}

/// The exercise moves to [to], the next rung of its ladder.
final class Advance extends ProgressionStep {
  final String to;

  const new(this.to);

  @override
  bool operator ==(Object other) => other is Advance && other.to == to;

  @override
  int get hashCode => to.hashCode;

  @override
  String toString() => 'Advance($to)';
}

/// The one reading of the growth rules (heart-api#228). The app runs it after
/// a program workout; the server stores what the app wrote and never runs it.
abstract final class Progression {
  /// What a session's [sets] of one exercise do to its [base].
  ///
  /// [sets] are the session's logged sets; warm-ups, sets not ticked and
  /// supplemental sets are left out here. [misses] is the streak before this
  /// session ([streak]). [lighter] is a lighter week: nothing moves and
  /// nothing counts. [week] is the program week the session belongs to and
  /// [closesCycle] whether it completed that week's cycle; a rule that grows
  /// per cycle or per wave reads them.
  static ProgressionStep next({
    required GrowthRule rule,
    required num? base,
    required Iterable<ExerciseSet> sets,
    int misses = 0,
    bool lighter = false,
    int week = 1,
    bool closesCycle = true,
  }) {
    if (lighter || base == null) return const Hold();
    final working = _working(sets).toList();
    if (working.isEmpty) return const Hold();

    switch (rule) {
      case NoGrowth():
        return const Hold();
      case Longer(:final step):
        final held = working.every((set) => (_length(set) ?? 0) >= base);
        return held && closesCycle ? Grow(base + step) : const Hold();
      case AddWeight(:final step):
        if (_missed(rule.miss, working)) return _miss(rule.miss, base, step, misses);
        return _step(rule, base, step, working);
      case RangeThenWeight(:final step):
        if (_missed(rule.miss, working)) return _miss(rule.miss, base, step, misses);
        final top = working.every((set) {
          final reps = set.target?[.reps];
          final aim = reps?.max ?? reps?.min;
          return aim == null || (set.reps ?? 0) >= aim;
        });
        return top ? _step(rule, base, step, working) : const Hold();
      case ShareOfMax(:final step):
        final missed = _missed(rule.miss, working);
        if (missed && misses + 1 >= rule.miss.after) return Cut(_down(base * (1 - rule.miss.cut), step));
        if (missed) return Missed(misses + 1);
        if (!closesCycle || !rule.closesWave(week)) return const Hold();
        return _step(rule, base, step, working);
    }
  }

  /// Misses in a row at the end of [sessions], oldest first: the streak the
  /// next session continues. A session with no working sets breaks nothing,
  /// and neither does one of a lighter week: [lighter] says, in the same
  /// order, which sessions were, a session past its end being a normal one.
  static int streak(
    GrowthRule rule,
    Iterable<Iterable<ExerciseSet>> sessions, {
    Iterable<bool> lighter = const [],
  }) {
    final miss = rule.miss;
    if (miss == null) return 0;
    final light = lighter.toList();
    var count = 0;
    for (final (index, session) in sessions.indexed) {
      if (index < light.length && light[index]) continue;
      final working = _working(session).toList();
      if (working.isEmpty) continue;
      count = _missed(miss, working) ? count + 1 : 0;
    }
    return count;
  }

  /// A base from a test session (heart-api#233): [share] of the best
  /// estimated one-rep max among [sets], rounded down to [step]. Brzycki, as
  /// everywhere else in the app, from sets of at most 10 reps, past which it
  /// stops being an estimate. Null when no set qualifies.
  static num? test(Iterable<ExerciseSet> sets, {num share = 0.9, num step = 2.5}) {
    double? best;
    for (final set in _working(sets)) {
      final (weight, reps) = (set.weight, set.reps);
      if (weight == null || weight <= 0 || reps == null || reps < 1 || reps > 10) continue;
      final estimate = weight / (1.0278 - .0278 * reps);
      if (best == null || estimate > best) best = estimate;
    }
    return switch (best) {
      final double best => _down(best * share, step),
      null => null,
    };
  }
}

/// What a [Longer] rule grows in [set]: the measure its target names, else
/// distance for an exercise logged by weight and distance, else duration.
num? _length(ExerciseSet set) {
  final target = set.target;
  final distance = switch ((target?[.distance], target?[.duration])) {
    (final TargetRange _, _) => true,
    (null, final TargetRange _) => false,
    _ => set.category == .weightedDistance,
  };
  return distance ? set.distance : set.duration;
}

Iterable<ExerciseSet> _working(Iterable<ExerciseSet> sets) {
  return sets.where(
    (set) => set.isCompleted && set.setType != .warmup && !(set.target?.supplemental ?? false),
  );
}

/// The set a session's AMRAP is: the last working set whose reps target is as
/// many as possible.
ExerciseSet? _amrapSet(List<ExerciseSet> working) {
  for (final set in working.reversed) {
    if (set.target?[.reps]?.isAmrap ?? false) return set;
  }
  return null;
}

bool _short(ExerciseSet set) {
  final target = set.target;
  if (target == null) return false;
  final reps = target[.reps];
  final duration = target[.duration];
  return (reps != null && (set.reps ?? 0) < reps.min) || (duration != null && (set.duration ?? 0) < duration.min);
}

bool _missed(MissRule? miss, List<ExerciseSet> working) {
  if (miss == null) return false;
  switch (miss.when) {
    case .anySet:
      return working.any(_short);
    case .amrap:
      final amrap = _amrapSet(working);
      return amrap == null ? working.any(_short) : _short(amrap);
    case .totalReps:
      final done = working.fold<int>(0, (sum, set) => sum + (set.reps ?? 0));
      final floor = miss.floor ?? working.fold<num>(0, (sum, set) => sum + (set.target?[.reps]?.min ?? 0)).toInt();
      return done < floor;
  }
}

ProgressionStep _miss(MissRule miss, num base, num step, int misses) {
  final streak = misses + 1;
  if (streak >= miss.after) return Cut(_down(base * (1 - miss.cut), step));
  return Missed(streak);
}

/// The rule's step, or the AMRAP table's when the session has an AMRAP set.
ProgressionStep _step(GrowthRule rule, num base, num step, List<ExerciseSet> working) {
  var chosen = step;
  final amrap = _amrapSet(working);
  if (rule.amrap.isNotEmpty && amrap != null) {
    final reps = amrap.reps ?? 0;
    final rows = [...rule.amrap]..sort((a, b) => b.reps.compareTo(a.reps));
    for (final row in rows) {
      if (reps >= row.reps) {
        chosen = row.step;
        break;
      }
    }
  }
  if (chosen == 0) return const Hold();
  final value = base + chosen;
  return chosen > 0 ? Grow(value) : Cut(max(value, 0));
}

/// [value] rounded down to a whole number of [step]s: a cut lands on a weight
/// the plates can make.
num _down(num value, num step) {
  if (step <= 0) return value;
  final steps = (value / step + 1e-9).floor();
  final rounded = steps * step;
  return rounded == rounded.roundToDouble() ? rounded.round() : double.parse(rounded.toStringAsFixed(3));
}
