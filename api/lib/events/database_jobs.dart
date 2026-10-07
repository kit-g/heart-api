import 'package:heart/db/cron.dart';
import 'package:heart/globals/config.dart';
import 'package:logging/logging.dart' as logging;
import 'package:relic/relic.dart';

final _logger = logging.Logger('cron');

/// Consumes `db.schedule`, which the deploy sends once the new code is live:
/// declares the database's pg_cron jobs. Safe to repeat; each job is updated
/// by name.
Future<void> declareDatabaseJobs(Request request) async {
  switch (await request.config.db.declareCronJobs()) {
    case null:
      _logger.warning('pg_cron is not installed: the database jobs were not declared and will not run');
    case final int declared:
      _logger.info('declared $declared database jobs');
  }
}
