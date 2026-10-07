import 'dart:convert';
import 'dart:io';

import 'package:heart/globals/config.dart';
import 'package:heart/oauth/protocol.dart';
import 'package:test/test.dart';

/// The site serves the authorization server metadata as a static file per
/// environment. It has to say exactly what the server does.
void main() {
  final environments = {
    'dev': OAuthConfig(
      issuer: Uri.parse('https://dev.heart-of.me'),
      apiBase: Uri.parse('https://dev.api.heart-of.me/v1'),
      mcpResource: 'https://dev.api.heart-of.me/v1/mcp',
    ),
    'prod': OAuthConfig(
      issuer: Uri.parse('https://heart-of.me'),
      apiBase: Uri.parse('https://api.heart-of.me/v1'),
      mcpResource: 'https://api.heart-of.me/v1/mcp',
    ),
  };

  for (final MapEntry(key: env, value: oauth) in environments.entries) {
    test('$env: the site metadata matches the server', () {
      final file = File('../site/.well-known/$env/oauth-authorization-server');
      expect(jsonDecode(file.readAsStringSync()), oauth.toServerMetadata());
    });
  }

  test('the issuer derives the metadata URL clients fetch', () {
    final oauth = environments['prod']!;
    expect(
      oauth.issuer.replace(path: '/.well-known/oauth-authorization-server').toString(),
      'https://heart-of.me/.well-known/oauth-authorization-server',
    );
  });
}
