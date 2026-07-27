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
}
