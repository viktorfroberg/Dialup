import AppKit
import WebKit

/// One page: wraps a WKWebView and reports its state to whoever listens.
@MainActor
final class Tab: NSObject, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
    private static var nextID = 1
    let id: Int
    let webView: WKWebView
    /// Restored tabs load lazily: the URL is kept here until the tab is first shown.
    private(set) var pendingURL: URL?
    /// target=_blank / window.open: the window decides (new tab or new window). Must return a web
    /// view created with the given configuration, or nil to load in this tab instead.
    var onCreateWebView: ((WKWebViewConfiguration, WKNavigationAction) -> WKWebView?)?
    /// The page called window.close().
    var onCloseRequest: (() -> Void)?
    var onChange: (() -> Void)?
    /// The start page's "Customize" link asks to open settings at a given tab.
    var onOpenSettings: ((String) -> Void)?
    /// Download progress and completion, for the chrome (`{ name, fraction, state, path }`).
    var onDownload: (([String: Any]) -> Void)?

    /// Last error or other message for the status bar; cleared on next navigation.
    private(set) var statusText: String?
    /// Dial-up mode: images still "downloading" on this page.
    private(set) var items: (remaining: Int, total: Int, url: String)?
    private var observations: [NSKeyValueObservation] = []

    init(configuration: WKWebViewConfiguration, pendingURL: URL? = nil) {
        id = Self.nextID
        Self.nextID += 1
        self.pendingURL = pendingURL
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
            "id": id,
            "url": String(Self.displayURL(webView.url ?? pendingURL).prefix(4096)),
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

    /// The URL to remember for session restore.
    var sessionURL: URL? { webView.url ?? pendingURL }

    /// Loads a restored tab's URL the first time it's shown.
    func loadIfNeeded() {
        guard let url = pendingURL else { return }
        pendingURL = nil
        webView.load(URLRequest(url: url))
    }

    func setItems(remaining: Int, total: Int, url: String) {
        items = total > 0 ? (remaining, total, url) : nil
        scheduleChange()
    }

    var displayTitle: String {
        if let title = webView.title, !title.isEmpty { return title }
        if isShowingStartPage || pendingURL == Preferences.startURL { return "Start Page" }
        if let pendingURL { return pendingURL.host ?? pendingURL.absoluteString }
        return webView.url?.host ?? "Untitled"
    }

    // MARK: Navigation

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        if navigationAction.targetFrame?.isMainFrame == true,
           [.linkActivated, .formSubmitted, .backForward].contains(navigationAction.navigationType) {
            SoundEffects.shared.play(.click) // the era's navigation "tick"
        }
        if navigationAction.shouldPerformDownload { return .download }
        if let url = navigationAction.request.url, let scheme = url.scheme?.lowercased(), !Self.webSchemes.contains(scheme) {
            // mailto:, tel:, itms-apps: … go to the system, but only when the user clicked something.
            if navigationAction.navigationType == .linkActivated { NSWorkspace.shared.open(url) }
            return .cancel
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

    /// Schemes WebKit renders itself; anything else is handed to the system.
    static let webSchemes: Set<String> = ["http", "https", "about", "data", "blob", "file", "javascript", StartPageSchemeHandler.scheme]

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse) async -> WKNavigationResponsePolicy {
        let disposition = (navigationResponse.response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Disposition") ?? ""
        if !navigationResponse.canShowMIMEType || disposition.lowercased().hasPrefix("attachment") { return .download }
        return .allow
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = self
    }

    // MARK: Downloads (to ~/Downloads, never overwriting)

    private var downloadObservations: [ObjectIdentifier: NSKeyValueObservation] = [:]
    private var downloadNames: [ObjectIdentifier: String] = [:]
    private var downloadPaths: [ObjectIdentifier: URL] = [:]

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String) async -> URL? {
        let folder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        let destination = Self.uniqueDestination(in: folder, for: suggestedFilename)
        let id = ObjectIdentifier(download)
        downloadNames[id] = destination.lastPathComponent
        downloadPaths[id] = destination
        downloadObservations[id] = download.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
            let fraction = progress.fractionCompleted
            MainActor.assumeIsolated { self?.downloadChanged(id, state: "downloading", fraction: fraction) }
        }
        downloadChanged(id, state: "downloading", fraction: 0)
        return destination
    }

    func downloadDidFinish(_ download: WKDownload) {
        let id = ObjectIdentifier(download)
        downloadChanged(id, state: "done", fraction: 1)
        SoundEffects.shared.play(.complete)
        forget(id)
    }

    func download(_ download: WKDownload, didFailWithError error: any Error, resumeData: Data?) {
        let id = ObjectIdentifier(download)
        downloadChanged(id, state: "failed", fraction: 0)
        SoundEffects.shared.play(.error)
        forget(id)
    }

    private func downloadChanged(_ id: ObjectIdentifier, state: String, fraction: Double) {
        let name = downloadNames[id] ?? "file"
        statusText = switch state {
        case "done": "Download complete: \(name)"
        case "failed": "Download failed: \(name)"
        default: "Downloading \(name)… \(Int(fraction * 100))%"
        }
        onDownload?(["name": name, "fraction": fraction, "state": state, "path": downloadPaths[id]?.path ?? ""])
        scheduleChange()
    }

    private func forget(_ id: ObjectIdentifier) {
        downloadObservations[id] = nil
        downloadNames[id] = nil
        downloadPaths[id] = nil
    }

    /// "file.zip", then "file 2.zip", "file 3.zip"… so downloads never overwrite each other.
    static func uniqueDestination(in folder: URL, for suggested: String) -> URL {
        let safe = suggested.replacingOccurrences(of: "/", with: "-").trimmingCharacters(in: .whitespaces)
        let name = safe.isEmpty ? "download" : safe
        var candidate = folder.appendingPathComponent(name)
        let base = (name as NSString).deletingPathExtension, ext = (name as NSString).pathExtension
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent(ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)")
            n += 1
        }
        return candidate
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

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let created = onCreateWebView?(configuration, navigationAction) { return created }
        webView.load(navigationAction.request)
        return nil
    }

    func webViewDidClose(_ webView: WKWebView) {
        onCloseRequest?()
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo) async {
        let alert = NSAlert()
        alert.messageText = frame.securityOrigin.host.isEmpty ? "Dialup" : frame.securityOrigin.host
        alert.informativeText = message
        if let window = webView.window { _ = await alert.beginSheetModal(for: window) } else { alert.runModal() }
    }

    /// `<input type=file>`: without this, file pickers silently do nothing in WKWebView.
    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame frame: WKFrameInfo) async -> [URL]? {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.canChooseFiles = true
        guard let window = webView.window else { return panel.runModal() == .OK ? panel.urls : nil }
        return await panel.beginSheetModal(for: window) == .OK ? panel.urls : nil
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?,
                 initiatedByFrame frame: WKFrameInfo) async -> String? {
        let alert = NSAlert()
        alert.messageText = frame.securityOrigin.host.isEmpty ? "Dialup" : frame.securityOrigin.host
        alert.informativeText = prompt
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.stringValue = defaultText ?? ""
        alert.accessoryView = field
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        let response = if let window = webView.window { await alert.beginSheetModal(for: window) } else { alert.runModal() }
        return response == .alertFirstButtonReturn ? field.stringValue : nil
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
