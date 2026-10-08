# Hevy import data

- `months.json` — the month token the Hevy app writes in export dates
  (`d MMM yyyy, HH:mm`), per language, copied from real exports in all 17
  languages. Not CLDR: Catalan is capitalized, Hindi uses `.`, Spanish is
  `sep` not `sept`, Russian is genitive. No token means two months in any
  pair of languages, which is why one table serves every language.
  `scripts/hevy_months.py` generates `api/lib/models/hevy_months.dart` from
  it; re-run after editing, the Dart is committed.

Hevy's own catalog — every exercise's title in all 17 languages, which the
app's export writes verbatim — is Hevy's content and stays out of this
repository. It lives in the dev account's static bucket under
`imports/hevy/2026-10-04/` (with every real export, the API dump and the
draft Hevy→Heart mapping; see its `README.md` and `manifest.json`), and
`scripts/import_names.py` loads it into the `import_names` table, which is
where a translated title is resolved on import. The exports the tests read
are copies under `api/test/fixtures/hevy/` (English only; the German and
Korean ones, which carry the translated catalog, are read from the gitignored
`content/assets/hevy/` where present).
