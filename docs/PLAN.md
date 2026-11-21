# Dialup: plan and architecture (kept current)

A macOS browser that looks and feels like 2001–2004 browsers (Windows XP, Mac OS X Aqua, Windows 98/2000 Classic) on modern WebKit. It's meant to be easy to reskin and extend: the whole UI is HTML/CSS, with no build step.

## Architecture (as built)

```
DialupWindow (borderless and transparent; the skin draws the frame and corners)
 └─ BrowserLayoutView
     ├─ Chrome WKWebView   dialup://chrome/index.html  (transparent; draws title bar, toolbars, status bar)
     ├─ Page WKWebView     the active tab, positioned by insets the chrome reports
     └─ ScanlineView       Dial-up Mode CRT overlay (ignores clicks)
```

- **Host (Swift 6, `Host/`):**
  - `App/`: `AppDelegate` (windows, session restore, default browser; opens no windows while hosting tests), `MainMenu` (every shortcut), `Preferences` + `PreferencesStore`, `PatchableSettings` (the tolerant decoding and JSON-patch merging shared by both settings models), `Bookmarks` (bookmarks.html), `SoundEffects` (synthesized sounds), `SkinIcon`, `LaunchEnvironment` (XCTest detection, debug-only overrides).
  - `Window/`: `BrowserWindowController` (tabs, chrome events, window state, navigation helpers), with the chrome's commands in `+HostCommands` and native menu actions in `+MenuActions`; `BrowserWindowOpening` (how a window opens others, injected by the app delegate), `BookmarksPanels`, `NativePopupMenu`, `BrowserLayoutView`, `DialupWindow`, `DebugSnapshot`.
  - `Tabs/`: `Tab` (one page: navigation policy, downloads, JS dialogs, crash recovery) and `TabList` (pure tab order and active index, unit-tested).
  - `Bridge/`: `ChromeBridge` (the only door into the host), `HostCommand` (every command parsed and validated once), `DialupSchemeHandler` (serves `dialup://`, symlink-safe).
  - `Page/`: `PageConfiguration` (pages' WebKit configuration and the hover-link script), `AdBlocker`, `AddressResolver`, `StartPageSchemeHandler`.
  - `DialupMode/`: `DialupModeSettings`, `DialupModeStore`, `DialupModeRenderer` (Core Image filters), `DialupModePageScript` + `page-script.js` (the in-page script, a bundled resource), `ScanlineView`.
- **Chrome (`Chrome/`):** `index.html` and `base.css` (Luna look), `skins/*.css`, `js/main.js` (UI), `js/host.js` (bridge, plus `mock-host.js` for browser-only development), `js/overlay.js` (HTML menus and dialogs), `js/settings.js` (Dialup Options), `js/wizard.js` (first-run wizard).
- **Bridge:** `host.call(cmd, args)` goes to the host; the host sends `window.dialup.receive({event, data})` back. Documented in `docs/host-api.md`. Only the chrome's main frame on `dialup://` is accepted, and unknown or malformed commands are ignored.
- **Overlay:** while a menu or dialog is open, the host raises the transparent chrome above the page, so menus never get clipped.
- **Pages:** a separate WebKit configuration with no bridge and no `dialup://`. The only extras are a hover-link script and the Dial-up Mode script, both in isolated content worlds, the ad-blocking content rule list, plus `dialup-start://` (static start page; personal config only for the start page itself).
- **Single sources of truth:** presets, connection speeds (from the `Connection` enum), the picture cap, default links, skins and search engines (enums) and the favorites cap all live in Swift and reach JS through `prefs.catalog`.
- **Tests and CI:** `Tests/` has one file per area (address bar, bridge commands, tab order, settings, security boundaries, scheme handler, bookmarks, ad blocker, Dial-up Mode and its page script in a real WKWebView). GitHub Actions builds and tests every push.

## Done

- Test build; custom title bar; skins Luna (default) and Aqua; retro HTML menus and dialogs; Dialup Options; first-run Setup Wizard; retro start page.
- Dial-up Mode: image trickle-in with "(n items remaining)", dial-in sequence, 256-colour images, faint CRT, old fonts, page touches (safe ones on, risky ones opt-in), hard-mode whole-page filters.
- Fixes from the first review: detached images, start-page privacy and Customize lock, stale status, settings and wizard only send changed keys, address bar dirtiness, dialog key stack and focus trap, lifecycle, debug-only flags.

## Done in the second round

- Authenticity pass for Luna and Aqua, original synthesized sounds, padlock and certificate dialog, portal start page.
- Tabs with the wizard and Settings choice (tabs or one page per window), session restore with lazily loaded tabs, popups as tabs or cascading windows.
- Wayback button, Classic (98/2000) skin, Favorites menu, Add to Favorites, bookmarks.html import/export.
- Skin-drawn window corners, IE-style address bar dropdown, start page redesign (800×600 home page with per-skin personality).
- Security groundwork for add-ons: symlink-safe scheme handler (tested) and a Content-Security-Policy on the browser UI. The add-on design is in `docs/EXTENDING-PROPOSAL.md`.

## Done in the third round

- Icons from the Tango Icon Library (public domain); the app icon is the Tango globe on a tile per skin, and the Dock icon follows the skin.
- Start page redesign: a 2004 search engine front page (tabs, one box, two buttons, a random Wikipedia article), with the portal one click away.
- Ad and tracker blocking with a native content rule list (compiled once, cached across launches).
- Browser basics: downloads, file uploads, `prompt()`, external links, zoom, print, find in page, default browser.
- Swift refactor: typed host commands, a tested `TabList`, shared settings decoding, the page script as a bundled resource, async/await panels and rule lists, no windows while hosting tests, and CI.

## Next

1. Toolbar plugins (`Toolbars/<id>/manifest.json`, sandboxed iframes with a permission gate), with draggable rebar bands and Lock the Toolbars.
2. Explorer-style sidebars (Search, Favorites, History), history storage.
3. Address autocomplete, a downloads window.
4. More skins (Platinum, Communicator-style), and skin import.
5. Real throttling proxy for Dial-up Mode, a pop-up blocker with an information bar, WKWebExtension.
