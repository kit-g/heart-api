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

const _requiredConfig = {
  'CONTENT_BUCKET',
  'ENV',
  'EVENTS_QUEUE_ARN',
  'EVENTS_QUEUE_URL',
  'EVENTS_DLQ',
  'FIREBASE_EVENTS_QUEUE_URL',
  'FIREBASE_PROJECT_ID',
  'MEDIA_DISTRIBUTION',
  'MIN_APP_VERSION',
  'MONITORING_TOPIC_ARN',
  'REGION',
  'SCHEDULE_GROUP',
  'SCHEDULER_ROLE_ARN',
};

enum Env {
  dev,
  prod;

  factory fromString(String? v) {
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

  const new({
    required this.host,
    required this.port,
    required this.database,
    this.user,
    this.password,
  });

  /// The Postgres connection alone, from the same `PG_*` variables the API
  /// Lambda's environment carries — for entrypoints (like the CDN library
  /// publisher) that need a `Database` but none of [AppConfig]'s other,
  /// unrelated required config.
  factory fromEnv() {
    final env = Platform.environment;
    return PostgresConfig(
      host: env['PG_HOST'] ?? 'localhost',
      port: int.tryParse(env['PG_PORT'] ?? '') ?? 5432,
      database: env['PG_DATABASE'] ?? 'heart',
      user: env['PG_USER'],
      password: env['PG_PASSWORD'],
    );
  }

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

/// Everything needed to talk to Apple's identity service on the account's
/// behalf: the Sign in with Apple key, and which clients it may speak for.
///
/// Absent entirely in an environment whose Apple secrets have not been set up —
/// see [AppConfig.apple], which is nullable for exactly that reason.
class AppleConfig {
  /// Apple Developer team, the `iss` of the client secret.
  final String teamId;

  /// Identifies which of the team's keys signed the client secret.
  final String keyId;

  /// The Sign in with Apple private key, PEM-wrapped PKCS#8, exactly as the
  /// `.p8` Apple issues — the file is stored verbatim so rotating it is a
  /// paste rather than a conversion.
  final String privateKey;

  /// The clients this key may sign a secret for, each mapped to the redirect
  /// URI its code exchange needs, or null where none applies.
  ///
  /// There is more than one because Apple issues a code against whichever
  /// client asked for it: a native sign-in names the running app's bundle id,
  /// which differs per platform and per environment, and the web flow names a
  /// Services ID and must echo its redirect back on the exchange.
  final Map<String, String?> clients;

  const new({
    required this.teamId,
    required this.keyId,
    required this.privateKey,
    required this.clients,
  });

  /// Parses `APPLE_CLIENT_IDS`: a comma-separated list of client ids, each
  /// optionally carrying its redirect URI after an `=`.
  static Map<String, String?> _clients(String raw) {
    return Map.fromEntries(
      raw
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .map(
            (entry) => switch (entry.split('=')) {
              [final clientId, final redirect] => MapEntry(clientId, redirect),
              _ => MapEntry(entry, null),
            },
          ),
    );
  }

  /// Null unless every part is present: a half-configured key cannot sign
  /// anything, and reading it as "Apple is set up" would turn a deployment
  /// mistake into a silent no-op at revoke time.
  static AppleConfig? fromEnv(Map<String, String> env) {
    return switch (env) {
      {
        'APPLE_TEAM_ID': String teamId,
        'APPLE_KEY_ID': String keyId,
        'APPLE_PRIVATE_KEY': String privateKey,
        'APPLE_CLIENT_IDS': String clientIds,
      }
          when [teamId, keyId, privateKey, clientIds].every((v) => v.isNotEmpty) =>
        AppleConfig(
          teamId: teamId,
          keyId: keyId,
          privateKey: privateKey,
          clients: _clients(clientIds),
        ),
      _ => null,
    };
  }
}

/// Parses `ALLOWED_ORIGINS`: a comma-separated allowlist. Absent or blank is an
/// empty set rather than a wildcard — an origin has to be named to be trusted.
Set<String> _origins(String? raw) {
  return switch (raw) {
    final String value => value.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toSet(),
    null => const {},
  };
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

  String get monitoringTopicArn;

  String get scheduleGroup;

  Duration get accountDeletionOffset;

  /// Null where the Sign in with Apple secrets are not configured; the
  /// deletion path then skips revocation rather than failing.
  AppleConfig? get apple;

  String get schedulerRoleArn;

  String get eventsQueueArn;

  String get eventsQueueUrl;

  String get firebaseEventsQueueUrl;

  PostgresConfig get db;

  Set<String> get allowedMimeTypes;

  /// Browser origins allowed to call this API, as serialized origins
  /// (`https://heart-of.me`, no trailing slash). Empty in an environment with
  /// no browser client, which is the same thing as CORS being off.
  Set<String> get allowedOrigins;

  /// development flags, allows to call the /events endpoint
  bool get allowNonHttpEvents;

  factory fromEnv() {
    final env = Platform.environment;
    switch (env) {
      case {
            'CONTENT_BUCKET': String contentBucket,
            'ENV': String environment,
            'EVENTS_QUEUE_ARN': String eventsSqsArn,
            'EVENTS_QUEUE_URL': String eventsQueueUrl,
            'EVENTS_DLQ': String dlq,
            'FIREBASE_EVENTS_QUEUE_URL': String firebaseEventsQueueUrl,
            'FIREBASE_PROJECT_ID': String firebaseProjectId,
            'MEDIA_DISTRIBUTION': String mediaDistribution,
            'MIN_APP_VERSION': String version,
            'MONITORING_TOPIC_ARN': String monitoringTopicArn,
            'REGION': String region,
            'SCHEDULE_GROUP': String scheduleGroup,
            'SCHEDULER_ROLE_ARN': String schedulerRoleArn,
          }
          when [region, environment, firebaseProjectId, contentBucket].every((v) => v.isNotEmpty):
        return _EnvConfig(
          awsProfile: env['AWS_PROFILE'],
          awsRegion: region,
          env: Env.fromString(environment),
          firebaseProjectId: firebaseProjectId,
          eventsDlq: dlq,
          monitoringTopicArn: monitoringTopicArn,
          scheduleGroup: scheduleGroup,
          accountDeletionOffset: Duration(
            days: int.tryParse(env['ACCOUNT_DELETION_OFFSET_DAYS'] ?? '') ?? 30,
          ),
          apple: AppleConfig.fromEnv(env),
          schedulerRoleArn: schedulerRoleArn,
          eventsQueueArn: eventsSqsArn,
          eventsQueueUrl: eventsQueueUrl,
          firebaseEventsQueueUrl: firebaseEventsQueueUrl,
          logLevel: env['LOG_LEVEL'] ?? 'ALL',
          testUserId: env['TEST_USER_ID'],
          minimalAppVersion: version,
          shouldCheckVersion: env['SHOULD_CHECK_VERSION']?.toLowerCase() == 'true',
          contentBucket: contentBucket,
          supportedLocales: env['SUPPORTED_LOCALES']?.split(',') ?? ['en'],
          defaultLocale: env['DEFAULT_LOCALE'] ?? 'en',
          mediaDistribution: mediaDistribution,
          allowedMimeTypes: env['ALLOWED_MIME_TYPES']?.split(',').toSet() ?? _defaultMimeTypes,
          allowedOrigins: _origins(env['ALLOWED_ORIGINS']),
          allowNonHttpEvents: bool.tryParse(env['ALLOW_NON_HTTP_EVENTS'] ?? '', caseSensitive: false) ?? false,
          db: PostgresConfig.fromEnv(),
        );
      default:
        final missing = _requiredConfig.where((key) => env[key] == null || env[key]!.isEmpty).toList();
        throw StateError(
          'Missing required environment variables: ${missing.join(', ')}. '
          'Ensure all required configuration values are set.',
        );
    }
  }

  String cdnAssetUrl(String key);
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
  final String monitoringTopicArn;
  @override
  final String scheduleGroup;
  @override
  final Duration accountDeletionOffset;
  @override
  final AppleConfig? apple;
  @override
  final String schedulerRoleArn;
  @override
  final String eventsQueueArn;
  @override
  final String eventsQueueUrl;
  @override
  final String firebaseEventsQueueUrl;
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
  final Set<String> allowedOrigins;
  @override
  final bool allowNonHttpEvents;

  const new({
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
    required this.allowedOrigins,
    required this.allowNonHttpEvents,
    required this.eventsDlq,
    required this.monitoringTopicArn,
    required this.scheduleGroup,
    required this.accountDeletionOffset,
    required this.apple,
    required this.schedulerRoleArn,
    required this.eventsQueueArn,
    required this.eventsQueueUrl,
    required this.firebaseEventsQueueUrl,
  });

  @override
  String cdnAssetUrl(String key) => Uri.https(mediaDistribution, key).toString();
}

final _configProperty = ContextProperty<AppConfig>('AppConfig');

extension RequestConfig on Request {
  AppConfig get config => _configProperty.get(this);

  set config(AppConfig c) => _configProperty[this] = c;
}
