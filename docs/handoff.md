# Definition of done

Applies to any nontrivial change, human or agent. For agents this is the
submission protocol: the run is not finished until every item below is
satisfied or explicitly flagged in the handoff.

(Not to be confused with the `handoff` skill, which hands a finished backend
feature off to the Flutter app. This file is about finishing work *here*.)

## Checklist

1. **Verified** — `make lint` and `make test` pass; record the exact commands
   and outcomes. `make test` is Dart ×3, migrations + pgtap, pytest ×3, and
   the Terraform checks. Targeted suites are fine when the diff is narrow
   (`make test-dart` / `test-db` / `test-python` / `test-tf`), but say which
   ran. The database lives on the host: a container launched with `--db`
   reaches it and runs `make test-db` and the api's db-tagged tests
   (`cd api && dart test --run-skipped -t db`) like anyone else; one
   launched without it runs what it can and **flags those two** for the host.
2. **Health data never reaches the server** — no route, model, column, or
   migration gains a health-shaped field (heart rate, HRV, sleep, body mass,
   resting HR, active energy, steps…). Workout `calories` stays the MET
   estimate. Health-backed goals sync definition only. CLAUDE.md has the
   full rule; a violation is a finding above everything else.
3. **Shared packages** — a change to `shared/heart_models` or
   `shared/heart_aws` bumps `version:` in its pubspec and prepends a
   `CHANGELOG.md` entry in the *same* diff. Additive only: minor for new
   public API, patch for fixes; a removed or changed signature needs an app
   migration first and is out of scope for an agent. Test-, docs- or
   lint-only changes don't bump.
4. **Migrations** — new files only, named `YYYY-MM-DD.slug.sql`; never edit
   one that has been applied anywhere (the runner tracks by filename and
   silently skips it). Every new table or function has a pgtap test under
   `database/tests/`. snake_case columns, house style per the
   `add-migration` skill.
5. **Endpoints** — a new or changed route follows the `add-endpoint` skill
   end to end: input class, service interface, query, db mixin and its
   three registrations, DI middleware, handler, route + middleware wiring in
   `buildApp`, mocks regenerated, route test, and a `db`-tagged integration
   test for any non-trivial SQL. camelCase JSON, snake_case columns.
6. **Python services** — `firebase/` and `assets/` changes carry pytest
   coverage and are ruff-clean; dependencies go through `pyproject.toml` +
   `uv lock`, never a bare install.
7. **CI and infrastructure** — workflow edits follow the `ci-workflows`
   skill (repo scripts, never inline copies; paths filters include the
   workflow itself). Terraform changes pass `make test-tf`; agents **plan,
   never apply**. Provider versions are pinned in each environment's
   `providers.tf`, not in shared modules.
8. **Secrets stay out** — nothing fetched from S3 (`secrets/*.json`,
   `/tmp/supabase.json`), no env files, no tokens or connection strings in
   the diff or in the handoff text.
9. **Style** — `docs/style.md`, the no-nos the linter cannot catch: inputs at the
   boundary, switch over cast-and-branch, one-round-trip SQL with `RETURNING`,
   casing by layer, shapes in one place, repos named without the `kit-g/`
   prefix. Every entry there is a finding.
10. **Git** — never commit or push. Leave work in the tree and run
   `git add -N .` so new files appear in `git diff`.
11. **Self-review** — run the `review-handoff` skill on the finished tree
    before writing the handoff. Fix what it finds, re-run, and leave
    `REVIEW.md` describing the tree as handed off. The reviewer runs the
    same skill, so anything it would catch is cheaper caught here.

## The handoff artifact

Agents write `HANDOFF.md` at the worktree root (gitignored — it is review
material, not product):

- What changed and why, in a few sentences.
- Verification evidence: commands run, results.
- The checklist above, each item marked done / n-a / flagged, with reasons.
- Open ends, and anything that needs the host: database suites, a
  `terraform plan` against real state, a live AWS check.
- A pointer to `REVIEW.md` (also gitignored), the self-review's record.

If the task was dispatched from a GitHub issue, post the same summary as a
comment on that issue — this single outward action is pre-authorized for
agents; nothing else outward is.
