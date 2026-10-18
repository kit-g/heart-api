# Mobile 1.13 contract

This client uses the exact `heart_models` revision from
[heart-of-yours v1.13.0's lockfile](https://github.com/kit-g/heart-of-yours/blob/4e3be05854422902e5e7594433a4ddc3bcad42c3/pubspec.lock):
`501a6f100a44e8ebb2c83b9e872472e0de4127c1`, version 2.14.0.
Keep this pin when current models change; another supported baseline gets its own directory.

`db/mobile_compatibility_db_test.dart` sends synthetic requests through the current
HTTP app and Postgres, then passes real responses to this separate process. It checks
the old reader's values and unread counts, and sends its serialized save back to the
server. The CDN case passes a newly rendered publication through the same old reader.

`workout-save.json` is synthetic, serialized by this pinned client's `Workout.toMap()`;
its generated exercise start was normalized to the fixture's fixed start. Tests replace
only row identities to keep database runs isolated. Do not regenerate it from current models.

Run `make prepare-compat-tests` once, then `make test-api-db`. `make bootstrap` and
CI prepare it too. The tests fail if this package is missing; they never silently skip.
