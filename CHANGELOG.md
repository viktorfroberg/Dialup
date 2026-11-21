# Changelog

Milestones so far, oldest first. Version 0.1.0, not released yet.

## 0.1.0 (in development)

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

### Start page
- Retro start page and a portal-style page.
- Redesigned as a hand-made 800×600 home page on a desktop wallpaper, with a webring and 88×31 buttons. Each skin gives it its own personality.

### Browsing
- First-run Setup Wizard.
- Tabs, or one page per window, chosen in the wizard and in settings. Session restore with lazily loaded tabs. Popups open as tabs or cascading windows.
- Wayback button, Favorites menu, Add to Favorites, Links bar, `bookmarks.html` import and export.

### Privacy and security
- Review fixes: the start page's personal config is only served to the start page, settings and the wizard send only changed keys, dialog focus trap, debug-only flags.
- Groundwork for add-ons: the scheme handler resolves symlinks before its folder check (tested), and the browser UI has a strict Content-Security-Policy.
- Proposal for user skins, toolbars and add-ons: [docs/EXTENDING-PROPOSAL.md](docs/EXTENDING-PROPOSAL.md).
