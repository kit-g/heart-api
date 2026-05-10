String deSanitizeId(String id) => id.replaceAll('_', '.');

String sanitizeId(DateTime start) => start.toIso8601String().replaceAll('.', '_');

/// Returns the `DateTime` of the Monday of the week for the given [date] date.
///
/// This function calculates the previous Monday for any given `DateTime` object.
/// If the provided date is already a Monday, it returns the same date.
///
/// The function works as follows:
/// - It checks the weekday of the given [date] date, where 1 represents Monday and 7 represents Sunday.
/// - It then calculates how many days to subtract to get to the previous Monday.
/// - If the given date is already a Monday, it returns the same date.
/// - Otherwise, it subtracts the necessary number of days to reach the most recent Monday.
///
/// Example:
/// ```dart
/// final date = DateTime.parse('2025-01-14'); // A Tuesday
/// final monday = _getMonday(date);
/// print(monday); // Outputs: 2025-01-13 00:00:00.000
/// ```
///
/// Parameters:
/// - [date]: A `DateTime` object representing any date in the week.
///
/// Returns:
/// - A `DateTime` object representing the Monday of the week that the [random] date belongs to.
///
/// Edge Cases:
/// - If the given date is already a Monday, the function returns the same date.
/// - It handles dates from any day of the week, including edge cases like weekend dates.
DateTime getMonday(DateTime date) {
  final daysToSubtract = switch (date.weekday - DateTime.monday) {
    int count when count < 0 => count + 7,
    int count => count,
  };

  final monday = switch (date.subtract(Duration(days: daysToSubtract)).isAtSameMomentAs(date)) {
    true => date, // If the given date is Monday, return it,
    false => date.subtract(Duration(days: daysToSubtract)),
  };

  return DateTime(monday.year, monday.month, monday.day);
}
