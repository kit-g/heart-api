import pytest
from events import ObjectCreated


def _object_created(key: str = 'exercise-uploads/Bicycle Crunch.gif') -> dict:
    return {
        'version': '0',
        'detail-type': 'Object Created',
        'source': 'aws.s3',
        'detail': {
            'bucket': {'name': 'heart-content'},
            'object': {'key': key, 'size': 123},
        },
    }


class TestParseObjectCreated:
    def test_extracts_bucket_and_key(self):
        evt = ObjectCreated.from_eb_rule(_object_created())
        assert isinstance(evt, ObjectCreated)
        assert evt.bucket == 'heart-content'
        assert evt.key == 'exercise-uploads/Bicycle Crunch.gif'

    def test_rejects_unknown_detail_type(self):
        with pytest.raises(ValueError):
            ObjectCreated.from_eb_rule({'detail-type': 'Object Deleted', 'source': 'aws.s3', 'detail': {}})

    def test_rejects_non_s3_source(self):
        with pytest.raises(ValueError):
            ObjectCreated.from_eb_rule({'detail-type': 'Object Created', 'source': 'aws.other', 'detail': {}})
