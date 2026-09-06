---
name: review-handoff
description: Review an autonomous agent's work against this repo's definition of done — a worktree under .claude/worktrees/<name> with its HANDOFF.md, or the PR it became. Verifies instead of trusting the handoff: re-runs make lint/test, checks the diff against the ticket, the device-only health rule, heart_models versioning, migration and endpoint conventions, secrets, and tree hygiene, then writes REVIEW.md beside HANDOFF.md. Agents run it on their own work before handing off. Not the `handoff` skill (that hands a feature off to the app). Triggers: "review the <name> worktree", "review agent work", "review the handoff", "review PR N", "self-review", "is this ready to commit".
---

# Review a handoff

Agent work arrives as an **uncommitted diff in a worktree** plus `HANDOFF.md`; the user reviews,
commits, and opens the PR. This skill is the review. Its stance: **HANDOFF.md is a set of claims,
and every claim gets checked.** The built-in `/code-review` finds bugs in any codebase; this skill
adds what only this repo knows — `docs/handoff.md`, `docs/style.md`, CLAUDE.md, the `add-endpoint` /
`add-migration` / `ci-workflows` skills, and the contract table below.

Two modes, same checklist:

- **Reviewer** (the user, or a session asked to review): report only. Findings go to
  `REVIEW.md`; fixing is a separate ask, because the user is the one who commits.
- **Self-review** (an agent before it writes `HANDOFF.md`): fix what you find, re-run the
  checks, and let `REVIEW.md` record the final state. `HANDOFF.md` then points at it. Anything
  you could not fix becomes an *open end* in the handoff, not a silent pass.

## 1. Locate the target

| Target                        | Where the diff is                                                                                                                                                                 |
|-------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| worktree name (`a1`, `db`, …) | `W=.claude/worktrees/<name>`; `git -C "$W" add -N . && git -C "$W" diff`                                                                                                          |
| self-review                   | you are already in the worktree: `W=.`                                                                                                                                            |
| PR number                     | `gh pr view N`, `gh pr diff N`. Run checks in the worktree it came from if it still exists (`git worktree list`); otherwise review the diff statically and say so in the verdict. |

Everything below runs with `-C "$W"` or from inside it. A worktree produced by a **container**
agent has `.dart_tool` and `.venv` pointing at the container's SDKs — run `make bootstrap` in it
first, or every tool will complain.

Also read, before the diff:

- `$W/HANDOFF.md` — the claims.
- The ticket: `gh issue view N --json title,body -q '.title, .body'` (the number is in the
  handoff's title). In self-review the task text is already in your context.

## 2. Ticket fidelity

List what the ticket asked for, one line each. Map each line to the diff. Then list what the diff
does that the ticket did **not** ask for — an unrelated fix "along the way", a refactor, a new
dependency, a migration the ticket never mentioned. Extra work is not automatically wrong, but it
is a decision for the committer, so it is always a finding, filed under *beyond the ticket*,
never buried in the summary.

## 3. Re-verify

Run the checks yourself. Do not accept "all green" from the handoff.

```sh
make lint                              # dart analyze x3 + ruff
make format-check
make test-dart                         # if api/ or shared/ changed
make db-up && make test-db             # if database/ or api/lib/db changed (host only)
(cd api && dart test --run-skipped -t db)   # same trigger: the db-tagged integration tests
make test-python                       # if firebase/, assets/, or scripts/ changed
make test-tf                           # if infrastructure/ changed
```

Compare with the handoff's verification section. Findings here:

- Any red. Paste the failing output into the review.
- The handoff ran raw `dart test` / `pytest` / `terraform validate` instead of the make targets
  and scripts. Make is the entrypoint (it pins `PGHOST`, wires the plugin cache, runs the same
  matrix as CI); raw commands can pass locally and fail in CI. Flag it — the number may still be
  right, the process was not.
- A container agent launched without `--db` flagged the database suites as not run. That is
  correct behaviour, and it means **you** run them now, before anything else in this section
  counts.
- New tests: do they exist, and do they test the change rather than the framework? Open them.
  Non-trivial SQL with only a mocked route test is untested — a `db`-tagged integration test is
  the requirement.

## 4. Generic correctness

Invoke `/code-review` at **high** effort with `$W` as the path target, and fold its findings in.
Do not restate what it already covers (null-safety, dead code, duplication, efficiency). Your job
is the rest.

## 5. The repo contract

Each row is a check to run, not a box to tick from the handoff.

| Check                                       | How                                                                                                                                                                                                                                                                                                                                                                                                             |
|---------------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| **Health data** — device-only               | `git diff -U0 -- api shared database \| grep -inE 'heart_?rate\|hrv\|sleep\|body_?mass\|resting\|active_?energy\|steps'`. Any hit that is a route input, model field, column, migration, or stored aggregate is the top finding, no exceptions. Workout `calories` must remain the MET estimate; health-backed goals sync definition only; health alerts are contentless pushes. See CLAUDE.md.                    |
| **Shared packages** — versioned in-diff     | `git diff --stat -- shared/heart_models shared/heart_aws`. Any non-test, non-docs change ⇒ that package's pubspec `version:` moved and `CHANGELOG.md` has a new top entry, in this same diff. A removed or re-typed public member is a major and a finding: heart_models changes must stay additive (the app pulls from git `main`).                                                                                  |
| **Migrations** — new files only             | `git diff --name-only --diff-filter=MD -- database/migrations` is empty. New files match `YYYY-MM-DD.slug.sql`. Each new table/function has a pgtap test under `database/tests/` (tables: `plan(N)`; functions: `test__*` + `runtests()`). Columns snake_case; `COMMENT ON` for every object; house style per `add-migration`.                                                                                       |
| **Endpoints** — every step of add-endpoint  | For each new route: input class in `api/lib/inputs/`, service interface in heart_models, query in `queries.dart`, db mixin + the three `db.dart` registrations, the three DI middleware spots, handler, route in `routes/index.dart` **and** `..use(...)` in `buildApp`, `@GenerateMocks` updated. Lists return `Paginated<T>`; handlers never call `req.json()`. camelCase in `toMap`/JSON, snake_case in `fromRow`. |
| **Python** — locked and tested              | `firebase/` or `assets/` code change ⇒ a pytest change beside it. `uv.lock` moved only with a `pyproject.toml` change, and vice versa. No `pip install` in scripts or workflows.                                                                                                                                                                                                                                 |
| **CI** — scripts, not inline copies         | Workflow diffs: any check that also exists as a script/make target is called, not copied. `paths:` filters include the workflow file itself. `astral-sh/setup-uv` stays an exact pin. Reusables have no `workflow_dispatch`.                                                                                                                                                                                       |
| **Infrastructure** — plan only              | `make test-tf` green. The handoff shows no `terraform apply` (the guard blocks it; check anyway). Provider `version` pins live in `environments/*/providers.tf`, never in a `stack/` or `modules/` file. `terraform fmt` clean.                                                                                                                                                                                     |
| **Content** — validated                     | `content/` changes: `uv run python scripts/validate_library.py` passes. Localized overlays under `content/i18n/` edited only for the locale the ticket names.                                                                                                                                                                                                                                                      |
| **Secrets**                                 | `git diff \| grep -inE 'AKIA\|aws_secret\|password\|token\|postgres://'` over added lines. Anything real is a finding above everything else, and so is a `secrets/*.json` or `supabase.json` body pasted into a doc, test fixture, or the handoff.                                                                                                                                                                  |
| **Style** — `docs/style.md`                 | Every entry there is a finding. Quick tells over the diff hunks: parsing inside a handler; `as` casts where a `switch` pattern belongs; a multi-line ternary; a `try`/`catch` that only rethrows; a second query where one CTE would do; a write without `RETURNING`; a server-only type added to `heart_models`; `kit-g/` in prose. Comments that narrate the next line instead of the reason.                                                                                                                                                              |
| **Dependencies**                            | A new `pubspec.yaml` or `pyproject.toml` entry is a finding to surface (not reject): what it is for, whether the lockfile moved only for it.                                                                                                                                                                                                                                                                       |

## 6. Tree hygiene

```sh
git -C "$W" status --short          # everything the committer is about to pick up
git -C "$W" diff --stat
```

- Generated or ignored files must **not** appear in the diff: `*.mocks.dart`, `.dart_tool`,
  `.terraform`, `.terraform.lock.hcl`, `.venv`, `build/`, `__pycache__`. If one does, the
  ignore rules broke; that is a finding above everything else.
- New files show in `git diff` (the agent ran `git add -N .`). Untracked files listed as `??`
  were not, so the reviewer would miss them — flag and run it.
- Scratch left behind — a throwaway script at the repo root, a debug print, a `TODO(agent)`, a
  commented-out block — is a finding.
- The worktree branch has no commits of its own (`git -C "$W" log --oneline main..HEAD` is
  empty). The never-commit rule is enforced by a hook, so this is a sanity check, not an
  expectation of trouble.

## 7. Host pass

Three things a container may not have had; if the diff needs any of them, the reviewer does them.

1. **Database suites** — `make db-up && make test-db`, then the api's `db`-tagged tests, when
   `database/` or `api/lib/db` changed and the agent ran without `--db`. Section 3 already
   demanded this; confirm it happened.
2. **`terraform plan`** against real dev state when `infrastructure/` changed. `validate` proves
   the config is well-formed; only a plan shows what would actually change. Paste the resource
   summary line into the review. Never apply as part of a review.
3. **Live reads** — when the change depends on something deployed (a queue's real attributes, a
   bucket's actual layout, a Lambda's env), check it with the `heart-dev` profile rather than
   trusting the diff's assumption.

## 8. Open ends → to-dos

Rewrite the handoff's *Open ends* as concrete actions for the committer, one line each, with the
command where there is one (`gh issue comment 72 --body-file build/issue-72-comment.md`). Add any
the review found that the handoff did not mention.

## 9. Write REVIEW.md

At `$W/REVIEW.md` (gitignored, like `HANDOFF.md`). Shape:

```markdown
# Review — <ticket or task>, worktree <name>

**Verdict:** ready to commit | needs changes | needs your eyes (product call / plan output)

## Findings
Ranked, most severe first. Each: what, where (`path:line`), why it matters, what to do.
Group *beyond the ticket* items under their own heading so they read as decisions, not defects.

## Verification
What you ran and what happened — commands and outcomes, not adjectives. Where it differs from
HANDOFF.md, say so.

## Contract
One line per row of section 5, plus tree hygiene and the host pass: verified / failed (→ finding) / n-a.

## To-dos for the committer
From section 8.
```

In the terminal, give the verdict and the findings; the file holds the rest. In self-review, after
fixing, re-run sections 3 and 5 and rewrite `REVIEW.md` so it describes the tree as handed off —
a review that describes a state you then changed is worse than none.
