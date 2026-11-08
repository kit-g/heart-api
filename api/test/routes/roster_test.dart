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

  void stubRoster() {
    when(
      app.db.getRoster(
        coachId: anyNamed('coachId'),
        reason: anyNamed('reason'),
        former: anyNamed('former'),
        cursor: anyNamed('cursor'),
        limit: anyNamed('limit'),
      ),
    ).thenAnswer((_) async => const Page(items: [], hasMore: false));
  }

  test('a later page reads what the first left, so nobody moves between pages', () async {
    stubRoster();
    final res = await app.send('GET', '/coach/clients?cursor=1:$one');
    expect(res.status, 200);
    verifyNever(app.db.getDirtySummaries(coachId: anyNamed('coachId')));
    final cursor =
        verify(
              app.db.getRoster(
                coachId: anyNamed('coachId'),
                reason: anyNamed('reason'),
                former: anyNamed('former'),
                cursor: captureAnyNamed('cursor'),
                limit: anyNamed('limit'),
              ),
            ).captured.single
            as OrderedCursor;
    expect((cursor.order, cursor.id), (1, one));
  });

  test('former clients show nothing a refresh would change', () async {
    stubRoster();
    expect((await app.send('GET', '/coach/clients?former=true')).status, 200);
    verifyNever(app.db.getDirtySummaries(coachId: anyNamed('coachId')));
  });

  for (final query in ['cursor=99999999999:$one', 'cursor=2:$one', 'cursor=1:not-an-id', 'former=1']) {
    test('$query is refused before anything is worked out', () async {
      final res = await app.send('GET', '/coach/clients?$query');
      expect(res.status, 400);
      verifyNever(app.db.getDirtySummaries(coachId: anyNamed('coachId')));
    });
  }

  test('a feed cursor that is none is refused', () async {
    expect((await app.send('GET', '/coach/feed?cursor=nonsense')).status, 400);
    verifyNever(app.db.getDirtySummaries(coachId: anyNamed('coachId')));
  });

  group('marking a client reviewed', () {
    void stubReviewed({required bool found}) {
      when(
        app.db.markReviewed(coachId: anyNamed('coachId'), connectionId: anyNamed('connectionId'), at: anyNamed('at')),
      ).thenAnswer((_) async => found);
    }

    test('answers 204', () async {
      stubReviewed(found: true);
      expect((await app.send('PUT', '/coach/clients/$one/reviewed', body: const {})).status, 204);
    });

    test('is a 404 for someone who isn\'t their client', () async {
      stubReviewed(found: false);
      expect((await app.send('PUT', '/coach/clients/$one/reviewed', body: const {})).status, 404);
    });

    test('is a 404 for an id that can\'t be one, not a database error', () async {
      final res = await app.send('PUT', '/coach/clients/abc/reviewed', body: const {});
      expect(res.status, 404);
      verifyNever(
        app.db.markReviewed(coachId: anyNamed('coachId'), connectionId: anyNamed('connectionId'), at: anyNamed('at')),
      );
    });
  });
}
