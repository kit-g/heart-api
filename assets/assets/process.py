"""
Pure image + key logic — no AWS, so it unit-tests against bytes alone.

Raw uploads land at `exercise-uploads/<exercise-slug>.<ext>`; the filename stem
is the exercise's stable slug (exercises.key, the content repo's map key), not
its display name — names are renamable copy, S3 keys are not. Processed objects
are written under `exercises/<exercise-slug>/`.
"""

import io
from dataclasses import dataclass

from PIL import Image

SOURCE_PREFIX = 'exercise-uploads/'
DEST_PREFIX = 'exercises/'
THUMBNAIL_NAME = 'thumbnail.jpg'
THUMBNAIL_MAX_EDGE = 320  # longest edge, px

_CONTENT_TYPES = {
    'gif': 'image/gif',
    'png': 'image/png',
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'webp': 'image/webp',
}


@dataclass(frozen=True)
class Dimensions:
    width: int
    height: int


@dataclass(frozen=True)
class ProcessedMedia:
    asset: Dimensions
    thumbnail_bytes: bytes
    thumbnail: Dimensions


def exercise_key(key: str) -> str:
    """
    `exercise-uploads/bicycle-crunch.gif` -> `bicycle-crunch`.

    The stem is the exercise's stable slug (exercises.key), the same key the
    content repo uses — not the display name, which is renamable copy.
    """
    base = key.rsplit('/', 1)[-1]
    stem, dot, _ext = base.rpartition('.')
    return stem if dot else base


def asset_ext(key: str) -> str:
    """
    Lowercased extension without the dot, or '' if none.
    """
    base = key.rsplit('/', 1)[-1]
    _stem, dot, ext = base.rpartition('.')
    return ext.lower() if dot else ''


def content_type(ext: str) -> str:
    return _CONTENT_TYPES.get(ext.lower(), 'application/octet-stream')


def dest_keys(exercise: str, ext: str) -> tuple[str, str]:
    """
    Returns (asset_key, thumbnail_key) under `exercises/<slug>/`.
    """
    asset = f'{DEST_PREFIX}{exercise}/asset.{ext}' if ext else f'{DEST_PREFIX}{exercise}/asset'
    return asset, f'{DEST_PREFIX}{exercise}/{THUMBNAIL_NAME}'


def render(data: bytes) -> ProcessedMedia:
    """
    Measures the source and renders a JPEG thumbnail (longest edge
    [THUMBNAIL_MAX_EDGE]). For animated GIFs this is the first frame; alpha is
    flattened so it encodes cleanly as JPEG.
    """
    with Image.open(io.BytesIO(data)) as img:
        asset = Dimensions(img.width, img.height)

        img.seek(0)  # first frame for animated sources; no-op for stills
        frame = img.convert('RGB')
        frame.thumbnail((THUMBNAIL_MAX_EDGE, THUMBNAIL_MAX_EDGE))

        buf = io.BytesIO()
        frame.save(buf, format='JPEG', quality=82, optimize=True)
        thumbnail = Dimensions(frame.width, frame.height)

    return ProcessedMedia(asset=asset, thumbnail_bytes=buf.getvalue(), thumbnail=thumbnail)
