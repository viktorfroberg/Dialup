import WebKit
import XCTest
@testable import Dialup

/// The rules that keep web pages away from the host: the bridge, the chrome's scheme and the
/// start page's personal data.
@MainActor
final class SecurityBoundaryTests: XCTestCase {
    /// The core rule: web pages never get the dialup:// scheme or the chrome's script controller.
    func testPagesDoNotGetChromePowers() {
        let chrome = ChromeConfiguration.make(bridge: ChromeBridge(), schemeHandler: DialupSchemeHandler(roots: [:]))
        let page = PageConfiguration.make(hoverHandler: HoverLinkHandler(), dialupModeScript: DialupModePageScript())

        XCTAssertNotNil(chrome.urlSchemeHandler(forURLScheme: DialupSchemeHandler.scheme))
        XCTAssertNil(page.urlSchemeHandler(forURLScheme: DialupSchemeHandler.scheme))
        XCTAssertNotNil(page.urlSchemeHandler(forURLScheme: StartPageSchemeHandler.scheme))
        XCTAssertNil(chrome.urlSchemeHandler(forURLScheme: StartPageSchemeHandler.scheme))
        XCTAssertFalse(chrome.userContentController === page.userContentController)
        XCTAssertFalse(page.userContentController.userScripts.contains { $0.source.contains("messageHandlers.host") })
    }

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

    func testStartConfigIsValidJS() {
        var p = Preferences()
        p.name = "</script><b>"
        let js = StartPageSchemeHandler.configScript(p)
        XCTAssertTrue(js.hasPrefix("window.DIALUP_START = {"))
        XCTAssertTrue(js.contains("<\\/script>"))
        XCTAssertTrue(js.contains(#""skin":"luna""#))
    }

    func testHomePageAndFavoritesNeverBecomeSearches() {
        XCTAssertNil(AddressResolver.resolveAddress("hello world"))
        XCTAssertEqual(Preferences().merging(["homePage": "not a url"]).homePage, Preferences.startPageHome)
        XCTAssertTrue(Preferences().merging(["quickLinks": [["title": "x", "url": "two words"]]]).quickLinks.isEmpty)
    }

    func testDownloadsNeverOverwrite() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        XCTAssertEqual(Tab.uniqueDestination(in: folder, for: "a.zip").lastPathComponent, "a.zip")
        try Data().write(to: folder.appendingPathComponent("a.zip"))
        XCTAssertEqual(Tab.uniqueDestination(in: folder, for: "a.zip").lastPathComponent, "a 2.zip")
        XCTAssertEqual(Tab.uniqueDestination(in: folder, for: "../../x").deletingLastPathComponent().standardizedFileURL,
                       folder.standardizedFileURL, "a suggested name can't leave the folder")
        XCTAssertEqual(Tab.uniqueDestination(in: folder, for: "  ").lastPathComponent, "download")
    }
}
