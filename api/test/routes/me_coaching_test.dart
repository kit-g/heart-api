import 'package:heart/globals/config.dart';
import 'package:heart/globals/globals.dart';
import 'package:heart/middleware/database.dart';
import 'package:heart/models/changes.dart';
import 'package:heart/models/errors.dart';
import 'package:heart/routes/me_index.dart';
import 'package:heart_models/heart_models.dart';
import 'package:mockito/mockito.dart';
import 'package:relic_core/relic_core.dart';
import 'package:test/test.dart';

import '../helpers/request.dart';
import '../mocks.mocks.dart';

/// `/me/coaching`: a coach's reads, each as the coach's assistant reads, held to
/// the shapes the reference publishes.
void main() {
  late MockRosterService roster;
  late MockApiWorkoutService workouts;
  late MockProgramChangeService copies;
  late MockIdempotentGoalService goals;
  late MockCoachLibraryService library;
  late MockAppConfig config;

  const client = 'student-1';
  const programId = '01900000-0000-7000-8000-0000000000c1';
  const workoutId = '01900000-0000-7000-8000-0000000000c2';
  const yours = '01900000-0000-7000-8000-0000000000c3';
  const theirs = '01900000-0000-7000-8000-0000000000c4';

  setUp(() {
    roster = MockRosterService();
    workouts = MockApiWorkoutService();
    copies = MockProgramChangeService();
    goals = MockIdempotentGoalService();
    library = MockCoachLibraryService();
    config = MockAppConfig();
    when(config.cdnAssetUrl(any)).thenAnswer((i) => 'https://media.example/${i.positionalArguments.first}');
    when(roster.getDirtySummaries(coachId: anyNamed('coachId'))).thenAnswer((_) async => const []);
  });

  Request build({Map<String, String> query = const {}}) {
    return bareRequest(method: Method.get, query: query)
      ..user = User(id: 'u1')
      ..scopes = const ['read', 'read:coaching']
      ..config = config
      ..rosterService = roster
      ..workoutsService = workouts
      ..programChangeService = copies
      ..goalService = goals
      ..coachLibraryService = library;
  }

  Future<Map<String, dynamic>> serve(
    String route, {
    Map<String, String> path = const {},
    Map<String, String> query = const {},
  }) async {
    return (await meRoutes[(route, Method.get)]!.call(build(query: query), path: path))!.toMap();
  }

  Workout workout({String? loggedBy}) {
    return Workout.fromRow({
      'id': workoutId,
      'name': 'Legs',
      'started_at': '2026-11-01T10:00:00Z',
      'completed_at': '2026-11-01T11:00:00Z',
      'logged_by': loggedBy,
      'exercises': <Object>[],
    }, imageUrl: (key) => key);
  }

  Template session(String id, {required String by}) {
    return Template.fromJson({
      'id': id,
      'order': 0,
      'name': 'Session $id',
      'assignedBy': {'id': by, 'username': by},
      'exercises': <Object>[],
    });
  }

  test('the roster is read as the assistant reads it, and pages by rank', () async {
    when(roster.getRoster(coachId: 'u1', former: false, limit: 50, assistant: true)).thenAnswer(
      (_) async => Page(
        items: [
          ClientSummary(
            connectionId: '01900000-0000-7000-8000-0000000000d1',
            studentId: client,
            name: 'Alex',
            status: 'active',
            acceptedAt: DateTime.utc(2026, 10),
            programName: 'Strength',
            programWeek: 3,
            programWeeks: 8,
            recent: [DateTime.utc(2026, 11, 2)],
            reasons: const ['note'],
            assistant: true,
          ),
        ],
        hasMore: true,
      ),
    );

    final page = await serve('/coaching/clients');

    expect((page['clients'] as List).single, {
      'clientId': client,
      'name': 'Alex',
      'status': 'active',
      'since': '2026-10-01T00:00:00.000Z',
      'sharesWithAssistant': true,
      'program': {'name': 'Strength', 'week': 3, 'weeks': 8},
      'recent': ['2026-11-02T00:00:00.000Z'],
      'reasons': ['note'],
    });
    expect(page['cursor'], '0:01900000-0000-7000-8000-0000000000d1');
    verify(roster.getDirtySummaries(coachId: 'u1')).called(1);
  });

  test('the feed is read as the assistant reads it', () async {
    when(roster.getCoachFeed(coachId: 'u1', limit: 50, assistant: true)).thenAnswer(
      (_) async => Page(
        items: [
          CoachFeedItem(
            kind: 'workout',
            id: workoutId,
            studentId: client,
            name: 'Alex',
            at: DateTime.utc(2026, 11, 2),
            title: 'Legs',
            cursor: '2026-11-02T00:00:00.000Z|$workoutId',
          ),
        ],
        hasMore: true,
      ),
    );

    final feed = await serve('/coaching/feed');

    expect((feed['items'] as List).single, {
      'kind': 'workout',
      'id': workoutId,
      'clientId': client,
      'name': 'Alex',
      'at': '2026-11-02T00:00:00.000Z',
      'title': 'Legs',
    });
    expect(feed['cursor'], '2026-11-02T00:00:00.000Z|$workoutId');
  });

  test("a client's workouts say which the coach logged, and who logged the rest stays out", () async {
    when(
      workouts.getWorkouts(
        userId: 'u1',
        targetUserId: client,
        imageUrl: anyNamed('imageUrl'),
        limit: 30,
        assistant: true,
      ),
    ).thenAnswer(
      (_) async => Page(
        items: [
          workout(loggedBy: 'u1'),
          workout(loggedBy: 'coach-2'),
        ],
        hasMore: false,
      ),
    );

    final page = await serve('/coaching/clients/:clientId/workouts', path: {'clientId': client});

    final [mine, another] = (page['workouts'] as List).cast<Map>();
    expect(mine['loggedByYou'], isTrue);
    expect(another, isNot(contains('loggedByYou')));
    expect(another, isNot(contains('loggedBy')));
  });

  test("the user's own id is no client, and is refused before anything is read", () {
    expect(
      () => serve('/coaching/clients/:clientId/workouts', path: {'clientId': 'u1'}),
      throwsA(isA<Forbidden>().having((e) => e.code, 'code', 'not_shared')),
    );
    verifyNever(
      workouts.getWorkouts(
        userId: anyNamed('userId'),
        targetUserId: anyNamed('targetUserId'),
        imageUrl: anyNamed('imageUrl'),
        assistant: anyNamed('assistant'),
      ),
    );
  });

  test("a client who doesn't share is not_shared, and a workout that can't be one is missing", () async {
    when(
      workouts.getTargetWorkout(
        requesterId: 'u1',
        targetUserId: client,
        workoutId: workoutId,
        imageUrl: anyNamed('imageUrl'),
        assistant: true,
      ),
    ).thenThrow(const Forbidden(reason: 'no'));

    await expectLater(
      serve('/coaching/clients/:clientId/workouts/:workoutId', path: {'clientId': client, 'workoutId': workoutId}),
      throwsA(isA<Forbidden>().having((e) => e.code, 'code', 'not_shared')),
    );
    await expectLater(
      serve('/coaching/clients/:clientId/workouts/:workoutId', path: {'clientId': client, 'workoutId': 'x'}),
      throwsA(isA<NotFound>()),
    );
  });

  test('a program is read in one snapshot, with what is done and what the coach sent', () async {
    when(copies.readCopy(coachId: 'u1', studentId: client, programId: programId, assistant: true)).thenAnswer(
      (_) async => (
        program: Program(id: programId, name: 'Strength', sessions: const [yours, theirs], coachId: 'u1'),
        sessions: [
          session(yours, by: 'u1'),
          session(theirs, by: 'coach-2'),
        ],
        actions: const <ProgramAction>[],
        marks: const <ProgramMark>[],
      ),
    );
    when(copies.getCopies(coachId: 'u1', studentId: client, assistant: true)).thenAnswer(
      (_) async => [
        Program(id: programId, name: 'Strength', sessions: const [yours, theirs]),
      ],
    );

    final listed = await serve('/coaching/clients/:clientId/programs', path: {'clientId': client});
    expect(listed['programs'], [
      {'id': programId, 'name': 'Strength', 'archived': false, 'sessions': 2},
    ]);

    final program = await serve(
      '/coaching/clients/:clientId/programs/:programId',
      path: {'clientId': client, 'programId': programId},
    );
    expect(program['position'], containsPair('week', 1));
    final [sent, other] = (program['sessions'] as List).cast<Map>();
    expect(sent, allOf(containsPair('sentByYou', true), containsPair('done', false), containsPair('id', yours)));
    expect(other, isNot(contains('sentByYou')));
  });

  test("a program the coach didn't send is missing, and its history says who changed what", () async {
    final since = const ChangeCursor(xid: '7', id: '01900000-0000-7000-8000-0000000000e1').toString();
    when(
      copies.readCopy(coachId: 'u1', studentId: client, programId: programId, assistant: true),
    ).thenThrow(const NotFound(type: 'Program', id: programId, code: 'program_not_found'));
    await expectLater(
      serve('/coaching/clients/:clientId/programs/:programId', path: {'clientId': client, 'programId': programId}),
      throwsA(isA<NotFound>().having((e) => e.code, 'code', 'program_not_found')),
    );

    when(
      copies.getProgramChanges(
        ownerId: client,
        programId: programId,
        since: since,
        readerId: 'u1',
        assistant: true,
      ),
    ).thenAnswer(
      (_) async => Page(
        items: [
          ProgramChange(
            id: '01900000-0000-7000-8000-0000000000f2',
            programId: programId,
            sessionId: yours,
            actorId: client,
            kind: 'edit',
            revision: 2,
            before: const {'name': 'A'},
            after: const {'name': 'B'},
            at: DateTime.utc(2026, 11, 3),
          ),
          ProgramChange(
            id: '01900000-0000-7000-8000-0000000000f3',
            programId: programId,
            actorId: 'u1',
            kind: 'library_update',
            revision: 3,
            at: DateTime.utc(2026, 11, 4),
            cursor: 'next',
          ),
          ProgramChange(
            id: '01900000-0000-7000-8000-0000000000f4',
            programId: programId,
            kind: 'edit',
            revision: 4,
            at: DateTime.utc(2026, 11, 5),
            cursor: 'last',
          ),
        ],
        hasMore: true,
      ),
    );
    final history = await serve(
      '/coaching/clients/:clientId/programs/:programId/changes',
      path: {'clientId': client, 'programId': programId},
      query: {'since': since},
    );
    expect(history['changes'], [
      {
        'id': '01900000-0000-7000-8000-0000000000f2',
        'at': '2026-11-03T00:00:00.000Z',
        'by': 'client',
        'kind': 'edit',
        'sessionId': yours,
        'before': {'name': 'A'},
        'after': {'name': 'B'},
      },
      {
        'id': '01900000-0000-7000-8000-0000000000f3',
        'at': '2026-11-04T00:00:00.000Z',
        'by': 'you',
        'kind': 'library_update',
      },
      {'id': '01900000-0000-7000-8000-0000000000f4', 'at': '2026-11-05T00:00:00.000Z', 'kind': 'edit'},
    ]);
    expect(history['cursor'], 'last');
    expect(history['hasMore'], isTrue);

    // nothing new: the same cursor back, to poll with again
    when(
      copies.getProgramChanges(ownerId: client, programId: programId, since: since, readerId: 'u1', assistant: true),
    ).thenAnswer((_) async => const Page(items: <ProgramChange>[], hasMore: false));
    final quiet = await serve(
      '/coaching/clients/:clientId/programs/:programId/changes',
      path: {'clientId': client, 'programId': programId},
      query: {'since': since},
    );
    expect(quiet, {'changes': <Object>[], 'cursor': since, 'hasMore': false});

    expect(
      () => serve(
        '/coaching/clients/:clientId/programs/:programId/changes',
        path: {'clientId': client, 'programId': programId},
        query: {'since': 'from-here'},
      ),
      throwsA(isA<BadRequest>()),
      reason: 'a cursor that cannot be one is never a fresh start',
    );
  });

  test("an empty list of programs is told apart from a client who doesn't share", () async {
    when(copies.getCopies(coachId: 'u1', studentId: client, assistant: true)).thenAnswer((_) async => []);
    when(
      workouts.getWorkouts(
        userId: 'u1',
        targetUserId: client,
        imageUrl: anyNamed('imageUrl'),
        limit: 1,
        assistant: true,
      ),
    ).thenAnswer((_) async => const Page(items: <Workout>[], hasMore: false));
    expect(await serve('/coaching/clients/:clientId/programs', path: {'clientId': client}), {'programs': <Object>[]});

    when(
      workouts.getWorkouts(
        userId: 'u1',
        targetUserId: client,
        imageUrl: anyNamed('imageUrl'),
        limit: 1,
        assistant: true,
      ),
    ).thenThrow(const Forbidden(reason: 'no'));
    await expectLater(
      serve('/coaching/clients/:clientId/programs', path: {'clientId': client}),
      throwsA(isA<Forbidden>().having((e) => e.code, 'code', 'not_shared')),
    );
  });

  test('goals need the goals share too', () async {
    when(
      goals.getTargetUserGoals(requesterId: 'u1', targetUserId: client, archived: false, assistant: true),
    ).thenThrow(const Forbidden(reason: 'no'));

    await expectLater(
      serve('/coaching/clients/:clientId/goals', path: {'clientId': client}),
      throwsA(isA<Forbidden>().having((e) => e.reason, 'reason', contains('their goals'))),
    );
  });

  test("the coach's library: listed, and one in full with the server's own say over its body", () async {
    when(library.getCoachPrograms(coachId: 'u1', limit: 30)).thenAnswer(
      (_) async => Page(
        items: [CoachProgram(id: programId, name: 'Strength', version: 2, updatedAt: DateTime.utc(2026, 11))],
        hasMore: true,
      ),
    );
    final listed = await serve('/coaching/library');
    expect(listed, {
      'programs': [
        {'id': programId, 'name': 'Strength', 'version': 2, 'updatedAt': '2026-11-01T00:00:00.000Z'},
      ],
      'cursor': programId,
    });

    when(library.getCoachProgram(coachId: 'u1', id: programId)).thenAnswer(
      (_) async => CoachProgram(
        id: programId,
        name: 'Strength',
        version: 2,
        updatedAt: DateTime.utc(2026, 11),
        body: const {
          'version': 99,
          'sessions': [
            {'name': 'A'},
          ],
        },
      ),
    );
    final one = await serve('/coaching/library/:programId', path: {'programId': programId});
    expect(one['version'], 2);
    expect(one['sessions'], [
      {'name': 'A'},
    ]);

    when(
      library.getCoachProgram(coachId: 'u1', id: yours),
    ).thenThrow(const NotFound(type: 'Library program', id: yours));
    await expectLater(
      serve('/coaching/library/:programId', path: {'programId': yours}),
      throwsA(isA<NotFound>().having((e) => e.code, 'code', 'program_not_found')),
    );
  });
}
