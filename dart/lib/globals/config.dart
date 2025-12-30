import 'dart:io';

import 'package:relic/relic.dart';

enum Env {
  dev,
  prod
  ;

  factory Env.fromString(String? v) {
    return switch (v) {
      'dev' || 'd' || 'development' => dev,
      'prod' || 'p' || 'production' => prod,
      _ => throw UnimplementedError('Valid environments are: ${Env.values}'),
    };
  }

  bool get isProd => this == prod;
}

abstract interface class AppConfig {
  String get firebaseProjectId;

  Env get env;

  String get logLevel;

  String get awsRegion;

  String get workoutsTable;

  String? get awsProfile;

  factory AppConfig.fromEnv() {
    return _EnvConfig(
      awsProfile: Platform.environment['AWS_PROFILE'],
      awsRegion: Platform.environment['REGION']!,
      env: Env.fromString(Platform.environment['ENV']!),
      firebaseProjectId: Platform.environment['FIREBASE_PROJECT_ID']!,
      logLevel: Platform.environment['LOG_LEVEL'] ?? 'ALL',
      workoutsTable: Platform.environment['WORKOUTS_TABLE']!,
    );
  }
}

class _EnvConfig implements AppConfig {
  @override
  final Env env;
  @override
  final String firebaseProjectId;
  @override
  final String logLevel;
  @override
  final String awsRegion;
  @override
  final String workoutsTable;
  @override
  final String? awsProfile;

  const _EnvConfig({
    required this.env,
    required this.firebaseProjectId,
    required this.logLevel,
    required this.awsRegion,
    required this.workoutsTable,
    this.awsProfile,
  });
}

final _configProperty = ContextProperty<AppConfig>('AppConfig');

extension RequestConfig on Request {
  AppConfig get config => _configProperty.get(this);

  set config(AppConfig c) => _configProperty[this] = c;
}
