import 'dart:convert';

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
    final program = Program(id: programId, name: 'Getting stronger', sessions: [session], perWeek: 3);
    when(app.db.getPrograms('u1')).thenAnswer((_) async => [program]);
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
