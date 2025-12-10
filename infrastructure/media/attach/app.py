import os

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


def write(*, user_id: str, workout_id: str, url: str) -> dict:
    return dynamo().update_item(
        TableName=workouts_table,
        Key={
            'PK': {'S': f'USER#{user_id}'},
            'SK': {'S': f'WORKOUT#{workout_id}'},
        },
        UpdateExpression='SET #url = :url',
        ExpressionAttributeNames={'#url': 'image'},
        ExpressionAttributeValues={':url': {'S': url}},
    )


def update_workout_on_image(bucket: str, key: str) -> None:
    tag_set = s3().get_object_tagging(Bucket=bucket, Key=key)
    tags = {tag['Key']: tag['Value'] for tag in tag_set['TagSet']}

    match tags:
        case {'userId': user_id, 'workoutId': workout_id}:
            url = f'{media_distribution}/{key}'
            write(user_id=user_id, workout_id=workout_id, url=url)
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
