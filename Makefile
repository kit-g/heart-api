# Repo-wide entrypoints. `make test` runs the same matrix CI does.
# Database targets need local Postgres + pgtap (see database/README.md).

.PHONY: bootstrap test test-dart test-db test-python lint

bootstrap:
	cd api && dart pub get && dart run build_runner build --delete-conflicting-outputs
	cd shared/heart_aws && dart pub get
	cd shared/heart_models && dart pub get && dart run build_runner build --delete-conflicting-outputs
	uv sync --all-packages

test: test-dart test-db test-python

test-dart:
	cd api && dart test
	cd shared/heart_aws && dart test
	cd shared/heart_models && dart test

# PGHOST default pinned to localhost: apply_migrations.sh without it falls
# back to fetching Supabase creds and pointing at the shared database.
test-db:
	PGHOST=$${PGHOST:-localhost} PGDATABASE=$${PGDATABASE:-heart} ./scripts/apply_migrations.sh
	./scripts/db_tests.sh

test-python:
	uv run pytest
	uv run pytest assets/tests -o pythonpath=assets/assets
	uv run pytest scripts/tests -o pythonpath=scripts

lint:
	cd api && dart analyze
	cd shared/heart_aws && dart analyze
	cd shared/heart_models && dart analyze
	uv run ruff check firebase assets scripts
