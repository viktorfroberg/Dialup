import WebKit

/// Opens new browser windows. Injected into each window (the app delegate implements it), so a
/// window can open others (tabs turned off, popups) without reaching for `NSApp.delegate`.
@MainActor
protocol BrowserWindowOpening: AnyObject {
    /// A new window with these tabs; empty = the home page.
    func openWindow(urls: [URL])

    /// window.open / target=_blank with tabs turned off: a new window whose first tab uses
    /// WebKit's configuration (required for the opener relationship). Returns that tab's web view.
    func openPopupWindow(configuration: WKWebViewConfiguration) -> WKWebView?
}
