import 'package:heart/inputs/inputs.dart';
import 'package:heart/models/errors.dart';
import 'package:test/test.dart';

import '../helpers/request.dart';

void main() {
  group('ExerciseCreateIn — required strings / trimmed name', () {
    Future<ExerciseCreateIn> parse(Map<String, dynamic> body) => ExerciseCreateIn.fromRequest(jsonRequest(body: body));

    const valid = {'name': 'Pin Squat', 'category': 'barbell', 'target': 'Quads'};

    test('parses name / category / target / instructions', () async {
      final input = await parse({...valid, 'instructions': 'Set the pins low.'});
      expect(input.name, 'Pin Squat');
      expect(input.category, 'barbell');
      expect(input.target, 'Quads');
      expect(input.instructions, 'Set the pins low.');
    });

    test('instructions stay null when absent', () async {
      expect((await parse(valid)).instructions, isNull);
    });

    test('trims the name', () async {
      expect((await parse({...valid, 'name': '  Pin Squat  '})).name, 'Pin Squat');
    });

    test('rejects a whitespace-only name', () async {
      await expectLater(parse({...valid, 'name': '   '}), throwsA(isA<BadRequest>()));
    });

    test('rejects a name over 200 chars', () async {
      await expectLater(parse({...valid, 'name': 'x' * 201}), throwsA(isA<BadRequest>()));
    });

    for (final field in ['name', 'category', 'target']) {
      test('rejects a missing $field', () async {
        await expectLater(parse({...valid}..remove(field)), throwsA(isA<BadRequest>()));
      });
    }

    test('rejects instructions over 10000 chars', () async {
      await expectLater(parse({...valid, 'instructions': 'x' * 10001}), throwsA(isA<BadRequest>()));
    });
  });

  group('ExerciseUpdateIn — everything optional', () {
    Future<ExerciseUpdateIn> parse(Map<String, dynamic> body) => ExerciseUpdateIn.fromRequest(jsonRequest(body: body));

    test('an empty body parses to all nulls', () async {
      final input = await parse({});
      expect(input.category, isNull);
      expect(input.target, isNull);
      expect(input.instructions, isNull);
      expect(input.archived, isNull);
    });

    test('parses the provided fields', () async {
      final input = await parse({'category': 'dumbbell', 'target': 'Chest', 'archived': true});
      expect(input.category, 'dumbbell');
      expect(input.target, 'Chest');
      expect(input.archived, isTrue);
    });

    test('rejects a non-boolean archived', () async {
      await expectLater(parse({'archived': 'yes'}), throwsA(isA<BadRequest>()));
    });

    test('rejects an empty-string category', () async {
      await expectLater(parse({'category': ''}), throwsA(isA<BadRequest>()));
    });

    test('a pattern is set, cleared with null, and left alone when absent (heart-api#269)', () async {
      expect((await parse({'pattern': 'horizontal_press'})).pattern, (value: 'horizontal_press'));
      expect((await parse({'pattern': null})).pattern, (value: null));
      expect((await parse({'target': 'Chest'})).pattern, isNull, reason: 'an older build sends none');
      for (final bad in ['Horizontal Press', '', 5, 'x' * 65]) {
        await expectLater(
          parse({'pattern': bad}),
          throwsA(isA<BadRequest>().having((e) => e.code, 'code', 'invalid_pattern')),
          reason: '$bad',
        );
      }
    });
  });

  group('instructions (heart-api#443)', () {
    Future<ExerciseUpdateIn> edit(Map<String, dynamic> body) => ExerciseUpdateIn.fromRequest(jsonRequest(body: body));
    Future<ExerciseCreateIn> create(Map<String, dynamic> body) => ExerciseCreateIn.fromRequest(
      jsonRequest(body: {'name': 'Landmine press', 'category': 'Barbell', 'target': 'Shoulders', ...body}),
    );

    test('an edit sets them, clears them with null or blank text, and leaves them alone when absent', () async {
      expect((await edit({'instructions': '  Brace first.\n'})).instructions, (value: '  Brace first.\n'));
      for (final none in [null, '', '   ', '\n\t']) {
        expect((await edit({'instructions': none})).instructions, (value: null), reason: '$none');
      }
      expect((await edit({'target': 'Chest'})).instructions, isNull);
    });

    test('a create reads blank text as none, as an edit does', () async {
      expect((await create({'instructions': ''})).instructions, isNull);
      expect((await create({'instructions': '  '})).instructions, isNull);
      expect((await create({'instructions': 'Slow down'})).instructions, 'Slow down');
    });

    test('anything but text of at most 10000 characters is a 400', () async {
      for (final bad in [42, true, 'x' * 10001]) {
        await expectLater(edit({'instructions': bad}), throwsA(isA<BadRequest>()), reason: '$bad');
        await expectLater(create({'instructions': bad}), throwsA(isA<BadRequest>()), reason: '$bad');
      }
      expect((await edit({'instructions': 'x' * 10000})).instructions?.value, hasLength(10000));
    });
  });

  group('ExerciseCreateIn — a movement pattern (heart-api#269)', () {
    Future<ExerciseCreateIn> parse(Map<String, dynamic> body) => ExerciseCreateIn.fromRequest(
      jsonRequest(body: {'name': 'Landmine press', 'category': 'Barbell', 'target': 'Shoulders', ...body}),
    );

    test('optional: a key, or none', () async {
      expect((await parse({'pattern': 'vertical_press'})).pattern, 'vertical_press');
      expect((await parse({})).pattern, isNull);
      expect((await parse({'pattern': null})).pattern, isNull);
      await expectLater(parse({'pattern': 'vertical press'}), throwsA(isA<BadRequest>()));
    });
  });
}
