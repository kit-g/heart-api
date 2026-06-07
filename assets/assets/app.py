"""
SQS-triggered Lambda entry point for the assets pipeline.

Flow: you upload a raw file to `s3://<content>/exercise-uploads/<Name>.<ext>`;
S3 -> EventBridge -> SQS delivers an 'Object Created' event here. For each one
we render a thumbnail, measure dimensions, write `exercises/<name>/asset.<ext>`
and `exercises/<name>/thumbnail.jpg` back to the same bucket, then hand the API
the S3 keys via the `exercise.asset.processed` event. The API owns the DB and
builds the env-aware CDN links — this service never touches either.

Failed records are reported via partial-batch response so SQS only retries the
ones that errored, not the whole batch.
"""

import json
import logging
import os
from typing import Any

import boto3

from events import Event, ObjectCreated
from process import asset_ext, content_type, dest_keys, exercise_name, render

logging.basicConfig(level=logging.INFO)
log = logging.getLogger(__name__)

_clients: dict[str, Any] = {}


def _client(name: str):
    """
    Lazy, memoized boto3 client — keeps import side-effect-free for tests
    and reuses the connection across warm invocations.
    """
    if name not in _clients:
        _clients[name] = boto3.client(name)
    return _clients[name]


def handler(event: dict[str, Any], _) -> dict[str, Any]:
    def message(record: dict) -> dict | None:
        message_id = record.get('messageId', '?')
        try:
            _dispatch(ObjectCreated.from_eb_rule(json.loads(record['body'])))
            return None
        except Exception:
            log.exception('record %s failed', message_id)
            return {'itemIdentifier': message_id}

    match event:
        case {'Records': list(records)}:
            failures = list(filter(bool, map(message, records)))
            return {'batchItemFailures': failures}
        case _:
            return {'batchItemFailures': []}


def _dispatch(event: Event) -> None:
    match event:
        case ObjectCreated():
            _upload(event.bucket, event.key)


def _upload(bucket: str, key: str) -> None:
    name = exercise_name(key)
    ext = asset_ext(key)

    data = _client('s3').get_object(Bucket=bucket, Key=key)['Body'].read()
    media = render(data)
    asset_key, thumb_key = dest_keys(name, ext)

    s3 = _client('s3')
    s3.put_object(Bucket=bucket, Key=asset_key, Body=data, ContentType=content_type(ext))
    s3.put_object(Bucket=bucket, Key=thumb_key, Body=media.thumbnail_bytes, ContentType='image/jpeg')

    _client('sqs').send_message(
        QueueUrl=os.environ['API_EVENTS_QUEUE_URL'],
        MessageBody=json.dumps(
            {
                'type': 'exercise.asset.processed',
                'name': name,
                'asset': {'key': asset_key, 'width': media.asset.width, 'height': media.asset.height},
                'thumbnail': {
                    'key': thumb_key,
                    'width': media.thumbnail.width,
                    'height': media.thumbnail.height,
                },
            }
        ),
    )

    log.info(
        'processed %s -> %s (%dx%d), thumbnail %dx%d',
        key,
        asset_key,
        media.asset.width,
        media.asset.height,
        media.thumbnail.width,
        media.thumbnail.height,
    )
