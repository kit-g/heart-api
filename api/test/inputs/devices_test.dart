import 'package:heart/globals/config.dart';
import 'package:heart/inputs/inputs.dart';
import 'package:heart/models/errors.dart';
import 'package:heart_models/heart_models.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import '../helpers/request.dart';
import '../mocks.mocks.dart';

void main() {
  group('DeviceRegisterIn — mapping / parsed enum', () {
    late MockAppConfig config;

    setUp(() {
      config = MockAppConfig();
      when(config.supportedLocales).thenReturn(const ['en']);
      when(config.defaultLocale).thenReturn('en');
    });

    Future<DeviceRegisterIn> parse(Map<String, dynamic> body) =>
        DeviceRegisterIn.fromRequest(jsonRequest(body: body)..config = config);

    test('parses platform / token / settings', () async {
      final input = await parse({
        'platform': 'ios',
        'token': 'tok',
        'settings': {'a': 1},
      });
      expect(input.platform, DevicePlatform.ios);
      expect(input.token, 'tok');
      expect(input.settings, containsPair('a', 1));
    });

    test('defaults settings to empty when absent (mapping orElse)', () async {
      final input = await parse({'platform': 'ios', 'token': 'tok'});
      expect(input.settings, isEmpty);
    });

    test('rejects a non-object settings', () async {
      await expectLater(parse({'platform': 'ios', 'token': 'tok', 'settings': 'x'}), throwsA(isA<BadRequest>()));
    });

    test('rejects an unknown platform', () async {
      await expectLater(parse({'platform': 'nope', 'token': 'tok'}), throwsA(isA<BadRequest>()));
    });

    test('rejects a missing token', () async {
      await expectLater(parse({'platform': 'ios'}), throwsA(isA<BadRequest>()));
    });
  });
}
