import 'package:heart/db/db.dart';
import 'package:postgres/postgres.dart' hide Connection;

abstract class DatabaseTestBase {
  late Pool pool;
  late Database db;

  Future<void> setupDatabase() async {
    pool = Pool.withEndpoints(
      [Endpoint(host: 'localhost', port: 5432, database: 'heart')],
      settings: const PoolSettings(maxConnectionCount: 5, applicationName: 'heart-test'),
    );
    db = Database(pool: pool);
  }

  Future<void> teardownDatabase() async {
    await pool.close();
  }
}
