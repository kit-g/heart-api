import 'dart:convert';

import 'package:heart_models/heart_models.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import '../helpers/app_harness.dart';

void main() {
  late AppHarness app;

  setUp(() async => app = await AppHarness.start());
  tearDown(() => app.stop());

  const one = '01900000-0000-7000-8000-000000000001';
  const two = '01900000-0000-7000-8000-000000000002';

  test('one client who can\'t be worked out leaves the rest of the roster, through the real app', () async {
    when(app.db.getDirtySummaries(coachId: anyNamed('coachId'))).thenAnswer(
      (_) async => [
        (connectionId: one, coachId: 'u1', studentId: 's1', generation: 1, program: null),
        (connectionId: two, coachId: 'u1', studentId: 's2', generation: 1, program: null),
      ],
    );
    when(
      app.db.refreshSummary(
        connectionId: one,
        coachId: anyNamed('coachId'),
        studentId: anyNamed('studentId'),
        generation: anyNamed('generation'),
        programId: anyNamed('programId'),
        programName: anyNamed('programName'),
        programWeek: anyNamed('programWeek'),
        programWeeks: anyNamed('programWeeks'),
        ending: anyNamed('ending'),
      ),
    ).thenThrow(StateError('a bad row'));
    when(
      app.db.refreshSummary(
        connectionId: two,
        coachId: anyNamed('coachId'),
        studentId: anyNamed('studentId'),
        generation: anyNamed('generation'),
        programId: anyNamed('programId'),
        programName: anyNamed('programName'),
        programWeek: anyNamed('programWeek'),
        programWeeks: anyNamed('programWeeks'),
        ending: anyNamed('ending'),
      ),
    ).thenAnswer((_) async {});
    when(
      app.db.getRoster(
        coachId: anyNamed('coachId'),
        reason: anyNamed('reason'),
        former: anyNamed('former'),
        cursor: anyNamed('cursor'),
        limit: anyNamed('limit'),
      ),
    ).thenAnswer(
      (_) async => Page(
        items: [ClientSummary(connectionId: two, studentId: 's2', status: 'active')],
        hasMore: false,
      ),
    );

    final res = await app.send('GET', '/coach/clients');
    expect(res.status, 200);
    expect(((jsonDecode(res.body) as Map)['clients'] as List), hasLength(1));
    verify(
      app.db.refreshSummary(
        connectionId: two,
        coachId: anyNamed('coachId'),
        studentId: anyNamed('studentId'),
        generation: anyNamed('generation'),
        programId: anyNamed('programId'),
        programName: anyNamed('programName'),
        programWeek: anyNamed('programWeek'),
        programWeeks: anyNamed('programWeeks'),
        ending: anyNamed('ending'),
      ),
    ).called(1);
  });

  test('the feed answers through the real app', () async {
    when(app.db.getDirtySummaries(coachId: anyNamed('coachId'))).thenAnswer((_) async => const []);
    when(
      app.db.getCoachFeed(coachId: anyNamed('coachId'), cursor: anyNamed('cursor'), limit: anyNamed('limit')),
    ).thenAnswer((_) async => const Page(items: [], hasMore: false));
    final res = await app.send('GET', '/coach/feed');
    expect(res.status, 200);
  });
}
