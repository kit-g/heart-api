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
  weight). Watch-measured energy stays a device-only view in the client.
- Health-backed goals sync their **definition** (target, deadline, cadence); progress for those
  kinds is computed on device and never written server-side.
- Alerts derived from health data use contentless/silent pushes: the server stores only the
  schedule, the device evaluates and composes the notification.
- The server's role around health features is: reference content, algorithm parameters,
  schemas, and coordination — never storage.

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

## Backlog

Feature backlog lives in GitHub issues under the `backlog` label. Each issue body carries
scope, the API-vs-FE boundary notes, and dependencies.
