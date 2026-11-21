import Foundation
import WebKit

/// Whatever carries out the chrome's commands (a browser window).
@MainActor
protocol HostCommandHandling: AnyObject {
    /// Performs the command; the result (a JSON-compatible value or nil) is the reply.
    func perform(_ command: HostCommand) -> Any?
}

/// Receives `host.call(cmd, args)` from the chrome UI, parses it into a `HostCommand` and replies.
/// Accepts messages only from the chrome's main frame on the dialup:// origin,
/// so iframes (later: toolbar plugins) can never call the host directly.
@MainActor
final class ChromeBridge: NSObject, WKScriptMessageHandlerWithReply {
    static let handlerName = "host"
    static let apiVersion = 1

    weak var handler: (any HostCommandHandling)?

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
        guard let handler else {
            replyHandler(nil, "no window")
            return
        }
        let command: HostCommand
        do {
            command = try HostCommand(cmd, body["args"] as? [String: Any] ?? [:])
        } catch {
            // Logged, not rejected: the chrome has always treated a bad call as a no-op (null reply).
            NSLog("Dialup: ignored host command: %@", String(describing: error))
            replyHandler(NSNull(), nil)
            return
        }
        replyHandler(handler.perform(command) ?? NSNull(), nil)
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
