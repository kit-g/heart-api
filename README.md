# Heart of Yours

Backend for the Heart of Yours fitness app. Dart server on AWS Lambda behind API Gateway, Postgres via Supabase, all CDN/storage on AWS.

## Repository layout

```
heart-go/
├── api/                       # Dart server (Lambda entrypoint)
├── shared/
│   ├── heart_models/          # Data classes + service interfaces (used by api + the Flutter client)
│   └── heart_aws/             # Boto3-shaped AWS clients (S3, SQS, SNS, Scheduler) on aws_signature_v4
├── database/
│   ├── migrations/            # Forward-only SQL migrations
│   ├── tests/                 # pgtap suite — public/{tables,functions}, archive/...
│   └── test_utils/            # Test helpers (builders + JSON validators)
├── infrastructure/            # Terraform stacks (api, cdn, content, modules/iam) + environments/dev
├── content/                   # Exercise library YAML + sample templates JSON, synced to CDN
├── scripts/                   # Migration runner, db test runner, library generator
└── .github/workflows/         # CI: deploy-api, exercise-library
```

Per-component docs:
- [api/README.md](api/README.md) — server architecture, routing/db/AWS conventions, testing
- [database/README.md](database/README.md) — migrations + pgtap
- [infrastructure/README.md](infrastructure/README.md) — Terraform stacks + deployment

## Stack

| Layer                | Tech                                                                                         |
|----------------------|----------------------------------------------------------------------------------------------|
| Server runtime       | Dart 3.10 + [relic](https://pub.dev/packages/relic), compiled to native + Lambda Web Adapter |
| Storage              | Postgres (Supabase), no ORM — raw SQL                                                        |
| Object storage / CDN | S3 + CloudFront                                                                              |
| Auth                 | Firebase OIDC token verification                                                             |
| Async                | EventBridge S3-rules → SQS → `/events` (Lambda routes events back to itself)                 |
| Scheduled jobs       | EventBridge Scheduler → SQS → `/events`                                                      |
| IaC                  | Terraform (with Supabase provider)                                                           |
| CI/CD                | GitHub Actions, OIDC role for AWS                                                            |
| Tests                | Dart `test` + mockito for app code, pgtap for the database                                   |

## Local development

```bash
# Dart
cd api && dart pub get && dart test
cd shared/heart_aws && dart pub get && dart test
cd shared/heart_models && dart pub get && dart test

# Database (requires local Postgres + pgtap)
DB_PASSWORD=... DB_HOST_URL=localhost DB_USER=... DB_HOST_PORT=5432 \
  scripts/db_tests.sh
```

The api package can be run locally against any Postgres + AWS profile — see [api/README.md](api/README.md#local-development).

## Deployment

`main` branch pushes trigger `.github/workflows/deploy-api.yml`:

1. Lint, format check, analyze
2. Dart tests across all three packages
3. Database tests (ephemeral Postgres + pgtap)
4. Apply unapplied migrations to Supabase
5. Build Lambda binary, update function, smoke-test `/version`

Content changes (`content/**`) trigger `exercise-library-dev.yml` which regenerates the localized exercise library and uploads it + the sample templates to the CDN bucket.

## Conventions

- **Migrations are forward-only.** No down migrations. Wrong schema → write a new migration that fixes it.
- **No comments unless the WHY is non-obvious** — naming carries the WHAT.
- **Single source of truth for shapes.** Anything the client sees lives in `heart_models`; server-only types stay in `api/lib/models`.
- **Boto3-shaped AWS package** — generic, no domain knowledge in `heart_aws`.
