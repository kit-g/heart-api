import 'dart:io' show Platform;

import 'package:postgres/postgres.dart' hide Connection;
import 'package:relic/relic.dart';

const _defaultMimeTypes = {
  'image/jpeg',
  'image/jpg',
  'image/png',
  'image/webp',
  'image/heic',
  'image/gif',
};

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

  String get contentBucket;

  List<String> get supportedLocales;

  String get defaultLocale;

  String get mediaDistribution;

  /// API event DLQ URL
  String get eventsDlq;

  PostgresConfig get db;

  Set<String> get allowedMimeTypes;

  /// development flags, allows to call the /events endpoint
  bool get allowNonHttpEvents;

  factory AppConfig.fromEnv() {
    final env = Platform.environment;
    switch (env) {
      case {
            'REGION': String region,
            'ENV': String environment,
            'FIREBASE_PROJECT_ID': String firebaseProjectId,
            'MIN_APP_VERSION': String version,
            'CONTENT_BUCKET': String contentBucket,
            'MEDIA_DISTRIBUTION': String mediaDistribution,
            'EVENTS_DLQ': String dlq,
          }
          when [region, environment, firebaseProjectId, contentBucket].every((v) => v.isNotEmpty):
        return _EnvConfig(
          awsProfile: env['AWS_PROFILE'],
          awsRegion: region,
          env: Env.fromString(environment),
          firebaseProjectId: firebaseProjectId,
          eventsDlq: dlq,
          logLevel: env['LOG_LEVEL'] ?? 'ALL',
          testUserId: env['TEST_USER_ID'],
          minimalAppVersion: version,
          shouldCheckVersion: env['SHOULD_CHECK_VERSION']?.toLowerCase() == 'true',
          contentBucket: contentBucket,
          supportedLocales: env['SUPPORTED_LOCALES']?.split(',') ?? ['en'],
          defaultLocale: env['DEFAULT_LOCALE'] ?? 'en',
          mediaDistribution: mediaDistribution,
          allowedMimeTypes: env['ALLOWED_MIME_TYPES']?.split(',').toSet() ?? _defaultMimeTypes,
          allowNonHttpEvents: bool.tryParse(env['ALLOW_NON_HTTP_EVENTS'] ?? '', caseSensitive: false) ?? false,
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
          'Ensure REGION, ENV, FIREBASE_PROJECT_ID, CONTENT_BUCKET, EVENTS_DLQ and MEDIA_DISTRIBUTION are set.',
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
  final String contentBucket;
  @override
  final String eventsDlq;
  @override
  final List<String> supportedLocales;
  @override
  final String defaultLocale;
  @override
  final String mediaDistribution;
  @override
  final PostgresConfig db;
  @override
  final Set<String> allowedMimeTypes;
  @override
  final bool allowNonHttpEvents;

  const _EnvConfig({
    required this.env,
    required this.firebaseProjectId,
    required this.logLevel,
    required this.awsRegion,
    this.awsProfile,
    this.testUserId,
    required this.minimalAppVersion,
    required this.shouldCheckVersion,
    required this.contentBucket,
    required this.supportedLocales,
    required this.defaultLocale,
    required this.mediaDistribution,
    required this.db,
    required this.allowedMimeTypes,
    required this.allowNonHttpEvents,
    required this.eventsDlq,
  });

  @override
  String workoutImageUrl(String key) => Uri.https(mediaDistribution, key).toString();
}

final _configProperty = ContextProperty<AppConfig>('AppConfig');

extension RequestConfig on Request {
  AppConfig get config => _configProperty.get(this);

  set config(AppConfig c) => _configProperty[this] = c;
}
