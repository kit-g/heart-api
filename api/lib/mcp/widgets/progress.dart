part of '../widgets.dart';

/// `get_exercise_history`'s chart: the app's progress chart for one exercise,
/// a point per session oldest to newest, one metric at a time.
///
/// Drawn by `ProgressCard` in `pages/lib/cards/`, compiled by `make cards`.
const _progressHtml =
    '$_head<title>Heart exercise progress</title><style>$_baseCss$_progressCardCss</style></head>'
    '$_root<script>$_progressCardJs</script></body></html>';
