import AppKit
import WebKit

/// One browser window: a chrome web view (the HTML UI) plus one page web view per tab.
@MainActor
final class BrowserWindowController: NSWindowController, NSWindowDelegate, NSMenuItemValidation, WKNavigationDelegate {
    /// Home page from preferences. `-HomePage <url>` on the command line overrides it (debugging).
    static var homeURL: URL {
        UserDefaults.standard.string(forKey: "HomePage").flatMap(URL.init(string:))
            ?? PreferencesStore.shared.preferences.homeURL
    }
    static let chromeURL = URL(string: "dialup://chrome/index.html")!

    var onClose: (() -> Void)?
    /// Called when tabs or their URLs change, so the app can save the session.
    var onSessionChange: (() -> Void)?

    /// All open windows, so shared page handlers can find which window a web view belongs to.
    private static let all = NSHashTable<BrowserWindowController>.weakObjects()

    static func owner(of webView: WKWebView) -> BrowserWindowController? {
        all.allObjects.first { $0.tabs.contains { $0.webView === webView } }
    }

    private let layoutView = BrowserLayoutView()
    private let bridge = ChromeBridge()
    private let hoverHandler = HoverLinkHandler()
    private let dialupModePage = DialupModePage()
    private let chromeView: WKWebView
    private let pageConfiguration: WKWebViewConfiguration
    private(set) var tabs: [Tab] = []
    private var activeIndex = 0
    private var tab: Tab { tabs[activeIndex] }
    private var chromeReady = false
    private var observers: [NSObjectProtocol] = []

    /// - Parameters:
    ///   - urls: tabs to open (restored sessions load lazily); empty = the home page.
    ///   - popupConfiguration: for window.open with tabs off: the first tab must use WebKit's configuration.
    init(urls: [URL] = [], activeIndex: Int = 0, popupConfiguration: WKWebViewConfiguration? = nil) {
        let chromeConfig = ChromeConfiguration.make(bridge: bridge, schemeHandler: .bundled())
        chromeView = WKWebView(frame: .zero, configuration: chromeConfig)
        chromeView.isInspectable = true
        // Transparent, so when menus/dialogs raise the chrome above the page, the page shows through.
        chromeView.setValue(false, forKey: "drawsBackground")
        pageConfiguration = popupConfiguration
            ?? PageConfiguration.make(hoverHandler: hoverHandler, dialupModePage: dialupModePage)

        // A frameless, transparent window (see DialupWindow): the HTML chrome draws the title bar,
        // the buttons and the window corners. ⌘W/⌘M, Mission Control and resizing still work.
        let window = DialupWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 780))
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 520, height: 340)
        window.title = "Dialup"
        super.init(window: window)

        window.contentView = layoutView
        layoutView.chromeView = chromeView
        // New windows cascade from the current one; the first window remembers its frame.
        if let key = NSApp.keyWindow, Self.all.count > 0 {
            window.setFrame(key.frame, display: false)
            window.setFrameTopLeftPoint(window.cascadeTopLeft(from: NSPoint(x: key.frame.minX, y: key.frame.maxY)))
        } else {
            if !window.setFrameUsingName("DialupMain") { window.center() }
            window.setFrameAutosaveName("DialupMain")
        }
        Self.all.add(self)

        bridge.controller = self
        chromeView.navigationDelegate = self
        // These handlers belong to the page configuration, which a popup window may share with its
        // opener, so route by web view instead of capturing this window.
        hoverHandler.onHover = { webView, url in
            BrowserWindowController.owner(of: webView)?.hoverChanged(on: webView, url: url)
        }
        dialupModePage.onStatus = { webView, remaining, total, url in
            BrowserWindowController.owner(of: webView)?.tabs.first { $0.webView === webView }?
                .setItems(remaining: remaining, total: total, url: url)
        }

        if popupConfiguration != nil {
            _ = addTab(configuration: popupConfiguration, url: nil, select: true)
        } else if urls.isEmpty {
            _ = addTab(url: Self.homeURL, select: true)
        } else {
            for url in urls { _ = addTab(url: url, select: false, lazy: true) }
            selectTab(at: min(max(0, activeIndex), tabs.count - 1))
        }
        observers.append(NotificationCenter.default.addObserver(forName: PreferencesStore.didChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.preferencesDidChange() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: Self.soundsDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.emit("sounds", ["enabled": SoundEffects.shared.isEnabled]) }
        })
        observers.append(NotificationCenter.default.addObserver(forName: DialupMode.didChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.dialupModeDidChange() }
        })
        applyDialupMode()
        AdBlocker.apply(PreferencesStore.shared.preferences.blockAds, to: pageConfiguration.userContentController)
        window.delegate = self // only now: delegate callbacks assume at least one tab

        chromeView.load(URLRequest(url: Self.chromeURL))
        DebugSnapshot.scheduleIfRequested(chrome: chromeView, page: tab.webView, in: layoutView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    func windowWillClose(_ notification: Notification) {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        Self.all.remove(self)
        onClose?()
    }

    // MARK: Tabs

    private var tabsEnabled: Bool { PreferencesStore.shared.preferences.tabs }

    /// Creates a tab. `configuration` is only passed for WebKit-created popups.
    @discardableResult
    private func addTab(configuration: WKWebViewConfiguration? = nil, url: URL?, select: Bool, lazy: Bool = false) -> Tab {
        let tab = Tab(configuration: configuration ?? pageConfiguration, pendingURL: lazy ? url : nil)
        tab.onChange = { [weak self, weak tab] in
            guard let self, let tab else { return }
            self.tabDidChange(tab)
        }
        tab.onOpenSettings = { [weak self] section in self?.emit("openSettings", ["tab": section]) }
        tab.onCreateWebView = { [weak self] configuration, _ in self?.openPopup(configuration: configuration) }
        tab.onCloseRequest = { [weak self, weak tab] in
            guard let self, let tab, let index = self.tabs.firstIndex(where: { $0 === tab }) else { return }
            self.closeTab(at: index)
        }
        let insertAt = tabs.isEmpty ? 0 : activeIndex + 1
        tabs.insert(tab, at: insertAt)
        if !lazy, let url { tab.webView.load(URLRequest(url: url)) }
        if select { selectTab(at: insertAt) } else if insertAt <= activeIndex && tabs.count > 1 { activeIndex += 1 }
        emitTabs()
        return tab
    }

    /// target=_blank / window.open: a new tab, or (tabs off) a new cascading window.
    private func openPopup(configuration: WKWebViewConfiguration) -> WKWebView? {
        if tabsEnabled {
            return addTab(configuration: configuration, url: nil, select: true).webView
        }
        return (NSApp.delegate as? AppDelegate)?.openPopupWindow(configuration: configuration)
    }

    private func selectTab(at index: Int) {
        guard tabs.indices.contains(index) else { return }
        activeIndex = index
        let tab = tabs[index]
        tab.loadIfNeeded()
        layoutView.pageView = tab.webView
        applyDialupMode()
        tabDidChange(tab)
        emitTabs()
        if window?.firstResponder !== chromeView { focusPage() }
    }

    private func closeTab(at index: Int) {
        guard tabs.indices.contains(index) else { return }
        if tabs.count == 1 { window?.performClose(nil); return }
        let closing = tabs.remove(at: index)
        closing.webView.stopLoading()
        closing.webView.removeFromSuperview()
        if index < activeIndex || activeIndex >= tabs.count { activeIndex = max(0, activeIndex - 1) }
        selectTab(at: activeIndex)
    }

    private func tabIndex(_ args: [String: Any]) -> Int? {
        guard let id = (args["id"] as? NSNumber)?.intValue else { return nil }
        return tabs.firstIndex { $0.id == id }
    }

    private var tabsPayload: [String: Any] {
        [
            "enabled": tabsEnabled,
            "active": tab.id,
            "tabs": tabs.map { ["id": $0.id, "title": String($0.displayTitle.prefix(120)), "loading": $0.webView.isLoading] as [String: Any] },
        ]
    }

    private var lastTabsJSON = ""

    private func emitTabs() {
        guard !tabs.isEmpty else { return }
        let payload = tabsPayload
        let json = (try? JSONSerialization.data(withJSONObject: payload)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        guard json != lastTabsJSON else { return }
        lastTabsJSON = json
        emit("tabs", payload)
        onSessionChange?()
    }

    /// For session restore: this window's tab URLs and which one is active.
    var session: (urls: [URL], active: Int) {
        (tabs.compactMap(\.sessionURL), activeIndex)
    }

    private func hoverChanged(on webView: WKWebView, url: String) {
        guard webView === tab.webView else { return }
        emit("hoverLink", ["url": url])
    }

    private func applyDialupMode() {
        guard !tabs.isEmpty else { return }
        DialupModeRenderer.apply(DialupMode.shared.settings, to: layoutView, page: tab.webView,
                                 allPages: tabs.map(\.webView), pageScripts: dialupModePage)
    }

    // MARK: Window state → chrome (title bar look)

    private var lastWindowState: [String: Bool] = [:]

    private var windowState: [String: Bool] {
        guard let window else { return [:] }
        return [
            "key": window.isKeyWindow,
            "zoomed": window.isZoomed,
            "fullscreen": window.styleMask.contains(.fullScreen),
        ]
    }

    private func emitWindowState() {
        let state = windowState
        guard state != lastWindowState else { return }
        lastWindowState = state
        emit("windowState", state)
    }

    func windowDidBecomeKey(_ notification: Notification) { emitWindowState() }
    func windowDidResignKey(_ notification: Notification) { emitWindowState() }
    func windowDidEnterFullScreen(_ notification: Notification) { emitWindowState() }
    func windowDidExitFullScreen(_ notification: Notification) { emitWindowState() }
    func windowDidEndLiveResize(_ notification: Notification) { emitWindowState() }
    func windowDidResize(_ notification: Notification) {
        if !(window?.inLiveResize ?? false) { emitWindowState() }
    }
    func windowDidChangeBackingProperties(_ notification: Notification) { dialupModeDidChange() }

    /// Title bar double-click follows the user's macOS setting (Zoom / Minimize / nothing).
    private func titlebarDoubleClick() {
        switch UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") {
        case "Minimize": window?.performMiniaturize(nil)
        case "None": break
        default: window?.performZoom(nil)
        }
    }

    // MARK: Dial-up mode

    private func dialupModeDidChange() {
        applyDialupMode()
        emit("dialupMode", DialupMode.shared.settings.dictionary)
    }

    // MARK: Preferences

    private var preferencesPayload: [String: Any] {
        PreferencesStore.shared.preferences.dictionary.merging(["catalog": Preferences.catalog]) { a, _ in a }
    }

    private func preferencesDidChange() {
        emit("prefs", preferencesPayload)
        refreshShadow()
        applyDialupMode() // skin-specific scrollbars
        AdBlocker.apply(PreferencesStore.shared.preferences.blockAds, to: pageConfiguration.userContentController)
        for tab in tabs where tab.isShowingStartPage { tab.webView.reload() }
        emitTabs()
    }

    static let soundsDidChange = Notification.Name("DialupSoundsDidChange")

    /// A transparent window's shadow follows its painted shape; recompute it once the skin has drawn.
    private func refreshShadow() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.window?.invalidateShadow() }
    }

    /// Certificate summary for the padlock dialog.
    private func securityInfo() -> [String: Any]? {
        let webView = tab.webView
        guard let url = webView.url, url.scheme == "https" else { return nil }
        var info: [String: Any] = ["host": url.host ?? "", "secure": webView.hasOnlySecureContent]
        if let trust = webView.serverTrust,
           let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate] {
            if let leaf = chain.first { info["subject"] = SecCertificateCopySubjectSummary(leaf) as String? ?? "" }
            if chain.count > 1 { info["issuer"] = SecCertificateCopySubjectSummary(chain[1]) as String? ?? "" }
        }
        return info
    }

    // MARK: Overlay (retro menus and dialogs)

    private var responderBeforeOverlay: NSResponder?

    /// Menus and dialogs are drawn by the chrome. While one is open, the chrome sits above
    /// the page (its page area is transparent) and has keyboard focus.
    private func setOverlay(_ open: Bool) {
        guard layoutView.chromeOnTop != open, let window else { return }
        layoutView.chromeOnTop = open
        if open {
            responderBeforeOverlay = window.firstResponder
            window.makeFirstResponder(chromeView)
        } else {
            let previous = responderBeforeOverlay
            responderBeforeOverlay = nil
            if let view = previous as? NSView, view.window === window, view !== chromeView {
                window.makeFirstResponder(view)
            } else {
                focusPage()
            }
        }
    }

    private func clearData(_ what: String) {
        let types: Set<String> = switch what {
        case "cache": [WKWebsiteDataTypeDiskCache, WKWebsiteDataTypeMemoryCache, WKWebsiteDataTypeFetchCache]
        default: WKWebsiteDataStore.allWebsiteDataTypes()
        }
        WKWebsiteDataStore.default().removeData(ofTypes: types, modifiedSince: .distantPast) {}
    }

    // MARK: Host API (called from the chrome via ChromeBridge)

    func handle(_ cmd: String, _ args: [String: Any]) -> Any? {
        let webView = tab.webView
        switch cmd {
        case "ready":
            chromeReady = true
            refreshShadow()
            lastWindowState = windowState
            return [
                "apiVersion": ChromeBridge.apiVersion,
                "tab": tab.state,
                "tabs": tabsPayload,
                "window": lastWindowState,
                "dialupMode": DialupMode.shared.settings.dictionary,
                "prefs": preferencesPayload,
                "sounds": SoundEffects.shared.isEnabled,
            ]
        case "menuAction":
            // Items in the chrome's own menu bar. Allowlisted selectors only, sent after the
            // overlay has closed, so they reach the page (or whatever had focus before).
            let allowed: [String: Selector] = [
                "newWindow": #selector(AppDelegate.newWindow(_:)),
                "performClose": #selector(NSWindow.performClose(_:)),
                "cut": #selector(NSText.cut(_:)),
                "copy": #selector(NSText.copy(_:)),
                "paste": #selector(NSText.paste(_:)),
                "selectAll": #selector(NSText.selectAll(_:)),
                "toggleFullScreen": #selector(NSWindow.toggleFullScreen(_:)),
            ]
            if let name = args["action"] as? String, let selector = allowed[name] {
                NSApp.sendAction(selector, to: nil, from: nil)
            }
        case "search":
            if let query = args["query"] as? String, !query.isEmpty,
               let encoded = query.addingPercentEncoding(withAllowedCharacters: .alphanumerics),
               let url = URL(string: PreferencesStore.shared.preferences.searchTemplate.replacingOccurrences(of: "%s", with: encoded)) {
                SoundEffects.shared.play(.click)
                webView.load(URLRequest(url: url))
                focusPage()
            }
        case "securityInfo": return securityInfo()
        case "sound":
            if let name = args["name"] as? String, let sound = SoundEffects.Sound(rawValue: name), sound != .modem {
                SoundEffects.shared.play(sound)
            }
        case "soundSet":
            SoundEffects.shared.isEnabled = args["enabled"] as? Bool ?? true
            NotificationCenter.default.post(name: Self.soundsDidChange, object: nil)
        case "addFavorite":
            if let url = args["url"] as? String {
                var prefs = PreferencesStore.shared.preferences
                let title = (args["title"] as? String) ?? url
                if prefs.quickLinks.count < Preferences.maxFavorites, !prefs.quickLinks.contains(where: { $0.url == url }) {
                    prefs.quickLinks.append(QuickLink(title: title, url: url))
                    prefs.sanitize()
                    PreferencesStore.shared.preferences = prefs
                }
            }
        case "newTab":
            let url = (args["url"] as? String).flatMap { AddressResolver.resolve($0) } ?? Self.homeURL
            if tabsEnabled { addTab(url: url, select: true) } else { (NSApp.delegate as? AppDelegate)?.openWindow(urls: [url]) }
        case "closeTab":
            if let index = tabIndex(args) { closeTab(at: index) }
        case "selectTab":
            if let index = tabIndex(args) { selectTab(at: index) }
        case "wayback":
            // Reload the current page as the Wayback Machine saw it around the chosen year.
            if let year = (args["year"] as? NSNumber)?.intValue, (1996...2030).contains(year),
               let current = tab.sessionURL, ["http", "https"].contains(current.scheme ?? ""),
               let url = URL(string: "https://web.archive.org/web/\(year)0601000000/\(current.absoluteString)") {
                SoundEffects.shared.play(.click)
                tab.webView.load(URLRequest(url: url))
            }
        case "importBookmarks": importBookmarks()
        case "exportBookmarks": exportBookmarks()
        case "prefsGet": return preferencesPayload
        case "prefsSet":
            PreferencesStore.shared.preferences = PreferencesStore.shared.preferences.merging(args)
        case "overlay": setOverlay(args["open"] as? Bool ?? false)
        case "clearData": clearData(args["what"] as? String ?? "cache")
        case "windowClose": window?.performClose(nil)
        case "windowMinimize": window?.performMiniaturize(nil)
        case "windowZoom": window?.performZoom(nil)
        case "windowDrag":
            // Same trick Tauri uses: start a native window drag from the current mouse-down.
            // The JS message arrives asynchronously, so only drag while the button is still held.
            if let event = NSApp.currentEvent, event.type == .leftMouseDown || event.type == .leftMouseDragged,
               NSEvent.pressedMouseButtons & 1 != 0 {
                window?.performDrag(with: event)
            }
        case "titlebarDoubleClick": titlebarDoubleClick()
        case "dialupModeGet": return DialupMode.shared.settings.dictionary
        case "dialupModeSet":
            DialupMode.shared.settings = DialupMode.shared.settings.merging(args)
        case "dialupModePreset":
            if let id = args["id"] as? String, let preset = DialupModeSettings.presets[id] {
                DialupMode.shared.settings = preset
            }
        case "setInsets":
            func n(_ key: String) -> CGFloat { CGFloat((args[key] as? NSNumber)?.doubleValue ?? 0) }
            layoutView.insets = NSEdgeInsets(top: n("top"), left: n("left"), bottom: n("bottom"), right: n("right"))
        case "navigate":
            let prefs = PreferencesStore.shared.preferences
            SoundEffects.shared.play(.click)
            if let input = args["input"] as? String,
               let url = ["about:home", "about:start"].contains(input.trimmingCharacters(in: .whitespaces).lowercased())
                   ? Preferences.startURL
                   : AddressResolver.resolve(input, searchTemplate: prefs.searchTemplate) {
                webView.load(URLRequest(url: url))
                focusPage()
            }
        case "back": webView.goBack()
        case "forward": webView.goForward()
        case "reload": webView.reload()
        case "stop": webView.stopLoading()
        case "home": webView.load(URLRequest(url: Self.homeURL))
        case "focusPage": focusPage()
        case "log":
            NSLog("Dialup chrome: %@", String((args["message"] as? String ?? "").prefix(2000)))
        case "history":
            let back = (args["direction"] as? String) != "forward"
            let list = back ? webView.backForwardList.backList.reversed() : webView.backForwardList.forwardList
            return list.prefix(15).enumerated().map { index, item in
                [
                    "offset": (index + 1) * (back ? -1 : 1),
                    "title": item.title ?? "",
                    "url": item.url.absoluteString,
                ] as [String: Any]
            }
        case "goHistory":
            if let offset = (args["offset"] as? NSNumber)?.intValue,
               let item = webView.backForwardList.item(at: offset) {
                webView.go(to: item)
            }
        case "popupMenu":
            let items = args["items"] as? [[String: Any]] ?? []
            let x = (args["x"] as? NSNumber)?.doubleValue ?? 0
            let y = (args["y"] as? NSNumber)?.doubleValue ?? 0
            return popupMenu(items, at: NSPoint(x: x, y: y))
        default:
            NSLog("Dialup: unknown host command %@", cmd)
        }
        return nil
    }

    /// Sends `{event, data}` to the chrome's `window.dialup.receive`.
    func emit(_ event: String, _ data: [String: Any]) {
        guard chromeReady else { return }
        chromeView.callAsyncJavaScript(
            "window.dialup && window.dialup.receive(msg)",
            arguments: ["msg": ["event": event, "data": data]],
            in: nil, in: .page, completionHandler: nil
        )
    }

    private func tabDidChange(_ changed: Tab) {
        if changed === tab {
            window?.title = "\(tab.displayTitle) – Dialup"
            emit("tab", tab.state)
        }
        emitTabs()
    }

    private func focusPage() {
        window?.makeFirstResponder(tab.webView)
    }

    /// Item spec: `{ id, title, enabled?, checked?, separator?, items? }`; `items` makes a submenu.
    private func popupMenu(_ items: [[String: Any]], at point: NSPoint) -> String? {
        let picker = MenuPicker()
        let menu = Self.buildMenu(items, picker: picker)
        // layoutView is flipped and the chrome fills it, so chrome CSS pixels map directly.
        menu.popUp(positioning: nil, at: point, in: layoutView)
        return picker.picked
    }

    private static func buildMenu(_ items: [[String: Any]], picker: MenuPicker, depth: Int = 0) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for spec in items {
            if spec["separator"] as? Bool == true {
                menu.addItem(.separator())
                continue
            }
            let item = NSMenuItem(title: spec["title"] as? String ?? "", action: nil, keyEquivalent: "")
            item.isEnabled = spec["enabled"] as? Bool ?? true
            item.state = (spec["checked"] as? Bool ?? false) ? .on : .off
            if let children = spec["items"] as? [[String: Any]], depth < 3 {
                item.submenu = buildMenu(children, picker: picker, depth: depth + 1)
            } else {
                item.action = #selector(MenuPicker.pick(_:))
                item.target = picker
                item.representedObject = spec["id"] as? String
            }
            menu.addItem(item)
        }
        return menu
    }

    // MARK: Menu actions (native shortcuts)

    @objc func openSetupWizard(_ sender: Any?) {
        emit("openWizard", [:])
    }

    @objc func openSettings(_ sender: Any?) {
        emit("openSettings", ["tab": "general"])
    }

    @objc func openLocation(_ sender: Any?) {
        window?.makeFirstResponder(chromeView)
        emit("focusAddress", [:])
    }

    @objc func newTab(_ sender: Any?) {
        if tabsEnabled { addTab(url: Self.homeURL, select: true) } else { (NSApp.delegate as? AppDelegate)?.newWindow(nil) }
    }

    /// ⌘W closes the current tab; the last tab closes the window.
    @objc func closeTabOrWindow(_ sender: Any?) { closeTab(at: activeIndex) }
    @objc func selectNextTab(_ sender: Any?) { selectTab(at: (activeIndex + 1) % tabs.count) }
    @objc func selectPreviousTab(_ sender: Any?) { selectTab(at: (activeIndex - 1 + tabs.count) % tabs.count) }
    @objc func selectTabByNumber(_ sender: NSMenuItem) { selectTab(at: min(sender.tag, tabs.count) - 1) }

    @objc func dialupBack(_ sender: Any?) { tab.webView.goBack() }
    @objc func dialupForward(_ sender: Any?) { tab.webView.goForward() }
    @objc func dialupReload(_ sender: Any?) { tab.webView.reload() }
    @objc func dialupStop(_ sender: Any?) { tab.webView.stopLoading() }
    @objc func dialupHome(_ sender: Any?) { tab.webView.load(URLRequest(url: Self.homeURL)) }

    @objc func toggleDialupMode(_ sender: Any?) {
        DialupMode.shared.settings.enabled.toggle()
    }

    @objc func reloadChrome(_ sender: Any?) {
        chromeReady = false
        setOverlay(false)
        chromeView.load(URLRequest(url: Self.chromeURL))
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(dialupBack(_:)): tab.webView.canGoBack
        case #selector(dialupForward(_:)): tab.webView.canGoForward
        case #selector(dialupStop(_:)): tab.webView.isLoading
        case #selector(selectNextTab(_:)), #selector(selectPreviousTab(_:)): tabs.count > 1
        case #selector(selectTabByNumber(_:)): menuItem.tag <= tabs.count
        case #selector(toggleDialupMode(_:)):
            {
                menuItem.state = DialupMode.shared.settings.enabled ? .on : .off
                return true
            }()
        default: true
        }
    }

    // MARK: Bookmarks (Netscape bookmark file format, as every browser of the era exported)

    private func importBookmarks() {
        guard let window else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.html]
        panel.message = "Choose a bookmarks file (bookmarks.html) exported from another browser."
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            MainActor.assumeIsolated {
                let html = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
                let imported = Bookmarks.parse(html)
                var prefs = PreferencesStore.shared.preferences
                var added = 0
                for link in imported where !prefs.quickLinks.contains(where: { $0.url == link.url }) {
                    guard prefs.quickLinks.count < Preferences.maxFavorites else { break }
                    prefs.quickLinks.append(link)
                    added += 1
                }
                prefs.sanitize()
                PreferencesStore.shared.preferences = prefs
                self?.emit("bookmarksImported", ["added": added, "found": imported.count])
            }
        }
    }

    private func exportBookmarks() {
        guard let window else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.html]
        panel.nameFieldStringValue = "bookmarks.html"
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            MainActor.assumeIsolated {
                try? Bookmarks.export(PreferencesStore.shared.preferences.quickLinks).write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }

    // MARK: Chrome navigation guard

    /// The chrome may only show dialup:// content. Anything else opens in the page instead.
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard webView === chromeView else { return .allow }
        if navigationAction.request.url?.scheme == DialupSchemeHandler.scheme { return .allow }
        if let url = navigationAction.request.url { tab.webView.load(URLRequest(url: url)) }
        return .cancel
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard webView === chromeView else { return }
        reloadChrome(nil)
    }
}

@MainActor
private final class MenuPicker: NSObject {
    var picked: String?
    @objc func pick(_ sender: NSMenuItem) { picked = sender.representedObject as? String }
}
