import 'dart:convert';

import 'package:relic_core/relic_core.dart';

/// Builds a request with a JSON body, ready to feed into route handlers that
/// call `req.json()`.
///
/// [extraHeaders] lets you set raw header values (e.g. `accept-language`) for
/// route logic that reads them.
Request jsonRequest({
  Method method = Method.post,
  String path = '/',
  Map<String, dynamic> body = const {},
  Map<String, String> query = const {},
  Map<String, String> extraHeaders = const {},
}) {
  return RequestInternal.create(
    method,
    _uri(path, query),
    Object(),
    body: Body.fromString(jsonEncode(body), mimeType: MimeType.json),
    headers: _headers(extraHeaders),
  );
}

/// Builds a request with a raw text body (e.g. a CSV upload), for handlers
/// that read via `req.text()`.
Request textRequest({
  Method method = Method.post,
  String path = '/',
  String body = '',
  MimeType mimeType = MimeType.csv,
  Map<String, String> query = const {},
  Map<String, String> extraHeaders = const {},
}) {
  return RequestInternal.create(
    method,
    _uri(path, query),
    Object(),
    body: Body.fromString(body, mimeType: mimeType),
    headers: _headers(extraHeaders),
  );
}

/// Builds a request with no body. Suitable for handlers that don't call
/// `req.json()` (e.g. event handlers given userId directly, GET routes that
/// read only query params).
Request bareRequest({
  Method method = Method.post,
  String path = '/',
  Map<String, String> query = const {},
  Map<String, String> extraHeaders = const {},
}) {
  return RequestInternal.create(
    method,
    _uri(path, query),
    Object(),
    headers: _headers(extraHeaders),
  );
}

Uri _uri(String path, Map<String, String> query) {
  return Uri.parse('http://localhost$path').replace(
    queryParameters: query.isEmpty ? null : query,
  );
}

Headers? _headers(Map<String, String> extra) {
  if (extra.isEmpty) return null;
  return Headers.build((mh) {
    for (final MapEntry(key: name, value: value) in extra.entries) {
      mh[name] = [value];
    }
  });
}
