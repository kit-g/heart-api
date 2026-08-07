import 'package:heart/models/template_folders.dart';
import 'package:heart_models/heart_models.dart';
import 'package:test/test.dart';

void main() {
  group('TemplateFoldersResponse', () {
    test('toMap serializes each folder via toMap()', () {
      final response = TemplateFoldersResponse(
        folders: [
          TemplateFolder(id: 'f1', name: 'Push', order: 1, templateCount: 2),
          TemplateFolder(name: 'Pull'),
        ],
      );

      final folders = response.toMap()['folders'] as List;
      expect(folders, hasLength(2));
      expect(folders[0], containsPair('id', 'f1'));
      expect(folders[0], containsPair('name', 'Push'));
      expect(folders[0], containsPair('templateCount', 2));
      expect(folders[1], containsPair('name', 'Pull'));
      expect(folders[1] as Map, isNot(contains('id')));
    });

    test('toMap emits an empty list for no folders', () {
      expect(TemplateFoldersResponse(folders: const []).toMap(), {'folders': isEmpty});
    });
  });

  group('TemplateSharesResponse', () {
    test('toMap serializes each share via toMap()', () {
      final response = TemplateSharesResponse(
        shares: [
          TemplateShare(
            id: 's1',
            masterTemplateId: 'mt1',
            studentTemplateId: 'st1',
            templateName: 'Block A',
            assignedTo: Profile(id: 'u2', name: 'Kim'),
            assignedAt: DateTime.utc(2026, 1, 1),
          ),
        ],
      );

      final shares = response.toMap()['shares'] as List;
      expect(shares, hasLength(1));
      final share = shares.first as Map;
      expect(share, containsPair('id', 's1'));
      expect(share, containsPair('masterTemplateId', 'mt1'));
      expect(share, containsPair('studentTemplateId', 'st1'));
      expect(share['assignedTo'], containsPair('id', 'u2'));
    });

    test('toMap emits an empty list when the folder had nothing to share', () {
      expect(TemplateSharesResponse(shares: const []).toMap(), {'shares': isEmpty});
    });
  });
}
