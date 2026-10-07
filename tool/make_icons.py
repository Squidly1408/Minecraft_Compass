"""Generates the app logo and launcher icons from the compass frames.

Run from the repo root:  python tool/make_icons.py   (needs Pillow)
"""
import json
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
FRAME = ROOT / "assets/frames/frame_41.png"  # needle pointing up-right (NE)

GRID = 24  # logo is a 24x24 pixel-art tile
BG_TOP = (36, 52, 92)
BG_BOTTOM = (18, 24, 48)
STAR = (230, 230, 255)
STARS = [(3, 3), (19, 2), (21, 7), (2, 15), (20, 19), (6, 21), (11, 1)]
SHADOW = (10, 14, 30)


def compass16() -> Image.Image:
    """The frame at its native 16x16 resolution."""
    return Image.open(FRAME).convert("RGBA").resize((16, 16), Image.NEAREST)


def background_tile() -> Image.Image:
    tile = Image.new("RGBA", (GRID, GRID))
    for y in range(GRID):
        # Banded gradient, 4 rows per band, to keep it blocky.
        t = (y // 4) / (GRID // 4 - 1)
        c = tuple(round(a + (b - a) * t) for a, b in zip(BG_TOP, BG_BOTTOM))
        for x in range(GRID):
            tile.putpixel((x, y), c + (255,))
    for x, y in STARS:
        tile.putpixel((x, y), STAR + (255,))
    return tile


def compass_layer(with_shadow: bool) -> Image.Image:
    layer = Image.new("RGBA", (GRID, GRID), (0, 0, 0, 0))
    comp = compass16()
    if with_shadow:
        alpha = comp.split()[3]
        shadow = Image.new("RGBA", comp.size, SHADOW + (255,))
        shadow.putalpha(alpha.point(lambda a: 160 if a else 0))
        layer.alpha_composite(shadow, (5, 5))
    layer.alpha_composite(comp, (4, 4))
    return layer


def upscale(img: Image.Image, size: int) -> Image.Image:
    """Nearest-neighbour upscale past the target, then crop to exact size."""
    cell = -(-size // img.width)
    big = img.resize((img.width * cell, img.height * cell), Image.NEAREST)
    off = (big.width - size) // 2
    return big.crop((off, off, off + size, off + size))


def shrink(img: Image.Image, size: int) -> Image.Image:
    return img.resize((size, size), Image.LANCZOS) if img.width != size else img


def main() -> None:
    bg = background_tile()
    full = bg.copy()
    full.alpha_composite(compass_layer(with_shadow=True))

    master = upscale(full, 1024)
    master.save(ROOT / "assets/logo.png")
    master.save(ROOT / ".github/logo.png")

    # iOS: opaque icons listed in Contents.json.
    ios = ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
    for entry in json.loads((ios / "Contents.json").read_text())["images"]:
        pts = float(entry["size"].split("x")[0])
        px = round(pts * int(entry["scale"][0]))
        shrink(master, px).convert("RGB").save(ios / entry["filename"])

    # Android legacy icons (48dp) + adaptive icon layers (108dp).
    res = ROOT / "android/app/src/main/res"
    densities = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}
    # Adaptive foreground: compass inside the 66dp safe zone of a 108dp canvas.
    # 27 cells of 4dp each puts the 16-cell compass at 64dp.
    fg_grid = Image.new("RGBA", (27, 27), (0, 0, 0, 0))
    fg_grid.alpha_composite(compass_layer(with_shadow=True).crop((2, 2, 22, 22)), (3, 3))
    fg_master = upscale(fg_grid, 1080)
    bg_master = upscale(bg, 1080)
    for name, scale in densities.items():
        d = res / f"mipmap-{name}"
        d.mkdir(exist_ok=True)
        shrink(master, round(48 * scale)).save(d / "ic_launcher.png")
        shrink(fg_master, round(108 * scale)).save(d / "ic_launcher_foreground.png")
        shrink(bg_master, round(108 * scale)).save(d / "ic_launcher_background.png")

    anydpi = res / "mipmap-anydpi-v26"
    anydpi.mkdir(exist_ok=True)
    (anydpi / "ic_launcher.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@mipmap/ic_launcher_background" />\n'
        '    <foreground android:drawable="@mipmap/ic_launcher_foreground" />\n'
        "</adaptive-icon>\n"
    )


if __name__ == "__main__":
    main()
