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
  });
}
