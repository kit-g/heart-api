import 'package:heart/core/openapi/shape.dart';
import 'package:heart_models/heart_models.dart';

// The wire shapes of the heart_models types the API answers with. Their
// `toMap()` is shared with the app and stays the writer; these only describe
// it, and every encode checks the one against the other while asserts are on.
// A field here that a `toMap()` stops writing fails the first test that
// returns one.

final Shape<Workout> workoutShape = .model('Workout', {
  'id': .required(.string),
  'name': .required(.nullable(.string)),
  'start': .required(.isoString),
  'end': .required(.nullable(.isoString)),
  'calories': .optional(
    .number,
    null,
    'An estimate from catalog MET values and a weight the user typed, never a measurement.',
  ),
  'note': .required(.nullable(.string)),
  'pauses': .required(.list(_pause)),
  'templateId': .optional(.string),
  'programId': .optional(.string),
  'exercises': .required(.list(_workoutExercise)),
  'images': .required(.list(_imageRow)),
});

final Shape<Model> _pause = .model('WorkoutPause', {
  'start': .required(.isoString),
  'end': .required(.isoString),
});

final Shape<Model> _imageRow = .model('WorkoutImageRow', {
  'workoutId': .required(.string),
  'id': .required(.string),
  'url': .required(.nullable(.string)),
  'key': .required(.nullable(.string)),
});

final Shape<WorkoutExercise> _workoutExercise = .model('WorkoutExercise', {
  'id': .required(.string),
  'order': .required(.integer),
  'exercise': .optional(exerciseShape),
  'start': .required(.isoString),
  'met': .optional(.number),
  'note': .optional(.string),
  'rest': .optional(.nullable(.integer)),
  'superset': .optional(.nullable(.integer)),
  'pattern': .optional(.nullable(.string)),
  'totalReps': .optional(.nullable(_targetRange)),
  'sets': .required(.list(_exerciseSet)),
});

final Shape<ExerciseSet> _exerciseSet = .model('ExerciseSet', {
  'id': .required(.string),
  'completed': .required(.boolean),
  'started_at': .required(.isoString),
  'completed_at': .optional(.isoString),
  'reps': .optional(.integer),
  'duration': .optional(.number),
  'distance': .optional(.number),
  'weight': .optional(.number, null, 'Kilograms.'),
  'set_type': .required(.string),
  'rpe': .required(.nullable(.number)),
  'target': .optional(.nullable(_setTarget)),
});

/// Open: a target carries the kinds a newer build wrote.
final Shape<Model> _setTarget = .model('SetTarget', {
  'reps': .optional(_targetRange),
  'weight': .optional(_targetRange),
  'duration': .optional(_targetRange),
  'distance': .optional(_targetRange),
  'share': .optional(.number),
  'of': .optional(.string),
  'ofSlot': .optional(.integer),
  'rir': .optional(.integer),
  'supplemental': .optional(.boolean),
}, open: true);

final Shape<Model> _targetRange = .model('TargetRange', {
  'min': .required(.number),
  'max': .optional(.number),
  'amrap': .optional(.boolean),
});

final Shape<Exercise> exerciseShape = .model('Exercise', {
  'id': .required(.string),
  'key': .optional(.string),
  'category': .required(.enumOf<Category>(Category.values, (category) => category.value)),
  'name': .required(.string),
  'target': .required(.enumOf<Target>(Target.values, (target) => target.value)),
  'instructions': .optional(.string),
  'validated': .optional(.flag),
  'aliases': .optional(.list(.string)),
  'asset': .optional(.string),
  'assetHeight': .optional(.nullable(.number)),
  'assetWidth': .optional(.nullable(.number)),
  'thumbnail': .optional(.string),
  'thumbnailHeight': .optional(.nullable(.number)),
  'thumbnailWidth': .optional(.nullable(.number)),
  'own': .required(.flag),
  'archived': .required(.flag),
  'muscles': .optional(_muscles),
  'movement': .optional(_movement),
  'health': .optional(_health),
  'unitSystem': .optional(.enumOf<MeasurementUnit>(MeasurementUnit.values, (unit) => unit.name)),
  'restTimer': .optional(.integer),
});

final Shape<Model> _muscles = .model('MuscleTagging', {
  'primary': .required(_muscleTag),
  'secondary': .optional(_muscleTag),
});

final Shape<Model> _muscleTag = .model('MuscleTag', {
  'ids': .required(.nullable(.list(.string))),
  'groups': .required(.nullable(.list(.string))),
  'share': .optional(.number),
});

final Shape<Model> _movement = .model('Movement', {
  'groups': .required(.list(.string)),
  'axialLoad': .required(.string),
  'stability': .required(.string),
  'unilateral': .required(.boolean),
  'impact': .required(.string),
  'skill': .required(.string),
});

final Shape<Model> _health = .model('ExerciseHealth', {
  'activity': .optional(.string),
});
