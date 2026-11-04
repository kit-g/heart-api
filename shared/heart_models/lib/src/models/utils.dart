/// Reverses the Firebase-era escaping of [sanitizeId]. Kept as a reader only:
/// device DBs still hold ids and week keys written with `_` for `.`, and those
/// must parse forever. Plain ISO strings pass through untouched.
String deSanitizeId(String id) => id.replaceAll('_', '.');

@Deprecated(
  "Firebase-era escaping ('.' was Firebase's path separator); nothing writes these ids anymore. "
  'Mint a v7 uuid (uuidV7) for identities, or use plain toIso8601String() for date keys — '
  'readers go through deSanitizeId, which accepts both forms.',
)
String sanitizeId(DateTime start) => start.toIso8601String().replaceAll('.', '_');

/// Midnight, local time, on the Monday of [date]'s week; a Monday gives its
/// own midnight.
///
/// The week is read from [date]'s calendar fields, in its own zone, and the
/// result is local, so a UTC [date] gives the local midnight of its UTC week's
/// Monday.
///
/// Steps back by calendar days, not 24-hour durations: a week with a clock
/// change has a 23- or 25-hour day, and subtracting durations across it lands
/// a day off (heart-api#383).
///
/// ```dart
/// getMonday(DateTime(2025, 1, 14, 9)); // 2025-01-13 00:00:00.000
/// ```
DateTime getMonday(DateTime date) {
  return DateTime(date.year, date.month, date.day - (date.weekday - DateTime.monday));
}
