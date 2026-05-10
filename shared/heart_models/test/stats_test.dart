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
}
