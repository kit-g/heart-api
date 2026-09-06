import 'package:heart/core/handler.dart';
import 'package:heart/globals/globals.dart';
import 'package:heart/middleware/database.dart';
import 'package:heart/models/errors.dart';
import 'package:heart/routes/templates.dart';
import 'package:heart_models/heart_models.dart';
import 'package:mockito/mockito.dart';
import 'package:relic_core/relic_core.dart';
import 'package:test/test.dart';

import '../helpers/request.dart';
import '../mocks.mocks.dart';

const _meId = 'u1';

Template _fakeTemplate(String id, {int order = 0}) => Template.empty(id: id, order: order);

// A well-formed v7 uuid, the shape the app mints for the client-side id
// (heart-api#66) — distinct from '_fakeTemplate's ids, which are never
// validated as uuids.
const _v7Id = '019def00-0000-7000-8000-0000000000f1';

TemplateShare _fakeShare(String id) => TemplateShare(
  id: id,
  masterTemplateId: 'm-$id',
  studentTemplateId: 'ts-$id',
  templateName: 'Push',
  assignedTo: Profile.fromJson({'id': 's1', 'username': 'Stu', 'avatar': null}),
  assignedAt: DateTime.utc(2026, 1, 1),
);

void main() {
  late MockIdempotentTemplateService templates;

  setUp(() => templates = MockIdempotentTemplateService());

  Request wire(Request req) => req
    ..user = User(id: _meId)
    ..templatesService = templates;

  Request getReq(String path, {Map<String, String> query = const {}}) =>
      wire(bareRequest(method: Method.get, path: path, query: query));

  Request bodyReq(Map<String, dynamic> body, {Method method = Method.post}) =>
      wire(jsonRequest(method: method, path: '/templates', body: body));

  group('createTemplate', () {
    void stub((Template, bool) answer) {
      when(
        templates.createTemplateOrExisting(userId: anyNamed('userId'), body: anyNamed('body')),
      ).thenAnswer((_) async => answer);
    }

    test('a fresh id inserts and responds 201', () async {
      final template = _fakeTemplate('t-1');
      stub((template, true));

      final result = await createTemplate(bodyReq({'id': _v7Id, 'name': 'Push'}));

      expect(result, isA<Created<Template>>());
      expect((result as Created<Template>).value, same(template));
      verify(templates.createTemplateOrExisting(userId: _meId, body: anyNamed('body'))).called(1);
    });

    test('a replayed id resolves to the existing template and responds 200, not 201', () async {
      final template = _fakeTemplate('t-1');
      stub((template, false));

      final result = await createTemplate(bodyReq({'id': _v7Id, 'name': 'Push'}));

      expect(result, same(template));
      expect(result, isNot(isA<Created<Template>>()));
    });

    test('an id belonging to another account is Forbidden with id_taken', () async {
      when(
        templates.createTemplateOrExisting(userId: anyNamed('userId'), body: anyNamed('body')),
      ).thenThrow(const Forbidden(code: 'id_taken', reason: 'this id belongs to another account'));

      await expectLater(
        createTemplate(bodyReq({'id': _v7Id, 'name': 'Push'})),
        throwsA(isA<Forbidden>().having((e) => e.code, 'code', 'id_taken')),
      );
    });

    test('a malformed id is rejected before reaching the service', () async {
      await expectLater(
        createTemplate(bodyReq({'id': 'not-a-uuid', 'name': 'Push'})),
        throwsA(isA<BadRequest>()),
      );
      verifyNever(templates.createTemplateOrExisting(userId: anyNamed('userId'), body: anyNamed('body')));
    });
  });

  group('getMyTemplates', () {
    void stub(Page<Template> page) {
      when(
        templates.getTemplates(
          userId: anyNamed('userId'),
          cursor: anyNamed('cursor'),
          limit: anyNamed('limit'),
          folderId: anyNamed('folderId'),
          unfiledOnly: anyNamed('unfiledOnly'),
        ),
      ).thenAnswer((_) async => page);
    }

    test('omits cursor when there is no next page', () async {
      stub(Page(items: [_fakeTemplate('t-1')], hasMore: false));

      final result = await getMyTemplates(getReq('/templates'));

      expect(result.toMap()['templates'], hasLength(1));
      expect(result.toMap().containsKey('cursor'), isFalse);
    });

    test('emits the last template\'s order and id as cursor when there is a next page', () async {
      stub(Page(items: [_fakeTemplate('t-1'), _fakeTemplate('t-2', order: 4)], hasMore: true));

      final result = await getMyTemplates(getReq('/templates'));

      // Both halves matter: the listing walks (order, id), not id alone.
      expect(result.toMap()['cursor'], '4:t-2');
    });

    test('clamps limit to the max and passes the cursor through', () async {
      stub(const Page(items: [], hasMore: false));

      await getMyTemplates(getReq('/templates', query: {'limit': '999', 'cursor': '3:t-9'}));

      final sent =
          verify(
                templates.getTemplates(
                  userId: _meId,
                  cursor: captureAnyNamed('cursor'),
                  limit: 100,
                  folderId: null,
                  unfiledOnly: false,
                ),
              ).captured.single
              as OrderedCursor;
      expect(sent.order, 3);
      expect(sent.id, 't-9');
    });

    test('rejects a cursor the client made up', () async {
      stub(const Page(items: [], hasMore: false));

      await expectLater(
        getMyTemplates(getReq('/templates', query: {'cursor': 'not-a-cursor'})),
        throwsA(isA<BadRequest>()),
      );
    });

    test('a cursor round-trips through the wire form it emitted', () async {
      stub(Page(items: [_fakeTemplate('t-1', order: 7)], hasMore: true));
      final emitted = (await getMyTemplates(getReq('/templates'))).toMap()['cursor'] as String;

      stub(const Page(items: [], hasMore: false));
      await getMyTemplates(getReq('/templates', query: {'cursor': emitted}));

      final sent =
          verify(
                templates.getTemplates(
                  userId: _meId,
                  cursor: captureAnyNamed('cursor'),
                  limit: anyNamed('limit'),
                  folderId: anyNamed('folderId'),
                  unfiledOnly: anyNamed('unfiledOnly'),
                ),
              ).captured.last
              as OrderedCursor;
      expect(sent.order, 7);
      expect(sent.id, 't-1');
    });

    test('defaults to a limit of 30 with no cursor when unspecified', () async {
      stub(const Page(items: [], hasMore: false));

      await getMyTemplates(getReq('/templates'));

      verify(
        templates.getTemplates(userId: _meId, cursor: null, limit: 30, folderId: null, unfiledOnly: false),
      ).called(1);
    });

    test('no folder param lists every template, filed or not', () async {
      stub(const Page(items: [], hasMore: false));

      await getMyTemplates(getReq('/templates'));

      verify(
        templates.getTemplates(
          userId: _meId,
          cursor: anyNamed('cursor'),
          limit: anyNamed('limit'),
          folderId: null,
          unfiledOnly: false,
        ),
      ).called(1);
    });

    test('folder=<id> narrows the listing to that folder', () async {
      stub(const Page(items: [], hasMore: false));

      await getMyTemplates(getReq('/templates', query: {'folder': 'f-1'}));

      verify(
        templates.getTemplates(
          userId: _meId,
          cursor: anyNamed('cursor'),
          limit: anyNamed('limit'),
          folderId: 'f-1',
          unfiledOnly: false,
        ),
      ).called(1);
    });

    test('folder=none narrows the listing to the unfiled ones', () async {
      stub(const Page(items: [], hasMore: false));

      await getMyTemplates(getReq('/templates', query: {'folder': 'none'}));

      verify(
        templates.getTemplates(
          userId: _meId,
          cursor: anyNamed('cursor'),
          limit: anyNamed('limit'),
          folderId: null,
          unfiledOnly: true,
        ),
      ).called(1);
    });

    test('an empty folder param is treated as absent', () async {
      stub(const Page(items: [], hasMore: false));

      await getMyTemplates(getReq('/templates', query: {'folder': ''}));

      verify(
        templates.getTemplates(
          userId: _meId,
          cursor: anyNamed('cursor'),
          limit: anyNamed('limit'),
          folderId: null,
          unfiledOnly: false,
        ),
      ).called(1);
    });
  });

  group('getMyTemplateShares', () {
    void stub(Page<TemplateShare> page) {
      when(
        templates.getTemplateShares(userId: anyNamed('userId'), cursor: anyNamed('cursor'), limit: anyNamed('limit')),
      ).thenAnswer((_) async => page);
    }

    test('emits the last share id as cursor when there is a next page', () async {
      stub(Page(items: [_fakeShare('share-1'), _fakeShare('share-2')], hasMore: true));

      final result = await getMyTemplateShares(getReq('/templates/shares'));

      expect(result.toMap()['shares'], hasLength(2));
      expect(result.toMap()['cursor'], 'share-2');
    });

    test('omits cursor when the list is exhausted', () async {
      stub(Page(items: [_fakeShare('share-1')], hasMore: false));

      final result = await getMyTemplateShares(getReq('/templates/shares'));

      expect(result.toMap().containsKey('cursor'), isFalse);
    });
  });
}
