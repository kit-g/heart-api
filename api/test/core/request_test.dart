import 'package:heart/core/request.dart';
import 'package:heart/models/errors.dart';
import 'package:relic_core/relic_core.dart';
import 'package:test/test.dart';

import '../helpers/request.dart';

/// Locks the body-decoding contract of `Request.json()`: an
/// `application/json` body parses, anything else is the client's mistake
/// (415), not a missing server feature (501).
void main() {
  test('an application/json body decodes to a map', () async {
    final request = jsonRequest(body: {'a': 1});
    expect(await request.json(), {'a': 1});
  });

  test('a non-JSON body throws UnsupportedMediaType', () {
    final request = RequestInternal.create(
      Method.post,
      Uri.parse('http://localhost/'),
      Object(),
      body: Body.fromString('plain text', mimeType: MimeType.plainText),
    );
    expect(request.json, throwsA(isA<UnsupportedMediaType>()));
  });

  test('a bodiless request throws UnsupportedMediaType', () {
    expect(bareRequest().json, throwsA(isA<UnsupportedMediaType>()));
  });
}
