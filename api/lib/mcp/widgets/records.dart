part of '../widgets.dart';

/// `get_personal_records`' list: per exercise, each record with the date it
/// was set and what it beat.
const _recordsHtml =
    '$_head<title>Heart personal records</title><style>$_baseCss$_recordsCss</style></head>'
    '<body><main id="root" aria-live="polite"></main><script>$_kitJs$_recordsJs$_bridgeJs</script></body></html>';

const _recordsCss = r'''
.record { display: grid; grid-template-columns: 1fr auto; column-gap: 12px; }
.record + .record { margin-top: 6px; }
.record .what { color: var(--muted); }
.record .best { font-weight: 600; color: var(--accent-ink); font-variant-numeric: tabular-nums; text-align: right; }
.record .when { grid-column: 1 / -1; color: var(--faint); font-size: 12px; }
''';

/// The headline records in the order the app lists them, each formatted
/// from its own fields; `repMaxes` and the totals follow.
const _recordsJs = r'''
var recordKinds = [
  ['heaviest', 'Heaviest', function (r) { return setText(r); }],
  ['oneRepMax', 'Estimated 1RM', function (r) { return weight(r.value); }, function (r) { return setText(r); }],
  ['bestVolume', 'Best set volume', function (r) { return weight(r.value, 0); }, function (r) { return setText(r); }],
  ['mostReps', 'Most reps', function (r) { return r.reps + ' reps' + (isNum(r.weightKg) ? ' · ' + weight(r.weightKg) : ''); }],
  ['lightestAssistance', 'Lightest assistance', function (r) { return setText(r); }],
  ['longestDistance', 'Longest distance', function (r) { return distance(r.distanceKm); }, function (r) {
    return [isNum(r.weightKg) ? weight(r.weightKg) : '', isNum(r.seconds) ? clock(r.seconds) : ''].filter(Boolean).join(' · ');
  }],
  ['longestDuration', 'Longest', function (r) { return clock(r.seconds); }],
  ['bestPace', 'Best pace', function (r) { return pace(r.pace); }, function (r) { return setText(r); }]
];
function record(card, label, best, set, when, was) {
  var row = el('div', 'record');
  row.append(el('span', 'what', label), el('span', 'best', best));
  var line = when ? shortDate(when) : '';
  if (set) line += (line ? ' · ' : '') + set;
  if (was) line += (line ? ' · ' : '') + 'was ' + was;
  if (line) row.append(el('span', 'when', line));
  card.append(row);
}
function render(root, data) {
  var list = Array.isArray(data.records) ? data.records : [];
  if (!list.length) { root.append(el('p', 'note', 'No records yet.')); return; }
  list.forEach(function (entry) {
    var exercise = entry.exercise || {};
    var card = el('section', 'card');
    card.append(el('h1', 'title', exercise.name || 'Exercise'));
    var meta = [];
    if (isNum(entry.sessions)) meta.push(entry.sessions === 1 ? '1 session' : entry.sessions + ' sessions');
    if (entry.lastTrained) meta.push('last trained ' + shortDate(entry.lastTrained));
    if (meta.length) card.append(el('div', 'muted', meta.join(' · ')));
    card.append(el('div', 'rule'));
    recordKinds.forEach(function (kind) {
      var r = entry[kind[0]];
      if (!r || typeof r !== 'object') return;
      var best = kind[2](r), set = kind[3] ? kind[3](r) : null;
      var was = r.previous && typeof r.previous === 'object' ? kind[2](r.previous) : null;
      record(card, kind[1], best, set, r.at, was);
    });
    if (Array.isArray(entry.repMaxes)) {
      entry.repMaxes.forEach(function (r) {
        if (isNum(r.reps) && isNum(r.weightKg)) record(card, r.reps + '-rep max', weight(r.weightKg), null, r.at, null);
      });
    }
    var totals = [];
    if (isNum(entry.totalVolume)) totals.push(weight(entry.totalVolume, 0) + ' volume');
    if (isNum(entry.totalReps)) totals.push(num(entry.totalReps, 0) + ' reps');
    if (isNum(entry.totalDistance)) totals.push(distance(entry.totalDistance));
    if (isNum(entry.totalDuration)) totals.push(span(entry.totalDuration));
    if (totals.length) card.append(el('p', 'note', 'In all: ' + totals.join(' · ')));
    root.append(card);
  });
  if (data.cursor) root.append(el('p', 'note', 'More exercises follow on the next page.'));
  warnings(root, data.warnings);
}
''';
