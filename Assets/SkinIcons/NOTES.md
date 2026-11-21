# Dialup skin icons

Three original, hand-built vector compositions. Each uses a 1024 × 1024 canvas and an 824 × 824 rounded-square body at (100, 100), with a 185 px corner radius, a fine edge highlight, and a soft layered shadow. The supplied cream-CRT icon informed the shared grid, generous margins, and finished dimensional rendering. No artwork was traced or embedded.

## Luna

A saturated blue globe with invented continent shapes, luminous latitude/longitude curves, a white specular reflection, and one closed golden orbit. The ring's back section sits behind the globe; its front section crosses the globe. A sky-blue tile with subdued meadow-green curves recalls the cheerful colour and glossy object rendering of the XP period. The original globe-and-orbit composition conveys connecting to the web without a letter, browser monogram, or reproduced logo.

## Aqua

A blue gel rotary telephone dial, with exactly ten recessed finger holes, a chrome outer rim, a small white centre disc, and a metal finger stop. Horizontal pinstripes and a silver-grey tile recall early Mac OS X materials. Broad gel reflections and cool metal highlights supply the period feeling; the telephone mechanism supplies Dialup's own motif. There is no compass, needle, rose, or browser emblem.

## Classic

A sparse navy sky above a curved blue-green Earth. One cream-coloured comet leaves a wavy, asymmetric tail, suggesting a modem signal. Chunky invented land masses, stepped atmospheric bands, a restrained palette, and flatter shading evoke late-1990s web artwork. The signal comet is its own drawing; no letter, wheel, animal, flag, or existing logo is used. The rendering evokes indexed-colour art without limiting the PNG alpha channel or forcing a literal 256-colour palette.

## Sizes and small artwork

Each design has a detailed `<name>.svg` and a distinct `<name>-small.svg`. The 16, 32, and 64 px PNGs use the small master; 128, 256, 512, and 1024 px use the detailed master. Small Luna drops the fine globe grid and secondary reflections. Small Aqua drops the tile pinstripes and fine hole highlights while retaining all ten holes. Small Classic reduces the star field, removes the horizon grid, and thickens the comet and signal tail. All SVGs are self-contained, with no text, fonts, linked resources, or raster images.

`sheet.png` shows all three 256 px icons together, followed by their actual 32 px and 16 px exports, on a light background. The sheet and full-size artwork were visually inspected; the small comet was strengthened after review. All 21 PNG dimensions and their transparent corner pixels were checked.

## Rebuilding on macOS

Run `python3 build_icons.py`, then `python3 make_sheet.py` (Pillow required for the sheet). The build script compiles the included `render.swift` helper using AppKit's native SVG reader, then renders the PNGs. This avoids the installed ImageMagick SVG renderer's incorrect transform and gradient handling. All build inputs and outputs stay in this directory. The shadow uses translucent vector layers, so the visible tile shadow does not depend on SVG filter support.
