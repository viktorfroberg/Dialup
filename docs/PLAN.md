# Kikare — a 2003-style browser on modern WebKit

## Context
Hobby project in the empty folder `~/hacks/browser`. Goal: a real, usable macOS browser that looks and feels like 2002–2004 browsers (IE6, Safari 1, Firefox 1.0). It has rearrangeable toolbar rows ("rebar"), add-on search/links bars, a throbber, a status bar and an Explorer-style sidebar. It also supports modern essentials: tabs, real sites, and later Chrome extensions. People should be able to reskin it and write toolbars without touching Swift.

Research outcome (previous turn): the "Search" browser (github.com/driceroland/Search, MIT) is Swift + WKWebView, not Rust. We use the same engine approach. The difference is that we draw the browser UI in HTML/CSS inside its own WKWebView (Firefox-1.0/XUL style), so skins = CSS and toolbars = small web apps.

Environment checked: Xcode 27 / Swift 6.4, macOS 27, `xcodegen` installed, **no Node**. So the UI is plain ES modules and CSS with no build step. That's also more hackable for skin and toolbar authors.

## Architecture
```
NSWindow
 ├─ Chrome WKWebView (fills window)  ← index.html: toolbars, tab strip, sidebar, status bar
 │     reports viewport *insets* (top/left/right/bottom) to host
 └─ Page WKWebView(s), one per tab, positioned by host inside those insets (only active one visible)
Native: main menu + all keyboard shortcuts, NSMenu popups (requested by chrome), focus, downloads, persistence
Optional: borderless NSPanel + WKWebView for address-bar autocomplete (the only overlay that must float over the page)
```

**Key decisions**
- **Two separate WKWebViewConfigurations.** The chrome config gets the `host` message handler and the `kikare://` scheme handler. The page config gets neither. Pages only get a tiny hover-link script in an isolated `WKContentWorld` posting `{url}` to a narrow handler, used for status bar text. This boundary is the core security rule.
- **`kikare://` custom scheme** (`WKURLSchemeHandler`) serves `chrome/`, `skins/<id>/`, `toolbars/<id>/`. Bundled resources are merged with user folders in `~/Library/Application Support/Kikare/{skins,toolbars}`, and user folders win.
- **Bridge v1:** chrome → host is `await host.call(cmd, args)` via `WKScriptMessageHandlerWithReply`. Host → chrome is `kikare.receive({event, data})` via `callAsyncJavaScript`. Messages are Codable enums in Swift and carry an `apiVersion` field.
- **Layout from insets, not rects,** so live window resize stays in sync without waiting on JS.
- **Native menus for every dropdown:** the in-window "File Edit View Favorites" bar, back/forward history and toolbar chevrons all call `host.popupMenu(items, point)`. This avoids clipping and removes most overlay needs.
- **Native owns shortcuts.** Main-menu key equivalents work regardless of focus. Cmd-L focuses the chrome web view, then JS focuses the address field. Enter navigates and gives focus back to the page.
- **Mock host:** `chrome/index.html?mock` runs in any browser (`python3 -m http.server`), so skin and toolbar authors iterate without Xcode.
- App Sandbox off (hobby project, reads user folders). Deployment target macOS 15.4 (needed for WKWebExtension).

## Repo layout
```
browser/
  project.yml                 XcodeGen → Kikare.xcodeproj (generated, gitignored)
  Host/
    App/AppDelegate.swift, MainMenu.swift
    Window/BrowserWindowController.swift, BrowserLayoutView.swift
    Tabs/Tab.swift (wraps WKWebView, KVO title/url/progress/canGoBack), TabStore.swift
    Bridge/ChromeBridge.swift, BridgeMessages.swift, KikareSchemeHandler.swift
    Page/PageConfiguration.swift, HoverLinkScript.swift, NavigationDelegate.swift
    Addons/SkinRegistry.swift, ToolbarRegistry.swift, Manifest.swift, Permissions.swift
    Store/Session.swift, Favorites.swift, History.swift (sqlite3 C API)
  Chrome/   index.html, base.css, js/{main,host,mock-host,tabs,rebar,toolbars,skins,statusbar,sidebar}.js
  Skins/    blasippa/ (Luna-ish blue, original art), akvarell/ (Aqua pinstripe-ish, original art)
            each: skin.json, skin.css, img/
  Toolbars/ search/, links/   each: manifest.json, index.html, toolbar.js
  Tests/    KikareTests (manifest parsing, permission gate, URL-vs-search input, tab state)
  docs/     host-api.md, skin-api.md (stable class names/parts + CSS variables), toolbar-api.md
```

## Plugin contracts
- **Skin** = `skin.json` (`id, name, author, apiVersion`) + `skin.css`, which overrides CSS variables and restyles documented classes, + images. View > Skin switches live.
- **Toolbar** = `manifest.json` (`id, name, slot: toolbar|sidebar|statusbar, entry, permissions: [currentUrl, navigate, search, storage]`). Runs in `<iframe sandbox="allow-scripts">` (opaque origin, no access to chrome DOM or pages). It gets the `retro.*` API over postMessage (`onNavigate`, `getCurrentUrl`, `navigate`, `setStatus`, `storage.get/set`). The chrome side checks the manifest permissions before forwarding anything to the host. v1 has no "read page content" permission.
- **Rebar:** toolbar rows with drag grippers, reorder/hide, lock toolbars, layout persisted.

## Phases (commit per phase, `git init` in `~/hacks/browser`)
0. **Spike: prove the risky parts (1–2 days).** Window + chrome view + one page view sized from insets. Address bar, back/forward/stop/reload, throbber, progress and hover-link text in the status bar. Cmd-L / Enter / Esc focus round-trip. One NSMenu popup from chrome (back-history dropdown).
   *Exit criteria:* no focus traps, live resize doesn't lag, typing in the page never triggers chrome shortcuts. If focus can't be made solid, fall back to SwiftUI-drawn chrome. Skins would then be JSON + 9-slice images, and toolbars would stay HTML in a sidebar.
1. **Tabs:** TabStore, tab strip (hidden when there's 1 tab, a pref), Cmd-T/W/Shift-Cmd-[ ], `target=_blank`/`window.open` → new tab via `WKUIDelegate`, session restore with lazily created web views, multiple windows.
2. **Skins:** registry, the two bundled skins, live switch, mock host, `skin-api.md`.
3. **Toolbars:** registry, sandbox + permission gate, rebar layout, Search bar (multiple providers) and Links bar, `toolbar-api.md`.
4. **Era features:** Favorites (menu, bar and sidebar), History sidebar, downloads (`WKDownload`) in the status bar, find in page, zoom, address autocomplete panel, element fullscreen enabled.
5. **Real extensions (optional, big):** `WKWebExtensionController`, starting with load-unpacked. Later CRX install and Chrome-API shims, borrowing from Search's `Crx.swift`/`ExtensionShims.swift` (MIT, with attribution).
6. **Polish:** `WKContentRuleList` ad blocking, app icon, about box with a fake "128-bit cipher strength".

## Self-critique (folded in)
- *Chrome JS hangs → browser unusable.* Native menu and shortcuts keep working. Add View > Reload Chrome.
- *Page gets host powers by accident.* Prevented by the split configurations. A unit test asserts the page config has no `host` handler.
- *Plugin abuse.* Opaque-origin iframes plus a manifest permission gate, and no page access in v1.
- *Scope creep.* Phase 5 is explicitly optional. Phases 0–3 already make a complete, fun browser.
- *Trademark/copying.* Original skins and art only, era-inspired, no Microsoft/Apple assets.
- *Things WebKit can't do.* No Widevine DRM (some streaming fails) and no built-in password manager. Accepted.

## Verification
- `xcodegen && xcodebuild -scheme Kikare build test` (unit tests for manifest parsing, permission gate, input→URL/search, page-config isolation).
- Run the app and work through the phase exit-criteria checklist. Take window screenshots with `screencapture -l<windowID>` to compare skins.
- `python3 -m http.server` in `Chrome/` and open `index.html?mock` to check skins and toolbars in a normal browser.
- Not deployed anywhere. Local builds only (ad-hoc signed).
