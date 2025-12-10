import boto3
from PIL import Image
import io
from urllib.parse import unquote_plus

s3 = boto3.client('s3')

MAX_SIZE = 1024
MAX_BYTES = 1024 * 200


def handler(event: dict, _) -> dict:
    match event:
        case {
            'Records': [
                {
                    's3': {
                        'bucket': {'name': bucket},
                        'object': {'key': key},
                    },
                }
            ]
        }:
            key = unquote_plus(key)

            tagging = s3.get_object_tagging(Bucket=bucket, Key=key)
            tags = {tag['Key']: tag['Value'] for tag in tagging['TagSet']}
            destination = tags.get('destination')

            dst_tags = '&'.join([f'{k}={v}' for k, v in tags.items()])
            if not destination:
                print(f'No destination tag found for {key}, skipping.')
                return {}

            obj = s3.get_object(Bucket=bucket, Key=key)
            raw = obj['Body'].read()

            if len(raw) <= MAX_BYTES:
                try:
                    image = Image.open(io.BytesIO(raw))
                    if max(image.size) <= MAX_SIZE:
                        s3.put_object(
                            Bucket=destination,
                            Key=key,
                            Body=raw,
                            ContentType=obj['ContentType'],
                            Tagging=dst_tags,
                        )
                        print('Uploaded without resizing')
                        return {}
                except Exception as e:
                    print(f'Image check failed, defaulting to resize: {e}')

            with Image.open(io.BytesIO(raw)).convert('RGB') as image:
                image.thumbnail((MAX_SIZE, MAX_SIZE))
                output = io.BytesIO()
                image.save(output, format='JPEG', quality=85)
                output.seek(0)

                s3.put_object(
                    Bucket=destination,
                    Key=key,
                    Body=output,
                    ContentType='image/jpeg',
                    Tagging=dst_tags,
                )
                print('Uploaded resized image')
            return {}

    raise ValueError(event)
