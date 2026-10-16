import 'package:heart_models/heart_models.dart';

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
/// the unit every count here folds.
typedef LensRow = ({
  String workoutId,
  DateTime start,
  int sets,
  Iterable<String> patterns,
  Map<MuscleGroupKey, double> muscles,
});

extension LensRows on List<ExerciseRecordSets> {
  /// Each exercise's sets per workout, read against [library] (the caller's
  /// exercises, as `ExerciseService.getExercises` lists them). The muscle
  /// groups are the tags' at their shares; an exercise nobody tagged (one the
  /// user made) falls to its target's group. An exercise the library doesn't
  /// list trains nothing these counts can see.
  List<LensRow> toLensRows(Map<String, dynamic> library) {
    final known = {
      for (final exercise in (library['exercises'] as List? ?? const []).whereType<Map>())
        if (exercise['id'] case final String id) id: exercise,
    };
    return [
      for (final exercise in this)
        for (final MapEntry(key: workoutId, value: sets) in exercise.sets.workouts.entries)
          (
            workoutId: workoutId,
            start: DateTime.parse(sets.first.at),
            sets: sets.length,
            patterns: known[exercise.exerciseId].toPatterns(),
            muscles: known[exercise.exerciseId].toMuscleShares(),
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

  Map<MuscleGroupKey, double> toMuscleShares() {
    final tagged = switch (this?['muscles']) {
      final Map muscles => MuscleTagging.fromJson(muscles).groupShares,
      _ => const <MuscleGroupKey, double>{},
    };
    if (tagged.isNotEmpty) return tagged;
    return switch (Target.values.where((target) => target.value == this?['target']).firstOrNull?.muscleGroup) {
      final MuscleGroupKey group => {group: 1.0},
      null => const {},
    };
  }
}

/// What one key gathered in one week: working sets, fractional where a
/// muscle receives a share of each, and the workouts that touched it.
typedef LensCount = ({double sets, Set<String> workouts});

/// `GET /me/volume`: working sets and sessions per muscle group and per
/// movement pattern, week by week.
final class MeVolume implements Model {
  final LensWindow window;
  final Map<DateTime, ({Map<String, LensCount> muscles, Map<String, LensCount> patterns, int unplaced})> weeks;

  const new _(this.window, this.weeks);

  factory fold(LensWindow window, Iterable<LensRow> rows) {
    final weeks = {
      for (final week in window.weeks)
        week: (muscles: <String, LensCount>{}, patterns: <String, LensCount>{}, unplaced: 0),
    };
    void add(Map<String, LensCount> counts, String key, double sets, String workoutId) {
      final (sets: before, :workouts) = counts[key] ?? (sets: .0, workouts: <String>{});
      counts[key] = (sets: before + sets, workouts: workouts..add(workoutId));
    }

    for (final row in rows) {
      final week = window.weekOf(row.start);
      if (weeks[week] case (:final muscles, :final patterns, :final unplaced)) {
        for (final MapEntry(key: group, value: share) in row.muscles.entries) {
          add(muscles, group.value, row.sets * share, row.workoutId);
        }
        for (final pattern in row.patterns) {
          add(patterns, pattern, row.sets.toDouble(), row.workoutId);
        }
        // sets neither key can place: an untagged exercise of no group and no
        // pattern, such as cardio the user made
        final placed = row.muscles.isNotEmpty || row.patterns.isNotEmpty;
        weeks[week] = (muscles: muscles, patterns: patterns, unplaced: unplaced + (placed ? 0 : row.sets));
      }
    }
    return MeVolume._(window, weeks);
  }

  /// The muscle groups no set reached in the whole window.
  List<String> get untrained {
    final trained = {for (final week in weeks.values) ...week.muscles.keys};
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
        for (final MapEntry(key: week, value: (:muscles, :patterns, :unplaced)) in weeks.entries)
          {
            'week': week.toIso8601String().substring(0, 10),
            'muscles': muscles.toCountMap(),
            'patterns': patterns.toCountMap(),
            if (unplaced > 0) 'unplacedSets': unplaced,
          },
      ],
      'untrained': untrained,
    };
  }
}

extension on Map<String, LensCount> {
  Map<String, dynamic> toCountMap() {
    final keys = this.keys.toList()..sort((a, b) => this[b]!.sets.compareTo(this[a]!.sets));
    return {
      for (final key in keys) key: {'sets': this[key]!.sets.toTwoPlaces(), 'sessions': this[key]!.workouts.length},
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

  const new _(this.window, this.pairs);

  /// [content] read tolerantly, as the app reads it: a pair or side this
  /// server can't read is passed over. Side names are in [locale], else its
  /// language, else English.
  factory fold(
    LensWindow window,
    Iterable<LensRow> rows, {
    required Map<String, dynamic>? content,
    required String locale,
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
    ]);
  }

  @override
  Map<String, dynamic> toMap() => {...window.toMap(), 'weeks': window.weeks.length, 'pairs': pairs};
}
