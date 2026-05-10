import 'package:heart_models/src/models/ts_for_id.dart';
import 'package:test/test.dart';

class TestTimestampId with UsesTimestampForId {
  @override
  final DateTime start;

  TestTimestampId(this.start);
}

void main() {
  group(
    'UsesTimestampForId Tests',
    () {
      test(
        'ID is generated correctly',
        () {
          final timestamp = DateTime.parse('2025-01-01T12:00:00.000Z');
          final instance = TestTimestampId(timestamp);

          expect(instance.id, '2025-01-01T12:00:00.000Z');
        },
      );

      test(
        'Equality works correctly',
        () {
          final timestamp1 = DateTime.parse('2025-01-01T12:00:00Z');
          final timestamp2 = DateTime.parse('2025-01-02T12:00:00Z');

          final instance1 = TestTimestampId(timestamp1);
          final instance2 = TestTimestampId(timestamp1);
          final instance3 = TestTimestampId(timestamp2);

          expect(instance1 == instance2, true);
          expect(instance1.hashCode == instance2.hashCode, true);

          expect(instance1 == instance3, false);
          expect(instance1.hashCode == instance3.hashCode, false);
        },
      );

      test(
        'Elapsed time is calculated correctly',
        () async {
          final timestamp = DateTime.now();
          final instance = TestTimestampId(timestamp);

          await Future.delayed(const Duration(milliseconds: 100));
          expect(instance.elapsed().inMilliseconds >= 100, true);
        },
      );

      test(
        'Comparison works correctly',
        () {
          final timestamp1 = DateTime.parse('2025-01-01T12:00:00Z');
          final timestamp2 = DateTime.parse('2025-01-02T12:00:00Z');

          final instance1 = TestTimestampId(timestamp1);
          final instance2 = TestTimestampId(timestamp2);

          expect(instance1.compareTo(instance2), lessThan(0));
          expect(instance2.compareTo(instance1), greaterThan(0));
          expect(instance1.compareTo(instance1), 0);
        },
      );
    },
  );
}
