import 'dart:io';

import 'package:heart/db/db.dart';
import 'package:postgres/postgres.dart' hide Connection;

abstract class DatabaseTestBase {
  late Pool pool;
  late Database db;

  Future<void> setupDatabase() async {
    // Standard PG* env vars with local defaults, so the same harness works on a
    // dev machine (peer auth as the OS user) and in CI (PGUSER=postgres).
    final env = Platform.environment;
    pool = Pool.withEndpoints(
      [
        Endpoint(
          host: env['PGHOST'] ?? 'localhost',
          port: int.parse(env['PGPORT'] ?? '5432'),
          database: env['PGDATABASE'] ?? 'heart',
          username: env['PGUSER'] ?? env['USER'],
          password: env['PGPASSWORD'],
        ),
      ],
      // Local Postgres has no TLS; the default requires it.
      settings: const PoolSettings(
        maxConnectionCount: 5,
        applicationName: 'heart-test',
        sslMode: SslMode.disable,
      ),
    );
    db = Database(pool: pool);
  }

  Future<void> teardownDatabase() async {
    await pool.close();
  }
}
