import 'package:relic/relic.dart';

import '../models/version.dart';

Future<VersionInfo> getVersion(final Request req) async {
  const commit = String.fromEnvironment('COMMIT', defaultValue: 'dev');
  const buildTime = String.fromEnvironment('BUILD_TIME', defaultValue: 'unknown');

  return const VersionInfo(commit: commit, deployedAt: buildTime);
}
