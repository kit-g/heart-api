import 'package:heart/inputs/inputs.dart';
import 'package:heart/models/errors.dart';
import 'package:test/test.dart';

import '../helpers/request.dart';

void main() {
  group('TemplateFolderCreateIn — trimmed name / defaulted order', () {
    Future<TemplateFolderCreateIn> parse(Map<String, dynamic> body) =>
        TemplateFolderCreateIn.fromRequest(jsonRequest(body: body));

    test('parses name and order', () async {
      final input = await parse({'name': 'Push', 'order': 2});
      expect(input.name, 'Push');
      expect(input.order, 2);
    });

    test('trims the name', () async {
      expect((await parse({'name': '  Push  '})).name, 'Push');
    });

    test('defaults order to 0 when absent', () async {
      expect((await parse({'name': 'Push'})).order, 0);
    });

    test('truncates a fractional order to an int', () async {
      expect((await parse({'name': 'Push', 'order': 1.9})).order, 1);
    });

    test('builds a TemplateFolder from the parsed parts', () async {
      final folder = (await parse({'name': 'Pull', 'order': 3})).folder;
      expect(folder.name, 'Pull');
      expect(folder.order, 3);
      expect(folder.id, isNull);
    });

    for (final (label, name) in <(String, Object?)>[
      ('missing', null),
      ('empty', ''),
      ('whitespace-only', '   '),
      ('over 80 chars', 'x' * 81),
      ('non-string', 42),
    ]) {
      test('rejects a $label name', () async {
        await expectLater(parse({'name': ?name}), throwsA(isA<BadRequest>()));
      });
    }

    for (final (label, order) in <(String, Object)>[('negative', -1), ('non-numeric', 'first')]) {
      test('rejects a $label order', () async {
        await expectLater(parse({'name': 'Push', 'order': order}), throwsA(isA<BadRequest>()));
      });
    }
  });

  group('TemplateFolderUpdateIn — same shape as create', () {
    Future<TemplateFolderUpdateIn> parse(Map<String, dynamic> body) =>
        TemplateFolderUpdateIn.fromRequest(jsonRequest(body: body));

    test('parses and trims', () async {
      final input = await parse({'name': ' Legs ', 'order': 1});
      expect(input.name, 'Legs');
      expect(input.order, 1);
      expect(input.folder.name, 'Legs');
    });

    test('rejects an empty name', () async {
      await expectLater(parse({'name': ''}), throwsA(isA<BadRequest>()));
    });
  });
}
