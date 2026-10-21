import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

import 'format.dart';

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
/// Calories are the MET estimate and say so wherever they show.
class WorkoutCard extends StatelessComponent {
  const new(this.workout, this.format, {super.key});

  final Map<String, Object?> workout;
  final Format format;

  static const _setTags = {'warmup': 'W', 'drop': 'D', 'failure': 'F'};

  @override
  Component build(BuildContext context) {
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
          _stat(end.difference(start).toSpan(), 'Duration'),
      if (volume > 0) _stat('${format.number(volume.round())} kg', 'Total volume'),
      if (distance > 0) _stat('${format.number(distance, 2)} km', 'Distance'),
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
      for (final exercise in exercises) _exercise(exercise),
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

  Component _exercise(Map<String, Object?> exercise) {
    final sets = exercise.sets;
    var n = 0;
    return div(classes: 'exercise', [
      div(classes: 'row', [
        span(classes: 'name', [.text(exercise.text('name') ?? 'Exercise')]),
        span(classes: 'muted', [.text(sets.length == 1 ? '1 set' : '${sets.length} sets')]),
      ]),
      if (exercise['note'] case final String note) div(classes: 'exercise-note', [.text(note)]),
      div(classes: 'sets', [
        for (final set in sets)
          div(classes: set['completed'] == false ? 'row undone' : 'row', [
            span([
              span(classes: 'tag', [.text(_setTags[set['type']] ?? '${++n}')]),
              if (set['completed'] == false) const .text('not done'),
            ]),
            span([.text(set.toSetText(format))]),
          ]),
      ]),
    ]);
  }
}

extension on Map<String, Object?> {
  String? text(String key) => switch (this[key]) {
    final String text => text,
    _ => null,
  };

  List<Map<String, Object?>> get sets => [
    if (this['sets'] case final List sets)
      for (final set in sets)
        if (set case final Map<String, Object?> set) set,
  ];

  /// `225 kg × 5 · RPE 8`, `8 reps`, `2 km · 8:00`, or a dash for a set with nothing in it.
  String toSetText(Format format) {
    final parts = [
      switch ((this['weightKg'], this['reps'])) {
        (final num weight, final num reps) => '${format.number(weight)} kg × $reps',
        (final num weight, _) => '${format.number(weight)} kg',
        (_, 1) => '1 rep',
        (_, final num reps) => '$reps reps',
        _ => null,
      },
      if (this['distanceKm'] case final num km) '${format.number(km, 2)} km',
      if (this['seconds'] case final num seconds) Duration(seconds: seconds.round()).toClock(),
    ].nonNulls;
    final text = parts.isEmpty ? '—' : parts.join(' · ');
    return switch (this['rpe']) {
      final num rpe => '$text · RPE ${format.number(rpe)}',
      _ => text,
    };
  }
}

extension on Duration {
  /// `1 h 24 m`, `52 m`, `40 s`.
  String toSpan() {
    if (inSeconds < 60) return '$inSeconds s';
    final minutes = (inSeconds / 60).round();
    return minutes >= 60 ? '${minutes ~/ 60} h ${minutes % 60} m' : '$minutes m';
  }

  /// `8:00`, `1:02:05`.
  String toClock() {
    String pad(int n) => n.toString().padLeft(2, '0');
    final hours = inHours, minutes = inMinutes % 60, seconds = inSeconds % 60;
    return hours > 0 ? '$hours:${pad(minutes)}:${pad(seconds)}' : '$minutes:${pad(seconds)}';
  }
}
