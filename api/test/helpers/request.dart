import 'dart:convert';

import 'package:relic_core/relic_core.dart';

/// Builds a request with a JSON body, ready to feed into route handlers that
/// call `req.json()`.
Request jsonRequest({
  Method method = Method.post,
  String path = '/',
  Map<String, dynamic> body = const {},
  Map<String, String> query = const {},
}) {
  return RequestInternal.create(
    method,
    _uri(path, query),
    Object(),
    body: Body.fromString(jsonEncode(body), mimeType: MimeType.json),
  );
}

/// Builds a request with no body. Suitable for handlers that don't call
/// `req.json()` (e.g. event handlers given userId directly, GET routes that
/// read only query params).
Request bareRequest({
  Method method = Method.post,
  String path = '/',
  Map<String, String> query = const {},
}) {
  return RequestInternal.create(method, _uri(path, query), Object());
}

Uri _uri(String path, Map<String, String> query) {
  return Uri.parse('http://localhost$path').replace(
    queryParameters: query.isEmpty ? null : query,
  );
}