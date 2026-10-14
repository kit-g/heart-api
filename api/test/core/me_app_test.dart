import 'dart:convert';
import 'dart:io';

import 'package:heart/models/changes.dart';
import 'package:heart/models/tokens.dart';
import 'package:heart_models/heart_models.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import '../helpers/app_harness.dart';

/// The `/me` surface end to end: token authentication instead of Firebase, no
/// version gate, rate limiting, and the published workout shape.
void main() {
  late AppHarness app;
  final secret = TokenSecret.mint();
  final now = DateTime.now().toUtc();
  const workoutId = '019a0000-0000-7000-8000-0000000000aa';

  TokenUse use({int minute = 1}) {
    return (
      userId: 'u1',
      resource: null,
      clientId: null,
      scopes: const ['read'],
      purpose: null,
      minuteStart: now,
      minuteCount: minute,
      dayStart: now,
      dayCount: minute,
    );
  }

  Workout workout() {
    return Workout.fromRow(
      {
        'id': workoutId,
        'name': 'Push',
        'started_at': '2026-10-01T10:00:00Z',
        'completed_at': '2026-10-01T11:00:00Z',
        'exercises': [],
        'images': [
          {'id': 'img1', 'key': 'workouts/hashed/img1.jpg', 'workout_id': workoutId},
        ],
      },
      imageUrl: (key) => 'https://media.example/$key',
    );
  }

  setUp(() async {
    app = await AppHarness.start();
    when(app.config.freeApiLimits).thenReturn(ApiLimits.free);
    when(app.config.cdnAssetUrl(any)).thenAnswer((i) => 'https://media.example/${i.positionalArguments.first}');
    when(app.db.useToken(TokenSecret.hash(secret))).thenAnswer((_) async => use());
  });

  tearDown(() => app.stop());

  test('a Firebase token is not accepted on /me', () async {
    final response = await app.send('GET', '/me', token: AppHarness.goodToken);
    expect(response.status, 401);
    expect((jsonDecode(response.body) as Map)['code'], 'invalid_token');
  });

  test('a token reads /me without an app version, even where the version gate is on', () async {
    when(app.config.shouldCheckVersion).thenReturn(true);
    when(app.db.getProfile('u1')).thenAnswer(
      (_) async => User(
        id: 'u1',
        displayName: 'Sam',
        settings: const Settings(unitSystem: MeasurementUnit.metric),
      ),
    );
    when(app.db.getAccountSummary('u1')).thenAnswer(
      (_) async => const AccountSummary(
        collections: {ExportableCollection.workouts: CollectionSummary(count: 412)},
      ),
    );

    final response = await app.send('GET', '/me', token: secret);

    expect(response.status, 200);
    expect(jsonDecode(response.body), {
      'id': 'u1',
      'username': 'Sam',
      'unitSystem': 'metric',
      'counts': {
        'workouts': 412,
        'templates': 0,
        'templateFolders': 0,
        'goals': 0,
        'customExercises': 0,
        'programs': 0,
      },
    });
  });

  test('programs come with where the user stands, computed; one program adds its bases', () async {
    const programId = '01900000-0000-7000-8000-000000000050';
    const session = '01900000-0000-7000-8000-000000000051';
    const bench = '01900000-0000-7000-8000-000000000001';
    const slot = '01900000-0000-7000-8000-000000000052';
    final program = Program(
      id: programId,
      name: 'Getting stronger',
      sessions: [session],
      perWeek: 3,
      rules: {bench: const AddWeight(step: 2.5)},
    );
    when(app.db.getPrograms('u1')).thenAnswer((_) async => [program]);
    when(app.db.getTemplate(userId: 'u1', templateId: session)).thenAnswer(
      (_) async => Template.fromJson(const {
        'id': session,
        'order': 0,
        'name': 'A',
        'exercises': [
          {
            'id': slot,
            'exercise': {'id': bench, 'name': 'Bench Press', 'category': 'Barbell', 'target': 'Chest'},
            'sets': [
              {
                'id': '01900000-0000-7000-8000-000000000053',
                'completed': false,
                'started_at': '2026-10-01T08:00:00.000Z',
                'target': {
                  'reps': {'min': 5, 'max': 5},
                  'share': 0.9,
                },
              },
            ],
          },
        ],
      }),
    );
    when(app.db.getProgram(userId: 'u1', programId: programId)).thenAnswer((_) async => program);
    when(app.db.getProgramMarks(userId: 'u1', programId: programId)).thenAnswer(
      (_) async => [ProgramMark(templateId: session, at: DateTime.utc(2026, 10, 2), isWorkout: true)],
    );
    when(app.db.getProgramActions(userId: 'u1', programId: programId)).thenAnswer((_) async => const []);
    when(app.db.getProgramBases(userId: 'u1', programId: programId)).thenAnswer(
      (_) async => [
        ProgramBase(exerciseId: bench, value: 100, at: DateTime.utc(2026, 10, 1)),
        ProgramBase(exerciseId: bench, value: 102.5, at: DateTime.utc(2026, 10, 2)),
        ProgramBase(exerciseId: bench, slot: slot, value: 80, at: DateTime.utc(2026, 10, 2)),
      ],
    );

    final list = await app.send('GET', '/me/programs', token: secret);
    expect(list.status, 200);
    final listed = ((jsonDecode(list.body) as Map)['programs'] as List).single as Map;
    expect((listed['position'] as Map)['week'], 2, reason: 'its one session is done');
    expect(listed.containsKey('bases'), isFalse);

    final one = await app.send('GET', '/me/programs/$programId', token: secret);
    expect(one.status, 200);
    final bases = (jsonDecode(one.body) as Map)['bases'] as Map;
    expect(bases[bench], {'value': 102.5, 'at': '2026-10-02T00:00:00.000Z', 'exerciseId': bench});
    expect(
      bases[slot],
      {'value': 80, 'at': '2026-10-02T00:00:00.000Z', 'exerciseId': bench, 'slot': slot},
      reason: 'a base kept per occurrence is keyed by its slot, and says which exercise it is',
    );
    expect((jsonDecode(one.body) as Map)['nextSession'], {
      'templateId': session,
      'week': 2,
      'lighter': false,
      'exercises': [
        {
          'slot': slot,
          'exerciseId': bench,
          'base': 80,
          'sets': [
            {
              'target': {
                'reps': {'min': 5, 'max': 5},
                'share': 0.9,
              },
              'weight': 70,
            },
          ],
        },
      ],
    }, reason: "the slot's own base: 90% of 80 is 72, down to the rule's 2.5 kg");
  });

  test("a program's history: each base with its cause and the value before it, actions, skips", () async {
    const programId = '01900000-0000-7000-8000-000000000050';
    const test = '01900000-0000-7000-8000-000000000051';
    const session = '01900000-0000-7000-8000-000000000054';
    const bench = '01900000-0000-7000-8000-000000000001';
    const tested = '01900000-0000-7000-8000-000000000061';
    const worked = '01900000-0000-7000-8000-000000000062';
    const missed = '01900000-0000-7000-8000-000000000063';
    const replay = '01900000-0000-7000-8000-000000000071';
    final program = Program(
      id: programId,
      name: 'Getting stronger',
      sessions: [test, session],
      tests: {test: const ProgramTest()},
    );
    when(app.db.getProgram(userId: 'u1', programId: programId)).thenAnswer((_) async => program);
    when(app.db.getProgramBases(userId: 'u1', programId: programId)).thenAnswer(
      (_) async => [
        ProgramBase(exerciseId: bench, value: 100, workoutId: tested, at: DateTime.utc(2026, 10, 1)),
        ProgramBase(exerciseId: bench, value: 102.5, workoutId: worked, at: DateTime.utc(2026, 10, 2)),
        ProgramBase(exerciseId: bench, value: 92.5, workoutId: missed, at: DateTime.utc(2026, 10, 3)),
        ProgramBase(exerciseId: bench, value: 90, actionId: replay, at: DateTime.utc(2026, 10, 4)),
        ProgramBase(exerciseId: bench, value: 95, at: DateTime.utc(2026, 10, 5)),
      ],
    );
    when(app.db.getProgramActions(userId: 'u1', programId: programId)).thenAnswer(
      (_) async => [ProgramAction(id: replay, kind: .replay, week: 1, at: DateTime.utc(2026, 10, 4))],
    );
    when(app.db.getProgramSkips(userId: 'u1', programId: programId)).thenAnswer(
      (_) async => [
        TrainingSkip(at: DateTime.utc(2026, 10, 6), reason: 'sore', templateId: session, programId: programId),
      ],
    );
    when(app.db.getProgramWorkouts(userId: 'u1', programId: programId)).thenAnswer(
      (_) async => {tested: test, worked: session, missed: session},
    );

    final response = await app.send('GET', '/me/programs/$programId/history', token: secret);
    expect(response.status, 200);
    final body = jsonDecode(response.body) as Map;
    expect(
      [for (final base in body['bases'] as List) ((base as Map)['cause'], base['previous'])],
      [
        ('test', null),
        ('workout', 100),
        ('workout', 102.5),
        ('action', 92.5),
        ('user', 90),
      ],
    );
    expect((body['bases'] as List).first, {
      'exerciseId': bench,
      'value': 100,
      'workoutId': tested,
      'at': '2026-10-01T00:00:00.000Z',
      'cause': 'test',
    });
    expect(body['actions'], [
      {'id': replay, 'kind': 'replay', 'week': 1, 'at': '2026-10-04T00:00:00.000Z'},
    ]);
    expect(body['skips'], [
      {'at': '2026-10-06T00:00:00.000Z', 'reason': 'sore', 'templateId': session},
    ]);

    final missing = await app.send('GET', '/me/programs/nope/history', token: secret);
    expect(missing.status, 404);
  });

  group('the program library (heart-api#259)', () {
    const walking = '01900000-0000-7000-8000-0000000000e1';
    Map<String, dynamic> library() => jsonDecode(File('test/fixtures/programs/library.json').readAsStringSync());

    setUp(() {
      when(app.config.supportedLocales).thenReturn(['en', 'es']);
      when(app.config.defaultLocale).thenReturn('en');
      when(app.db.getExercises('u1', locale: anyNamed('locale'))).thenAnswer(
        (invocation) async => {
          'exercises': [
            {
              'id': walking,
              'key': 'walking',
              'name': invocation.namedArguments[#locale] == 'es' ? 'Caminar' : 'Walking',
            },
            {'id': '01900000-0000-7000-8000-0000000000e9', 'name': 'My own walk'},
          ],
        },
      );
    });

    test('lists the programs, and reads one in full, in the caller\'s language', () async {
      when(app.storage.read()).thenAnswer((_) async => library());

      final list = await app.send('GET', '/me/library/programs', token: secret);
      expect(list.status, 200);
      final programs = (jsonDecode(list.body) as Map)['programs'] as List;
      expect(programs.map((program) => (program as Map)['key']), ['walk_and_move', 'full_body_three']);

      final one = await app.send(
        'GET',
        '/me/library/programs/walk_and_move',
        token: secret,
        extraHeaders: {'accept-language': 'es'},
      );
      expect(one.status, 200);
      final program = jsonDecode(one.body) as Map;
      expect(program['name'], 'Camina y muévete');
      expect((program['exercises'] as Map)['walking'], 'Caminar');
      expect((program['research'] as List).first, containsPair('sources', ['who_2020']));

      final missing = await app.send('GET', '/me/library/programs/nope', token: secret);
      expect(missing.status, 404);
      expect((jsonDecode(missing.body) as Map)['code'], 'library_program_not_found');
    });

    test('before the library is published: an empty list, and no program', () async {
      when(app.storage.read()).thenAnswer((_) async => null);
      final list = await app.send('GET', '/me/library/programs', token: secret);
      expect(jsonDecode(list.body), {'programs': []});
      expect((await app.send('GET', '/me/library/programs/walk_and_move', token: secret)).status, 404);
    });

    test('a copy of a library program carries the research behind it, anchored to the copy', () async {
      const programId = '01900000-0000-7000-8000-000000000050';
      const session = '01900000-0000-7000-8000-000000000051';
      when(app.storage.read()).thenAnswer((_) async => library());
      final program = Program(id: programId, name: 'Walk and move', source: 'walk_and_move', sessions: [session]);
      when(app.db.getProgram(userId: 'u1', programId: programId)).thenAnswer((_) async => program);
      when(app.db.getProgramMarks(userId: 'u1', programId: programId)).thenAnswer((_) async => const []);
      when(app.db.getProgramActions(userId: 'u1', programId: programId)).thenAnswer((_) async => const []);
      when(app.db.getProgramBases(userId: 'u1', programId: programId)).thenAnswer((_) async => const []);
      when(app.db.getTemplate(userId: 'u1', templateId: session)).thenAnswer(
        (_) async =>
            Template.fromJson(const {'id': session, 'order': 0, 'name': 'Walk and strengthen', 'exercises': []}),
      );

      final one = await app.send('GET', '/me/programs/$programId', token: secret);
      expect(one.status, 200);
      final research = (jsonDecode(one.body) as Map)['research'] as Map;
      expect(research['key'], 'walk_and_move');
      final claims = (research['claims'] as List).cast<Map>();
      expect(claims[1]['about'], [
        {'on': 'grows'},
        {'on': 'rule', 'exercise': walking},
      ]);
      expect(claims[2]['about'], [
        {'on': 'week'},
        {'on': 'session', 'session': session},
      ], reason: 'the second session the claim names is not in this copy');
      expect((research['sources'] as Map)['otago_2022'], containsPair('year', isA<int>()));
      expect((jsonDecode(one.body) as Map)['nextSession'], containsPair('templateId', session));
    });
  });

  test('workouts are paginated and images keep only id and url', () async {
    when(
      app.db.getWorkouts(
        userId: 'u1',
        targetUserId: 'u1',
        imageUrl: anyNamed('imageUrl'),
        cursor: null,
        limit: 30,
      ),
    ).thenAnswer((_) async => Page(items: [workout()], hasMore: false));

    final response = await app.send('GET', '/me/workouts', token: secret);

    expect(response.status, 200);
    expect(response.body, isNot(contains('"key"')));
    expect(response.body, isNot(contains('"workoutId"')));
    final body = jsonDecode(response.body) as Map;
    final images = ((body['workouts'] as List).single as Map)['images'] as List;
    expect(images.single, {'id': 'img1', 'url': 'https://media.example/workouts/hashed/img1.jpg'});
  });

  test('over the limit is a 429 with Retry-After', () async {
    when(app.db.useToken(TokenSecret.hash(secret))).thenAnswer((_) async => use(minute: 21));

    final response = await app.send('GET', '/me', token: secret);

    expect(response.status, 429);
    expect(int.parse(response.headers['retry-after']!), inInclusiveRange(1, 60));
  });

  test('the token routes themselves stay behind Firebase', () async {
    final response = await app.send('GET', '/accounts/tokens', token: secret);
    expect(response.status, 401);
  });

  test('/workouts/changes is the feed, not a workout id', () async {
    when(
      app.db.getWorkoutChanges(
        userId: 'u1',
        since: null,
        limit: 100,
        imageUrl: anyNamed('imageUrl'),
      ),
    ).thenAnswer((_) async => const WorkoutChanges(upserted: [], deleted: [], cursor: null, hasMore: false));

    final response = await app.send('GET', '/me/workouts/changes', token: secret);

    expect(response.status, 200);
    expect(jsonDecode(response.body), {'workouts': [], 'deleted': [], 'hasMore': false});
  });
}
