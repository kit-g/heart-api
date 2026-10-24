part of '../widgets.dart';

/// `create_template`'s and `update_template`'s card: the template as the app's
/// template card lays it out (title, folder, note, hairline, each exercise with
/// its sets), under a line saying whether it is a preview, created or replaced.
const _templateHtml =
    '$_head<title>Heart template</title><style>$_baseCss$_templateCss</style></head>'
    '<body><main id="root" aria-live="polite"></main><script>$_kitJs$_templateJs$_bridgeJs</script></body></html>';

const _templateCss = r'''
.status { display: inline-block; font-size: 10px; letter-spacing: 1.5px; text-transform: uppercase;
  color: var(--accent-ink); border: 1px solid var(--accent-ink); border-radius: 8px; padding: 1px 6px; margin-bottom: 8px; }
.status.preview { color: var(--muted); border-color: var(--border); background: var(--fill); }
.quote { border-left: 2px solid var(--border); padding-left: 10px; }
.exercise + .exercise { margin-top: 12px; }
.exercise .name { font-weight: 600; }
.exercise .sets { margin-top: 4px; }
.exercise .tag { display: inline-block; width: 1.6em; color: var(--muted); font-variant-numeric: tabular-nums; }
.exercise .aim { color: var(--muted); }
''';

/// The status line first, so a preview never reads as saved. Targets read as
/// the app writes them ("6–10 reps", "8+ reps"); a set's own values are what
/// the app fills in when the session starts.
const _templateJs = r'''
var setTags = { warmup: 'W', drop: 'D', failure: 'F' };
var statuses = {
  preview: 'Preview · not saved yet',
  created: 'Saved to Heart',
  updated: 'Replaced in Heart'
};
var measures = [
  ['reps', function (n) { return num(n, 0); }, function () { return ' reps'; }],
  ['weightKg', function (n) { return num(ctx.imperial ? n * 2.20462262 : n); }, function () { return ctx.imperial ? ' lb' : ' kg'; }],
  ['distanceKm', function (n) { return num(ctx.imperial ? n * 0.621371192 : n, 2); }, function () { return ctx.imperial ? ' mi' : ' km'; }],
  ['seconds', function (n) { return clock(n); }, function () { return ''; }]
];
function range(r, format, unit) {
  if (!r || !isNum(r.min)) return null;
  if (!isNum(r.max)) return format(r.min) + '+' + unit;
  if (r.max === r.min) return format(r.min) + unit;
  return (r.amrap ? 'up to ' + format(r.max) : format(r.min) + '–' + format(r.max)) + unit;
}
function aim(target) {
  if (!target || typeof target !== 'object') return '';
  var parts = [];
  measures.forEach(function (m) { var text = range(target[m[0]], m[1], m[2]()); if (text) parts.push(text); });
  if (isNum(target.rir)) parts.push(num(target.rir) + ' in reserve');
  return parts.join(' · ');
}
function render(root, data) {
  var t = data.template || {};
  var text = t.quoted && typeof t.quoted === 'object' ? t.quoted : t;
  var card = el('section', 'card');
  var status = statuses[data.status];
  if (status) card.append(el('div', 'status' + (data.status === 'preview' ? ' preview' : ''), status));
  var body = card;
  if (t.quoted) {
    card.append(el('div', 'muted', 'From ' + (text.by || 'another account')));
    body = el('div', 'quote');
    card.append(body);
  }
  body.append(el('h1', 'title', text.name || 'Untitled'));
  var exercises = Array.isArray(text.exercises) ? text.exercises : [];
  var meta = [];
  if (t.folder && t.folder.name) meta.push(t.folder.name);
  meta.push(exercises.length === 1 ? '1 exercise' : exercises.length + ' exercises');
  body.append(el('div', 'muted', meta.join(' · ')));
  if (text.note) body.append(el('p', 'note', text.note));
  if (exercises.length) body.append(el('div', 'rule'));

  exercises.forEach(function (x) {
    var sets = Array.isArray(x.sets) ? x.sets : [];
    var block = el('div', 'exercise');
    var head = el('div', 'row');
    var label = (isNum(x.superset) ? 'Superset ' + x.superset + ' · ' : '') + (x.name || 'Exercise');
    head.append(el('span', 'name', label), el('span', 'muted', sets.length === 1 ? '1 set' : sets.length + ' sets'));
    block.append(head);
    if (isNum(x.rest)) block.append(el('div', 'faint', clock(x.rest) + ' rest'));
    var list = el('div', 'sets');
    var n = 0;
    sets.forEach(function (s) {
      var row = el('div', 'row');
      var left = el('span');
      left.append(el('span', 'tag', setTags[s.type] || String(++n)));
      var goal = aim(s.target);
      if (goal) left.append(el('span', 'aim', goal));
      var filled = setText(s);
      row.append(left, el('span', '', filled === '—' && goal ? '' : filled));
      list.append(row);
    });
    block.append(list);
    body.append(block);
  });
  root.append(card);
}
''';
