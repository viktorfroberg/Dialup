# Proposal: customizing and extending Dialup

Status: proposal. It's grounded in the code as of 2026-11 and follows on from PLAN.md "Next" items 1, 4 and 5. Part of phase 0 has since landed: the symlink-safe `resolve` (with a test) and the chrome CSP, so those two gaps below are closed.

**Summary.** Dialup's best feature for extension is one most browsers lack: the whole UI is CSS. So let people share **data first and code later**. Skins, sounds, presets, search engines and start themes are files that can't run code, so they carry little risk and give a lot back. Toolbars are next: sandboxed iframes in rebar bands with a small API that you have to ask permission for. Page scripts and real WebExtensions stay opt-in and come last. Every add-on type is a folder under `~/Library/Application Support/Dialup/`, and all of them are managed from one Add-ons tab.

---

## 1. Who customizes what

| Persona | Who | Wants | Won't do |
|---|---|---|---|
| **The Nostalgic Browser** | Downloads it for fun and maybe uses it daily for an hour | Pick a skin, turn on dial-up sounds, a cute start page, their search engine, one-click "make it 1998" | Open a folder, edit JSON, read a permission list longer than three lines |
| **The Themer** | Made Winamp skins or a Neocities page, knows CSS | Make "Luna Olive", "Platinum" or "BeOS", see changes instantly, share the result, swap the icons and the throbber | Install Xcode |
| **The Toolbar Hacker** | A web developer with a weekend free | Rebuild the 2004 Google Toolbar: a band with a field and buttons that knows the current URL and calls an API | Learn a build system or Swift |
| **The Power User** | Uses it as their real browser | Ad blocking, fixing one site's ugly CSS, a password manager, sync with their other Mac | Give up security for retro looks |

The Nostalgic Browser sets the bar for user experience: installing anything should be a double-click and a confirmation. The Power User sets the bar for honesty: say plainly what Dialup won't do (sync, a password manager) instead of half-building it.

## 2. What exists today, and what's missing

**Already in place:**
- **The chrome is all CSS and HTML.** `Chrome/base.css` declares variables (`--face`, `--rebar-bg`, `--icon-back`…) and a documented class list in its header comment (`.rebar .band .gripper .tb .drop .address-box .throbber #statusbar .cell`). `Chrome/skins/aqua.css` shows that one CSS file can completely restyle the browser, down to caption buttons, menus and dialogs.
- **Skin switching is a single `href` swap.** `applyPrefs` in `Chrome/js/main.js` sets `skins/${skin}.css` and `body[data-skin]`.
- **The scheme handler already supports user folders.** `DialupSchemeHandler` takes `roots: [area: [URL]]`, searched in order, "user folder first", and its comment already mentions `"skins"` and `"toolbars"` areas. Only `bundled()` with `chrome` is wired up so far.
- **The bridge is ready for iframes.** `ChromeBridge.accepts` only accepts the chrome's main frame on `dialup:`, and the test `testBridgeOnlyAcceptsChromeMainFrame` enforces it. host-api.md already says plugin iframes must go through the chrome.
- **Settings decoding is tolerant.** `Preferences.merging` / `DialupModeSettings.merging` drop unknown keys and fall back on bad values, which is exactly what you want for import.
- **Isolated content worlds are already in use.** `PageConfiguration` (`dialup-hover`) and `DialupModePage` (`dialup-mode`) both run in them, and `DialupModePage.apply` keeps any user scripts that aren't its own. User styles can reuse this.
- **Deployment target is macOS 15.4** (`project.yml`), so `WKWebExtension` is available without raising it.

**Gaps:**
- **Skins, search engines and presets are hard-coded.** `Preferences.skins` and `Preferences.searchEngines` are static arrays, and `sanitize()` resets any unknown id, so a user skin would be silently reset to Luna. `DialupModeSettings.presets` has only `1998` and `2003`.
- **Skin previews are hard-coded** in `base.css` (`.skin-luna .mini-titlebar` and friends) and in `wizard.js` (three fixed cards). The page scrollbar CSS in `DialupMode.swift` is keyed by skin id (`SCROLLBARS[skin] || SCROLLBARS.luna`).
- **The chrome has no CSP** (`Chrome/index.html`). Today that's fine because everything is first-party, but it has to be fixed before a third-party CSS file goes into that document.
- **Possible symlink escape.** `DialupSchemeHandler.resolve` checks `standardizedFileURL`, which doesn't resolve symlinks. A downloaded add-on folder containing `secret -> ~/.ssh/id_ed25519` passes the prefix check. That's harmless for bundled files but a real hole once user folders exist and toolbars can `fetch()` their own files.
- **The rebar is static markup** in `index.html`, with no drag, no layout persistence and no slot for extra bands.
- **Sounds can't be replaced.** `SoundEffects` synthesizes all five sounds (`click, complete, error, ding, modem`) and has no override hook.
- **Theme files would leak.** The start page is bundle-only, and `StartPageSchemeHandler` serves its static files to any page. That's fine for the stock files but would become a fingerprinting leak ("this visitor has theme X") once user themes exist. Only `config.js` is locked to the start page today.
- **No import/export** for anything except bookmarks.

## 3. Proposed extension points

### 3.0 Shared foundation (do this first)

On disk:
```
~/Library/Application Support/Dialup/
  Skins/<id>/          Toolbars/<id>/        Sounds/<id>/
  StartThemes/<id>/    Presets/*.dialuppreset
  UserStyles/*.user.css   UserScripts/*.user.js
  AddonData/<id>/storage.json        # toolbar storage, host-owned
  addons.json                        # enabled, granted permissions, installed version
```
- **`AddonRegistry` (Swift, new, `Host/Addons/`).** Scans the folders at launch and on change (FSEvents), validates manifests and feeds `Preferences.catalog`. `catalog.skins` gets user entries with `"user": true`, and `sanitize()` checks the registry instead of the static array.
- **`DialupSchemeHandler.bundled()`** becomes `roots: ["chrome": [bundle], "skins": [bundle/skins, user/Skins], "toolbars": [user/Toolbars], "sdk": [bundle/sdk]]`. `resolve` switches to `resolvingSymlinksInPath()` for both the root and the candidate. Add a test next to `testRefusesTraversalAndUnknownAreas`.
- **`.dialupaddon` = zip of one add-on folder.** Register the UTType in the Info.plist so a double-click opens Dialup. Dialup unzips into a temp folder, **rejects symlinks, absolute paths and files over 5 MB**, shows a retro confirmation dialog through `overlay.js`, then moves the folder into place.
- **An "Add-ons" tab in Dialup Options** (`settings.js` `tabs` array). Sections for Skins, Toolbars, Sounds, Start Page, Page Styles & Scripts. Each row has a toggle, Remove, "Show in Finder" and Permissions… Footer buttons: **Get more…** (the gallery, §4), **Install from file…**, **Open Add-ons Folder**.
- **New host commands:** `addonsList`, `addonSetEnabled {id, enabled}`, `addonRemove {id}`, `addonInstall` (native open panel), `addonReveal {id}`. New events: `addons` (registry changed) and `skinReloaded {id}`.
- **Chrome CSP** in `index.html`:
  ```html
  <meta http-equiv="Content-Security-Policy" content="default-src dialup:; script-src dialup://chrome;
    style-src dialup: 'unsafe-inline'; img-src dialup: data:; font-src dialup:; frame-src dialup://toolbars;
    connect-src 'none'">
  ```
  With this, skin CSS can't beacon out with `url(https://…)` or `@import`, and no script outside `Chrome/` can run in the trusted document.

### 3.1 User skins

**What a user sees.** Double-click `luna-olive.dialupaddon` (or drop the folder into `Skins/`). Appearance shows a new card. Clicking a card applies it live, and Cancel reverts. That needs a small change in `settings.js`: swap `#skin-css` on radio change and restore the baseline on cancel.

**Format:**
```
Skins/luna-olive/
  skin.json  skin.css  preview.png (240×160, optional)  img/throbber.svg …
```
```json
{
  "id": "luna-olive", "name": "Luna Olive", "version": "1.0.0", "author": "jane",
  "skinApi": 1,
  "base": "luna",
  "platform": "windows",
  "pageScrollbars": "luna",
  "preview": "preview.png"
}
```
- **`base` is the most valuable field.** The chrome loads the built-in skin first, then the user CSS: `<link id="skin-base">` plus `<link id="skin-css" href="dialup://skins/luna-olive/skin.css">`. "Luna but green" becomes 15 lines of CSS:
  ```css
  :root { --rebar-bg: linear-gradient(#f4f6e8, #dfe5c4); --titlebar-bg: linear-gradient(#a8b878, #7d8f4a); }
  .throbber { background-image: url(img/throbber.svg); }  /* relative to the skin folder */
  ```
- **`platform`** documents the menu bar decision. For `mac`, `#band-menu` is hidden, as `aqua.css` does today. It's also what the wizard uses to group skins.
- **`pageScrollbars`** picks one of the existing `SCROLLBARS` entries in `DialupMode.swift` instead of keying on the skin id.

**Skin API v1 (a stable contract, published as `docs/skin-api.md`):**
- every `--*` variable declared in `base.css :root`
- the element IDs in `index.html` (`#titlebar`, `#band-*`, `#statusbar`, `#tabstrip`, …)
- the documented classes
- the body state classes (`inactive`, `zoomed`, `fullscreen`, `dialup-mode`) and `data-skin`
- the overlay/menu/dialog classes from `overlay.js`

Rules: within v1, names are only ever added, never renamed. A rename bumps `skinApi`, and v1 skins keep loading through a tiny alias stylesheet. A skin that declares a newer `skinApi` than the app supports gets a warning: "made for a newer Dialup".

**Hot reload for authors.** `AddonRegistry` watches the *active* skin's folder. On change it emits `skinReloaded`, and the chrome sets `href = …/skin.css?t=<now>`. `Cache-Control: no-cache` is already sent. Combined with the existing Web Inspector, authors can edit in an editor and see changes on save. For quick iteration without the app, the existing `mock-host.js` workflow can accept `?skin=path/to/folder`.

**Security.** CSS only, no JS, enforced by CSP. A skin **can** fake the padlock or hide the address bar. We accept that and say so in the install dialog ("Skins change everything you see, including the security padlock. Install skins from people you trust."). Gallery review (§4) is the mitigation. Making security UI skin-proof would cost too much of the "everything is CSS" charm.

### 3.2 Toolbar add-ons ("toolbars")

This is the headline add-on type, and the feature people remember from 2004: Google Toolbar, Alexa, Yahoo Companion.

**What a user sees.** Install, then confirm a dialog in plain language:
> **Babel Bar** would like to:
> • see the address of the page you're viewing
> • read text you've selected, when you click its button
> • talk to api.mymemory.translated.net
> [Cancel] [Add Toolbar]

The toolbar shows up as a new rebar band. View → Toolbars lists every band with a checkmark (IE6-style). Bands can be dragged by their gripper, and **Lock the Toolbars** freezes them.

**Format:**
```json
{
  "id": "babel-bar", "name": "Babel Bar", "version": "0.3.0", "type": "toolbar",
  "dialupApi": 1,
  "entry": "band.html",
  "band": { "minWidth": 220, "height": 24, "row": "new" },
  "permissions": ["page.url", "page.selection", "navigate", "storage", "popup"],
  "network": ["https://api.mymemory.translated.net"]
}
```

**How it runs.**
- The chrome renders each band as `<iframe sandbox="allow-scripts allow-forms" src="dialup://toolbars/babel-bar/band.html">`. Without `allow-same-origin` the frame gets an opaque origin, so it has no access to the chrome DOM, `localStorage` or cookies. `ChromeBridge` already rejects it (it's not the main frame).
- The scheme handler sends a per-add-on CSP header built from the manifest: `default-src dialup://toolbars/babel-bar/ dialup://sdk/; connect-src https://api.mymemory.translated.net; img-src … data:; form-action 'none'`. No remote `script-src`, ever: everything that runs ships in the folder, so a reviewed toolbar can't change under you.
- `Chrome/js/addons.js` (new) is the broker. It owns each iframe, checks `event.source === frame.contentWindow`, matches the method against the granted permissions and rate-limits calls. It only ever maps calls onto a **fixed** set of host commands. It never forwards a raw `host.call`.

**API.** The toolbar loads `dialup://sdk/addon-v1.js`, a roughly 60-line postMessage RPC shim:
```js
import { connect } from 'dialup://sdk/addon-v1.js';
const dialup = await connect();               // handshake, returns granted permissions

dialup.page.get();                 // {url, title, secure}             page.url
dialup.on('page', fn);             // fires on navigation               page.url
await dialup.page.selection();     // string, max 4 KB                  page.selection
dialup.navigate(url, { newTab });  // http(s) only                      navigate
await dialup.storage.get(k); dialup.storage.set(k, v);  // 100 KB/add-on storage
dialup.ui.status('Translated!');   // status bar text, 3 s              (always)
dialup.ui.popup({ entry: 'panel.html', width: 320, height: 240 });  // popup
dialup.ui.menu(items, x, y);       // retro menu via overlay.js         (always)
dialup.theme();                    // a few skin colors/fonts, so bands match the skin
```
- `page.selection` is answered by a one-shot script that the **host** evaluates in a new isolated world (`dialup-addons`) on the active tab, only after a click inside the band (user activation is forwarded by the broker). The toolbar never runs code in the page.
- `storage` is stored by the host in `AddonData/<id>/storage.json` through new host commands `addonStorageGet/Set`. The chrome's data store is `.nonPersistent()`, and the frame is opaque anyway, so web storage isn't an option.
- `popup` opens the add-on's second page in an `overlay.js` dialog frame. It uses the same sandbox and the same broker.

**Can never get:** the page DOM, cookies, history, other tabs, preferences, other add-ons, the file system, or `dialup://chrome`. If a toolbar needs the page DOM, it should be a WebExtension (§3.8).

**Architecture changes.** `index.html` bands become data-driven: built-in bands stay in the markup, and add-on bands are appended. A new pref, `toolbarLayout: [{band, row, width, hidden}]`, is validated in `Preferences.sanitize`. `reportInsets()` already re-measures through `ResizeObserver`, so the page view follows extra rows for free.

**Bundled samples** (they double as documentation):
- **Site Notes**: a per-URL sticky note (`page.url`, `storage`, no network).
- **Wayback Lookup**: "this page first archived: 1998" (`page.url`, network to `archive.org/wayback/available`). It sits next to the existing `wayback` command.
- **Babel Bar**: translates the selection.
- **Weather**: "Forecast: 100% chance of busy signal". No permissions, which makes it the hello-world.

### 3.3 Page styles and page scripts

**User styles (yes, phase 4).** Drop `UserStyles/hn-bigger.user.css` into the folder:
```css
/* ==UserStyle==
@name   HN, readable
@match  https://news.ycombinator.com/*
==/UserStyle== */
body { font-size: 14px !important; }
```
The host compiles enabled styles into one `WKUserScript` in a `dialup-userstyles` content world. The script checks `@match` against `location` and attaches a `<style>`, the same way `DialupModePage` already attaches `dialup-mode-style`. WebKit has no public per-URL user stylesheet API, so self-matching is the honest approach. The Add-ons tab also gets "Edit style for this site…", which opens a small dialog with a textarea. That's the Stylus experience without Stylus. Risk: the CSS sees the page but can't read it, apart from CSS exfiltration through `url()` on attribute selectors, which matters only for styles from strangers. Gallery styles get flagged if they contain remote `url()`.

**User scripts (yes, but gated).** User scripts are code with **full power over every site they match**, including password fields. Rules:
- Off unless **Developer Mode** is turned on in the Add-ons tab, with an explanation.
- `@match` is required and shown at install ("can read and change: news.ycombinator.com").
- Each script runs in **its own** named `WKContentWorld` (`userscript-<id>`), so page JavaScript can't see or tamper with it, and scripts can't see each other.
- No message handler at all in v1: no `GM_xmlhttpRequest` and no bridge. Scripts can only do what the page itself could do.
- Not distributed through the gallery. Point people to Greasy Fork and make them choose deliberately.

### 3.4 Start page themes and widgets

**Themes (phase 2):** `StartThemes/<id>/theme.json` + `theme.css` + images, applied on top of `start.css`/`portal.css`. Picked in Settings → Start Page. They're served under `dialup-start://home/themes/<id>/…`, **but only when `mainDocumentURL` is the start page**. That's the same check `allowsConfig` already does for `config.js`, so websites can't probe which themes you have installed.

**Widgets (later, maybe never):** sandboxed iframes inside the start page (a hit counter, a tip of the day, a webring). The start page already has no bridge, so the risk is low. But each widget brings its own CSP and review burden for small payoff. Ship two built-in widgets first and see whether anyone asks for more.

### 3.5 Dial-up Mode presets

Presets are just `DialupModeSettings`: enums and booleans. Sharing them is risk-free because `merging()` drops anything unknown.
```json
{ "dialupPreset": 1, "name": "AOL 3.0 at Grandma's", "settings":
  { "enabled": true, "connection": "modem56k", "colors": "websafeDither", "resolution": "chunky",
    "scanlines": true, "oldFonts": true, "underlineLinks": true } }
```
The Dial-up Mode tab gets **Save as Preset…**, **Copy Share Code** and **Paste Share Code**. A share code is `dialup-preset:` plus base64 JSON, small enough to paste into a forum post. User presets land in `Presets/` and show up in the `drop-dialup-mode` menu next to 1998 and 2003. `catalog.dialupPresets` becomes the built-in presets plus the user's.

### 3.6 Sound packs

```json
{ "id": "win98-ish", "name": "Desktop '98", "version": "1.0.0", "type": "sounds",
  "sounds": { "click": "click.wav", "complete": "done.m4a", "modem": "handshake.m4a" } }
```
Any sound that isn't listed falls back to the synthesized one. In `SoundEffects.buffer(for:)`, check the active pack first, then decode with `AVAudioFile` into the same cached `AVAudioPCMBuffer` path. Limits: 3 s per UI sound, 45 s for modem, 5 MB per pack. Licensing note in the docs and gallery rules: **no ripped OS sounds**, only original or CC-licensed recordings.

### 3.7 Search engines, and profile import/export

**Search engines.** Add a pref `customEngines: [{id, name, template, keyword?}]`. `sanitize()` requires `https` and exactly one `%s`, and checks against built-in plus custom ids. Two ways to add one:
- Settings → General → **Add…** with a name and URL template.
- **OpenSearch discovery.** Extend the `dialup-hover` script so it also reports `<link rel="search" type="application/opensearchdescription+xml">`. The search box then shows a glowing "+" (the Firefox 2 look). On click, the host fetches and parses the XML (a `text/html` `Url` template only) and asks for confirmation.

Keywords (`w spacejam` searches Wikipedia) go in `AddressResolver`. That's small and a big win for power users.

**Profile import/export.** File → Export Settings… writes `MyDialup.dialupprofile`:
```json
{ "dialupProfile": 1, "exported": "2026-11-21",
  "prefs": { "skin": "luna-olive", "searchEngine": "duckduckgo", "customEngines": [], "quickLinks": [] },
  "dialupMode": { "enabled": false, "connection": "modem56k" },
  "sounds": { "enabled": true, "pack": "win98-ish" },
  "addons": [{ "id": "luna-olive", "version": "1.0.0", "source": "gallery" }] }
```
- It contains **references** to add-ons, not their code. Import offers to fetch the missing ones from the gallery.
- No cookies, history or website data, ever.
- Import goes straight through the existing tolerant `merging()` decoders.

This is also "sync" for hobbyists: put the file in iCloud Drive.

### 3.8 Real WebExtensions (WKWebExtension)

**When it's worth it:** when the Power User wants things our add-ons deliberately can't do, such as page-DOM extensions (uBlock Origin Lite, SponsorBlock, Stylus or Violentmonkey if you'd rather not maintain §3.3). The deployment target is already 15.4.

**Cost (L):**
- a `WKWebExtensionController` attached to `PageConfiguration`
- `WKWebExtensionTab`/`WKWebExtensionWindow` conformance on `Tab` and `BrowserWindowController`
- action buttons rendered as chrome toolbar buttons, plus a popover for action popups
- permission prompts and storage
- an ongoing compatibility tail

The page boundary still holds: extensions run in WebKit's own extension contexts, not through `ChromeBridge`. Password managers are the usual request and won't work as users expect, so don't promise them.

**Recommendation:** do it last, as "Experimental: load unpacked MV3 folder". Cover the main reason people want extensions (blocking ads) earlier with built-in `WKContentRuleList` blocking, which is native, fast and S–M effort. Keep the custom toolbar system anyway. Persistent inline rebar bands aren't a WebExtension concept, and they're the retro charm. The rule between the two: **toolbars never touch the page DOM, and WebExtensions never draw rebar bands.**

## 4. Distribution: the Dialup Add-on Gallery

Keep it hobby-sized: **one public GitHub repo plus GitHub Pages, no server and no accounts.**

- `dialup-addons/` holds one folder per add-on. Authors open a PR, and the owner reviews it (it's a hobby; a review is reading 50 lines of CSS).
- A GitHub Action validates manifests, zips each add-on into `.dialupaddon`, computes its sha256, and writes `index.json`:
  ```json
  { "gallery": 1, "generated": "2026-11-21T10:00:00Z", "addons": [
    { "id": "luna-olive", "type": "skin", "name": "Luna Olive", "version": "1.0.0", "author": "jane",
      "preview": "luna-olive/preview.png", "url": "luna-olive-1.0.0.dialupaddon",
      "sha256": "9f2c…", "permissions": [] } ] }
  ```
- `index.json` is **signed with Ed25519** (minisign-style detached `index.json.sig`). The public key is compiled into the app, and verification takes about 10 lines with CryptoKit `Curve25519.Signing`. This protects against a hijacked Pages site or repo without needing per-author keys. Per-file sha256 values chain from the signed index.
- **In the app:** "Get more…" opens a retro gallery dialog that fetches the index **only when opened**. No background polling and no telemetry. Updates are checked at the same moment. A new version that asks for new permissions needs consent again.
- **Trust tiers, shown as badges:**
  - Data (skins, sounds, presets, start themes, engines): fast review.
  - Toolbars: code read, network hosts checked.
  - User styles: allowed if there are no remote `url()`s.
  - User scripts and WebExtensions: not hosted.
- **Kill switch:** the index can carry `"revoked": ["id@version"]`, and the app disables those on the next gallery open.
- **Manual install** of any `.dialupaddon` always works, with an "Unverified add-on" line in the confirmation dialog.

## 5. Roadmap

| Phase | What | Effort | Why now |
|---|---|---|---|
| **0. Foundation** | Symlink-safe `resolve` + test, chrome CSP, `AddonRegistry`, user roots, dynamic `catalog.skins` | S | Prerequisite; hardens what exists |
| **1. Make it yours (data only)** | User skins with `base` inheritance, live preview, hot reload, `skin-api.md`; custom search engines + keywords; preset share codes; profile export/import | M | Most value, no code execution |
| **2. Add-ons tab** | Settings tab, `.dialupaddon` double-click install, sound packs, start page themes | M | Non-developers can install things |
| **3. Toolbars** | Data-driven rebar, drag + Lock, View → Toolbars, SDK + broker, 4 bundled samples | L | The headline feature, on solid ground |
| **4. Pages** | `WKContentRuleList` blocking; user styles + "Edit style for this site"; user scripts behind Developer Mode | M | Power-user asks, kept sandboxed |
| **5. Gallery** | Repo + Action + signed index + in-app browser | M | Only once there are about 10 add-ons worth listing |
| **6. WebExtensions** | Experimental unpacked MV3 | L | Only if users ask after phase 4 |

**Build first:** phase 0 plus user skins with `base` inheritance and hot reload. A day or two of work turns "Skins are plain CSS files in `Chrome/skins/`" (the current hint in `settings.js`, which points into the app bundle) into something real.

### Things we should NOT do

- **No JS in skins, and no HTML templates in skins.** CSS-only keeps `index.html` a stable contract and the trusted document trusted.
- **No add-on access to `host.call`, not even "read-only".** The broker maps a fixed menu, and new capabilities mean new named permissions.
- **No remote code.** No toolbar that is just an `https://` URL, and no remote `script-src`. Reviewed code must equal running code.
- **No build step, npm, or SDK package** for add-on authors. One folder, one JSON file, done.
- **No background update checks or telemetry**, no accounts, no ratings or comments in the gallery.
- **Don't write our own ad-block engine or reimplement `chrome.*` APIs** in the custom system.
- **Don't promise sync or password managers.** Export files and iCloud Drive are the honest answer.

### Open questions for the owner

1. Will you personally review gallery PRs? If not, should the gallery list data add-ons only?
2. Is it OK that skins can fake the padlock, given the warning plus review? Or should the status-bar security cell be drawn in a host-protected layer?
3. Spike needed: does WebKit honor a `Content-Security-Policy` **response header** from a `WKURLSchemeHandler` for sandboxed iframes? If not, inject a `<meta>` CSP when serving `band.html`, and reject add-on HTML that tries to override it.
4. Should user scripts ship at all, or should we wait for WebExtensions and recommend Violentmonkey?
5. Should manifests support localized names now (`"name": {"en": …, "sv": …}`), or wait?
6. Is "Developer Mode" also where "Load unpacked add-on from folder…" (symlink-free, path stored in prefs) lives? (Recommendation: yes.)
