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
  'Anomaly.observed': .shape(.mapOf(.unknown('what was entered, by field'))),
  'CountMap.*': const .open('`sets`, `primarySets` and `sessions` by the name being counted.'),
  // maps assembled before a toMap() sees them, whose keys it can't read
  'MeGoalProgress.goals': .shape(
    .list(.unknown('a goal, with its `exerciseName`, `period`, `current`, `progress` and `warnings`')),
  ),
  'MeBalance.pairs': .shape(.list(.unknown('a pair: its `key`, `left`, `right` and `weeksTrained`'))),
  'ProgramHistory.actions': .shape(.list(.unknown('an action of the program'))),
  'ProgramHistory.skips': .shape(.list(.unknown('a skipped session of the program'))),
  'ProgramHistoryBase.*': const .open('a base, with its `cause` and `previous`.'),
  // keyed by what the program's author named
  'MeProgram.stages': .shape(.mapOf(.integer)),
  'MeProgram.research': .shape(.unknown('the research behind a library program')),
  'MeProgramBases.*': const .open('a base by the slot or exercise it belongs to.'),
  'ProgramRules.*': const .open('a rule by the name its sessions use.'),
  'ProgramTests.*': const .open('a test session by its name.'),
  'ProgramJoined.*': const .open('when each slot joined, by the slot.'),
  // strings the server formats as moments, which their type can't say
  'MeExerciseSession.at': const .shape(.isoString),
  'MeRecordsRecord.lastTrained': const .shape(.isoString),
  // what a caller needs to know that no doc comment says, or says for the
  // app's developers rather than the API's
  'ExerciseSet.set_type': const .describe(
    'What kind of set: `normal`, `warmup`, `drop` or `failure`, and a word you don\'t know may be added.',
  ),
  'Goal.pattern': const .describe('A movement pattern key from the exercise library (`horizontal_press`).'),
  'Goal.muscle': const .describe('A muscle id prefix (`triceps_brachii`) or a muscle group (`chest`).'),
  'Warning.reason': const .describe('Why the entry looks wrong. A word you don\'t know may be added.'),
  'Anomaly.reason': const .describe('Why the entry looks wrong. A word you don\'t know may be added.'),
  'ExerciseSet.weight': const .describe('Kilograms.'),
  'MeWorkoutChanges.cursor': const .describe('Where to resume: pass it back as `since`.'),
  'MeExerciseSession.metrics': const .describe('What the progress chart plots, by chart.'),
};
