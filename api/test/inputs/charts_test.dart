import 'dart:convert';

import 'package:heart/inputs/inputs.dart';
import 'package:heart/models/errors.dart';
import 'package:heart_models/heart_models.dart';
import 'package:test/test.dart';

import '../helpers/request.dart';

void main() {
  group('ChartPreferenceSaveIn — data as object / JSON string', () {
    Future<ChartPreferenceSaveIn> parse(Map<String, dynamic> body) =>
        ChartPreferenceSaveIn.fromRequest(jsonRequest(body: body));

    test('parses a minimal body (type only)', () async {
      final pref = (await parse({'type': 'totalVolume'})).preference;
      expect(pref.type, ChartPreferenceType.totalVolume);
      expect(pref.id, isNull);
      expect(pref.data, isNull);
    });

    test('coerces a non-string id to a string', () async {
      expect((await parse({'id': 5, 'type': 'totalVolume'})).preference.id, '5');
    });

    test('accepts data as an object', () async {
      final pref = (await parse({
        'type': 'topSetWeight',
        'data': {'exerciseName': 'Squat (Barbell)'},
      })).preference;
      expect(pref.data, containsPair('exerciseName', 'Squat (Barbell)'));
      expect(pref.exerciseName, 'Squat (Barbell)');
    });

    test('accepts data as a JSON-encoded object string', () async {
      final pref = (await parse({
        'type': 'topSetWeight',
        'data': jsonEncode({'exerciseName': 'Deadlift (Barbell)'}),
      })).preference;
      expect(pref.data, containsPair('exerciseName', 'Deadlift (Barbell)'));
    });

    test('rejects a JSON string that decodes to a non-object', () async {
      await expectLater(parse({'type': 'topSetWeight', 'data': '[1, 2]'}), throwsA(isA<BadRequest>()));
    });

    test('rejects a non-object, non-string data value', () async {
      await expectLater(parse({'type': 'topSetWeight', 'data': 42}), throwsA(isA<BadRequest>()));
    });

    test('rejects an unknown type', () async {
      await expectLater(parse({'type': 'nope'}), throwsA(isA<BadRequest>()));
    });

    test('rejects a missing type', () async {
      await expectLater(parse({}), throwsA(isA<BadRequest>()));
    });
  });
}
