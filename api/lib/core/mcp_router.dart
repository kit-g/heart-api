import 'package:heart/db/db.dart';
import 'package:heart/mcp/server.dart';
import 'package:heart/middleware/database.dart';
import 'package:heart/middleware/s3.dart';
import 'package:relic/relic.dart';

/// Where the API attaches the MCP server. Its own function serves the same
/// router at the root of a dedicated host.
const mcpPrefix = '/mcp';

/// The MCP server as a router of its own: one endpoint, JSON-RPC in and out,
/// authenticated per request by the endpoint itself (whether a request counts
/// against the rate limit depends on the JSON-RPC method in its body), and
/// only the services its tools read.
RelicRouter buildMcpRouter({required Database database}) {
  return RelicRouter()
    ..use('/', apiTokensDb(db: database))
    ..use('/', profilesDb(db: database))
    ..use('/', workoutsDb(db: database))
    ..use('/', exercisesDb(db: database))
    ..use('/', templatesDb(db: database))
    ..use('/', templateFoldersDb(db: database))
    ..use('/', goalsDb(db: database))
    ..add(.post, '/', mcpEndpoint)
    ..add(.get, '/.well-known/oauth-protected-resource', mcpResourceMetadata)
    ..add(.get, '/', mcpMethodNotAllowed)
    ..add(.delete, '/', mcpMethodNotAllowed);
}
