import 'package:heart/globals/globals.dart';
import 'package:heart/middleware/database.dart';
import 'package:heart/routes/templates.dart';
import 'package:heart_models/heart_models.dart';
import 'package:mockito/mockito.dart';
import 'package:relic_core/relic_core.dart';
import 'package:test/test.dart';

import '../helpers/request.dart';
import '../mocks.mocks.dart';

const _meId = 'u1';

Template _fakeTemplate(String id) => Template.empty(id: id, order: 0);

TemplateShare _fakeShare(String id) => TemplateShare(
  id: id,
  studentTemplateId: 'ts-$id',
  templateName: 'Push',
  assignedTo: Profile.fromJson({'id': 's1', 'username': 'Stu', 'avatar': null}),
  assignedAt: DateTime.utc(2026, 1, 1),
);

void main() {
  late MockApiTemplateService templates;

  setUp(() => templates = MockApiTemplateService());

  Request wire(Request req) => req
    ..user = User(id: _meId)
    ..templatesService = templates;

  Request getReq(String path, {Map<String, String> query = const {}}) =>
      wire(bareRequest(method: Method.get, path: path, query: query));

  group('getMyTemplates', () {
    void stub(Page<Template> page) {
      when(
        templates.getTemplates(userId: anyNamed('userId'), cursor: anyNamed('cursor'), limit: anyNamed('limit')),
      ).thenAnswer((_) async => page);
    }

    test('omits cursor when there is no next page', () async {
      stub(Page(items: [_fakeTemplate('t-1')], hasMore: false));

      final result = await getMyTemplates(getReq('/templates'));

      expect(result.toMap()['templates'], hasLength(1));
      expect(result.toMap().containsKey('cursor'), isFalse);
    });

    test('emits the last template id as cursor when there is a next page', () async {
      stub(Page(items: [_fakeTemplate('t-1'), _fakeTemplate('t-2')], hasMore: true));

      final result = await getMyTemplates(getReq('/templates'));

      expect(result.toMap()['cursor'], 't-2');
    });

    test('clamps limit to the max and passes the cursor through', () async {
      stub(const Page(items: [], hasMore: false));

      await getMyTemplates(getReq('/templates', query: {'limit': '999', 'cursor': 't-9'}));

      verify(templates.getTemplates(userId: _meId, cursor: 't-9', limit: 100)).called(1);
    });

    test('defaults to a limit of 30 with no cursor when unspecified', () async {
      stub(const Page(items: [], hasMore: false));

      await getMyTemplates(getReq('/templates'));

      verify(templates.getTemplates(userId: _meId, cursor: null, limit: 30)).called(1);
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
