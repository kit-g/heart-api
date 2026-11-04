import 'dart:convert';

import 'package:heart_models/heart_models.dart';
import 'package:test/test.dart';

/// What a client receives for [model]: the API answers with `jsonEncode(model.toMap())`
/// (`api/lib/core/response.dart`), and the app decodes it.
Map<String, dynamic> wire(Model model) => jsonDecode(jsonEncode(model.toMap())) as Map<String, dynamic>;

/// [model] written, sent and read back with [read] writes what it wrote.
void expectRoundTrip<T extends Model>(T model, T Function(Map) read) {
  expect(read(wire(model)).toMap(), wire(model));
}
