import hashlib
import os
from datetime import datetime, timezone

import boto3

_dynamo = None
_s3 = None
workouts_table = os.environ['WORKOUTS_TABLE']
media_distribution = os.environ['MEDIA_DISTRIBUTION']


def dynamo():
    global _dynamo
    if _dynamo is None:
        _dynamo = boto3.client('dynamodb')
    return _dynamo


def s3():
    global _s3
    if _s3 is None:
        _s3 = boto3.client('s3')
    return _s3


def _photo_id(*, event_ts: str, image_key: str) -> str:
    # event_ts is RFC3339 like '2025-12-11T20:41:16.797Z'
    # add a short deterministic suffix to avoid rare collisions and make replays idempotent
    suffix = hashlib.sha256(image_key.encode('utf-8')).hexdigest()[:8]
    return f'{event_ts}~{suffix}'


def write(*, user_id: str, workout_id: str, url: str, image_key: str, event_ts: str) -> dict:
    pk = f'USER#{user_id}'
    workout_sk = f'WORKOUT#{workout_id}'

    photo_id = _photo_id(event_ts=event_ts, image_key=image_key)
    progress_sk = f'PROGRESS#{workout_id}#{photo_id}'

    return dynamo().transact_write_items(
        TransactItems=[
            {
                'Update': {
                    'TableName': workouts_table,
                    'Key': {
                        'PK': {'S': pk},
                        'SK': {'S': workout_sk},
                    },
                    'UpdateExpression': 'SET #url = :url, #key = :key',
                    'ExpressionAttributeNames': {'#url': 'image', '#key': 'image_key'},
                    'ExpressionAttributeValues': {
                        ':url': {'S': url},
                        ':key': {'S': image_key},
                    },
                }
            },
            {
                'Put': {
                    'TableName': workouts_table,
                    'Item': {
                        'PK': {'S': pk},
                        'SK': {'S': progress_sk},
                        'workout_id': {'S': workout_id},
                        'photo_id': {'S': photo_id},
                        'image': {'S': url},
                        'image_key': {'S': image_key},
                    },
                    # (still idempotent for exact retries because photo_id is deterministic from key+event_ts)
                    'ConditionExpression': 'attribute_not_exists(PK) AND attribute_not_exists(SK)',
                }
            },
        ]
    )


def update_workout_on_image(bucket: str, key: str, event_ts: str) -> None:
    tag_set = s3().get_object_tagging(Bucket=bucket, Key=key)
    tags = {tag['Key']: tag['Value'] for tag in tag_set['TagSet']}

    match tags:
        case {'userId': user_id, 'workoutId': workout_id}:
            url = f'{media_distribution}/{key}?v={datetime.now(tz=timezone.utc).isoformat()}'
            write(user_id=user_id, workout_id=workout_id, url=url, image_key=key, event_ts=event_ts)
        case _:
            raise ValueError(f'Invalid tags: {tags}')


def handler(event: dict, _) -> dict:
    print(event)

    match event:
        case {
            'Records': [
                {
                    'eventTime': event_time,
                    'eventName': s3_event,
                    's3': {
                        'bucket': {'name': bucket},
                        'object': {'key': key},
                    },
                },
            ],
        } if f'{s3_event}'.startswith('ObjectCreated:'):
            update_workout_on_image(bucket, key, event_ts=event_time)
        case _:
            raise ValueError(f'Invalid event: {event}')
    return {'status': 'ok'}
