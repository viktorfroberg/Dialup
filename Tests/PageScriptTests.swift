import WebKit
import XCTest
@testable import Dialup

/// Runs the real Dial-up Mode page script in a WKWebView.
@MainActor
final class PageScriptTests: XCTestCase {
    private static let timeout: Duration = .seconds(15)

    func testImageLoadedWhileDetachedStillAppears() async throws {
        let script = DialupModePageScript()
        let config = PageConfiguration.make(hoverHandler: HoverLinkHandler(), dialupModeScript: script)
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 400, height: 300), configuration: config)
        script.apply(DialupModeSettings(enabled: true, connection: .dsl), to: [webView], skin: .luna)

        let delegate = LoadDelegate()
        webView.navigationDelegate = delegate
        // A preloaded image (new Image + onload → append) never fires a document-level load event.
        webView.loadHTMLString("""
        <body><script>
          const img = new Image();
          img.onload = () => { img.id = 'late'; document.body.appendChild(img); };
          img.src = "data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' width='40' height='40'/>";
        </script></body>
        """, baseURL: URL(string: "https://example.com/"))
        try await delegate.waitForLoad()

        let visible = await poll(webView, until: """
            (() => { const i = document.getElementById('late'); return !!i && getComputedStyle(i).visibility === 'visible'; })()
            """)
        XCTAssertTrue(visible, "a detached-then-inserted image must not stay hidden")

        // The page script ran without a syntax error: its style sheet (incl. retro scrollbars) is in the page.
        let hasScrollbars = await poll(webView, until: """
            (document.getElementById('dialup-mode-style')?.textContent || '').includes('::-webkit-scrollbar-button:vertical:start:decrement')
            """)
        XCTAssertTrue(hasScrollbars, "retro scrollbar CSS missing")
        withExtendedLifetime(delegate) {}
    }

    /// Re-evaluates `condition` (a JS expression returning a boolean) until it's true or time runs out.
    private func poll(_ webView: WKWebView, until condition: String) async -> Bool {
        let deadline = ContinuousClock.now + Self.timeout
        while ContinuousClock.now < deadline {
            if (try? await webView.evaluateJavaScript(condition, contentWorld: .page)) as? Bool == true { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return false
    }
}

@MainActor
private final class LoadDelegate: NSObject, WKNavigationDelegate {
    private var finished = false
    private var failure: (any Error)?

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finished = true }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) { failure = error }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        failure = error
    }

    func waitForLoad(timeout: Duration = .seconds(15)) async throws {
        let deadline = ContinuousClock.now + timeout
        while !finished {
            if let failure { throw failure }
            guard ContinuousClock.now < deadline else { throw URLError(.timedOut) }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}
