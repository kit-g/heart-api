import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

import 'format.dart';
import 'kit.dart';
import 'units.dart';

/// `create_template`'s and `update_template`'s card: the template as the
/// app's template card lays it out (title, folder, note, hairline, each
/// exercise with its sets), under a line saying whether it is a preview,
/// created or replaced.
///
/// The status line comes first, so a preview never reads as saved. Targets
/// read as the app writes them ("6–10 reps", "8+ reps"); a set's own values
/// are what the app fills in when the session starts. Weights and distances
/// show in the user's units (`unitSystem`).
class TemplateCard extends StatelessComponent {
  const new(this.result, this.format, {super.key});

  final Map<String, Object?> result;
  final Format format;

  Units get _units => Units.of(result['unitSystem']);

  static const _setTags = {'warmup': 'W', 'drop': 'D', 'failure': 'F'};

  static const _statuses = {
    'preview': 'Preview · not saved yet',
    'created': 'Saved to Heart',
    'updated': 'Replaced in Heart',
  };

  @override
  Component build(BuildContext context) {
    final template = result.object('template') ?? const {};
    final quoted = template.object('quoted');
    final text = quoted ?? template;
    final exercises = text.maps('exercises');
    final status = result.text('status');
    final meta = [
      ?template.object('folder')?.text('name'),
      plural(exercises.length, 'exercise'),
    ];
    final body = [
      h1(classes: 'title', [.text(text.text('name') ?? 'Untitled')]),
      div(classes: 'muted', [.text(meta.join(' · '))]),
      if (text.text('note') case final note?) p(classes: 'note', [.text(note)]),
      if (exercises.isNotEmpty) const div(classes: 'rule', []),
      for (final exercise in exercises) _exercise(exercise),
    ];
    return section(classes: 'card', [
      if (_statuses[status] case final label?)
        div(classes: status == 'preview' ? 'status preview' : 'status', [.text(label)]),
      if (quoted != null) ...[
        div(classes: 'muted', [.text('From ${quoted.text('by') ?? 'another account'}')]),
        div(classes: 'quote', body),
      ] else
        ...body,
    ]);
  }

  Component _exercise(Map<String, Object?> exercise) {
    final sets = exercise.sets;
    final label = [
      if (exercise.number('superset') case final superset?) 'Superset $superset',
      exercise.text('name') ?? 'Exercise',
    ].join(' · ');
    var n = 0;
    return div(classes: 'exercise', [
      div(classes: 'row', [
        span(classes: 'name', [.text(label)]),
        span(classes: 'muted', [.text(plural(sets.length, 'set'))]),
      ]),
      if (exercise.number('rest') case final rest?) div(classes: 'faint', [.text('${rest.toClock()} rest')]),
      div(classes: 'sets', [
        for (final set in sets)
          if ((_aim(set.object('target')), set.toSetText(format, _units)) case (final aim, final filled))
            div(classes: 'row', [
              span([
                span(classes: 'tag', [.text(_setTags[set['type']] ?? '${++n}')]),
                if (aim.isNotEmpty) span(classes: 'aim', [.text(aim)]),
              ]),
              span([.text(filled == '—' && aim.isNotEmpty ? '' : filled)]),
            ]),
      ]),
    ]);
  }

  /// A set's target as the app writes it: each measure's range, then reps in
  /// reserve.
  String _aim(Map<String, Object?>? target) {
    if (target == null) return '';
    return [
      ?_range(target.object('reps'), (n) => format.number(n, 0), ' reps'),
      ?_range(target.object('weightKg'), (n) => format.number(_units.fromKg(n)), ' ${_units.weight}'),
      ?_range(target.object('distanceKm'), (n) => format.number(_units.fromKm(n), 2), ' ${_units.distance}'),
      ?_range(target.object('seconds'), (n) => n.toClock(), ''),
      if (target.number('rir') case final rir?) '${format.number(rir)} in reserve',
    ].join(' · ');
  }

  /// `8+ reps` (open top), `8 reps` (exact), `up to 10 reps` (capped as many
  /// as possible), `6–10 reps`.
  static String? _range(Map<String, Object?>? range, String Function(num) format, String unit) {
    final min = range?.number('min');
    if (range == null || min == null) return null;
    return switch (range.number('max')) {
      null => '${format(min)}+$unit',
      final max when max == min => '${format(min)}$unit',
      final max when range['amrap'] == true => 'up to ${format(max)}$unit',
      final max => '${format(min)}–${format(max)}$unit',
    };
  }
}
