part of '../widgets.dart';

// What every widget page shares: the design system's tokens, the helpers
// that format a tool's units, and the MCP Apps bridge (ext-apps 2026-01-26).

/// The page's opening, up to its own styles.
const _head =
    '<!DOCTYPE html><html lang="en"><head><meta charset="utf-8">'
    '<meta name="viewport" content="width=device-width, initial-scale=1">';

/// The Ink preset of the Heart design system, as `site/assets/site.css` has
/// it: eleven tokens per brightness, no shadows, the accent a fill and
/// accent-ink for text and lines, 12px cards. The fonts are named but never
/// fetched; a host without them falls back to the system face.
///
/// The host's `theme` wins over the OS setting when it sends one.
const _baseCss = r'''
:root {
  --ground: #FFFFFF; --surface: #FFFFFF; --fill: #F4F1EA; --ink: #1A1815; --muted: #5D584E;
  --faint: #948F85; --border: #E2DED4; --accent: #1F4EC8; --on-accent: #FFFFFF; --accent-ink: #1B43A8;
  --destructive: #9E2B25;
  --font-text: 'IBM Plex Sans', system-ui, -apple-system, 'Segoe UI', sans-serif;
  --font-title: 'Literata', Georgia, serif;
  color-scheme: light;
}
@media (prefers-color-scheme: dark) {
  :root:not([data-theme="light"]) {
    --ground: #141311; --surface: #1E1C19; --fill: #2A2721; --ink: #F2F0EA; --muted: #A29D93;
    --faint: #6F6B63; --border: #302D27; --accent: #93ADFF; --on-accent: #0F1526; --accent-ink: #93ADFF;
    --destructive: #FF7A66;
    color-scheme: dark;
  }
}
:root[data-theme="dark"] {
  --ground: #141311; --surface: #1E1C19; --fill: #2A2721; --ink: #F2F0EA; --muted: #A29D93;
  --faint: #6F6B63; --border: #302D27; --accent: #93ADFF; --on-accent: #0F1526; --accent-ink: #93ADFF;
  --destructive: #FF7A66;
  color-scheme: dark;
}
* { box-sizing: border-box; }
html, body { margin: 0; }
body {
  background: var(--ground); color: var(--ink); font-family: var(--font-text);
  font-size: 13px; line-height: 1.4; padding: 2px;
}
.card {
  background: var(--surface); border: 1px solid var(--border); border-radius: 12px;
  padding: 14px 14px 14px 16px;
}
.card + .card { margin-top: 10px; }
.title { font-family: var(--font-title); font-size: 17px; font-weight: 600; margin: 0; }
.muted { color: var(--muted); }
.faint { color: var(--faint); }
.stats { display: flex; gap: 12px; margin-top: 14px; }
.stat { flex: 1; min-width: 0; }
.value {
  font-family: var(--font-title); font-size: 17px; font-weight: 700; color: var(--accent-ink);
  font-variant-numeric: tabular-nums;
}
.label { font-size: 10px; letter-spacing: 1.5px; color: var(--muted); text-transform: uppercase; }
.rule { height: 1px; background: var(--border); margin: 12px 0 8px; }
.row { display: flex; justify-content: space-between; gap: 12px; }
.row + .row { margin-top: 4px; }
.row > :last-child { font-variant-numeric: tabular-nums; text-align: right; }
.note { color: var(--muted); font-size: 12px; margin: 10px 0 0; }
.warn { color: var(--destructive); font-size: 12px; margin: 10px 0 0; }
''';

/// Formatting in the tools' units (kg, km, seconds), in the host's locale
/// and time zone once it has said them. Every string from a result goes
/// into the page as text, never as markup.
const _kitJs = r'''
var ctx = { locale: undefined, timeZone: undefined };
function el(tag, cls, text) {
  var e = document.createElement(tag);
  if (cls) e.className = cls;
  if (text !== undefined && text !== null) e.textContent = String(text);
  return e;
}
function isNum(n) { return typeof n === 'number' && isFinite(n); }
function num(n, digits) {
  try { return new Intl.NumberFormat(ctx.locale, { maximumFractionDigits: digits === undefined ? 1 : digits }).format(n); }
  catch (e) { return String(n); }
}
function kg(n) { return num(n) + ' kg'; }
function km(n) { return num(n, 2) + ' km'; }
function pad(n) { return n < 10 ? '0' + n : String(n); }
function clock(seconds) {
  var s = Math.round(seconds), h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60);
  return h ? h + ':' + pad(m) + ':' + pad(s % 60) : m + ':' + pad(s % 60);
}
function span(seconds) {
  if (seconds < 60) return Math.round(seconds) + ' s';
  var m = Math.round(seconds / 60), h = Math.floor(m / 60);
  return h ? h + ' h ' + (m % 60) + ' m' : m + ' m';
}
function date(iso, options) {
  var d = new Date(iso);
  if (isNaN(d.getTime())) return String(iso);
  try { return new Intl.DateTimeFormat(ctx.locale, Object.assign({ timeZone: ctx.timeZone }, options)).format(d); }
  catch (e) { return new Intl.DateTimeFormat(undefined, options).format(d); }
}
function shortDate(iso) { return date(iso, { day: 'numeric', month: 'short', year: 'numeric' }); }
function setText(set) {
  var parts = [];
  if (isNum(set.weightKg) && isNum(set.reps)) parts.push(kg(set.weightKg) + ' × ' + set.reps);
  else if (isNum(set.weightKg)) parts.push(kg(set.weightKg));
  else if (isNum(set.reps)) parts.push(set.reps + '×');
  if (isNum(set.distanceKm)) parts.push(km(set.distanceKm));
  if (isNum(set.seconds)) parts.push(clock(set.seconds));
  return parts.join(' · ') || '—';
}
function warnings(root, list) {
  if (!Array.isArray(list) || !list.length) return;
  root.append(el('p', 'warn', list.length === 1
    ? 'One entry here looks off and has not been checked yet.'
    : list.length + ' entries here look off and have not been checked yet.'));
}
''';

/// The view's side of the MCP Apps bridge, with no SDK: `ui/initialize`,
/// then `ui/notifications/initialized`; the host answers with its context
/// and later sends the tool result. Size changes go back up so the host can
/// fit the frame. ChatGPT's older `window.openai.toolOutput` is read too.
///
/// Each page defines `render(root, structuredContent)` before this runs.
const _bridgeJs = r'''
(function () {
  var nextId = 0, pending = {}, last = null;
  var root = document.getElementById('root');
  function post(message) { window.parent.postMessage(message, '*'); }
  function request(method, params) {
    var id = ++nextId;
    post({ jsonrpc: '2.0', id: id, method: method, params: params });
    return new Promise(function (resolve) { pending[id] = resolve; });
  }
  function textOf(result) {
    var content = result && Array.isArray(result.content) ? result.content : [];
    for (var i = 0; i < content.length; i++) if (content[i] && content[i].type === 'text') return content[i].text;
    return 'Nothing to show.';
  }
  function show(result) {
    last = result;
    root.replaceChildren();
    var data = result && result.structuredContent;
    if (!data || result.isError) root.append(el('p', 'note', textOf(result)));
    else try { render(root, data); }
    catch (e) { root.replaceChildren(el('p', 'note', 'This result could not be drawn here; the text answer has all of it.')); }
    measure();
  }
  function context(c) {
    if (!c) return;
    if (c.theme === 'light' || c.theme === 'dark') document.documentElement.setAttribute('data-theme', c.theme);
    if (typeof c.locale === 'string') ctx.locale = c.locale;
    if (typeof c.timeZone === 'string') ctx.timeZone = c.timeZone;
    if (last) show(last);
  }
  window.addEventListener('message', function (event) {
    if (event.source !== window.parent) return;
    var m = event.data;
    if (!m || m.jsonrpc !== '2.0') return;
    if (m.method === undefined) {
      if (pending[m.id]) { pending[m.id](m.result); delete pending[m.id]; }
      return;
    }
    switch (m.method) {
      case 'ui/notifications/tool-result': show(m.params); break;
      case 'ui/notifications/host-context-changed': context(m.params); break;
      case 'ui/resource-teardown': case 'ping': post({ jsonrpc: '2.0', id: m.id, result: {} }); break;
      default:
        if (m.id !== undefined) post({ jsonrpc: '2.0', id: m.id, error: { code: -32601, message: 'Method not found' } });
    }
  });

  // Measured as soon as asked, not on the next animation frame as the SDK
  // does: a browser may throttle frames for a cross-origin iframe that is
  // still a few pixels tall, and the report must not wait on one.
  var lastWidth = 0, lastHeight = 0;
  function measure() {
    var html = document.documentElement, height = html.style.height;
    html.style.height = 'max-content';
    var h = Math.ceil(html.getBoundingClientRect().height);
    html.style.height = height;
    var w = Math.ceil(window.innerWidth);
    if (w === lastWidth && h === lastHeight) return;
    lastWidth = w; lastHeight = h;
    post({ jsonrpc: '2.0', method: 'ui/notifications/size-changed', params: { width: w, height: h } });
  }

  request('ui/initialize', {
    appInfo: { name: 'heart', version: '1.0.0' },
    appCapabilities: { availableDisplayModes: ['inline'] },
    protocolVersion: '2026-01-26'
  }).then(function (result) {
    context(result && result.hostContext);
    post({ jsonrpc: '2.0', method: 'ui/notifications/initialized' });
    new ResizeObserver(measure).observe(document.body);
  });

  var openai = window.openai;
  if (openai) {
    context({ theme: openai.theme, locale: openai.locale });
    if (openai.toolOutput) show({ structuredContent: openai.toolOutput });
    window.addEventListener('openai:set_globals', function (event) {
      var globals = (event.detail && event.detail.globals) || {};
      if (globals.theme || globals.locale) context({ theme: globals.theme, locale: globals.locale });
      if (globals.toolOutput) show({ structuredContent: globals.toolOutput });
    });
  }
})();
''';
