# Dialup app icon

An original cream CRT on a glossy cyan-to-ocean-blue tile. The screen holds a small globe with invented islands and a tilted web page: picture bands and fading lines suggest a page arriving over a slow connection. A warm gold telephone coil, modem-style lights in the monitor foot, and a connection sparkle complete the early-web mood. Soft moulded bevels, glass reflections, and warm highlights recall 2001–2004 desktop illustration.

Both SVGs use a 1024 × 1024 canvas, an 824 × 824 body at (100, 100), and 185 px corners. A subtle shadow sits below the body; the surrounding canvas is transparent. No text, fonts, external assets, or existing logos are used. All artwork is editable vector geometry.

`icon-small.svg` keeps the monitor, globe, page, and sparkle, while removing the cord, globe grid, reflections, and fine controls. Wider outlines and larger picture bands preserve the silhouette at 16 and 32 px.

The ten PNGs follow macOS iconset naming and the requested pixel sizes. Exports through 64 px use the small SVG; 128–1024 px use the master. They were rendered with sharp/librsvg in sRGB, visually inspected at 1024, 64, 32, and 16 px, and checked for dimensions and transparent corners. The icon grid is provided in the artwork; application asset configuration determines how macOS installs and presents it.

To regenerate, run `node render.cjs` with the `sharp` module available. The helper also recognizes the local ChatGPT bundled module, or an explicit `SHARP_MODULE` path. Use an SVG renderer with full gradient, clipping, and filter support; ImageMagick's internal MSVG renderer misrenders this artwork.
