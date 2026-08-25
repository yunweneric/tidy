#!/usr/bin/env python3
"""Render the landing page's Open Graph card.

A Flutter page draws to a canvas, so a link unfurl on Slack, X or LinkedIn
never sees any of it. This 1200x630 PNG and the meta tags in `web/index.html`
are the entire preview, and they are the first thing most people will see of
the app.

Committed rather than built in CI: it changes when the wording or the mark
changes, which is roughly never, and generating it on every deploy would put
librsvg in the Pages workflow for no benefit.

    python3 scripts/generate_og_image.py

Requires `rsvg-convert` (brew install librsvg), the same dependency
`generate_icons.py` already has.
"""

import pathlib
import subprocess

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "web" / "og-image.png"

WIDTH, HEIGHT = 1200, 630

# AppColorTokens.dark(): the canvas, its gradient, and the brand accent. The
# card is the app's own dark appearance, so the preview and the page a click
# later are recognisably the same thing.
CANVAS = "#15112E"
CANVAS_LIFT = "#1B1440"
ACCENT = "#A593FF"
TEXT = "#FFFFFF"
MUTED = "#C4C0D8"

# The tile ramp, straight off `BrandMark.ramp`.
RAMP = [(0.00, "#D8CCFF"), (0.34, "#9B7CF6"), (1.00, "#5B21B6")]

FONT = "Inter, SF Pro Display, -apple-system, Helvetica, sans-serif"


def mark(x: float, y: float, size: float) -> str:
    """The app icon: a Mac screen with a four-point spark, on the violet ramp.

    Same 48-unit grid as `assets/icon/src/app_icon.svg` and `BrandMark`, so
    the card, the Dock tile and the sidebar are one drawing at three sizes.
    """
    tile = size
    glyph = size * 0.55
    gx, gy = x + (tile - glyph) / 2, y + (tile - glyph) / 2
    s = glyph / 48.0
    return f"""
  <rect x="{x}" y="{y}" width="{tile}" height="{tile}" rx="{tile * 0.225:.2f}" fill="url(#tile)"/>
  <g transform="translate({gx:.2f} {gy:.2f}) scale({s:.6f})">
    <rect x="7" y="10" width="34" height="23" rx="5" stroke="#fff" stroke-width="3" fill="none"/>
    <path d="M20.5 33v4h7v-4M16 39h16" stroke="#fff" stroke-width="3" stroke-linecap="round" fill="none"/>
    <path d="M24 14.5c1.3 4.8 3.2 6.7 8 8-4.8 1.3-6.7 3.2-8 8-1.3-4.8-3.2-6.7-8-8 4.8-1.3 6.7-3.2 8-8Z" fill="#fff"/>
  </g>"""


def chip(x: float, y: float, label: str) -> str:
    """One module pill along the foot of the card."""
    width = 26 + len(label) * 12.2
    return f"""
  <rect x="{x:.1f}" y="{y}" width="{width:.1f}" height="44" rx="22"
        fill="#FFFFFF" fill-opacity="0.08" stroke="#FFFFFF" stroke-opacity="0.16"/>
  <text x="{x + width / 2:.1f}" y="{y + 29}" text-anchor="middle"
        font-family="{FONT}" font-size="19" font-weight="500" fill="{MUTED}">{label}</text>""", width


def build() -> str:
    stops = "".join(f'<stop offset="{o}" stop-color="{c}"/>' for o, c in RAMP)

    chips = []
    cursor = 80.0
    for label in ("Cleanup", "Uninstaller", "Clipboard", "Performance",
                  "Recycle Bin", "Network"):
        svg, width = chip(cursor, 500, label)
        chips.append(svg)
        cursor += width + 14

    return f"""<svg xmlns="http://www.w3.org/2000/svg" width="{WIDTH}" height="{HEIGHT}"
     viewBox="0 0 {WIDTH} {HEIGHT}">
  <defs>
    <linearGradient id="tile" x1="0" y1="0" x2="0" y2="1">{stops}</linearGradient>
    <linearGradient id="ground" x1="0" y1="0" x2="0.4" y2="1">
      <stop offset="0" stop-color="{CANVAS_LIFT}"/>
      <stop offset="1" stop-color="{CANVAS}"/>
    </linearGradient>
    <radialGradient id="pool" cx="0.28" cy="0.06" r="0.75">
      <stop offset="0" stop-color="{ACCENT}" stop-opacity="0.28"/>
      <stop offset="1" stop-color="{ACCENT}" stop-opacity="0"/>
    </radialGradient>
  </defs>

  <rect width="{WIDTH}" height="{HEIGHT}" fill="url(#ground)"/>
  <rect width="{WIDTH}" height="{HEIGHT}" fill="url(#pool)"/>
{mark(80, 74, 96)}
  <text x="196" y="126" font-family="{FONT}" font-size="38" font-weight="700"
        letter-spacing="-0.6" fill="{TEXT}">Tidy</text>
  <text x="196" y="158" font-family="{FONT}" font-size="21" font-weight="500"
        fill="{MUTED}">for macOS</text>

  <text x="80" y="286" font-family="{FONT}" font-size="66" font-weight="700"
        letter-spacing="-2.2" fill="{TEXT}">Clean, tune and reclaim</text>
  <text x="80" y="358" font-family="{FONT}" font-size="66" font-weight="700"
        letter-spacing="-2.2" fill="{TEXT}">your Mac</text>

  <text x="80" y="418" font-family="{FONT}" font-size="25" font-weight="400"
        fill="{MUTED}">One app for the small jobs macOS makes awkward.</text>
  <text x="80" y="454" font-family="{FONT}" font-size="25" font-weight="400"
        fill="{MUTED}">Free, open source, and nothing leaves your Mac.</text>
{"".join(chips)}
</svg>"""


def main() -> None:
    OUT.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        ["rsvg-convert", "-w", str(WIDTH), "-h", str(HEIGHT), "-o", str(OUT)],
        input=build().encode(),
        check=True,
    )
    print(f"wrote {OUT.relative_to(ROOT)} ({OUT.stat().st_size // 1024} KB)")


if __name__ == "__main__":
    main()
