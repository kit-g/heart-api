import 'package:heart/models/version.dart';
import 'package:test/test.dart';

void main() {
  test('VersionInfo.toMap exposes commit and deployedAt', () {
    final info = const VersionInfo(commit: 'abc123', deployedAt: '2026-01-01T00:00:00Z');

    expect(info.toMap(), {
      'commit': 'abc123',
      'deployedAt': '2026-01-01T00:00:00Z',
    });
  });
}