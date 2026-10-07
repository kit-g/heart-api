@Tags(['db'])
library;

import 'dart:io';

import 'package:heart/db/cron.dart';
import 'package:heart/globals/config.dart';
import 'package:postgres/postgres.dart' as pg;
import 'package:test/test.dart';

import 'db_test_utility.dart';

/// Declaring the database's pg_cron jobs, against a live Postgres. pg_cron
/// isn't installed locally or in CI, so the declaring case runs against
/// stand-in `cron` functions that record their calls.
///
/// Tagged `db` — skipped by the default `dart test`. Run with:
///   dart test --run-skipped -t db
void main() {
  final h = _Harness();
  final env = Platform.environment;
  final database = env['PGDATABASE'] ?? 'heart';
  final config = PostgresConfig(
    host: env['PGHOST'] ?? 'localhost',
    port: int.parse(env['PGPORT'] ?? '5432'),
    database: database,
    user: env['PGUSER'] ?? env['USER'],
    password: env['PGPASSWORD'],
  );
  // pg_cron would live elsewhere; here the jobs' database stands in for it
  Future<int?> declare() => config.declareCronJobs(cronDatabase: database, sslMode: pg.SslMode.disable);

  setUpAll(h.setupDatabase);
  tearDownAll(h.teardownDatabase);

  test('without pg_cron nothing is declared, and that is not an error', () async {
    expect(await h.exec("SELECT 1 FROM pg_namespace WHERE nspname = 'cron'", {}), isEmpty);
    expect(await declare(), isNull);
  });

  test('with pg_cron each job is declared to run in the app database', () async {
    for (final statement in [
      'CREATE SCHEMA cron',
      'CREATE TABLE cron.calls (jobname TEXT, schedule TEXT, command TEXT, db TEXT)',
      'CREATE FUNCTION cron.schedule_in_database(job_name TEXT, schedule TEXT, command TEXT, database TEXT) '
          'RETURNS BIGINT LANGUAGE sql '
          'AS \$\$ INSERT INTO cron.calls VALUES (job_name, schedule, command, database) RETURNING 1 \$\$',
      'CREATE FUNCTION cron.schedule(job_name TEXT, schedule TEXT, command TEXT) '
          'RETURNS BIGINT LANGUAGE sql '
          'AS \$\$ INSERT INTO cron.calls VALUES (job_name, schedule, command, NULL) RETURNING 1 \$\$',
    ]) {
      await h.exec(statement, {});
    }
    try {
      expect(await declare(), 2);
      final calls = [
        for (final row in await h.exec('SELECT jobname, schedule, command, db FROM cron.calls ORDER BY jobname', {}))
          row.toColumnMap(),
      ];
      expect(calls.map((c) => c['jobname']), ['cron-history-cleanup', 'oauth-cleanup']);
      expect(calls.last, {
        'jobname': 'oauth-cleanup',
        'schedule': '17 4 * * *',
        'command': 'SELECT _clean_up_oauth()',
        'db': database,
      });
      expect(calls.first['command'], contains('cron.job_run_details'));
    } finally {
      await h.exec('DROP SCHEMA cron CASCADE', {});
    }
  });
}

class _Harness extends DatabaseTestBase;
