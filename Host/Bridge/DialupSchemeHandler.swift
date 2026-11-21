import Foundation
import WebKit

/// Serves the browser UI from `dialup://<area>/<path>`.
/// Only the chrome web view has this handler. Pages can't load dialup:// URLs.
@MainActor
final class DialupSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "dialup"

    /// area ("chrome", later "skins", "toolbars") → folders searched in order (user folder first).
    private let roots: [String: [URL]]
    private let acceptedScheme: String

    init(roots: [String: [URL]], scheme: String = DialupSchemeHandler.scheme) {
        self.roots = roots
        self.acceptedScheme = scheme
    }

    static func bundled() -> DialupSchemeHandler {
        let resources = Bundle.main.resourceURL!
        return DialupSchemeHandler(roots: ["chrome": [resources.appendingPathComponent("Chrome")]])
    }

    func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
        guard let url = task.request.url,
              let file = resolve(url),
              let data = try? Data(contentsOf: file) else {
            task.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        let response = HTTPURLResponse(
            url: url, statusCode: 200, httpVersion: "HTTP/1.1",
            headerFields: [
                "Content-Type": Self.mimeType(forExtension: file.pathExtension),
                "Cache-Control": "no-cache",
            ]
        )!
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {}

    /// Maps a dialup:// URL to a file. Refuses anything that escapes its root folder.
    func resolve(_ url: URL) -> URL? {
        guard url.scheme == acceptedScheme, let area = url.host, let bases = roots[area] else { return nil }
        let path = (url.path.isEmpty || url.path == "/") ? "/index.html" : url.path
        for base in bases {
            let root = base.standardizedFileURL.path
            let candidate = base.appendingPathComponent(path).standardizedFileURL
            guard candidate.path.hasPrefix(root + "/") else { continue }
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    static func mimeType(forExtension ext: String) -> String {
        switch ext.lowercased() {
        case "html", "htm": "text/html; charset=utf-8"
        case "css": "text/css; charset=utf-8"
        case "js", "mjs": "text/javascript; charset=utf-8"
        case "json": "application/json; charset=utf-8"
        case "svg": "image/svg+xml"
        case "png": "image/png"
        case "gif": "image/gif"
        case "jpg", "jpeg": "image/jpeg"
        case "woff2": "font/woff2"
        default: "application/octet-stream"
        }
    }
}
