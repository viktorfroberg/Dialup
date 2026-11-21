import Foundation
import WebKit

/// Receives `host.call(cmd, args)` from the chrome UI and replies.
/// Accepts messages only from the chrome's main frame on the dialup:// origin,
/// so iframes (later: toolbar plugins) can never call the host directly.
@MainActor
final class ChromeBridge: NSObject, WKScriptMessageHandlerWithReply {
    static let handlerName = "host"
    static let apiVersion = 1

    weak var controller: BrowserWindowController?

    /// Only the chrome document itself (main frame, dialup:// origin) may talk to the host.
    nonisolated static func accepts(isMainFrame: Bool, originProtocol: String) -> Bool {
        isMainFrame && originProtocol == DialupSchemeHandler.scheme
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage,
        replyHandler: @escaping @MainActor @Sendable (Any?, String?) -> Void
    ) {
        guard Self.accepts(isMainFrame: message.frameInfo.isMainFrame,
                           originProtocol: message.frameInfo.securityOrigin.protocol),
              let body = message.body as? [String: Any],
              let cmd = body["cmd"] as? String else {
            replyHandler(nil, "rejected message")
            return
        }
        guard let controller else {
            replyHandler(nil, "no window")
            return
        }
        let args = body["args"] as? [String: Any] ?? [:]
        let result = controller.handle(cmd, args)
        replyHandler(result ?? NSNull(), nil)
    }
}

/// Builds the configuration for the chrome web view: dialup:// scheme + host bridge.
/// Never reuse this for web pages.
@MainActor
enum ChromeConfiguration {
    static func make(bridge: ChromeBridge, schemeHandler: DialupSchemeHandler) -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.setURLSchemeHandler(schemeHandler, forURLScheme: DialupSchemeHandler.scheme)
        config.userContentController.addScriptMessageHandler(bridge, contentWorld: .page, name: ChromeBridge.handlerName)
        return config
    }
}
