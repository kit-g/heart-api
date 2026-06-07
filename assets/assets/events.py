"""
The assets service consumes S3 "Object Created" events. They arrive as
EventBridge events buffered through SQS (S3 -> EventBridge -> SQS -> this
Lambda), so each SQS record body is the EventBridge envelope. We only care
about the bucket and object key; everything else about how the file got there
is upstream's problem.
"""

from dataclasses import dataclass
from typing import Any, Self


@dataclass(frozen=True)
class ObjectCreated:
    bucket: str
    key: str

    @classmethod
    def from_dict(cls, d: dict[str, Any]) -> Self:
        detail = d['detail']
        return cls(
            bucket=str(detail['bucket']['name']),
            key=str(detail['object']['key']),
        )


Event = ObjectCreated


def parse_event(body: dict[str, Any]) -> Event:
    """
    Returns a typed event for [body]. Raises ValueError on unknown shape.
    """
    match body:
        case {
            'detail-type': 'Object Created', 
            'source': 'aws.s3',
        }:
            return ObjectCreated.from_dict(body)
        case _:
            raise ValueError(f'unexpected event: {body.get('detail-type')!r}')
