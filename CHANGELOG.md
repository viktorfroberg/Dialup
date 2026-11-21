# Changelog

Milestones so far, oldest first.

## 0.1.0 (2026-11-21)

First public release.

### Foundations
- Test build: an HTML/CSS/JS browser UI in one WKWebView, the web page in another, a Swift host in between. Address bar, Back/Forward with history dropdowns, throbber, status bar.
- Renamed to Dialup. The title bar is drawn by the UI, not by macOS.

### Dial-up Mode
- First version as "extreme mode", then reworked and renamed Dial-up Mode, with the focus on how loading feels. Pictures trickle in at modem speed, the status bar shows "(n items remaining)", and there's a dial-in sequence, 256-colour pictures, faint CRT scanlines and old fonts.
- Hard mode: whole-page 16-bit, web-safe and dithered colours.
- Retro page touches: classic scrollbars, square corners, and opt-in no shadows / no animations / underlined links.

### Look and feel
- Retro HTML menus and dialogs that skins can style. Dialup Options (⌘,) with visual previews.
- Aqua skin (Mac OS X, 2003) next to Luna (Windows XP, 2001), then the Classic skin (Windows 98/2000).
- Authenticity pass: Luna menu bar, frame, throbber and Links bar; Safari-style Aqua toolbar, bookmarks bar and search field; retro dropdowns and tooltips; padlock and certificate dialog; original synthesized sounds.
- Window corners drawn by the skin, no native frame.
- Address bar dropdown as a full-width combo list, like IE.
- Icons from the Tango Icon Library (public domain). The app icon is the Tango globe on a tile in each skin's colours, and the Dock icon follows the skin.
- Proper XP and Classic page scrollbars; live skin preview in Settings; calmer default colours.

### Start page
- Retro start page and a portal-style page.
- Redesigned as a hand-made 800×600 home page on a desktop wallpaper, with a webring and 88×31 buttons. Each skin gives it its own personality.
- Redesigned again as a 2004 search engine front page: a wordmark, Web/Images/News/Wikipedia/Archive tabs, one big box and two buttons (one opens a random Wikipedia article). The portal is one click away.

### Browsing
- First-run Setup Wizard.
- Tabs, or one page per window, chosen in the wizard and in settings. Session restore with lazily loaded tabs. Popups open as tabs or cascading windows.
- Wayback button, Favorites menu, Add to Favorites, Links bar, `bookmarks.html` import and export.
- Browser basics: downloads to ~/Downloads (never overwriting), file uploads, `prompt()`, mailto: and other links handed to the system, zoom, print, find in page, and Dialup as the default browser.

### Privacy and security
- Review fixes: the start page's personal config is only served to the start page, settings and the wizard send only changed keys, dialog focus trap, debug-only flags.
- Groundwork for add-ons: the scheme handler resolves symlinks before its folder check (tested), and the browser UI has a strict Content-Security-Policy.
- Proposal for user skins, toolbars and add-ons: [docs/EXTENDING-PROPOSAL.md](docs/EXTENDING-PROPOSAL.md).
- Ad and tracker blocking with WebKit's native content rule lists, on by default.
- MIT license.

### Under the hood
- Swift refactor: the chrome's commands are parsed once into a typed `HostCommand` (unknown or malformed calls are logged and ignored; `clearData` with an unknown kind no longer clears everything); tab order lives in a unit-tested `TabList`; the browser window is split into state, host commands and menu actions; both settings models share one tolerant-decoding protocol, with skins and search engines as enums and connection speeds from one place.
- The Dial-up Mode page script is a bundled `page-script.js` instead of a Swift string. Bookmark panels and ad-blocker compilation use async/await; the compiled rule list is reused across launches.
- Debug overrides (`-HomePage`) only exist in debug builds, and the app opens no windows while hosting the unit tests. Tests are split per area (82, up from 33), and GitHub Actions builds and tests every push.
