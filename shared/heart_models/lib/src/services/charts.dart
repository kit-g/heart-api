import '../models/charts.dart';

abstract interface class ChartPreferenceService {
  Future<Iterable<ChartPreference>> getPreferences(String userId);

  Future<ChartPreference> saveChartPreference(ChartPreference preference, String userId);

  Future<void> deleteChartPreference(String preferenceId, String userId);
}
