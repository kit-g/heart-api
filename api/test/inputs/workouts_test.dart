import 'package:heart/inputs/inputs.dart';
import 'package:heart/models/errors.dart';
import 'package:test/test.dart';

import '../helpers/request.dart';

void main() {
  group('WorkoutPatchIn — dateOrNull / string / cross-field', () {
    test('parses name + start + end', () async {
      final input = await WorkoutPatchIn.fromRequest(
        jsonRequest(body: {'name': 'A', 'start': '2026-07-20T18:00:00Z', 'end': '2026-07-20T19:00:00Z'}),
      );
      expect(input.name, 'A');
      expect(input.start, DateTime.parse('2026-07-20T18:00:00Z'));
      expect(input.end, DateTime.parse('2026-07-20T19:00:00Z'));
    });

    test('a name-only patch leaves the times null', () async {
      final input = await WorkoutPatchIn.fromRequest(jsonRequest(body: {'name': 'A'}));
      expect(input.start, isNull);
      expect(input.end, isNull);
    });

    test('rejects an empty body (no fields)', () async {
      await expectLater(WorkoutPatchIn.fromRequest(jsonRequest(body: {})), throwsA(isA<BadRequest>()));
    });

    test('rejects end before start', () async {
      await expectLater(
        WorkoutPatchIn.fromRequest(jsonRequest(body: {'start': '2026-07-20T19:00:00Z', 'end': '2026-07-20T18:00:00Z'})),
        throwsA(isA<BadRequest>()),
      );
    });

    test('rejects a blank name', () async {
      await expectLater(WorkoutPatchIn.fromRequest(jsonRequest(body: {'name': ''})), throwsA(isA<BadRequest>()));
    });

    test('rejects an unparseable date', () async {
      await expectLater(
        WorkoutPatchIn.fromRequest(jsonRequest(body: {'start': 'not-a-date'})),
        throwsA(isA<BadRequest>()),
      );
    });
  });

  group('WorkoutPatchIn — the note', () {
    Future<WorkoutPatchIn> patch(Map<String, dynamic> body) => WorkoutPatchIn.fromRequest(jsonRequest(body: body));

    test('a note alone is a patch, trimmed', () async {
      expect((await patch({'note': '  felt strong '})).note, (value: 'felt strong'));
    });

    test('null or blank clears it, and still counts as a field', () async {
      expect((await patch({'note': null})).note, (value: null));
      expect((await patch({'note': '   '})).note, (value: null));
    });

    test('no note key leaves it alone', () async {
      expect((await patch({'name': 'A'})).note, isNull);
    });

    test('over 1000 code points is a 400; 1000 emoji fit', () async {
      expect((await patch({'note': '💪' * 1000})).note?.value?.runes.length, 1000);
      await expectLater(
        patch({'note': 'x' * 1001}),
        throwsA(isA<BadRequest>().having((e) => e.code, 'code', 'workout_note_too_long')),
      );
    });

    test('a non-string note is a 400', () async {
      await expectLater(patch({'note': 42}), throwsA(isA<BadRequest>()));
    });
  });

  group('WorkoutPatchIn — pauses', () {
    Future<WorkoutPatchIn> patch(Map<String, dynamic> body) => WorkoutPatchIn.fromRequest(jsonRequest(body: body));

    test('a list alone is a patch, an empty one included', () async {
      final input = await patch({
        'pauses': [
          {'start': '2026-10-03T18:10:00Z', 'end': '2026-10-03T18:20:00Z'},
        ],
      });
      expect(input.pauses?.single.start, DateTime.utc(2026, 10, 3, 18, 10));
      expect((await patch({'pauses': []})).pauses, isEmpty);
    });

    test('no pauses key leaves them alone', () async {
      expect((await patch({'name': 'A'})).pauses, isNull);
    });

    test('a bad pause is a 400', () async {
      await expectLater(
        patch({
          'pauses': [
            {'start': '2026-10-03T18:20:00Z', 'end': '2026-10-03T18:10:00Z'},
          ],
        }),
        throwsA(isA<BadRequest>().having((e) => e.code, 'code', 'invalid_pauses')),
      );
    });
  });
}
