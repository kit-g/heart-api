import 'dart:io';

import 'package:heart/db/db.dart';
import 'package:heart/globals/config.dart';
import 'package:heart/publish/exercise_library.dart';
import 'package:postgres/postgres.dart' hide Connection;

/// Generates the CDN objects under `static/exercises/`: one JSON file per
/// locale (byte-for-byte the `GET /v1/exercises` body for that locale) and
/// the `index.json` manifest. Reuses the server's own `Database` and query
/// code (see `publish/exercise_library.dart`) so the shape cannot drift from
/// the live API.
///
/// Usage: `dart run bin/publish_library.dart <output-dir> <locale1,locale2,...>`
///
/// Connects via the same PG_* variables the API Lambda gets (`PostgresConfig.fromEnv`) —
/// just the database, none of `AppConfig`'s other, unrelated required config.
/// `version` is `GITHUB_SHA` when set (CI), else the local git revision.
Future<void> main(List<String> args) async {
  if (args.length != 2) {
    stderr.writeln('usage: dart run bin/publish_library.dart <output-dir> <locale1,locale2,...>');
    exitCode = 2;
    return;
  }

  final outDir = Directory(args[0]);
  final locales = args[1].split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

  final pool = Pool.withEndpoints(
    [PostgresConfig.fromEnv().endpoint],
    settings: const PoolSettings(maxConnectionCount: 1, applicationName: 'heart-api-publish-library'),
  );
  final database = Database(pool: pool);

  try {
    final version = Platform.environment['GITHUB_SHA'] ?? await _gitRevision();

    final publication = await renderLibraryPublication(
      service: database,
      locales: locales,
      version: version,
      generatedAt: DateTime.now().toUtc(),
    );

    await outDir.create(recursive: true);
    for (final MapEntry(key: locale, value: body) in publication.localeFiles.entries) {
      await File('${outDir.path}/$locale.json').writeAsString(body);
    }
    await File('${outDir.path}/index.json').writeAsString(publication.manifest);
  } finally {
    await pool.close();
  }
}

Future<String> _gitRevision() async {
  final result = await Process.run('git', ['rev-parse', 'HEAD']);
  if (result.exitCode != 0) {
    throw StateError('failed to resolve git revision: ${result.stderr}');
  }
  return (result.stdout as String).trim();
}
