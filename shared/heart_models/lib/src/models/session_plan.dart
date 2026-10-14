import 'dart:math';

import 'exercise_set.dart';
import 'misc.dart';
import 'program.dart';
import 'program_math.dart';
import 'program_position.dart';
import 'set_target.dart';
import 'template.dart';

/// A program session as the user will meet it: its sets with this week's
/// targets and the weights worked out from the current bases (heart-api#260).
/// It reads what is stored and does what the app does when it opens the
/// session. It is not a forecast: a workout logged since changes it.
///
/// [PlannedSession.of] is the one reading, so the app, the developer API and
/// MCP show the same numbers.
abstract interface class PlannedSession implements Model {
  /// The session's template id.
  String get templateId;

  /// The program week it falls in.
  int get week;

  /// A lighter cycle: weights at [Deload.load], working sets at
  /// [Deload.volume].
  bool get lighter;

  /// The share of a best estimated max a test session sets the base at; null
  /// for a session that isn't a test. A test's sets carry no planned weight:
  /// the test is how the base is found.
  num? get test;

  List<PlannedExercise> get exercises;

  /// [session] as program week [ProgramPosition.week] plans it, from [bases]
  /// as `currentBases` keys them.
  ///
  /// The rules:
  /// - A `shareOfMax` rule's wave for the week sets each working set's share,
  ///   reps, AMRAP and supplemental in order; sets past the wave keep their
  ///   own targets.
  /// - A set with a share weighs the share of its base: the slot's, else the
  ///   exercise's, or the exercise's that `of` names. Rounded down to that
  ///   exercise's rule step, else to 2.5 kg.
  /// - A set without a share under `addWeight` or `rangeThenWeight` weighs
  ///   the base; under `longer`, the base is its duration or distance, the
  ///   measure its target names.
  /// - Any other set keeps what its template stores.
  /// - A lighter cycle keeps the first [Deload.volume] of the working sets
  ///   (rounded up, at least one), warm-ups all, and takes [Deload.load] of
  ///   each worked-out weight, rounded down the same way.
  factory of(
    Program program,
    Template session, {
    required ProgramPosition position,
    required Map<String, ProgramBase> bases,
  }) {
    final week = position.week;
    final lighter = position.lighter;
    final deload = program.deload;
    final load = deload?.load ?? Deload.defaultLoad;
    final volume = deload?.volume ?? Deload.defaultVolume;
    final test = program.tests[session.id]?.share;

    num stepOf(String exerciseId) => switch (program.rules[exerciseId]) {
      AddWeight(:final step) || RangeThenWeight(:final step) || ShareOfMax(:final step) => step,
      _ => 2.5,
    };

    num? weigh(num share, String exerciseId, ProgramBase? base) {
      if (base == null) return null;
      final step = stepOf(exerciseId);
      final weight = roundDown(share * base.value, step);
      return lighter ? roundDown(weight * load, step) : weight;
    }

    final exercises = <PlannedExercise>[];
    for (final exercise in session) {
      final exerciseId = exercise.exercise.id;
      final rule = program.rules[exerciseId];
      final base = bases[exercise.id] ?? bases[exerciseId];
      final wave = switch (rule) {
        ShareOfMax() when test == null => rule.week(week),
        _ => const <WaveSet>[],
      };

      final all = exercise.toList();
      final working = all.where((set) => set.setType != .warmup).length;
      final keep = lighter ? max(1, (working * volume).ceil()) : working;

      final sets = <PlannedSet>[];
      var index = 0;
      for (final set in all) {
        final warmup = set.setType == .warmup;
        if (!warmup && index >= keep) continue;
        var target = set.target;
        if (!warmup && index < wave.length) target = wave[index].onto(target);
        if (!warmup) index++;

        num? weight = set.weight;
        num? duration = set.duration;
        num? distance = set.distance;
        if (test != null || warmup) {
          // a test finds the base; a warm-up keeps what it stores
        } else if (target?.share case final num share) {
          weight = switch (target?.of) {
            final String of => weigh(share, of, bases[of]),
            null => weigh(share, exerciseId, base),
          };
        } else if (base != null) {
          switch (rule) {
            case AddWeight() || RangeThenWeight():
              weight = lighter ? roundDown(base.value * load, stepOf(exerciseId)) : base.value;
            case Longer():
              if (growsDistance(set, target)) {
                distance = base.value;
              } else {
                duration = base.value;
              }
            default:
              break;
          }
        }
        sets.add(
          PlannedSet(
            setType: set.setType,
            target: target,
            weight: weight,
            reps: set.reps,
            duration: duration,
            distance: distance,
          ),
        );
      }
      exercises.add(PlannedExercise(slot: exercise.id, exerciseId: exerciseId, base: base?.value, sets: sets));
    }
    return _PlannedSession(templateId: session.id, week: week, lighter: lighter, test: test, exercises: exercises);
  }
}

/// One exercise of a [PlannedSession].
final class PlannedExercise implements Model {
  /// The template exercise id: the slot a base may be kept for.
  final String slot;

  final String exerciseId;

  /// The base its sets were worked out from, when it has one.
  final num? base;

  final List<PlannedSet> sets;

  const new({required this.slot, required this.exerciseId, required this.base, required this.sets});

  @override
  Map<String, dynamic> toMap() {
    return {
      'slot': slot,
      'exerciseId': exerciseId,
      'base': ?base,
      'sets': [for (final set in sets) set.toMap()],
    };
  }
}

/// One set of a [PlannedExercise]: its target and the values worked out for
/// it, in kilograms, seconds and kilometres.
final class PlannedSet implements Model {
  final SetType setType;
  final SetTarget? target;
  final num? weight;
  final num? reps;
  final num? duration;
  final num? distance;

  const new({this.setType = .normal, this.target, this.weight, this.reps, this.duration, this.distance});

  @override
  Map<String, dynamic> toMap() {
    return {
      if (setType != .normal) 'setType': setType.value,
      if (target case final SetTarget target when !target.isEmpty) 'target': target.toMap(),
      'weight': ?weight,
      'reps': ?reps,
      'duration': ?duration,
      'distance': ?distance,
    };
  }
}

class _PlannedSession implements PlannedSession {
  @override
  final String templateId;
  @override
  final int week;
  @override
  final bool lighter;
  @override
  final num? test;
  @override
  final List<PlannedExercise> exercises;

  const new({
    required this.templateId,
    required this.week,
    required this.lighter,
    required this.test,
    required this.exercises,
  });

  @override
  Map<String, dynamic> toMap() {
    return {
      'templateId': templateId,
      'week': week,
      'lighter': lighter,
      'test': ?test,
      'exercises': [for (final exercise in exercises) exercise.toMap()],
    };
  }
}

extension on WaveSet {
  /// [target] with this wave set's share, reps, AMRAP and supplemental; what
  /// else it says (rir, `of`, measures this build can't read) stays.
  SetTarget onto(SetTarget? target) {
    return SetTarget.fromJson({
      ...?target?.toMap(),
      'share': share,
      'reps': (amrap ? TargetRange(min: reps) : TargetRange.exactly(reps)).toMap(),
      'supplemental': supplemental,
    });
  }
}
