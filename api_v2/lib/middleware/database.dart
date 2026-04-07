import 'package:heart/models/connections.dart';
import 'package:heart_models/heart_models.dart';
import 'package:relic/relic.dart';

final _chatsProperty = ContextProperty<ChartPreferenceService>('ChartPreferenceService');
final _connectionsProperty = ContextProperty<ConnectionsService>('ConnectionsService');

Middleware chartsDb({required ChartPreferenceService db}) {
  return (final Handler next) {
    return (final request) {
      _chatsProperty[request] = db;
      return next(request);
    };
  };
}

Middleware connectionsDb({required ConnectionsService db}) {
  return (final Handler next) {
    return (final request) {
      _connectionsProperty[request] = db;
      return next(request);
    };
  };
}

extension DatabaseContext on Request {
  ChartPreferenceService get chartPreferenceService => _chatsProperty.get(this);

  set chartPreferenceService(ChartPreferenceService v) => _chatsProperty[this] = v;

  ConnectionsService get connectionsService => _connectionsProperty.get(this);

  set connectionsService(ConnectionsService v) => _connectionsProperty[this] = v;
}
