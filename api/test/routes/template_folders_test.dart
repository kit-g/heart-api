import 'package:heart/globals/globals.dart';
import 'package:heart/middleware/database.dart';
import 'package:heart/models/errors.dart';
import 'package:heart/routes/template_folders.dart';
import 'package:heart_models/heart_models.dart';
import 'package:mockito/mockito.dart';
import 'package:relic_core/relic_core.dart';
import 'package:test/test.dart';

import '../helpers/request.dart';
import '../mocks.mocks.dart';

const _meId = 'u1';
const _folderId = 'f-1';

TemplateFolder _fakeFolder(String name, {int order = 0, int count = 0}) =>
    TemplateFolder(id: _folderId, name: name, order: order, templateCount: count);

TemplateShare _fakeShare(String id) => TemplateShare(
  id: id,
  masterTemplateId: 'm-$id',
  studentTemplateId: 'ts-$id',
  templateName: 'Push',
  assignedTo: Profile.fromJson({'id': 's1', 'username': 'Stu', 'avatar': null}),
  assignedAt: DateTime.utc(2026, 1, 1),
);

void main() {
  late MockApiTemplateFolderService folders;

  setUp(() => folders = MockApiTemplateFolderService());

  Request wire(Request req) => req
    ..user = User(id: _meId)
    ..templateFolderService = folders;

  Request getReq(String path, {Map<String, String> query = const {}}) =>
      wire(bareRequest(method: Method.get, path: path, query: query));

  Request bodyReq(Map<String, dynamic> body, {Method method = Method.post}) =>
      wire(jsonRequest(method: method, path: '/template-folders', body: body));

  group('getMyFolders', () {
    test('returns the caller\'s folders under a folders key', () async {
      when(folders.getFolders(userId: anyNamed('userId'))).thenAnswer(
        (_) async => [_fakeFolder('Push', count: 3)],
      );

      final result = await getMyFolders(getReq('/template-folders'));
      final listed = result.toMap()['folders'] as List;

      expect(listed, hasLength(1));
      expect((listed.single as Map)['name'], 'Push');
      expect((listed.single as Map)['templateCount'], 3);
      verify(folders.getFolders(userId: _meId)).called(1);
    });

    test('serializes an empty list rather than omitting the key', () async {
      when(folders.getFolders(userId: anyNamed('userId'))).thenAnswer((_) async => const []);

      final result = await getMyFolders(getReq('/template-folders'));
      expect(result.toMap()['folders'], isEmpty);
    });
  });

  group('createFolder', () {
    void stub() {
      when(
        folders.createFolder(userId: anyNamed('userId'), folder: anyNamed('folder')),
      ).thenAnswer((invocation) async => invocation.namedArguments[#folder] as TemplateFolder);
    }

    test('passes the trimmed name and order through', () async {
      stub();

      await createFolder(bodyReq({'name': '  Push  ', 'order': 2}));

      final sent = verify(folders.createFolder(userId: _meId, folder: captureAnyNamed('folder'))).captured.single;
      expect((sent as TemplateFolder).name, 'Push');
      expect(sent.order, 2);
    });

    test('defaults order to 0 when the body omits it', () async {
      stub();

      await createFolder(bodyReq({'name': 'Push'}));

      final sent = verify(folders.createFolder(userId: _meId, folder: captureAnyNamed('folder'))).captured.single;
      expect((sent as TemplateFolder).order, 0);
    });

    test('rejects a missing name', () async {
      await expectLater(createFolder(bodyReq({})), throwsA(isA<BadRequest>()));
    });

    test('rejects a name that is only whitespace', () async {
      await expectLater(createFolder(bodyReq({'name': '   '})), throwsA(isA<BadRequest>()));
    });

    test('rejects a name longer than 80 characters', () async {
      await expectLater(createFolder(bodyReq({'name': 'x' * 81})), throwsA(isA<BadRequest>()));
    });

    test('rejects a negative order', () async {
      await expectLater(createFolder(bodyReq({'name': 'Push', 'order': -1})), throwsA(isA<BadRequest>()));
    });
  });

  group('updateFolderById', () {
    test('addresses the folder from the path and sends the new name', () async {
      when(
        folders.updateFolder(
          userId: anyNamed('userId'),
          folderId: anyNamed('folderId'),
          folder: anyNamed('folder'),
        ),
      ).thenAnswer((_) async => _fakeFolder('After'));

      final result = await updateFolderById(
        bodyReq({'name': 'After', 'order': 1}, method: Method.put),
        _folderId,
      );

      expect(result.name, 'After');
      final sent = verify(
        folders.updateFolder(userId: _meId, folderId: _folderId, folder: captureAnyNamed('folder')),
      ).captured.single;
      expect((sent as TemplateFolder).name, 'After');
      expect(sent.order, 1);
    });

    test('rejects a blank rename before reaching the service', () async {
      await expectLater(
        updateFolderById(bodyReq({'name': ''}, method: Method.put), _folderId),
        throwsA(isA<BadRequest>()),
      );
      verifyNever(
        folders.updateFolder(
          userId: anyNamed('userId'),
          folderId: anyNamed('folderId'),
          folder: anyNamed('folder'),
        ),
      );
    });
  });

  group('deleteFolderById', () {
    test('deletes and answers 204', () async {
      when(folders.deleteFolder(userId: anyNamed('userId'), folderId: anyNamed('folderId'))).thenAnswer((_) async {});

      await expectLater(
        deleteFolderById(getReq('/template-folders/$_folderId'), _folderId),
        throwsA(isA<NoContent>()),
      );
      verify(folders.deleteFolder(userId: _meId, folderId: _folderId)).called(1);
    });
  });

  group('assignFolderToUserById', () {
    void stub(List<TemplateShare> shares) {
      when(
        folders.shareFolder(
          coachId: anyNamed('coachId'),
          targetUserId: anyNamed('targetUserId'),
          folderId: anyNamed('folderId'),
        ),
      ).thenAnswer((_) async => shares);
    }

    test('returns one share per assigned template', () async {
      stub([_fakeShare('s-1'), _fakeShare('s-2')]);

      final result = await assignFolderToUserById(getReq('/accounts/s1/folders/$_folderId'), 's1', _folderId);

      expect(result.toMap()['shares'], hasLength(2));
      verify(folders.shareFolder(coachId: _meId, targetUserId: 's1', folderId: _folderId)).called(1);
    });

    test('an empty folder returns an empty share list, not an error', () async {
      stub(const []);

      final result = await assignFolderToUserById(getReq('/accounts/s1/folders/$_folderId'), 's1', _folderId);
      expect(result.toMap()['shares'], isEmpty);
    });

    test('refuses to assign to yourself', () async {
      await expectLater(
        assignFolderToUserById(getReq('/accounts/$_meId/folders/$_folderId'), _meId, _folderId),
        throwsA(isA<Forbidden>()),
      );
      verifyNever(
        folders.shareFolder(
          coachId: anyNamed('coachId'),
          targetUserId: anyNamed('targetUserId'),
          folderId: anyNamed('folderId'),
        ),
      );
    });
  });
}
