import 'dart:io';

import 'package:relic/relic.dart';

abstract interface class AppConfig {
  String get firebaseProjectId;

  factory AppConfig.fromEnv() {
    return _EnvConfig(
      firebaseProjectId: Platform.environment['FIREBASE_PROJECT_ID']!,
    );
  }
}

class _EnvConfig implements AppConfig {
  @override
  final String firebaseProjectId;

  const _EnvConfig({required this.firebaseProjectId});
}

final _configProperty = ContextProperty<AppConfig>('AppConfig');

extension RequestConfig on Request {
  AppConfig get config => _configProperty.get(this);

  set config(AppConfig c) => _configProperty[this] = c;
}
