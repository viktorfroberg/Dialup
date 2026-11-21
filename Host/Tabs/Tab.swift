import AppKit
import WebKit

/// One page: wraps a WKWebView and reports its state to whoever listens.
@MainActor
final class Tab: NSObject, WKNavigationDelegate, WKUIDelegate {
    let webView: WKWebView
    var onChange: (() -> Void)?
    /// The start page's "Customize" link asks to open settings at a given tab.
    var onOpenSettings: ((String) -> Void)?

    /// Last error or other message for the status bar; cleared on next navigation.
    private(set) var statusText: String?
    /// Dial-up mode: images still "downloading" on this page.
    private(set) var items: (remaining: Int, total: Int, url: String)?
    private var observations: [NSKeyValueObservation] = []

    init(configuration: WKWebViewConfiguration) {
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.isInspectable = true
        webView.allowsBackForwardNavigationGestures = true
        watch(\.title)
        watch(\.url)
        watch(\.isLoading)
        watch(\.estimatedProgress)
        watch(\.canGoBack)
        watch(\.canGoForward)
    }

    private func watch<Value>(_ keyPath: KeyPath<WKWebView, Value>) {
        observations.append(webView.observe(keyPath, options: []) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.scheduleChange() }
        })
    }

    private var changePending = false

    /// Coalesces bursts of KVO changes (progress ticks etc.) into one state update per run loop.
    private func scheduleChange() {
        guard !changePending else { return }
        changePending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            changePending = false
            onChange?()
        }
    }

    /// Snapshot sent to the chrome as the `tab` event.
    var state: [String: Any] {
        [
            "url": String(Self.displayURL(webView.url).prefix(4096)),
            "title": String((webView.title ?? "").prefix(300)),
            "secure": webView.url?.scheme == "https" && webView.hasOnlySecureContent,
            "loading": webView.isLoading,
            "progress": webView.estimatedProgress,
            "canGoBack": webView.canGoBack,
            "canGoForward": webView.canGoForward,
            "statusText": statusText ?? NSNull(),
            "items": items.map { ["remaining": $0.remaining, "total": $0.total, "url": $0.url] as [String: Any] } ?? NSNull(),
        ]
    }

    /// The start page shows as "about:home" in the address bar.
    static func displayURL(_ url: URL?) -> String {
        guard let url else { return "" }
        return url.scheme == StartPageSchemeHandler.scheme ? "about:home" : url.absoluteString
    }

    var isShowingStartPage: Bool { webView.url?.scheme == StartPageSchemeHandler.scheme }

    func setItems(remaining: Int, total: Int, url: String) {
        items = total > 0 ? (remaining, total, url) : nil
        scheduleChange()
    }

    var displayTitle: String {
        if let title = webView.title, !title.isEmpty { return title }
        if isShowingStartPage { return "Start Page" }
        return webView.url?.host ?? "Untitled"
    }

    // MARK: Navigation

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        if navigationAction.targetFrame?.isMainFrame == true,
           [.linkActivated, .formSubmitted, .backForward].contains(navigationAction.navigationType) {
            SoundEffects.shared.play(.click) // the era's navigation "tick"
        }
        if navigationAction.request.url == StartPageSchemeHandler.customizeURL {
            // Only the start page itself, navigating its own main frame, may open settings.
            if Self.isTrustedCustomize(sourceProtocol: navigationAction.sourceFrame.securityOrigin.protocol,
                                       targetIsMainFrame: navigationAction.targetFrame?.isMainFrame ?? false) {
                onOpenSettings?("startpage")
            }
            return .cancel
        }
        return .allow
    }

    static func isTrustedCustomize(sourceProtocol: String, targetIsMainFrame: Bool) -> Bool {
        sourceProtocol == StartPageSchemeHandler.scheme && targetIsMainFrame
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        items = nil // the previous document's "(n items remaining)" no longer applies
        scheduleChange()
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        statusText = nil
        items = nil
        onChange?()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        let nsError = error as NSError
        guard !Self.isBenign(nsError) else { return }
        statusText = nsError.localizedDescription
        onChange?()
        SoundEffects.shared.play(.error)
        if let failingURL = nsError.userInfo[NSURLErrorFailingURLErrorKey] as? URL {
            webView.loadSimulatedRequest(URLRequest(url: failingURL),
                                         responseHTML: ErrorPage.html(url: failingURL, message: nsError.localizedDescription))
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        let nsError = error as NSError
        guard !Self.isBenign(nsError) else { return }
        statusText = nsError.localizedDescription
        onChange?()
    }

    private var lastCrash: Date?

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        // Reload once; if it crashes again right away, stop instead of looping.
        if let lastCrash, Date().timeIntervalSince(lastCrash) < 10 {
            statusText = "The page crashed again. Click Refresh to try once more."
            scheduleChange()
            return
        }
        lastCrash = Date()
        webView.reload()
        statusText = "The page crashed and was reloaded."
        scheduleChange()
    }

    private static func isBenign(_ error: NSError) -> Bool {
        (error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled)
            || (error.domain == "WebKitErrorDomain" && error.code == 102) // frame load interrupted (e.g. download)
    }

    // MARK: UI

    /// target=_blank / window.open: no tabs yet (phase 1), so open in the same view.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        webView.load(navigationAction.request)
        return nil
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo) async {
        let alert = NSAlert()
        alert.messageText = frame.securityOrigin.host.isEmpty ? "Dialup" : frame.securityOrigin.host
        alert.informativeText = message
        if let window = webView.window { _ = await alert.beginSheetModal(for: window) } else { alert.runModal() }
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo) async -> Bool {
        let alert = NSAlert()
        alert.messageText = frame.securityOrigin.host.isEmpty ? "Dialup" : frame.securityOrigin.host
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        let response = if let window = webView.window { await alert.beginSheetModal(for: window) } else { alert.runModal() }
        return response == .alertFirstButtonReturn
    }
}

enum ErrorPage {
    static func html(url: URL, message: String) -> String {
        let safeURL = escape(url.absoluteString)
        let safeMessage = escape(message)
        return """
        <!doctype html><html><head><meta charset="utf-8"><title>Cannot find server</title>
        <style>
          body { font: 13px Tahoma, Verdana, sans-serif; margin: 24px 40px; color: #000; background: #fff; }
          h1 { font-size: 17px; font-weight: bold; margin: 0 0 14px; }
          hr { border: 0; border-top: 1px solid #c0c0c0; }
          ul { padding-left: 22px; } li { margin: 4px 0; } code { color: #555; }
        </style></head><body>
        <h1>The page cannot be displayed</h1>
        <p>The page you are looking for is currently unavailable. The Web site might be experiencing
        technical difficulties, or you may need to adjust your browser settings.</p><hr>
        <p>Please try the following:</p>
        <ul><li>Click the <b>Refresh</b> button, or try again later.</li>
        <li>If you typed the page address in the Address bar, make sure that it is spelled correctly.</li></ul>
        <p><code>\(safeMessage)</code><br><code>\(safeURL)</code></p>
        </body></html>
        """
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
