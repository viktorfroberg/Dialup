# App icons

Dialup's globe is drawn by [`tools/make_globe.py`](tools/make_globe.py) from real map data: Natural Earth's
1:110m land polygons ([`data/ne_110m_land.geojson`](data/ne_110m_land.geojson), public domain,
[naturalearthdata.com](https://www.naturalearthdata.com/)), projected onto a sphere over the Atlantic and shaded
in the glossy style of early-2000s icons. It sits on a macOS-shaped tile in each skin's colours: sky blue (Luna),
light grey (Aqua), navy (Classic).

```sh
python3 Assets/AppIcon/tools/make_globe.py     # needs numpy and Pillow
```

Writes `Host/Assets.xcassets/AppIcon.appiconset/` (Luna), `Resources/SkinIcons/<skin>.png` (the Dock icon
follows the skin) and `globe.png`. Small sizes get a globe drawn at their own size.
