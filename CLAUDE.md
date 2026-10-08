# heart-go

Backend monorepo for Heart, a workout-tracking app: Dart API (`api/`), shared Dart models
(`shared/heart_models`), Postgres migrations (`database/`), Python Lambda services (`firebase/`,
`assets/`), infrastructure and content pipelines.

## The device-only health rule

The Flutter client reads health data (resting HR, HRV, sleep, steps, active energy, body mass)
from Apple HealthKit / Google Health Connect. **That data never reaches this backend — not raw
samples, not derived aggregates, not rollups.** The OS store is the system of record; the client
keeps only a disposable local mirror. "Your health data never leaves your device" is a promise
made in the app's own copy.

Consequences for API work:

- No route may accept a health-shaped field (`heartRate`, `hrv`, `sleep`, `bodyMass`,
  `restingHeartRate`, active energy readings, …).
- Workout `calories` is the MET-based **estimate only** (public catalog data + user-entered
  weight — never health-store body mass, not even as a prefilled default). Watch-measured
  energy stays a device-only view in the client.
- Health-backed goals sync their **definition** (target, deadline, cadence); progress for those
  kinds is computed on device and never written server-side.
- Alerts derived from health data use contentless/silent pushes: the server stores only the
  schedule, the device evaluates and composes the notification.
- The server's role around health features is: reference content, algorithm parameters,
  schemas, and coordination — never storage.
- Enforced, not just stated: `Request.json()` (`api/lib/core/request.dart`) rejects a body with a
  health-shaped key anywhere in it (`400 health_data`), and `database/tests/public/health_rule.sql`
  fails on a health-named column. The two share one list; extend both together.

## Package versioning

The Flutter app consumes `shared/heart_models` straight from git `main`, so every merged
change is released the moment it lands. Consequences:

- Bump `version:` in the package's pubspec **in the same commit/PR as the change** — never
  batched into a later chore commit.
- Semver by consumer impact: **patch** for fixes and internal changes, **minor** for new
  public API (the normal case — heart_models changes must stay additive), **major** never,
  without coordinating an app migration first.
- Prepend a matching `CHANGELOG.md` entry; that file is what the app side reads to learn
  what a pull brings in.
- Test-, docs-, or lint-only changes don't bump.
- `shared/heart_aws` follows the same rules — its only consumer is `api/`, but the history
  discipline is identical.
- `api/` is not consumed as a package; its pubspec version is inert. API releases are the
  repo tags (`v*`), which drive the prod deploy.

## Compatibility floor

Mobile **1.12** on `heart_models` **2.11.0** is the first store release Heart promotes. Every
build that reaches a phone stays installed for months and cannot be patched, so from that
release on the API, the CDN content and `heart_models` are read by builds we don't control.

- Additive changes are the default and are safe: new routes, new optional fields and keys,
  new values of an existing vocabulary (2.11.0 reads an unknown value tolerantly and carries
  it untouched — `docs/2026-10-05.tolerant-reads.md`), new package members.
- Anything an installed build sends or reads is a contract. Removing, renaming, retyping or
  re-meaning it, tightening what the server accepts, changing a status code or error `code`,
  or changing a `heart_models` signature is a **breaking change**: it gets a migration plan
  before any code (the `breaking-change` skill) and ships in phases, never in one PR.
- Raising the minimal app version (a 426 to every older build) is a product decision,
  announced ahead, never a shortcut for a schema change.
- Every prod release (`v*` tag) carries a compatibility note: each contract change since the
  last tag classified as additive or as a phase of a named plan, and the oldest app version
  it still serves. It lives in `release_notes/v<version>.md`, drafted by the `release` skill,
  committed before the tag, and published as the GitHub release.

## Definition of done

`docs/handoff.md` is the submission checklist for any nontrivial change.
Autonomous agents (`agents/README.md`) finish by writing `HANDOFF.md` (worktree root,
gitignored) and, when dispatched from a GitHub issue, commenting the summary on it;
interactive sessions just meet the list. Agents never commit or push; the user's own
interactive session may. `agents/hooks/guard.sh` enforces that, wired in per tool:
`.claude/settings.json` for Claude Code, `.codex/hooks.json` for Codex.

This file is the single source of truth for both: `AGENTS.md` is a symlink to it, and
`.agents/skills` a symlink to `.claude/skills`. Edit the originals — never a copy.

`docs/style.md` is what the linter cannot say: boundaries, switch-over-cast, SQL shapes, the
casing-by-layer rule, keeping each file's comments in its own layer, and the naming conventions.
Every entry there is a review finding.

# Working across Heart's two repos

Heart is two repositories that ship together:

| Repo                                                        | Role                                                         |
|-------------------------------------------------------------|--------------------------------------------------------------|
| [`heart-api`](https://github.com/kit-g/heart-api)           | backend — Dart API, Postgres, Lambda services, shared models |
| [`heart-of-yours`](https://github.com/kit-g/heart-of-yours) | frontend — Flutter app                                       |

They are coupled by one thing: the **`shared/heart_models` package**, which the app pulls straight
from git `main`.

Refer to them as **`heart-api`** and **`heart-of-yours`**, and to issues as `heart-api#66` /
`heart-of-yours#92` — no `kit-g/` prefix in prose, docs, comments, changelogs or tickets. The owner
appears only where a tool needs the full slug (a `github.com` URL, `gh -R`, an OIDC `repo:` subject). 

## Tickets across the boundary

Each repo owns its own code. A ticket filed in the other repo is a **request**: it lists what
needs to exist (data, fields, endpoints, behaviour, limits), to be met on a best-effort basis.
It never says how — no file lists, schemas, migrations, method signatures, task checklists or
UX. Hard constraints go in only when there is an objective reason (a breaking change, the
device-only health rule, a published contract), and the reason goes with them.

Reading a ticket from the other side, take its specifics as the filer's best guess, not a spec.
Assess it as what this repo has to build to satisfy the need, briefly; don't review the ticket.

Label every ticket an agent files `agent-filed`, in either repo.

The roadmap is the GitHub Project "Heart roadmap" (`gh project … 1 --owner kit-g`). Issues in
`heart-of-yours` join it automatically; issues filed in `heart-api` don't. Add them with
`gh project item-add` and set Status, Line and Tier.