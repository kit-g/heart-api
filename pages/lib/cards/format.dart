/// Locale-aware formatting for a card, supplied by whichever side renders
/// it: the browser's `Intl` in an MCP Apps view (in the host's locale and time
/// zone), `package:intl` on a server.
abstract interface class Format {
  /// [n] with at most [digits] fraction digits, grouped for the locale.
  String number(num n, [int digits = 1]);

  /// An ISO timestamp as a weekday, date and time.
  String dateTime(String iso);
}
