import 'dart:convert';

import 'package:heart_models/heart_models.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import '../helpers/app_harness.dart';

/// Route-level HTTP tests for `routes/charts.dart`. The save path exercises
/// `ChartPreferenceSaveIn`'s three accepted `data` shapes (absent, object,
/// JSON-encoded string) plus the malformed variants that must map to 400.
void main() {
  late AppHarness app;

  setUp(() async => app = await AppHarness.start());
  tearDown(() => app.stop());

  ChartPreference sample({String? id, Map<String, dynamic>? data}) =>
      ChartPreference.create(id: id ?? 'p1', type: ChartPreferenceType.topSetWeight, data: data);

  group('GET /charts', () {
    test('lists the caller’s preferences', () async {
      when(app.db.getPreferences(any)).thenAnswer((_) async => [sample()]);

      final res = await app.send('GET', '/charts');
      expect(res.status, 200);
      final body = jsonDecode(res.body) as Map;
      expect(body['preferences'], hasLength(1));
      expect((body['preferences'] as List).first, containsPair('type', 'topSetWeight'));
      verify(app.db.getPreferences('u1')).called(1);
    });
  });

  group('POST /charts', () {
    ChartPreference captured() =>
        verify(app.db.saveChartPreference(captureAny, 'u1')).captured.single as ChartPreference;

    setUp(() {
      when(
        app.db.saveChartPreference(any, any),
      ).thenAnswer((i) async => i.positionalArguments[0] as ChartPreference);
    });

    test('saves a preference from a minimal body (no id, no data)', () async {
      final res = await app.send('POST', '/charts', body: {'type': 'totalVolume'});
      expect(res.status, 200);

      final pref = captured();
      expect(pref.type, ChartPreferenceType.totalVolume);
      expect(pref.id, isNull);
      expect(pref.data, isNull);
    });

    test('passes the client id through', () async {
      final res = await app.send('POST', '/charts', body: {'id': 'p9', 'type': 'totalVolume'});
      expect(res.status, 200);
      expect(captured().id, 'p9');
    });

    test('accepts data as an object', () async {
      final res = await app.send(
        'POST',
        '/charts',
        body: {
          'type': 'topSetWeight',
          'data': {'exerciseName': 'Squat (Barbell)'},
        },
      );
      expect(res.status, 200);
      expect(captured().data, containsPair('exerciseName', 'Squat (Barbell)'));
    });

    test('accepts data as a JSON-encoded object string', () async {
      final res = await app.send(
        'POST',
        '/charts',
        body: {
          'type': 'topSetWeight',
          'data': jsonEncode({'exerciseName': 'Deadlift (Barbell)'}),
        },
      );
      expect(res.status, 200);
      expect(captured().data, containsPair('exerciseName', 'Deadlift (Barbell)'));
    });

    test('rejects a JSON string that is not an object with 400', () async {
      final res = await app.send('POST', '/charts', body: {'type': 'topSetWeight', 'data': '"just a string"'});
      expect(res.status, 400);
      verifyNever(app.db.saveChartPreference(any, any));
    });

    test('rejects a garbage (non-JSON) data string with 400', () async {
      final res = await app.send('POST', '/charts', body: {'type': 'topSetWeight', 'data': 'not json at all'});
      expect(res.status, 400);
      verifyNever(app.db.saveChartPreference(any, any));
    });

    test('rejects a non-object, non-string data value with 400', () async {
      final res = await app.send('POST', '/charts', body: {'type': 'topSetWeight', 'data': 42});
      expect(res.status, 400);
      verifyNever(app.db.saveChartPreference(any, any));
    });

    test('rejects an unknown type with 400', () async {
      final res = await app.send('POST', '/charts', body: {'type': 'nope'});
      expect(res.status, 400);
      verifyNever(app.db.saveChartPreference(any, any));
    });

    test('rejects a missing type with 400', () async {
      final res = await app.send('POST', '/charts', body: {'data': {}});
      expect(res.status, 400);
      verifyNever(app.db.saveChartPreference(any, any));
    });
  });

  group('DELETE /charts/:preferenceId', () {
    test('deletes the preference by path param (204)', () async {
      when(app.db.deleteChartPreference(any, any)).thenAnswer((_) async {});

      final res = await app.send('DELETE', '/charts/p1');
      expect(res.status, 204);
      verify(app.db.deleteChartPreference('p1', 'u1')).called(1);
    });
  });
}
