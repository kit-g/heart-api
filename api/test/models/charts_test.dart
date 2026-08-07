import 'package:heart/models/charts.dart';
import 'package:heart_models/heart_models.dart';
import 'package:test/test.dart';

void main() {
  group('ChartPreferenceResponse', () {
    test('toMap serializes each preference via toMap()', () {
      final response = ChartPreferenceResponse(
        preferences: [
          ChartPreference.create(id: 'p1', type: ChartPreferenceType.topSetWeight, data: {'exerciseName': 'Squat'}),
          ChartPreference.create(type: ChartPreferenceType.totalVolume),
        ],
      );

      final prefs = response.toMap()['preferences'] as List;
      expect(prefs, hasLength(2));
      expect(prefs[0], containsPair('id', 'p1'));
      expect(prefs[0], containsPair('type', 'topSetWeight'));
      expect(prefs[0], containsPair('data', {'exerciseName': 'Squat'}));
      expect(prefs[1], containsPair('type', 'totalVolume'));
      expect(prefs[1] as Map, isNot(contains('data')));
    });

    test('toMap emits an empty list for no preferences', () {
      expect(ChartPreferenceResponse(preferences: const []).toMap(), {'preferences': isEmpty});
    });
  });
}
