# Host API (v1)

The chrome UI (`Chrome/`) talks to the native host through `js/host.js`.

```js
import { host, onEvent } from './host.js';
await host.call('navigate', { input: 'example.com' });
onEvent('tab', (state) => { /* … */ });
```

Only the chrome's **main frame** on a `dialup://` origin can call the host. Iframes (future toolbar plugins) are rejected and must go through the chrome.

On the Swift side, `ChromeBridge` parses each call into a typed `HostCommand` (`Host/Bridge/HostCommand.swift`) and the window carries it out (`BrowserWindowController+HostCommands.swift`). An unknown command, or a missing or invalid required argument, is logged and ignored: the call resolves with `null`, nothing happens.

## Commands (chrome → host)

Arguments marked `?` are optional; the default is given where it matters.

| cmd | args | returns |
|---|---|---|
| `ready` | – | `{ apiVersion, tab, tabs, window, dialupMode, prefs, sounds }` (`sounds` is a boolean). Call once at startup; events only flow after this |
| `setInsets` | `{ top?, left?, right?, bottom? }` CSS px, missing sides = 0 | – positions the page view |
| `navigate` | `{ input }` URL, bare host, `about:home`, or search text | – searches go to the preferred engine |
| `back` / `forward` / `reload` / `stop` / `home` | – | – |
| `focusPage` | – | – gives keyboard focus to the page |
| `history` | `{ direction?: 'back' \| 'forward' }` (anything but `'forward'` = back) | `[{ offset, title, url }]` (max 15) |
| `goHistory` | `{ offset }` negative = back | – |
| `windowClose` / `windowMinimize` / `windowZoom` | – | – (custom title bar buttons) |
| `windowDrag` | – | – call on mousedown in an empty title bar area |
| `titlebarDoubleClick` | – | – zoom/minimize per the macOS setting |
| `dialupModeGet` | – | dial-up mode settings `{ enabled, connection, colors, resolution, scanlines, oldFonts, includeChrome, retroPage, squareCorners, noShadows, noAnimations, underlineLinks }` |
| `dialupModeSet` | any subset of the settings | – applies to all windows. Unknown keys and invalid values are ignored |
| `dialupModePreset` | `{ id: '1998' \| '2003' }` | – |
| `prefsGet` | – | preferences `{ skin, homePage, searchEngine, name, quickLinks, onboarded, tabs, restoreSession, blockAds, catalog }`. `quickLinks` are the favorites (`[{ title, url }]`). `catalog` is the single source for lists and constants: `skins` and `searchEngines` (`[{ id, name }]`), `defaultLinks`, `dialupPresets`, `connectionSpeeds` (`{ <connection>: bitsPerSecond }`), `pictureCapMs`, `maxFavorites` |
| `prefsSet` | any subset of the preferences | – validated and applied to all windows. Unknown keys and invalid values are ignored |
| `overlay` | `{ open? }` default false | – raises the transparent chrome above the page while a menu/dialog is open (see `js/overlay.js`) |
| `clearData` | `{ what?: 'cache' \| 'all' }` default `'cache'` | – clears website data. Any other `what` clears nothing |
| `log` | `{ message }` | – writes to the app log (capped at 2000 characters) |
| `newTab` | `{ url? }` resolved like the address bar; default the home page | – a new tab at the end (or a new window when tabs are off) |
| `closeTab` / `selectTab` | `{ id }` (a `tabs[].id`) | – closing the last tab closes the window |
| `wayback` | `{ year }` 1996–2030 | – reloads the current page from web.archive.org around that year |
| `find` | `{ text, backwards?, caseSensitive? }` | – finds the next match in the page (wraps around). The result arrives as the `findResult` event |
| `importBookmarks` / `exportBookmarks` | – | – native open/save sheet; bookmarks.html format. Import result arrives as the `bookmarksImported` event |
| `menuAction` | `{ action }` one of `newWindow, performClose, cut, copy, paste, selectAll, toggleFullScreen` | – sent to the responder chain (from the chrome's own menu bar) |
| `search` | `{ query }` non-empty | – searches with the preferred engine |
| `securityInfo` | – | `{ host, secure, subject, issuer }` for HTTPS pages, else null |
| `sound` | `{ name: 'click' \| 'complete' \| 'error' \| 'ding' }` | – plays an original synthesized sound |
| `soundSet` | `{ enabled? }` default true | – app-wide; broadcast as the `sounds` event |
| `addFavorite` | `{ url, title? }` title defaults to the URL | – appends to the favorites unless the URL is already there or there are `maxFavorites` |
| `popupMenu` | `{ items: [{ id, title, enabled?, checked?, separator?, items? }], x, y }` (`items` = submenu, up to 3 levels) | picked `id` or `null` (native NSMenu, so it never gets clipped) |

## Events (host → chrome)

| event | data |
|---|---|
| `tab` | `{ id, url, title, secure, loading, progress, canGoBack, canGoForward, statusText, items }`. State updates are coalesced, and `url`/`title` are length-capped. `items` = `{ remaining, total, url }` while dial-up mode trickles in images, else null |
| `hoverLink` | `{ url }` (empty string when leaving a link) |
| `focusAddress` | – sent on ⌘L |
| `windowState` | `{ key, zoomed, fullscreen }`. The chrome sets body classes `inactive`, `zoomed`, `fullscreen` |
| `prefs` | preferences (same shape as `prefsGet`). The chrome swaps `skins/<skin>.css` |
| `openSettings` | `{ tab }`. Sent on ⌘, (`'general'`) and from the start page's Customize link (`'startpage'`, only when the start page itself asks) |
| `openWizard` | – sent from Help → Setup Wizard… |
| `sounds` | `{ enabled }` |
| `tabs` | `{ enabled, active, tabs: [{ id, title, loading }] }`. `active` is the active tab's `id` |
| `bookmarksImported` | `{ added, found }` |
| `dialupMode` | dial-up mode settings. The chrome sets body class `dialup-mode` |
| `download` | `{ name, fraction, state: 'downloading' \| 'done' \| 'failed', path }`. Downloads go to ~/Downloads and never overwrite (`file 2.zip`…) |
| `openFind` | – sent on ⌘F; the chrome shows its Find dialog |
| `findAgain` | `{ backwards }` – sent on ⌘G / ⇧⌘G |
| `findResult` | `{ found }` – the answer to `find` |
| `addFavorite` | – sent on ⌘D; the chrome shows its Add to Favorites dialog, which then calls `addFavorite` |

## Keyboard

All app shortcuts are native menu items (`Host/App/MainMenu.swift`). The chrome doesn't bind global shortcuts, so typing in a page never triggers chrome actions. The one exception: while a menu or dialog is open, `js/overlay.js` handles Esc/Enter/arrows/Tab for the topmost overlay only. The chrome has focus then.

## Menus and dialogs

`js/overlay.js` draws menus (`showMenu(items, x, y)`) and dialogs (`openDialog({...})`) in HTML, so skins can style them. While one is open, the chrome calls `overlay {open:true}`. The host then moves the transparent chrome web view above the page, so menus can cover the page without being clipped. The native `popupMenu` command is still available.

## Start page

`Start/` is served to *page* web views as `dialup-start://home/`. It's static files plus a generated `config.js` (name, favorites, search engine, skin), with no bridge. It shows as `about:home` in the address bar. Its Customize link (`dialup-start://home/customize`) is intercepted by the tab and opens settings. Both are locked to the start page: `config.js` returns an empty config unless the requesting document is the start page, and Customize only works when the start page navigates its own main frame.
