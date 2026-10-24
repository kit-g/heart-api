import 'dart:math';

import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

import 'format.dart';
import 'kit.dart';
import 'units.dart';

/// `get_exercise_history`'s card: the app's progress chart for one exercise,
/// a point per session oldest to newest, one metric at a time, with chips to
/// switch between the metrics the sessions have.
///
/// The metrics are the ones `toSessionMetrics` names, in the order a session
/// lists them; one this card doesn't know shows under its own key. Weights,
/// distances and paces show in the user's units (`unitSystem`).
class ProgressCard extends StatefulComponent {
  const new(this.history, this.format, {super.key});

  final Map<String, Object?> history;
  final Format format;

  @override
  State<ProgressCard> createState() => _ProgressCardState();
}

typedef _Metric = ({String name, String Function(Format format, Units units, num n) show});

class _ProgressCardState extends State<ProgressCard> {
  String? _chosen;

  static final _metrics = <String, _Metric>{
    'topSetWeight': (name: 'Top set', show: (f, units, n) => f.weight(n, units)),
    'estimatedOneRepMax': (name: 'Estimated 1RM', show: (f, units, n) => f.weight(n, units)),
    'totalVolume': (name: 'Volume', show: (f, units, n) => f.weight(n, units, 0)),
    'averageWorkingWeight': (name: 'Average working weight', show: (f, units, n) => f.weight(n, units)),
    'assistanceWeight': (name: 'Assistance', show: (f, units, n) => f.weight(n, units)),
    'totalReps': (name: 'Total reps', show: (f, _, n) => f.number(n, 0)),
    'maxConsecutiveReps': (name: 'Most reps in a set', show: (f, _, n) => f.number(n, 0)),
    'cardioDistance': (name: 'Distance', show: (f, units, n) => f.distance(n, units)),
    'cardioDuration': (name: 'Duration', show: (_, _, n) => n.toClock()),
    'totalTimeUnderTension': (name: 'Time under tension', show: (_, _, n) => n.toClock()),
    'averagePace': (name: 'Pace', show: (f, units, n) => f.pace(n, units)),
  };

  static _Metric _metricOf(String key) => _metrics[key] ?? (name: key, show: (f, _, n) => f.number(n, 2));

  @override
  Component build(BuildContext context) {
    final history = component.history, format = component.format;
    final newestFirst = history.maps('sessions');
    final sessions = newestFirst.reversed.toList();
    final title = h1(classes: 'title', [.text(history.object('exercise')?.text('name') ?? 'Exercise')]);
    if (sessions.isEmpty) {
      return section(classes: 'card', [
        title,
        const p(classes: 'note', [.text('No sessions in this span.')]),
      ]);
    }

    final keys = <String>[];
    for (final session in newestFirst) {
      for (final MapEntry(:key, :value) in (session.object('metrics') ?? const {}).entries) {
        if (value is num && value.isFinite && !keys.contains(key)) keys.add(key);
      }
    }
    final chosen = keys.contains(_chosen) ? _chosen! : keys.firstOrNull;

    return section(classes: 'card', [
      title,
      div(classes: 'muted', [.text(plural(sessions.length, 'session'))]),
      if (keys.length > 1)
        div(classes: 'chips', [
          for (final key in keys)
            button(
              classes: 'chip',
              type: .button,
              attributes: {'aria-pressed': '${key == chosen}'},
              onClick: () => setState(() => _chosen = key),
              [.text(_metricOf(key).name)],
            ),
        ]),
      if (chosen != null) ..._metric(chosen, sessions, format),
    ]);
  }

  List<Component> _metric(String key, List<Map<String, Object?>> sessions, Format format) {
    final (:name, :show) = _metricOf(key);
    final units = Units.of(component.history['unitSystem']);
    String shown(num n) => show(format, units, n);
    final points = [
      for (final session in sessions)
        if ((session.text('at'), session.object('metrics')?.number(key)) case (final at?, final value?))
          (at: at, value: value),
    ];
    if (points.isEmpty) return const [];
    final (first, latest) = (points.first, points.last);
    final trend = switch (latest.value.compareTo(first.value)) {
      > 0 => 'up from ${shown(first.value)}',
      < 0 => 'down from ${shown(first.value)}',
      _ => 'level',
    };
    return [
      _Chart(points: points, label: '$name per session', show: shown, format: format),
      p(classes: 'note', [
        .text(
          points.length > 1
              ? '$name, ${format.date(first.at)} to ${format.date(latest.at)}: ${shown(latest.value)}, $trend.'
              : '$name, ${format.date(latest.at)}: ${shown(latest.value)}.',
        ),
      ]),
      if (component.history['cursor'] != null)
        const p(classes: 'note', [.text('There are older sessions than these.')]),
      ?warningsOf(component.history['warnings']),
      const div(classes: 'rule', []),
      for (final point in points.reversed)
        div(classes: 'row', [
          span(classes: 'muted', [.text(format.date(point.at))]),
          span([.text(shown(point.value))]),
        ]),
    ];
  }
}

typedef _Point = ({String at, num value});

/// The chart: four gridlines labelled with their values, a day label per
/// day thinned to about six as the app's axis does, the line, and a dot per
/// session whose tooltip names it.
class _Chart extends StatelessComponent {
  const new({required this.points, required this.label, required this.show, required this.format});

  final List<_Point> points;
  final String label;
  final String Function(num n) show;
  final Format format;

  static const _width = 600.0, _height = 220.0;
  static const _left = 64.0, _right = 12.0, _top = 10.0, _bottom = 24.0;

  @override
  Component build(BuildContext context) {
    final values = points.map((point) => point.value);
    final (low, high) = (values.reduce(min), values.reduce(max));
    // a tenth of the spread above and below; a flat line gets a tenth of its
    // value, and a flat zero one unit
    final padding = high != low ? (high - low) * 0.1 : (high != 0 ? high.abs() * 0.1 : 1);
    final top = high + padding;
    // never below zero for values that never are
    final bottom = low >= 0 && low - padding < 0 ? 0 : low - padding;

    double x(int i) {
      return points.length == 1
          ? (_left + _width - _right) / 2
          : _left + i * (_width - _left - _right) / (points.length - 1);
    }

    double y(num v) => _top + (top - v) * (_height - _top - _bottom) / (top - bottom);

    final days = <int>[];
    String? previous;
    for (final (i, point) in points.indexed) {
      final day = format.dayMonth(point.at);
      if (day != previous) days.add(i);
      previous = day;
    }
    final every = max(1, (days.length / 6).ceil());

    return svg(
      viewBox: '0 0 ${_width.toInt()} ${_height.toInt()}',
      attributes: {'role': 'img', 'aria-label': label},
      [
        for (var g = 0; g <= 3; g++)
          if (bottom + (top - bottom) * g / 3 case final v) ...[
            line(classes: 'grid', x1: _n(_left), x2: _n(_width - _right), y1: _n(y(v)), y2: _n(y(v)), []),
            _text(show(v), x: _left - 8, y: y(v) + 4, anchor: 'end'),
          ],
        for (final (nth, i) in days.indexed)
          if (nth % every == 0) _text(format.dayMonth(points[i].at), x: x(i), y: _height - 6, anchor: 'middle'),
        if (points.length > 1)
          polyline(
            classes: 'line',
            points: [for (final (i, point) in points.indexed) '${_n(x(i))},${_n(y(point.value))}'].join(' '),
            [],
          ),
        for (final (i, point) in points.indexed)
          circle(classes: 'dot', cx: _n(x(i)), cy: _n(y(point.value)), r: '4', [
            Component.element(tag: 'title', children: [.text('${format.date(point.at)}: ${show(point.value)}')]),
          ]),
      ],
    );
  }

  static Component _text(String text, {required double x, required double y, required String anchor}) {
    return Component.element(
      tag: 'text',
      attributes: {'x': _n(x), 'y': _n(y), 'text-anchor': anchor},
      children: [.text(text)],
    );
  }

  /// A coordinate to a tenth of a unit: plenty at this size, and a smaller page.
  static String _n(num n) => n.toStringAsFixed(1);
}
