import 'package:heart_models/heart_models.dart';

import 'anomalies.dart';
import 'changes.dart';

/// The balance pairs as the CDN serves them (`static/balance`,
/// `docs/2026-10-15.balance-pairs.md`), the copy the app reads too.
abstract interface class BalancePairs {
  /// The rendered file, or null while none is published.
  Future<Map<String, dynamic>?> readPairs();
}

/// The weeks a count by muscle, pattern or pair reads: whole weeks starting on
/// [weekStart] (ISO, 1 Monday to 7 Sunday), in UTC, from the one [from] falls
/// in through the one before [to]. Sets count when their workout started in
/// `[from, to)`.
final class LensWindow {
  final int weekStart;
  final DateTime from;
  final DateTime to;

  const new _({required this.weekStart, required this.from, required this.to});

  /// The longest window a count reads: a year, give or take a week.
  static const longest = Duration(days: 371);

  /// How many weeks a window reads when it isn't told where to start.
  static const defaultWeeks = 4;

  /// [from] and [to] as given, [to] now when absent, and [from] the start of
  /// the [defaultWeeks] weeks ending with [to]'s when absent.
  factory resolve({required int weekStart, DateTime? from, DateTime? to}) {
    final end = to ?? DateTime.timestamp();
    final start = from ?? _weekOf(end, weekStart).subtract(const Duration(days: 7 * (defaultWeeks - 1)));
    return LensWindow._(weekStart: weekStart, from: start, to: end);
  }

  /// The first day of every week the window reads, oldest first.
  List<DateTime> get weeks {
    final last = _weekOf(to.subtract(const Duration(microseconds: 1)), weekStart);
    return [
      for (var week = _weekOf(from, weekStart); !week.isAfter(last); week = week.add(const Duration(days: 7))) week,
    ];
  }

  /// The first day of the week [moment] falls in.
  DateTime weekOf(DateTime moment) => _weekOf(moment, weekStart);

  static DateTime _weekOf(DateTime moment, int weekStart) {
    final utc = moment.toUtc();
    return DateTime.utc(utc.year, utc.month, utc.day - (utc.weekday - weekStart) % 7);
  }

  Map<String, dynamic> toMap() {
    return {'weekStart': weekStart, 'from': from.toUtc().toIso8601String(), 'to': to.toUtc().toIso8601String()};
  }
}

/// One exercise's working sets in one workout, with what the exercise trains:
/// the unit every count here folds. [primary] is the groups of [muscles] the
/// exercise works first; [volume] is its weight times reps, in kg.
typedef LensRow = ({
  String workoutId,
  String exerciseId,
  DateTime start,
  int sets,
  double volume,
  Iterable<String> patterns,
  Map<MuscleGroupKey, double> muscles,
  Set<MuscleGroupKey> primary,
});

extension LensRows on List<ExerciseRecordSets> {
  /// Each exercise's sets per workout, read against [library] (the caller's
  /// exercises, as `ExerciseService.getExercises` lists them). The muscle
  /// groups are the tags' at their shares; an exercise nobody tagged (one the
  /// user made) falls to its target's group, as primary. An exercise the
  /// library doesn't list trains nothing these counts can see.
  List<LensRow> toLensRows(Map<String, dynamic> library) {
    final known = {
      for (final exercise in (library['exercises'] as List? ?? const []).whereType<Map>())
        if (exercise['id'] case final String id) id: exercise,
    };
    return [
      for (final exercise in this)
        for (final MapEntry(key: workoutId, value: sets) in exercise.sets.workouts.entries)
          if (known[exercise.exerciseId].toMuscleShares() case (:final muscles, :final primary))
            (
              workoutId: workoutId,
              exerciseId: exercise.exerciseId,
              start: DateTime.parse(sets.first.at),
              sets: sets.length,
              // assistance is weight taken off, not lifted
              volume: switch (exercise.category) {
                .assistedBodyWeight => 0,
                _ => sets.fold(0.0, (sum, set) => sum + set.volume),
              },
              patterns: known[exercise.exerciseId].toPatterns(),
              muscles: muscles,
              primary: primary,
            ),
    ];
  }
}

extension on List<RecordSet> {
  Map<String, List<RecordSet>> get workouts {
    final byWorkout = <String, List<RecordSet>>{};
    for (final set in this) {
      byWorkout.putIfAbsent(set.workoutId, () => []).add(set);
    }
    return byWorkout;
  }
}

extension on Map? {
  Iterable<String> toPatterns() {
    return switch (this?['movement']) {
      {'groups': final List groups} => groups.whereType<String>(),
      _ => const [],
    };
  }

  ({Map<MuscleGroupKey, double> muscles, Set<MuscleGroupKey> primary}) toMuscleShares() {
    if (this?['muscles'] case final Map muscles) {
      final tagging = MuscleTagging.fromJson(muscles);
      if (tagging.groupShares case final shares when shares.isNotEmpty) {
        return (muscles: shares, primary: tagging.primaryGroups);
      }
    }
    return switch (Target.values.where((target) => target.value == this?['target']).firstOrNull?.muscleGroup) {
      final MuscleGroupKey group => (muscles: {group: 1.0}, primary: {group}),
      null => (muscles: const {}, primary: const {}),
    };
  }
}

/// What one key gathered in one week: working sets, fractional where a
/// muscle receives a share of each, the part of them from exercises that work
/// it first, and the workouts that touched it.
typedef LensCount = ({double sets, double primarySets, Set<String> workouts});

/// One week of [MeVolume].
final class _Week {
  final muscles = <String, LensCount>{};
  final patterns = <String, LensCount>{};
  var unplaced = 0;
  var volume = .0;
  var workouts = 0;
  var duration = Duration.zero;

  void add(Map<String, LensCount> counts, String key, double sets, String workoutId, {required bool primary}) {
    final (sets: before, primarySets: first, :workouts) =
        counts[key] ?? (sets: .0, primarySets: .0, workouts: <String>{});
    counts[key] = (sets: before + sets, primarySets: first + (primary ? sets : 0), workouts: workouts..add(workoutId));
  }
}

/// `GET /me/volume`: working sets and sessions per muscle group and per
/// movement pattern, week by week, with the week's finished workouts, their
/// time and the weight they moved.
final class MeVolume implements Model {
  final LensWindow window;
  final Map<DateTime, _Week> _weeks;
  final List<Anomaly> warnings;

  const new _(this.window, this._weeks, this.warnings);

  /// [spans] are the window's finished workouts; [warnings] the pending
  /// anomalies among what was counted.
  factory fold(
    LensWindow window,
    Iterable<LensRow> rows, {
    Iterable<WorkoutSpan> spans = const [],
    List<Anomaly> warnings = const [],
  }) {
    final weeks = {for (final week in window.weeks) week: _Week()};
    for (final row in rows) {
      if (weeks[window.weekOf(row.start)] case final week?) {
        for (final MapEntry(key: group, value: share) in row.muscles.entries) {
          week.add(week.muscles, group.value, row.sets * share, row.workoutId, primary: row.primary.contains(group));
        }
        for (final pattern in row.patterns) {
          week.add(week.patterns, pattern, row.sets.toDouble(), row.workoutId, primary: true);
        }
        // sets neither key can place: an untagged exercise of no group and no
        // pattern, such as cardio the user made
        if (row.muscles.isEmpty && row.patterns.isEmpty) week.unplaced += row.sets;
        week.volume += row.volume;
      }
    }
    for (final span in spans) {
      if (weeks[window.weekOf(span.start)] case final week?) {
        week
          ..workouts += 1
          ..duration += span.duration;
      }
    }
    return MeVolume._(window, weeks, warnings);
  }

  /// The muscle groups no set reached in the whole window.
  List<String> get untrained {
    final trained = {for (final week in _weeks.values) ...week.muscles.keys};
    return [
      for (final group in MuscleGroupKey.values)
        if (!trained.contains(group.value)) group.value,
    ];
  }

  @override
  Map<String, dynamic> toMap() {
    return {
      ...window.toMap(),
      'weeks': [
        for (final MapEntry(key: start, value: week) in _weeks.entries)
          {
            'week': start.toIso8601String().substring(0, 10),
            'workouts': week.workouts,
            'duration': week.duration.inSeconds,
            'totalVolume': week.volume.toTwoPlaces(),
            'muscles': week.muscles.toCountMap(withPrimary: true),
            'patterns': week.patterns.toCountMap(),
            if (week.unplaced > 0) 'unplacedSets': week.unplaced,
          },
      ],
      'untrained': untrained,
      if (warnings.isNotEmpty) 'warnings': warnings.toWarnings(),
    };
  }
}

extension on Map<String, LensCount> {
  Map<String, dynamic> toCountMap({bool withPrimary = false}) {
    final keys = this.keys.toList()..sort((a, b) => this[b]!.sets.compareTo(this[a]!.sets));
    return {
      for (final key in keys)
        key: {
          'sets': this[key]!.sets.toTwoPlaces(),
          if (withPrimary) 'primarySets': this[key]!.primarySets.toTwoPlaces(),
          'sessions': this[key]!.workouts.length,
        },
    };
  }
}

extension on double {
  /// Shares are halves and quarters; two places keep them and drop the float
  /// noise their sums carry.
  num toTwoPlaces() => switch ((this * 100).round() / 100) {
    final double whole when whole == whole.truncateToDouble() => whole.toInt(),
    final double other => other,
  };
}

/// `GET /me/balance`: each pair's two sides set against each other over the
/// window, counts only. A side's sets are a row's whole sets once when any of
/// the exercise's patterns is on that side; the rows are the window's.
final class MeBalance implements Model {
  final LensWindow window;
  final List<Map<String, dynamic>> pairs;
  final List<Anomaly> warnings;

  const new _(this.window, this.pairs, this.warnings);

  /// [content] read tolerantly, as the app reads it: a pair or side this
  /// server can't read is passed over. Side names are in [locale], else its
  /// language, else English.
  factory fold(
    LensWindow window,
    Iterable<LensRow> rows, {
    required Map<String, dynamic>? content,
    required String locale,
    List<Anomaly> warnings = const [],
  }) {
    String? named(Object? names) {
      return switch (names) {
        final Map names => switch (names[locale] ?? names[locale.split('_').first] ?? names['en']) {
          final String name => name,
          _ => null,
        },
        _ => null,
      };
    }

    ({Map<String, dynamic> side, Iterable<LensRow> rows})? side(Object? json) {
      if (json case {'key': final String key, 'patterns': final List patterns} when patterns.isNotEmpty) {
        final on = patterns.whereType<String>().toSet();
        final trained = rows.where((row) => row.patterns.any(on.contains)).toList();
        return (
          side: {
            'key': key,
            'name': ?named(json['name']),
            'patterns': on.toList(),
            'sets': trained.fold(0, (sum, row) => sum + row.sets),
          },
          rows: trained,
        );
      }
      return null;
    }

    return MeBalance._(window, [
      for (final pair in (content?['pairs'] as List? ?? const []).whereType<Map>())
        if (pair case {'key': final String key, 'left': final left, 'right': final right})
          if ((side(left), side(right)) case (final left?, final right?))
            {
              'key': key,
              'left': left.side,
              'right': right.side,
              'weeksTrained': {for (final row in left.rows.followedBy(right.rows)) window.weekOf(row.start)}.length,
            },
    ], warnings);
  }

  @override
  Map<String, dynamic> toMap() {
    return {
      ...window.toMap(),
      'weeks': window.weeks.length,
      'pairs': pairs,
      if (warnings.isNotEmpty) 'warnings': warnings.toWarnings(),
    };
  }
}

/// `GET /me/goals/progress`: each live goal with where it stands, measured as
/// the app measures it, so the two agree.
///
/// The app's side is `currentGoalValue` in heart-of-yours.
///
/// - A goal with a cadence reads the week or calendar month [now] falls in
///   (`period`): weeks start on [weekStart], both in UTC. One without reads
///   all time.
/// - `workouts` counts finished workouts.
/// - `sets` and `sessions` count the goal's subject as volume does: an
///   exercise's own sets, a pattern's, a muscle group's at its share.
/// - Any other metric is its exercise's per-session value, as the progress
///   chart plots it: the best session for a milestone, the period's sessions
///   folded by [ChartPreferenceType.periodAggregate] for a cadence.
///
/// `current` is absent where there is nothing to read: no session of the
/// exercise yet, a pace with no run in the period, or a muscle key that is no
/// group. `progress` is how far along the current stage is, 0 to 1; 1 for a
/// finished ladder.
final class MeGoalProgress implements Model {
  final int weekStart;
  final List<Map<String, dynamic>> goals;

  const new _(this.weekStart, this.goals);

  /// [sets], [rows] and [spans] are all time's: a milestone reads all of it.
  /// [library] names the exercises goals point at. [pending] are the
  /// anomalies nobody has looked at; each goal names those on the sets it
  /// read, in its period.
  factory measure(
    Iterable<Goal> goals, {
    required DateTime now,
    required int weekStart,
    List<ExerciseRecordSets> sets = const [],
    List<LensRow> rows = const [],
    List<WorkoutSpan> spans = const [],
    Map<String, dynamic> library = const {},
    List<Anomaly> pending = const [],
  }) {
    final names = {
      for (final exercise in (library['exercises'] as List? ?? const []).whereType<Map>())
        if (exercise case {'id': final String id, 'name': final String name}) id: name,
    };
    final exercises = {for (final exercise in sets) exercise.exerciseId: exercise};

    (DateTime, DateTime)? periodOf(GoalCadence? cadence) {
      return switch (cadence) {
        null => null,
        .week => switch (LensWindow.resolve(weekStart: weekStart, to: now).weekOf(now)) {
          final start => (start, start.add(const Duration(days: 7))),
        },
        .month => (DateTime.utc(now.year, now.month), DateTime.utc(now.year, now.month + 1)),
      };
    }

    bool within(DateTime moment, (DateTime, DateTime)? period) {
      return switch (period) {
        null => true,
        (final from, final to) => !moment.isBefore(from) && moment.isBefore(to),
      };
    }

    /// How much of one row a sets or sessions goal counts; null for a subject
    /// no row can reach.
    double Function(LensRow)? shareOf(Goal goal) {
      return switch (goal.subject) {
        ExerciseSubject(:final id) => (row) => row.exerciseId == id ? 1 : 0,
        PatternSubject(:final key) => (row) => row.patterns.contains(key) ? 1 : 0,
        MuscleSubject(:final key) => switch (MuscleGroupKey.tryParse(key)) {
          final MuscleGroupKey group => (row) => row.muscles[group] ?? 0,
          null => null,
        },
        null => null,
      };
    }

    // what each exercise trains, to tell which anomalies a subject goal read
    final trains = {for (final row in rows) row.exerciseId: row};

    num? subjectValue(Goal goal, (DateTime, DateTime)? period) {
      final share = shareOf(goal);
      if (share == null) return null;
      var counted = .0;
      final workouts = <String>{};
      for (final row in rows) {
        if (!within(row.start, period)) continue;
        if (share(row) case final part when part > 0) {
          counted += row.sets * part;
          workouts.add(row.workoutId);
        }
      }
      return goal.metric == .sessions ? workouts.length : counted.toTwoPlaces();
    }

    num? exerciseValue(Goal goal, (DateTime, DateTime)? period) {
      final chart = goal.metric.chart;
      final exercise = exercises[goal.exerciseId];
      if (chart == null || goal.exerciseId == null) return null;
      final sessions = <String, List<RecordSet>>{};
      for (final set in exercise?.sets ?? const <RecordSet>[]) {
        if (within(DateTime.parse(set.at), period)) sessions.putIfAbsent(set.workoutId, () => []).add(set);
      }
      final values = [
        for (final session in sessions.values)
          if (session.toSessionMetrics(exercise!.category)[chart.value] case final num value) value,
      ];
      if (values.isEmpty) {
        // nothing logged yet this period is zero of anything that adds up;
        // not of pace, where zero would read as met
        return period != null && !goal.metric.lowerIsBetter ? 0 : null;
      }
      if (period != null) return chart.periodAggregate.of(values);
      return values.reduce(switch (goal.metric.lowerIsBetter) {
        true => (a, b) => a < b ? a : b,
        false => (a, b) => a > b ? a : b,
      });
    }

    Map<String, dynamic> measured(Goal goal) {
      final period = periodOf(goal.cadence);
      final current = switch (goal.metric) {
        .workouts => spans.where((span) => within(span.start, period)).length,
        .sets || .sessions => subjectValue(goal, period),
        _ => exerciseValue(goal, period),
      };
      final share = shareOf(goal);
      final warnings = [
        for (final anomaly in pending)
          if (anomaly.workoutStart case final start? when within(start, period))
            if (switch (goal.metric) {
              // a workout counts whatever its time, so no anomaly moves it
              .workouts => false,
              .sets || .sessions => switch ((share, trains[anomaly.exerciseId])) {
                (final share?, final row?) => share(row) > 0,
                _ => false,
              },
              _ => anomaly.exerciseId != null && anomaly.exerciseId == goal.exerciseId,
            })
              anomaly,
      ];
      return {
        ...goal.toMap(),
        'exerciseName': ?names[goal.exerciseId],
        if (period case (final from, final to)) 'period': {'from': from.toIso8601String(), 'to': to.toIso8601String()},
        'current': ?current,
        'progress': goal.progressAt(current).toTwoPlaces(),
        if (warnings.isNotEmpty) 'warnings': warnings.toWarnings(),
      };
    }

    return MeGoalProgress._(weekStart, [for (final goal in goals) measured(goal)]);
  }

  @override
  Map<String, dynamic> toMap() => {'weekStart': weekStart, 'goals': goals};
}

extension on Goal {
  /// How far along the current stage [current] is, 0 to 1, as the app's goal
  /// card fills it: 1 for a finished ladder, 0 for nothing to read; the target
  /// over the reading where lower is better.
  double progressAt(num? current) {
    return switch ((currentStage?.target, current)) {
      (null, _) => 1,
      (_, null) => 0,
      (final num target, final num value) when metric.lowerIsBetter => value <= 0 ? 0 : (target / value).clamp(0, 1),
      (final num target, final num value) => target <= 0 ? 1 : (value / target).clamp(0, 1).toDouble(),
    };
  }
}
