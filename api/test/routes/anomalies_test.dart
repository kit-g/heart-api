import 'package:heart/globals/globals.dart';
import 'package:heart/middleware/database.dart';
import 'package:heart/models/errors.dart';
import 'package:heart/routes/anomalies.dart';
import 'package:heart_models/heart_models.dart';
import 'package:mockito/mockito.dart';
import 'package:relic_core/relic_core.dart';
import 'package:test/test.dart';

import '../helpers/request.dart';
import '../mocks.mocks.dart';

const _meId = 'u1';
const _anomalyId = '019def00-0000-7000-8000-000000000041';

Anomaly _anomaly({String id = _anomalyId, String status = 'pending'}) {
  return Anomaly.fromJson({
    'id': id,
    'workoutId': '019def00-0000-7000-8000-000000000042',
    'setId': '019def00-0000-7000-8000-000000000043',
    'reason': 'outlier_weight',
    'observed': {'weight': 630, 'reps': 5},
    'typical': 285,
    'status': status,
    'detectedAt': '2026-10-17T12:00:00.000Z',
    if (status != 'pending') 'resolvedAt': '2026-10-17T13:00:00.000Z',
  });
}

void main() {
  late MockApiAnomalyService service;

  setUp(() => service = MockApiAnomalyService());

  Request wire(Request req) {
    return req
      ..user = User(id: _meId)
      ..anomalyService = service;
  }

  group('getAnomalies', () {
    test('a page of one status, with the cursor of the last', () async {
      when(
        service.getAnomalies(userId: _meId, status: AnomalyStatus.pending, cursor: null, limit: 1),
      ).thenAnswer((_) async => Page(items: [_anomaly()], hasMore: true));

      final page = await getAnomalies(
        wire(bareRequest(method: Method.get, path: '/anomalies', query: {'status': 'pending', 'limit': '1'})),
      );

      expect(page.toMap(), {
        'anomalies': [_anomaly().toMap()],
        'cursor': _anomalyId,
      });
    });

    test('an empty status is no status, as any optional parameter', () async {
      when(
        service.getAnomalies(userId: _meId, status: null, cursor: null, limit: 30),
      ).thenAnswer((_) async => const Page(items: [], hasMore: false));

      final page = await getAnomalies(
        wire(bareRequest(method: Method.get, path: '/anomalies', query: {'status': ''})),
      );

      expect(page.toMap(), {'anomalies': <Object>[]});
    });

    test('an unknown status or a malformed cursor is a 400', () {
      expect(
        () => getAnomalies(wire(bareRequest(method: Method.get, path: '/anomalies', query: {'status': 'maybe'}))),
        throwsA(isA<BadRequest>()),
      );
      expect(
        () => getAnomalies(wire(bareRequest(method: Method.get, path: '/anomalies', query: {'cursor': 'x'}))),
        throwsA(isA<BadRequest>()),
      );
    });
  });

  group('resolveAnomaly', () {
    Request body(Map<String, dynamic> json) {
      return wire(jsonRequest(method: Method.put, path: '/anomalies/$_anomalyId', body: json));
    }

    test('records the decision', () async {
      when(
        service.resolveAnomaly(userId: _meId, anomalyId: _anomalyId, status: AnomalyStatus.invalid),
      ).thenAnswer((_) async => _anomaly(status: 'invalid'));

      final resolved = await resolveAnomalyById(body({'status': 'invalid'}), _anomalyId);

      expect(resolved.status, AnomalyStatus.invalid);
    });

    test('pending is no decision, and nothing else is either', () {
      for (final status in ['pending', 'maybe', null]) {
        expect(
          () => resolveAnomalyById(body({'status': status}), _anomalyId),
          throwsA(isA<BadRequest>().having((e) => e.code, 'code', 'invalid_status')),
        );
      }
    });

    test("a malformed id, or someone else's, is a 404", () {
      when(
        service.resolveAnomaly(userId: _meId, anomalyId: _anomalyId, status: AnomalyStatus.valid),
      ).thenAnswer((_) async => null);

      expect(() => resolveAnomalyById(body({'status': 'valid'}), 'x'), throwsA(isA<NotFound>()));
      expect(() => resolveAnomalyById(body({'status': 'valid'}), _anomalyId), throwsA(isA<NotFound>()));
    });
  });
}
