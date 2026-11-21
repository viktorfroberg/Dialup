import Foundation
import WebKit

/// Serves the built-in start page at `dialup-start://home/` to *page* web views.
/// It only serves the static files in `Start/`, plus a generated `config.js` with the
/// user's start page settings. There's no bridge to the host, and pages still can't reach dialup://.
@MainActor
final class StartPageSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "dialup-start"
    /// Clicking "Customize" on the start page navigates here; the tab intercepts it and opens settings.
    static let customizeURL = URL(string: "dialup-start://home/customize")!

    private let files: DialupSchemeHandler

    init(root: URL = Bundle.main.resourceURL!.appendingPathComponent("Start")) {
        // Reuse the path-safe file resolver with a single area ("home").
        files = DialupSchemeHandler(roots: ["home": [root]], scheme: Self.scheme)
    }

    func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
        guard let url = task.request.url else { return }
        if url.host == "home", url.path == "/config.js" {
            // Personal data (name, favourites): only for the start page itself, never for other sites.
            let config = Self.allowsConfig(mainDocumentURL: task.request.mainDocumentURL) ? Self.configScript() : Self.emptyConfig
            respond(task, url: url, mime: "text/javascript; charset=utf-8", data: Data(config.utf8))
            return
        }
        guard let file = files.resolve(url), let data = try? Data(contentsOf: file) else {
            task.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        respond(task, url: url, mime: DialupSchemeHandler.mimeType(forExtension: file.pathExtension), data: data)
    }

    func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {}

    private func respond(_ task: any WKURLSchemeTask, url: URL, mime: String, data: Data) {
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": mime, "Cache-Control": "no-cache"])!
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    static let emptyConfig = "window.DIALUP_START = {};\n"

    static func allowsConfig(mainDocumentURL: URL?) -> Bool {
        mainDocumentURL?.scheme == scheme
    }

    static func configScript(_ prefs: Preferences = PreferencesStore.shared.preferences) -> String {
        let config: [String: Any] = [
            "name": prefs.name,
            "quickLinks": prefs.quickLinks.map { ["title": $0.title, "url": $0.url] },
            "search": ["name": prefs.searchEngineName, "template": prefs.searchTemplate],
            "skin": prefs.skin,
        ]
        let json = (try? JSONSerialization.data(withJSONObject: config)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        return "window.DIALUP_START = \(json);\n"
    }
}
