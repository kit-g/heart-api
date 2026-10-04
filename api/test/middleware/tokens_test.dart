import 'dart:convert';

import 'package:heart/globals/config.dart';
import 'package:heart/globals/globals.dart';
import 'package:heart/middleware/database.dart';
import 'package:heart/middleware/tokens.dart';
import 'package:heart/models/tokens.dart';
import 'package:heart_models/heart_models.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:relic/relic.dart' hide Logger;
import 'package:test/test.dart';

import '../helpers/request.dart';
import '../mocks.mocks.dart';

void main() {
  late MockApiTokenService service;
  late MockAppConfig config;
  final now = DateTime.utc(2026, 10, 4, 12);
  final secret = TokenSecret.mint();

  setUp(() {
    service = MockApiTokenService();
    config = MockAppConfig();
    when(config.freeApiLimits).thenReturn(const ApiLimits(perMinute: 20, perDay: 200));
  });

  TokenUse use({int minute = 1, int day = 1, DateTime? minuteStart, DateTime? dayStart}) {
    return (
      userId: 'u1',
      scopes: const ['read'],
      purpose: ApiTokenPurpose.aiAssistant,
      minuteStart: minuteStart ?? now,
      minuteCount: minute,
      dayStart: dayStart ?? now,
      dayCount: day,
    );
  }

  Request build({String? bearer, String? userAgent}) {
    return bareRequest(
        method: Method.get,
        path: '/me/workouts',
        extraHeaders: {
          'authorization': ?(bearer == null ? null : 'Bearer $bearer'),
          'user-agent': ?userAgent,
        },
      )
      ..config = config
      ..apiTokenService = service;
  }

  Future<Response> run(Request request, {Handler? inner}) async {
    final handler = tokenAuthentication(clock: () => now)(
      inner ?? (req) async => Response.ok(body: Body.fromString(req.userId)),
    );
    return await handler(request) as Response;
  }

  test('a valid token reaches the handler as its account', () async {
    when(service.useToken(TokenSecret.hash(secret))).thenAnswer((_) async => use());

    final response = await run(build(bearer: secret));

    expect(response.statusCode, 200);
    expect(await response.readAsString(), 'u1');
  });

  test('missing, malformed and unknown tokens are the same 401 invalid_token', () async {
    when(service.useToken(any)).thenAnswer((_) async => null);

    for (final bearer in [null, 'not-a-token', TokenSecret.mint()]) {
      final response = await run(build(bearer: bearer));
      expect(response.statusCode, 401);
      expect((jsonDecode(await response.readAsString()) as Map)['code'], 'invalid_token');
    }
    // Only the well-formed one reaches the database.
    verify(service.useToken(any)).called(1);
  });

  test('over the minute window is a 429 until that window restarts', () async {
    when(service.useToken(any)).thenAnswer(
      (_) async => use(minute: 21, minuteStart: now.subtract(const Duration(seconds: 15))),
    );

    final response = await run(build(bearer: secret));

    expect(response.statusCode, 429);
    expect(response.headers.retryAfter?.delay, 45);
    final body = jsonDecode(await response.readAsString()) as Map;
    expect(body['code'], 'rate_limited');
    expect(body['retryAfter'], 45);
  });

  test('over the day window is a 429 until that window restarts', () async {
    when(service.useToken(any)).thenAnswer(
      (_) async => use(day: 201, dayStart: now.subtract(const Duration(hours: 23))),
    );

    final response = await run(build(bearer: secret));

    expect(response.statusCode, 429);
    expect(response.headers.retryAfter?.delay, 3600);
  });

  test('exactly at the limit still passes', () async {
    when(service.useToken(any)).thenAnswer((_) async => use(minute: 20, day: 200));
    expect((await run(build(bearer: secret))).statusCode, 200);
  });

  test('logs one usage line without the account id or the token', () async {
    when(service.useToken(any)).thenAnswer((_) async => use());
    final lines = <String>[];
    Logger.root.level = Level.ALL;
    final sub = Logger('ApiUsage').onRecord.listen((r) => lines.add(r.message));
    addTearDown(sub.cancel);

    await run(build(bearer: secret, userAgent: 'python-requests/2.32.3'));

    final line = jsonDecode(lines.single) as Map;
    expect(line, {
      'surface': 'me',
      'route': '/me/workouts',
      'status': 200,
      'credential': 'pat',
      'client': null,
      'purpose': 'aiAssistant',
      'uaFamily': 'python-requests',
      'account': pseudonym('u1'),
    });
    expect(lines.single, isNot(contains(secret)));
    expect(lines.single, isNot(contains('"u1"')));
  });

  group('userAgentFamily', () {
    test('groups known tools and keeps unknown product tokens', () {
      expect(userAgentFamily('curl/8.7.1'), 'curl');
      expect(userAgentFamily('HomeAssistant/2026.10 aiohttp/3.10'), 'home-assistant');
      expect(userAgentFamily('claude-code/2.1.0'), 'claude-code');
      expect(userAgentFamily('Mozilla/5.0 (Macintosh)'), 'browser');
      expect(userAgentFamily('my-sheet-sync/1.0'), 'my-sheet-sync');
      expect(userAgentFamily(null), isNull);
      expect(userAgentFamily('  '), isNull);
    });
  });
}
