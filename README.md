# Kikare

A browser from 2003, built in 2026. It has rebar toolbars, a throbber, a status bar with a security zone, and later add-on search bars, all on modern WebKit (the same engine as Safari).

## How it works

```
NSWindow
 ├─ Chrome WKWebView   kikare://chrome/index.html — the whole UI is HTML/CSS/JS (Chrome/)
 └─ Page WKWebView     the web page, positioned inside insets the chrome reports
```

- **Host** (`Host/`, Swift): windows, menus and shortcuts, focus, the page web view, the bridge.
- **Chrome** (`Chrome/`, plain HTML/CSS/ES modules, no build step): everything you see around the page.
- The chrome talks to the host with `host.call(cmd, args)`. The host pushes events with `window.kikare.receive({event, data})`. See [docs/host-api.md](docs/host-api.md).
- **Security rule:** web pages use a separate WebKit configuration with no bridge and no `kikare://` scheme. A unit test enforces it.

## Build & run

```sh
brew install xcodegen          # once
xcodegen generate
xcodebuild -scheme Kikare -derivedDataPath build build
open build/Build/Products/Debug/Kikare.app
xcodebuild -scheme Kikare -derivedDataPath build test
```

## Hacking on the UI without Xcode

```sh
cd Chrome && python3 -m http.server 8000   # open http://localhost:8000
```

Without a native host, `js/mock-host.js` fakes one, so you can restyle the chrome in any browser. Inside the app, use **View → Reload Chrome** (⌥⌘R) after editing files in the built app bundle. The chrome and pages are inspectable with Safari's Web Inspector (Develop menu).

## Debug snapshot

```sh
build/Build/Products/Debug/Kikare.app/Contents/MacOS/Kikare -KikareSnapshot /tmp/kikare.png -KikareSnapshotDelay 6
```

## Roadmap

0. ✅ Test build: chrome web view + page, address bar, nav buttons, throbber, status bar, history dropdowns
1. Tabs, session restore, multiple windows
2. Skins (`Skins/<id>/skin.json + skin.css`)
3. Toolbar plugins (`Toolbars/<id>/manifest.json`), rearrangeable rebar
4. Favorites, history sidebar, downloads, find, zoom, autocomplete
5. Real extensions via WKWebExtension (optional)
6. Polish: content blocking, icon, about box
