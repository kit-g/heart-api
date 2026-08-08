# Postgres with pgtap baked in, for the local dev/test database.
# Version matches CI (deploy-api.yml PG_VERSION) — the reference environment.
FROM postgres:17

RUN apt-get update \
    && apt-get install -y --no-install-recommends postgresql-17-pgtap \
    && rm -rf /var/lib/apt/lists/*
