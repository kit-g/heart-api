part of '../widgets.dart';

/// `get_workout`'s card: the design system's workout card (title, date, hero
/// stats, hairline, roster), with every set under its exercise.
const _workoutHtml =
    '$_head<title>Heart workout</title><style>$_baseCss$_workoutCss</style></head>'
    '<body><main id="root" aria-live="polite"></main><script>$_kitJs$_workoutJs$_bridgeJs</script></body></html>';

const _workoutCss = r'''
.exercise + .exercise { margin-top: 12px; }
.exercise .name { font-weight: 600; }
.exercise .sets { margin-top: 4px; }
.exercise .tag { display: inline-block; width: 1.6em; color: var(--muted); font-variant-numeric: tabular-nums; }
.exercise .undone { color: var(--faint); }
.exercise .exercise-note { color: var(--muted); font-style: italic; margin-top: 2px; }
''';

/// Volume counts done working sets, as the app's does: warm-ups and sets not
/// done are left out, and so is assisted work, whose weight is help, not load.
/// Calories are the MET estimate and say so wherever they show.
const _workoutJs = r'''
var setTags = { warmup: 'W', drop: 'D', failure: 'F' };
function render(root, w) {
  var card = el('section', 'card');
  card.append(el('h1', 'title', w.name || 'Workout'));
  if (w.start) {
    card.append(el('div', 'muted', date(w.start, {
      weekday: 'long', day: 'numeric', month: 'short', year: 'numeric', hour: 'numeric', minute: '2-digit'
    })));
  }
  var exercises = Array.isArray(w.exercises) ? w.exercises : [];
  var volume = 0, distance = 0;
  exercises.forEach(function (x) {
    (Array.isArray(x.sets) ? x.sets : []).forEach(function (s) {
      if (s.type === 'warmup' || s.completed === false) return;
      if (isNum(s.weightKg) && isNum(s.reps) && x.category !== 'Assisted Body Weight') volume += s.weightKg * s.reps;
      if (isNum(s.distanceKm)) distance += s.distanceKm;
    });
  });

  var stats = el('div', 'stats');
  function stat(value, label, hint) {
    var s = el('div', 'stat');
    s.append(el('div', 'value', value), el('div', 'label', label));
    if (hint) s.title = hint;
    stats.append(s);
  }
  if (w.start && w.end) {
    var seconds = (new Date(w.end) - new Date(w.start)) / 1000;
    if (seconds >= 0) stat(span(seconds), 'Duration');
  }
  if (volume > 0) stat(kg(Math.round(volume)), 'Total volume');
  if (distance > 0) stat(km(distance), 'Distance');
  if (isNum(w.caloriesEstimate)) {
    stat(num(w.caloriesEstimate, 0) + ' kcal', 'Calories, estimated', 'An estimate from the exercises, not a measurement.');
  }
  if (stats.childNodes.length) card.append(stats);
  if (w.note) card.append(el('p', 'note', w.note));
  if (exercises.length) card.append(el('div', 'rule'));

  exercises.forEach(function (x) {
    var sets = Array.isArray(x.sets) ? x.sets : [];
    var block = el('div', 'exercise');
    var head = el('div', 'row');
    head.append(el('span', 'name', x.name || 'Exercise'), el('span', 'muted', sets.length === 1 ? '1 set' : sets.length + ' sets'));
    block.append(head);
    if (x.note) block.append(el('div', 'exercise-note', x.note));
    var list = el('div', 'sets');
    var n = 0;
    sets.forEach(function (s) {
      var row = el('div', 'row' + (s.completed === false ? ' undone' : ''));
      var left = el('span');
      left.append(el('span', 'tag', setTags[s.type] || String(++n)));
      if (s.completed === false) left.append(document.createTextNode('not done'));
      var right = setText(s);
      if (isNum(s.rpe)) right += ' · RPE ' + num(s.rpe);
      row.append(left, el('span', '', right));
      list.append(row);
    });
    block.append(list);
    card.append(block);
  });
  root.append(card);
}
''';
