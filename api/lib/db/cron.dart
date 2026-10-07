import 'package:heart/globals/config.dart';
import 'package:postgres/postgres.dart' as pg;

/// Whether pg_cron is installed where this connection landed.
const _cronAvailable = '''
SELECT EXISTS (
    SELECT 1
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'cron'
    AND p.proname = 'schedule_in_database'
) AS available
''';

/// Heart's scheduled database jobs: work that only touches data runs in
/// Postgres, not on AWS. Declaring a job again updates it by name, so this
/// list is the whole truth: a job removed here needs a `cron.unschedule` in
/// the same change. `@database` is the app's database, where each job runs.
const _cronJobs = [
  // 04:17 UTC daily: OAuth rows no flow can use any more
  "SELECT cron.schedule_in_database('oauth-cleanup', '17 4 * * *', 'SELECT _clean_up_oauth()', @database)",
  // 04:47 UTC daily: pg_cron's own run log, which otherwise grows forever
  r"""SELECT cron.schedule(
    'cron-history-cleanup',
    '47 4 * * *',
    $$DELETE FROM cron.job_run_details WHERE end_time < now() - interval '14 days'$$
)""",
];

extension CronJobs on PostgresConfig {
  /// Declares [_cronJobs] through pg_cron, which lives in [cronDatabase]
  /// (Supabase pins it to `postgres`), each to run in this config's database.
  /// Returns how many were declared, or null when pg_cron isn't installed.
  ///
  /// A connection of its own, opened and closed here: the app's pool points
  /// at its own database, and this runs once a deploy.
  Future<int?> declareCronJobs({
    String cronDatabase = 'postgres',
    pg.SslMode sslMode = pg.SslMode.require,
  }) async {
    final connection = await pg.Connection.open(
      pg.Endpoint(host: host, port: port, database: cronDatabase, username: user, password: password),
      settings: pg.ConnectionSettings(sslMode: sslMode, applicationName: 'heart-api-cron'),
    );
    try {
      final available = await connection.execute(_cronAvailable);
      if (available.single.toColumnMap()['available'] != true) return null;
      return await connection.runTx((tx) async {
        for (final job in _cronJobs) {
          await tx.execute(pg.Sql.named(job), parameters: job.contains('@database') ? {'database': database} : null);
        }
        return _cronJobs.length;
      });
    } finally {
      await connection.close();
    }
  }
}
