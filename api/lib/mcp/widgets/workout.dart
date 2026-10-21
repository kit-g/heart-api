part of '../widgets.dart';

/// `get_workout`'s card: the design system's workout card (title, date, hero
/// stats, hairline, roster), with every set under its exercise.
///
/// Drawn by `WorkoutCard`, a Jaspr component in `pages/lib/cards/` that a
/// share page can render too, with its own MCP Apps bridge; `make cards`
/// compiles it into [_workoutCardJs]. The styles stay here with the shell's.
const _workoutHtml =
    '$_head<title>Heart workout</title><style>$_baseCss$_workoutCss</style></head>'
    '<body><main id="root" aria-live="polite"></main><script>$_workoutCardJs</script></body></html>';

const _workoutCss = r'''
.exercise + .exercise { margin-top: 12px; }
.exercise .name { font-weight: 600; }
.exercise .sets { margin-top: 4px; }
.exercise .tag { display: inline-block; width: 1.6em; color: var(--muted); font-variant-numeric: tabular-nums; }
.exercise .undone { color: var(--faint); }
.exercise .exercise-note { color: var(--muted); font-style: italic; margin-top: 2px; }
''';
