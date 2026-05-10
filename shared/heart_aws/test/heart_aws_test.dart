import 'package:heart_aws/heart_aws.dart';
import 'package:test/test.dart';

void main() {
  group('SchedulerApi.atExpression', () {
    test('formats a UTC DateTime as at(YYYY-MM-DDTHH:MM:SS)', () {
      final dt = DateTime.utc(2026, 5, 10, 14, 30, 45);
      expect(SchedulerApi.atExpression(dt), 'at(2026-05-10T14:30:45)');
    });

    test('zero-pads single-digit components', () {
      final dt = DateTime.utc(2026, 1, 2, 3, 4, 5);
      expect(SchedulerApi.atExpression(dt), 'at(2026-01-02T03:04:05)');
    });

    test('converts non-UTC input to UTC', () {
      // Construct a local time, then check it's normalized to UTC in the output.
      // EST = UTC-5; 09:00 EST → 14:00 UTC (during EST). DateTime.toUtc() handles this.
      final local = DateTime.utc(2026, 5, 10, 14, 30, 45).toLocal();
      expect(SchedulerApi.atExpression(local), 'at(2026-05-10T14:30:45)');
    });

    test('drops fractional seconds', () {
      final dt = DateTime.utc(2026, 5, 10, 14, 30, 45, 999);
      expect(SchedulerApi.atExpression(dt), 'at(2026-05-10T14:30:45)');
    });
  });
}
