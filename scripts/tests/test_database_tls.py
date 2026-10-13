from unittest.mock import Mock

import library_locales
import pytest


@pytest.fixture
def connection(monkeypatch):
    for key in ['SECRETS_BUCKET', 'PGHOST', 'PGSSLROOTCERT']:
        monkeypatch.delenv(key, raising=False)
    connect = Mock()
    monkeypatch.setattr(library_locales.psycopg, 'connect', connect)
    return connect


def test_supabase_requires_certificate_and_hostname_verification(monkeypatch, connection):
    monkeypatch.setenv('SECRETS_BUCKET', 'test-bucket')
    monkeypatch.setattr(
        library_locales,
        'fetch_db_creds',
        lambda _: {'host': 'db.example', 'port': 5432, 'user': 'test', 'password': 'test-only'},
    )
    library_locales.connect()
    assert connection.call_args.kwargs['sslmode'] == 'verify-full'
    assert connection.call_args.kwargs['sslrootcert'].endswith('/api/bin/supabase-ca.crt')


@pytest.mark.parametrize('host', ['localhost', '127.0.0.1', '::1'])
def test_local_database_needs_no_custom_ca(monkeypatch, connection, host):
    monkeypatch.setenv('PGHOST', host)
    library_locales.connect()
    assert 'sslmode' not in connection.call_args.kwargs


@pytest.mark.parametrize('host', ['db.example', 'localhost.evil.example', '10.0.0.1'])
def test_remote_pg_environment_also_requires_tls(monkeypatch, connection, host):
    monkeypatch.setenv('PGHOST', host)
    monkeypatch.setenv('PGSSLROOTCERT', '/custom/ca.crt')
    library_locales.connect()
    assert connection.call_args.kwargs['sslmode'] == 'verify-full'
    assert connection.call_args.kwargs['sslrootcert'] == '/custom/ca.crt'
