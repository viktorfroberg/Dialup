import Foundation
import WebKit

/// Configuration for web pages. Deliberately has NO host bridge and NO dialup:// scheme
/// (only the static, bridge-less dialup-start:// start page).
/// The only additions are the hover-link script (so the status bar can show link targets) and the
/// Dial-up Mode page script, both in isolated content worlds that page scripts can't see.
@MainActor
enum PageConfiguration {
    /// Many sites check for "Version/x Safari"; a bare WKWebView user agent doesn't include it.
    static let userAgentSuffix = "Version/26.0 Safari/605.1.15"

    static func make(hoverHandler: HoverLinkHandler, dialupModeScript: DialupModePageScript) -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.applicationNameForUserAgent = userAgentSuffix
        config.preferences.isElementFullscreenEnabled = true
        config.setURLSchemeHandler(StartPageSchemeHandler(), forURLScheme: StartPageSchemeHandler.scheme)

        config.userContentController.addUserScript(WKUserScript(
            source: HoverLinkHandler.script,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false,
            in: HoverLinkHandler.world
        ))
        config.userContentController.add(hoverHandler, contentWorld: HoverLinkHandler.world, name: HoverLinkHandler.name)
        dialupModeScript.install(on: config.userContentController)
        return config
    }
}

/// Reports the link under the mouse (`""` when leaving a link) for the status bar.
@MainActor
final class HoverLinkHandler: NSObject, WKScriptMessageHandler {
    static let world = WKContentWorld.world(name: "dialup-hover")
    static let name = "dialupHover"
    private static let maxURLLength = 2048
    static let script = """
    (() => {
      let last = null;
      const send = (url) => {
        if (url === last) return;
        last = url;
        window.webkit.messageHandlers.\(name).postMessage(url);
      };
      document.addEventListener('mouseover', (e) => {
        const a = e.target instanceof Element ? e.target.closest('a[href]') : null;
        send(a ? a.href : '');
      }, true);
      document.addEventListener('mouseout', (e) => { if (!e.relatedTarget) send(''); }, true);
    })();
    """

    var onHover: ((WKWebView, String) -> Void)?

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let url = message.body as? String, let webView = message.webView else { return }
        onHover?(webView, String(url.prefix(Self.maxURLLength)))
    }
}
