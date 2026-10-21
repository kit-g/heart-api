/// The cards' styles, beside the components that draw them: whatever page
/// shows a card, an MCP Apps view or a share page, takes [cardCss] and the
/// card's own entry in [cardStyles] on top of the design system's tokens
/// (`package:heart_design`'s `tokensCss`, or `site/assets/tokens.css`).
///
/// No shadows, the accent a fill and accent-ink for text and lines. The
/// fonts are named but never fetched; a host without them falls back to the
/// system face.
library;

/// What every card shares: the page, the card, its title, hero stats,
/// hairline and rows.
const cardCss = r'''
* { box-sizing: border-box; }
html, body { margin: 0; }
body {
  background: var(--ground); color: var(--ink); font-family: var(--font-text);
  font-size: 13px; line-height: 1.4; padding: 2px;
}
.card {
  background: var(--surface); border: 1px solid var(--border); border-radius: var(--radius-card);
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

/// Each card's own styles, by the name of its script in `cards/`.
const cardStyles = {
  'workout': r'''
.exercises { display: grid; grid-template-columns: repeat(auto-fill, minmax(220px, 1fr)); gap: 12px 28px; }
.exercise .name { font-weight: 600; }
.exercise .sets { margin-top: 4px; }
.exercise .tag { display: inline-block; min-width: 2.8em; color: var(--muted); font-variant-numeric: tabular-nums; }
.exercise .undone { color: var(--faint); }
.exercise .exercise-note { color: var(--muted); font-style: italic; margin-top: 2px; }
''',
  'progress': r'''
.chips { display: flex; flex-wrap: wrap; gap: 6px; margin-top: 12px; }
.chip {
  font: inherit; font-size: 12px; padding: 4px 10px; border-radius: var(--radius-control); cursor: pointer;
  border: 1px solid var(--border); background: var(--surface); color: var(--ink);
}
.chip[aria-pressed="true"] { background: var(--accent); border-color: var(--accent); color: var(--on-accent); }
svg { display: block; width: 100%; height: auto; margin-top: 12px; overflow: visible; }
svg text { font-family: var(--font-text); font-size: 11px; fill: var(--muted); }
svg .grid { stroke: var(--border); stroke-width: 1; }
svg .line { fill: none; stroke: var(--accent-ink); stroke-width: 2; stroke-linejoin: round; }
svg .dot { fill: var(--surface); stroke: var(--accent-ink); stroke-width: 2; }
''',
  'records': r'''
.record { display: grid; grid-template-columns: 1fr auto; column-gap: 12px; }
.record + .record { margin-top: 6px; }
.record .what { color: var(--muted); }
.record .best { font-weight: 600; color: var(--accent-ink); font-variant-numeric: tabular-nums; text-align: right; }
.record .when { grid-column: 1 / -1; color: var(--faint); font-size: 12px; }
''',
  'template': r'''
.status { display: inline-block; font-size: 10px; letter-spacing: 1.5px; text-transform: uppercase;
  color: var(--accent-ink); border: 1px solid var(--accent-ink); border-radius: var(--radius-control);
  padding: 1px 6px; margin-bottom: 8px; }
.status.preview { color: var(--muted); border-color: var(--border); background: var(--fill); }
.quote { border-left: 2px solid var(--border); padding-left: 10px; }
.exercise + .exercise { margin-top: 12px; }
.exercise .name { font-weight: 600; }
.exercise .sets { margin-top: 4px; }
.exercise .tag { display: inline-block; width: 1.6em; color: var(--muted); font-variant-numeric: tabular-nums; }
.exercise .aim { color: var(--muted); }
''',
};
