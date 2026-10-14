/// What a set's effort may hold, and how long an exercise's note may run —
/// one definition for every writer (the workout input, the CSV import),
/// matching the database's own CHECKs. A set's type is `heart_models`'
/// `SetType`, sent to the database as its wire word.
library;

import 'package:heart_models/heart_models.dart';

import 'errors.dart';

/// RPE's scale: 1–10, rated in whole or half points.
bool isRpe(num value) => value >= 1 && value <= 10 && (value * 2) == (value * 2).roundToDouble();

/// The longest note an exercise keeps, counted in code points as the column
/// counts it — so an emoji is one character, not two.
const maxExerciseNoteLength = 500;

/// A set's `set_type` as a body sent it: a wire word, or null for a normal
/// set. Anything else is a 400 naming the set at [at].
SetType setType(Object? value, {required String at}) {
  return switch (value) {
    null => SetType.normal,
    final String word when SetType.values.any((type) => type.value == word) => SetType.fromString(word),
    _ => throw BadRequest(
      code: 'invalid_set_type',
      reason: '$at.set_type must be one of ${SetType.values.map((type) => type.value).join(', ')}, or null',
    ),
  };
}

/// A set's `target` as a body sent it: an object keyed by measure, each a
/// `{min, max?}` range — at least zero, `max` no lower than `min`, reps and
/// seconds whole — plus, in a program, `share`: the weight as a share of the
/// exercise's base. Null (or `{}`) is no target, which clears a stored one.
/// Anything else is a 400 naming the set at [at].
SetTarget setTarget(Object? value, {required String at}) {
  Never invalid(String why) => throw BadRequest(code: 'invalid_target', reason: '$at.target $why');

  bool whole(TargetMeasure measure) => measure == .reps || measure == .duration;

  TargetRange range(TargetMeasure measure, Object? value) {
    final key = measure.value;
    final range = switch (value) {
      final Map m when m.keys.any((k) => k != 'min' && k != 'max') => invalid('.$key takes only min and max'),
      {'min': final num min} && final Map m => switch (m['max']) {
        null => TargetRange(min: min),
        final num max => TargetRange(min: min, max: max),
        _ => invalid('.$key.max must be a number or absent'),
      },
      _ => invalid('.$key must be an object with a numeric min'),
    };
    return switch (range) {
      TargetRange(:final min) when min < 0 => invalid('.$key.min must be >= 0'),
      TargetRange(:final min, max: final num max) when max < min => invalid('.$key.max must be >= min'),
      TargetRange(:final min, :final max) when whole(measure) && [min, ?max].any((n) => n != n.truncate()) => invalid(
        '.$key must be whole numbers',
      ),
      _ => range,
    };
  }

  TargetMeasure measure(Object? key) {
    return switch (TargetMeasure.values.where((measure) => measure.value == key).firstOrNull) {
      final TargetMeasure measure => measure,
      null => invalid('has an unknown measure: $key'),
    };
  }

  // the weight as a share of the exercise's base in a program: above zero,
  // and at most twice it, which no plan reaches
  num? share(Object? value) {
    return switch (value) {
      null => null,
      final num share when share > 0 && share <= 2 => share,
      _ => invalid('.share must be a number above 0 and at most 2'),
    };
  }

  return switch (value) {
    null => SetTarget.none,
    final Map m => SetTarget({
      for (final MapEntry(:key, :value) in m.entries)
        if (key != 'share')
          if (measure(key) case final measure) measure: range(measure, value),
    }, share: share(m['share'])),
    _ => invalid('must be an object or null'),
  };
}
