# Hevy lookup tables

Source data for `scripts/hevy_catalog.py`, which generates
`api/lib/models/hevy_catalog.dart` — the two tables the Hevy CSV importer
reads (`WorkoutImport.fromHevyCsv`). Re-run the script after editing either
file; the generated Dart is committed.

- `catalog.json` — Hevy's own exercise catalog, 454 entries: the 451 the
  public API lists (2026-10-04) plus 3 archived ones old histories still carry
  (`Stair Machine`, `Box Squat`, `Farmers Walk (Distance Duration)`). Each has
  its English `title`, Hevy's `type`, and the title in the 16 other app
  languages, extracted from the hevy.com web bundle. The app's export writes
  exactly these titles, verified against real exports in all 17 languages.
- `months.json` — the month token the app writes in export dates
  (`d MMM yyyy, HH:mm`), per language, copied from real exports. Not CLDR:
  Catalan is capitalized, Hindi uses `.`, Spanish is `sep` not `sept`, Russian
  is genitive. No token means two months in any pair of languages, which is
  why one table serves every language.

The full probe bundle (every export, the API dump, the draft Hevy→Heart
mapping) is in the dev account at
`s3://583168578067-ca-central-1-static/imports/hevy/2026-10-04/`; the
exports the tests read are copies under `api/test/fixtures/hevy/`.
