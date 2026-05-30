# firebase

The Firebase microservice. Python 3.14 Lambda, triggered by SQS, runs everything the API can't reach without the bloated Firebase Admin SDK in process — push notifications and Auth user lifecycle.

## Why a separate service

The Dart API needs ~5 MB of binary to do its job; pulling `firebase-admin` into it for two endpoints would have meant carrying ~45 MB of Google client libraries in every API cold start. Splitting them apart keeps the API slim and lets this service grow into more FB-specific work (FCM topic mgmt, custom claims, etc.) without the API caring.

The API enqueues events to the `heart-firebase-events` SQS queue; this Lambda consumes them.

## Events

| Type              | Payload                                                           | Handler                                    |
|-------------------|-------------------------------------------------------------------|--------------------------------------------|
| `comment.created` | `{tokens: [...], title, body, data: {commentId, workoutId, ...}}` | `notify.send_comment_push` — FCM multicast |
| `account.delete`  | `{uid: "<firebase-uid>"}`                                         | `auth.delete_user` — Admin SDK             |

Add a new event:

1. New `@dataclass(frozen=True)` in `events.py` with a `from_dict` classmethod.
2. Add the `case "your.type": …` branch in `parse_event`.
3. Add a handler module if appropriate.
4. Add the `case YourEvent(): …` branch in `handler._dispatch`.
5. Test in `tests/test_events.py` and `tests/test_handler.py`.

## SA key

The Firebase Admin SDK reads `/var/task/firebase.json`, baked into the deployment zip by the CI workflow:

```bash
aws s3 cp s3://<fb-key.json> pkg/firebase.json
```

Image-embedded → no S3 GetObject per cold start, and key rotation is `aws lambda update-function-code`.

The `FIREBASE_CRED_PATH` env var overrides the default for local testing.

## Layout

```
firebase/
├── pyproject.toml    # workspace member; firebase-admin dep + uv config
├── firebase/         # source modules; flat imports (`from events import ...`)
│   ├── handler.py    # Lambda entry; CMD = "handler.handler"
│   ├── events.py
│   ├── notify.py
│   ├── auth.py
│   └── creds.py
└── tests/            # pytest; importable via pythonpath config at the root pyproject
```

Source uses flat-style imports (`from events import ...`) so the same files work unchanged when copied into the Lambda zip (where they sit at the zip root). Tests rely on `pythonpath = ["firebase/firebase"]` configured in the root `pyproject.toml` so the same imports resolve locally.

## Deploy

Zip-based Python Lambda (no container — `firebase-admin` is ~45 MB unzipped, well under the 250 MB limit). CI flow:

```bash
uv export --package firebase --frozen --no-dev --no-hashes > requirements.txt
pip install --no-cache-dir --target pkg/ -r requirements.txt
cp firebase/firebase/*.py pkg/
aws s3 cp s3://…/secrets/dev/firebase/firebase.json pkg/firebase.json
( cd pkg && zip -qr ../firebase.zip . )
aws lambda update-function-code --function-name heart-firebase --zip-file fileb://firebase.zip
```

`--package firebase` exports just this service's deps (the workspace knows the scope). The handler entry is `handler.handler` — flat module path, since files live at the zip root.

See `.github/workflows/deploy-firebase.yml` (task 17).

## Local

```bash
uv sync --all-packages    # syncs root + every workspace member
uv run pytest             # discovers firebase/tests via root pyproject testpaths
```

Without `--all-packages`, `uv sync` installs only the root project's deps (boto3, pillow) and skips workspace members — `firebase_admin` won't land in the venv.

To exercise a real Firebase call locally:

```bash
FIREBASE_CRED_PATH=/path/to/firebase.json uv run python -c \
  "import sys; sys.path.insert(0, 'firebase/firebase'); from creds import ensure_initialized; ensure_initialized(); print('ok')"
```

## Why typed events instead of dict-passing

Same reason the API uses typed input classes in `api/lib/inputs/`: parse once at the edge, hand the rest of the code a typed object. Saves having `body.get('uid')` sprinkled everywhere with no shape contract. See `api/lib/inputs/README.md` for the philosophy.