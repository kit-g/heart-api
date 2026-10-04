import 'dart:convert';

import 'package:relic/relic.dart';

import '../models/errors.dart';

extension JsonBody on Request {
  /// The JSON object body. A body naming a health-shaped field anywhere in it
  /// is a 400, even where no route would read the field: health data never
  /// reaches this backend (CLAUDE.md, *The device-only health rule*).
  Future<Map<String, dynamic>> json() async {
    final Map<String, dynamic> decoded = switch (body.bodyType) {
      BodyType(:MimeType mimeType) when mimeType == .json => jsonDecode(await readAsString()),
      // a client mistake, not a missing server feature: 415, not 501
      _ => throw const UnsupportedMediaType(reason: 'expected an application/json request body'),
    };
    if (_healthField(decoded) case final String field) {
      throw BadRequest(
        code: 'health_data',
        reason: '$field looks like health data, which stays on the device',
      );
    }
    return decoded;
  }

  /// Raw text body, whatever the declared content type — file uploads like a
  /// CSV export arrive as `text/csv`, `text/plain`, or `application/octet-stream`
  /// depending on the client, and the parser is the real gatekeeper anyway.
  Future<String> text() => readAsString();

  /// reproducible raw shape of the request
  Map<String, String> signature() {
    return {
      ...url.queryParameters,
      ...pathParameters.raw.map((k, v) => MapEntry(k.toString(), v)),
    };
  }
}

/// The path of the first health-shaped key in [value] (`exercises[0].heartRate`),
/// or null when there is none.
String? _healthField(Object? value, [String path = '']) {
  switch (value) {
    case Map map:
      for (final MapEntry(:key, value: child) in map.entries) {
        final at = path.isEmpty ? '$key' : '$path.$key';
        if (_isHealthShaped('$key')) return at;
        if (_healthField(child, at) case final String found) return found;
      }
    case List list:
      for (final (index, child) in list.indexed) {
        if (_healthField(child, '$path[$index]') case final String found) return found;
      }
  }
  return null;
}

/// Keys a health reading would travel under, compared case- and
/// separator-blind: `heartRate`, `heart_rate` and `Heart-Rate` are one name.
/// A fragment matches anywhere in a key; `steps` only as the whole key.
/// `database/tests/public/health_rule.sql` holds the same list for columns.
bool _isHealthShaped(String key) {
  final normalized = key.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');
  return normalized == 'steps' || _healthFragments.any(normalized.contains);
}

const _healthFragments = [
  'heartrate',
  'hrv',
  'sleep',
  'bodymass',
  'bodyweight',
  'bodyfat',
  'activeenergy',
  'restingenergy',
  'basalenergy',
  'stepcount',
  'oxygensaturation',
  'spo2',
  'vo2max',
  'respiratoryrate',
  'bloodpressure',
  'bloodglucose',
];

extension Locale on Request {
  /// Picks the best locale for a request, given a list of supported locales
  /// and a default fallback.
  ///
  /// Greedy match against the highest-quality acceptable language; relic's
  /// header parsing lowercases the whole BCP-47 tag (`en-CA` -> `en-ca`), so
  /// each tag is canonicalized to the spelling our config uses (`en_CA`:
  /// lowercase language, underscore, uppercase region) before comparison.
  ///
  /// Each requested tag is tried three ways before moving to the next: the
  /// exact tag, then its bare language, then any supported regional variant
  /// of that language. Devices commonly send only a regional tag (`es-MX`),
  /// and content is authored under base languages (`es`) with regional
  /// overlays only where copy diverges — without the truncation step every
  /// Spanish speaker outside the one listed region would fall through to
  /// [defaultLocale] (i.e. English).
  String locale(
    List<String> supportedLocales,
    String defaultLocale,
  ) {
    switch (headers.acceptLanguage?.languages) {
      case null:
        return defaultLocale;
      case List l when l.isEmpty:
        return defaultLocale;
      case List<LanguageQuality> l:
        final sorted = List.of(l)..sort((a, b) => (b.quality ?? 0).compareTo(a.quality ?? 0));
        for (final tag in sorted.map((l) => _canonical(l.language))) {
          if (supportedLocales.contains(tag)) return tag;
          final language = tag.split('_').first;
          if (supportedLocales.contains(language)) return language;
          for (final supported in supportedLocales) {
            if (supported.startsWith('${language}_')) return supported;
          }
        }
        return defaultLocale;
    }
  }

  static String _canonical(String tag) {
    final [language, ...rest] = tag.replaceAll('-', '_').split('_');
    return [language.toLowerCase(), ...rest.map((part) => part.toUpperCase())].join('_');
  }
}
