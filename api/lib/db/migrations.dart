import 'dart:io';

import 'package:heart/globals/config.dart';
import 'package:postgres/postgres.dart' as pg;

const _ensureTracking = '''
CREATE TABLE IF NOT EXISTS _schema_migrations (
    filename   TEXT        PRIMARY KEY,
    applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
)
''';

const _appliedFilenames = 'SELECT filename FROM _schema_migrations';

const _recordMigration = 'INSERT INTO _schema_migrations (filename) VALUES (@filename)';

extension Migrations on PostgresConfig {
  /// Applies every `*.sql` file in [directory] not yet recorded in
  /// `_schema_migrations`, in filename order, each in one transaction with its
  /// record, as `scripts/apply_migrations.sh` does: a file applies whole or not
  /// at all, and a failure stops the run there.
  ///
  /// A connection of its own: this runs once a deploy, before the code that
  /// needs the schema takes traffic.
  Future<({List<String> applied, int skipped})> applyMigrations(
    Directory directory, {
    pg.SslMode sslMode = pg.SslMode.require,
  }) async {
    final files = [
      for (final entity in directory.listSync())
        if (entity is File && entity.path.endsWith('.sql')) entity,
    ]..sort((a, b) => a.uri.pathSegments.last.compareTo(b.uri.pathSegments.last));

    final connection = await pg.Connection.open(
      pg.Endpoint(host: host, port: port, database: database, username: user, password: password),
      settings: pg.ConnectionSettings(sslMode: sslMode, applicationName: 'heart-api-migrations'),
    );
    try {
      await connection.execute(_ensureTracking);
      final done = {
        for (final row in await connection.execute(_appliedFilenames)) row.toColumnMap()['filename'] as String,
      };
      final applied = <String>[];
      for (final file in files) {
        final name = file.uri.pathSegments.last;
        if (done.contains(name)) continue;
        final sql = await file.readAsString();
        await connection.runTx((tx) async {
          // simple protocol: a migration is many statements, functions and DO blocks
          await tx.execute(sql, queryMode: pg.QueryMode.simple);
          await tx.execute(pg.Sql.named(_recordMigration), parameters: {'filename': name});
        });
        applied.add(name);
      }
      return (applied: applied, skipped: files.length - applied.length);
    } finally {
      await connection.close();
    }
  }
}
