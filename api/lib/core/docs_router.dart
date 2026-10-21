import 'dart:convert';

import 'package:heart/core/openapi/endpoint.dart';
import 'package:heart/routes/me_index.dart';
import 'package:relic/relic.dart';

/// Where the API attaches its reference: the spec and a Swagger UI over it.
const docsPrefix = '/docs';

/// The Developer API's OpenAPI document, built from [meRoutes] as declared.
Map<String, Object?> meOpenApi() {
  return openApiDocument(
    meRoutes,
    prefix: tokenPrefix,
    title: 'Heart Developer API',
    version: '1',
    description:
        'Read-only access to your own Heart log with a personal access token. '
        'Published and additive-only: fields and routes are added, never removed or re-meant.',
    securitySchemes: {
      'token': {'type': 'http', 'scheme': 'bearer', 'description': 'A personal access token from the app.'},
    },
    everywhere: [
      const .unauthorized('unauthorized', 'no token, or one revoked or expired'),
      const .tooManyRequests('rate_limited', 'too many requests for this token'),
    ],
  );
}

/// The reference as a router of its own, public: a spec describes nothing a
/// caller can't already send. Attached only where the environment says so.
RelicRouter buildDocsRouter() {
  final spec = jsonEncode(meOpenApi());
  return RelicRouter()
    ..add(.get, '/me.json', respondWith((_) => Response.ok(body: .fromString(spec, mimeType: .json))))
    ..add(.get, '/', respondWith((_) => Response.ok(body: .fromString(_swaggerUi, mimeType: .html))));
}

const _swaggerUi = '''<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Heart Developer API</title>
  <link rel="stylesheet" href="https://unpkg.com/swagger-ui-dist@5.17.14/swagger-ui.css">
</head>
<body>
  <div id="ui"></div>
  <script src="https://unpkg.com/swagger-ui-dist@5.17.14/swagger-ui-bundle.js"></script>
  <script>SwaggerUIBundle({url: location.pathname.replace(/\\/\$/, '') + '/me.json', dom_id: '#ui'});</script>
</body>
</html>
''';
