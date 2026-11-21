import AppKit
import WebKit

/// One browser window: a chrome web view (the HTML UI) plus one page web view per tab.
///
/// This file has the window's state: tabs, the chrome connection and events, window state and
/// navigation helpers. Commands from the chrome are in `BrowserWindowController+HostCommands.swift`,
/// native menu actions in `BrowserWindowController+MenuActions.swift`.
@MainActor
final class BrowserWindowController: NSWindowController, NSWindowDelegate, WKNavigationDelegate {
    /// Home page from preferences (debug builds: `-HomePage <url>` overrides it).
    static var homeURL: URL {
        LaunchEnvironment.homePageOverride ?? PreferencesStore.shared.preferences.homeURL
    }
    /// Force-unwrapped: a constant, valid URL.
    static let chromeURL = URL(string: "dialup://chrome/index.html")!

    private static let defaultContentSize = NSSize(width: 1100, height: 780)
    private static let minimumSize = NSSize(width: 520, height: 340)
    /// The first window remembers its frame under this name; later ones cascade from the key window.
    private static let frameAutosaveName = "DialupMain"
    /// How many closed tabs ⇧⌘T can bring back.
    private static let maxClosedTabs = 20
    private static let maxTabTitleLength = 120
    /// A transparent window's shadow follows its painted shape, so it's recomputed once the skin has drawn.
    private static let shadowRefreshDelay = Duration.milliseconds(300)

    var onClose: (() -> Void)?
    /// Called when tabs or their URLs change, so the app can save the session.
    var onSessionChange: (() -> Void)?

    /// All open windows, so shared page handlers can find which window a web view belongs to.
    private static let all = NSHashTable<BrowserWindowController>.weakObjects()

    static func owner(of webView: WKWebView) -> BrowserWindowController? {
        all.allObjects.first { $0.tab(for: webView) != nil }
    }

    let layoutView = BrowserLayoutView()
    let chromeView: WKWebView
    private let bridge = ChromeBridge()
    private let hoverHandler = HoverLinkHandler()
    private let dialupModeScript = DialupModePageScript()
    private let pageConfiguration: WKWebViewConfiguration
    private weak var windowOpener: (any BrowserWindowOpening)?

    private(set) var tabs = TabList<Tab>()
    /// Tabs closed in this window, newest last, for ⇧⌘T (Reopen Closed Tab).
    private(set) var closedTabs: [URL] = []
    /// Events are only sent once the chrome has called `ready`.
    private var chromeReady = false
    private var lastWindowState: [String: Bool] = [:]
    /// Who had focus before a retro menu or dialog opened, to give it back afterwards.
    private var responderBeforeOverlay: NSResponder?
    private var lastTabsJSON = ""

    /// The visible tab. A window always has one: closing the last tab closes the window,
    /// and `init` opens the first tab before anything can ask.
    var activeTab: Tab {
        guard let tab = tabs.active else { preconditionFailure("a browser window always has a tab") }
        return tab
    }

    var tabsEnabled: Bool { PreferencesStore.shared.preferences.tabs }

    /// - Parameters:
    ///   - urls: tabs to open (restored sessions load lazily); empty = the home page.
    ///   - activeIndex: which of `urls` to show.
    ///   - popupConfiguration: for window.open with tabs off: the first tab must use WebKit's configuration.
    ///   - opener: opens further windows (tabs turned off, popups).
    init(urls: [URL] = [], activeIndex: Int = 0, popupConfiguration: WKWebViewConfiguration? = nil,
         opener: (any BrowserWindowOpening)?) {
        chromeView = WKWebView(frame: .zero, configuration: ChromeConfiguration.make(bridge: bridge, schemeHandler: .bundled()))
        chromeView.isInspectable = true
        // Transparent, so when menus/dialogs raise the chrome above the page, the page shows through.
        chromeView.setValue(false, forKey: "drawsBackground")
        pageConfiguration = popupConfiguration
            ?? PageConfiguration.make(hoverHandler: hoverHandler, dialupModeScript: dialupModeScript)
        windowOpener = opener

        // A frameless, transparent window (see DialupWindow): the HTML chrome draws the title bar,
        // the buttons and the window corners. ⌘W/⌘M, Mission Control and resizing still work.
        let window = DialupWindow(contentRect: NSRect(origin: .zero, size: Self.defaultContentSize))
        window.isReleasedWhenClosed = false
        window.minSize = Self.minimumSize
        window.title = "Dialup"
        super.init(window: window)

        window.contentView = layoutView
        layoutView.chromeView = chromeView
        if let key = NSApp.keyWindow, Self.all.count > 0 {
            window.setFrame(key.frame, display: false)
            window.setFrameTopLeftPoint(window.cascadeTopLeft(from: NSPoint(x: key.frame.minX, y: key.frame.maxY)))
        } else {
            if !window.setFrameUsingName(Self.frameAutosaveName) { window.center() }
            window.setFrameAutosaveName(Self.frameAutosaveName)
        }
        Self.all.add(self)

        bridge.handler = self
        chromeView.navigationDelegate = self
        // These handlers belong to the page configuration, which a popup window may share with its
        // opener, so route by web view instead of capturing this window.
        hoverHandler.onHover = { webView, url in
            BrowserWindowController.owner(of: webView)?.hoverChanged(on: webView, url: url)
        }
        dialupModeScript.onStatus = { webView, remaining, total, url in
            BrowserWindowController.owner(of: webView)?.tab(for: webView)?
                .setItems(remaining: remaining, total: total, url: url)
        }

        if popupConfiguration != nil {
            addTab(configuration: popupConfiguration, url: nil, select: true)
        } else if urls.isEmpty {
            addTab(url: Self.homeURL, select: true)
        } else {
            for url in urls { addTab(url: url, at: .end, select: false, lazy: true) }
            selectTab(at: min(max(0, activeIndex), tabs.count - 1))
        }

        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(preferencesDidChange), name: PreferencesStore.didChange, object: nil)
        center.addObserver(self, selector: #selector(soundsDidChange), name: SoundEffects.didChange, object: nil)
        center.addObserver(self, selector: #selector(dialupModeDidChange), name: DialupModeStore.didChange, object: nil)
        applyDialupMode()
        AdBlocker.update(pageConfiguration.userContentController)
        window.delegate = self // only now: delegate callbacks assume at least one tab

        chromeView.load(URLRequest(url: Self.chromeURL))
        DebugSnapshot.scheduleIfRequested(chrome: chromeView, page: activeTab.webView, in: layoutView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    func windowWillClose(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self)
        Self.all.remove(self)
        onClose?()
    }

    // MARK: Tabs

    func tab(for webView: WKWebView) -> Tab? {
        tabs.firstIndex { $0.webView === webView }.map { tabs[$0] }
    }

    /// Creates a tab. `configuration` is only passed for WebKit-created popups; `lazy` tabs
    /// (session restore) load their URL when first shown.
    @discardableResult
    func addTab(configuration: WKWebViewConfiguration? = nil, url: URL?, at position: TabList<Tab>.Position = .afterActive,
                select: Bool, lazy: Bool = false) -> Tab {
        let tab = Tab(configuration: configuration ?? pageConfiguration, pendingURL: lazy ? url : nil)
        tab.onChange = { [weak self, weak tab] in
            guard let self, let tab else { return }
            tabDidChange(tab)
        }
        tab.onOpenSettings = { [weak self] section in self?.emit("openSettings", ["tab": section]) }
        tab.onCreateWebView = { [weak self] configuration, _ in self?.openPopup(configuration: configuration) }
        tab.onDownload = { [weak self] info in self?.emit("download", info) }
        tab.onCloseRequest = { [weak self, weak tab] in
            guard let self, let tab, let index = tabs.index(of: tab) else { return }
            closeTab(at: index)
        }
        let index = tabs.insert(tab, at: position)
        if !lazy, let url { tab.webView.load(URLRequest(url: url)) }
        if select { selectTab(at: index) }
        emitTabs()
        return tab
    }

    /// Opens `url` in a new tab at the end, or in a new window when tabs are turned off.
    func openInNewTabOrWindow(_ url: URL, at position: TabList<Tab>.Position = .end) {
        if tabsEnabled {
            addTab(url: url, at: position, select: true)
        } else {
            windowOpener?.openWindow(urls: [url])
        }
    }

    /// Links from other apps: a new tab in this window, brought to the front.
    func openInNewTab(_ url: URL) {
        addTab(url: url, at: .end, select: true)
        window?.makeKeyAndOrderFront(nil)
    }

    /// target=_blank / window.open: a new tab, or (tabs off) a new cascading window.
    private func openPopup(configuration: WKWebViewConfiguration) -> WKWebView? {
        if tabsEnabled {
            return addTab(configuration: configuration, url: nil, select: true).webView
        }
        return windowOpener?.openPopupWindow(configuration: configuration)
    }

    func selectTab(at index: Int) {
        guard tabs.select(index) else { return }
        let tab = activeTab
        tab.loadIfNeeded()
        layoutView.pageView = tab.webView
        applyDialupMode()
        tabDidChange(tab)
        emitTabs()
        if window?.firstResponder !== chromeView { focusPage() }
    }

    /// Closes a tab; closing the last one closes the window.
    func closeTab(at index: Int) {
        guard tabs.indices.contains(index) else { return }
        guard tabs.count > 1 else { window?.performClose(nil); return }
        guard let closing = tabs.remove(at: index) else { return }
        if let url = closing.sessionURL {
            closedTabs.append(url)
            closedTabs = Array(closedTabs.suffix(Self.maxClosedTabs))
        }
        closing.webView.stopLoading()
        closing.webView.removeFromSuperview()
        selectTab(at: tabs.activeIndex)
    }

    func reopenClosedTab() {
        guard let url = closedTabs.popLast() else { return }
        openInNewTabOrWindow(url, at: .afterActive)
    }

    func tabIndex(id: Int) -> Int? {
        tabs.firstIndex { $0.id == id }
    }

    /// For session restore: this window's tab URLs and which one is active.
    var session: (urls: [URL], active: Int) {
        (tabs.elements.compactMap(\.sessionURL), tabs.activeIndex)
    }

    // MARK: Events to the chrome

    /// The `ready` handshake: from now on events flow. Returns everything the chrome needs to draw.
    func chromeDidBecomeReady() -> [String: Any] {
        chromeReady = true
        refreshShadow()
        lastWindowState = windowState
        return [
            "apiVersion": ChromeBridge.apiVersion,
            "tab": activeTab.state,
            "tabs": tabsPayload,
            "window": lastWindowState,
            "dialupMode": DialupModeStore.shared.settings.dictionary,
            "prefs": preferencesPayload,
            "sounds": SoundEffects.shared.isEnabled,
        ]
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

    private var tabsPayload: [String: Any] {
        [
            "enabled": tabsEnabled,
            "active": activeTab.id,
            "tabs": tabs.elements.map {
                ["id": $0.id, "title": String($0.displayTitle.prefix(Self.maxTabTitleLength)), "loading": $0.webView.isLoading] as [String: Any]
            },
        ]
    }

    /// Sends the `tabs` event when the strip actually changed (and lets the app save the session).
    private func emitTabs() {
        guard !tabs.isEmpty else { return }
        let payload = tabsPayload
        let json = (try? JSONSerialization.data(withJSONObject: payload)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        guard json != lastTabsJSON else { return }
        lastTabsJSON = json
        emit("tabs", payload)
        onSessionChange?()
    }

    private func tabDidChange(_ changed: Tab) {
        if changed === activeTab {
            window?.title = "\(changed.displayTitle) – Dialup"
            emit("tab", changed.state)
        }
        emitTabs()
    }

    private func hoverChanged(on webView: WKWebView, url: String) {
        guard webView === activeTab.webView else { return }
        emit("hoverLink", ["url": url])
    }

    var preferencesPayload: [String: Any] {
        PreferencesStore.shared.preferences.dictionary.merging(["catalog": Preferences.catalog]) { current, _ in current }
    }

    // MARK: App-wide changes

    @objc private func preferencesDidChange(_ notification: Notification) {
        emit("prefs", preferencesPayload)
        refreshShadow()
        applyDialupMode() // skin-specific scrollbars
        AdBlocker.update(pageConfiguration.userContentController)
        for tab in tabs.elements where tab.isShowingStartPage { tab.webView.reload() }
        emitTabs()
    }

    @objc private func soundsDidChange(_ notification: Notification) {
        emit("sounds", ["enabled": SoundEffects.shared.isEnabled])
    }

    @objc private func dialupModeDidChange(_ notification: Notification?) {
        applyDialupMode()
        emit("dialupMode", DialupModeStore.shared.settings.dictionary)
    }

    private func applyDialupMode() {
        guard !tabs.isEmpty else { return }
        DialupModeRenderer.apply(DialupModeStore.shared.settings, to: layoutView, page: activeTab.webView,
                                 allPages: tabs.elements.map(\.webView), pageScript: dialupModeScript,
                                 skin: PreferencesStore.shared.preferences.skin)
    }

    private func refreshShadow() {
        Task { [weak self] in
            try? await Task.sleep(for: Self.shadowRefreshDelay)
            self?.window?.invalidateShadow()
        }
    }

    // MARK: Window state → chrome (title bar look)

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
    /// Moving to a screen with another scale changes the pixel size of the hard-mode filters.
    func windowDidChangeBackingProperties(_ notification: Notification) { dialupModeDidChange(nil) }

    // MARK: Focus and overlay (retro menus and dialogs)

    func focusPage() {
        window?.makeFirstResponder(activeTab.webView)
    }

    /// Menus and dialogs are drawn by the chrome. While one is open, the chrome sits above
    /// the page (its page area is transparent) and has keyboard focus.
    func setOverlay(_ open: Bool) {
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

    func reloadChrome() {
        chromeReady = false
        setOverlay(false)
        chromeView.load(URLRequest(url: Self.chromeURL))
    }

    // MARK: Navigation (shared by host commands and menu actions)

    func load(_ url: URL) {
        activeTab.webView.load(URLRequest(url: url))
    }

    /// Address-bar input: a URL, a bare host, `about:home`, or search text for the preferred engine.
    func navigate(to input: String) {
        SoundEffects.shared.play(.click)
        let prefs = PreferencesStore.shared.preferences
        guard let url = AddressResolver.resolve(input, searchTemplate: prefs.searchTemplate, startURL: Preferences.startURL) else { return }
        load(url)
        focusPage()
    }

    func search(for query: String) {
        guard let url = AddressResolver.searchURL(for: query, template: PreferencesStore.shared.preferences.searchTemplate) else { return }
        SoundEffects.shared.play(.click)
        load(url)
        focusPage()
    }

    func goBack() { activeTab.webView.goBack() }
    func goForward() { activeTab.webView.goForward() }
    func reload() { activeTab.webView.reload() }
    func stopLoading() { activeTab.webView.stopLoading() }
    func goHome() { load(Self.homeURL) }

    // MARK: Chrome navigation guard

    /// The chrome may only show dialup:// content. Anything else opens in the page instead.
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard webView === chromeView else { return .allow }
        if navigationAction.request.url?.scheme == DialupSchemeHandler.scheme { return .allow }
        if let url = navigationAction.request.url { load(url) }
        return .cancel
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard webView === chromeView else { return }
        reloadChrome()
    }
}
