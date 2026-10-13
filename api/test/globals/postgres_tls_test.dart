import 'dart:io';

import 'package:heart/globals/config.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

void main() {
  for (final host in ['localhost', '127.0.0.1', '::1']) {
    test('$host keeps the local database usable without TLS', () {
      final config = PostgresConfig(host: host, port: 5432, database: 'heart');
      expect(config.sslMode, SslMode.disable);
      expect(config.securityContext, isNull);
    });
  }

  for (final host in ['aws-1-ca-central-1.pooler.supabase.com', 'localhost.evil.example', '10.0.0.1']) {
    test('$host requires a verified server certificate', () {
      final config = PostgresConfig(
        host: host,
        port: 5432,
        database: 'heart',
        sslRootCertificate: 'bin/supabase-ca.crt',
      );
      expect(config.sslMode, SslMode.verifyFull);
      expect(config.securityContext, isA<SecurityContext>());
    });
  }

  test('an unavailable trust file fails closed', () {
    const config = PostgresConfig(
      host: 'db.example',
      port: 5432,
      database: 'heart',
      sslRootCertificate: 'missing-ca.crt',
    );
    expect(() => config.securityContext, throwsA(isA<FileSystemException>()));
  });
}
