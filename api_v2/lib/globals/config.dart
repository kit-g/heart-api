import 'dart:io' show Platform;

import 'package:postgres/postgres.dart' hide Connection;
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

class PostgresConfig {
  final String host;
  final int port;
  final String database;
  final String? user;
  final String? password;

  const PostgresConfig({
    required this.host,
    required this.port,
    required this.database,
    this.user,
    this.password,
  });

  Endpoint get endpoint {
    return Endpoint(
      host: host,
      port: port,
      database: database,
      username: user,
      password: password,
    );
  }
}

abstract interface class AppConfig {
  String get firebaseProjectId;

  Env get env;

  String get logLevel;

  String get awsRegion;

  String? get awsProfile;

  String? get testUserId;

  String get minimalAppVersion;

  bool get shouldCheckVersion;

  String get exerciseBucket;

  List<String> get supportedLocales;

  String get defaultLocale;

  String get mediaDistribution;

  PostgresConfig get db;

  factory AppConfig.fromEnv() {
    final env = Platform.environment;
    switch (env) {
      case {
            'REGION': String region,
            'ENV': String environment,
            'FIREBASE_PROJECT_ID': String firebaseProjectId,
            'MIN_APP_VERSION': String version,
            'EXERCISE_BUCKET': String exerciseBucket,
            'MEDIA_DISTRIBUTION': String mediaDistribution,
          }
          when [region, environment, firebaseProjectId, exerciseBucket].every((v) => v.isNotEmpty):
        return _EnvConfig(
          awsProfile: env['AWS_PROFILE'],
          awsRegion: region,
          env: Env.fromString(environment),
          firebaseProjectId: firebaseProjectId,
          logLevel: env['LOG_LEVEL'] ?? 'ALL',
          testUserId: env['TEST_USER_ID'],
          minimalAppVersion: version,
          shouldCheckVersion: env['SHOULD_CHECK_VERSION']?.toLowerCase() == 'true',
          exerciseBucket: exerciseBucket,
          supportedLocales: env['SUPPORTED_LOCALES']?.split(',') ?? ['en'],
          defaultLocale: env['DEFAULT_LOCALE'] ?? 'en',
          mediaDistribution: mediaDistribution,
          db: PostgresConfig(
            host: env['PG_HOST'] ?? 'localhost',
            port: int.tryParse(env['PG_PORT'] ?? '') ?? 5432,
            database: env['PG_DATABASE'] ?? 'heart',
            user: env['PG_USER'],
            password: env['PG_PASSWORD'],
          ),
        );
      default:
        throw StateError(
          'Missing required environment variables. '
          'Ensure REGION, ENV, FIREBASE_PROJECT_ID, EXERCISE_BUCKET, and MEDIA_DISTRIBUTION are set.',
        );
    }
  }

  String workoutImageUrl(String key);
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
  final String? awsProfile;
  @override
  final String? testUserId;
  @override
  final String minimalAppVersion;
  @override
  final bool shouldCheckVersion;
  @override
  final String exerciseBucket;
  @override
  final List<String> supportedLocales;
  @override
  final String defaultLocale;
  @override
  final String mediaDistribution;
  @override
  final PostgresConfig db;

  const _EnvConfig({
    required this.env,
    required this.firebaseProjectId,
    required this.logLevel,
    required this.awsRegion,
    this.awsProfile,
    this.testUserId,
    required this.minimalAppVersion,
    required this.shouldCheckVersion,
    required this.exerciseBucket,
    required this.supportedLocales,
    required this.defaultLocale,
    required this.mediaDistribution,
    required this.db,
  });

  @override
  String workoutImageUrl(String key) => Uri.https(mediaDistribution, key).toString();
}

final _configProperty = ContextProperty<AppConfig>('AppConfig');

extension RequestConfig on Request {
  AppConfig get config => _configProperty.get(this);

  set config(AppConfig c) => _configProperty[this] = c;
}
