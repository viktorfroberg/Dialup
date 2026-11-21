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
        let page = PageConfiguration.make(hoverHandler: HoverLinkHandler())

        XCTAssertNotNil(chrome.urlSchemeHandler(forURLScheme: DialupSchemeHandler.scheme))
        XCTAssertNil(page.urlSchemeHandler(forURLScheme: DialupSchemeHandler.scheme))
        XCTAssertFalse(chrome.userContentController === page.userContentController)
        XCTAssertFalse(page.userContentController.userScripts.contains { $0.source.contains("messageHandlers.host") })
    }
}

@MainActor
final class ExtremeModeTests: XCTestCase {
    func testMergeAppliesKnownKeysAndIgnoresJunk() {
        let base = ExtremeSettings()
        let merged = base.merging(["enabled": true, "colors": "thousands", "bogus": 1])
        XCTAssertTrue(merged.enabled)
        XCTAssertEqual(merged.colors, .thousands)
        XCTAssertEqual(merged.resolution, base.resolution)
    }

    func testInvalidValueKeepsSettings() {
        let base = ExtremeSettings()
        XCTAssertEqual(base.merging(["colors": "ultraviolet"]), base)
    }

    func testDisabledMeansNoFilters() {
        var s = ExtremeSettings.presets["1998"]!
        XCTAssertEqual(ExtremeRenderer.filters(for: s, backingScale: 2).count, 3) // pixellate, dither, posterize
        s.enabled = false
        XCTAssertTrue(ExtremeRenderer.filters(for: s, backingScale: 2).isEmpty)
    }

    func testClassicPixelsAreNoOpOnNonRetina() {
        let s = ExtremeSettings(enabled: true, colors: .millions, resolution: .classic, scanlines: false, oldFonts: false)
        XCTAssertTrue(ExtremeRenderer.filters(for: s, backingScale: 1).isEmpty)
        XCTAssertEqual(ExtremeRenderer.filters(for: s, backingScale: 2).first?.name, "CIPixellate")
    }
}
