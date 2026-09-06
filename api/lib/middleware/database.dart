import 'package:heart/models/creates.dart';
import 'package:heart/models/exercise_preferences.dart';
import 'package:heart/models/images.dart';
import 'package:heart/models/profile.dart';
import 'package:heart/models/workouts.dart';
import 'package:heart_models/heart_models.dart';
import 'package:relic/relic.dart';

final _profilesProperty = ContextProperty<ApiProfileService>('ApiProfileService');
final _imageDbProperty = ContextProperty<ApiImageDbService>('ApiImageDbService');
final _chatsProperty = ContextProperty<ChartPreferenceService>('ChartPreferenceService');
final _exercisePrefsProperty = ContextProperty<ApiExercisePreferenceService>('ApiExercisePreferenceService');
final _goalsProperty = ContextProperty<IdempotentGoalService>('IdempotentGoalService');
final _commentsProperty = ContextProperty<CommentService>('CommentService');
final _connectionsProperty = ContextProperty<ConnectionsService>('ConnectionsService');
final _devicesProperty = ContextProperty<DeviceService>('DeviceService');
final _workoutsProperty = ContextProperty<ApiWorkoutService>('ApiWorkoutService');
final _templatesProperty = ContextProperty<IdempotentTemplateService>('IdempotentTemplateService');
final _templateFoldersProperty = ContextProperty<IdempotentTemplateFolderService>('IdempotentTemplateFolderService');

Middleware profilesDb({required ApiProfileService db}) {
  return (Handler next) {
    return (request) {
      _profilesProperty[request] = db;
      return next(request);
    };
  };
}

Middleware chartsDb({required ChartPreferenceService db}) {
  return (Handler next) {
    return (request) {
      _chatsProperty[request] = db;
      return next(request);
    };
  };
}

Middleware exercisePreferencesDb({required ApiExercisePreferenceService db}) {
  return (Handler next) {
    return (request) {
      _exercisePrefsProperty[request] = db;
      return next(request);
    };
  };
}

Middleware goalsDb({required IdempotentGoalService db}) {
  return (Handler next) {
    return (request) {
      _goalsProperty[request] = db;
      return next(request);
    };
  };
}

Middleware connectionsDb({required ConnectionsService db}) {
  return (Handler next) {
    return (request) {
      _connectionsProperty[request] = db;
      return next(request);
    };
  };
}

Middleware devicesDb({required DeviceService db}) {
  return (Handler next) {
    return (request) {
      _devicesProperty[request] = db;
      return next(request);
    };
  };
}

Middleware commentsDb({required CommentService db}) {
  return (Handler next) {
    return (request) {
      _commentsProperty[request] = db;
      return next(request);
    };
  };
}

Middleware templatesDb({required IdempotentTemplateService db}) {
  return (Handler next) {
    return (request) {
      _templatesProperty[request] = db;
      return next(request);
    };
  };
}

Middleware templateFoldersDb({required IdempotentTemplateFolderService db}) {
  return (Handler next) {
    return (request) {
      _templateFoldersProperty[request] = db;
      return next(request);
    };
  };
}

Middleware imageDb({required ApiImageDbService db}) {
  return (Handler next) {
    return (request) {
      _imageDbProperty[request] = db;
      return next(request);
    };
  };
}

Middleware workoutsDb({required ApiWorkoutService db}) {
  return (Handler next) {
    return (request) {
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

  ApiExercisePreferenceService get exercisePreferenceService => _exercisePrefsProperty.get(this);

  set exercisePreferenceService(ApiExercisePreferenceService v) => _exercisePrefsProperty[this] = v;

  IdempotentGoalService get goalService => _goalsProperty.get(this);

  set goalService(IdempotentGoalService v) => _goalsProperty[this] = v;

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

  IdempotentTemplateService get templatesService => _templatesProperty.get(this);

  set templatesService(IdempotentTemplateService v) => _templatesProperty[this] = v;

  IdempotentTemplateFolderService get templateFolderService => _templateFoldersProperty.get(this);

  set templateFolderService(IdempotentTemplateFolderService v) => _templateFoldersProperty[this] = v;
}
