import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

import 'format.dart';
import 'units.dart';

/// A tool result read tolerantly: a missing or mistyped field is null or
/// empty, never an error, so a card leaves its line out instead of failing.
extension Json on Map<String, Object?> {
  String? text(String key) => switch (this[key]) {
    final String text => text,
    _ => null,
  };

  num? number(String key) => switch (this[key]) {
    final num n when n.isFinite => n,
    _ => null,
  };

  Map<String, Object?>? object(String key) => switch (this[key]) {
    final Map<String, Object?> map => map,
    _ => null,
  };

  List<Map<String, Object?>> maps(String key) => [
    if (this[key] case final List list)
      for (final item in list)
        if (item case final Map<String, Object?> item) item,
  ];

  List<Map<String, Object?>> get sets => maps('sets');

  /// `225 kg × 5 · RPE 8`, `8 reps`, `2 km · 8:00`, or a dash for a set with
  /// nothing in it, in [units].
  String toSetText(Format format, Units units) {
    final parts = [
      switch ((number('weightKg'), number('reps'))) {
        (final weight?, final reps?) => '${format.weight(weight, units)} × $reps',
        (final weight?, null) => format.weight(weight, units),
        (null, 1) => '1 rep',
        (null, final reps?) => '$reps reps',
        _ => null,
      },
      if (number('distanceKm') case final km?) format.distance(km, units),
      if (number('seconds') case final seconds?) seconds.toClock(),
    ].nonNulls;
    final text = parts.isEmpty ? '—' : parts.join(' · ');
    return switch (number('rpe')) {
      final rpe? => '$text · RPE ${format.number(rpe)}',
      null => text,
    };
  }
}

/// The tools' kilograms, kilometres and seconds per kilometre, in the user's
/// [Units].
extension Measures on Format {
  /// `102.5 kg`, `226 lb`.
  String weight(num kg, Units units, [int digits = 1]) => '${number(units.fromKg(kg), digits)} ${units.weight}';

  /// `5.02 km`, `3.12 mi`.
  String distance(num km, Units units) => '${number(units.fromKm(km), 2)} ${units.distance}';

  /// `5:12 /km`, `8:22 /mi`.
  String pace(num secondsPerKm, Units units) => '${units.perKm(secondsPerKm).toClock()} /${units.distance}';
}

/// A count of seconds, as the tools give durations.
extension Seconds on num {
  /// `8:00`, `1:02:05`.
  String toClock() {
    String pad(int n) => n.toString().padLeft(2, '0');
    final s = round(), hours = s ~/ 3600, minutes = s % 3600 ~/ 60;
    return hours > 0 ? '$hours:${pad(minutes)}:${pad(s % 60)}' : '$minutes:${pad(s % 60)}';
  }

  /// `1 h 24 m`, `52 m`, `40 s`.
  String toSpan() {
    if (this < 60) return '${round()} s';
    final minutes = (this / 60).round();
    return minutes >= 60 ? '${minutes ~/ 60} h ${minutes % 60} m' : '$minutes m';
  }
}

/// `1 session`, `3 sessions`.
String plural(num n, String one) => n == 1 ? '1 $one' : '$n ${one}s';

/// A result's `warnings`, flagged anomalies not yet reviewed, as one line, or
/// nothing when there are none.
Component? warningsOf(Object? warnings) {
  return switch (warnings) {
    List(isEmpty: false, length: 1) => const p(classes: 'warn', [
      .text('One entry here looks off and has not been checked yet.'),
    ]),
    List(isEmpty: false, :final length) => p(classes: 'warn', [
      .text('$length entries here look off and have not been checked yet.'),
    ]),
    _ => null,
  };
}
