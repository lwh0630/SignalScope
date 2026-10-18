"""SignalScope app icon generator.

Style: white squircle tile with a few bold rounded blocks in cyan / azure / blue-violet.
Overlaps get darker through multiply blending, like layered coloured glass.
No text, no outlines, no gradients inside the mark.

Variants (all drawn from pure geometry):

    a  Slabs   three right-leaning slabs of rising height   <- chosen for the app
    b  Peaks   two overlapping rounded peaks
    c  Sweep   two sectors from one origin (radar sweep / signal fan)
    d  Stairs  two stacked staircase silhouettes (merged signal bars)

Usage (from any directory):

    python assets/branding/generate_icons.py                 # export variant a only (default)
    python assets/branding/generate_icons.py b d             # export b and d
    python assets/branding/generate_icons.py all --preview   # export all + icon_preview.png
    python assets/branding/generate_icons.py all --preview --no-export --out build/tmp
                                                             # preview only, no per-variant files

Deps: pip install resvg-py pillow numpy

Outputs (in --out, default: next to this script), for each exported variant <v>:
    icon_<v>.svg             full icon (white tile + mark), vector
    icon_<v>_mark.svg        mark only, transparent (README / splash / adaptive foreground)
    icon_<v>.png             1024x1024 RGBA, tile with transparent corners
    icon_<v>_foreground.png  432x432 Android adaptive-icon foreground (mark inside safe zone)
and, with --preview:
    icon_preview.png         the selected variants on a dark wallpaper, 3 sizes each
"""

from __future__ import annotations

import argparse
import io
import math
from pathlib import Path

import numpy as np
import resvg_py
from PIL import Image

HERE = Path(__file__).resolve().parent

CYAN = "#16D6E6"
AZURE = "#2F7BFF"
INDIGO = "#6E7BFF"

SIZE = 1024
CORNER = 232
MARK_FIT = 540  # longest side of the visible mark inside the 1024 tile
FG_FIT = 470  # same, for the Android adaptive-icon foreground (kept inside the safe zone)


# ------------------------------------------------------------------ geometry helpers
def rounded_poly(pts: list[tuple[float, float]], r: float) -> str:
    """Closed path through polygon `pts` with every corner rounded (quadratic fillet)."""
    n = len(pts)
    segs = []
    for i in range(n):
        p, c, nx = pts[i - 1], pts[i], pts[(i + 1) % n]
        v1 = (p[0] - c[0], p[1] - c[1])
        v2 = (nx[0] - c[0], nx[1] - c[1])
        l1, l2 = math.hypot(*v1), math.hypot(*v2)
        d = min(r, 0.5 * l1, 0.5 * l2)
        a = (c[0] + v1[0] / l1 * d, c[1] + v1[1] / l1 * d)
        b = (c[0] + v2[0] / l2 * d, c[1] + v2[1] / l2 * d)
        segs.append((a, c, b))
    d_ = f"M{segs[0][0][0]:.2f},{segs[0][0][1]:.2f}"
    for i, (a, c, b) in enumerate(segs):
        if i:
            d_ += f"L{a[0]:.2f},{a[1]:.2f}"
        d_ += f"Q{c[0]:.2f},{c[1]:.2f} {b[0]:.2f},{b[1]:.2f}"
    return d_ + "Z"


def sector(cx: float, cy: float, radius: float, a1: float, a2: float, n: int = 48):
    """Polygon approximating a circular sector (angles in degrees, SVG orientation)."""
    pts = [(cx, cy)]
    for i in range(n + 1):
        a = math.radians(a1 + (a2 - a1) * i / n)
        pts.append((cx + radius * math.cos(a), cy + radius * math.sin(a)))
    return pts


# A block is (path_d, colour)
Block = tuple[str, str]


# ------------------------------------------------------------------ variants
def slabs() -> list[Block]:
    """a: three right-leaning parallelogram slabs, rising heights, overlapping."""
    base, w, pitch, lean = 800, 200, 135, 80
    heights = (250, 400, 550)
    colors = (CYAN, AZURE, INDIGO)
    out = []
    for i, (h, c) in enumerate(zip(heights, colors)):
        x = 200 + i * pitch
        pts = [(x, base), (x + w, base), (x + w + lean, base - h), (x + lean, base - h)]
        out.append((rounded_poly(pts, 46), c))
    return out


def peaks() -> list[Block]:
    """b: a wide cyan peak and a tall azure peak, interleaved."""
    wide = [(170, 790), (470, 300), (770, 790)]
    tall = [(330, 790), (640, 160), (950, 790)]
    return [(rounded_poly(wide, 64), CYAN), (rounded_poly(tall, 64), AZURE)]


def sweep() -> list[Block]:
    """c: two sectors (radar sweep / signal fan) from the same lower-left origin."""
    big = sector(250, 790, 560, -88, -2)
    small = sector(250, 790, 340, -74, 12)
    return [(rounded_poly(big, 70), CYAN), (rounded_poly(small, 56), AZURE)]


def stairs() -> list[Block]:
    """d: two staircase silhouettes (merged signal bars) stacked with a diagonal offset."""

    def stair(ox, oy, s=1.0):
        pts = [(0, 0), (480, 0), (480, -440), (320, -440), (320, -300), (160, -300), (160, -160), (0, -160)]
        return [(ox + x * s, oy + y * s) for x, y in pts]

    return [
        (rounded_poly(stair(250, 800), 40), CYAN),
        (rounded_poly(stair(330, 730, 0.88), 36), AZURE),
    ]


VARIANTS = {"a": slabs, "b": peaks, "c": sweep, "d": stairs}
DEFAULT_VARIANTS = ["a"]


# ------------------------------------------------------------------ SVG / raster
def mark_group(blocks: list[Block], transform: str = "") -> str:
    body = "\n".join(
        f'<path d="{d}" fill="{c}" style="mix-blend-mode:multiply"/>' for d, c in blocks
    )
    return f'<g style="isolation:isolate" transform="{transform}">\n{body}\n</g>'


def svg(inner: str, tile: bool) -> str:
    defs = (
        '<defs><linearGradient id="t" x1="0" y1="0" x2="0" y2="1">'
        '<stop offset="0" stop-color="#FFFFFF"/><stop offset="1" stop-color="#EEF2F7"/>'
        "</linearGradient></defs>"
    )
    tile_el = f'<rect width="{SIZE}" height="{SIZE}" rx="{CORNER}" fill="url(#t)"/>\n' if tile else ""
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{SIZE}" height="{SIZE}" '
        f'viewBox="0 0 {SIZE} {SIZE}">\n{defs}\n{tile_el}{inner}\n</svg>\n'
    )


def render(svg_text: str, px: int) -> Image.Image:
    data = resvg_py.svg_to_bytes(svg_string=svg_text, width=px, height=px)
    return Image.open(io.BytesIO(bytes(data))).convert("RGBA")


def fit_transform(blocks: list[Block], fit: float) -> str:
    """Scale + translate so the visible mark is optically centred with long side == fit."""
    scale, tx, ty = 1.0, 0.0, 0.0
    for _ in range(3):
        img = render(svg(mark_group(blocks, f"translate({tx:.3f} {ty:.3f}) scale({scale:.5f})"), False), SIZE)
        a = np.asarray(img)[:, :, 3]
        ys, xs = np.where(a > 8)
        x0, x1, y0, y1 = xs.min(), xs.max() + 1, ys.min(), ys.max() + 1
        k = fit / max(x1 - x0, y1 - y0)
        cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
        tx = SIZE / 2 + (tx - cx) * k
        ty = SIZE / 2 + (ty - cy) * k
        scale *= k
    return f"translate({tx:.3f} {ty:.3f}) scale({scale:.5f})"


def preview(icons: dict[str, Image.Image], out: Path) -> None:
    """Selected variants on a dark blue-grey wallpaper, each at 360 px plus 120/72/48 px."""
    n = len(icons)
    W, H = 500 * n, 760
    yy, xx = np.mgrid[0:H, 0:W]
    t = (xx / W * 0.6 + yy / H * 0.4)[..., None]
    c0, c1 = np.array([38, 50, 66]), np.array([84, 96, 112])
    canvas = Image.fromarray((c0 + (c1 - c0) * t).astype(np.uint8), "RGB").convert("RGBA")
    for i, key in enumerate(icons):
        cx = 250 + i * 500
        canvas.alpha_composite(icons[key].resize((360, 360), Image.LANCZOS), (cx - 180, 90))
        x = cx - 150
        for px in (120, 72, 48):
            canvas.alpha_composite(icons[key].resize((px, px), Image.LANCZOS), (x, 560 + (120 - px) // 2))
            x += px + 40
    canvas.convert("RGB").save(out / "icon_preview.png", optimize=True)


# ------------------------------------------------------------------ main
def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("variants", nargs="*", help="a b c d, or 'all' (default: a)")
    ap.add_argument("--preview", action="store_true", help="also write icon_preview.png")
    ap.add_argument("--no-export", action="store_true", help="skip the per-variant svg/png files")
    ap.add_argument("--out", type=Path, default=HERE, help="output directory (default: script directory)")
    args = ap.parse_args()

    keys = list(VARIANTS) if args.variants == ["all"] else (args.variants or DEFAULT_VARIANTS)
    unknown = [k for k in keys if k not in VARIANTS]
    if unknown:
        ap.error(f"unknown variant(s): {', '.join(unknown)} (choose from {', '.join(VARIANTS)})")
    out: Path = args.out
    out.mkdir(parents=True, exist_ok=True)

    icons: dict[str, Image.Image] = {}
    for key in keys:
        blocks = VARIANTS[key]()
        mark = mark_group(blocks, fit_transform(blocks, MARK_FIT))
        icons[key] = render(svg(mark, True), 1024)
        if args.no_export:
            continue
        (out / f"icon_{key}.svg").write_text(svg(mark, True), encoding="utf-8")
        (out / f"icon_{key}_mark.svg").write_text(svg(mark, False), encoding="utf-8")
        icons[key].save(out / f"icon_{key}.png", optimize=True)
        # adaptive-icon foreground: mark scaled into the safe zone, transparent
        fg_mark = mark_group(blocks, fit_transform(blocks, FG_FIT))
        render(svg(fg_mark, False), 432).save(out / f"icon_{key}_foreground.png", optimize=True)

    if args.preview:
        preview(icons, out)
    print("done ->", out, "| variants:", ", ".join(keys))


if __name__ == "__main__":
    main()
