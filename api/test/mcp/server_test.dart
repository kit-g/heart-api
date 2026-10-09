import 'dart:convert';

import 'package:heart/models/tokens.dart';
import 'package:heart/models/changes.dart';
import 'package:heart_models/heart_models.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import '../helpers/app_harness.dart';

/// The MCP endpoint end to end through the real app: both protocol eras,
/// header validation, auth and counting, and the tools.
void main() {
  late AppHarness app;
  final secret = TokenSecret.mint();
  final now = DateTime.now().toUtc();

  TokenUse use({int count = 1}) {
    return (
      userId: 'u1',
      resource: null,
      clientId: null,
      scopes: const ['read'],
      purpose: ApiTokenPurpose.aiAssistant,
      minuteStart: now,
      minuteCount: count,
      dayStart: now,
      dayCount: count,
    );
  }

  setUp(() async {
    app = await AppHarness.start();
    when(app.config.freeApiLimits).thenReturn(ApiLimits.free);
    when(app.config.cdnAssetUrl(any)).thenAnswer((i) => 'https://media.example/${i.positionalArguments.first}');
    when(app.db.useToken(TokenSecret.hash(secret), count: anyNamed('count'))).thenAnswer((_) async => use());
  });

  tearDown(() => app.stop());

  Future<({int status, Map body, Map<String, String> headers})> rpc(
    String method, {
    Map<String, dynamic>? params,
    Object? id = 1,
    String? token,
    Map<String, String> headers = const {},
  }) async {
    final response = await app.send(
      'POST',
      '/mcp',
      token: token ?? secret,
      body: {'jsonrpc': '2.0', 'id': ?id, 'method': method, 'params': ?params},
      extraHeaders: headers,
    );
    return (
      status: response.status,
      body: response.body.isEmpty ? const {} : jsonDecode(response.body) as Map,
      headers: response.headers,
    );
  }

  Map<String, dynamic> modernMeta() => {
    'io.modelcontextprotocol/protocolVersion': '2026-07-28',
    'io.modelcontextprotocol/clientInfo': {'name': 'claude-code', 'version': '2.1'},
    'io.modelcontextprotocol/clientCapabilities': <String, dynamic>{},
  };

  Map<String, String> modernHeaders(String method, {String? name}) => {
    'mcp-protocol-version': '2026-07-28',
    'mcp-method': method,
    'mcp-name': ?name,
  };

  group('auth', () {
    test('no token is a 401 with a Bearer challenge', () async {
      final response = await app.send(
        'POST',
        '/mcp',
        token: null,
        body: {'jsonrpc': '2.0', 'id': 1, 'method': 'tools/list'},
      );
      expect(response.status, 401);
      expect(response.headers['www-authenticate'], startsWith('Bearer'));
    });

    test('a Firebase token is not a personal access token', () async {
      expect((await rpc('tools/list', token: AppHarness.goodToken)).status, 401);
    });

    test('the handshake and listings are free; tool calls count', () async {
      when(app.db.getProfile('u1')).thenAnswer((_) async => User(id: 'u1'));
      when(app.db.getAccountSummary('u1')).thenAnswer((_) async => const AccountSummary(collections: {}));

      await rpc('initialize', params: {'protocolVersion': '2025-06-18'});
      await rpc('tools/list');
      verify(app.db.useToken(any, count: false)).called(2);

      await rpc('tools/call', params: {'name': 'get_profile'});
      verify(app.db.useToken(any, count: true)).called(1);
    });

    test('a tool call over the limit is a 429', () async {
      when(app.db.useToken(any, count: true)).thenAnswer((_) async => use(count: 21));
      final response = await rpc('tools/call', params: {'name': 'get_profile'});
      expect(response.status, 429);
    });

    test('a browser origin the API does not trust is refused', () async {
      final response = await rpc('tools/list', headers: {'origin': 'https://evil.example'});
      expect(response.status, 403);
    });
  });

  group('legacy (initialize) clients', () {
    test('initialize echoes a supported version and names the server', () async {
      final response = await rpc(
        'initialize',
        params: {
          'protocolVersion': '2025-06-18',
          'clientInfo': {'name': 'cursor', 'version': '1'},
          'capabilities': <String, dynamic>{},
        },
      );
      expect(response.status, 200);
      final result = response.body['result'] as Map;
      expect(result['protocolVersion'], '2025-06-18');
      expect((result['serverInfo'] as Map)['name'], 'heart');
      expect(result['instructions'], contains('no health data'));
      expect(response.headers.containsKey('mcp-session-id'), isFalse);
    });

    test('an unknown requested version gets the newest legacy one', () async {
      final result = (await rpc('initialize', params: {'protocolVersion': '2024-01-01'})).body['result'] as Map;
      expect(result['protocolVersion'], '2025-11-25');
    });

    test('a notification is accepted with 202 and no body', () async {
      final response = await rpc('notifications/initialized', id: null);
      expect(response.status, 202);
    });

    test('tools are listed with read-only annotations', () async {
      final tools = ((await rpc('tools/list')).body['result'] as Map)['tools'] as List;
      expect(
        tools.map((t) => (t as Map)['name']),
        containsAll(['list_workouts', 'get_exercise_history', 'search_exercises']),
      );
      for (final tool in tools.cast<Map>()) {
        final annotations = tool['annotations'] as Map;
        expect(annotations['readOnlyHint'], isTrue, reason: tool['name'] as String);
        expect(annotations['destructiveHint'], isFalse);
        expect(tool['title'], isNotEmpty);
        expect((tool['name'] as String).length, lessThanOrEqualTo(64));
      }
    });

    test('GET and DELETE are 405', () async {
      expect((await app.send('GET', '/mcp', token: secret)).status, 405);
      expect((await app.send('DELETE', '/mcp', token: secret)).status, 405);
    });
  });

  group('modern (2026-07-28) clients', () {
    test('server/discover advertises both eras', () async {
      final response = await rpc(
        'server/discover',
        params: {'_meta': modernMeta()},
        headers: modernHeaders('server/discover'),
      );
      expect(response.status, 200);
      final result = response.body['result'] as Map;
      expect(result['supportedVersions'], containsAll(['2026-07-28', '2025-11-25']));
      expect(result['resultType'], 'complete');
      expect(((result['_meta'] as Map)['io.modelcontextprotocol/serverInfo'] as Map)['name'], 'heart');
    });

    test('lists carry a cache hint', () async {
      final result =
          (await rpc(
                'tools/list',
                params: {'_meta': modernMeta()},
                headers: modernHeaders('tools/list'),
              )).body['result']
              as Map;
      expect(result['ttlMs'], greaterThan(0));
      expect(result['cacheScope'], 'private');
    });

    test('headers that disagree with the body are a 400 HeaderMismatch', () async {
      final missing = await rpc('tools/list', params: {'_meta': modernMeta()});
      expect(missing.status, 400);
      expect((missing.body['error'] as Map)['code'], -32020);

      final wrongName = await rpc(
        'tools/call',
        params: {'name': 'get_profile', '_meta': modernMeta()},
        headers: modernHeaders('tools/call', name: 'list_workouts'),
      );
      expect((wrongName.body['error'] as Map)['code'], -32020);
    });

    test('a Base64-encoded Mcp-Name is decoded before comparing', () async {
      when(app.db.getProfile('u1')).thenAnswer((_) async => User(id: 'u1'));
      when(app.db.getAccountSummary('u1')).thenAnswer((_) async => const AccountSummary(collections: {}));
      final encoded = '=?base64?${base64.encode(utf8.encode('get_profile'))}?=';

      final response = await rpc(
        'tools/call',
        params: {'name': 'get_profile', '_meta': modernMeta()},
        headers: modernHeaders('tools/call', name: encoded),
      );
      expect(response.status, 200);
    });

    test('an unsupported version is a 400 listing the supported ones', () async {
      final meta = {...modernMeta(), 'io.modelcontextprotocol/protocolVersion': '2099-01-01'};
      final response = await rpc(
        'tools/list',
        params: {'_meta': meta},
        headers: {...modernHeaders('tools/list'), 'mcp-protocol-version': '2099-01-01'},
      );
      expect(response.status, 400);
      final error = response.body['error'] as Map;
      expect(error['code'], -32022);
      expect((error['data'] as Map)['supported'], contains('2026-07-28'));
    });

    test('an unknown method is a 404 method-not-found', () async {
      final response = await rpc(
        'prompts/list',
        params: {'_meta': modernMeta()},
        headers: modernHeaders('prompts/list'),
      );
      expect(response.status, 404);
      expect((response.body['error'] as Map)['code'], -32601);
    });
  });

  group('tools', () {
    test('list_workouts returns summaries with a cursor while there is more', () async {
      final workout = Workout.fromRow(
        {
          'id': '019a0000-0000-7000-8000-0000000000aa',
          'name': 'Push',
          'started_at': '2026-10-01T10:00:00Z',
          'completed_at': '2026-10-01T11:00:00Z',
          'exercises': [],
        },
        imageUrl: (k) => k,
      );
      when(
        app.db.getWorkouts(userId: 'u1', targetUserId: 'u1', imageUrl: anyNamed('imageUrl'), cursor: null, limit: 20),
      ).thenAnswer((_) async => Page(items: [workout], hasMore: true));

      final result = (await rpc('tools/call', params: {'name': 'list_workouts'})).body['result'] as Map;

      expect(result['isError'], isFalse);
      final structured = result['structuredContent'] as Map;
      expect(structured['cursor'], '019a0000-0000-7000-8000-0000000000aa');
      final summary = (structured['workouts'] as List).single as Map;
      expect(summary['name'], 'Push');
      expect(summary['minutes'], 60);
      expect(jsonDecode(((result['content'] as List).single as Map)['text'] as String), structured);
    });

    test('a bad id is a tool error the model can act on, not a protocol failure', () async {
      final response = await rpc(
        'tools/call',
        params: {
          'name': 'get_workout',
          'arguments': {'workoutId': 'nope'},
        },
      );
      expect(response.status, 200);
      final result = response.body['result'] as Map;
      expect(result['isError'], isTrue);
      expect(((result['content'] as List).single as Map)['text'], contains('list_workouts'));
    });

    test('get_personal_records narrows by name, and says so when nothing matches', () async {
      when(app.db.getRecordSets(userId: 'u1', exerciseId: null)).thenAnswer(
        (_) async => [
          (
            exerciseId: 'a',
            name: 'Bench Press',
            category: Category.barbell,
            sets: [
              const RecordSet(weight: 100, reps: 5, duration: null, distance: null, workoutId: 'w', at: '2026-01-01'),
            ],
          ),
        ],
      );

      final found =
          (await rpc(
                'tools/call',
                params: {
                  'name': 'get_personal_records',
                  'arguments': {'exercise': 'bench'},
                },
              )).body['result']
              as Map;
      final records = (found['structuredContent'] as Map)['records'] as List;
      expect(((records.single as Map)['heaviest'] as Map)['weightKg'], 100);

      final none =
          (await rpc(
                'tools/call',
                params: {
                  'name': 'get_personal_records',
                  'arguments': {'exercise': 'deadlift'},
                },
              )).body['result']
              as Map;
      expect(none['isError'], isTrue);
    });

    test('get_exercise_history pages one exercise, and points elsewhere for ids', () async {
      const exercise = '01900000-0000-7000-8000-000000000001';
      const workout = '01900000-0000-7000-8000-0000000000a1';
      when(app.db.getExerciseHistory(userId: 'u1', exerciseId: exercise, cursor: null, limit: 1)).thenAnswer(
        (_) async => (
          exerciseId: exercise,
          name: 'Bench Press',
          category: Category.barbell,
          sessions: const Page<ExerciseSession>(
            items: [
              (
                workoutId: workout,
                at: '2026-01-01T00:00:00.000Z',
                sets: [
                  RecordSet(weight: 100, reps: 5, duration: null, distance: null, workoutId: workout, at: ''),
                ],
              ),
            ],
            hasMore: true,
          ),
        ),
      );

      final found =
          (await rpc(
                'tools/call',
                params: {
                  'name': 'get_exercise_history',
                  'arguments': {'exerciseId': exercise, 'limit': 1},
                },
              )).body['result']
              as Map;
      final history = found['structuredContent'] as Map;
      expect((history['exercise'] as Map)['name'], 'Bench Press');
      final session = (history['sessions'] as List).single as Map;
      expect(session['sets'], [
        {'weightKg': 100, 'reps': 5},
      ]);
      expect((session['metrics'] as Map)['topSetWeight'], 100);
      expect(history['cursor'], workout);

      final malformed =
          (await rpc(
                'tools/call',
                params: {
                  'name': 'get_exercise_history',
                  'arguments': {'exerciseId': 'bench'},
                },
              )).body['result']
              as Map;
      expect(malformed['isError'], isTrue);
      expect(((malformed['content'] as List).single as Map)['text'], contains('get_personal_records'));
    });

    test('search_exercises searches in the given locale, and says so when nothing matches', () async {
      when(app.config.supportedLocales).thenReturn(['en', 'es']);
      when(app.config.defaultLocale).thenReturn('en');
      when(app.db.getExercises('u1', locale: 'es')).thenAnswer(
        (_) async => {
          'exercises': [
            {
              'id': 'e1',
              'name': 'Peso muerto rumano',
              'category': 'Barbell',
              'target': 'Legs',
              'aliases': ['rdl'],
            },
          ],
          'glossary': <String, Object>{},
        },
      );

      Future<Map> search(Map<String, Object> arguments) async {
        return (await rpc('tools/call', params: {'name': 'search_exercises', 'arguments': arguments})).body['result']
            as Map;
      }

      final found = await search({'query': 'rdl', 'locale': 'es'});
      final exercise = ((found['structuredContent'] as Map)['exercises'] as List).single as Map;
      expect(exercise['name'], 'Peso muerto rumano');
      expect(exercise['match'], 'vocabulary');

      expect((await search({'query': 'zzz', 'locale': 'es'}))['isError'], isTrue);
      expect((await search({'query': 'rdl', 'locale': 'de'}))['isError'], isTrue);
    });

    Future<Map> call(String name, [Map<String, dynamic> arguments = const {}]) async {
      final response = await rpc('tools/call', params: {'name': name, 'arguments': arguments});
      expect(response.status, 200);
      return response.body['result'] as Map;
    }

    String text(Map result) => ((result['content'] as List).single as Map)['text'] as String;

    test('a malformed cursor or an out-of-range limit is a tool error, not an internal one', () async {
      final cursor = await call('list_workouts', {'cursor': 'garbage'});
      expect(cursor['isError'], isTrue);
      expect(text(cursor), contains('cursor'));

      final limit = await call('list_workouts', {'limit': 500});
      expect(limit['isError'], isTrue);
      expect(text(limit), contains('1 to 50'));
      verifyNever(
        app.db.getWorkouts(
          userId: anyNamed('userId'),
          targetUserId: anyNamed('targetUserId'),
          imageUrl: anyNamed('imageUrl'),
          cursor: anyNamed('cursor'),
          limit: anyNamed('limit'),
        ),
      );
    });

    test('get_personal_records pages by exercise name, in the tools\' units and rounded', () async {
      ExerciseRecordSets exercise(String id, String name, double weight) => (
        exerciseId: id,
        name: name,
        category: Category.barbell,
        sets: [RecordSet(weight: weight, reps: 5, duration: null, distance: null, workoutId: 'w', at: '2026-01-01')],
      );
      when(app.db.getRecordSets(userId: 'u1', exerciseId: null)).thenAnswer(
        (_) async => [
          exercise('c', 'Squat', 140),
          exercise('a', 'Bench Press', 81.6466293334961),
          exercise('b', 'Deadlift', 180),
        ],
      );

      final first = (await call('get_personal_records', {'limit': 2}))['structuredContent'] as Map;
      final names = [for (final entry in first['records'] as List) ((entry as Map)['exercise'] as Map)['name']];
      expect(names, ['Bench Press', 'Deadlift']);
      final bench = (first['records'] as List).first as Map;
      expect((bench['heaviest'] as Map)['weightKg'], 81.647);
      expect((bench['heaviest'] as Map).containsKey('weight'), isFalse);
      expect(first['cursor'], 'b');

      final last = (await call('get_personal_records', {'limit': 2, 'cursor': 'b'}))['structuredContent'] as Map;
      expect([for (final entry in last['records'] as List) ((entry as Map)['exercise'] as Map)['name']], ['Squat']);
      expect(last.containsKey('cursor'), isFalse);

      expect((await call('get_personal_records', {'cursor': 'nope'}))['isError'], isTrue);
    });

    test('a span narrows records and history, and a bad one is a tool error', () async {
      when(
        app.db.getRecordSets(userId: 'u1', exerciseId: null, from: DateTime.utc(2025), to: DateTime.utc(2026)),
      ).thenAnswer((_) async => []);

      final records = await call('get_personal_records', {'from': '2025-01-01', 'to': '2026-01-01'});
      expect(records['isError'], isFalse);
      expect((records['structuredContent'] as Map)['records'], isEmpty);

      expect((await call('get_personal_records', {'from': 'last year'}))['isError'], isTrue);
      expect((await call('get_personal_records', {'from': '2026-01-01', 'to': '2025-01-01'}))['isError'], isTrue);
    });

    test('list_goals names the exercise a goal is on', () async {
      const bench = '01900000-0000-7000-8000-000000000001';
      when(app.db.getTargetUserGoals(requesterId: 'u1', targetUserId: 'u1', archived: false)).thenAnswer(
        (_) async => [
          Goal.fromJson({
            'id': 'g1',
            'metric': 'topSetWeight',
            'exerciseId': bench,
            'stages': [
              {'target': 100},
            ],
          }),
          Goal.fromJson({
            'id': 'g2',
            'metric': 'workouts',
            'stages': [
              {'target': 3},
            ],
          }),
        ],
      );
      when(app.db.getExercises('u1')).thenAnswer(
        (_) async => {
          'exercises': [
            {'id': bench, 'name': 'Bench Press'},
          ],
        },
      );

      final goals = ((await call('list_goals'))['structuredContent'] as Map)['goals'] as List;
      expect((goals.first as Map)['exerciseName'], 'Bench Press');
      expect((goals.last as Map).containsKey('exerciseName'), isFalse);
    });

    test('an unknown tool is invalid params', () async {
      final response = await rpc('tools/call', params: {'name': 'delete_everything'});
      expect((response.body['error'] as Map)['code'], -32602);
    });
  });
}
