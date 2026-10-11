# Hevy import data

- `dates.json` — the tokens Hevy's two exporters write in their export dates,
  copied from real exports. `months.app` is the month token the app writes
  (`d MMM yyyy, HH:mm`), per language, in all 17 languages; not CLDR: Catalan
  is capitalized, Hindi uses `.`, Spanish is `sep` not `sept`, Russian is
  genitive. `months.web` is hevy.com's (`Intl` medium date, Chrome 154's ICU,
  which Node 20's reproduces), per language, for the 8 of its 13 languages
  whose month is a word (the rest write a number); it differs from the app's
  in Spanish (`sept`) and Russian (`июн.`, `июл.` for `июня`, `июля`).
  `dayPeriods` is every
  word hevy.com puts next to a 12-hour time (`AM`/`PM`, `오전`/`오후`, zh_tw's
  six), split into the morning ones and the rest. No month token means two
  months, and no day-period word is both halves, in any pair of languages or
  exporters, which is why one table of each serves every language.
  `scripts/hevy_dates.py` generates `api/lib/models/hevy_dates.dart` from it
  and asserts both; re-run after editing, the Dart is committed.

Hevy's own catalog — every exercise's title in all 17 languages, which the
app's export writes verbatim — is Hevy's content and stays out of this
repository. It lives in the dev account's static bucket under
`imports/hevy/2026-10-04/` (with every real export, the API dump and the
draft Hevy→Heart mapping; see its `README.md` and `manifest.json`), and
`scripts/import_names.py` loads it into the `import_names` table, which is
where a translated title is resolved on import. The exports the tests read
are copies under `api/test/fixtures/hevy/` (the English app file, and the web
files in all 13 of hevy.com's languages, which carry English titles only; the
German and Korean app files, which carry the translated catalog, are read from
the gitignored `content/assets/hevy/` where present).
