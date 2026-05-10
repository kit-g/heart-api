import 'dart:math' as math;

import 'misc.dart';
import 'utils.dart';

final _random = math.Random();

abstract interface class WorkoutSummary implements Model {
  String get id;

  String? get name;

  factory WorkoutSummary({required String id, String? name}) {
    return _WorkoutSummary(id: id, name: name);
  }
}

abstract interface class WeekSummary with Iterable<WorkoutSummary> implements Comparable<WeekSummary> {
  String get weekId;

  Iterable<WorkoutSummary> get workouts;

  DateTime get startDate;
}

abstract interface class WorkoutAggregation with Iterable<WeekSummary> {
  /// A factory constructor for creating a [WorkoutAggregation] instance
  /// from a given [json] map.
  ///
  /// This method processes the provided JSON to generate a list of weeks, each
  /// containing workout data. It ensures that any missing weeks between the
  /// earliest and current weeks are populated as empty weeks. The result is
  /// a complete sorted list of weeks.
  ///
  /// If the parsed data is empty, the method returns an empty [WorkoutAggregation].
  ///
  /// It also ensures that the weeks are represented in a reversed order (latest
  /// week first) and only retains the most recent weeks, up to the maximum defined.
  factory WorkoutAggregation.fromJson(Map<String, dynamic> json) = _WorkoutAggregation.fromJson;

  factory WorkoutAggregation.fromRows(List<Map<String, dynamic>> rows) = _WorkoutAggregation.fromRows;

  factory WorkoutAggregation.dummy() = _WorkoutAggregation.dummy;

  factory WorkoutAggregation.empty() = _WorkoutAggregation.empty;

  int get max;
}

class _WorkoutSummary implements WorkoutSummary {
  @override
  final String id;
  @override
  final String? name;

  const _WorkoutSummary({
    required this.id,
    required this.name,
  });

  @override
  Map<String, dynamic> toMap() {
    return {id: name};
  }
}

class _WeekSummary with Iterable<WorkoutSummary> implements WeekSummary {
  @override
  final String weekId;
  @override
  final Iterable<WorkoutSummary> workouts;

  const _WeekSummary({
    required this.weekId,
    required this.workouts,
  });

  factory _WeekSummary.empty({required String weekId}) {
    return _WeekSummary(weekId: weekId, workouts: const []);
  }

  @override
  Iterator<WorkoutSummary> get iterator => workouts.iterator;

  @override
  DateTime get startDate => DateTime.parse(deSanitizeId(weekId));

  @override
  int compareTo(WeekSummary other) {
    return weekId.compareTo(other.weekId);
  }

  @override
  String toString() {
    return '$startDate with $length workouts';
  }
}

class _WorkoutAggregation with Iterable<WeekSummary> implements WorkoutAggregation {
  final Iterable<WeekSummary> _weeks;

  const _WorkoutAggregation({required Iterable<WeekSummary> weeks}) : _weeks = weeks;

  @override
  Iterator<WeekSummary> get iterator => _weeks.iterator;

  @override
  bool get isEmpty => !any((summary) => summary.isNotEmpty);

  factory _WorkoutAggregation.empty() {
    return const _WorkoutAggregation(weeks: []);
  }

  factory _WorkoutAggregation.fromJson(Map<String, dynamic> json) {
    final parsed = json.entries.map(
      (week) {
        return _WeekSummary(
          weekId: week.key,
          workouts: (week.value as Map).entries.map(
            (summary) {
              return _WorkoutSummary(
                id: summary.key,
                name: summary.value,
              );
            },
          ),
        );
      },
    ).toList()
      ..sort();

    final currentWeekStart = getMonday(DateTime.timestamp());

    if (parsed.isEmpty) {
      return _WorkoutAggregation.empty();
    }

    final earliestParsedWeekStart = parsed.first.startDate.toUtc();
    final limit = currentWeekStart.subtract(const Duration(days: 7 * 7));
    final earliestWeekStart = switch (earliestParsedWeekStart.isAfter(limit)) {
      true => limit,
      false => earliestParsedWeekStart,
    };

    final completeWeeks = Iterable.generate(
      // how many weeks exist between earliestWeekStart and currentWeekStart
      currentWeekStart.difference(earliestWeekStart).inDays ~/ 7 + 1,
      (index) => earliestWeekStart.add(Duration(days: index * 7)),
    )
        .map(
          (iteration) {
            return parsed.firstWhere(
              (w) => w.startDate.isAtSameWeekAs(iteration),
              orElse: () => _WeekSummary.empty(weekId: sanitizeId(iteration)),
            );
          },
        )
        .toList()
        .reversed
        .toList()
      ..sort();

    return _WorkoutAggregation(weeks: completeWeeks);
  }

  factory _WorkoutAggregation.fromRows(List<Map<String, dynamic>> rows) {
    final byWeek = <String, List<_WorkoutSummary>>{};

    for (final row in rows) {
      final DateTime start = DateTime.parse(row['start']);
      final String weekId = sanitizeId(getMonday(start));

      byWeek.putIfAbsent(weekId, () => []).add(
            _WorkoutSummary(
              id: row['id'],
              name: row['name'],
            ),
          );
    }

    final parsed = byWeek.entries.map(
      (entry) {
        return _WeekSummary(
          weekId: entry.key,
          workouts: entry.value,
        );
      },
    ).toList()
      ..sort();

    if (parsed.isEmpty) {
      return _WorkoutAggregation.empty();
    }

    final currentWeekStart = getMonday(DateTime.timestamp());
    final earliestParsedWeekStart = parsed.first.startDate.toUtc();
    final limit = currentWeekStart.subtract(const Duration(days: 7 * 7));
    final earliestWeekStart = earliestParsedWeekStart.isAfter(limit) ? limit : earliestParsedWeekStart;

    final completeWeeks = Iterable.generate(
      (currentWeekStart.difference(earliestWeekStart).inDays ~/ 7) + 1,
      (index) => earliestWeekStart.add(Duration(days: index * 7)),
    )
        .map(
          (weekStart) => parsed.firstWhere(
            (w) => w.startDate.isAtSameWeekAs(weekStart),
            orElse: () => _WeekSummary.empty(weekId: sanitizeId(weekStart)),
          ),
        )
        .toList()
      ..sort();

    return _WorkoutAggregation(weeks: completeWeeks);
  }

  /// generates a bunch of randomly populated week summaries
  factory _WorkoutAggregation.dummy({int limit = 8}) {
    final currentWeekStart = getMonday(DateTime.timestamp());
    final earliestWeekStart = currentWeekStart.subtract(Duration(days: 7 * limit - 1));

    final weeks = Iterable.generate(
      currentWeekStart.difference(earliestWeekStart).inDays ~/ 7 + 1,
      (index) => earliestWeekStart.add(Duration(days: index * 7)),
    ).map(
      (iteration) {
        return _WeekSummary(
          weekId: sanitizeId(iteration),
          workouts: List.generate(
            // between 2 and 6
            2 + _random.nextInt(5),
            (index) {
              return _WorkoutSummary(
                id: sanitizeId(
                  iteration.copyWith(hour: iteration.hour + index),
                ),
                name: '',
              );
            },
          ),
        );
      },
    ).toList()
      ..sort();
    return _WorkoutAggregation(weeks: weeks);
  }

  @override
  int get max {
    try {
      return map((summary) => summary.length).reduce(math.max);
    } on StateError {
      return 0;
    }
  }
}

extension on DateTime {
  bool isAtSameWeekAs(DateTime other) {
    return _isTheSameDay(getMonday(this), getMonday(other));
  }
}

bool _isTheSameDay(DateTime one, DateTime two) {
  return one.year == two.year && one.month == two.month && one.day == two.day;
}
