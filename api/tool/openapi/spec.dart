import 'package:heart/core/openapi/endpoint.dart';
import 'package:heart/routes/me_index.dart';

/// The Developer API's OpenAPI document, built from [meRoutes] as declared.
/// Nothing the server runs builds it: it's committed as `openapi/me.json`, a
/// test holds that file to this, and the site publishes it
/// (`scripts/pages.sh`).
Map<String, Object?> meOpenApi() {
  return openApiDocument(
    meRoutes,
    prefix: tokenPrefix,
    title: 'Heart Developer API',
    version: '1',
    description:
        'Read-only access to your own Heart log with a personal access token. '
        'Published and additive-only: fields and routes are added, never removed or re-meant.',
    servers: const ['https://api.heart-of.me/v1'],
    securitySchemes: {
      'token': {'type': 'http', 'scheme': 'bearer', 'description': 'A personal access token from the app.'},
    },
    everywhere: [
      const .unauthorized('invalid_token', 'a token missing, unknown, revoked or expired'),
      const .new(403, 'insufficient_scope', description: 'a token without the read scope'),
      const .tooManyRequests('rate_limited', 'too many requests for this token'),
    ],
  );
}
