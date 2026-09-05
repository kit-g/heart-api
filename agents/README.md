# Autonomous agents

Claude Code agents working this repo's backlog in parallel: **containerized**
(broad permissions, hard isolation) and **host-side** (scoped permissions,
your own toolchain and AWS profiles). Work arrives from GitHub issues or a
manual prompt; work leaves as an **uncommitted diff in a per-agent
worktree** — you review and commit, always.

Same shape as `agents/` in the app repo (kit-g/heart-of-yours), built for
this repo's toolchain: the image carries the Dart SDK, uv + Python 3.14,
psql + pg_prove, Terraform, gh, the AWS CLI and Claude Code — no Flutter,
no Docker-in-Docker. The two repos share only the credentials file.

## Quick start

```sh
# once: credentials directory (outside any repo — checkouts get mounted
# into containers wholesale, so secrets can never live in one). Shared with
# the app repo's agents; if you already have it, only AGENT_AWS_ROLE_ARN is new.
mkdir -p ~/.config/heart-agents
cp agents/env.example ~/.config/heart-agents/default.env   # then fill it in
claude setup-token    # → CLAUDE_CODE_OAUTH_TOKEN for the env file

# then, one terminal tab each:
agents/agent a1 --issue 71                     # containerized, headless
agents/agent a2 --task "…" --aws --db          # + read-only dev AWS, + your dev Postgres
agents/host-agent ops --issue 64               # host: terraform plan, live AWS reads
agents/watch a1                                # follow a container's narration
```

No `--task`/`--issue` drops you into an interactive session in the same
isolation (useful for steering); `--shell` gives bash in the container;
`--build` rebuilds the image (after changing the Dockerfile or bumping its
Dart/Terraform pins).

## How the pieces fit

**Isolation.** Each agent runs `claude --worktree <name>`, so edits land in
`.claude/worktrees/<name>` and Claude Code itself blocks writes to the main
checkout. Containers add the hard shell: non-root, default-deny egress
firewall (`init-firewall.sh`), resource caps, and only this repo mounted.
The repo is mounted at its **identical host path** because worktree
metadata records absolute paths.

**Permissions.** Containerized agents run `--permission-mode
bypassPermissions` — sanctioned for exactly this shape: non-root,
firewalled, scoped credentials. The host agent runs `acceptEdits` and leans
on the allowlist in `.claude/settings.local.json`; unlisted commands
prompt, and a headless run cannot answer a prompt, so they fail closed.

**Guardrails.** `.claude/settings.json` wires `hooks/guard.sh` as a
PreToolUse hook for every session in this repo — hooks still fire under
bypassPermissions. Beyond the app repo's rules (no committing or pushing,
no work-destroying git, no recursive force-deletes outside build dirs) it
blocks the ways an agent could reach a shared environment from here:

| Blocked                                                                     | Why                                                                                                      |
|-----------------------------------------------------------------------------|----------------------------------------------------------------------------------------------------------|
| `terraform apply/destroy/import/state rm…`                                  | plan and validate are the agent's tools; applying is yours                                               |
| `apply_migrations.sh` without `PGHOST=` on the command                      | without it the script fetches Supabase creds from S3 and migrates the **shared dev database**            |
| `--profile heart-prod`, `AWS_PROFILE=heart-prod`                            | prod stays yours, on the host too                                                                        |
| mutating `aws` calls (`put`, `update`, `invoke`, `purge`, `s3 cp … s3://`…) | the container's role is read-only anyway; the host agent runs with your profile, so the hook is the line |

`hooks/guard_test.sh` is the regression matrix; run it after touching the
hook. It's a guardrail, not a jail — real containment is the container plus
read-only credentials. One known false positive: a heredoc or `echo` whose
*text* mentions a blocked command in command position trips it (writing a
README that quotes one, say); use the Write tool for such files.

**Verification.** CI's matrix is `ubuntu-latest` and the image has the same
tools, so containers run `make lint`, `make test-dart`, `make test-python`
and `make test-tf` natively. The database needs the host: `make db-up`
yourself, then launch with `--db` — the firewall opens to
`host.docker.internal:5432` and `PG*` are set to the compose database, so
`make test-db` and `cd api && dart test --run-skipped -t db` work inside.
Without `--db` the agent is told to flag those suites in the handoff.

**Review.** Agents finish by writing `HANDOFF.md` at the worktree root
(gitignored) — what changed, verification evidence, the `docs/handoff.md`
checklist with each item done/n-a/flagged, and anything needing the host —
and, for issue-dispatched work, the same summary as an issue comment.
Before writing it they run the `review-handoff` skill on their own tree and
leave `REVIEW.md` beside it. Review with the same skill — "review the a1
worktree" — which re-runs lint and tests, checks the diff against the
ticket and the repo contract, and rewrites `REVIEW.md` with a verdict and
to-dos; then commit yourself. Picking up a container-produced worktree on
the host? Run `make bootstrap` in it first — its `.dart_tool` and `.venv`
point at the container's SDKs.

## Credentials (default.env, shared; per-agent override optional)

| What                      | Scope                                                                                                      | Why this scope                                                                                                                                                                                                                                                                      |
|---------------------------|------------------------------------------------------------------------------------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `CLAUDE_CODE_OAUTH_TOKEN` | from `claude setup-token`                                                                                  | headless auth in containers                                                                                                                                                                                                                                                         |
| `GH_TOKEN`                | fine-grained PAT: heart-api + heart; Contents **Read**, Issues **Read/write**, Metadata Read               | agents read issues and comment; read-only Contents means the token cannot push even if asked to                                                                                                                                                                                     |
| `SENTRY_AUTH_TOKEN`       | project:read, event:read, issue:read                                                                       | triage crashes; no mutation                                                                                                                                                                                                                                                         |
| `AGENT_AWS_ROLE_ARN`      | `heart-agent` role, dev account only, `ReadOnlyAccess` (`infrastructure/global/environments/dev/agent.tf`) | no static secret at all — with `--aws` the launcher assumes the role via your `heart-dev` profile and injects session creds that expire on their own (default 4h; agent needs a restart past that); `--aws` also opens the firewall to AWS ranges in ca-central-1; prod stays yours |

The issue text for `--issue` is fetched on the **host** with your own `gh`
auth before the container starts, so agent PATs stay minimal.

## The list of things one forgets

- **Toolchain pins**: `DART_VERSION` and `TERRAFORM_VERSION` are build-args
  in the Dockerfile; match them to what you run (`dart --version`) and what
  CI runs (`terraform-checks.yml`), then `--build`.
- **Auth persistence**: each agent's `~/.claude` is a named docker volume
  (`heart-api-agent-<name>-claude`), so login/session state survives
  `--rm`. Pub, uv and Terraform-provider caches are shared volumes — first
  `make bootstrap` is slow, later ones aren't.
- **The database is yours to start**: no docker-in-docker, deliberately
  (the socket is root on the host). `make db-up` here, `--db` there. A
  native Postgres owning 5432 is not reachable from a container (Docker's
  host gateway does not reach loopback-only listeners), so put the compose
  database on another port and tell the launcher the same:
  `HEART_DB_PORT=5433 make db-up`, then `HEART_DB_PORT=5433 agents/agent … --db`.
  The variable sets the container's `PGPORT` and the firewall hole together.
- **Migrations in a container**: with `--db`, `PGHOST` is already in the
  environment, but the guard reads the command line, so a bare
  `./scripts/apply_migrations.sh` is still refused. `make test-db` or an
  explicit `PGHOST=… ./scripts/apply_migrations.sh` is the form.
- **No Dart MCP/LSP in containers**: agents fall back to grep. The host
  agent has the full setup.
- **Firewall staleness**: allowed IPs are resolved at container start; big
  CDNs rotate. If egress starts failing mid-run, restart the container.
- **Following along**: containers stream via `agents/watch <name>`; the
  host agent narrates to its own terminal (same rendering — both go through
  `agents/narrate.jq`), with the raw event stream kept in
  `$TMPDIR/heart-agent-<name>.jsonl` for post-mortems.
- **Docker Desktop resources**: each agent is capped at 3 CPUs / 6 GB —
  check the VM allowance covers the number you run plus headroom.
- **Escape hatch**: `AGENT_SKIP_FIREWALL=1` (env file) disables the egress
  lockdown for debugging. Don't leave it on.

## What stays out of reach, on purpose

Pushing anywhere, committing, tagging a release (`v*` tags drive the prod
deploy — the agent PAT cannot push them, and the hook stops the host agent),
prod AWS, `terraform apply`, the shared dev database (migrations only ever
target the host's compose Postgres), other repos (only this one is
mounted), and any env file (they live outside the repos and
`.claude/settings.json` denies reading `~/.config/heart-agents/`).
