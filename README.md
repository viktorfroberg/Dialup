<h1 align="center"><img src="site/img/icon-64.png" width="64" height="64" alt=""><br>Dialup</h1>

<p align="center"><i>The web browser that looks like 2003.</i></p>

<p align="center">
  <a href="https://github.com/viktorfroberg/Dialup/releases/latest/download/Dialup.zip"><img src="site/img/btn-get-dialup.gif" width="88" height="31" alt="Get Dialup!"></a>
  <img src="site/img/btn-made-on-mac.gif" width="88" height="31" alt="Made on a Mac">
  <a href="LICENSE"><img src="site/img/btn-mit.gif" width="88" height="31" alt="MIT open source"></a>
  <img src="site/img/btn-no-cookies.gif" width="88" height="31" alt="No cookies">
  <img src="site/img/btn-800x600.gif" width="88" height="31" alt="Best viewed at 800x600">
</p>

<p align="center">
  <a href="https://github.com/viktorfroberg/Dialup/actions/workflows/ci.yml"><img src="https://github.com/viktorfroberg/Dialup/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
</p>

Dialup is a macOS browser that looks and feels like the browsers of 2001–2004: the blue Windows XP title bar, the brushed-metal Mac toolbar, the grey 3D bevels of Windows 98. Underneath it's modern WebKit (the engine Safari uses), so today's web works fine. Turn on **Dial-up Mode** and pictures trickle in at modem speed while the status bar counts down "(3 items remaining)".

<p align="center">
  <img src="docs/screenshots/dialup-mode.gif" width="800" alt="Animation: Dial-up Mode loading the 1996 Space Jam website. The planets appear one by one while the status bar counts down the items remaining, then reads Done.">
</p>

The whole browser UI is plain HTML and CSS, with no build step. A skin is one CSS file.

## Download

**[⬇ Download Dialup for macOS](https://github.com/viktorfroberg/Dialup/releases/latest/download/Dialup.zip)** · macOS 15.4 or later · Apple silicon and Intel · free ([MIT](LICENSE)) · [all releases](https://github.com/viktorfroberg/Dialup/releases)

**The easy way (no security warning):** paste this into Terminal. It downloads the latest version, checks it, puts it in Applications and opens it. [Read the script first](install.sh) if you like; it's short.

```sh
curl -fsSL https://raw.githubusercontent.com/viktorfroberg/Dialup/main/install.sh | sh
```

**Or download the zip**, unzip it and drag Dialup.app to Applications. Dialup isn't notarized by Apple, so macOS blocks the first launch: try to open it once, then go to **System Settings → Privacy & Security**, scroll down and click **Open Anyway**.

**Updates are built in.** Dialup checks GitHub quietly when it starts (you can turn that off in Dialup Options), and **Help → Check for Updates…** checks right away. Updates are signed, and after the first install they open without any warning.

<p align="center">
  <img src="docs/screenshots/skins.gif" width="800" alt="Animation: the start page in the three skins, Luna, Aqua and Classic, one after another">
</p>

## Screenshots

<table>
  <tr>
    <td width="33%"><img src="docs/screenshots/skin-luna.png" alt="Luna skin: blue XP-style title bar and toolbars"></td>
    <td width="33%"><img src="docs/screenshots/skin-aqua.png" alt="Aqua skin: brushed-metal Mac-style toolbar with bookmarks bar"></td>
    <td width="33%"><img src="docs/screenshots/skin-classic.png" alt="Classic skin: grey Windows 98/2000-style chrome"></td>
  </tr>
  <tr>
    <td align="center"><b>Luna</b><br>Windows XP, 2001 (default)</td>
    <td align="center"><b>Aqua</b><br>Mac OS X, 2003</td>
    <td align="center"><b>Classic</b><br>Windows 98/2000</td>
  </tr>
</table>

<table>
  <tr>
    <td width="50%"><img src="docs/screenshots/dialup-mode.png" alt="Dial-up Mode: the 1996 Space Jam site, every picture in 256 colours"></td>
    <td width="50%"><img src="docs/screenshots/dialup-mode-hard.png" alt="Dial-up Mode hard mode: Wikimedia Commons in 216 dithered web-safe colours"></td>
  </tr>
  <tr>
    <td align="center"><b>Dial-up Mode</b>: pictures load at 56k speed, in GIF colours</td>
    <td align="center"><b>Hard mode</b>: the whole page in 216 dithered colours</td>
  </tr>
  <tr>
    <td><img src="docs/screenshots/options-dialup.png" alt="The Dialup Options dialog, Dial-up Mode tab, with visual previews of each colour setting"></td>
    <td><img src="docs/screenshots/setup-wizard.png" alt="The first-run Setup Wizard asking which computer you grew up with"></td>
  </tr>
  <tr>
    <td align="center"><b>Dialup Options</b> (⌘,) with live previews</td>
    <td align="center"><b>Setup Wizard</b> on first run</td>
  </tr>
  <tr>
    <td><img src="docs/screenshots/start-page-luna.png" alt="The built-in start page in the Luna skin: a 2004-style search page with search tabs, your favorites and a site of the day"></td>
    <td><img src="docs/screenshots/start-page-aqua.png" alt="The same start page in the Aqua skin, with Aqua-style buttons"></td>
  </tr>
  <tr>
    <td align="center"><b>Start page</b>, hand-made at 800×600</td>
    <td align="center">…and it dresses up to match each skin</td>
  </tr>
</table>

## Features

- **Three skins.** Luna, Aqua and Classic each restyle everything: title bar, caption buttons, toolbars, menus, dialogs, tooltips, dropdowns and the status bar. The window itself is borderless, so the skin draws the whole frame, rounded XP and Aqua corners included.
- **Dial-up Mode** (⇧⌘D). Pictures load line by line at 56k, ISDN or 512k speed with a live "(n items remaining)" count. You also get a dial-in sequence, 256-colour "GIF" pictures, a faint CRT glow and scanlines, and old fonts. Hard mode puts the whole page in 16-bit or 216 web-safe colours, dithered if you like.
- **Retro page touches.** Classic scrollbars and square corners (on by default). No shadows, no animations and underlined links are opt-in.
- **Sounds.** Original synthesized clicks, a page-complete tick, error and ding, and a modem handshake. No samples taken from anywhere.
- **Tabs, or one page per window.** You choose in the wizard, like it's 2004. Session restore loads tabs lazily.
- **Wayback button.** Reload the current page as the Wayback Machine saw it in a year you pick.
- **Favorites.** Add to Favorites (⌘D), a Favorites menu and a Links bar (Aqua gets a bookmarks bar). Import and export the Netscape `bookmarks.html` format that every browser still understands.
- **A 2004-style start page** (`about:home`): a search engine front page with a wordmark, Web/Images/News/Wikipedia/Archive tabs, one big box and two buttons (one opens a random Wikipedia article). The portal-style page, with favorites, a webring and 88×31 buttons, is one click away.
- **Ad and tracker blocking** (on by default). Well-known ad and tracking networks are blocked with WebKit's native content rule lists, the engine Safari's blockers use. The domain list is Dialup's own.
- **Browser basics.** Downloads to ~/Downloads (never overwriting), file uploads, find in page (⌘F, ⌘G), zoom (⌘+ ⌘− ⌘0), print, JavaScript dialogs, mailto: and other links handed to the right app, and Dialup can be your default browser (Dialup → Make Dialup the Default Browser…).
- **Era details.** Padlock and certificate dialog, security zone in the status bar, throbber, address-bar combo dropdown, Back/Forward history menus.
- **Setup Wizard** on first run (Help → Setup Wizard… to see it again), and **Dialup Options** with visual previews of every Dial-up Mode setting.

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

The tests run inside the app, but it opens no windows and leaves your saved session alone while they do. GitHub Actions runs the same build and tests on every push and pull request ([`.github/workflows/ci.yml`](.github/workflows/ci.yml)).

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
- **Bridge:** the chrome calls `host.call(cmd, args)`. The host pushes events back with `window.dialup.receive({event, data})`. See [docs/host-api.md](docs/host-api.md).
- **Menus that can cover the page:** while a menu or dialog is open, the host raises the transparent chrome web view above the page, so nothing gets clipped.

**The security boundary.** The browser UI and web pages never share a WebKit configuration. Pages get their own configuration with **no bridge** and **no `dialup://` scheme**, so a website can't call the host or load the chrome's files. The bridge only accepts messages from the chrome's main frame on `dialup://`. The scheme handler resolves symlinks before its folder check, and the chrome runs under a strict Content-Security-Policy (own files only, no remote scripts, styles or frames). The only extras injected into pages (a hover-link helper and the Dial-up Mode script) run in isolated content worlds. The start page's personal config is only served to the start page itself. Unit tests in `Tests/` check the bridge, scheme-handler and start-page rules.

## Make it yours

**Skins are CSS.** Each skin is one file in [`UI/skins/`](UI/skins/) (`luna.css`, `aqua.css`, `classic.css`) on top of `UI/base.css`. `base.css` declares the variables (`--face`, `--rebar-bg`, `--icon-back`…) and lists the class names in its header comment. Tweaking a built-in skin is just editing its CSS. Adding a brand-new skin today means copying one and adding a case to the `Skin` enum in `Host/App/Preferences.swift` (plus a few per-skin touches in the wizard and the page scrollbars in `Host/DialupMode/page-script.js`). Installable user skins from a folder are planned; see [docs/EXTENDING-PROPOSAL.md](docs/EXTENDING-PROPOSAL.md).

**Hack on the UI without Xcode.** The chrome runs in any browser with a fake host:

```sh
cd UI && python3 -m http.server 8000   # then open http://localhost:8000
```

Without a native host, `js/mock-host.js` stands in for it, so you can restyle the whole browser in Safari or Chrome: edit, reload, repeat, with devtools at hand.

**Inside the app**, use **View → Reload Chrome** (⌥⌘R) after editing files in the built app bundle. Both the chrome and pages can be inspected with Safari's Web Inspector (Develop menu).

**Debug snapshots** (debug builds only, like the `-HomePage` override) write the composited window to a PNG without Screen Recording permission. That's how the screenshots above were made:

```sh
build/Build/Products/Debug/Dialup.app/Contents/MacOS/Dialup \
  -DialupSnapshot ~/Desktop/dialup.png -DialupSnapshotDelay 6 \
  -HomePage "https://www.spacejam.com/1996/"
# add  -DialupChromeEval "<js>"  to run JavaScript in the UI first (e.g. open a dialog),
# and  -DialupSnapshotFrames 20 -DialupSnapshotInterval 0.3  for a numbered sequence (how the GIFs were made)
```

**Docs:** [docs/host-api.md](docs/host-api.md) (chrome ↔ host bridge), [docs/PLAN.md](docs/PLAN.md) (architecture and plan), [docs/EXTENDING-PROPOSAL.md](docs/EXTENDING-PROPOSAL.md) (user skins, toolbars and add-ons). There's an index in [docs/README.md](docs/README.md).

## Roadmap

Next up, roughly in order:

1. Toolbar plugins in sandboxed iframes, with draggable rebar bands and Lock the Toolbars.
2. Explorer-style sidebars (Search, Favorites, History) and history storage.
3. Address autocomplete and a downloads window.
4. More skins (Platinum, Communicator-style) and user skins you can install without rebuilding.
5. A real throttling proxy for Dial-up Mode, a pop-up blocker with an information bar, WebExtensions.

See [docs/PLAN.md](docs/PLAN.md) for the full plan and [docs/EXTENDING-PROPOSAL.md](docs/EXTENDING-PROPOSAL.md) for how add-ons could work safely. What has shipped so far is in [CHANGELOG.md](CHANGELOG.md).

## Originality

The skins, sounds and start page are original, drawn or synthesized for Dialup. Toolbar and settings icons and the globe in the app icon come from the **Tango Icon Library** (public domain), real icons from the era by human artists. The skins are *inspired by* the look of the era. They don't contain any Microsoft or Apple artwork, and Dialup isn't affiliated with or endorsed by Microsoft, Apple, Netscape or anyone else. Windows, Windows XP, Internet Explorer, Mac OS X, Aqua, Safari and other names mentioned are trademarks of their respective owners. Websites in the screenshots belong to their owners.

## Credits

- **Icons:** [Tango Icon Library](http://tango.freedesktop.org/) 0.8.90 by the Tango Desktop Project artists, released into the public domain. Files are in `UI/img/tango/`.
- **Engine:** WebKit, via Apple's WKWebView.
- **Updates:** [Sparkle](https://sparkle-project.org/) (MIT).

## License

[MIT](LICENSE). Use it, fork it, reskin it. The Tango icons are public domain.

<p align="center">
  <img src="site/img/btn-dialup-now.gif" width="88" height="31" alt="Dialup NOW!">
  <img src="site/img/btn-valid-html.gif" width="88" height="31" alt="Valid HTML">
  <img src="site/img/counter.gif" alt="Visitor counter (decoration)"><br>
  <sub>Best viewed in Dialup at 800×600.</sub>
</p>
