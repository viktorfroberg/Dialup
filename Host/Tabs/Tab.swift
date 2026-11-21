import AppKit
import WebKit

/// One page: wraps a WKWebView and reports its state to whoever listens.
@MainActor
final class Tab: NSObject, WKNavigationDelegate, WKUIDelegate {
    let webView: WKWebView
    var onChange: (() -> Void)?

    /// Last error or other message for the status bar; cleared on next navigation.
    private(set) var statusText: String?
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
            MainActor.assumeIsolated { self?.onChange?() }
        })
    }

    /// Snapshot sent to the chrome as the `tab` event.
    var state: [String: Any] {
        [
            "url": webView.url?.absoluteString ?? "",
            "title": webView.title ?? "",
            "loading": webView.isLoading,
            "progress": webView.estimatedProgress,
            "canGoBack": webView.canGoBack,
            "canGoForward": webView.canGoForward,
            "statusText": statusText ?? NSNull(),
        ]
    }

    var displayTitle: String {
        if let title = webView.title, !title.isEmpty { return title }
        return webView.url?.host ?? "Untitled"
    }

    // MARK: Navigation

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        statusText = nil
        onChange?()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        let nsError = error as NSError
        guard !Self.isBenign(nsError) else { return }
        statusText = nsError.localizedDescription
        onChange?()
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

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        statusText = "The page crashed and was reloaded."
        webView.reload()
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
