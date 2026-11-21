import Foundation
import WebKit

/// Configuration for web pages. Deliberately has NO host bridge and NO kikare:// scheme.
/// The only addition is a hover-link script in an isolated content world, which page
/// scripts can't see, so the status bar can show link targets.
@MainActor
enum PageConfiguration {
    /// Many sites check for "Version/x Safari"; a bare WKWebView user agent doesn't include it.
    static let userAgentSuffix = "Version/26.0 Safari/605.1.15"

    static func make(hoverHandler: HoverLinkHandler) -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.applicationNameForUserAgent = userAgentSuffix
        config.preferences.isElementFullscreenEnabled = true

        let world = WKContentWorld.world(name: "kikare-hover")
        config.userContentController.addUserScript(WKUserScript(
            source: HoverLinkHandler.script,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false,
            in: world
        ))
        config.userContentController.add(hoverHandler, contentWorld: world, name: HoverLinkHandler.name)
        return config
    }
}

@MainActor
final class HoverLinkHandler: NSObject, WKScriptMessageHandler {
    static let name = "kikareHover"
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
        onHover?(webView, String(url.prefix(2048)))
    }
}
