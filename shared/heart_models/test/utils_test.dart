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
  });
}
