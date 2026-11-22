#!/usr/bin/env python3
"""Generate the small pixel graphics for the Dialup homepage (site/img/).

Everything here is drawn from scratch with PIL: 88x31 buttons, the NEW! badge,
bullets, the gradient tiles.
Text is rendered without antialiasing (fontmode "1"), the way 2003 buttons looked.

Also copies/resizes the screenshots and the favicon from the repo.

    python3 site/tools/make_buttons.py
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

SITE = Path(__file__).resolve().parent.parent
REPO = SITE.parent
OUT = SITE / "img"
OUT.mkdir(exist_ok=True)

FONT_DIR = Path("/System/Library/Fonts/Supplemental")


def font(name, size):
    try:
        return ImageFont.truetype(str(FONT_DIR / name), size)
    except OSError:
        return ImageFont.load_default_imagefont()


VERDANA = lambda s: font("Verdana.ttf", s)
VERDANA_B = lambda s: font("Verdana Bold.ttf", s)
TAHOMA_B = lambda s: font("Tahoma Bold.ttf", s)
GEORGIA_B = lambda s: font("Georgia Bold.ttf", s)


def canvas(w, h, bg):
    im = Image.new("RGB", (w, h), bg)
    d = ImageDraw.Draw(im)
    d.fontmode = "1"  # no antialiasing: crisp pixel text
    return im, d


def text_c(d, box, s, f, fill):
    """Draw s centred in box (x0, y0, x1, y1)."""
    l, t, r, b = d.textbbox((0, 0), s, font=f)
    x = box[0] + (box[2] - box[0] - (r - l)) // 2 - l
    y = box[1] + (box[3] - box[1] - (b - t)) // 2 - t
    d.text((x, y), s, font=f, fill=fill)


def bevel(d, x0, y0, x1, y1, light, dark):
    d.line([(x0, y1), (x0, y0), (x1, y0)], fill=light)
    d.line([(x0, y1), (x1, y1), (x1, y0)], fill=dark)


def globe(d, cx, cy, r, sea=(58, 110, 190), land=(92, 168, 84), line=(20, 50, 110)):
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=sea, outline=line)
    # a couple of blocky continents
    d.rectangle([cx - r + 3, cy - 3, cx - 1, cy + 2], fill=land)
    d.rectangle([cx - r + 5, cy - 6, cx - 2, cy - 3], fill=land)
    d.rectangle([cx + 2, cy + 1, cx + r - 4, cy + 5], fill=land)
    d.rectangle([cx + 3, cy - 6, cx + 5, cy - 2], fill=land)
    d.arc([cx - r // 2, cy - r, cx + r // 2, cy + r], 0, 360, fill=line)
    d.line([(cx - r, cy), (cx + r, cy)], fill=line)
    d.point([(cx - 3, cy - r + 3), (cx - 2, cy - r + 3)], fill=(230, 240, 255))


def save_gif(frames, name, durations):
    pal = [f.convert("P", palette=Image.ADAPTIVE, colors=64, dither=Image.NONE) for f in frames]
    if len(pal) == 1:
        pal[0].save(OUT / name)
    else:
        pal[0].save(OUT / name, save_all=True, append_images=pal[1:], duration=durations,
                    loop=0, optimize=True, disposal=1)


# ---------------------------------------------------------------- 88x31 buttons
W, H = 88, 31
BLACK = (0, 0, 0)


def frame_border(d, outer=(0, 0, 0), light=(255, 255, 255), dark=(128, 128, 128)):
    d.rectangle([0, 0, W - 1, H - 1], outline=outer)
    bevel(d, 1, 1, W - 2, H - 2, light, dark)


def btn_dialup_now():
    frames = []
    for i, word_col in enumerate([(255, 214, 64), (255, 255, 255)]):
        im, d = canvas(W, H, (22, 52, 110))
        d.rectangle([2, 2, 29, H - 3], fill=(225, 234, 248))
        globe(d, 15, 15, 10)
        d.line([(30, 2), (30, H - 3)], fill=BLACK)
        text_c(d, (31, 3, W - 3, 15), "Dialup", VERDANA_B(11), (255, 255, 255))
        text_c(d, (31, 15, W - 3, 28), "NOW!", TAHOMA_B(11), word_col)
        frame_border(d, light=(120, 150, 210), dark=(8, 20, 50))
        frames.append(im)
    save_gif(frames, "btn-dialup-now.gif", [700, 500])


def btn_made_on_mac():
    im, d = canvas(W, H, (214, 214, 214))
    # brushed-metal-ish horizontal streaks, deterministic
    for y in range(2, H - 2):
        v = 206 + (y * 37 % 11) - (y * 13 % 7)
        d.line([(2, y), (W - 3, y)], fill=(v, v, v))
    # a tiny generic compact computer
    d.rectangle([6, 5, 22, 25], fill=(236, 232, 220), outline=(70, 70, 70))
    d.rectangle([9, 8, 19, 16], fill=(70, 110, 160), outline=(40, 40, 40))
    d.line([(11, 10), (16, 10)], fill=(220, 230, 245))  # a few lines of "text" on screen
    d.line([(11, 12), (14, 12)], fill=(220, 230, 245))
    d.rectangle([11, 14, 12, 14], fill=(255, 255, 255))
    d.line([(9, 20), (14, 20)], fill=(90, 90, 90))
    d.rectangle([7, 25, 21, 26], fill=(150, 150, 150))
    text_c(d, (25, 3, W - 3, 15), "Made on a", VERDANA(9), (40, 40, 40))
    text_c(d, (25, 14, W - 3, 28), "Mac", GEORGIA_B(13), (20, 20, 20))
    frame_border(d, outer=(60, 60, 60), dark=(150, 150, 150))
    save_gif([im], "btn-made-on-mac.gif", [0])


def btn_valid_html():
    im, d = canvas(W, H, (255, 255, 255))
    d.rectangle([2, 2, 37, H - 3], fill=(36, 84, 160))
    text_c(d, (2, 2, 37, H - 3), "HTML", TAHOMA_B(11), (255, 255, 255))
    d.line([(38, 2), (38, H - 3)], fill=BLACK)
    text_c(d, (39, 3, W - 3, 15), "VALID", VERDANA_B(10), (200, 120, 0))
    text_c(d, (39, 15, W - 3, 28), "markup", VERDANA(9), (60, 60, 60))
    frame_border(d, dark=(110, 110, 110), light=(230, 230, 230))
    save_gif([im], "btn-valid-html.gif", [0])


def btn_mit():
    im, d = canvas(W, H, (250, 246, 232))
    d.rectangle([2, 2, 31, H - 3], fill=(150, 30, 40))
    text_c(d, (2, 2, 31, H - 3), "MIT", VERDANA_B(10), (255, 255, 255))
    d.line([(32, 2), (32, H - 3)], fill=BLACK)
    text_c(d, (33, 3, W - 3, 15), "open", VERDANA(9), (60, 50, 40))
    text_c(d, (33, 15, W - 3, 28), "source", VERDANA_B(9), (60, 50, 40))
    frame_border(d, dark=(120, 110, 90))
    save_gif([im], "btn-mit.gif", [0])


def btn_no_cookies():
    im, d = canvas(W, H, (255, 250, 236))
    # a cookie with a red "no" circle
    d.ellipse([5, 4, 26, 25], fill=(200, 150, 80), outline=(120, 80, 30))
    for p in [(10, 9), (17, 8), (13, 15), (20, 17), (9, 19), (16, 21)]:
        d.rectangle([p[0], p[1], p[0] + 1, p[1] + 1], fill=(80, 45, 20))
    d.ellipse([3, 2, 28, 27], outline=(200, 20, 20), width=2)
    d.line([(7, 6), (24, 23)], fill=(200, 20, 20), width=2)
    text_c(d, (30, 3, W - 3, 15), "NO", TAHOMA_B(11), (200, 20, 20))
    text_c(d, (30, 15, W - 3, 28), "cookies", VERDANA(9), (60, 50, 40))
    frame_border(d, dark=(140, 120, 90))
    save_gif([im], "btn-no-cookies.gif", [0])


def btn_get_dialup():
    msg = "free download  *  Mac OS X  *  MIT  *"
    f = VERDANA(9)
    # render the scrolling text once, measured as actually drawn (1-bit text is wider)
    probe, pd = canvas(600, 14, (0, 0, 0))
    pd.text((0, 0), msg, font=f, fill=(255, 255, 255))
    strip_w = probe.getbbox()[2] + 14
    strip, sd = canvas(strip_w, 12, (22, 52, 110))
    sd.text((0, -1), msg, font=f, fill=(255, 214, 64))
    frames = []
    step = 6
    for off in range(0, strip_w - strip_w % step, step):
        im, d = canvas(W, H, (238, 238, 230))
        d.rectangle([2, 2, W - 3, 16], fill=(255, 255, 255))
        text_c(d, (2, 2, W - 3, 16), "Get Dialup!", VERDANA_B(10), (22, 52, 110))
        d.rectangle([2, 17, W - 3, H - 3], fill=(22, 52, 110))
        for k in (0, 1, 2):
            im.paste(strip, (4 - off + k * strip_w, 17))
        d.rectangle([W - 2, 0, W - 1, H - 1], fill=(0, 0, 0))  # clear overflow past the edge
        d.line([(2, 16), (W - 3, 16)], fill=BLACK)
        frame_border(d, dark=(90, 90, 90))
        frames.append(im)
    save_gif(frames, "btn-get-dialup.gif", [120] * len(frames))


def btn_800x600():
    im, d = canvas(W, H, (0, 0, 0))
    d.rectangle([2, 2, W - 3, H - 3], fill=(0, 64, 64))
    text_c(d, (2, 3, W - 3, 15), "best at", VERDANA(9), (160, 220, 210))
    text_c(d, (2, 14, W - 3, 28), "800x600", TAHOMA_B(12), (255, 255, 255))
    frame_border(d, light=(80, 160, 160), dark=(0, 20, 20))
    save_gif([im], "btn-800x600.gif", [0])


# ---------------------------------------------------------------- small graphics
def new_badge():
    frames = []
    for bg, fg in [((204, 0, 0), (255, 255, 255)), ((255, 204, 0), (204, 0, 0))]:
        im, d = canvas(31, 13, bg)
        d.rectangle([0, 0, 30, 12], outline=(120, 0, 0))
        text_c(d, (0, 0, 31, 13), "NEW!", VERDANA_B(9), fg)
        frames.append(im)
    save_gif(frames, "new.gif", [500, 500])


def bullets():
    # bevelled blue square bullet
    im, d = canvas(9, 9, (255, 255, 255))
    d.rectangle([1, 1, 7, 7], fill=(58, 98, 170))
    bevel(d, 1, 1, 7, 7, (150, 180, 230), (20, 40, 90))
    im.convert("P", palette=Image.ADAPTIVE, colors=16).save(OUT / "bullet.gif")
    # small right arrow for nav links
    im = Image.new("P", (7, 9), 0)
    im.putpalette([255, 0, 255, 22, 52, 110] + [0] * 762)
    d = ImageDraw.Draw(im)
    d.polygon([(1, 0), (5, 4), (1, 8)], fill=1)
    im.save(OUT / "arrow.gif", transparency=0)


def gradient_tiles():
    # 1px-wide vertical gradients, tiled with repeat-x: header, box title bars, nav bar
    def vgrad(h, top, bottom, name):
        im = Image.new("RGB", (1, h))
        for y in range(h):
            t = y / max(1, h - 1)
            im.putpixel((0, y), tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)))
        im.convert("P", palette=Image.ADAPTIVE, colors=64).save(OUT / name)
    vgrad(92, (44, 78, 140), (24, 46, 94), "header-bg.gif")
    vgrad(19, (98, 132, 190), (52, 84, 144), "titlebar-bg.gif")
    vgrad(24, (250, 250, 247), (222, 220, 210), "navbar-bg.gif")




# ---------------------------------------------------------------- photos & icons
SHOTS = {
    "hero-luna-tabs": "hero-luna-tabs.png",
    "skin-luna": "skin-luna.png",
    "skin-aqua": "skin-aqua.png",
    "skin-classic": "skin-classic.png",
    "dialup-mode": "dialup-mode.png",
    "dialup-mode-hard": "dialup-mode-hard.png",
    "options-dialup": "options-dialup.png",
    "setup-wizard": "setup-wizard.png",
    "start-page-luna": "start-page-luna.png",
    "start-page-aqua": "start-page-aqua.png",
}


def screenshots():
    src_dir = REPO / "docs" / "screenshots"
    for name, fn in SHOTS.items():
        src = Image.open(src_dir / fn).convert("RGB")
        full = src.resize((1000, round(src.height * 1000 / src.width)), Image.LANCZOS)
        full.save(OUT / f"{name}.jpg", quality=84, optimize=True, progressive=False)
        # thumbnails share one size (160x113): crop taller shots from the top
        crop = src.crop((0, 0, src.width, min(src.height, round(src.width * 1134 / 1600))))
        thumb = crop.resize((160, 113), Image.LANCZOS)
        if name != "hero-luna-tabs":  # the hero has its own 560px copy instead
            thumb.save(OUT / f"{name}-t.jpg", quality=86, optimize=True)
    hero = Image.open(src_dir / "hero-luna-tabs.png").convert("RGB")
    hero.resize((560, round(hero.height * 560 / hero.width)), Image.LANCZOS).save(
        OUT / "hero-560.jpg", quality=86, optimize=True)
    icons = Image.open(src_dir / "app-icons.png").convert("RGBA")
    bg = Image.new("RGBA", icons.size, (255, 255, 255, 255))
    bg.alpha_composite(icons)
    bg.convert("RGB").resize((410, 150), Image.LANCZOS).save(OUT / "app-icons.jpg", quality=88)
    # Open Graph image: 1200x630 crop of the hero shot
    og = hero.resize((1200, round(hero.height * 1200 / hero.width)), Image.LANCZOS).crop((0, 0, 1200, 630))
    og.save(OUT / "og.jpg", quality=84, optimize=True)


def icons():
    src = Image.open(REPO / "Resources" / "SkinIcons" / "luna.png").convert("RGBA")
    src.resize((64, 64), Image.LANCZOS).save(OUT / "icon-64.png", optimize=True)
    src.resize((180, 180), Image.LANCZOS).save(SITE / "apple-touch-icon.png", optimize=True)
    src.save(SITE / "favicon.ico", sizes=[(16, 16), (32, 32), (48, 48)])


if __name__ == "__main__":
    btn_dialup_now(); btn_made_on_mac(); btn_valid_html(); btn_mit()
    btn_no_cookies(); btn_get_dialup(); btn_800x600()
    new_badge(); bullets(); gradient_tiles()
    screenshots(); icons()
    print("wrote", len(list(OUT.iterdir())), "files to", OUT)
