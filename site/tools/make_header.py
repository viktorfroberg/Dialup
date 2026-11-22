#!/usr/bin/env python3
"""Draws the website's header: banner, free-standing globe and the "Dialup" wordmark.

    python3 site/tools/make_header.py

Uses the app's globe (Assets/AppIcon/globe.png, from make_globe.py) and macOS's Trebuchet MS.
Writes site/img/header-banner.png, header-globe.png and wordmark.png.
"""
import math
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "site" / "img"
FONT = "/System/Library/Fonts/Supplemental/Trebuchet MS Bold Italic.ttf"
W, H = 760, 92


def banner():
    """Navy gradient with a faint wireframe globe on the right, like a product banner."""
    ss = 3
    img = Image.new("RGB", (W * ss, H * ss))
    top, bottom = (52, 92, 168), (16, 40, 96)
    px = img.load()
    for y in range(H * ss):
        t = y / (H * ss - 1)
        c = tuple(round(a + (b - a) * t) for a, b in zip(top, bottom))
        for x in range(W * ss):
            px[x, y] = c
    lines = Image.new("L", img.size, 0)
    d = ImageDraw.Draw(lines)
    cx, cy, r = 640 * ss, 64 * ss, 150 * ss
    w = 2 * ss // 2
    d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=255, width=w)
    for k in range(1, 6):  # meridians
        rx = r * math.cos(math.radians(k * 15))
        d.ellipse([cx - rx, cy - r, cx + rx, cy + r], outline=255, width=w)
    for lat in (-60, -30, 0, 30, 60):  # parallels
        y = cy - r * math.sin(math.radians(lat))
        half = r * math.cos(math.radians(lat))
        d.line([cx - half, y, cx + half, y], fill=255, width=w)
    white = Image.new("RGB", img.size, (255, 255, 255))
    img = Image.composite(white, img, lines.point(lambda v: v * 0.13))
    # A soft highlight along the top edge.
    shine = Image.new("L", img.size, 0)
    ImageDraw.Draw(shine).rectangle([0, 0, img.size[0], 2 * ss], fill=60)
    img = Image.composite(white, img, shine.filter(ImageFilter.GaussianBlur(2 * ss)))
    img.resize((W, H), Image.LANCZOS).save(OUT / "header-banner.png", optimize=True)


def header_globe():
    """The app's globe without its tile, with a soft shadow."""
    size, g = 76, 64
    globe = Image.open(ROOT / "Assets" / "AppIcon" / "globe.png").convert("RGBA").resize((g, g), Image.LANCZOS)
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    shadow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).ellipse([8, 12, 8 + g - 2, 12 + g - 2], fill=(0, 10, 40, 110))
    out.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(3)))
    out.alpha_composite(globe, (4, 4))
    out.save(OUT / "header-globe.png", optimize=True)


def wordmark():
    """'Dialup' in bold italic with a white-to-sky gradient, a dark outline and a drop shadow."""
    ss = 4
    f = ImageFont.truetype(FONT, 46 * ss)
    text = "Dialup"
    left, top, right, bottom = f.getbbox(text, stroke_width=3 * ss)
    w, h = right - left + 8 * ss, bottom - top + 8 * ss
    mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(mask).text((-left + 2 * ss, -top + 2 * ss), text, font=f, fill=255)
    outline = Image.new("L", (w, h), 0)
    ImageDraw.Draw(outline).text((-left + 2 * ss, -top + 2 * ss), text, font=f, fill=255,
                                 stroke_width=3 * ss, stroke_fill=255)

    grad = Image.new("RGBA", (w, h))
    gp = grad.load()
    for y in range(h):
        t = y / (h - 1)
        # white on top, a glassy step at the middle, sky blue at the bottom
        if t < 0.5:
            c = (255, 255, 255)
        else:
            u = (t - 0.5) / 0.5
            c = tuple(round(a + (b - a) * u) for a, b in zip((206, 226, 255), (140, 188, 250)))
        for x in range(w):
            gp[x, y] = c + (255,)

    out = Image.new("RGBA", (w + 4 * ss, h + 4 * ss), (0, 0, 0, 0))
    shadow = Image.new("RGBA", out.size, (0, 0, 0, 0))
    shadow.paste((5, 15, 45, 150), (3 * ss, 3 * ss), outline)
    out.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(1.5 * ss)))
    dark = Image.new("RGBA", (w, h), (10, 28, 80, 255))
    out.paste(dark, (0, 0), outline)
    out.paste(grad, (0, 0), mask)
    out = out.resize((out.width // ss, out.height // ss), Image.LANCZOS)
    out.save(OUT / "wordmark.png", optimize=True)
    print("wordmark", out.size)


if __name__ == "__main__":
    banner()
    header_globe()
    wordmark()
