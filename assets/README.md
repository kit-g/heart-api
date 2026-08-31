# assets

The assets pipeline. Python 3.12 Lambda, triggered by SQS, that turns a raw
exercise upload into a web-ready asset + thumbnail and tells the API to record
it.

## Why a separate service

Image processing needs Pillow (a C-extension with a chunky binary), and the
Dart API has no image stack at all. Keeping it out of the API keeps that
function slim, and lets this service own the one thing it does. It also keeps
DB credentials out of here entirely: this service only touches S3 and hands
the API S3 keys over SQS — the API owns the database and builds the env-aware
CDN links.

> **Runtime is pinned to python3.12.** Pillow's prebuilt wheels don't run on
> AWS Lambda runtimes above 3.12, so the function, the TF `runtime`, and the CI
> wheel install all target 3.12. Local dev/test runs on the workspace's newer
> interpreter, where Pillow is fine.

## Flow

```
you: uv run python scripts/sync_assets.py --source content/assets --bucket <content>
        │  validates display-name stems against the library, slugifies,
        │  uploads only new/changed files as exercise-uploads/<slug>.<ext>
        ▼  S3 ─ EventBridge (prefix exercise-uploads/) ─ SQS ─▶ this Lambda
                                                                   │ measure dims
                                                                   │ render 320px JPEG thumb (first GIF frame)
                                                                   │ PUT exercises/<slug>/asset.<ext>
                                                                   │ PUT exercises/<slug>/thumbnail.jpg
                                                                   ▼ SQS ─▶ heart-api-events
        API /events ◀─ {type: exercise.asset.processed, key, asset:{key,w,h}, thumbnail:{key,w,h}} ─┘
                          updates the exercises row (link built via cdnAssetUrl)
```

The uploaded file's stem is the exercise's **slug** (`bicycle-crunch.gif` →
`exercises.key`), never its display name — names are renamable, localized
copy. The human collection lives in Drive under display names (mirrored
locally at `content/assets/`, gitignored); `scripts/sync_assets.py` is the
only bridge between the two conventions. Never write `exercises/` by hand —
it is pipeline output.

## Events

| Type           | Source                                  | Handler                         |
|----------------|-----------------------------------------|---------------------------------|
| `Object Created` (EventBridge via SQS) | S3 `exercise-uploads/` prefix | `app._process_upload` → render + store + notify |

Emitted to the API queue: `exercise.asset.processed` with `name` and
`{key, width, height}` for both `asset` and `thumbnail`.

## Layout

```
assets/
├── pyproject.toml    # workspace member; pillow + boto3; uv package=false
├── assets/           # source; flat imports (`from events import ...`)
│   ├── app.py        # Lambda entry; handler = "app.handler"
│   ├── events.py     # typed event parse
│   └── process.py    # pure image + key logic (no AWS)
└── tests/            # pytest
```

Source uses flat imports so the same files work unchanged at the Lambda zip
root. `process.py` is AWS-free so it unit-tests against raw bytes; `app.py` is
thin glue over boto3 + `process`.

## Deploy

Zip-based Python Lambda. Terraform only ships a placeholder; CI builds and
updates the real code (see `.github/workflows/deploy-assets.yml`):

```bash
uv export --package assets --frozen --no-dev --no-hashes > requirements.txt
uv pip install --no-cache-dir --target pkg/ \
  --python-platform aarch64-manylinux2014 --python-version 3.12 \
  --requirements requirements.txt
cp assets/assets/*.py pkg/
( cd pkg && zip -qr ../assets.zip . )
aws lambda update-function-code --function-name heart-assets --zip-file fileb://assets.zip
```

## Local

```bash
uv sync --all-packages                          # root + every workspace member
uv run pytest assets/tests -o pythonpath=assets/assets
```

The scoped `pythonpath` is required: services share module names (`app`,
`events`), so a plain `uv run pytest` (which loads the firebase suite) can't
also resolve this service's modules. Run each service's tests in its own
process. See the note in the root `pyproject.toml`.
