# Repo-wide entrypoints. `make test` runs the same matrix CI does.
# Database targets need local Postgres + pgtap (see database/README.md).

.PHONY: bootstrap test test-dart test-db test-python lint format-check db-up db-down db-reset db-seed

bootstrap:
	cd api && dart pub get && dart run build_runner build
	cd shared/heart_aws && dart pub get
	cd shared/heart_models && dart pub get && dart run build_runner build
	uv sync --all-packages
	uv run pre-commit install --hook-type pre-push

test: test-dart test-db test-python

test-dart:
	cd api && dart test
	cd shared/heart_aws && dart test
	cd shared/heart_models && dart test

# Containerized dev database (Postgres 17 + pgtap, see compose.yaml).
# Alternative to a native install; set HEART_DB_PORT if 5432 is taken.
db-up:
	docker compose up --build --wait db

db-down:
	docker compose down

# Clean slate: drops the data volume and replays every migration from zero.
# Needed after editing an already-applied migration — the runner tracks by
# filename and silently skips those otherwise.
db-reset:
	docker compose down -v
	docker compose up --build --wait db

# PGHOST default pinned to localhost: apply_migrations.sh without it falls
# back to fetching Supabase creds and pointing at the shared database.
test-db:
	PGHOST=$${PGHOST:-localhost} PGDATABASE=$${PGDATABASE:-heart} ./scripts/apply_migrations.sh
	./scripts/db_tests.sh

# Deterministic local dataset: migrations, then the exercise library synced
# from content/ into the local database (no AWS involved — the seed script
# only talks S3 when SECRETS_BUCKET is set, which CI does and this does not).
db-seed:
	PGHOST=$${PGHOST:-localhost} PGDATABASE=$${PGDATABASE:-heart} ./scripts/apply_migrations.sh
	PGHOST=$${PGHOST:-localhost} PGDATABASE=$${PGDATABASE:-heart} uv run python scripts/library_locales.py

test-python:
	uv run pytest
	uv run pytest assets/tests -o pythonpath=assets/assets
	uv run pytest scripts/tests -o pythonpath=scripts

lint:
	cd api && dart analyze
	cd shared/heart_aws && dart analyze
	cd shared/heart_models && dart analyze
	uv run ruff check firebase assets scripts

# The invariant is "the whole repo is formatted", so this checks everything
# (minus generated files), not a changed-files subset.
format-check:
	find api shared -name '*.dart' \
		-not -path '*/.dart_tool/*' \
		-not -name '*.mocks.dart' \
		-not -name '*.g.dart' \
		-not -name '*.freezed.dart' \
		-print0 \
		| xargs -0 dart format --output=none --set-exit-if-changed
