import WebKit
import XCTest
@testable import Dialup

final class AddressResolverTests: XCTestCase {
    func resolve(_ s: String) -> String? { AddressResolver.resolve(s)?.absoluteString }

    func testFullURLsPassThrough() {
        XCTAssertEqual(resolve("http://example.com/a?b=1"), "http://example.com/a?b=1")
        XCTAssertEqual(resolve("  https://example.com  "), "https://example.com")
        XCTAssertEqual(resolve("about:blank"), "about:blank")
    }

    func testBareHostsGetHTTPS() {
        XCTAssertEqual(resolve("example.com"), "https://example.com")
        XCTAssertEqual(resolve("en.wikipedia.org/wiki/Netscape"), "https://en.wikipedia.org/wiki/Netscape")
    }

    func testLocalHostsGetHTTP() {
        XCTAssertEqual(resolve("localhost:3000"), "http://localhost:3000")
        XCTAssertEqual(resolve("192.168.1.1"), "http://192.168.1.1")
        XCTAssertEqual(resolve("10.0.0.2:8080/x"), "http://10.0.0.2:8080/x")
    }

    func testEverythingElseSearches() {
        XCTAssertEqual(resolve("hello world"), "https://duckduckgo.com/?q=hello%20world")
        XCTAssertEqual(resolve("a&b=c"), "https://duckduckgo.com/?q=a%26b%3Dc")
        XCTAssertEqual(resolve("dialup"), "https://duckduckgo.com/?q=dialup")
        XCTAssertEqual(resolve("what is 3.5 mm"), "https://duckduckgo.com/?q=what%20is%203.5%20mm")
    }

    func testEmptyIsNil() {
        XCTAssertNil(resolve("   "))
    }
}

@MainActor
final class SchemeHandlerTests: XCTestCase {
    var root: URL!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let chrome = root.appendingPathComponent("chrome")
        try FileManager.default.createDirectory(at: chrome.appendingPathComponent("js"), withIntermediateDirectories: true)
        try "<html>".write(to: chrome.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
        try "x".write(to: chrome.appendingPathComponent("js/main.js"), atomically: true, encoding: .utf8)
        try "secret".write(to: root.appendingPathComponent("secret.txt"), atomically: true, encoding: .utf8)
    }

    func handler() -> DialupSchemeHandler {
        DialupSchemeHandler(roots: ["chrome": [root.appendingPathComponent("chrome")]])
    }

    func testResolvesFiles() {
        XCTAssertEqual(handler().resolve(URL(string: "dialup://chrome/")!)?.lastPathComponent, "index.html")
        XCTAssertEqual(handler().resolve(URL(string: "dialup://chrome/js/main.js")!)?.lastPathComponent, "main.js")
    }

    func testRefusesTraversalAndUnknownAreas() {
        XCTAssertNil(handler().resolve(URL(string: "dialup://chrome/../secret.txt")!))
        XCTAssertNil(handler().resolve(URL(string: "dialup://chrome/%2E%2E/secret.txt")!))
        XCTAssertNil(handler().resolve(URL(string: "dialup://skins/index.html")!))
        XCTAssertNil(handler().resolve(URL(string: "https://chrome/index.html")!))
    }

    func testRefusesSymlinksPointingOutside() throws {
        let link = root.appendingPathComponent("chrome/leak.txt")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: root.appendingPathComponent("secret.txt"))
        XCTAssertNil(handler().resolve(URL(string: "kikare://chrome/leak.txt".replacingOccurrences(of: "kikare", with: "dialup"))!))
    }

    func testMimeTypes() {
        XCTAssertTrue(DialupSchemeHandler.mimeType(forExtension: "js").hasPrefix("text/javascript"))
        XCTAssertEqual(DialupSchemeHandler.mimeType(forExtension: "svg"), "image/svg+xml")
    }
}

@MainActor
final class ConfigurationIsolationTests: XCTestCase {
    /// The core security rule: web pages never get the dialup:// scheme or the chrome's script controller.
    func testPagesDoNotGetChromePowers() {
        let chrome = ChromeConfiguration.make(bridge: ChromeBridge(), schemeHandler: DialupSchemeHandler(roots: [:]))
        let page = PageConfiguration.make(hoverHandler: HoverLinkHandler(), dialupModePage: DialupModePage())

        XCTAssertNotNil(chrome.urlSchemeHandler(forURLScheme: DialupSchemeHandler.scheme))
        XCTAssertNil(page.urlSchemeHandler(forURLScheme: DialupSchemeHandler.scheme))
        XCTAssertNotNil(page.urlSchemeHandler(forURLScheme: StartPageSchemeHandler.scheme))
        XCTAssertNil(chrome.urlSchemeHandler(forURLScheme: StartPageSchemeHandler.scheme))
        XCTAssertFalse(chrome.userContentController === page.userContentController)
        XCTAssertFalse(page.userContentController.userScripts.contains { $0.source.contains("messageHandlers.host") })
    }
}

@MainActor
final class DialupModeTests: XCTestCase {
    func testMergeAppliesKnownKeysAndIgnoresJunk() {
        let base = DialupModeSettings()
        let merged = base.merging(["enabled": true, "colors": "thousands", "bogus": 1])
        XCTAssertTrue(merged.enabled)
        XCTAssertEqual(merged.colors, .thousands)
        XCTAssertEqual(merged.resolution, base.resolution)
    }

    func testInvalidValueKeepsCurrentSetting() {
        let current = DialupModeSettings(colors: .websafe)
        XCTAssertEqual(current.merging(["colors": "ultraviolet"]).colors, .websafe)
    }

    func testDefaultsKeepTextSharp() {
        // The default and both presets must not filter the page (text stays readable).
        var s = DialupModeSettings()
        s.enabled = true
        XCTAssertTrue(DialupModeRenderer.filters(for: s, backingScale: 2).isEmpty)
        for preset in DialupModeSettings.presets.values {
            XCTAssertTrue(DialupModeRenderer.filters(for: preset, backingScale: 2).isEmpty)
        }
    }

    func testHardModeFilters() {
        var s = DialupModeSettings(enabled: true, colors: .websafeDither, resolution: .classic)
        XCTAssertEqual(DialupModeRenderer.filters(for: s, backingScale: 2).count, 3) // pixellate, dither, posterize
        s.enabled = false
        XCTAssertTrue(DialupModeRenderer.filters(for: s, backingScale: 2).isEmpty)
    }

    func testConnectionSpeedOnlyWhenEnabled() {
        var s = DialupModeSettings(connection: .modem56k)
        XCTAssertEqual(s.bitsPerSecond, 0)
        s.enabled = true
        XCTAssertEqual(s.bitsPerSecond, 53_333)
        XCTAssertEqual(DialupModePage.config(for: s)["gifImages"] as? Bool, true)
    }

    func testClassicPixelsAreNoOpOnNonRetina() {
        let s = DialupModeSettings(enabled: true, colors: .millions, resolution: .classic, scanlines: false, oldFonts: false)
        XCTAssertTrue(DialupModeRenderer.filters(for: s, backingScale: 1).isEmpty)
        XCTAssertEqual(DialupModeRenderer.filters(for: s, backingScale: 2).first?.name, "CIPixellate")
    }
}

final class DialupModeSettingsCompatTests: XCTestCase {
    func testOldSavedSettingsStillDecode() throws {
        let old = #"{"enabled":true,"colors":"websafe","resolution":"classic","scanlines":true,"oldFonts":false}"#
        let s = try JSONDecoder().decode(DialupModeSettings.self, from: Data(old.utf8))
        XCTAssertTrue(s.enabled)
        XCTAssertEqual(s.colors, .websafe)
        XCTAssertFalse(s.includeChrome)
    }
}

final class PreferencesTests: XCTestCase {
    func testSanitizesValues() {
        let p = Preferences().merging([
            "skin": "vista", "searchEngine": "altavista", "name": "  Viktor  ",
            "quickLinks": [["title": "", "url": "example.com"], ["title": "Bad", "url": "javascript:alert(1)"]],
        ])
        XCTAssertEqual(p.skin, Preferences().skin)
        XCTAssertEqual(p.searchEngine, "duckduckgo")
        XCTAssertEqual(p.name, "Viktor")
        XCTAssertEqual(p.quickLinks, [QuickLink(title: "example.com", url: "https://example.com")])
    }

    func testHomePage() {
        XCTAssertEqual(Preferences().homeURL, Preferences.startURL)
        XCTAssertEqual(Preferences().merging(["homePage": "example.com"]).homeURL.absoluteString, "https://example.com")
    }

    @MainActor
    func testStartConfigIsValidJS() {
        var p = Preferences()
        p.name = "</script><b>"
        let js = StartPageSchemeHandler.configScript(p)
        XCTAssertTrue(js.hasPrefix("window.DIALUP_START = {"))
        XCTAssertTrue(js.contains("<\\/script>"))
    }
}

@MainActor
final class PageTouchesTests: XCTestCase {
    func testSafeTouchesOnByDefaultRiskyOff() {
        var s = DialupModeSettings()
        s.enabled = true
        let cfg = DialupModePage.config(for: s, skin: "aqua")
        XCTAssertEqual(cfg["retroPage"] as? Bool, true)
        XCTAssertEqual(cfg["squareCorners"] as? Bool, true)
        XCTAssertEqual(cfg["noShadows"] as? Bool, false)
        XCTAssertEqual(cfg["noAnimations"] as? Bool, false)
        XCTAssertEqual(cfg["underlineLinks"] as? Bool, false)
        XCTAssertEqual(cfg["skin"] as? String, "aqua")
    }

    func testNothingInjectedWhenDisabled() {
        let cfg = DialupModePage.config(for: DialupModeSettings())
        XCTAssertEqual(cfg["retroPage"] as? Bool, false)
        XCTAssertEqual(cfg["squareCorners"] as? Bool, false)
    }

    func testFirstRunDefaults() {
        XCTAssertEqual(Preferences().skin, "luna")
        XCTAssertFalse(Preferences().onboarded)
    }
}

@MainActor
final class BoundaryTests: XCTestCase {
    func testBridgeOnlyAcceptsChromeMainFrame() {
        XCTAssertTrue(ChromeBridge.accepts(isMainFrame: true, originProtocol: "dialup"))
        XCTAssertFalse(ChromeBridge.accepts(isMainFrame: false, originProtocol: "dialup"))
        XCTAssertFalse(ChromeBridge.accepts(isMainFrame: true, originProtocol: "https"))
        XCTAssertFalse(ChromeBridge.accepts(isMainFrame: true, originProtocol: "dialup-start"))
    }

    func testOnlyTheStartPageMayOpenSettings() {
        XCTAssertTrue(Tab.isTrustedCustomize(sourceProtocol: "dialup-start", targetIsMainFrame: true))
        XCTAssertFalse(Tab.isTrustedCustomize(sourceProtocol: "https", targetIsMainFrame: true))
        XCTAssertFalse(Tab.isTrustedCustomize(sourceProtocol: "dialup-start", targetIsMainFrame: false))
    }

    func testStartConfigOnlyForTheStartPage() {
        XCTAssertTrue(StartPageSchemeHandler.allowsConfig(mainDocumentURL: URL(string: "dialup-start://home/")))
        XCTAssertFalse(StartPageSchemeHandler.allowsConfig(mainDocumentURL: URL(string: "http://evil.example/")))
        XCTAssertFalse(StartPageSchemeHandler.allowsConfig(mainDocumentURL: nil))
        XCTAssertFalse(StartPageSchemeHandler.emptyConfig.contains("name"))
    }

    func testHomePageAndLinksNeverBecomeSearches() {
        XCTAssertNil(AddressResolver.resolveAddress("hello world"))
        XCTAssertEqual(Preferences().merging(["homePage": "not a url"]).homePage, "start")
        XCTAssertTrue(Preferences().merging(["quickLinks": [["title": "x", "url": "two words"]]]).quickLinks.isEmpty)
    }

    func testCatalogCarriesTheOnlyCopyOfPresets() {
        let presets = Preferences.catalog["dialupPresets"] as? [String: [String: Any]]
        XCTAssertEqual(Set(presets?.keys ?? [:].keys), ["1998", "2003"])
        XCTAssertEqual(presets?["1998"]?["connection"] as? String, "modem56k")
        XCTAssertEqual(Preferences.catalog["pictureCapMs"] as? Int, DialupModePage.pictureCapMs)
    }

    func testOnboardedSurvivesMerge() {
        XCTAssertTrue(Preferences().merging(["onboarded": true]).onboarded)
    }
}

/// Runs the real Dial-up Mode page script in a WKWebView.
@MainActor
final class PageScriptTests: XCTestCase {
    func testImageLoadedWhileDetachedStillAppears() async throws {
        let page = DialupModePage()
        let config = PageConfiguration.make(hoverHandler: HoverLinkHandler(), dialupModePage: page)
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 400, height: 300), configuration: config)
        var settings = DialupModeSettings()
        settings.enabled = true
        settings.connection = .dsl
        page.apply(settings, to: [webView], skin: "luna")

        let loaded = expectation(description: "loaded")
        let delegate = LoadDelegate { loaded.fulfill() }
        webView.navigationDelegate = delegate
        // A preloaded image (new Image + onload → append) never fires a document-level load event.
        webView.loadHTMLString("""
        <body><script>
          const img = new Image();
          img.onload = () => { img.id = 'late'; document.body.appendChild(img); };
          img.src = "data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' width='40' height='40'/>";
        </script></body>
        """, baseURL: URL(string: "https://example.com/"))
        await fulfillment(of: [loaded], timeout: 10)

        var visible = false
        for _ in 0..<40 where !visible {
            try await Task.sleep(for: .milliseconds(100))
            let result = try? await webView.evaluateJavaScript(
                "(() => { const i = document.getElementById('late'); return !!i && getComputedStyle(i).visibility === 'visible'; })()")
            visible = (result as? Bool) == true
        }
        XCTAssertTrue(visible, "a detached-then-inserted image must not stay hidden")
        // The page script ran without a syntax error: its style sheet (incl. retro scrollbars) is in the page.
        let css = try? await webView.evaluateJavaScript("document.getElementById('dialup-mode-style')?.textContent || ''") as? String
        XCTAssertTrue(css?.contains("::-webkit-scrollbar-button:vertical:start:decrement") == true, "retro scrollbar CSS missing")
        _ = delegate
    }
}

private final class LoadDelegate: NSObject, WKNavigationDelegate {
    let done: () -> Void
    init(_ done: @escaping () -> Void) { self.done = done }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { done() }
}

final class BookmarksTests: XCTestCase {
    func testRoundTripAndFiltering() {
        let html = """
        <DL><p><DT><H3>Folder</H3><DL><p>
        <DT><A HREF="https://example.com/a?x=1&amp;y=2" ADD_DATE="1">Example &amp; Co</A>
        <DT><A HREF="javascript:alert(1)">Bad</A>
        <DT><a href="http://old.example/">Old <b>site</b></a>
        </DL><p></DL>
        """
        let parsed = Bookmarks.parse(html)
        XCTAssertEqual(parsed, [
            QuickLink(title: "Example & Co", url: "https://example.com/a?x=1&y=2"),
            QuickLink(title: "Old site", url: "http://old.example/"),
        ])
        XCTAssertEqual(Bookmarks.parse(Bookmarks.export(parsed)), parsed)
    }

    func testTabsPreferenceDefaults() {
        XCTAssertTrue(Preferences().tabs)
        XCTAssertFalse(Preferences().merging(["tabs": false]).tabs)
    }
}
