import 'package:heart/core/handler.dart';
import 'package:heart/globals/globals.dart';
import 'package:heart/middleware/database.dart';
import 'package:heart/models/errors.dart';
import 'package:heart/routes/skips.dart';
import 'package:heart_models/heart_models.dart';
import 'package:mockito/mockito.dart';
import 'package:relic_core/relic_core.dart';
import 'package:test/test.dart';

import '../helpers/request.dart';
import '../mocks.mocks.dart';

const _meId = 'u1';
const _skipId = '019def00-0000-7000-8000-000000000030';

void main() {
  late MockSkipService service;

  setUp(() => service = MockSkipService());

  Request wire(Request req) {
    return req
      ..user = User(id: _meId)
      ..skipService = service;
  }

  test('a new skip is 201, a replay of it 200', () async {
    var created = true;
    when(
      service.createSkip(userId: anyNamed('userId'), skip: anyNamed('skip')),
    ).thenAnswer((i) async => (i.namedArguments[#skip] as TrainingSkip, created));
    Request body() => wire(jsonRequest(method: Method.post, path: '/skips', body: {'at': '2026-10-14T07:30:00Z'}));

    expect(await createSkip(body()), isA<Created<TrainingSkip>>());
    created = false;
    expect(await createSkip(body()), isA<TrainingSkip>());
  });

  test('lists a page with a cursor', () async {
    when(
      service.getSkips(userId: _meId, cursor: anyNamed('cursor'), limit: anyNamed('limit')),
    ).thenAnswer(
      (_) async => Page(
        items: [TrainingSkip(id: _skipId, at: DateTime.utc(2026, 10, 14))],
        hasMore: true,
      ),
    );

    final page = await getMySkips(wire(jsonRequest(path: '/skips')));

    expect(page.toMap(), containsPair('cursor', _skipId));
    expect(page.toMap()['skips'], hasLength(1));
  });

  test('delete is 204', () async {
    when(service.deleteSkip(userId: anyNamed('userId'), skipId: anyNamed('skipId'))).thenAnswer((_) async {});

    await expectLater(deleteSkipById(wire(jsonRequest(method: Method.delete)), _skipId), throwsA(isA<NoContent>()));
    verify(service.deleteSkip(userId: _meId, skipId: _skipId)).called(1);
  });
}
