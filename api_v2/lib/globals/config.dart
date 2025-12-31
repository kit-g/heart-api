import 'dart:io' show Platform;

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

  String? get testUserId;

  String get minimalAppVersion;

  factory AppConfig.fromEnv() {
    switch (Platform.environment) {
      case {
            'REGION': String region,
            'ENV': String env,
            'FIREBASE_PROJECT_ID': String firebaseProjectId,
            'WORKOUTS_TABLE': String table,
            'MIN_APP_VERSION': String version,
          }
          when [region, env, firebaseProjectId, table].every((v) => v.isNotEmpty):
        return _EnvConfig(
          awsProfile: Platform.environment['AWS_PROFILE'],
          awsRegion: region,
          env: Env.fromString(env),
          firebaseProjectId: firebaseProjectId,
          logLevel: Platform.environment['LOG_LEVEL'] ?? 'ALL',
          workoutsTable: table,
          testUserId: Platform.environment['TEST_USER_ID'],
          minimalAppVersion: version,
        );
      default:
        throw StateError(
          'Missing required environment variables. '
          'Ensure REGION, ENV, FIREBASE_PROJECT_ID, and WORKOUTS_TABLE are set.',
        );
    }
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
  @override
  final String? testUserId;
  @override
  final String minimalAppVersion;

  const _EnvConfig({
    required this.env,
    required this.firebaseProjectId,
    required this.logLevel,
    required this.awsRegion,
    required this.workoutsTable,
    this.awsProfile,
    this.testUserId,
    required this.minimalAppVersion,
  });
}

final _configProperty = ContextProperty<AppConfig>('AppConfig');

extension RequestConfig on Request {
  AppConfig get config => _configProperty.get(this);

  set config(AppConfig c) => _configProperty[this] = c;
}
