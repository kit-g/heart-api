part of '../widgets.dart';

/// `get_exercise_history`'s chart: the app's progress chart for one exercise,
/// a point per session oldest to newest, one metric at a time.
const _progressHtml =
    '$_head<title>Heart exercise progress</title><style>$_baseCss$_progressCss</style></head>'
    '<body><main id="root" aria-live="polite"></main><script>$_kitJs$_progressJs$_bridgeJs</script></body></html>';

const _progressCss = r'''
.chips { display: flex; flex-wrap: wrap; gap: 6px; margin-top: 12px; }
.chip {
  font: inherit; font-size: 12px; padding: 4px 10px; border-radius: 8px; cursor: pointer;
  border: 1px solid var(--border); background: var(--surface); color: var(--ink);
}
.chip[aria-pressed="true"] { background: var(--accent); border-color: var(--accent); color: var(--on-accent); }
svg { display: block; width: 100%; height: auto; margin-top: 12px; overflow: visible; }
svg text { font-family: var(--font-text); font-size: 11px; fill: var(--muted); }
svg .grid { stroke: var(--border); stroke-width: 1; }
svg .line { fill: none; stroke: var(--accent-ink); stroke-width: 2; stroke-linejoin: round; }
svg .dot { fill: var(--surface); stroke: var(--accent-ink); stroke-width: 2; }
''';

/// The metrics are the ones `toSessionMetrics` names, in the order a
/// session lists them; one this page doesn't know shows under its own key.
const _progressJs = r'''
function count(n) { return num(n, 0); }
function pace(n) { return clock(n) + ' /km'; }
var metricNames = {
  topSetWeight: ['Top set', kg],
  estimatedOneRepMax: ['Estimated 1RM', kg],
  totalVolume: ['Volume', function (n) { return kg(Math.round(n)); }],
  averageWorkingWeight: ['Average working weight', kg],
  assistanceWeight: ['Assistance', kg],
  totalReps: ['Total reps', count],
  maxConsecutiveReps: ['Most reps in a set', count],
  cardioDistance: ['Distance', km],
  cardioDuration: ['Duration', clock],
  totalTimeUnderTension: ['Time under tension', clock],
  averagePace: ['Pace', pace]
};
function metricOf(key) { return metricNames[key] || [key, function (n) { return num(n, 2); }]; }
var chosen = null;
function render(root, h) {
  var sessions = (Array.isArray(h.sessions) ? h.sessions : []).slice().reverse();
  var exercise = h.exercise || {};
  var card = el('section', 'card');
  card.append(el('h1', 'title', exercise.name || 'Exercise'));
  if (!sessions.length) {
    card.append(el('p', 'note', 'No sessions in this span.'));
    root.append(card);
    return;
  }
  var keys = [];
  h.sessions.forEach(function (s) {
    Object.keys(s.metrics || {}).forEach(function (k) { if (keys.indexOf(k) < 0 && isNum(s.metrics[k])) keys.push(k); });
  });
  if (keys.indexOf(chosen) < 0) chosen = keys[0];
  card.append(el('div', 'muted', sessions.length === 1 ? '1 session' : sessions.length + ' sessions'));

  if (keys.length > 1) {
    var chips = el('div', 'chips');
    keys.forEach(function (k) {
      var b = el('button', 'chip', metricOf(k)[0]);
      b.type = 'button';
      b.setAttribute('aria-pressed', String(k === chosen));
      b.addEventListener('click', function () { chosen = k; root.replaceChildren(); render(root, h); });
      chips.append(b);
    });
    card.append(chips);
  }
  if (!chosen) { root.append(card); return; }

  var name = metricOf(chosen)[0], format = metricOf(chosen)[1];
  var points = sessions.filter(function (s) { return s.metrics && isNum(s.metrics[chosen]); });
  card.append(chart(points, name, format));
  var first = points[0], latest = points[points.length - 1];
  var a = first.metrics[chosen], b = latest.metrics[chosen];
  var trend = b > a ? 'up from ' + format(a) : b < a ? 'down from ' + format(a) : 'level';
  card.append(el('p', 'note', points.length > 1
    ? name + ', ' + shortDate(first.at) + ' to ' + shortDate(latest.at) + ': ' + format(b) + ', ' + trend + '.'
    : name + ', ' + shortDate(latest.at) + ': ' + format(b) + '.'));
  if (h.cursor) card.append(el('p', 'note', 'There are older sessions than these.'));
  warnings(card, h.warnings);

  card.append(el('div', 'rule'));
  points.slice().reverse().forEach(function (s) {
    var row = el('div', 'row');
    row.append(el('span', 'muted', shortDate(s.at)), el('span', '', format(s.metrics[chosen])));
    card.append(row);
  });
  root.append(card);
}
var svgNs = 'http://www.w3.org/2000/svg';
function svg(tag, attrs, text) {
  var e = document.createElementNS(svgNs, tag);
  Object.keys(attrs).forEach(function (k) { e.setAttribute(k, attrs[k]); });
  if (text !== undefined) e.textContent = text;
  return e;
}
function chart(points, name, format) {
  var W = 600, H = 220, left = 64, right = 12, top = 10, bottom = 24;
  var values = points.map(function (p) { return p.metrics[chosen]; });
  var lo = Math.min.apply(null, values), hi = Math.max.apply(null, values);
  var padding = (hi - lo) * 0.1 || Math.abs(hi) * 0.1 || 1;
  lo -= padding; hi += padding;
  if (Math.min.apply(null, values) >= 0 && lo < 0) lo = 0;
  function x(i) { return points.length === 1 ? (left + W - right) / 2 : left + i * (W - left - right) / (points.length - 1); }
  function y(v) { return top + (hi - v) * (H - top - bottom) / (hi - lo); }
  var root = svg('svg', { viewBox: '0 0 ' + W + ' ' + H, role: 'img', 'aria-label': name + ' per session' });
  for (var g = 0; g <= 3; g++) {
    var v = lo + (hi - lo) * g / 3;
    root.append(svg('line', { class: 'grid', x1: left, x2: W - right, y1: y(v), y2: y(v) }));
    root.append(svg('text', { x: left - 8, y: y(v) + 4, 'text-anchor': 'end' }, format(v)));
  }
  // one label per day, thinned to about six, as the app's axis does
  var firstOfDay = [], previous = null;
  points.forEach(function (p, i) {
    var day = date(p.at, { day: 'numeric', month: 'short' });
    if (day !== previous) firstOfDay.push(i);
    previous = day;
  });
  var every = Math.max(1, Math.ceil(firstOfDay.length / 6));
  firstOfDay.forEach(function (i, nth) {
    if (nth % every) return;
    root.append(svg('text', { x: x(i), y: H - 6, 'text-anchor': 'middle' }, date(points[i].at, { day: 'numeric', month: 'short' })));
  });
  if (points.length > 1) {
    root.append(svg('polyline', { class: 'line', points: points.map(function (p, i) { return x(i) + ',' + y(p.metrics[chosen]); }).join(' ') }));
  }
  points.forEach(function (p, i) {
    var dot = svg('circle', { class: 'dot', cx: x(i), cy: y(p.metrics[chosen]), r: 4 });
    dot.append(svg('title', {}, shortDate(p.at) + ': ' + format(p.metrics[chosen])));
    root.append(dot);
  });
  return root;
}
''';
