import 'dart:convert';

import 'package:relic/relic.dart';

extension JsonBody on Request {
  Future<Map<String, dynamic>> json() {
    return switch (body.bodyType) {
      BodyType(:MimeType mimeType) when mimeType == .json => readAsString().then((v) => jsonDecode(v)),
      _ => throw UnimplementedError('Could not decode JSON request body'),
    };
  }
}
