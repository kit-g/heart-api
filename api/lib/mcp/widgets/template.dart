part of '../widgets.dart';

/// `create_template`'s and `update_template`'s card: the template as the app's
/// template card lays it out, under a line saying whether it is a preview,
/// created or replaced.
///
/// Drawn by `TemplateCard` in `pages/lib/cards/`, compiled by `make cards`.
const _templateHtml =
    '$_head<title>Heart template</title><style>$_baseCss$_templateCardCss</style></head>'
    '$_root<script>$_templateCardJs</script></body></html>';
