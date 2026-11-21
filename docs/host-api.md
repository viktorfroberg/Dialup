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
| `ready` | – | `{ apiVersion, tab, window, extreme }`. Call once at startup; events only flow after this |
| `setInsets` | `{ top, left, right, bottom }` CSS px | – positions the page view |
| `navigate` | `{ input }` URL, bare host or search text | – |
| `back` / `forward` / `reload` / `stop` / `home` | – | – |
| `focusPage` | – | – gives keyboard focus to the page |
| `history` | `{ direction: 'back' \| 'forward' }` | `[{ offset, title, url }]` (max 15) |
| `goHistory` | `{ offset }` negative = back | – |
| `windowClose` / `windowMinimize` / `windowZoom` | – | – (custom title bar buttons) |
| `windowDrag` | – | – call on mousedown in an empty title bar area |
| `titlebarDoubleClick` | – | – zoom/minimize per the macOS setting |
| `extremeGet` | – | extreme settings `{ enabled, colors, resolution, scanlines, oldFonts }` |
| `extremeSet` | any subset of the settings | – applies to all windows |
| `extremePreset` | `{ id: '1998' \| '2003' }` | – |
| `popupMenu` | `{ items: [{ id, title, enabled?, checked?, separator?, items? }], x, y }` (`items` = submenu) | picked `id` or `null` (native NSMenu, so it never gets clipped) |

## Events (host → chrome)

| event | data |
|---|---|
| `tab` | `{ url, title, loading, progress, canGoBack, canGoForward, statusText }` |
| `hoverLink` | `{ url }` (empty string when leaving a link) |
| `focusAddress` | – sent on ⌘L |
| `windowState` | `{ key, zoomed, fullscreen }`. The chrome sets body classes `inactive`, `zoomed`, `fullscreen` |
| `extreme` | extreme settings. The chrome sets body class `extreme` |

## Keyboard

All shortcuts are native menu items (`Host/App/MainMenu.swift`). The chrome must not bind global key handlers. That's what keeps typing in a page from triggering chrome actions.
