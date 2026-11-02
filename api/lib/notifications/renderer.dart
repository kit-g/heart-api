import 'templates.dart';

/// Renders the title for a push notification. A regional locale without
/// templates of its own falls back to its base language before the default
/// locale (`es_ES -> es -> en`), mirroring the exercise-library chain; falls
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
  final byEvent =
      notificationTemplates[locale] ??
      notificationTemplates[locale.split('_').first] ??
      notificationTemplates[defaultLocale]!;
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
