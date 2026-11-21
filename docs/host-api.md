# Host API (v1)

The chrome UI (`Chrome/`) talks to the native host through `js/host.js`.

```js
import { host, onEvent } from './host.js';
await host.call('navigate', { input: 'example.com' });
onEvent('tab', (state) => { /* … */ });
```

Only the chrome's **main frame** on a `dialup://` origin can call the host. Iframes (future toolbar plugins) are rejected and must go through the chrome.

## Commands (chrome → host)

| cmd | args | returns |
|---|---|---|
| `ready` | – | `{ apiVersion, tab, window, dialupMode, prefs }`. Call once at startup; events only flow after this |
| `setInsets` | `{ top, left, right, bottom }` CSS px | – positions the page view |
| `navigate` | `{ input }` URL, bare host or search text | – |
| `back` / `forward` / `reload` / `stop` / `home` | – | – |
| `focusPage` | – | – gives keyboard focus to the page |
| `history` | `{ direction: 'back' \| 'forward' }` | `[{ offset, title, url }]` (max 15) |
| `goHistory` | `{ offset }` negative = back | – |
| `windowClose` / `windowMinimize` / `windowZoom` | – | – (custom title bar buttons) |
| `windowDrag` | – | – call on mousedown in an empty title bar area |
| `titlebarDoubleClick` | – | – zoom/minimize per the macOS setting |
| `dialupModeGet` | – | dial-up mode settings `{ enabled, connection, colors, resolution, scanlines, oldFonts, includeChrome }` |
| `dialupModeSet` | any subset of the settings | – applies to all windows |
| `dialupModePreset` | `{ id: '1998' \| '2003' }` | – |
| `prefsGet` | – | preferences `{ skin, homePage, searchEngine, name, quickLinks, catalog }` |
| `prefsSet` | any subset of the preferences | – validated and applied to all windows |
| `overlay` | `{ open }` | – raises the transparent chrome above the page while a menu/dialog is open (see `js/overlay.js`) |
| `clearData` | `{ what: 'cache' \| 'all' }` | – clears website data |
| `log` | `{ message }` | – writes to the app log |
| `popupMenu` | `{ items: [{ id, title, enabled?, checked?, separator?, items? }], x, y }` (`items` = submenu) | picked `id` or `null` (native NSMenu, so it never gets clipped) |

## Events (host → chrome)

| event | data |
|---|---|
| `tab` | `{ url, title, loading, progress, canGoBack, canGoForward, statusText, items }`. `items` = `{ remaining, total, url }` while dial-up mode trickles in images, else null |
| `hoverLink` | `{ url }` (empty string when leaving a link) |
| `focusAddress` | – sent on ⌘L |
| `windowState` | `{ key, zoomed, fullscreen }`. The chrome sets body classes `inactive`, `zoomed`, `fullscreen` |
| `prefs` | preferences (same shape as `prefsGet`). The chrome swaps `skins/<skin>.css` |
| `openSettings` | `{ tab }`. Sent on ⌘, and from the start page's Customize link |
| `dialupMode` | dial-up mode settings. The chrome sets body class `dialup-mode` |

## Keyboard

All shortcuts are native menu items (`Host/App/MainMenu.swift`). The chrome must not bind global key handlers. That's what keeps typing in a page from triggering chrome actions.

## Menus and dialogs

`js/overlay.js` draws menus (`showMenu(items, x, y)`) and dialogs (`openDialog({...})`) in HTML, so skins can style them. While one is open, the chrome calls `overlay {open:true}`. The host then moves the transparent chrome web view above the page, so menus can cover the page without being clipped. The native `popupMenu` command is still available.

## Start page

`Start/` is served to *page* web views as `dialup-start://home/`. It's static files plus a generated `config.js` (name, quick links, search engine), with no bridge. It shows as `about:home` in the address bar. Its Customize link (`dialup-start://home/customize`) is intercepted by the tab and opens settings.
