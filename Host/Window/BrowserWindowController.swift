import AppKit
import WebKit

/// One browser window: a chrome web view (the HTML UI) plus the page web view.
@MainActor
final class BrowserWindowController: NSWindowController, NSWindowDelegate, NSMenuItemValidation, WKNavigationDelegate {
    static let homeURL = URL(string: "https://www.wikipedia.org/")!
    static let chromeURL = URL(string: "kikare://chrome/index.html")!

    var onClose: (() -> Void)?

    private let layoutView = BrowserLayoutView()
    private let bridge = ChromeBridge()
    private let hoverHandler = HoverLinkHandler()
    private let chromeView: WKWebView
    private let tab: Tab
    private var chromeReady = false

    init() {
        let chromeConfig = ChromeConfiguration.make(bridge: bridge, schemeHandler: .bundled())
        chromeView = WKWebView(frame: .zero, configuration: chromeConfig)
        chromeView.isInspectable = true
        tab = Tab(configuration: PageConfiguration.make(hoverHandler: hoverHandler))

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 780),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 520, height: 340)
        window.title = "Kikare"
        super.init(window: window)

        window.contentView = layoutView
        layoutView.chromeView = chromeView
        layoutView.pageView = tab.webView
        window.delegate = self
        if !window.setFrameUsingName("KikareMain") { window.center() }
        window.setFrameAutosaveName("KikareMain")

        bridge.controller = self
        chromeView.navigationDelegate = self
        hoverHandler.onHover = { [weak self] webView, url in
            guard let self, webView === self.tab.webView else { return }
            self.emit("hoverLink", ["url": url])
        }
        tab.onChange = { [weak self] in self?.tabDidChange() }

        chromeView.load(URLRequest(url: Self.chromeURL))
        tab.webView.load(URLRequest(url: Self.homeURL))
        DebugSnapshot.scheduleIfRequested(chrome: chromeView, page: tab.webView, in: layoutView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }

    // MARK: Host API (called from the chrome via ChromeBridge)

    func handle(_ cmd: String, _ args: [String: Any]) -> Any? {
        let webView = tab.webView
        switch cmd {
        case "ready":
            chromeReady = true
            return ["apiVersion": ChromeBridge.apiVersion, "tab": tab.state]
        case "setInsets":
            func n(_ key: String) -> CGFloat { CGFloat((args[key] as? NSNumber)?.doubleValue ?? 0) }
            layoutView.insets = NSEdgeInsets(top: n("top"), left: n("left"), bottom: n("bottom"), right: n("right"))
        case "navigate":
            if let input = args["input"] as? String, let url = AddressResolver.resolve(input) {
                webView.load(URLRequest(url: url))
                focusPage()
            }
        case "back": webView.goBack()
        case "forward": webView.goForward()
        case "reload": webView.reload()
        case "stop": webView.stopLoading()
        case "home": webView.load(URLRequest(url: Self.homeURL))
        case "focusPage": focusPage()
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
            NSLog("Kikare: unknown host command %@", cmd)
        }
        return nil
    }

    /// Sends `{event, data}` to the chrome's `window.kikare.receive`.
    func emit(_ event: String, _ data: [String: Any]) {
        guard chromeReady else { return }
        chromeView.callAsyncJavaScript(
            "window.kikare && window.kikare.receive(msg)",
            arguments: ["msg": ["event": event, "data": data]],
            in: nil, in: .page, completionHandler: nil
        )
    }

    private func tabDidChange() {
        window?.title = "\(tab.displayTitle) – Kikare"
        emit("tab", tab.state)
    }

    private func focusPage() {
        window?.makeFirstResponder(tab.webView)
    }

    private func popupMenu(_ items: [[String: Any]], at point: NSPoint) -> String? {
        let picker = MenuPicker()
        let menu = NSMenu()
        menu.autoenablesItems = false
        for spec in items {
            if spec["separator"] as? Bool == true {
                menu.addItem(.separator())
                continue
            }
            let item = NSMenuItem(title: spec["title"] as? String ?? "", action: #selector(MenuPicker.pick(_:)), keyEquivalent: "")
            item.target = picker
            item.representedObject = spec["id"] as? String
            item.isEnabled = spec["enabled"] as? Bool ?? true
            menu.addItem(item)
        }
        // layoutView is flipped and the chrome fills it, so chrome CSS pixels map directly.
        menu.popUp(positioning: nil, at: point, in: layoutView)
        return picker.picked
    }

    // MARK: Menu actions (native shortcuts)

    @objc func openLocation(_ sender: Any?) {
        window?.makeFirstResponder(chromeView)
        emit("focusAddress", [:])
    }

    @objc func kikareBack(_ sender: Any?) { tab.webView.goBack() }
    @objc func kikareForward(_ sender: Any?) { tab.webView.goForward() }
    @objc func kikareReload(_ sender: Any?) { tab.webView.reload() }
    @objc func kikareStop(_ sender: Any?) { tab.webView.stopLoading() }
    @objc func kikareHome(_ sender: Any?) { tab.webView.load(URLRequest(url: Self.homeURL)) }

    @objc func reloadChrome(_ sender: Any?) {
        chromeReady = false
        chromeView.load(URLRequest(url: Self.chromeURL))
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(kikareBack(_:)): tab.webView.canGoBack
        case #selector(kikareForward(_:)): tab.webView.canGoForward
        case #selector(kikareStop(_:)): tab.webView.isLoading
        default: true
        }
    }

    // MARK: Chrome navigation guard

    /// The chrome may only show kikare:// content. Anything else opens in the page instead.
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard webView === chromeView else { return .allow }
        if navigationAction.request.url?.scheme == KikareSchemeHandler.scheme { return .allow }
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
