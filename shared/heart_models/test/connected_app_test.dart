import 'package:heart_models/heart_models.dart';
import 'package:test/test.dart';

void main() {
  final connected = DateTime.utc(2026, 10, 5, 9);

  test('round-trips through toMap and fromJson', () {
    final app = ConnectedApp(
      id: '019a0000-0000-7000-8000-000000000001',
      clientId: 'https://claude.ai/oauth/claude-code-client-metadata',
      name: 'Claude Code',
      scopes: const ['read'],
      resource: 'https://mcp.heart-of.me',
      connectedAt: connected,
    );

    final map = app.toMap();
    expect(map.containsKey('lastUsedAt'), isFalse);
    expect(map['connectedAt'], '2026-10-05T09:00:00.000Z');

    final back = ConnectedApp.fromJson(map);
    expect(back, app);
    expect(back.name, 'Claude Code');
    expect(back.scopes, ['read']);
  });

  test('reads an oauth_grants row', () {
    final app = ConnectedApp.fromRow({
      'id': 'g1',
      'client_id': 'dcr_1',
      'client_name': 'ChatGPT',
      'scopes': ['read'],
      'resource': 'https://mcp.heart-of.me',
      'created_at': connected,
      'last_used_at': connected.add(const Duration(hours: 1)),
    });
    expect(app.lastUsedAt, connected.add(const Duration(hours: 1)));
    expect(app.name, 'ChatGPT');
  });
}
