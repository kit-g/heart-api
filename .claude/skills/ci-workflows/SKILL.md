---
name: ci-workflows
description: Conventions for editing .github/workflows/. Use whenever adding or changing a workflow — encodes the reusable+wrapper structure, PR gating, prod-on-tags (and the deliberate assets exception), action pinning (setup-uv has no floating major tags), caching blocks, and the CI-calls-repo-scripts rule. Triggers: "add a workflow", "change CI", "deploy workflow", "GitHub Actions", editing anything under .github/workflows/.
---

# CI workflow conventions

## Structure: one reusable + thin wrappers

Every workflow family is a reusable workflow (`deploy-api.yml`, `deploy-assets.yml`,
`deploy-firebase.yml`, `exercise-library.yml`) plus thin `-dev` / `-prod` wrappers that
pass account-specific inputs (role ARN, bucket, function name).

- **Reusables are `workflow_call` only — never add `workflow_dispatch` to them.** A
  workflow whose only trigger is `workflow_call` is hidden from the Actions sidebar,
  and dispatch-with-typed-inputs on a reusable is the fat-finger path to prod (hand-typed
  ARNs). Manual runs go through the wrappers' `workflow_dispatch: { }`.
- Wrappers own all triggers, `permissions`, and `concurrency`; reusables own the jobs.
- **Check-only workflows** (`python-checks.yml`, `terraform-checks.yml`) are single
  files, not families: `pull_request` + `push: main` with the same `paths:` filter, and
  they only ever call a repo script (`scripts/tf_checks.sh`) or make target.

## Triggers

- **Dev wrappers**: `push: branches [main]` + `pull_request` + `workflow_dispatch`, all
  with the same `paths:` filter. The paths list must include the workflow files
  themselves (both wrapper and reusable), or workflow edits ship untested.
- **Prod wrappers**: `push: tags ['v*']` + `workflow_dispatch`. No `paths:` with tag
  triggers (path filters don't apply to tags).
- **Deliberate exception**: `deploy-assets-prod.yml` ships prod from `main` pushes, not
  tags. This is intentional — do not "fix" it to match the others.

## PR gating

PRs run test jobs only. The deploy/sync jobs in each reusable are gated with:

```yaml
if: github.event_name != 'pull_request'
```

(For `workflow_call`, `github.event_name` reflects the **caller's** trigger, so this
works from inside the reusable.) Do not add a separate test-only workflow for a family —
the same workflow runs both modes.

## Concurrency

On wrappers:

```yaml
concurrency:
  group: <family>-<env>-${{ github.ref }}
  cancel-in-progress: ${{ github.event_name == 'pull_request' }}
```

Superseded PR runs cancel; deploys never do (two quick merges must queue, not overlap,
against the same Lambda/database).

## Action pinning

- **`astral-sh/setup-uv`: always an exact pin (`@v9.0.0`-style).** Upstream stopped
  publishing floating major tags after v7 — `@v7` resolves but is a dead end Dependabot
  can never advance, and `@v9` does not resolve at all (learned the hard way). Dependabot
  bumps exact pins when new releases appear.
- Other actions use floating majors (`actions/checkout@v7`); Dependabot maintains them
  (grouped minor/patch PRs, `.github/dependabot.yml`).

## Job boilerplate

Python jobs:

```yaml
- uses: astral-sh/setup-uv@v9.0.0        # exact pin, see above
  with:
    enable-cache: true
- run: uv sync --all-packages --frozen   # lockfile-only, never `pip install`
```

Dart jobs (setup-dart doesn't cache):

```yaml
- uses: dart-lang/setup-dart@v1
- uses: actions/cache@v6
  with:
    path: ~/.pub-cache
    key: pub-${{ runner.os }}-${{ hashFiles('**/pubspec.lock') }}
    restore-keys: pub-${{ runner.os }}-
```

Mocks are gitignored, not checked in — jobs that compile/test api or heart_models must
run `dart run build_runner build` first (heart_aws has no build_runner; skip it there).

## CI calls repo scripts — never inline copies

Any check that exists both as a repo script and inline in a workflow WILL drift, and the
drift hides bugs (an inline pg_prove copy is how a broken glob in `db_tests.sh` went
unnoticed for months). CI runs `./scripts/db_tests.sh`, `./scripts/apply_migrations.sh`,
`make` targets — the same entrypoints developers use. If a workflow needs a new check,
put it in a script or make target first, then call it.

## Test reporting

Test jobs write machine-readable output to `$GITHUB_WORKSPACE/test-reports/` and upload
it as `test-report-<name>` artifacts (`if: always()`, short retention); the
`test-summary` job downloads them and renders via `scripts/test_summary.py` into
`$GITHUB_STEP_SUMMARY`. Patterns:

- Dart: `--file-reporter="json:...json"` (plus `--reporter=github` for inline PR
  annotations). Artifact names can't hold `/` — derive `REPORT_NAME` by replacing it.
- pgtap: pipe the script through `tee` into `pgtap.tap` with `set -o pipefail` so the
  suite's exit status survives the pipe.
- The summary job needs `if: always()` — its whole point is the runs that went wrong.

## Verify before pushing

```bash
uv run python -c "import yaml; yaml.safe_load(open('.github/workflows/<file>.yml'))"
```

catches syntax; for anything referencing new actions or tags, confirm the ref actually
exists (`gh api repos/<owner>/<action>/git/matching-refs/tags/<prefix>`) — a bad ref
fails only at run time, in everyone's face.