import 'package:heart/models/connections.dart';
import 'package:heart/models/templates.dart';
import 'package:heart/models/workouts.dart';
import 'package:heart_models/heart_models.dart';
import 'package:relic/relic.dart';

final _chatsProperty = ContextProperty<ChartPreferenceService>('ChartPreferenceService');
final _connectionsProperty = ContextProperty<ConnectionsService>('ConnectionsService');
final _workoutsProperty = ContextProperty<ApiWorkoutService>('ApiWorkoutService');
final _templatesProperty = ContextProperty<ApiTemplateService>('ApiTemplateService');

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

Middleware templatesDb({required ApiTemplateService db}) {
  return (final Handler next) {
    return (final request) {
      _templatesProperty[request] = db;
      return next(request);
    };
  };
}

Middleware workoutsDb({required ApiWorkoutService db}) {
  return (final Handler next) {
    return (final request) {
      _workoutsProperty[request] = db;
      return next(request);
    };
  };
}

extension DatabaseContext on Request {
  ChartPreferenceService get chartPreferenceService => _chatsProperty.get(this);

  set chartPreferenceService(ChartPreferenceService v) => _chatsProperty[this] = v;

  ConnectionsService get connectionsService => _connectionsProperty.get(this);

  set connectionsService(ConnectionsService v) => _connectionsProperty[this] = v;

  ApiWorkoutService get workoutsService => _workoutsProperty.get(this);

  set workoutsService(ApiWorkoutService v) => _workoutsProperty[this] = v;

  ApiTemplateService get templatesService => _templatesProperty.get(this);

  set templatesService(ApiTemplateService v) => _templatesProperty[this] = v;
}
