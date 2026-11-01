"""Typed event dataclasses + dispatcher.

The Firebase service is a dumb pipe: it sends pre-built notifications and
deletes pre-resolved auth users. All localization, FCM-token lookup and
push-copy rendering happen upstream in the API event consumer; this service
doesn't know what a comment is.
"""

from dataclasses import dataclass, field
from typing import Any, Self


@dataclass(frozen=True)
class PushNotification:
    tokens: list[str]
    title: str | None = None
    body: str | None = None
    data: dict[str, str] = field(default_factory=dict)
    silent: bool = False
    channel: str | None = None
    collapse_key: str | None = None

    @classmethod
    def from_dict(cls, d: dict[str, Any]) -> Self:
        def text(key: str) -> str | None:
            return str(d[key]) if d.get(key) is not None else None

        return cls(
            tokens=[str(t) for t in d["tokens"]],
            title=text("title"),
            body=text("body"),
            data={k: str(v) for k, v in d.get("data", {}).items()},
            silent=bool(d.get("silent", False)),
            channel=text("channel"),
            collapse_key=text("collapseKey"),
        )


@dataclass(frozen=True)
class AccountDelete:
    uid: str

    @classmethod
    def from_dict(cls, d: dict[str, Any]) -> Self:
        return cls(uid=str(d["uid"]))


Event = PushNotification | AccountDelete


def parse_event(body: dict[str, Any]) -> Event:
    """Returns a typed event for [body]. Raises ValueError on unknown type."""
    match body.get("type"):
        case "push.notification":
            return PushNotification.from_dict(body)
        case "account.delete":
            return AccountDelete.from_dict(body)
        case unknown:
            raise ValueError(f"unknown event type: {unknown!r}")
