import 'dart:convert';
import 'dart:io';

import 'package:heart/core/openapi/endpoint.dart';
import 'package:heart/routes/me_index.dart';

const specPath = 'openapi/me.json';

/// Writes the document to [specPath], for the site (`scripts/pages.sh`).
///
///   dart run tool/openapi/spec.dart        (from api/; `make openapi` runs it)
void main() {
  File(specPath)
    ..createSync(recursive: true)
    ..writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(meOpenApi())}\n');
  stdout.writeln('wrote $specPath');
}

/// The Developer API's OpenAPI document, built from [meRoutes] as declared.
/// Nothing the server runs builds it.
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
