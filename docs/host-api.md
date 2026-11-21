# Host API (v1)

The chrome UI (`Chrome/`) talks to the native host through `js/host.js`.

```js
import { host, onEvent } from './host.js';
await host.call('navigate', { input: 'example.com' });
onEvent('tab', (state) => { /* … */ });
```

Only the chrome's **main frame** on a `kikare://` origin can call the host. Iframes (future toolbar plugins) are rejected and must go through the chrome.

## Commands (chrome → host)

| cmd | args | returns |
|---|---|---|
| `ready` | – | `{ apiVersion, tab }`. Call once at startup; events only flow after this |
| `setInsets` | `{ top, left, right, bottom }` CSS px | – positions the page view |
| `navigate` | `{ input }` URL, bare host or search text | – |
| `back` / `forward` / `reload` / `stop` / `home` | – | – |
| `focusPage` | – | – gives keyboard focus to the page |
| `history` | `{ direction: 'back' \| 'forward' }` | `[{ offset, title, url }]` (max 15) |
| `goHistory` | `{ offset }` negative = back | – |
| `popupMenu` | `{ items: [{ id, title, enabled?, separator? }], x, y }` | picked `id` or `null` (native NSMenu, so it never gets clipped) |

## Events (host → chrome)

| event | data |
|---|---|
| `tab` | `{ url, title, loading, progress, canGoBack, canGoForward, statusText }` |
| `hoverLink` | `{ url }` (empty string when leaving a link) |
| `focusAddress` | – sent on ⌘L |

## Keyboard

All shortcuts are native menu items (`Host/App/MainMenu.swift`). The chrome must not bind global key handlers. That's what keeps typing in a page from triggering chrome actions.
