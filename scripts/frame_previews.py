#!/usr/bin/env python3
"""Turn raw kitty screenshots (previews/raw/kitty-<slug>.png, made by
scripts/capture_previews.sh) into framed previews plus a comparison image.

    python3 scripts/frame_previews.py

Writes previews/<slug>.png and previews/comparison.png. Needs Pillow.
"""
from __future__ import annotations

import tomllib
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
SLUGS = ["dracula", "dracula-soft", "alucard"]
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
FONT_REG = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"


def hexrgb(h: str) -> tuple[int, int, int]:
    return tuple(int(h[i:i + 2], 16) for i in (1, 3, 5))


def mix(a, b, t):
    return tuple(round(x + (y - x) * t) for x, y in zip(a, b))


def crop_to_terminal(im: Image.Image, bg) -> Image.Image:
    """Drop window-manager borders: keep the box whose edges are terminal bg."""
    w, h = im.size
    px = im.load()
    right = next(x for x in range(w - 1, 0, -1) if px[x, h // 2] == bg)
    bottom = next(y for y in range(h - 1, 0, -1) if px[w // 2, y] == bg)
    return im.crop((0, 0, right + 1, bottom + 1))


def frame(im: Image.Image, title: str, bg, fg) -> Image.Image:
    bar = 44
    pad = 0
    out = Image.new("RGB", (im.width + 2 * pad, im.height + bar + pad), mix(bg, (0, 0, 0), 0.25))
    d = ImageDraw.Draw(out)
    for i, c in enumerate(["#FF5F57", "#FEBC2E", "#28C840"]):
        x = 20 + i * 24
        d.ellipse((x, bar // 2 - 7, x + 14, bar // 2 + 7), fill=c)
    f = ImageFont.truetype(FONT, 17)
    tw = d.textlength(title, font=f)
    d.text(((out.width - tw) / 2, bar // 2), title, font=f, fill=mix(fg, bg, 0.3), anchor="lm")
    out.paste(im, (pad, bar))
    return out


def main() -> None:
    framed = {}
    for slug in SLUGS:
        p = tomllib.loads((ROOT / "palettes" / f"{slug}.toml").read_text())
        bg, fg = hexrgb(p["colors"]["background"]), hexrgb(p["colors"]["foreground"])
        raw = Image.open(ROOT / "previews" / "raw" / f"kitty-{slug}.png").convert("RGB")
        im = crop_to_terminal(raw, bg)
        out = frame(im, f"grok  ·  {p['meta']['name']}  ·  kitty", bg, fg)
        out.save(ROOT / "previews" / f"{slug}.png", optimize=True)
        framed[slug] = (out, p)
        print(f"previews/{slug}.png {out.size}")

    scale = 0.62
    gap, label_h, margin = 24, 46, 28
    tiles = [(o.resize((round(o.width * scale), round(o.height * scale)), Image.LANCZOS), p) for o, p in framed.values()]
    W = sum(t.width for t, _ in tiles) + gap * (len(tiles) - 1) + 2 * margin
    H = max(t.height for t, _ in tiles) + label_h + 2 * margin
    comp = Image.new("RGB", (W, H), (24, 25, 33))
    d = ImageDraw.Draw(comp)
    fb, fr = ImageFont.truetype(FONT, 22), ImageFont.truetype(FONT_REG, 18)
    x = margin
    for t, p in tiles:
        tag = "official" if p["meta"]["official"] else "derived, unofficial"
        d.text((x, margin + 14), p["meta"]["name"], font=fb, fill=(248, 248, 242), anchor="lm")
        d.text((x + d.textlength(p["meta"]["name"], font=fb) + 12, margin + 15), f"({tag})", font=fr, fill=(160, 164, 190), anchor="lm")
        comp.paste(t, (x, margin + label_h))
        x += t.width + gap
    comp.save(ROOT / "previews" / "comparison.png", optimize=True)
    print(f"previews/comparison.png {comp.size}")


if __name__ == "__main__":
    main()
