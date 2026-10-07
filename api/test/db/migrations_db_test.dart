@Tags(['db'])
library;

import 'dart:io';

import 'package:heart/db/migrations.dart';
import 'package:heart/globals/config.dart';
import 'package:postgres/postgres.dart' as pg;
import 'package:test/test.dart';

import 'db_test_utility.dart';

/// The migration runner a deploy calls through `db.migrate`, against a live
/// Postgres: each test gets a database of its own, created and dropped here.
///
/// Tagged `db` — skipped by the default `dart test`. Run with:
///   dart test --run-skipped -t db
void main() {
  final h = _Harness();
  final env = Platform.environment;

  setUpAll(h.setupDatabase);
  tearDownAll(h.teardownDatabase);

  /// A fresh, empty database for one test, and its config.
  Future<PostgresConfig> scratch(String name) async {
    final database = 'migrations_${name}_${h.token}';
    await h.exec('CREATE DATABASE "$database"', {});
    addTearDown(() => h.exec('DROP DATABASE IF EXISTS "$database" WITH (FORCE)', {}));
    return PostgresConfig(
      host: env['PGHOST'] ?? 'localhost',
      port: int.parse(env['PGPORT'] ?? '5432'),
      database: database,
      user: env['PGUSER'] ?? env['USER'],
      password: env['PGPASSWORD'],
    );
  }

  Future<List<String>> recorded(PostgresConfig config) async {
    final c = await pg.Connection.open(
      pg.Endpoint(
        host: config.host,
        port: config.port,
        database: config.database,
        username: config.user,
        password: config.password,
      ),
      settings: const pg.ConnectionSettings(sslMode: pg.SslMode.disable),
    );
    try {
      return [
        for (final row in await c.execute('SELECT filename FROM _schema_migrations ORDER BY filename'))
          row.toColumnMap()['filename'] as String,
      ];
    } finally {
      await c.close();
    }
  }

  test("the repo's migrations replay from nothing, and a second run applies none", () async {
    final config = await scratch('replay');
    final directory = Directory('../database/migrations');
    final files = [
      for (final f in directory.listSync())
        if (f.path.endsWith('.sql')) f.uri.pathSegments.last,
    ]..sort();

    final first = await config.applyMigrations(directory, sslMode: .disable);
    expect(first.applied, files, reason: 'every file, in filename order');
    expect(first.skipped, 0);
    expect(await recorded(config), files);

    final again = await config.applyMigrations(directory, sslMode: .disable);
    expect(again.applied, isEmpty);
    expect(again.skipped, files.length);
  });

  test('a failing migration stops the run, and leaves nothing of itself behind', () async {
    final config = await scratch('failing');
    final directory = await Directory.systemTemp.createTemp('migrations');
    addTearDown(() => directory.delete(recursive: true));
    File('${directory.path}/2026-01-01.good.sql').writeAsStringSync('CREATE TABLE good (id int);');
    File('${directory.path}/2026-01-02.bad.sql').writeAsStringSync(
      'CREATE TABLE half (id int);\nSELECT no_such_function();',
    );
    File('${directory.path}/2026-01-03.later.sql').writeAsStringSync('CREATE TABLE later (id int);');

    await expectLater(config.applyMigrations(directory, sslMode: .disable), throwsA(isA<pg.ServerException>()));
    expect(await recorded(config), ['2026-01-01.good.sql'], reason: 'the bad file, and everything after it, waits');

    final c = await pg.Connection.open(
      pg.Endpoint(
        host: config.host,
        port: config.port,
        database: config.database,
        username: config.user,
        password: config.password,
      ),
      settings: const pg.ConnectionSettings(sslMode: pg.SslMode.disable),
    );
    try {
      final tables = [
        for (final row in await c.execute("SELECT tablename FROM pg_tables WHERE schemaname = 'public' ORDER BY 1"))
          row.toColumnMap()['tablename'],
      ];
      expect(tables, ['_schema_migrations', 'good'], reason: "the bad file's own table rolled back with it");
    } finally {
      await c.close();
    }
  });
}

class _Harness extends DatabaseTestBase;
