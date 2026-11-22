# Developing Dialup

How to build Dialup, how it's put together, and how to change it. Back to the [main README](../README.md).

## Build & run

**Requirements:** macOS 15.4 or later, Xcode 16 or later (Swift 6), and [XcodeGen](https://github.com/yonaskolb/XcodeGen) via Homebrew.

```sh
brew install xcodegen                 # once
git clone https://github.com/viktorfroberg/Dialup.git
cd Dialup
xcodegen generate                     # creates Dialup.xcodeproj (not checked in)
xcodebuild -project Dialup.xcodeproj -scheme Dialup -derivedDataPath build build
open build/Build/Products/Debug/Dialup.app
```

Run the tests:

```sh
xcodebuild -project Dialup.xcodeproj -scheme Dialup -derivedDataPath build test
```

The tests run inside the app, but it opens no windows and leaves your saved session alone while they do. GitHub Actions runs the same build and tests on every push and pull request ([`.github/workflows/ci.yml`](../.github/workflows/ci.yml)).

Or open `Dialup.xcodeproj` in Xcode and press ⌘R.


## How it works

```
DialupWindow (borderless and transparent; the skin draws the frame)
 └─ BrowserLayoutView
     ├─ UI WKWebView       dialup://chrome/index.html  (transparent; draws title bar, toolbars, status bar)
     ├─ Page WKWebView     the website, positioned inside insets the UI reports
     └─ ScanlineView       Dial-up Mode CRT overlay (ignores clicks)
```

- **Host** (`Host/`, Swift 6): windows, native menus and shortcuts, focus, preferences, tabs, Dial-up Mode, ad blocking, sounds, bookmarks, downloads, and the bridge. Commands from the chrome are parsed into a typed `HostCommand`; tab order lives in a small, unit-tested `TabList`.
- **Browser UI** (`UI/`, plain HTML/CSS/ES modules, no build step): everything you see around the page, plus the HTML menus and dialogs, Dialup Options and the wizard. In the code and docs it's called the *chrome*, the old word for a browser's own interface around the page. (It has nothing to do with Google Chrome, which was named after it.)
- **Start page** (`Start/`): static files served to pages as `dialup-start://home/`.
- **Bridge:** the chrome calls `host.call(cmd, args)`. The host pushes events back with `window.dialup.receive({event, data})`. See [docs/host-api.md](host-api.md).
- **Menus that can cover the page:** while a menu or dialog is open, the host raises the transparent chrome web view above the page, so nothing gets clipped.

**The security boundary.** The browser UI and web pages never share a WebKit configuration. Pages get their own configuration with **no bridge** and **no `dialup://` scheme**, so a website can't call the host or load the chrome's files. The bridge only accepts messages from the chrome's main frame on `dialup://`. The scheme handler resolves symlinks before its folder check, and the chrome runs under a strict Content-Security-Policy (own files only, no remote scripts, styles or frames). The only extras injected into pages (a hover-link helper and the Dial-up Mode script) run in isolated content worlds. The start page's personal config is only served to the start page itself. Unit tests in `Tests/` check the bridge, scheme-handler and start-page rules.

## Make it yours

**Skins are CSS.** Each skin is one file in [`UI/skins/`](../UI/skins/) (`luna.css`, `aqua.css`, `classic.css`) on top of `UI/base.css`. `base.css` declares the variables (`--face`, `--rebar-bg`, `--icon-back`…) and lists the class names in its header comment. Tweaking a built-in skin is just editing its CSS. Adding a brand-new skin today means copying one and adding a case to the `Skin` enum in `Host/App/Preferences.swift` (plus a few per-skin touches in the wizard and the page scrollbars in `Host/DialupMode/page-script.js`). Installable user skins from a folder are planned; see [docs/EXTENDING-PROPOSAL.md](EXTENDING-PROPOSAL.md).

**Hack on the UI without Xcode.** The chrome runs in any browser with a fake host:

```sh
cd UI && python3 -m http.server 8000   # then open http://localhost:8000
```

Without a native host, `js/mock-host.js` stands in for it, so you can restyle the whole browser in Safari or Chrome: edit, reload, repeat, with devtools at hand.

**Inside the app**, use **View → Reload Chrome** (⌥⌘R) after editing files in the built app bundle. Both the chrome and pages can be inspected with Safari's Web Inspector (Develop menu).

**Debug snapshots** (debug builds only, like the `-HomePage` override) write the composited window to a PNG without Screen Recording permission. That's how the README's screenshots and GIFs were made:

```sh
build/Build/Products/Debug/Dialup.app/Contents/MacOS/Dialup \
  -DialupSnapshot ~/Desktop/dialup.png -DialupSnapshotDelay 6 \
  -HomePage "https://www.spacejam.com/1996/"
# add  -DialupChromeEval "<js>"  to run JavaScript in the UI first (e.g. open a dialog),
# and  -DialupSnapshotFrames 20 -DialupSnapshotInterval 0.3  for a numbered sequence (how the GIFs were made)
```

**Docs:** [docs/host-api.md](host-api.md) (chrome ↔ host bridge), [docs/PLAN.md](PLAN.md) (architecture and plan), [docs/EXTENDING-PROPOSAL.md](EXTENDING-PROPOSAL.md) (user skins, toolbars and add-ons). There's an index in [docs/README.md](README.md).

## Roadmap

Next up, roughly in order:

1. Toolbar plugins in sandboxed iframes, with draggable rebar bands and Lock the Toolbars.
2. Explorer-style sidebars (Search, Favorites, History) and history storage.
3. Address autocomplete and a downloads window.
4. More skins (Platinum, Communicator-style) and user skins you can install without rebuilding.
5. A real throttling proxy for Dial-up Mode, a pop-up blocker with an information bar, WebExtensions.

See [docs/PLAN.md](PLAN.md) for the full plan and [docs/EXTENDING-PROPOSAL.md](EXTENDING-PROPOSAL.md) for how add-ons could work safely. What has shipped so far is in [CHANGELOG.md](../CHANGELOG.md).

## Originality

The skins, sounds and start page are original, drawn or synthesized for Dialup. Toolbar and settings icons come from the **Tango Icon Library** (public domain), real icons from the era by human artists. The app icon's globe is drawn by a script from Natural Earth map data (public domain); see `Assets/AppIcon/`. The skins are *inspired by* the look of the era. They don't contain any Microsoft or Apple artwork, and Dialup isn't affiliated with or endorsed by Microsoft, Apple, Netscape or anyone else. Windows, Windows XP, Internet Explorer, Mac OS X, Aqua, Safari and other names mentioned are trademarks of their respective owners. Websites in the screenshots belong to their owners.
