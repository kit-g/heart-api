import 'dart:io';

import 'package:heart/db/migrations.dart';
import 'package:heart/globals/config.dart';
import 'package:heart_models/heart_models.dart';
import 'package:logging/logging.dart' as logging;
import 'package:relic/relic.dart';

final _logger = logging.Logger('migrations');

/// The migrations bundled beside the binary (the deploy zips them in), or none
/// off Lambda.
Directory get _bundled => Directory('${Platform.environment['LAMBDA_TASK_ROOT'] ?? '.'}/migrations');

/// Handles `db.migrate`, which a deploy sends by invoking the new version
/// directly, before it takes traffic: the code that knows the migrations
/// applies them, with the database credentials only it holds. The deploy reads
/// the answer and stops if it isn't one.
Future<MigrationsApplied> migrate(Request request) async {
  final directory = _bundled;
  if (!directory.existsSync()) throw StateError('no migrations bundled at ${directory.path}');
  final (:applied, :skipped) = await request.config.db.applyMigrations(directory);
  _logger.info('migrations: ${applied.length} applied, $skipped already up to date');
  return MigrationsApplied(applied: applied, skipped: skipped);
}

class MigrationsApplied implements Model {
  final List<String> applied;
  final int skipped;

  const new({required this.applied, required this.skipped});

  @override
  Map<String, dynamic> toMap() => {'applied': applied, 'skipped': skipped};
}
