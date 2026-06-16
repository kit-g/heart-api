import 'package:heart/models/images.dart';
import 'package:heart/models/profile.dart';
import 'package:heart/models/workouts.dart';
import 'package:heart_models/heart_models.dart';
import 'package:relic/relic.dart';

final _profilesProperty = ContextProperty<ApiProfileService>('ApiProfileService');
final _imageDbProperty = ContextProperty<ApiImageDbService>('ApiImageDbService');
final _chatsProperty = ContextProperty<ChartPreferenceService>('ChartPreferenceService');
final _exercisePrefsProperty = ContextProperty<ExercisePreferenceService>('ExercisePreferenceService');
final _commentsProperty = ContextProperty<CommentService>('CommentService');
final _connectionsProperty = ContextProperty<ConnectionsService>('ConnectionsService');
final _devicesProperty = ContextProperty<DeviceService>('DeviceService');
final _workoutsProperty = ContextProperty<ApiWorkoutService>('ApiWorkoutService');
final _templatesProperty = ContextProperty<ApiTemplateService>('ApiTemplateService');

Middleware profilesDb({required ApiProfileService db}) {
  return (final Handler next) {
    return (final request) {
      _profilesProperty[request] = db;
      return next(request);
    };
  };
}

Middleware chartsDb({required ChartPreferenceService db}) {
  return (final Handler next) {
    return (final request) {
      _chatsProperty[request] = db;
      return next(request);
    };
  };
}

Middleware exercisePreferencesDb({required ExercisePreferenceService db}) {
  return (final Handler next) {
    return (final request) {
      _exercisePrefsProperty[request] = db;
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

Middleware devicesDb({required DeviceService db}) {
  return (final Handler next) {
    return (final request) {
      _devicesProperty[request] = db;
      return next(request);
    };
  };
}

Middleware commentsDb({required CommentService db}) {
  return (final Handler next) {
    return (final request) {
      _commentsProperty[request] = db;
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

Middleware imageDb({required ApiImageDbService db}) {
  return (final Handler next) {
    return (final request) {
      _imageDbProperty[request] = db;
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
  ApiProfileService get profileService => _profilesProperty.get(this);

  set profileService(ApiProfileService v) => _profilesProperty[this] = v;

  ChartPreferenceService get chartPreferenceService => _chatsProperty.get(this);

  set chartPreferenceService(ChartPreferenceService v) => _chatsProperty[this] = v;

  ExercisePreferenceService get exercisePreferenceService => _exercisePrefsProperty.get(this);

  set exercisePreferenceService(ExercisePreferenceService v) => _exercisePrefsProperty[this] = v;

  ConnectionsService get connectionsService => _connectionsProperty.get(this);

  set connectionsService(ConnectionsService v) => _connectionsProperty[this] = v;

  DeviceService get deviceService => _devicesProperty.get(this);

  set deviceService(DeviceService v) => _devicesProperty[this] = v;

  CommentService get commentService => _commentsProperty.get(this);

  set commentService(CommentService v) => _commentsProperty[this] = v;

  ApiImageDbService get imageDbService => _imageDbProperty.get(this);

  set imageDbService(ApiImageDbService v) => _imageDbProperty[this] = v;

  ApiWorkoutService get workoutsService => _workoutsProperty.get(this);

  set workoutsService(ApiWorkoutService v) => _workoutsProperty[this] = v;

  ApiTemplateService get templatesService => _templatesProperty.get(this);

  set templatesService(ApiTemplateService v) => _templatesProperty[this] = v;
}
