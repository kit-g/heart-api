@Tags(['db'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:heart/core/app.dart';
import 'package:heart/globals/firebase.dart';
import 'package:heart/middleware/aws.dart';
import 'package:heart/publish/exercise_library.dart';
import 'package:heart_models/heart_models.dart';
import 'package:heart_aws/heart_aws.dart';
import 'package:mockito/mockito.dart';
import 'package:relic/relic.dart';
import 'package:test/test.dart';

import '../mocks.mocks.dart';
import 'db_test_utility.dart';

void main() {
  final h = _Harness();
  late String owner;
  late String stranger;
  late String exerciseId;
  late RelicApp app;
  late RelicServer server;

  setUpAll(() async {
    await h.setupDatabase();
    owner = await h.seedProfile();
    stranger = await h.seedProfile();
    exerciseId = await h.seedGlobalExercise(name: h.uniqueName('Compatibility Bench'));
    final config = MockAppConfig();
    when(config.minimalAppVersion).thenReturn('1.13.0');
    when(config.shouldCheckVersion).thenReturn(true);
    when(config.firebaseProjectId).thenReturn('test-project');
    when(config.allowedOrigins).thenReturn(const {});
    when(config.oauth).thenReturn(null);
    when(config.cdnAssetUrl(any)).thenAnswer((call) => 'https://cdn.example/${call.positionalArguments.single}');
    app = buildApp(
      config: config,
      aws: AwsConfig(credentialsProvider: const AWSCredentialsProvider.defaultChain(), region: 'us-east-1'),
      database: h.db,
      storage: MockStorage(),
      eventPublisher: MockEventPublisher(),
      apple: MockAppleIdentityService(),
      auth: (_, token) async => switch (token) {
        'owner' => User(id: owner),
        'stranger' => User(id: stranger),
        _ => throw AuthenticationError(),
      },
    );
    server = await app.serve(port: 0);
  });

  tearDownAll(() async {
    await app.close();
    await h.teardownDatabase();
  });

  Future<({int status, Map<String, dynamic> body})> send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    String token = 'owner',
  }) async {
    final client = HttpClient();
    try {
      final request = await client.openUrl(method, Uri.parse('http://127.0.0.1:${server.port}$path'));
      request.headers.set('authorization', 'Bearer $token');
      request.headers.set('x-app-version', '1.13.0');
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(body));
      }
      final response = await request.close();
      final text = await response.transform(utf8.decoder).join();
      return (status: response.statusCode, body: jsonDecode(text) as Map<String, dynamic>);
    } finally {
      client.close(force: true);
    }
  }

  Map<String, dynamic> requestBody() {
    final body = jsonDecode(
      File('test/compatibility/mobile_1_13/workout-save.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    body['id'] = uuidV7();
    final exercise = (body['exercises'] as List).single as Map<String, dynamic>;
    exercise['id'] = uuidV7();
    (exercise['exercise'] as Map)['id'] = exerciseId;
    ((exercise['sets'] as List).single as Map)['id'] = uuidV7();
    return body;
  }

  test('1.13 creates, retries, reads and saves through HTTP without losing newer fields', () async {
    final body = requestBody();
    final created = await send('POST', '/workouts', body: body);
    expect(created.status, 201, reason: jsonEncode(created.body));
    expect(created.body['id'], body['id']);
    final retry = await send('POST', '/workouts', body: {...body, 'name': 'Retry must not overwrite'});
    expect(retry.status, 200);
    expect(retry.body['name'], 'Compatibility session');

    final (program, _) = await h.db.createProgramOrExisting(
      userId: owner,
      program: Program(name: 'Newer client program'),
      sessions: [TemplateRequest(userId: owner, name: 'A')],
    );
    await h.exec(
      'UPDATE workouts SET program_id = @p::uuid, template_id = @t::uuid WHERE id = @w::uuid',
      {'p': program.id, 't': program.sessions.single, 'w': body['id']},
    );
    await h.exec(
      'UPDATE workout_exercises SET superset = 2 WHERE workout_id = @w::uuid',
      {'w': body['id']},
    );
    // a target the set aimed for, which 1.13 predates (heart-api#286)
    await h.exec(
      'UPDATE exercise_sets es '
      'SET target = \'{"reps": {"min": 6, "max": 10}}\' '
      'FROM workout_exercises we WHERE we.id = es.workout_exercise_id AND we.workout_id = @w::uuid',
      {'w': body['id']},
    );

    final response = await send('GET', '/workouts/${body['id']}');
    expect(response.status, 200);
    final old = await _oldClient('workout', response.body);
    expect(old['unread'], 0, reason: 'tolerant reads must not hide a broken known shape');
    final exercises = (old['exercises'] as List).cast<Map>();
    expect(exercises, hasLength(1));
    expect(exercises.single['id'], exerciseId);
    expect(exercises.single['unread'], 0);
    final set = ((exercises.single['sets'] as List).single as Map);
    final sentExercise = (body['exercises'] as List).single as Map;
    expect(set, (sentExercise['sets'] as List).single);

    final save = old['save'] as Map<String, dynamic>;
    for (final field in ['id', 'name', 'start', 'end', 'note', 'pauses']) {
      expect(save[field], body[field], reason: '1.13 must still read $field');
    }
    expect(save.containsKey('templateId'), isFalse);
    expect(save.containsKey('programId'), isFalse);
    expect(((save['exercises'] as List).single as Map).containsKey('superset'), isFalse);
    expect((((save['exercises'] as List).single as Map)['sets'] as List).single, isNot(contains('target')));
    save['name'] = 'Edited by 1.13';
    final updated = await send('PUT', '/workouts/${body['id']}', body: save);
    expect(updated.status, 200, reason: jsonEncode(updated.body));

    final stored = await h.db.getWorkout(userId: owner, workoutId: body['id'] as String, imageUrl: (key) => key);
    expect(stored.name, 'Edited by 1.13');
    expect(stored.programId, program.id);
    expect(stored.templateId, program.sessions.single);
    expect(stored.single.superset, 2);
    expect(stored.single.single.id, set['id']);
    expect(stored.single.single.weight, 80);
    expect(stored.single.single.isCompleted, isTrue);
    expect(stored.single.single.target?[.reps], const TargetRange(min: 6, max: 10));
    expect(stored.note, 'A synthetic compatibility fixture');
    expect(stored.pauses, hasLength(1));
  });

  test('1.13 receives stable status and error codes for a foreign id and health data', () async {
    final body = requestBody();
    expect((await send('POST', '/workouts', body: body)).status, 201);
    final foreign = await send('POST', '/workouts', body: body, token: 'stranger');
    expect(foreign.status, 403);
    expect(foreign.body['code'], 'id_taken');

    final rejected = requestBody()..['heartRate'] = 120;
    final health = await send('POST', '/workouts', body: rejected);
    expect(health.status, 400);
    expect(health.body['code'], 'health_data');
    final rows = await h.exec('SELECT id FROM workouts WHERE id = @id::uuid', {'id': rejected['id']});
    expect(rows, isEmpty);
  });

  test('1.13 reads the current CDN publication without dropping known exercises', () async {
    final publication = await renderLibraryPublication(
      service: h.db,
      locales: const ['en'],
      version: 'compatibility-test',
      generatedAt: DateTime.utc(2026, 10, 1),
    );
    final old = await _oldClient('library', jsonDecode(publication.localeFiles['en']!) as Map<String, dynamic>);
    final exercises = (old['exercises'] as List).cast<Map>();
    final exercise = exercises.singleWhere((row) => row['id'] == exerciseId);
    expect(exercise['name'], contains('Compatibility Bench'));
    expect(exercise['key'], startsWith('itest-compatibility-bench'));
    expect(exercise['category'], 'Barbell');
    expect(exercise['target'], 'Chest');
  });
}

Future<Map<String, dynamic>> _oldClient(String operation, Map<String, dynamic> body) async {
  const directory = 'test/compatibility/mobile_1_13';
  expect(
    File('$directory/.dart_tool/package_config.json').existsSync(),
    isTrue,
    reason: 'run make prepare-compat-tests at the repository root',
  );
  final process = await Process.start(
    Platform.resolvedExecutable,
    ['--packages=$directory/.dart_tool/package_config.json', '$directory/client.dart', operation],
  );
  final output = process.stdout.transform(utf8.decoder).join();
  final errors = process.stderr.transform(utf8.decoder).join();
  process.stdin.write(jsonEncode(body));
  await process.stdin.close();
  final code = await process.exitCode;
  expect(code, 0, reason: await errors);
  return jsonDecode(await output) as Map<String, dynamic>;
}

class _Harness extends DatabaseTestBase;
