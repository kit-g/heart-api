import 'package:heart/models/anomalies.dart';
import 'package:heart/models/creates.dart';
import 'package:heart/models/exercise_preferences.dart';
import 'package:heart/models/images.dart';
import 'package:heart/models/oauth.dart';
import 'package:heart/models/profile.dart';
import 'package:heart/models/programs.dart';
import 'package:heart/models/skips.dart';
import 'package:heart/models/tokens.dart';
import 'package:heart/models/workouts.dart';
import 'package:heart/models/coach_library.dart';
import 'package:heart/models/program_changes.dart';
import 'package:heart_models/heart_models.dart';
import 'package:relic/relic.dart';

final _profilesProperty = ContextProperty<ApiProfileService>('ApiProfileService');
final _anomaliesProperty = ContextProperty<ApiAnomalyService>('ApiAnomalyService');
final _imageDbProperty = ContextProperty<ApiImageDbService>('ApiImageDbService');
final _chatsProperty = ContextProperty<ChartPreferenceService>('ChartPreferenceService');
final _exercisePrefsProperty = ContextProperty<ApiExercisePreferenceService>('ApiExercisePreferenceService');
final _goalsProperty = ContextProperty<IdempotentGoalService>('IdempotentGoalService');
final _programsProperty = ContextProperty<ProgramService>('ProgramService');
final _invitationsProperty = ContextProperty<InvitationService>('InvitationService');
final _pushProperty = ContextProperty<PushService>('PushService');
final _keysProperty = ContextProperty<KeyService>('KeyService');
final _threadsProperty = ContextProperty<ThreadService>('ThreadService');
final _notesProperty = ContextProperty<CoachNoteService>('CoachNoteService');
final _reportsProperty = ContextProperty<ReportService>('ReportService');
final _coachLibraryProperty = ContextProperty<CoachLibraryService>('CoachLibraryService');
final _programChangesProperty = ContextProperty<ProgramChangeService>('ProgramChangeService');
final _skipsProperty = ContextProperty<SkipService>('SkipService');
final _commentsProperty = ContextProperty<CommentService>('CommentService');
final _connectionsProperty = ContextProperty<ConnectionsService>('ConnectionsService');
final _devicesProperty = ContextProperty<DeviceService>('DeviceService');
final _apiTokensProperty = ContextProperty<ApiTokenService>('ApiTokenService');
final _oauthProperty = ContextProperty<OAuthService>('OAuthService');
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

Middleware anomaliesDb({required ApiAnomalyService db}) {
  return (Handler next) {
    return (request) {
      _anomaliesProperty[request] = db;
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

Middleware coachLibraryDb({required CoachLibraryService db}) {
  return (Handler next) {
    return (request) {
      _coachLibraryProperty[request] = db;
      return next(request);
    };
  };
}

Middleware programChangesDb({required ProgramChangeService db}) {
  return (Handler next) {
    return (request) {
      _programChangesProperty[request] = db;
      return next(request);
    };
  };
}

Middleware threadsDb({required ThreadService db}) {
  return (Handler next) {
    return (request) {
      _threadsProperty[request] = db;
      return next(request);
    };
  };
}

Middleware notesDb({required CoachNoteService db}) {
  return (Handler next) {
    return (request) {
      _notesProperty[request] = db;
      return next(request);
    };
  };
}

Middleware reportsDb({required ReportService db}) {
  return (Handler next) {
    return (request) {
      _reportsProperty[request] = db;
      return next(request);
    };
  };
}

Middleware keysDb({required KeyService db}) {
  return (Handler next) {
    return (request) {
      _keysProperty[request] = db;
      return next(request);
    };
  };
}

Middleware pushDb({required PushService db}) {
  return (Handler next) {
    return (request) {
      _pushProperty[request] = db;
      return next(request);
    };
  };
}

Middleware invitationsDb({required InvitationService db}) {
  return (Handler next) {
    return (request) {
      _invitationsProperty[request] = db;
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

Middleware apiTokensDb({required ApiTokenService db}) {
  return (Handler next) {
    return (request) {
      _apiTokensProperty[request] = db;
      return next(request);
    };
  };
}

Middleware oauthDb({required OAuthService db}) {
  return (Handler next) {
    return (request) {
      _oauthProperty[request] = db;
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

Middleware programsDb({required ProgramService db}) {
  return (Handler next) {
    return (request) {
      _programsProperty[request] = db;
      return next(request);
    };
  };
}

Middleware skipsDb({required SkipService db}) {
  return (Handler next) {
    return (request) {
      _skipsProperty[request] = db;
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

  ApiAnomalyService get anomalyService => _anomaliesProperty.get(this);

  set anomalyService(ApiAnomalyService v) => _anomaliesProperty[this] = v;

  IdempotentGoalService get goalService => _goalsProperty.get(this);

  set goalService(IdempotentGoalService v) => _goalsProperty[this] = v;

  ProgramService get programService => _programsProperty.get(this);

  set programService(ProgramService v) => _programsProperty[this] = v;

  SkipService get skipService => _skipsProperty.get(this);

  set skipService(SkipService v) => _skipsProperty[this] = v;

  CoachLibraryService get coachLibraryService => _coachLibraryProperty.get(this);

  set coachLibraryService(CoachLibraryService v) => _coachLibraryProperty[this] = v;

  ProgramChangeService get programChangeService => _programChangesProperty.get(this);

  set programChangeService(ProgramChangeService v) => _programChangesProperty[this] = v;

  ThreadService get threadService => _threadsProperty.get(this);

  set threadService(ThreadService v) => _threadsProperty[this] = v;

  CoachNoteService get noteService => _notesProperty.get(this);

  set noteService(CoachNoteService v) => _notesProperty[this] = v;

  ReportService get reportService => _reportsProperty.get(this);

  set reportService(ReportService v) => _reportsProperty[this] = v;

  KeyService get keyService => _keysProperty.get(this);

  set keyService(KeyService v) => _keysProperty[this] = v;

  PushService get pushService => _pushProperty.get(this);

  set pushService(PushService v) => _pushProperty[this] = v;

  InvitationService get invitationService => _invitationsProperty.get(this);

  set invitationService(InvitationService v) => _invitationsProperty[this] = v;

  ConnectionsService get connectionsService => _connectionsProperty.get(this);

  set connectionsService(ConnectionsService v) => _connectionsProperty[this] = v;

  DeviceService get deviceService => _devicesProperty.get(this);

  set deviceService(DeviceService v) => _devicesProperty[this] = v;

  ApiTokenService get apiTokenService => _apiTokensProperty.get(this);

  set apiTokenService(ApiTokenService v) => _apiTokensProperty[this] = v;

  OAuthService get oauthService => _oauthProperty.get(this);

  set oauthService(OAuthService v) => _oauthProperty[this] = v;

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
