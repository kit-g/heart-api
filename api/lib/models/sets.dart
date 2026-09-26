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
