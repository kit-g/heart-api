import 'package:heart/middleware/database.dart';
import 'package:logging/logging.dart' as logging;
import 'package:relic/relic.dart';

final _logger = logging.Logger('oauth');

/// Consumes the daily `oauth.cleanup` event: the OAuth tables' garbage
/// collection. Safe to run twice; a second run finds nothing.
Future<void> oauthCleanup(Request request) async {
  final deleted = await request.oauthService.cleanUpOAuth();
  _logger.info('oauth cleanup: $deleted');
}
