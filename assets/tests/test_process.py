import io

from PIL import Image
from process import (
    asset_ext,
    content_type,
    dest_keys,
    exercise_name,
    render,
)


def _image_bytes(fmt: str, size: tuple[int, int], mode: str = 'RGB') -> bytes:
    buf = io.BytesIO()
    Image.new(mode, size, color='red').save(buf, format=fmt)
    return buf.getvalue()


class TestKeyHelpers:
    def test_exercise_name_strips_prefix_and_extension(self):
        assert exercise_name('exercise-uploads/Bicycle Crunch.gif') == 'Bicycle Crunch'

    def test_exercise_name_handles_dotted_names(self):
        assert exercise_name('exercise-uploads/Step-up (Dumbbell).gif') == 'Step-up (Dumbbell)'

    def test_asset_ext_lowercased(self):
        assert asset_ext('exercise-uploads/Plank.JPEG') == 'jpeg'

    def test_asset_ext_absent(self):
        assert asset_ext('exercise-uploads/Plank') == ''

    def test_content_type(self):
        assert content_type('gif') == 'image/gif'
        assert content_type('jpeg') == 'image/jpeg'
        assert content_type('mystery') == 'application/octet-stream'

    def test_dest_keys(self):
        asset, thumb = dest_keys('Bicycle Crunch', 'gif')
        assert asset == 'exercises/Bicycle Crunch/asset.gif'
        assert thumb == 'exercises/Bicycle Crunch/thumbnail.jpg'

    def test_dest_keys_without_extension(self):
        asset, _ = dest_keys('Bicycle Crunch', '')
        assert asset == 'exercises/Bicycle Crunch/asset'


class TestRender:
    def test_measures_source_dimensions(self):
        media = render(_image_bytes('PNG', (600, 400)))
        assert media.asset.width == 600
        assert media.asset.height == 400

    def test_thumbnail_fits_longest_edge_and_preserves_aspect(self):
        media = render(_image_bytes('PNG', (640, 480)))
        # 640x480 scaled so the longest edge is 320 -> 320x240
        assert max(media.thumbnail.width, media.thumbnail.height) == 320
        assert media.thumbnail.width == 320
        assert media.thumbnail.height == 240

    def test_thumbnail_never_upscales(self):
        media = render(_image_bytes('PNG', (100, 80)))
        assert media.thumbnail.width == 100
        assert media.thumbnail.height == 80

    def test_thumbnail_is_jpeg(self):
        media = render(_image_bytes('PNG', (400, 400)))
        with Image.open(io.BytesIO(media.thumbnail_bytes)) as thumb:
            assert thumb.format == 'JPEG'

    def test_handles_animated_gif_first_frame(self):
        # A 2-frame GIF; render should measure the canvas and thumbnail frame 0.
        buf = io.BytesIO()
        frames = [Image.new('P', (500, 250), color=i) for i in range(2)]
        frames[0].save(buf, format='GIF', save_all=True, append_images=frames[1:])
        media = render(buf.getvalue())
        assert media.asset.width == 500
        assert media.asset.height == 250
        assert media.thumbnail.width == 320
        assert media.thumbnail.height == 160
