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
/// as many as possible).
final class TargetRange implements Model {
  final num min;
  final num? max;

  const new({required this.min, this.max});

  factory exactly(num value) => TargetRange(min: value, max: value);

  bool get isExact => max == min;

  bool get isOpen => max == null;

  /// Reads `{min, max?}`, and nothing else: a range carrying a key this build
  /// doesn't know is a shape it predates, so it is an [ArgumentError] here and
  /// [SetTarget.fromJson] carries it as it arrived.
  factory fromJson(Map json) {
    if (json.keys.any((key) => key != 'min' && key != 'max')) {
      throw ArgumentError.value(json, 'target', 'unknown range shape');
    }
    return switch (json) {
      {'min': final num min, 'max': final num max} => TargetRange(min: min, max: max),
      {'min': final num min} when json['max'] == null => TargetRange(min: min),
      _ => throw ArgumentError.value(json, 'target', 'unknown range shape'),
    };
  }

  @override
  Map<String, dynamic> toMap() => {'min': min, 'max': ?max};

  @override
  bool operator ==(Object other) => other is TargetRange && other.min == min && other.max == max;

  @override
  int get hashCode => Object.hash(min, max);

  @override
  String toString() => 'TargetRange($min, $max)';
}

/// What a template set aims for, per measure: "6 to 10 reps", "hold 30 s",
/// "8+". A target is a plan, never a record of what was done; a logged set
/// carries none.
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

  TargetRange? operator [](TargetMeasure measure);

  /// The same target with [measure]'s range replaced, or removed when [range]
  /// is null. Everything else, what this build could not read included, stays.
  SetTarget withRange(TargetMeasure measure, TargetRange? range);

  factory(Map<TargetMeasure, TargetRange> ranges, {num? share}) => _SetTarget(Map.of(ranges), const {}, share);

  factory fromJson(Map json) {
    final ranges = <TargetMeasure, TargetRange>{};
    final unread = <String, Object?>{};
    num? share;
    for (final MapEntry(:key, :value) in json.entries) {
      if (key == 'share' && value is num && value > 0) {
        share = value;
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
    return _SetTarget(ranges, unread, share);
  }
}

class _SetTarget implements SetTarget {
  @override
  final Map<TargetMeasure, TargetRange> ranges;

  /// Measures this build could not read, by their wire key, as they arrived.
  final Map<String, Object?> _unread;

  @override
  final num? share;

  const new(this.ranges, this._unread, [this.share]);

  @override
  bool get isEmpty => ranges.isEmpty && _unread.isEmpty && share == null;

  @override
  SetTarget withShare(num? share) => _SetTarget(ranges, {..._unread}..remove('share'), share);

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
    return _SetTarget(ranges, {..._unread}..remove(measure.value), share);
  }

  @override
  Map<String, dynamic> toMap() {
    return {
      ..._unread,
      for (final MapEntry(:key, :value) in ranges.entries) key.value: value.toMap(),
      'share': ?share,
    };
  }

  @override
  String toString() => 'SetTarget(${toMap()})';
}
