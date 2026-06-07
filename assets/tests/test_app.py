import io
import json

from PIL import Image

import app


def _png(size=(600, 400)) -> bytes:
    buf = io.BytesIO()
    Image.new('RGB', size, color='red').save(buf, format='PNG')
    return buf.getvalue()


def _sqs_event(key: str) -> dict:
    body = {
        'detail-type': 'Object Created',
        'source': 'aws.s3',
        'detail': {'bucket': {'name': 'heart-content'}, 'object': {'key': key}},
    }
    return {'Records': [{'messageId': 'm1', 'body': json.dumps(body)}]}


def _wire(mocker, monkeypatch, *, source_bytes=None):
    monkeypatch.setenv('API_EVENTS_QUEUE_URL', 'https://sqs/heart-api-events')
    s3 = mocker.MagicMock()
    sqs = mocker.MagicMock()
    s3.get_object.return_value = {'Body': io.BytesIO(source_bytes or _png())}
    app._clients.clear()
    mocker.patch.object(app, '_client', side_effect=lambda n: {'s3': s3, 'sqs': sqs}[n])
    return s3, sqs


class TestHandler:
    def test_writes_asset_and_thumbnail_then_notifies_api(self, mocker, monkeypatch):
        s3, sqs = _wire(mocker, monkeypatch)

        result = app.handler(_sqs_event('exercise-uploads/Bicycle Crunch.gif'), None)
        assert result == {'batchItemFailures': []}

        put_keys = {call.kwargs['Key'] for call in s3.put_object.call_args_list}
        assert put_keys == {
            'exercises/Bicycle Crunch/asset.gif',
            'exercises/Bicycle Crunch/thumbnail.jpg',
        }

        sqs.send_message.assert_called_once()
        msg = json.loads(sqs.send_message.call_args.kwargs['MessageBody'])
        assert msg['type'] == 'exercise.asset.processed'
        assert msg['name'] == 'Bicycle Crunch'
        assert msg['asset'] == {'key': 'exercises/Bicycle Crunch/asset.gif', 'width': 600, 'height': 400}
        assert msg['thumbnail']['key'] == 'exercises/Bicycle Crunch/thumbnail.jpg'
        assert max(msg['thumbnail']['width'], msg['thumbnail']['height']) == 320

    def test_original_bytes_are_stored_as_the_asset(self, mocker, monkeypatch):
        source = _png()
        s3, _ = _wire(mocker, monkeypatch, source_bytes=source)

        app.handler(_sqs_event('exercise-uploads/Plank.png'), None)

        asset_put = next(c for c in s3.put_object.call_args_list if c.kwargs['Key'].endswith('/asset.png'))
        assert asset_put.kwargs['Body'] == source
        assert asset_put.kwargs['ContentType'] == 'image/png'

    def test_bad_record_is_reported_not_raised(self, mocker, monkeypatch):
        _wire(mocker, monkeypatch)
        event = {'Records': [{'messageId': 'm1', 'body': 'not json'}]}
        assert app.handler(event, None) == {'batchItemFailures': [{'itemIdentifier': 'm1'}]}
