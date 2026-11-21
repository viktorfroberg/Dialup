# App icons

The Dialup mark is the **Tango "internet-web-browser" globe** (Tango Icon Library 0.8.90, public domain)
on a plain macOS-shaped tile, coloured per skin: sky blue (Luna), light grey (Aqua), navy (Classic).
The 32 px size uses Tango's hand-pixelled 22 px globe.

Recipe (needs ImageMagick):
```sh
swiftc -O tools/webrender.swift -o /tmp/webrender      # renders SVG with WebKit (keeps Tango's gradients)
/tmp/webrender globe.svg /tmp/globe-1024.png 1024
# tile: 824x824 rounded square (radius 185) at +100+100 on a 1024 canvas, soft shadow, globe at 700 px centred
```
Outputs go to `Host/Assets.xcassets/AppIcon.appiconset/` (Luna) and `Resources/SkinIcons/<skin>.png`.
