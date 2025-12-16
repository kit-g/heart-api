import os

import boto3

_dynamo = None
_s3 = None
workouts_table = os.environ.get('WORKOUTS_TABLE')
media_distribution = os.environ.get('MEDIA_DISTRIBUTION')


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


def write(*, user_id: str, workout_id: str, url: str, image_key: str) -> dict:
    pk = f'USER#{user_id}'
    workout_sk = f'WORKOUT#{workout_id}'

    progress_sk = f'PROGRESS#{workout_id}#{image_key}'

    return dynamo().transact_write_items(
        TransactItems=[
            {
                'Update': {
                    'TableName': workouts_table,
                    'Key': {
                        'PK': {'S': pk},
                        'SK': {'S': workout_sk},
                    },
                    'UpdateExpression': 'ADD #images :imageset',
                    'ExpressionAttributeNames': {
                        '#images': 'images',
                    },
                    'ExpressionAttributeValues': {
                        ':imageset': {'SS': [image_key]},
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
                        'image': {'S': url},
                        'image_key': {'S': image_key},
                    },
                }
            },
        ]
    )


def update_workout_on_image(bucket: str, key: str) -> None:
    tag_set = s3().get_object_tagging(Bucket=bucket, Key=key)
    tags = {tag['Key']: tag['Value'] for tag in tag_set['TagSet']}

    match tags:
        case {'userId': user_id, 'workoutId': workout_id}:
            url = f'{media_distribution}/{key}'
            write(user_id=user_id, workout_id=workout_id, url=url, image_key=key)
        case _:
            raise ValueError(f'Invalid tags: {tags}')


def handler(event: dict, _) -> dict:
    print(event)

    match event:
        case {
            'Records': [
                {
                    'eventName': s3_event,
                    's3': {
                        'bucket': {'name': bucket},
                        'object': {'key': key},
                    },
                },
            ],
        } if f'{s3_event}'.startswith('ObjectCreated:'):
            update_workout_on_image(bucket, key)
        case _:
            raise ValueError(f'Invalid event: {event}')
    return {'status': 'ok'}
