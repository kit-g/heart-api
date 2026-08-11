import 'package:heart_models/heart_models.dart';
import 'package:test/test.dart';

void main() {
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
}
