import 'package:heart/models/pagination.dart';
import 'package:heart_models/heart_models.dart';
import 'package:test/test.dart';

void main() {
  group('Paginated — cursor only when there is a next page', () {
    TemplateFolder folder(String id) => TemplateFolder(id: id, name: 'Folder $id');

    Paginated<TemplateFolder> paginated(Page<TemplateFolder> page) =>
        Paginated<TemplateFolder>.from(page, itemsKey: 'folders', cursorOf: (f) => f.id!);

    test('emits the last item’s cursor when hasMore is true', () {
      final response = paginated(Page(items: [folder('f1'), folder('f2')], hasMore: true));
      expect(response.cursor, 'f2');
      expect(response.toMap()['cursor'], 'f2');
    });

    test('omits the cursor when the list is exhausted', () {
      final response = paginated(Page(items: [folder('f1')], hasMore: false));
      expect(response.cursor, isNull);
      expect(response.toMap(), isNot(contains('cursor')));
    });

    test('omits the cursor when the page is empty, even with hasMore set', () {
      final response = paginated(Page(items: const [], hasMore: true));
      expect(response.cursor, isNull);
      expect(response.toMap(), isNot(contains('cursor')));
    });

    test('serializes the items under itemsKey via toMap()', () {
      final map = paginated(Page(items: [folder('f1')], hasMore: false)).toMap();
      expect(map['folders'], [containsPair('id', 'f1')]);
    });

    test('iterates over its items', () {
      final response = paginated(Page(items: [folder('f1'), folder('f2')], hasMore: false));
      expect(response.map((f) => f.id), ['f1', 'f2']);
    });

    test('the direct constructor keeps an explicit cursor', () {
      final response = Paginated<TemplateFolder>(items: [folder('f1')], itemsKey: 'folders', cursor: 'opaque');
      expect(response.toMap()['cursor'], 'opaque');
    });
  });
}
