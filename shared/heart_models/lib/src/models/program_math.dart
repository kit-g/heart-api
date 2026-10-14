import 'exercise_set.dart';
import 'set_target.dart';

// Shared by `Progression` and `PlannedSession`, and left out of the package's
// exports.

/// [value] rounded down to a whole number of [step]s: a weight the plates can
/// make.
num roundDown(num value, num step) {
  if (step <= 0) return value;
  final steps = (value / step + 1e-9).floor();
  final rounded = steps * step;
  return rounded == rounded.roundToDouble() ? rounded.round() : double.parse(rounded.toStringAsFixed(3));
}

/// Whether a `longer` rule grows [set]'s distance rather than its duration:
/// the measure [target] names, else distance for an exercise logged by weight
/// and distance.
bool growsDistance(ExerciseSet set, SetTarget? target) {
  return switch ((target?[.distance], target?[.duration])) {
    (final TargetRange _, _) => true,
    (null, final TargetRange _) => false,
    _ => set.category == .weightedDistance,
  };
}
