import 'package:heart_models/heart_models.dart';
import 'package:test/test.dart';

void main() {
  group('TemplateFolder', () {
    final createdAt = DateTime.utc(2026, 8, 1, 9, 30);

    test('fromRow reads snake_case columns', () {
      final folder = TemplateFolder.fromRow({
        'id': 'folder-1',
        'name': 'Push',
        'order_index': 2,
        'template_count': 5,
        'created_at': createdAt,
      });

      expect(folder.id, 'folder-1');
      expect(folder.name, 'Push');
      expect(folder.order, 2);
      expect(folder.templateCount, 5);
      expect(folder.createdAt, createdAt);
    });

    test('fromRow defaults the count when the query did not compute one', () {
      final folder = TemplateFolder.fromRow({'id': 'folder-1', 'name': 'Push', 'order_index': 0});
      expect(folder.templateCount, 0);
    });

    test('toMap emits camelCase for the wire', () {
      final map = TemplateFolder(
        id: 'folder-1',
        name: 'Push',
        order: 2,
        templateCount: 5,
      ).toMap();

      expect(map['id'], 'folder-1');
      expect(map['name'], 'Push');
      expect(map['order'], 2);
      expect(map['templateCount'], 5);
    });

    test('toMap omits an id the server has not minted yet', () {
      final map = TemplateFolder(name: 'Push').toMap();
      expect(map.containsKey('id'), isFalse);
      expect(map.containsKey('createdAt'), isFalse);
    });

    test('fromJson round-trips toMap', () {
      final original = TemplateFolder(id: 'folder-1', name: 'Pull', order: 3, templateCount: 1);
      final parsed = TemplateFolder.fromJson(original.toMap());

      expect(parsed.id, original.id);
      expect(parsed.name, original.name);
      expect(parsed.order, original.order);
      expect(parsed.templateCount, original.templateCount);
    });

    test('fromJson rejects a blank name', () {
      expect(() => TemplateFolder.fromJson({'name': '   '}), throwsArgumentError);
      expect(() => TemplateFolder.fromJson({}), throwsArgumentError);
    });

    test('sorts by order then name, case-insensitively', () {
      final folders = [
        TemplateFolder(id: 'c', name: 'zebra'),
        TemplateFolder(id: 'b', name: 'Alpha'),
        TemplateFolder(id: 'a', name: 'First', order: -1),
      ]..sort();

      expect(folders.map((f) => f.name), ['First', 'Alpha', 'zebra']);
    });

    test('copyWith preserves createdAt and replaces only what is given', () {
      final folder = TemplateFolder.fromRow({
        'id': 'folder-1',
        'name': 'Before',
        'order_index': 1,
        'created_at': createdAt,
      });

      final renamed = folder.copyWith(name: 'After');

      expect(renamed.name, 'After');
      expect(renamed.order, 1);
      expect(renamed.createdAt, createdAt);
    });

    test('identity is the id', () {
      expect(TemplateFolder(id: 'x', name: 'One'), equals(TemplateFolder(id: 'x', name: 'Two')));
      expect(TemplateFolder(id: 'x', name: 'One'), isNot(equals(TemplateFolder(id: 'y', name: 'One'))));
    });
  });
}
