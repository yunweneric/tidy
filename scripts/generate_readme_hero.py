#!/usr/bin/env python3
"""Frame a screenshot as a macOS window, for the top of the README.

A raw screenshot pasted into a README reads as a rectangle of pixels. The same
image inside a window — rounded corners, traffic lights, a shadow it sits above
rather than in — reads as an app. That is the whole job here: no cropping, no
annotation, just the chrome the screenshot was taken without.

The output is a transparent PNG, so the shadow falls on whichever background
GitHub is rendering (light or dark) rather than on a baked-in colour.

    python3 scripts/generate_readme_hero.py

    # after retaking the screenshot
    python3 scripts/generate_readme_hero.py --source ~/Desktop/dashboard.png

`--source` also *replaces* `docs/dashboard.png`, so the committed source and the
committed hero never drift apart. Take the screenshot of the window alone and
without its shadow:

    screencapture -o -w ~/Desktop/dashboard.png

Requires Pillow (`pip3 install Pillow`).
"""

import argparse
import pathlib

from PIL import Image, ImageDraw, ImageFilter

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCE = ROOT / "docs" / "dashboard.png"
OUT = ROOT / "docs" / "hero.png"

# Wide enough to stay sharp on a HiDPI screen at the ~900px GitHub renders it
# at, small enough that the repository does not carry a 3 MB PNG.
CONTENT_WIDTH = 1600

# The window's own geometry, in points, scaled with the image. macOS's corner
# radius and the traffic lights are fixed sizes on screen, so they have to be
# derived from the screenshot's scale rather than from its pixel size.
REFERENCE_POINT_WIDTH = 1512
CORNER_RADIUS_PT = 16
LIGHT_DIAMETER_PT = 12
LIGHT_ORIGIN_PT = (20, 20)
LIGHT_SPACING_PT = 20

# Traffic lights, in the order macOS draws them.
LIGHTS = ["#FF5F57", "#FEBC2E", "#28C840"]

# AppColorTokens.dark().accent, the same violet the landing page glows with.
GLOW = (139, 121, 255)

PAD_X = 110
PAD_TOP = 80
PAD_BOTTOM = 150


def rounded_mask(size: tuple[int, int], radius: int) -> Image.Image:
    mask = Image.new("L", size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([(0, 0), (size[0] - 1, size[1] - 1)], radius, fill=255)
    return mask


def shadow_layer(canvas: tuple[int, int], box: tuple[int, int, int, int], radius: int,
                 colour: tuple[int, int, int], alpha: int, blur: int, offset: int) -> Image.Image:
    """One blurred copy of the window's silhouette, dropped below it."""
    left, top, width, height = box
    mask = Image.new("L", canvas, 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [(left, top + offset), (left + width, top + height + offset)], radius, fill=alpha
    )
    mask = mask.filter(ImageFilter.GaussianBlur(blur))

    layer = Image.new("RGBA", canvas, colour + (0,))
    layer.putalpha(mask)
    return layer


def draw_traffic_lights(window: Image.Image, scale: float) -> None:
    """The three buttons, at the size and spacing macOS puts them."""
    diameter = LIGHT_DIAMETER_PT * scale
    x, y = (value * scale for value in LIGHT_ORIGIN_PT)
    spacing = LIGHT_SPACING_PT * scale

    # Supersampled, because a 14px circle drawn straight has visibly stepped
    # edges next to a screenshot that was rendered at 2x.
    ss = 4
    lights = Image.new("RGBA", (window.width * ss, window.height * ss), (0, 0, 0, 0))
    draw = ImageDraw.Draw(lights)
    for index, colour in enumerate(LIGHTS):
        cx = (x + index * spacing) * ss
        cy = y * ss
        r = diameter * ss / 2
        draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=colour)

    window.alpha_composite(lights.resize(window.size, Image.LANCZOS))


def build(source: pathlib.Path, out: pathlib.Path) -> None:
    shot = Image.open(source).convert("RGBA")
    height = round(shot.height * CONTENT_WIDTH / shot.width)
    shot = shot.resize((CONTENT_WIDTH, height), Image.LANCZOS)

    scale = CONTENT_WIDTH / REFERENCE_POINT_WIDTH
    radius = round(CORNER_RADIUS_PT * scale)

    window = Image.new("RGBA", shot.size, (0, 0, 0, 0))
    window.paste(shot, (0, 0), rounded_mask(shot.size, radius))
    draw_traffic_lights(window, scale)

    # A hairline, so the window keeps an edge where its content happens to match
    # the page behind it.
    ImageDraw.Draw(window).rounded_rectangle(
        [(0, 0), (window.width - 1, window.height - 1)], radius,
        outline=(255, 255, 255, 38), width=max(1, round(scale)),
    )

    canvas = (window.width + PAD_X * 2, window.height + PAD_TOP + PAD_BOTTOM)
    box = (PAD_X, PAD_TOP, window.width, window.height)
    hero = Image.new("RGBA", canvas, (0, 0, 0, 0))

    # Two shadows, the way the landing page's preview casts them: an accent
    # bloom for colour and a neutral one underneath for weight.
    hero.alpha_composite(shadow_layer(canvas, box, radius, GLOW, 90, 70, 46))
    hero.alpha_composite(shadow_layer(canvas, box, radius, (6, 3, 24), 150, 34, 26))
    hero.alpha_composite(window, (PAD_X, PAD_TOP))

    out.parent.mkdir(parents=True, exist_ok=True)
    hero.save(out, optimize=True)
    print(f"{out.relative_to(ROOT)}  {hero.width}x{hero.height}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=pathlib.Path, default=None,
                        help="a fresh screenshot; also replaces docs/dashboard.png")
    parser.add_argument("--out", type=pathlib.Path, default=OUT)
    args = parser.parse_args()

    if args.source is not None and args.source.resolve() != SOURCE.resolve():
        # Kept at the width the hero is rendered at. A larger copy would be a
        # megabyte of repository for pixels nothing reads.
        shot = Image.open(args.source).convert("RGB")
        if shot.width > CONTENT_WIDTH:
            shot = shot.resize(
                (CONTENT_WIDTH, round(shot.height * CONTENT_WIDTH / shot.width)), Image.LANCZOS
            )
        shot.save(SOURCE, optimize=True)
        print(f"{SOURCE.relative_to(ROOT)}  {shot.width}x{shot.height}")

    build(SOURCE, args.out)


if __name__ == "__main__":
    main()
