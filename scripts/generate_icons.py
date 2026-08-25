#!/usr/bin/env python3
"""Render every raster the app icon needs from one vector source.

The mark is "Spark": a Mac screen with a four-point spark inside it, on the
brand violet ramp. It is the design system's own identity rendered as an icon —
`Brand.mark` is already `strokeRoundedSparkles`, and the violet is the brand
`ModulePalette`, so the Dock tile and the app's own sidebar logo are the same
idea drawn at two sizes.

Two flavours come out of it, and they differ in exactly one thing: the ramp
behind the glyph. Prod is the brand violet; dev is amber. Same mark, same grid,
same lighting — so a dev build is unmistakable in the Dock without being a
different logo. See `lib/core/config/flavor.dart` for the other half.

Everything here is generated, never hand-edited: run
`python3 scripts/generate_icons.py` and the PNGs under `assets/icon/` are
rebuilt, then `flutter_launcher_icons` and `flutter_native_splash` fan the
*prod* ones out to the platform folders. The dev macOS icon has no generator to
hand it to — `flutter_launcher_icons` only knows about one icon per platform —
so this script writes `AppIcon-dev.appiconset` into the asset catalog itself.

Requires `rsvg-convert` (brew install librsvg).
"""

import math
import json
import pathlib
import subprocess
from dataclasses import dataclass

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "icon"
SRC = OUT / "src"
CATALOG = ROOT / "macos" / "Runner" / "Assets.xcassets"


@dataclass(frozen=True)
class Flavor:
    """A build flavour's tile colours.

    `ramp` is the top-lit gradient the tile is painted with, `shade` the deep
    colour pooled in its bottom corners, and `shadow` the one the tile casts
    onto the canvas. All three have to move together — an amber tile with a
    violet shadow reads as a rendering bug rather than a different build.
    """

    key: str
    ramp: tuple[tuple[float, str], ...]
    shade: str
    shadow: str


FLAVORS = {
    # The tile ramp, straight off the brand ModulePalette. Light lilac at the
    # top, the brand lift in the middle, a deep violet floor — the same top-lit
    # ramp the app paints its own backdrop with.
    "prod": Flavor(
        key="prod",
        ramp=((0.00, "#D8CCFF"), (0.34, "#9B7CF6"), (1.00, "#5B21B6")),
        shade="#280C5A",
        shadow="#2A0E5E",
    ),
    # Amber, because it is the furthest thing from the brand violet that still
    # looks deliberate: at Dock size the two are never confusable, which is the
    # entire job of a dev icon.
    "dev": Flavor(
        key="dev",
        ramp=((0.00, "#FFE6BE"), (0.34, "#F59E0B"), (1.00, "#B45309")),
        shade="#5A2A05",
        shadow="#5C2C06",
    ),
}


def ramp_defs(id_: str, flavor: Flavor) -> str:
    stops = "".join(
        f'<stop offset="{o}" stop-color="{c}"/>' for o, c in flavor.ramp
    )
    return (
        f'<linearGradient id="{id_}" x1="0" y1="0" x2="0" y2="1">{stops}</linearGradient>'
    )


def glyph(size: float, cx: float, cy: float, ink: str = "#FFFFFF",
          stroke: float = 3.0) -> str:
    """The mark itself, drawn in a 48x48 grid and scaled to `size`.

    `stroke` is in grid units: the small renderings need a heavier pen or the
    screen outline disappears into the tile.

    Deliberately not flavour-aware. The glyph is the product's identity; only
    what sits behind it changes between builds.
    """
    s = size / 48.0
    x, y = cx - size / 2, cy - size / 2
    return f"""<g transform="translate({x:.3f} {y:.3f}) scale({s:.6f})">
    <rect x="7" y="10" width="34" height="23" rx="5" stroke="{ink}" stroke-width="{stroke}" fill="none"/>
    <path d="M20.5 33v4h7v-4M16 39h16" stroke="{ink}" stroke-width="{stroke}" stroke-linecap="round" fill="none"/>
    <path d="M24 14.5c1.3 4.8 3.2 6.7 8 8-4.8 1.3-6.7 3.2-8 8-1.3-4.8-3.2-6.7-8-8 4.8-1.3 6.7-3.2 8-8Z" fill="{ink}"/>
  </g>"""


def squircle(cx: float, cy: float, half: float, n: float = 5.0,
             steps: int = 720) -> str:
    """Apple's continuous corner, as a superellipse rather than an arc.

    A plain `rx` rounded rect reads as visibly *not* a macOS icon next to real
    ones — the corner leaves the straight edge too abruptly. |x|^n + |y|^n = 1
    with n=5 is the shape Apple's grid actually uses.
    """
    pts = []
    for i in range(steps):
        t = 2 * math.pi * i / steps
        ct, st = math.cos(t), math.sin(t)
        px = half * math.copysign(abs(ct) ** (2 / n), ct)
        py = half * math.copysign(abs(st) ** (2 / n), st)
        pts.append(f"{cx + px:.2f},{cy + py:.2f}")
    return "M" + "L".join(pts) + "Z"


def lighting(id_prefix: str, flavor: Flavor) -> str:
    """The two overlays that keep the tile from reading as flat paint.

    A hot line along the top edge (the tile catching the light) and a pooled
    shadow in the bottom corners. Both are the CSS `inset` shadows from the
    design, which SVG has no equivalent for.
    """
    return (
        f'<linearGradient id="{id_prefix}-top" x1="0" y1="0" x2="0" y2="1">'
        f'<stop offset="0" stop-color="#FFFFFF" stop-opacity="0.55"/>'
        f'<stop offset="0.14" stop-color="#FFFFFF" stop-opacity="0"/>'
        f"</linearGradient>"
        f'<linearGradient id="{id_prefix}-bottom" x1="0" y1="0" x2="0" y2="1">'
        f'<stop offset="0.62" stop-color="{flavor.shade}" stop-opacity="0"/>'
        f'<stop offset="1" stop-color="{flavor.shade}" stop-opacity="0.42"/>'
        f"</linearGradient>"
    )


# ── The four sources ────────────────────────────────────────────────────────

def full_bleed(flavor: Flavor) -> str:
    """iOS, web and the Android legacy icon: the ramp edge to edge.

    No rounded corners baked in — every one of those platforms masks the icon
    itself, and a pre-rounded source ends up with the corner cut twice.
    """
    S = 1024
    return f"""<svg xmlns="http://www.w3.org/2000/svg" width="{S}" height="{S}" viewBox="0 0 {S} {S}">
  <defs>{ramp_defs('fb-ramp', flavor)}{lighting('fb', flavor)}</defs>
  <rect width="{S}" height="{S}" fill="url(#fb-ramp)"/>
  <rect width="{S}" height="{S}" fill="url(#fb-top)"/>
  <rect width="{S}" height="{S}" fill="url(#fb-bottom)"/>
  {glyph(560, S / 2, S / 2)}
</svg>"""


def macos_tile(flavor: Flavor) -> str:
    """macOS and Windows: the tile drawn *inside* the canvas, with its shadow.

    Apple's grid leaves the outer ~10% empty; an edge-to-edge macOS icon looks
    oversized in a Dock full of correctly-inset ones.
    """
    S = 1024
    half = 824 / 2
    cx = S / 2
    cy = S / 2 - 8  # Apple's grid sits the body a touch above centre.
    path = squircle(cx, cy, half)
    return f"""<svg xmlns="http://www.w3.org/2000/svg" width="{S}" height="{S}" viewBox="0 0 {S} {S}">
  <defs>
    {ramp_defs('mac-ramp', flavor)}{lighting('mac', flavor)}
    <clipPath id="mac-clip"><path d="{path}"/></clipPath>
    <filter id="mac-shadow" x="-25%" y="-25%" width="150%" height="150%">
      <feDropShadow dx="0" dy="22" stdDeviation="20" flood-color="{flavor.shadow}" flood-opacity="0.42"/>
    </filter>
  </defs>
  <g filter="url(#mac-shadow)">
    <path d="{path}" fill="url(#mac-ramp)"/>
    <g clip-path="url(#mac-clip)">
      <rect width="{S}" height="{S}" fill="url(#mac-top)"/>
      <rect width="{S}" height="{S}" fill="url(#mac-bottom)"/>
    </g>
  </g>
  {glyph(452, cx, cy)}
</svg>"""


def adaptive_foreground(flavor: Flavor) -> str:
    """Android adaptive foreground: glyph only, inside the 66% safe zone.

    Android crops this to whatever shape the launcher wants, so anything
    outside the middle two thirds can and will be cut off.
    """
    S = 1024
    return f"""<svg xmlns="http://www.w3.org/2000/svg" width="{S}" height="{S}" viewBox="0 0 {S} {S}">
  {glyph(430, S / 2, S / 2, stroke=3.2)}
</svg>"""


def splash_mark(flavor: Flavor) -> str:
    """The launch mark: the tile on transparency, so it sits on either canvas.

    Smaller than the app icon on purpose — a splash mark that fills the screen
    reads as an error state.
    """
    S = 512
    half = 452 / 2
    c = S / 2
    path = squircle(c, c, half)
    return f"""<svg xmlns="http://www.w3.org/2000/svg" width="{S}" height="{S}" viewBox="0 0 {S} {S}">
  <defs>
    {ramp_defs('sp-ramp', flavor)}{lighting('sp', flavor)}
    <clipPath id="sp-clip"><path d="{path}"/></clipPath>
  </defs>
  <path d="{path}" fill="url(#sp-ramp)"/>
  <g clip-path="url(#sp-clip)">
    <rect width="{S}" height="{S}" fill="url(#sp-top)"/>
    <rect width="{S}" height="{S}" fill="url(#sp-bottom)"/>
  </g>
  {glyph(248, c, c)}
</svg>"""


def menu_bar(flavor: Flavor) -> str:
    """The macOS status item: black on transparency, for a template image.

    AppKit recolours a template image to match the menu bar, so the only thing
    that matters here is the silhouette — hence the heavier pen and no ramp,
    and hence one rendering for both flavours rather than two identical ones.
    """
    S = 44
    return f"""<svg xmlns="http://www.w3.org/2000/svg" width="{S}" height="{S}" viewBox="0 0 {S} {S}">
  {glyph(38, S / 2, S / 2 + 0.6, ink="#000000", stroke=3.6)}
</svg>"""


SOURCES = {
    "app_icon": full_bleed,
    "app_icon_macos": macos_tile,
    "app_icon_foreground": adaptive_foreground,
    "splash_mark": splash_mark,
    "menu_bar_icon": menu_bar,
}

# name -> list of (output path relative to the flavour's asset dir, pixel width)
RENDERS = [
    ("app_icon", "app_icon.png", 1024),
    ("app_icon_macos", "app_icon_macos.png", 1024),
    ("app_icon_foreground", "app_icon_foreground.png", 1024),
    ("splash_mark", "splash_mark.png", 512),
    ("splash_mark", "splash_mark_android12.png", 960),
]

# The macOS asset catalog's sizes, as `flutter_launcher_icons` writes them for
# prod. Kept here so the dev set is the same ten entries pointing at the same
# seven files, rather than a hand-copied catalog that drifts.
APPICON_PIXELS = (16, 32, 64, 128, 256, 512, 1024)
APPICON_IMAGES = (
    ("16x16", "1x", 16),
    ("16x16", "2x", 32),
    ("32x32", "1x", 32),
    ("32x32", "2x", 64),
    ("128x128", "1x", 128),
    ("128x128", "2x", 256),
    ("256x256", "1x", 256),
    ("256x256", "2x", 512),
    ("512x512", "1x", 512),
    ("512x512", "2x", 1024),
)


def render(svg: pathlib.Path, png: pathlib.Path, size: int) -> None:
    png.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        ["rsvg-convert", "-w", str(size), "-h", str(size), "-o", str(png), str(svg)],
        check=True,
    )


def src_dir(flavor: Flavor) -> pathlib.Path:
    return SRC if flavor.key == "prod" else SRC / flavor.key


def write_appiconset(flavor: Flavor) -> None:
    """Write a macOS `.appiconset` straight into the Xcode asset catalog.

    Only for the non-prod flavours: prod's set is `flutter_launcher_icons`'
    output and stays that way, so there is exactly one tool responsible for it.
    """
    icon_set = CATALOG / f"AppIcon-{flavor.key}.appiconset"
    icon_set.mkdir(parents=True, exist_ok=True)

    for size in APPICON_PIXELS:
        render(
            src_dir(flavor) / "app_icon_macos.svg",
            icon_set / f"app_icon_{size}.png",
            size,
        )

    contents = {
        "info": {"version": 1, "author": "xcode"},
        "images": [
            {
                "size": size,
                "idiom": "mac",
                "filename": f"app_icon_{px}.png",
                "scale": scale,
            }
            for size, scale, px in APPICON_IMAGES
        ],
    }
    (icon_set / "Contents.json").write_text(json.dumps(contents, indent=4) + "\n")
    print(f"  AppIcon-{flavor.key}.appiconset  {len(APPICON_PIXELS)} sizes")


def main() -> None:
    for flavor in FLAVORS.values():
        print(f"{flavor.key}:")
        sources = src_dir(flavor)
        sources.mkdir(parents=True, exist_ok=True)
        for name, builder in SOURCES.items():
            (sources / f"{name}.svg").write_text(builder(flavor))

        if flavor.key == "prod":
            # The PNGs under `assets/icon/` exist because `pubspec.yaml` names
            # them: `flutter_launcher_icons` and `flutter_native_splash` read
            # them to fan prod's icon out to every platform.
            for name, out_name, size in RENDERS:
                render(sources / f"{name}.svg", OUT / out_name, size)
                print(f"  assets/icon/{out_name}  {size}px")
        else:
            # Nothing reads a rasterised dev icon except macOS, and macOS reads
            # the asset catalog — so that is the only thing rendered. The SVGs
            # above are the whole of the rest: if a dev flavour ever ships for
            # iOS or Android, the sources are already there to render from.
            write_appiconset(flavor)

    # The status item ships straight into the macOS asset catalog: AppKit wants
    # 1x and 2x, and no other size. One image for both flavours — it is a
    # template, so AppKit paints it whatever colour the menu bar needs.
    menubar_set = CATALOG / "MenuBarIcon.imageset"
    for scale, size in ((1, 22), (2, 44)):
        suffix = "" if scale == 1 else f"@{scale}x"
        render(SRC / "menu_bar_icon.svg", menubar_set / f"MenuBarIcon{suffix}.png", size)
        print(f"  MenuBarIcon{suffix}.png  {size}px")


if __name__ == "__main__":
    main()
