import 'package:heart_models/heart_models.dart';
import 'package:test/test.dart';

void main() {
  group('WorkoutAggregation.workoutCount', () {
    test('counts workouts, not weeks', () {
      final agg = WorkoutAggregation.fromRows([
        {'id': 'w-1', 'name': 'Push', 'start': DateTime(2026, 8, 3, 9).toUtc().toIso8601String()},
        {'id': 'w-2', 'name': 'Pull', 'start': DateTime(2026, 8, 5, 9).toUtc().toIso8601String()},
        {'id': 'w-3', 'name': 'Legs', 'start': DateTime(2026, 8, 12, 9).toUtc().toIso8601String()},
      ]);

      expect(agg.workoutCount, 3);
      // the trailing window pads empty weeks, so weeks and workouts disagree
      expect(agg.length, isNot(3));
    });

    test('is zero when empty', () {
      expect(WorkoutAggregation.empty().workoutCount, 0);
    });
  });

  group(
    'WorkoutSummary Tests',
    () {
      late String id;
      late String? name;

      setUp(() {
        id = 'test-id-123';
        name = 'Morning Workout';
      });

      test(
        'WorkoutSummary is initialized with required id and optional name',
        () {
          final summary = WorkoutSummary(id: id, name: name);

          expect(summary.id, equals(id));
          expect(summary.name, equals(name));
        },
      );

      test(
        'WorkoutSummary handles null name',
        () {
          final summary = WorkoutSummary(id: id, name: null);

          expect(summary.id, equals(id));
          expect(summary.name, isNull);
        },
      );
    },
  );

  group('WorkoutAggregation.fromRows bucketing', () {
    List<WeekSummary> nonEmptyWeeks(WorkoutAggregation agg) => agg.where((week) => week.isNotEmpty).toList();

    test('buckets by the local calendar week, not UTC', () {
      // These UTC instants read as Sunday 23:30 and Monday-of-the-same-week noon
      // on the *local* clock. West of UTC the Sunday-night instant is already
      // Monday in UTC, which is exactly when the old UTC bucketing filed it into
      // the next week and split the two apart. On the local calendar they share a
      // Mon–Sun week, so a correct bucketing groups them. (Aug 3 2026 is a Monday,
      // Aug 9 the Sunday that closes its week.) In a UTC test environment the two
      // clocks coincide and this still passes; in any western zone it fails on the
      // pre-fix code — the regression guard the UTC anchoring lacked.
      final localSundayNight = DateTime(2026, 8, 9, 23, 30);
      final localWeekMonday = DateTime(2026, 8, 3, 12);

      final agg = WorkoutAggregation.fromRows([
        {'id': 'w-sun', 'name': 'Sunday', 'start': localSundayNight.toUtc().toIso8601String()},
        {'id': 'w-mon', 'name': 'Monday', 'start': localWeekMonday.toUtc().toIso8601String()},
      ]);

      final weeks = nonEmptyWeeks(agg);
      expect(weeks, hasLength(1), reason: 'both sessions fall in one local week');
      expect(weeks.single, hasLength(2));
    });

    test('files sessions from different weeks into separate buckets', () {
      final firstWeek = DateTime(2026, 8, 4, 10); // week of Mon Aug 3
      final secondWeek = DateTime(2026, 8, 11, 10); // week of Mon Aug 10

      final agg = WorkoutAggregation.fromRows([
        {'id': 'a', 'name': 'A', 'start': firstWeek.toUtc().toIso8601String()},
        {'id': 'b', 'name': 'B', 'start': secondWeek.toUtc().toIso8601String()},
      ]);

      final weeks = nonEmptyWeeks(agg);
      expect(weeks, hasLength(2));
      expect(weeks.every((w) => w.length == 1), isTrue);
    });
  });

  group('WorkoutAggregation first weekday', () {
    // Aug 9 2026 is a Sunday: the last day of a Monday week, the first of a
    // Sunday one
    final saturday = DateTime(2026, 8, 8, 10);
    final sunday = DateTime(2026, 8, 9, 10);
    final rows = [
      {'id': 'sat', 'name': 'Saturday', 'start': saturday.toUtc().toIso8601String()},
      {'id': 'sun', 'name': 'Sunday', 'start': sunday.toUtc().toIso8601String()},
    ];

    List<WeekSummary> nonEmptyWeeks(WorkoutAggregation agg) => agg.where((week) => week.isNotEmpty).toList();

    test('weeks start on Monday when no day is given', () {
      final weeks = nonEmptyWeeks(WorkoutAggregation.fromRows(rows));

      expect(weeks.single.startDate, DateTime(2026, 8, 3));
      expect(weeks.single.weekId, getMonday(sunday).toIso8601String());
      expect(WorkoutAggregation.fromRows(rows, firstWeekday: DateTime.monday).map((w) => w.weekId), [
        for (final week in WorkoutAggregation.fromRows(rows)) week.weekId,
      ]);
    });

    test('fromRows buckets by the day supplied', () {
      final weeks = nonEmptyWeeks(WorkoutAggregation.fromRows(rows, firstWeekday: DateTime.sunday));

      expect(weeks.map((w) => w.startDate), [DateTime(2026, 8, 2), DateTime(2026, 8, 9)]);
      expect(weeks.map((w) => w.single.id), ['sat', 'sun']);
    });

    test('every week, filled ones included, starts on that day', () {
      final later = {'id': 'thu', 'name': 'Thursday', 'start': DateTime(2026, 8, 27, 10).toUtc().toIso8601String()};
      for (final firstWeekday in [DateTime.sunday, DateTime.saturday, DateTime.wednesday]) {
        final weeks = WorkoutAggregation.fromRows([...rows, later], firstWeekday: firstWeekday);
        expect(weeks.length, greaterThan(3), reason: 'weekday $firstWeekday');
        expect(weeks.every((w) => w.startDate.weekday == firstWeekday), isTrue, reason: 'weekday $firstWeekday');
      }
    });

    test('fromJson matches stored weeks and fills the gaps on that day', () {
      final agg = WorkoutAggregation.fromJson({
        DateTime(2026, 8, 2).toIso8601String(): {'sat': 'Saturday'},
        DateTime(2026, 8, 23).toIso8601String(): {'thu': 'Thursday'},
      }, firstWeekday: DateTime.sunday);

      expect(agg.take(5).map((w) => w.startDate), [
        for (final day in [2, 9, 16, 23, 30]) DateTime(2026, 8, day),
      ]);
      expect(nonEmptyWeeks(agg).map((w) => w.single.id), ['sat', 'thu']);
      expect(agg.workoutCount, 2);
    });
  });

  group('WorkoutAggregation across DST changes', () {
    // just after midnight the day after a change, and the week before one:
    // North America (Mar 8), Europe (Mar 29), Sydney (Apr 5, Oct 4), New
    // Zealand (Sep 27). In a zone without DST these pass trivially; in one
    // with it, a week counted in 24-hour steps lands on the day before and
    // drops the workouts of the week it should have been.
    final starts = [
      DateTime(2026, 3, 4, 10),
      DateTime(2026, 3, 9, 0, 30),
      DateTime(2026, 3, 30, 0, 30),
      DateTime(2026, 4, 6, 0, 30),
      DateTime(2026, 9, 28, 0, 30),
      DateTime(2026, 9, 30, 10),
      DateTime(2026, 10, 5, 0, 30),
    ];
    final rows = [
      for (final (i, start) in starts.indexed) {'id': '$i', 'name': '$i', 'start': start.toUtc().toIso8601String()},
    ];

    for (final firstWeekday in [DateTime.monday, DateTime.sunday, DateTime.wednesday]) {
      test('weeks on weekday $firstWeekday are whole calendar weeks holding every workout', () {
        final weeks = WorkoutAggregation.fromRows(rows, firstWeekday: firstWeekday).toList();

        expect(weeks.map((w) => w.weekId).toSet(), hasLength(weeks.length));
        for (final week in weeks) {
          expect(week.startDate, DateTime(week.startDate.year, week.startDate.month, week.startDate.day));
          expect(week.startDate.weekday, firstWeekday, reason: week.weekId);
        }
        for (var i = 1; i < weeks.length; i++) {
          final previous = weeks[i - 1].startDate;
          expect(weeks[i].startDate, DateTime(previous.year, previous.month, previous.day + 7));
        }
        for (final (i, start) in starts.indexed) {
          final week = weeks.singleWhere((w) => w.any((workout) => workout.id == '$i'));
          final end = DateTime(week.startDate.year, week.startDate.month, week.startDate.day + 7);
          expect(!start.isBefore(week.startDate) && start.isBefore(end), isTrue, reason: '$start in ${week.weekId}');
        }
        expect(weeks.fold(0, (total, week) => total + week.length), starts.length);
      });
    }
  });
}
