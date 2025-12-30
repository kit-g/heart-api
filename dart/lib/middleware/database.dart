import 'package:heart_models/heart_models.dart';
import 'package:relic/relic.dart';

final _property = ContextProperty<ChartPreferenceService>('ChartPreferenceService');

Middleware chartsDb({required ChartPreferenceService db}) {
  return (final Handler next) {
    return (final request) {
      _property[request] = db;
      return next(request);
    };
  };
}

extension DatabaseContext on Request {
  ChartPreferenceService get chartPreferenceService => _property.get(this);

  set chartPreferenceService(ChartPreferenceService v) => _property[this] = v;
}
