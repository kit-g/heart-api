import 'misc.dart';

/// A value a set records, as a target names it: the same units as the set's
/// own fields — kilograms, kilometres, seconds, a count of reps.
enum TargetMeasure {
  reps('reps'),
  weight('weight'),
  duration('duration'),
  distance('distance');

  /// The key under `target` on the wire.
  final String value;

  new(this.value);
}

/// One measure's aim: at least [min], at most [max]. A [max] equal to [min] is
/// an exact number ("8 reps", "hold 30 s"); a null [max] is an open top ("8+",
/// as many as possible). An [amrap] range with a [max] is as many as possible
/// up to it ("up to 10"): estimated-max formulas break down past about 10.
final class TargetRange implements Model {
  final num min;
  final num? max;
  final bool amrap;

  const new({required this.min, this.max, this.amrap = false});

  factory exactly(num value) => TargetRange(min: value, max: value);

  bool get isExact => max == min;

  bool get isOpen => max == null;

  /// As many as possible: an open top, or a capped [amrap].
  bool get isAmrap => isOpen || amrap;

  /// Reads `{min, max?, amrap?}`, and nothing else: a range carrying a key this
  /// build doesn't know is a shape it predates, so it is an [ArgumentError] here
  /// and [SetTarget.fromJson] carries it as it arrived.
  factory fromJson(Map json) {
    if (json.keys.any((key) => key != 'min' && key != 'max' && key != 'amrap')) {
      throw ArgumentError.value(json, 'target', 'unknown range shape');
    }
    final amrap = switch (json['amrap']) {
      null || false => false,
      true => true,
      _ => throw ArgumentError.value(json, 'target', 'unknown range shape'),
    };
    return switch (json) {
      {'min': final num min, 'max': final num max} => TargetRange(min: min, max: max, amrap: amrap),
      {'min': final num min} when json['max'] == null => TargetRange(min: min),
      _ => throw ArgumentError.value(json, 'target', 'unknown range shape'),
    };
  }

  @override
  Map<String, dynamic> toMap() => {'min': min, 'max': ?max, if (amrap && max != null) 'amrap': true};

  @override
  bool operator ==(Object other) =>
      other is TargetRange && other.min == min && other.max == max && other.amrap == amrap;

  @override
  int get hashCode => Object.hash(min, max, amrap);

  @override
  String toString() => 'TargetRange($min, $max${amrap ? ', amrap' : ''})';
}

/// What a template set aims for, or a logged set aimed for, per measure: "6
/// to 10 reps", "hold 30 s", "8+". A target is a plan, never a record of what
/// was done; a logged set carries it beside its values.
///
/// Read tolerantly: a measure this build doesn't know, or a range of a shape it
/// predates, is kept as it arrived and written back by [toMap], so a save by
/// this build never drops what a newer one wrote.
abstract interface class SetTarget implements Model {
  /// No target at all. On a template write it clears a stored one.
  static final none = SetTarget(const {});

  /// The ranges this build can read.
  Map<TargetMeasure, TargetRange> get ranges;

  /// Nothing at all, readable or not.
  bool get isEmpty;

  /// The weight as a share of the exercise's base in a program, a training
  /// max (heart-api#86): 0.85 is 85%. On the wire as `share`, beside the
  /// measures. Outside a program it has nothing to be a share of.
  num? get share;

  /// The same target with [share] replaced, or removed when null.
  SetTarget withShare(num? share);

  /// Whose base [share] is a share of: another exercise's id (the front squat
  /// at 60% of the squat's training max). Null is the set's own exercise. On
  /// the wire as `of`.
  String? get of;

  /// The same target as a share of another exercise's base, or of its own when
  /// [of] is null.
  SetTarget withOf(String? of);

  /// Which occurrence of [of] the share is of, when the lift has a base per
  /// slot: a template exercise id, the volume day at 90% of the intensity
  /// day's squat (heart-api#257). Its base, else [of]'s own. On the wire as
  /// `ofSlot`, only beside `of`.
  String? get ofSlot;

  /// The same target as a share of [ofSlot]'s base, or of [of]'s own when
  /// null.
  SetTarget withOfSlot(String? ofSlot);

  /// A supplemental set (a first-set-last 5×5 after the main sets): it takes
  /// its share like the others but never counts for an AMRAP, a miss or a bump.
  /// On the wire as `supplemental: true`.
  bool get supplemental;

  /// Reps in reserve: stop with this many left in the tank. On the wire as
  /// `rir`, beside the measures.
  num? get rir;

  /// The same target with [rir] replaced, or removed when null.
  SetTarget withRir(num? rir);

  TargetRange? operator [](TargetMeasure measure);

  /// The same target with [measure]'s range replaced, or removed when [range]
  /// is null. Everything else, what this build could not read included, stays.
  SetTarget withRange(TargetMeasure measure, TargetRange? range);

  factory(
    Map<TargetMeasure, TargetRange> ranges, {
    num? share,
    num? rir,
    String? of,
    String? ofSlot,
    bool supplemental = false,
  }) =>
      _SetTarget(Map.of(ranges), const {}, share: share, rir: rir, of: of, ofSlot: ofSlot, supplemental: supplemental);

  factory fromJson(Map json) {
    final ranges = <TargetMeasure, TargetRange>{};
    final unread = <String, Object?>{};
    num? share;
    num? rir;
    String? of;
    String? ofSlot;
    var supplemental = false;
    for (final MapEntry(:key, :value) in json.entries) {
      if (key == 'supplemental' && value is bool) {
        supplemental = value;
        continue;
      }
      if (key == 'of' && value is String) {
        of = value;
        continue;
      }
      if (key == 'ofSlot' && value is String) {
        ofSlot = value;
        continue;
      }
      if (key == 'share' && value is num && value > 0) {
        share = value;
        continue;
      }
      if (key == 'rir' && value is num && value >= 0) {
        rir = value;
        continue;
      }
      final measure = TargetMeasure.values.where((each) => each.value == key).firstOrNull;
      try {
        switch ((measure, value)) {
          case (final TargetMeasure measure, final Map range):
            ranges[measure] = TargetRange.fromJson(range);
          default:
            unread['$key'] = value;
        }
      } on ArgumentError {
        unread['$key'] = value;
      }
    }
    return _SetTarget(ranges, unread, share: share, rir: rir, of: of, ofSlot: ofSlot, supplemental: supplemental);
  }
}

class _SetTarget implements SetTarget {
  @override
  final Map<TargetMeasure, TargetRange> ranges;

  /// Measures this build could not read, by their wire key, as they arrived.
  final Map<String, Object?> _unread;

  @override
  final num? share;
  @override
  final num? rir;
  @override
  final String? of;
  @override
  final String? ofSlot;
  @override
  final bool supplemental;

  const new(this.ranges, this._unread, {this.share, this.rir, this.of, this.ofSlot, this.supplemental = false});

  @override
  bool get isEmpty =>
      ranges.isEmpty &&
      _unread.isEmpty &&
      share == null &&
      rir == null &&
      of == null &&
      ofSlot == null &&
      !supplemental;

  @override
  SetTarget withShare(num? share) => _SetTarget(
    ranges,
    {..._unread}..remove('share'),
    share: share,
    rir: rir,
    of: of,
    ofSlot: ofSlot,
    supplemental: supplemental,
  );

  @override
  SetTarget withRir(num? rir) => _SetTarget(
    ranges,
    {..._unread}..remove('rir'),
    share: share,
    rir: rir,
    of: of,
    ofSlot: ofSlot,
    supplemental: supplemental,
  );

  @override
  SetTarget withOf(String? of) => _SetTarget(
    ranges,
    {..._unread}..remove('of'),
    share: share,
    rir: rir,
    of: of,
    ofSlot: ofSlot,
    supplemental: supplemental,
  );

  @override
  SetTarget withOfSlot(String? ofSlot) => _SetTarget(
    ranges,
    {..._unread}..remove('ofSlot'),
    share: share,
    rir: rir,
    of: of,
    ofSlot: ofSlot,
    supplemental: supplemental,
  );

  @override
  TargetRange? operator [](TargetMeasure measure) => ranges[measure];

  @override
  SetTarget withRange(TargetMeasure measure, TargetRange? range) {
    final ranges = Map.of(this.ranges);
    switch (range) {
      case final TargetRange range:
        ranges[measure] = range;
      case null:
        ranges.remove(measure);
    }
    // the user set this measure, so a value this build couldn't read under
    // the same key no longer stands
    return _SetTarget(
      ranges,
      {..._unread}..remove(measure.value),
      share: share,
      rir: rir,
      of: of,
      ofSlot: ofSlot,
      supplemental: supplemental,
    );
  }

  @override
  Map<String, dynamic> toMap() {
    return {
      ..._unread,
      for (final MapEntry(:key, :value) in ranges.entries) key.value: value.toMap(),
      'share': ?share,
      'of': ?of,
      'ofSlot': ?ofSlot,
      'rir': ?rir,
      if (supplemental) 'supplemental': true,
    };
  }

  @override
  String toString() => 'SetTarget(${toMap()})';
}
