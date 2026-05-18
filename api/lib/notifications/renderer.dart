import 'templates.dart';

/// Truncates [s] to [maxLength] characters and appends a horizontal-ellipsis
/// (`…`, U+2026) if it had to cut. The ellipsis itself is locale-neutral so
/// safe to apply before knowing the recipient's language.
String snippetize(String s, {int maxLength = 200}) {
  if (s.length <= maxLength) return s;
  return '${s.substring(0, maxLength)}…';
}

/// Renders the title for a push notification. Falls back to the default
/// locale when the requested locale isn't in [notificationTemplates]; falls
/// back to the variant raw if the variant key is unknown (so a missing
/// translation surfaces as a non-localized but still readable string instead
/// of crashing).
String renderTitle({
  required String locale,
  required String eventType,
  required String variant,
  required Map<String, String> args,
  String defaultLocale = 'en',
}) {
  final byEvent = notificationTemplates[locale] ?? notificationTemplates[defaultLocale]!;
  final byVariant = byEvent[eventType] ?? const {};
  final template = byVariant[variant] ?? variant;
  return template.interpolated(args);
}

extension on String {
  String interpolated(Map<String, String> args) {
    var out = this;
    for (final MapEntry(key: k, value: v) in args.entries) {
      out = out.replaceAll('{$k}', v);
    }
    return out;
  }
}
