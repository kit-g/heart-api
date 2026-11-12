import 'package:heart/globals/config.dart';
import 'package:heart/globals/globals.dart';
import 'package:heart/middleware/database.dart';
import 'package:heart/models/errors.dart';
import 'package:heart/routes/devices.dart';
import 'package:heart_models/heart_models.dart';
import 'package:mockito/mockito.dart';
import 'package:relic_core/relic_core.dart';
import 'package:test/test.dart';

import '../helpers/request.dart';
import '../mocks.mocks.dart';

void main() {
  group('registerDevice', () {
    late MockDeviceService deviceService;
    late MockAppConfig config;
    late Request request;

    setUp(() {
      deviceService = MockDeviceService();
      config = MockAppConfig();
      when(config.supportedLocales).thenReturn(['en', 'en_CA', 'ru']);
      when(config.defaultLocale).thenReturn('en');
      when(
        deviceService.registerDevice(
          profileId: anyNamed('profileId'),
          platform: anyNamed('platform'),
          token: anyNamed('token'),
          locale: anyNamed('locale'),
          settings: anyNamed('settings'),
        ),
      ).thenAnswer((_) async {});
    });

    Request build(Map<String, dynamic> body, {Map<String, String> headers = const {}}) {
      return jsonRequest(path: '/devices', body: body, extraHeaders: headers)
        ..user = User(id: 'u1')
        ..config = config
        ..deviceService = deviceService;
    }

    test('upserts on valid payload, locale defaults when no Accept-Language', () async {
      request = build({
        'platform': 'ios',
        'token': 'tok-123',
        'settings': {'authorized': true, 'badge': 'enabled'},
      });

      expect(() => registerDevice(request), throwsA(isA<NoContent>()));

      await pumpEventQueue();
      verify(
        deviceService.registerDevice(
          profileId: 'u1',
          platform: DevicePlatform.ios,
          token: 'tok-123',
          locale: 'en',
          settings: {'authorized': true, 'badge': 'enabled'},
        ),
      ).called(1);
    });

    test('honors Accept-Language when set', () async {
      request = build(
        {'platform': 'android', 'token': 'tok-abc'},
        headers: {'accept-language': 'ru,en;q=0.8'},
      );

      expect(() => registerDevice(request), throwsA(isA<NoContent>()));

      await pumpEventQueue();
      verify(
        deviceService.registerDevice(
          profileId: 'u1',
          platform: DevicePlatform.android,
          token: 'tok-abc',
          locale: 'ru',
          settings: const <String, dynamic>{},
        ),
      ).called(1);
    });

    test('falls back to default for unsupported Accept-Language', () async {
      request = build(
        {'platform': 'web', 'token': 'tok-2'},
        headers: {'accept-language': 'fr'},
      );

      expect(() => registerDevice(request), throwsA(isA<NoContent>()));

      await pumpEventQueue();
      verify(
        deviceService.registerDevice(
          profileId: 'u1',
          platform: DevicePlatform.web,
          token: 'tok-2',
          locale: 'en',
          settings: const <String, dynamic>{},
        ),
      ).called(1);
    });

    test('rejects when platform missing', () async {
      request = build({'token': 'tok-1'});
      expect(() => registerDevice(request), throwsA(isA<BadRequest>()));
      verifyNever(
        deviceService.registerDevice(
          profileId: anyNamed('profileId'),
          platform: anyNamed('platform'),
          token: anyNamed('token'),
          locale: anyNamed('locale'),
          settings: anyNamed('settings'),
        ),
      );
    });

    test('rejects when token missing', () async {
      request = build({'platform': 'ios'});
      expect(() => registerDevice(request), throwsA(isA<BadRequest>()));
    });

    test('rejects on invalid platform', () async {
      request = build({'platform': 'blackberry', 'token': 'tok-1'});
      expect(() => registerDevice(request), throwsA(isA<BadRequest>()));
    });

    test('an offset is from UTC-12 to UTC+14, in whole minutes', () async {
      for (final offset in [-721, 841, 60.5, '60']) {
        request = build({'platform': 'ios', 'token': 'tok-1', 'utcOffsetMinutes': offset});
        await expectLater(registerDevice(request), throwsA(isA<BadRequest>()), reason: '$offset');
      }
    });
  });

  group('unregisterDevice', () {
    late MockDeviceService deviceService;

    setUp(() {
      deviceService = MockDeviceService();
      when(
        deviceService.unregisterDevice(profileId: anyNamed('profileId'), token: anyNamed('token')),
      ).thenAnswer((_) async {});
    });

    Request build(Map<String, dynamic> body) {
      return jsonRequest(path: '/devices/removals', body: body)
        ..user = User(id: 'u1')
        ..deviceService = deviceService;
    }

    test('stops the caller\'s pushes to that token, 204', () async {
      await expectLater(unregisterDevice(build({'token': 'tok-123'})), throwsA(isA<NoContent>()));
      verify(deviceService.unregisterDevice(profileId: 'u1', token: 'tok-123')).called(1);
    });

    test('needs a token', () async {
      await expectLater(unregisterDevice(build({})), throwsA(isA<BadRequest>()));
      verifyZeroInteractions(deviceService);
    });
  });
}
