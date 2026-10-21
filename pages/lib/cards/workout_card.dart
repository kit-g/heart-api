import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

import 'format.dart';
import 'kit.dart';
import 'units.dart';

/// `get_workout`'s card: the design system's workout card, which the app's
/// done screen ends on (title, date, hero stats, hairline, then every set
/// under its exercise).
///
/// No browser imports, so the same component draws the MCP Apps view in the
/// browser and can render a share page on a server. The [workout] is the
/// tool's `structuredContent`, read tolerantly: a missing or unexpected field
/// leaves its line out rather than failing the card.
///
/// Volume counts done working sets, as the app's does: warm-ups and sets not
/// done are left out, and so is assisted work, whose weight is help, not load.
/// Calories are the MET estimate and say so wherever they show. Weights and
/// distances show in the user's units (`unitSystem` on the result).
///
/// Sets in a row that read the same collapse into one line ("1–3  59 kg ×
/// 14"), and exercises flow into columns when the frame is wide enough, so a
/// long session stays short.
class WorkoutCard extends StatelessComponent {
  const new(this.workout, this.format, {super.key});

  final Map<String, Object?> workout;
  final Format format;

  @override
  Component build(BuildContext context) {
    final units = Units.of(workout['unitSystem']);
    final exercises = [
      if (workout['exercises'] case final List exercises)
        for (final exercise in exercises)
          if (exercise case final Map<String, Object?> exercise) exercise,
    ];
    var volume = 0.0, distance = 0.0;
    for (final exercise in exercises) {
      for (final set in exercise.sets) {
        if (set['type'] == 'warmup' || set['completed'] == false) continue;
        if ((set['weightKg'], set['reps']) case (final num weight, final num reps)
            when exercise['category'] != 'Assisted Body Weight') {
          volume += weight * reps;
        }
        if (set['distanceKm'] case final num km) distance += km;
      }
    }

    final stats = [
      if ((workout['start'], workout['end']) case (final String start, final String end))
        if ((DateTime.tryParse(start), DateTime.tryParse(end)) case (final start?, final end?)
            when !end.isBefore(start))
          _stat(end.difference(start).inSeconds.toSpan(), 'Duration'),
      if (volume > 0) _stat(format.weight(volume, units, 0), 'Total volume'),
      if (distance > 0) _stat(format.distance(distance, units), 'Distance'),
      if (workout['caloriesEstimate'] case final num kcal)
        _stat(
          '${format.number(kcal, 0)} kcal',
          'Calories, estimated',
          hint: 'An estimate from the exercises, not a measurement.',
        ),
    ];

    return section(classes: 'card', [
      h1(classes: 'title', [.text(workout.text('name') ?? 'Workout')]),
      if (workout['start'] case final String start) div(classes: 'muted', [.text(format.dateTime(start))]),
      if (stats.isNotEmpty) div(classes: 'stats', stats),
      if (workout['note'] case final String note) p(classes: 'note', [.text(note)]),
      if (exercises.isNotEmpty) const div(classes: 'rule', []),
      if (exercises.isNotEmpty)
        div(classes: 'exercises', [for (final exercise in exercises) _exercise(exercise, units)]),
    ]);
  }

  Component _stat(String value, String label, {String? hint}) {
    return div(
      classes: 'stat',
      attributes: {'title': ?hint},
      [
        div(classes: 'value', [.text(value)]),
        div(classes: 'label', [.text(label)]),
      ],
    );
  }

  Component _exercise(Map<String, Object?> exercise, Units units) {
    final sets = exercise.sets;
    return div(classes: 'exercise', [
      div(classes: 'row', [
        span(classes: 'name', [.text(exercise.text('name') ?? 'Exercise')]),
        span(classes: 'muted', [.text(sets.length == 1 ? '1 set' : '${sets.length} sets')]),
      ]),
      if (exercise['note'] case final String note) div(classes: 'exercise-note', [.text(note)]),
      div(classes: 'sets', [
        for (final run in sets.toRuns(format, units))
          div(classes: run.done ? 'row' : 'row undone', [
            span([
              span(classes: 'tag', [.text(run.label)]),
              if (!run.done) const .text('not done'),
            ]),
            span([.text(run.text)]),
          ]),
      ]),
    ]);
  }
}

/// Sets in a row that read the same, drawn as one line: numbered `1–3` when
/// they are working sets, tagged `W ×2` when they share a type.
typedef _Run = ({String label, String text, bool done});

extension on List<Map<String, Object?>> {
  List<_Run> toRuns(Format format, Units units) {
    const tags = {'warmup': 'W', 'drop': 'D', 'failure': 'F'};
    final runs = <({String? tag, int first, int count, String text, bool done})>[];
    var n = 0;
    for (final set in this) {
      final tag = tags[set['type']];
      final text = set.toSetText(format, units);
      final done = set['completed'] != false;
      if (tag == null) n++;
      if (runs.lastOrNull case final last? when last.tag == tag && last.text == text && last.done == done) {
        runs.last = (tag: tag, first: last.first, count: last.count + 1, text: text, done: done);
      } else {
        runs.add((tag: tag, first: n, count: 1, text: text, done: done));
      }
    }
    return [
      for (final run in runs)
        (
          label: switch ((run.tag, run.count)) {
            (final String tag, 1) => tag,
            (final String tag, final count) => '$tag ×$count',
            (null, 1) => '${run.first}',
            (null, final count) => '${run.first}–${run.first + count - 1}',
          },
          text: run.text,
          done: run.done,
        ),
    ];
  }
}
