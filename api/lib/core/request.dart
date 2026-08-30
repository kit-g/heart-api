import 'dart:convert';

import 'package:relic/relic.dart';

import '../models/errors.dart';

extension JsonBody on Request {
  Future<Map<String, dynamic>> json() {
    return switch (body.bodyType) {
      BodyType(:MimeType mimeType) when mimeType == .json => readAsString().then((v) => jsonDecode(v)),
      // a client mistake, not a missing server feature: 415, not 501
      _ => throw const UnsupportedMediaType(reason: 'expected an application/json request body'),
    };
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
