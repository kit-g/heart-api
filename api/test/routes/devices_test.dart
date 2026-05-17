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
    late Request request;

    setUp(() {
      deviceService = MockDeviceService();
      when(
        deviceService.registerDevice(
          profileId: anyNamed('profileId'),
          platform: anyNamed('platform'),
          token: anyNamed('token'),
          settings: anyNamed('settings'),
        ),
      ).thenAnswer((_) async {});
    });

    Request build(Map<String, dynamic> body) {
      return jsonRequest(path: '/devices', body: body)
        ..user = User(id: 'u1')
        ..deviceService = deviceService;
    }

    test('upserts on valid payload', () async {
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
          settings: {'authorized': true, 'badge': 'enabled'},
        ),
      ).called(1);
    });

    test('defaults settings to empty map when absent', () async {
      request = build({'platform': 'android', 'token': 'tok-abc'});

      expect(() => registerDevice(request), throwsA(isA<NoContent>()));

      await pumpEventQueue();
      verify(
        deviceService.registerDevice(
          profileId: 'u1',
          platform: DevicePlatform.android,
          token: 'tok-abc',
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
  });
}
