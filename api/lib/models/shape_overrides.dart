import 'package:heart/core/openapi/shape.dart';
import 'package:heart/models/exercises.dart';
import 'package:heart/models/library.dart';

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
  // a stage by the slot or exercise it belongs to, and a rule by the name its
  // sessions use, with those a newer build wrote beside them
  'MeProgram.stages': .shape(.mapOf(.integer)),
  'ProgramRules.*': const .open('a rule by the name its sessions use, and those a newer build wrote.'),
  'GrowthRule.*': const .open('`kind` says which rule; its parameters sit beside it.'),
  'Weather.*': const .open('it carries what a newer build wrote.'),
  // published content read back through the library
  'MeProgram.research': .shape(programResearchShape),
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

// Bodies no `toMap()` spells out, said by hand and checked like the rest while
// asserts are on: rows the database assembles, and published content, which
// stays open for what a later library adds.

/// `GET /me/exercises`: the rows as the query writes them, which is snake_case
/// for the two a preference holds.
final Shape<ExerciseResponse> customExercisesShape = .model('CustomExercises', {
  'exercises': .required(.list(_customExercise)),
  'glossary': .required(
    .mapOf(.unknown('what a search abbreviation stands for: its `words`, or the `muscles` it means')),
    'The abbreviations a search understands.',
  ),
});

final Shape<Object?> _customExercise = .described('CustomExercise', {
  'id': const .required(.string),
  'key': .required(.nullable(.string), 'The library\'s key; null for your own.'),
  'name': const .required(.string),
  'category': const .required(.string),
  'target': const .required(.string),
  'instructions': .required(.nullable(.string)),
  'validated': .required(.unknown('whether the library has checked it')),
  'aliases': .required(.nullable(.list(.string))),
  'asset': .required(.nullable(.string)),
  'thumbnail': .required(.nullable(.string)),
  'muscles': .required(.unknown('the muscles it works, as a library exercise says them')),
  'movement': .required(.unknown('the movement it is, as a library exercise says it')),
  'health': .required(.unknown('how it maps to a workout type on the phone')),
  'own': const .required(.boolean),
  'archived': const .required(.boolean),
  'unit_system': .required(.nullable(.string)),
  'rest_timer': .required(.nullable(.integer), 'Seconds.'),
});

/// `GET /me/library/programs`.
final Shape<LibraryResponse> libraryProgramsShape = .model('LibraryPrograms', {
  'programs': .required(.list(_programSummary)),
});

const Map<String, Field> _summaryFields = {
  'key': .required(Shape.string),
  'name': .required(Shape.string),
  'note': .optional(Shape.string),
  'audience': .optional(Shape.string, 'Who it\'s for.'),
  'equipment': .optional(Shape.string, 'What it needs.'),
  'perWeek': .optional(Shape.integer, 'Days a week.'),
  'minutes': .optional(Shape.integer, 'Minutes a session.'),
  'weeks': .optional(Shape.integer, 'How long it runs, when it has an end.'),
  'minApp': .optional(Shape.string, 'The oldest app version that can run it.'),
  'who': .optional(Shape.string),
};

final Shape<Object?> _programSummary = .described('LibraryProgramSummary', _summaryFields, open: true);

/// `GET /me/library/programs/:key`.
final Shape<LibraryResponse> libraryProgramShape = .model('LibraryProgram', {
  ..._summaryFields,
  'week': const .optional(.string, 'What a week looks like.'),
  'grows': const .optional(.string, 'How it grows.'),
  'misses': const .optional(.string, 'What happens after a miss.'),
  'rules': .required(.mapOf(.unknown('a growth rule, as its `kind` spells it')), 'By the exercise they grow.'),
  'deload': .optional(.unknown('its lighter weeks')),
  'phases': .optional(.list(_programPhase)),
  'tests': .optional(.mapOf(.unknown('a test session\'s rule')), 'Test sessions, by name.'),
  'sessions': .required(.list(_programSession)),
  'research': .required(.list(_claim)),
  'sources': .required(.mapOf(_source), 'What the research cites, by key.'),
  'safety': .required(.list(.string)),
  'next': .required(.list(_nextProgram), 'Programs to move on to.'),
  'exercises': .required(.mapOf(.string), 'What each exercise key is called in your library.'),
}, open: true);

final Shape<Object?> _programPhase = .described('LibraryProgramPhase', {
  'name': const .optional(.string),
  'sessions': .required(.list(.string)),
  'cycles': const .optional(.integer),
});

final Shape<Object?> _programSession = .described('LibraryProgramSession', {
  'name': .required(.nullable(.string)),
  'note': const .optional(.string),
  'exercises': .required(.list(_sessionExercise)),
});

final Shape<Object?> _sessionExercise = .described('LibraryProgramExercise', {
  'exercise': const .optional(.string, 'The exercise\'s library key, unless the slot is open.'),
  'name': const .optional(.string),
  'rest': const .optional(.integer, 'Seconds.'),
  'superset': const .optional(.integer),
  'pattern': const .optional(.string, 'An open slot: any exercise of this movement pattern.'),
  'totalReps': .optional(.unknown('reps to reach across the sets')),
  'rule': .optional(.unknown('its growth rule')),
  'sets': .required(.list(_sessionSet)),
}, open: true);

final Shape<Object?> _sessionSet = .described('LibraryProgramSet', {
  'setType': const .optional(.string, 'Left out for a normal set.'),
  'target': .optional(.unknown('what the set aims for')),
});

/// A program's `research`: the claims behind it on the parts of your copy they
/// explain, and their sources.
final Shape<Object?> programResearchShape = .described('ProgramResearch', {
  'key': const .required(.string),
  'claims': .required(.list(_claim)),
  'sources': .required(.mapOf(_source)),
});

final Shape<Object?> _claim = .described('ResearchClaim', {
  'text': const .optional(.string),
  'sources': .required(.list(.string), 'Keys of `sources`.'),
  'about': .required(.list(.unknown('the part of the program it explains, by `on`'))),
});

final Shape<Object?> _source = .described('ResearchSource', {
  'title': const .optional(.string),
  'who': const .optional(.string),
  'year': const .optional(.integer),
  'url': const .optional(.string),
  'finding': const .optional(.string, 'What it found, in plain words.'),
});

final Shape<Object?> _nextProgram = .described('LibraryProgramNext', {
  'key': const .required(.string),
  'name': const .required(.string),
});
