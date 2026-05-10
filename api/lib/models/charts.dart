import 'package:heart_models/heart_models.dart';

abstract interface class ChartPreferenceResponse implements Model {
  Iterable<ChartPreference> get preferences;

  factory ChartPreferenceResponse({required final Iterable<ChartPreference> preferences}) =
      _ChartPreferenceResponse.new;
}

class _ChartPreferenceResponse implements ChartPreferenceResponse {
  @override
  final Iterable<ChartPreference> preferences;

  _ChartPreferenceResponse({required this.preferences});

  @override
  Map<String, dynamic> toMap() {
    return {
      'preferences': preferences.map((each) => each.toMap()).toList(),
    };
  }
}
