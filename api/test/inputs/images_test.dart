import 'package:heart/globals/config.dart';
import 'package:heart/inputs/inputs.dart';
import 'package:heart/models/errors.dart';
import 'package:mockito/mockito.dart';
import 'package:relic_core/relic_core.dart';
import 'package:test/test.dart';

import '../helpers/request.dart';
import '../mocks.mocks.dart';

void main() {
  group('WorkoutImagePresignIn — mime allowlist / default type', () {
    late MockAppConfig config;

    setUp(() {
      config = MockAppConfig();
      when(config.allowedMimeTypes).thenReturn(const {'image/jpeg', 'image/png'});
    });

    Future<WorkoutImagePresignIn> parse(Map<String, dynamic> body) =>
        WorkoutImagePresignIn.fromRequest(jsonRequest(body: body)..config = config);

    test('defaults to image/jpeg with a jpg extension', () async {
      final input = await parse({});
      expect(input.mimeType, 'image/jpeg');
      expect(input.ext, 'jpg');
    });

    test('derives the extension from an allowed mime type', () async {
      final input = await parse({'mimeType': 'image/png'});
      expect(input.mimeType, 'image/png');
      expect(input.ext, 'png');
    });

    test('rejects a mime type outside the allowlist', () async {
      await expectLater(parse({'mimeType': 'image/gif'}), throwsA(isA<BadRequest>()));
    });
  });

  group('WorkoutImageDeleteQuery — required key', () {
    WorkoutImageDeleteQuery parse(Map<String, String> query) =>
        WorkoutImageDeleteQuery.fromRequest(bareRequest(method: Method.delete, query: query));

    test('reads the key from the query string', () {
      expect(parse({'key': '/workouts/w1/img.jpg'}).key, '/workouts/w1/img.jpg');
    });

    test('rejects a missing key', () {
      expect(() => parse({}), throwsA(isA<BadRequest>()));
    });
  });
}
