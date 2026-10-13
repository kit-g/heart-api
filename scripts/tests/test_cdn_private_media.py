import json
import subprocess
from pathlib import Path

import pytest

FUNCTION = Path(__file__).resolve().parents[2] / 'infrastructure/app/stacks/cdn/functions/private_media.js'


@pytest.mark.parametrize(
    'uri, denied',
    [
        ('/imports/parked/user/hevy.csv', True),
        ('/exports/id/heart-strong.csv', True),
        ('/uploads/photo.jpg', True),
        ('/exercise-uploads/source.gif', True),
        ('/imports', True),
        ('/%69mports/a.csv', True),
        ('/static/../exports/a.csv', True),
        ('//uploads/a.jpg', True),
        ('/static/%2e%2e/exports/a.csv', True),
        ('/%broken', True),
        ('/static/exercises/en.json', False),
        ('/exercises/squat/video.mp4', False),
        ('/workouts/user/photo.jpg', False),
        ('/avatars/user', False),
        ('/favicon.ico', False),
        ('/static/imports/help.json', False),
    ],
)
def test_public_media_boundary(uri, denied):
    script = FUNCTION.read_text() + '\nconsole.log(JSON.stringify(handler(JSON.parse(process.argv[1]))));'
    event = {'request': {'uri': uri, 'method': 'GET'}}
    result = subprocess.run(['node', '-e', script, json.dumps(event)], check=True, capture_output=True, text=True)
    response = json.loads(result.stdout)
    if denied:
        assert response['statusCode'] == 403
    else:
        assert response == event['request']
