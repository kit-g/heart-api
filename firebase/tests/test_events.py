import pytest

from events import AccountDelete, PushNotification, parse_event


class TestParsePushNotification:
    def test_full_payload(self):
        evt = parse_event(
            {
                'type': 'push.notification',
                'tokens': ['t1', 't2'],
                'title': 'Sarah commented on your Push Day',
                'body': 'nice form',
                'data': {'commentId': 'c-1', 'workoutId': 'w-1'},
            }
        )
        assert isinstance(evt, PushNotification)
        assert evt.tokens == ['t1', 't2']
        assert evt.title == 'Sarah commented on your Push Day'
        assert evt.body == 'nice form'
        assert evt.data == {'commentId': 'c-1', 'workoutId': 'w-1'}

    def test_data_defaults_to_empty(self):
        evt = parse_event(
            {'type': 'push.notification', 'tokens': ['t'], 'title': 'x', 'body': 'y'}
        )
        assert evt.data == {}

    def test_coerces_data_values_to_strings(self):
        evt = parse_event(
            {
                'type': 'push.notification',
                'tokens': ['t'],
                'title': 'x',
                'body': 'y',
                'data': {'count': 42},
            }
        )
        # FCM data payloads must be string-to-string; coerce at the edge.
        assert evt.data == {'count': '42'}


class TestParseAccountDelete:
    def test_uid(self):
        evt = parse_event({'type': 'account.delete', 'uid': 'u1'})
        assert isinstance(evt, AccountDelete)
        assert evt.uid == 'u1'


class TestParseUnknown:
    @pytest.mark.parametrize(
        'body', [
            {'type': 'ghost'},
            {'type': None}, {}
        ]
    )
    def test_raises(self, body):
        with pytest.raises(ValueError, match='unknown event type'):
            parse_event(body)