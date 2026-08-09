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
  /// header parsing uses BCP-47 (`en-CA`), so we normalize to the underscore
  /// form used in our config (`en_CA`) before comparison.
  String locale(
    final List<String> supportedLocales,
    final String defaultLocale,
  ) {
    switch (headers.acceptLanguage?.languages) {
      case null:
        return defaultLocale;
      case List l when l.isEmpty:
        return defaultLocale;
      case List<LanguageQuality> l:
        final sorted = List.of(l)..sort((a, b) => (b.quality ?? 0).compareTo(a.quality ?? 0));
        return sorted
            .map((l) => l.language.replaceAll('-', '_'))
            .firstWhere(supportedLocales.contains, orElse: () => defaultLocale);
    }
  }
}
