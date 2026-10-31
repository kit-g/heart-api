import 'package:heart/core/openapi/shape.dart';

import 'shapes.g.dart';

/// What `tool/openapi/shapes.dart` cannot read from a `toMap()`, said by
/// hand, keyed as the generator names the object and its key. The generator
/// fails on a hole no entry here covers, and on an entry nothing reads.
final Map<String, ShapeOverride> shapeOverrides = {
  // the tolerant reads: what a newer build wrote, carried untouched
  'WorkoutExercise.totalReps': .shape(.nullable(targetRangeShape)),
  'SetTarget.*': const .open('a target carries the kinds a newer build wrote.'),
  // values computed at runtime
  'MeRecordsRecord.*': const .open(
    'each record kind `toPersonalRecords` computes (heaviest, oneRepMax, …), beside the exercise.',
  ),
  'Warning.observed': .shape(.mapOf(.unknown('what was entered, by field'))),
  // strings the server formats as moments, which their type can't say
  'MeExerciseSession.at': const .shape(.isoString),
  'MeRecordsRecord.lastTrained': const .shape(.isoString),
  // what a caller needs to know that no doc comment says
  'ExerciseSet.weight': const .describe('Kilograms.'),
  'MeWorkoutChanges.cursor': const .describe('Where to resume: pass it back as `since`.'),
  'MeExerciseSession.metrics': const .describe('What the progress chart plots, by chart.'),
};
