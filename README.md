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
├── firebase/                  # Python Lambda: FCM push + Firebase auth cleanup (uv workspace member)
├── assets/                    # Python Lambda: exercise media processing pipeline (uv workspace member)
├── infrastructure/            # Terraform stacks (api, assets, cdn, content, firebase, monitoring)
│                              # + environments/{dev,prod} — see infrastructure/README.md
├── content/                   # Exercise library YAML + schema + sample templates JSON, synced to CDN
├── scripts/                   # Migration runner, db test runner, library sync/validation
├── site/                      # Static marketing/legal pages
├── docs/                      # Dated design docs; handoff.md is the definition of done, style.md the house style
├── agents/                    # Autonomous agent launchers + guard hook (see agents/README.md)
└── .github/workflows/         # CI: deploy-api, deploy-assets, deploy-firebase, exercise-library
                               # (each split into a reusable workflow + dev/prod wrappers)
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
| Side services        | Python 3.13 Lambdas in a uv workspace: `firebase/` (push, auth cleanup), `assets/` (media)   |
| IaC                  | Terraform (with Supabase provider)                                                           |
| CI/CD                | GitHub Actions, OIDC role for AWS                                                            |
| Tests                | Dart `test` + mockito for app code, pgtap for the database, pytest for the Python services   |

## Local development

```bash
make bootstrap   # dart pub get + mocks for all packages, uv sync, git hooks
make db-up       # containerized Postgres 17 + pgtap (skip if you run a native one)
make test        # the full matrix: Dart x3, migrations + pgtap, pytest x3
make lint        # dart analyze x3 + ruff
```

Each suite can also run individually — `make test-dart` / `test-db` / `test-python`,
or the underlying commands directly (see the Makefile and per-component READMEs).

The api package can be run locally against any Postgres + AWS profile — see [api/README.md](api/README.md#local-development).

## Deployment

Every workflow family is a reusable workflow plus thin `-dev` / `-prod` wrappers. Dev ships from
`main` pushes. Prod: api and exercise-library ship from `v*` tags; assets and firebase prod
deploys are currently manual (`workflow_dispatch`). Pull requests run the test jobs only — the
deploy jobs are gated on the event type.

`deploy-api.yml` (api/shared/database changes):

1. Lint, format check, analyze
2. Dart tests across all three packages
3. Database tests: ephemeral Postgres + pgtap via `scripts/db_tests.sh`, then the full api suite
   (including `db`-tagged integration tests) with a coverage floor
4. Apply unapplied migrations to Supabase
5. Build Lambda binary, update function, smoke-test `/version`

`deploy-firebase.yml` / `deploy-assets.yml` (Python changes): pytest, then package and update the
function code.

`exercise-library.yml` (content changes): validate the library YAML against its JSON schema plus
the sync parser, then sync exercises + translations to Postgres (guarded against mass-archiving).

## Conventions

- **Migrations are forward-only.** No down migrations. Wrong schema → write a new migration that fixes it.
- **No comments unless the WHY is non-obvious** — naming carries the WHAT.
- **Single source of truth for shapes.** Anything the client sees lives in `heart_models`; server-only types stay in `api/lib/models`.
- **Boto3-shaped AWS package** — generic, no domain knowledge in `heart_aws`.
