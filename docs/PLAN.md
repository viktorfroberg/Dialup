# Dialup: plan and architecture (kept current)

A hobby macOS browser that looks and feels like 2001–2004 browsers (IE6/XP, Safari 1/Aqua, Firefox 1.0) on modern WebKit. It's meant to be easy to reskin and extend: the whole UI is HTML/CSS, with no build step.

## Architecture (as built)

```
NSWindow (titled, full-size content, native buttons hidden)
 └─ BrowserLayoutView
     ├─ Chrome WKWebView   dialup://chrome/index.html  (transparent; draws title bar, toolbars, status bar)
     ├─ Page WKWebView     the website, positioned by insets the chrome reports
     └─ ScanlineView       Dial-up Mode CRT overlay (ignores clicks)
```

- **Host (Swift, `Host/`):** windows, native menu and shortcuts, focus, preferences (`App/Preferences.swift`), Dial-up Mode (`DialupMode/`), the bridge (`Bridge/`), the start page scheme (`Page/StartPageSchemeHandler.swift`).
- **Chrome (`Chrome/`):** `index.html` and `base.css` (Luna look), `skins/*.css`, `js/main.js` (UI), `js/host.js` (bridge, plus `mock-host.js` for browser-only development), `js/overlay.js` (HTML menus and dialogs), `js/settings.js` (Dialup Options), `js/wizard.js` (first-run wizard).
- **Bridge:** `host.call(cmd, args)` goes to the host; the host sends `window.dialup.receive({event, data})` back. Documented in `docs/host-api.md`. Only the chrome's main frame on `dialup://` is accepted.
- **Overlay:** while a menu or dialog is open, the host raises the transparent chrome above the page, so menus never get clipped.
- **Pages:** a separate WebKit configuration with no bridge and no `dialup://`. The only extras are a hover-link script and the Dial-up Mode script, both in isolated content worlds, plus `dialup-start://` (static start page; personal config only for the start page itself).
- **Single sources of truth:** presets, speeds, the picture cap, default links, skins and search engines all live in Swift and reach JS through `prefs.catalog`.

## Done

- Test build; custom title bar; skins Luna (default) and Aqua; retro HTML menus and dialogs; Dialup Options; first-run Setup Wizard; retro start page.
- Dial-up Mode: image trickle-in with "(n items remaining)", dial-in sequence, 256-colour images, faint CRT, old fonts, page touches (safe ones on, risky ones opt-in), hard-mode whole-page filters.
- Review round 1 fixes: detached images, start-page privacy and Customize lock, stale status, settings and wizard only send changed keys, address bar dirtiness, dialog key stack and focus trap, lifecycle, debug-only flags.

## Next

1. **Authenticity pass (from the UI review):**
   - Luna: in-window menu bar (File/Edit/View/Favorites/Tools/Help), blue window frame, bigger toolbar, frame-based throbber, address combo arrow, Links bar.
   - Aqua: one-row Safari-style toolbar with charcoal icons and a search field, bookmarks bar, Mac button order, preferences toolbar.
   - Both: retro dropdowns and tooltips, era menu animations, status bar sequence, HTTPS padlock with a certificate dialog, original synthesized sounds, a modal-miss flash, a portal-style start page.
2. **Tabs, with a choice:** a `tabs` preference asked in the Setup Wizard ("Tabs, like Firefox 1.0" or "One page per window, like 2001") and in Settings → General. With tabs off, ⌘T and target=_blank open cascading windows and the tab strip is hidden. The tab strip is styled per skin. Session restore.
3. **Wayback button:** reload the current page from web.archive.org at a chosen year.
4. **Classic (98/2000) skin**, later Platinum and a Communicator-style skin.
5. **Favorites:** menu, Add to Favorites, organize, bookmarks.html import and export.
6. **Later:** toolbar plugins (`Toolbars/<id>/manifest.json`, sandboxed iframes with a permission gate), Explorer-style sidebars, downloads, find, zoom, real throttling proxy, pop-up blocker, WKWebExtension.
