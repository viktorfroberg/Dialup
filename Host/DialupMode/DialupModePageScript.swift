import AppKit
import WebKit

/// The in-page part of Dial-up Mode: image trickle-in, GIF-style image colours, old fonts and
/// page touches. The script itself is the bundled resource `page-script.js`.
/// Runs in an isolated content world, so page scripts can't see or tamper with it, and reports
/// `{remaining, total, url}` for the status bar.
@MainActor
final class DialupModePageScript: NSObject, WKScriptMessageHandler {
    static let world = WKContentWorld.world(name: "dialup-mode")
    static let handlerName = "dialupLoading"
    /// The global the script installs itself as; identifies our user scripts among others.
    private static let marker = "__dialupMode"
    private static let configPlaceholder = "__CFG__"
    private static let maxReportedURLLength = 300

    /// Max time one picture takes to trickle in (shared with the settings preview via the catalog).
    nonisolated static let pictureCapMs = 2500

    /// `page-script.js` from the app bundle, with the config placeholder still in it.
    nonisolated static let template: String = {
        guard let url = Bundle.main.url(forResource: "page-script", withExtension: "js"),
              let source = try? String(contentsOf: url, encoding: .utf8) else {
            assertionFailure("page-script.js is missing from the app bundle")
            return ""
        }
        return source
    }()

    /// Status updates: (web view, items remaining, items total, url being "downloaded").
    var onStatus: ((WKWebView, Int, Int, String) -> Void)?

    func install(on controller: WKUserContentController) {
        controller.add(self, contentWorld: Self.world, name: Self.handlerName)
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame,
              let body = message.body as? [String: Any],
              let webView = message.webView else { return }
        let remaining = max(0, (body["remaining"] as? NSNumber)?.intValue ?? 0)
        let total = max(0, (body["total"] as? NSNumber)?.intValue ?? 0)
        let url = String((body["url"] as? String ?? "").prefix(Self.maxReportedURLLength))
        onStatus?(webView, remaining, total, url)
    }

    /// The config object the script receives. Every effect is off unless the mode is enabled.
    static func config(for s: DialupModeSettings, skin: Skin = .luna) -> [String: Any] {
        [
            "capMs": pictureCapMs,
            "enabled": s.enabled,
            "bps": s.bitsPerSecond,
            "gifImages": s.enabled && s.colors == .gifImages,
            "oldFonts": s.enabled && s.oldFonts,
            "retroPage": s.enabled && s.retroPage,
            "squareCorners": s.enabled && s.squareCorners,
            "noShadows": s.enabled && s.noShadows,
            "noAnimations": s.enabled && s.noAnimations,
            "underlineLinks": s.enabled && s.underlineLinks,
            "skin": skin.rawValue,
        ]
    }

    static func source(for s: DialupModeSettings, skin: Skin = .luna) -> String {
        let json = (try? JSONSerialization.data(withJSONObject: config(for: s, skin: skin)))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        return template.replacingOccurrences(of: configPlaceholder, with: json)
    }

    private var lastSource: String?

    /// Installs (and live-applies) the page script. No-op when nothing relevant changed, so
    /// unrelated preference or backing-scale changes don't reinstall scripts or reset a trickle.
    /// Note: live updates reach the main frame; iframes pick up changes on their next load.
    func apply(_ s: DialupModeSettings, to webViews: [WKWebView], skin: Skin) {
        guard let first = webViews.first else { return }
        // No dark mode in 2003: pages render in light appearance while retro page touches are on.
        for webView in webViews { webView.appearance = (s.enabled && s.retroPage) ? NSAppearance(named: .aqua) : nil }
        let source = Self.source(for: s, skin: skin)
        guard source != lastSource else { return }
        let wasInstalled = lastSource != nil
        lastSource = source
        // All tabs of a window share one configuration, so one user content controller.
        let controller = first.configuration.userContentController
        let others = controller.userScripts.filter { !$0.source.contains(Self.marker) }
        controller.removeAllUserScripts()
        others.forEach(controller.addUserScript)
        if !s.enabled && !wasInstalled { return } // never enabled: nothing to undo on the page
        if s.enabled {
            controller.addUserScript(WKUserScript(source: source, injectionTime: .atDocumentStart,
                                                  forMainFrameOnly: false, in: Self.world))
        }
        for webView in webViews {
            webView.evaluateJavaScript(source, in: nil, in: Self.world, completionHandler: nil)
        }
    }
}
