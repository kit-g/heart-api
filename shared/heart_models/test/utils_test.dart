import 'package:heart_models/heart_models.dart';
import 'package:test/test.dart';

void main() {
  group('getMonday Tests', () {
    test('Monday should return the same date', () {
      final date = DateTime.parse('2025-01-13'); // A Monday
      final result = getMonday(date);
      expect(result.isAtSameMomentAs(date), isTrue); // The result should be the same Monday
    });

    test('Tuesday should return the previous Monday', () {
      final date = DateTime.parse('2025-01-14'); // A Tuesday
      final expected = DateTime.parse('2025-01-13'); // Previous Monday
      final result = getMonday(date);
      expect(result.isAtSameMomentAs(expected), isTrue);
    });

    test('Wednesday should return the previous Monday', () {
      final date = DateTime.parse('2025-01-15'); // A Wednesday
      final expected = DateTime.parse('2025-01-13'); // Previous Monday
      final result = getMonday(date);
      expect(result.isAtSameMomentAs(expected), isTrue);
    });

    test('Thursday should return the previous Monday', () {
      final date = DateTime.parse('2025-01-16'); // A Thursday
      final expected = DateTime.parse('2025-01-13'); // Previous Monday
      final result = getMonday(date);
      expect(result.isAtSameMomentAs(expected), isTrue);
    });

    test('Friday should return the previous Monday', () {
      final date = DateTime.parse('2025-01-17'); // A Friday
      final expected = DateTime.parse('2025-01-13'); // Previous Monday
      final result = getMonday(date);
      expect(result.isAtSameMomentAs(expected), isTrue);
    });

    test('Saturday should return the previous Monday', () {
      final date = DateTime.parse('2025-01-18'); // A Saturday
      final expected = DateTime.parse('2025-01-13'); // Previous Monday
      final result = getMonday(date);
      expect(result.isAtSameMomentAs(expected), isTrue);
    });

    test('Sunday should return the previous Monday', () {
      final date = DateTime.parse('2025-01-19'); // A Sunday
      final expected = DateTime.parse('2025-01-13'); // Previous Monday
      final result = getMonday(date);
      expect(result.isAtSameMomentAs(expected), isTrue);
    });

    test('Monday at the start of a new year should return the same date', () {
      final date = DateTime.parse('2025-01-01'); // A Wednesday
      final expected = DateTime.parse('2024-12-30'); // Previous Monday
      final result = getMonday(date);
      expect(result.isAtSameMomentAs(expected), isTrue);
    });

    test('Edge case: December 31st should return the last Monday of the year', () {
      final date = DateTime.parse('2025-12-31'); // A Wednesday
      final expected = DateTime.parse('2025-12-29'); // Previous Monday
      final result = getMonday(date);
      expect(result.isAtSameMomentAs(expected), isTrue);
    });

    test('Edge case: Leap year February 29th should return the previous Monday', () {
      final date = DateTime.parse('2024-02-29'); // Leap year date
      final expected = DateTime.parse('2024-02-26'); // Previous Monday
      final result = getMonday(date);
      expect(result.isAtSameMomentAs(expected), isTrue);
    });

    test('Edge case: Any date on the weekend (Saturday) should return the last Monday', () {
      final date = DateTime.parse('2025-01-17'); // Saturday
      final expected = DateTime.parse('2025-01-13'); // Previous Monday
      final result = getMonday(date);
      expect(result.isAtSameMomentAs(expected), isTrue);
    });

    test('Edge case: Any date on the weekend (Sunday) should return the last Monday', () {
      final date = DateTime.parse('2025-01-18'); // Sunday
      final expected = DateTime.parse('2025-01-13'); // Previous Monday
      final result = getMonday(date);
      expect(result.isAtSameMomentAs(expected), isTrue);
    });

    // Under a zone with daylight saving (`make test-dart` and CI run this file
    // as America/New_York): 2026-11-01 is the 25-hour day US clocks went back.
    test('the week after the clocks go back starts on its Monday', () {
      expect(getMonday(DateTime(2026, 11, 1, 23, 59)), DateTime(2026, 10, 26));
      expect(getMonday(DateTime(2026, 11, 8, 23, 59)), DateTime(2026, 11, 2));
      expect(getMonday(DateTime(2026, 3, 15, 0, 30)), DateTime(2026, 3, 9));
    });

    test('every day of two years lands on its own Monday at midnight', () {
      for (var day = DateTime(2025); day.isBefore(DateTime(2027)); day = DateTime(day.year, day.month, day.day + 1)) {
        for (final hour in [0, 12, 23]) {
          final date = DateTime(day.year, day.month, day.day, hour, 59);
          final monday = getMonday(date);
          expect(monday.weekday, DateTime.monday, reason: '$date');
          expect((monday.hour, monday.minute), (0, 0), reason: '$date');
          final back = DateTime.utc(date.year, date.month, date.day).difference(
            DateTime.utc(monday.year, monday.month, monday.day),
          );
          expect(back.inDays, date.weekday - DateTime.monday, reason: '$date');
        }
      }
    });
  });
}
