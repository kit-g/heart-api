import 'package:heart/core/mcp_router.dart';
import 'package:heart/core/response.dart';
import 'package:heart/db/db.dart';
import 'package:heart/globals/config.dart';
import 'package:heart/middleware/config.dart';
import 'package:heart/middleware/logging.dart';
import 'package:heart/middleware/origin.dart';
import 'package:relic/relic.dart' hide Logger;

/// The MCP host's whole app (`mcp.heart-of.me`): the MCP router at the root,
/// and nothing of the app's API. Same binary as [buildApp], picked by
/// `HEART_SURFACE=mcp`; its own function, so MCP traffic has its own
/// concurrency and never queues behind the app's.
///
/// [originSecret] locks the app to its CloudFront distribution: the function
/// URL behind it is public. Null (locally, in tests) leaves it open.
RelicApp buildMcpApp({required AppConfig config, required Database database, String? originSecret}) {
  final app = RelicApp()..use('/', requestLogging());
  if (originSecret case final String secret when secret.isNotEmpty) app.use('/', cloudFrontOnly(secret));
  return app
    ..use('/', configuration(override: config))
    ..attach('/', buildMcpRouter(database: database), consume: true)
    ..fallback = requestLogging()(respondWith((_) => JsonResponse.noSuchRoute()));
}
