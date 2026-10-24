part of '../widgets.dart';

/// `get_workout`'s card: the design system's workout card (title, date, hero
/// stats, hairline, roster), with every set under its exercise; the roster
/// flows into columns when the frame is wide.
///
/// Drawn by `WorkoutCard`, a Jaspr component in `pages/lib/cards/` that a
/// share page can render too; `make cards` compiles it, with its bridge,
/// into [_workoutCardJs], and its styles into [_workoutCardCss].
const _workoutHtml =
    '$_head<title>Heart workout</title><style>$_baseCss$_workoutCardCss</style></head>'
    '$_root<script>$_workoutCardJs</script></body></html>';
