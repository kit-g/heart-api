import 'dart:convert';

import 'package:relic/relic.dart';

extension JsonBody on Request {
  Future<Map<String, dynamic>> json() {
    return switch (body.bodyType) {
      BodyType(:MimeType mimeType) when mimeType == .json => readAsString().then((v) => jsonDecode(v)),
      _ => throw UnimplementedError('Could not decode JSON request body'),
    };
  }

  /// reproducible raw shape of the request
  Map<String, String> signature() {
    return {
      ...url.queryParameters,
      ...pathParameters.raw.map((k, v) => MapEntry(k.toString(), v)),
    };
  }
}
