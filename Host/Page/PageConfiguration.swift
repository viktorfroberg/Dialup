import Foundation
import WebKit

/// Configuration for web pages. Deliberately has NO host bridge and NO dialup:// scheme
/// (only the static, bridge-less dialup-start:// start page).
/// The only addition is a hover-link script in an isolated content world, which page
/// scripts can't see, so the status bar can show link targets.
@MainActor
enum PageConfiguration {
    /// Many sites check for "Version/x Safari"; a bare WKWebView user agent doesn't include it.
    static let userAgentSuffix = "Version/26.0 Safari/605.1.15"

    static func make(hoverHandler: HoverLinkHandler, dialupModePage: DialupModePage) -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.applicationNameForUserAgent = userAgentSuffix
        config.preferences.isElementFullscreenEnabled = true
        config.setURLSchemeHandler(StartPageSchemeHandler(), forURLScheme: StartPageSchemeHandler.scheme)

        let world = WKContentWorld.world(name: "dialup-hover")
        config.userContentController.addUserScript(WKUserScript(
            source: HoverLinkHandler.script,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false,
            in: world
        ))
        config.userContentController.add(hoverHandler, contentWorld: world, name: HoverLinkHandler.name)
        dialupModePage.install(on: config.userContentController)
        return config
    }
}

@MainActor
final class HoverLinkHandler: NSObject, WKScriptMessageHandler {
    static let name = "dialupHover"
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
