import 'package:heart/core/openapi/shape.dart';
import 'package:heart_models/heart_models.dart';

// The wire shapes of the heart_models types the API answers with. Their
// `toMap()` is shared with the app and stays the writer; these only describe
// it, and every encode checks the one against the other while asserts are on.
// A field here that a `toMap()` stops writing fails the first test that
// returns one.

final Shape<Workout> workoutShape = .model('Workout', {
  'id': const .required(.string),
  'name': .required(.nullable(.string)),
  'start': const .required(.isoString),
  'end': .required(.nullable(.isoString)),
  'calories': const .optional(
    .number,
    null,
    'An estimate from catalog MET values and a weight the user typed, never a measurement.',
  ),
  'note': .required(.nullable(.string)),
  'pauses': .required(.list(_pause)),
  'templateId': const .optional(.string),
  'programId': const .optional(.string),
  'exercises': .required(.list(_workoutExercise)),
  'images': .required(.list(_imageRow)),
});

final Shape<Model> _pause = .model('WorkoutPause', {
  'start': const .required(.isoString),
  'end': const .required(.isoString),
});

final Shape<Model> _imageRow = .model('WorkoutImageRow', {
  'workoutId': const .required(.string),
  'id': const .required(.string),
  'url': .required(.nullable(.string)),
  'key': .required(.nullable(.string)),
});

final Shape<WorkoutExercise> _workoutExercise = .model('WorkoutExercise', {
  'id': const .required(.string),
  'order': const .required(.integer),
  'exercise': .optional(exerciseShape),
  'start': const .required(.isoString),
  'met': const .optional(.number),
  'note': const .optional(.string),
  'rest': .optional(.nullable(.integer)),
  'superset': .optional(.nullable(.integer)),
  'pattern': .optional(.nullable(.string)),
  'totalReps': .optional(.nullable(_targetRange)),
  'sets': .required(.list(_exerciseSet)),
});

final Shape<ExerciseSet> _exerciseSet = .model('ExerciseSet', {
  'id': const .required(.string),
  'completed': const .required(.boolean),
  'started_at': const .required(.isoString),
  'completed_at': const .optional(.isoString),
  'reps': const .optional(.integer),
  'duration': const .optional(.number),
  'distance': const .optional(.number),
  'weight': const .optional(.number, null, 'Kilograms.'),
  'set_type': const .required(.string),
  'rpe': .required(.nullable(.number)),
  'target': .optional(.nullable(_setTarget)),
});

/// Open: a target carries the kinds a newer build wrote.
final Shape<Model> _setTarget = .model('SetTarget', {
  'reps': .optional(_targetRange),
  'weight': .optional(_targetRange),
  'duration': .optional(_targetRange),
  'distance': .optional(_targetRange),
  'share': const .optional(.number),
  'of': const .optional(.string),
  'ofSlot': const .optional(.integer),
  'rir': const .optional(.integer),
  'supplemental': const .optional(.boolean),
}, open: true);

final Shape<Model> _targetRange = .model('TargetRange', {
  'min': const .required(.number),
  'max': const .optional(.number),
  'amrap': const .optional(.boolean),
});

final Shape<Exercise> exerciseShape = .model('Exercise', {
  'id': const .required(.string),
  'key': const .optional(.string),
  'category': .required(.enumOf<Category>(Category.values, (category) => category.value)),
  'name': const .required(.string),
  'target': .required(.enumOf<Target>(Target.values, (target) => target.value)),
  'instructions': const .optional(.string),
  'validated': const .optional(.flag),
  'aliases': .optional(.list(.string)),
  'asset': const .optional(.string),
  'assetHeight': .optional(.nullable(.number)),
  'assetWidth': .optional(.nullable(.number)),
  'thumbnail': const .optional(.string),
  'thumbnailHeight': .optional(.nullable(.number)),
  'thumbnailWidth': .optional(.nullable(.number)),
  'own': const .required(.flag),
  'archived': const .required(.flag),
  'muscles': .optional(_muscles),
  'movement': .optional(_movement),
  'health': .optional(_health),
  'unitSystem': .optional(.enumOf<MeasurementUnit>(MeasurementUnit.values, (unit) => unit.name)),
  'restTimer': const .optional(.integer),
});

final Shape<Model> _muscles = .model('MuscleTagging', {
  'primary': .required(_muscleTag),
  'secondary': .optional(_muscleTag),
});

final Shape<Model> _muscleTag = .model('MuscleTag', {
  'ids': .required(.nullable(.list(.string))),
  'groups': .required(.nullable(.list(.string))),
  'share': const .optional(.number),
});

final Shape<Model> _movement = .model('Movement', {
  'groups': .required(.list(.string)),
  'axialLoad': const .required(.string),
  'stability': const .required(.string),
  'unilateral': const .required(.boolean),
  'impact': const .required(.string),
  'skill': const .required(.string),
});

final Shape<Model> _health = .model('ExerciseHealth', {
  'activity': const .optional(.string),
});
