import AppKit
import WebKit

/// One browser window: a chrome web view (the HTML UI) plus the page web view.
@MainActor
final class BrowserWindowController: NSWindowController, NSWindowDelegate, NSMenuItemValidation, WKNavigationDelegate {
    /// Home page from preferences. `-HomePage <url>` on the command line overrides it (debugging).
    static var homeURL: URL {
        UserDefaults.standard.string(forKey: "HomePage").flatMap(URL.init(string:))
            ?? PreferencesStore.shared.preferences.homeURL
    }
    static let chromeURL = URL(string: "dialup://chrome/index.html")!

    var onClose: (() -> Void)?

    private let layoutView = BrowserLayoutView()
    private let bridge = ChromeBridge()
    private let hoverHandler = HoverLinkHandler()
    private let dialupModePage = DialupModePage()
    private let chromeView: WKWebView
    private let tab: Tab
    private var chromeReady = false

    init() {
        let chromeConfig = ChromeConfiguration.make(bridge: bridge, schemeHandler: .bundled())
        chromeView = WKWebView(frame: .zero, configuration: chromeConfig)
        chromeView.isInspectable = true
        // Transparent, so when menus/dialogs raise the chrome above the page, the page shows through.
        chromeView.setValue(false, forKey: "drawsBackground")
        tab = Tab(configuration: PageConfiguration.make(hoverHandler: hoverHandler, dialupModePage: dialupModePage))

        // A real titled window (so ⌘W/⌘M, Mission Control, Stage Manager and resizing all work),
        // but the title bar and its buttons are drawn by the HTML chrome.
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 780),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 520, height: 340)
        window.title = "Dialup"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        for button: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(button)?.isHidden = true
        }
        super.init(window: window)

        window.contentView = layoutView
        layoutView.chromeView = chromeView
        layoutView.pageView = tab.webView
        window.delegate = self
        if !window.setFrameUsingName("DialupMain") { window.center() }
        window.setFrameAutosaveName("DialupMain")

        bridge.controller = self
        chromeView.navigationDelegate = self
        hoverHandler.onHover = { [weak self] webView, url in
            guard let self, webView === self.tab.webView else { return }
            self.emit("hoverLink", ["url": url])
        }
        dialupModePage.onStatus = { [weak self] webView, remaining, total, url in
            guard let self, webView === self.tab.webView else { return }
            self.tab.setItems(remaining: remaining, total: total, url: url)
        }
        tab.onChange = { [weak self] in self?.tabDidChange() }
        tab.onOpenSettings = { [weak self] section in self?.emit("openSettings", ["tab": section]) }
        NotificationCenter.default.addObserver(forName: PreferencesStore.didChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.preferencesDidChange() }
        }
        NotificationCenter.default.addObserver(forName: DialupMode.didChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.dialupModeDidChange() }
        }
        DialupModeRenderer.apply(DialupMode.shared.settings, to: layoutView, page: tab.webView)

        chromeView.load(URLRequest(url: Self.chromeURL))
        tab.webView.load(URLRequest(url: Self.homeURL))
        DebugSnapshot.scheduleIfRequested(chrome: chromeView, page: tab.webView, in: layoutView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    func windowWillClose(_ notification: Notification) {
        onClose?()
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
        let settings = DialupMode.shared.settings
        DialupModeRenderer.apply(settings, to: layoutView, page: tab.webView)
        emit("dialupMode", settings.dictionary)
    }

    // MARK: Preferences

    private var preferencesPayload: [String: Any] {
        PreferencesStore.shared.preferences.dictionary.merging(["catalog": Preferences.catalog]) { a, _ in a }
    }

    private func preferencesDidChange() {
        emit("prefs", preferencesPayload)
        DialupModeRenderer.apply(DialupMode.shared.settings, to: layoutView, page: tab.webView) // skin-specific scrollbars
        if tab.isShowingStartPage { tab.webView.reload() }
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
            lastWindowState = windowState
            return [
                "apiVersion": ChromeBridge.apiVersion,
                "tab": tab.state,
                "window": lastWindowState,
                "dialupMode": DialupMode.shared.settings.dictionary,
                "prefs": preferencesPayload,
            ]
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
            if let event = NSApp.currentEvent, event.type == .leftMouseDown || event.type == .leftMouseDragged {
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

    private func tabDidChange() {
        window?.title = "\(tab.displayTitle) – Dialup"
        emit("tab", tab.state)
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
        case #selector(toggleDialupMode(_:)):
            {
                menuItem.state = DialupMode.shared.settings.enabled ? .on : .off
                return true
            }()
        default: true
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
