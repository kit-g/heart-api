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

/// A `{min, max?, amrap?}` range as a body sent it, at [at]: at least zero,
/// `max` no lower than `min`, whole numbers when [whole], and `amrap` only
/// when [amrap] allows it. Anything else is a 400 `invalid_target`.
TargetRange targetRange(Object? value, {required String at, required bool whole, bool amrap = true}) {
  Never invalid(String why) => throw BadRequest(code: 'invalid_target', reason: '$at $why');

  final keys = {'min', 'max', if (amrap) 'amrap'};
  final range = switch (value) {
    final Map m when m.keys.any((k) => !keys.contains(k)) => invalid('takes only ${keys.join(', ')}'),
    {'min': final num min} && final Map m => switch ((m['max'], m['amrap'])) {
      (_, final Object amrap) when amrap is! bool => invalid('.amrap must be true or false'),
      (null, _) => TargetRange(min: min),
      (final num max, final bool? amrap) => TargetRange(min: min, max: max, amrap: amrap ?? false),
      _ => invalid('.max must be a number or absent'),
    },
    _ => invalid('must be an object with a numeric min'),
  };
  return switch (range) {
    TargetRange(:final min) when min < 0 => invalid('.min must be >= 0'),
    TargetRange(:final min, max: final num max) when max < min => invalid('.max must be >= min'),
    TargetRange(:final min, :final max) when whole && [min, ?max].any((n) => n != n.truncate()) => invalid(
      'must be whole numbers',
    ),
    _ => range,
  };
}

/// A superset number within one template or workout: 1 to 50, or null for
/// none. Anything else is a 400 naming the exercise at [at].
int? superset(Object? value, {required String at}) {
  return switch (value) {
    null => null,
    final int n when n >= 1 && n <= 50 => n,
    _ => throw BadRequest(reason: '$at.superset must be a whole number from 1 to 50, or null'),
  };
}

/// A set's `target` as a body sent it: an object keyed by measure, each a
/// `{min, max?}` range — at least zero, `max` no lower than `min`, reps and
/// seconds whole, and `amrap` on a bounded range for "as many as you can, up to
/// max" — plus `rir`, reps in reserve, and in a program `share`, the weight as
/// a share of the exercise's base, or of another's named by `of`, at the
/// occurrence `ofSlot` names. Null (or `{}`) is no target, which clears a
/// stored one.
/// Anything else is a 400 naming the set at [at].
SetTarget setTarget(Object? value, {required String at}) {
  Never invalid(String why) => throw BadRequest(code: 'invalid_target', reason: '$at.target $why');

  bool whole(TargetMeasure measure) => measure == .reps || measure == .duration;

  TargetRange range(TargetMeasure measure, Object? value) {
    return targetRange(value, at: '$at.target.${measure.value}', whole: whole(measure));
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

  // reps in reserve: whole or half reps, and past 10 it says nothing
  num? rir(Object? value) {
    return switch (value) {
      null => null,
      final num rir when rir >= 0 && rir <= 10 && rir * 2 == (rir * 2).truncate() => rir,
      _ => invalid('.rir must be a number of reps from 0 to 10, in halves'),
    };
  }

  // whose base the share is of: another exercise, by id; only with a share
  String? of(Object? value, {required bool shared}) {
    return switch (value) {
      null => null,
      final String id when isUuidV7(id) && shared => id,
      final String _ when !shared => invalid('.of names whose base a share is of, so it needs a share'),
      _ => invalid('.of must be an exercise id'),
    };
  }

  // which occurrence of `of` the share is of: a template exercise, by id; only
  // beside `of`, the lift it is an occurrence of
  String? ofSlot(Object? value, {required bool named}) {
    return switch (value) {
      null => null,
      final String id when isUuidV7(id) && named => id,
      final String _ when !named => invalid('.ofSlot names an occurrence of the lift in of, so it needs of'),
      _ => invalid('.ofSlot must be a template exercise id'),
    };
  }

  return switch (value) {
    null => SetTarget.none,
    final Map m => SetTarget(
      {
        for (final MapEntry(:key, :value) in m.entries)
          if (!const {'share', 'rir', 'of', 'ofSlot', 'supplemental'}.contains(key))
            if (measure(key) case final measure) measure: range(measure, value),
      },
      share: share(m['share']),
      rir: rir(m['rir']),
      of: of(m['of'], shared: m['share'] != null),
      ofSlot: ofSlot(m['ofSlot'], named: m['of'] != null),
      supplemental: switch (m['supplemental']) {
        null || false => false,
        true => true,
        _ => invalid('.supplemental must be true or false'),
      },
    ),
    _ => invalid('must be an object or null'),
  };
}
