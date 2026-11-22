#!/usr/bin/env python3
"""Draws Dialup's globe and app icons from real map data, no clip art.

The continents come from Natural Earth's 1:110m land polygons (public domain, data/), projected
orthographically onto a sphere over the Atlantic, then shaded in the glossy style of early-2000s
icons: light from the top left, a gloss highlight, faint meridians and a dark rim.

    python3 Assets/AppIcon/tools/make_globe.py

Writes Host/Assets.xcassets/AppIcon.appiconset/*.png (Luna), Resources/SkinIcons/<skin>.png and
Assets/AppIcon/globe.png. Needs numpy and Pillow.
"""
import json
import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parents[1]

CENTER_LON, CENTER_LAT = -25.0, 18.0          # Atlantic: the Americas, Europe and Africa
LIGHT = np.array([-0.45, 0.6, 0.66])          # from the top left, towards the viewer
LIGHT = LIGHT / np.linalg.norm(LIGHT)

OCEAN_DEEP = np.array([22, 74, 168])
OCEAN_LIGHT = np.array([96, 168, 238])
LAND_DARK = np.array([150, 196, 120])
LAND_LIGHT = np.array([236, 248, 214])
RIM = np.array([18, 44, 110])

SKINS = {
    # tile gradient top → bottom
    'luna': ((136, 204, 254), (67, 143, 226)),
    'aqua': ((246, 247, 249), (196, 200, 208)),
    'classic': ((52, 84, 168), (10, 30, 104)),
}


def land_map(width=4096):
    """Equirectangular land mask (True on land)."""
    height = width // 2
    img = Image.new('L', (width, height), 0)
    draw = ImageDraw.Draw(img)
    data = json.loads((HERE / 'data' / 'ne_110m_land.geojson').read_text())

    def xy(lon, lat):
        return ((lon + 180) / 360 * width, (90 - lat) / 180 * height)

    for feature in data['features']:
        geom = feature['geometry']
        polys = geom['coordinates'] if geom['type'] == 'MultiPolygon' else [geom['coordinates']]
        for poly in polys:
            outer, *holes = poly
            draw.polygon([xy(*p) for p in outer], fill=255)
            for hole in holes:
                draw.polygon([xy(*p) for p in hole], fill=0)
    return np.asarray(img) > 127


def globe(size, land):
    """RGBA globe, `size` px, supersampled 3x."""
    ss = size * 3
    r = ss / 2 - ss * 0.02
    c = ss / 2
    ys, xs = np.mgrid[0:ss, 0:ss].astype(np.float64)
    nx = (xs + 0.5 - c) / r
    ny = (c - (ys + 0.5)) / r
    d2 = nx * nx + ny * ny
    inside = d2 <= 1.0
    nz = np.sqrt(np.clip(1 - d2, 0, 1))

    # Inverse orthographic projection → lon/lat for every pixel on the disc.
    phi0, lam0 = math.radians(CENTER_LAT), math.radians(CENTER_LON)
    rho = np.sqrt(d2)
    cc = np.arcsin(np.clip(rho, 0, 1))
    with np.errstate(invalid='ignore', divide='ignore'):
        lat = np.arcsin(np.cos(cc) * math.sin(phi0) + np.where(rho > 0, ny * np.sin(cc) * math.cos(phi0) / rho, 0))
        lon = lam0 + np.arctan2(nx * np.sin(cc), rho * np.cos(cc) * math.cos(phi0) - ny * np.sin(cc) * math.sin(phi0))
    lon = (np.degrees(lon) + 180) % 360 - 180
    lat = np.degrees(lat)
    h, w = land.shape
    mx = np.clip(((lon + 180) / 360 * w).astype(int), 0, w - 1)
    my = np.clip(((90 - lat) / 180 * h).astype(int), 0, h - 1)
    is_land = land[my, mx] & inside

    # Lambert shading plus a little ambient light.
    normal = np.stack([nx, ny, nz], axis=-1)
    lambert = np.clip(normal @ LIGHT, 0, 1)
    shade = 0.35 + 0.65 * lambert

    ocean = OCEAN_DEEP + (OCEAN_LIGHT - OCEAN_DEEP) * shade[..., None]
    ground = LAND_DARK + (LAND_LIGHT - LAND_DARK) * shade[..., None]
    rgb = np.where(is_land[..., None], ground, ocean)

    # Faint meridians and parallels every 30°: a nod to the "web".
    grid = ((np.abs(((lon + 180) % 30) - 15) > 14.55) | (np.abs(((lat + 90) % 30) - 15) > 14.55)) & inside
    rgb = np.where(grid[..., None], rgb * 0.82 + 255 * 0.18, rgb)

    # Darken towards the edge (limb), then a dark rim.
    limb = np.clip((1 - nz) ** 3, 0, 1)
    rgb = rgb * (1 - 0.45 * limb[..., None])
    edge = (rho > 0.975) & inside
    rgb = np.where(edge[..., None], RIM, rgb)

    # Gloss: an Aqua-style highlight over the upper half, with a soft edge, bright at the top.
    gx, gy = nx / 0.74, (ny - 0.47) / 0.47
    inside_gloss = np.clip((1 - np.sqrt(gx * gx + gy * gy)) / 0.06, 0, 1)
    fade = np.clip((ny - 0.05) / 0.85, 0, 1)
    gloss = inside_gloss * (0.12 + 0.6 * fade ** 0.9)
    rgb = rgb + (255 - rgb) * gloss[..., None]

    alpha = inside.astype(np.float64) * 255
    out = np.dstack([np.clip(rgb, 0, 255), alpha]).astype(np.uint8)
    return Image.fromarray(out, 'RGBA').resize((size, size), Image.LANCZOS)


def tile_icon(size, globe_img, top, bottom):
    """A macOS-shaped tile in the skin's colours with the globe and soft shadows."""
    ss = 4
    S = size * ss
    canvas = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    inset, side, radius = round(S * 100 / 1024), round(S * 824 / 1024), round(S * 185 / 1024)

    # Tile shadow.
    shadow = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle([inset, inset + S * 0.012, inset + side, inset + side + S * 0.012],
                                             radius, fill=(0, 0, 0, 70))
    canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(S * 0.012)))

    # Tile gradient.
    grad = Image.new('RGBA', (1, side))
    for y in range(side):
        t = y / (side - 1)
        grad.putpixel((0, y), tuple(round(a + (b - a) * t) for a, b in zip(top, bottom)) + (255,))
    grad = grad.resize((side, side))
    mask = Image.new('L', (side, side), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, side - 1, side - 1], radius, fill=255)
    canvas.paste(grad, (inset, inset), mask)

    # Globe shadow, then the globe.
    g = round(S * 700 / 1024)
    big = globe_img.resize((g, g), Image.LANCZOS)
    gshadow = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(gshadow).ellipse([(S - g) / 2 + S * 0.03, (S - g) / 2 + S * 0.06,
                                     (S + g) / 2 - S * 0.03, (S + g) / 2 + S * 0.04], fill=(0, 20, 60, 80))
    canvas.alpha_composite(gshadow.filter(ImageFilter.GaussianBlur(S * 0.025)))
    canvas.alpha_composite(big, ((S - g) // 2, (S - g) // 2 - round(S * 0.01)))
    return canvas.resize((size, size), Image.LANCZOS)


def main():
    land = land_map()
    g = globe(1024, land)
    g.save(HERE / 'globe.png')
    iconset = ROOT / 'Host/Assets.xcassets/AppIcon.appiconset'
    for skin, (top, bottom) in SKINS.items():
        tile_icon(1024, g, top, bottom).save(ROOT / 'Resources/SkinIcons' / f'{skin}.png')
    top, bottom = SKINS['luna']
    for points in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            px = points * scale
            name = f'icon_{points}x{points}' + ('@2x' if scale == 2 else '') + '.png'
            # Small sizes get a globe drawn at their own size (sharper than downscaling).
            gl = g if px >= 256 else globe(round(px * 700 / 1024) * 2, land)
            tile_icon(px, gl, top, bottom).save(iconset / name)
    print('wrote', HERE / 'globe.png', 'and the app icons')


if __name__ == '__main__':
    main()
