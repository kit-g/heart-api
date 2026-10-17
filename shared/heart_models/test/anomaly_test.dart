import 'package:heart_models/heart_models.dart';
import 'package:test/test.dart';

void main() {
  group('Anomaly', () {
    final json = {
      'id': '019a0000-0000-7000-8000-000000000001',
      'workoutId': '019a0000-0000-7000-8000-000000000002',
      'workoutStart': '2026-10-06T10:00:00.000Z',
      'setId': '019a0000-0000-7000-8000-000000000003',
      'exerciseId': '019a0000-0000-7000-8000-000000000004',
      'exerciseName': 'Leg Press',
      'reason': 'outlier_weight',
      'observed': {'weight': 630, 'reps': 5},
      'typical': 285,
      'status': 'pending',
      'detectedAt': '2026-10-17T12:00:00.000Z',
    };

    test('round-trips the wire shape', () {
      expect(Anomaly.fromJson(json).toMap(), json);
    });

    test('a reason this build does not know still reads', () {
      final anomaly = Anomaly.fromJson({...json, 'reason': 'duplicate_session'});
      expect(anomaly.reason, 'duplicate_session');
    });

    test('a resolution reads with when it was made', () {
      final anomaly = Anomaly.fromJson({...json, 'status': 'invalid', 'resolvedAt': '2026-10-18T09:00:00.000Z'});
      expect(anomaly.status, AnomalyStatus.invalid);
      expect(anomaly.resolvedAt, DateTime.utc(2026, 10, 18, 9));
    });

    test('a status is one of three', () {
      expect(AnomalyStatus.fromString('valid'), AnomalyStatus.valid);
      expect(() => AnomalyStatus.fromString('maybe'), throwsArgumentError);
    });
  });
}
