import XCTest
@testable import Dialup

@MainActor
final class SchemeHandlerTests: XCTestCase {
    private var root: URL!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let chrome = root.appendingPathComponent("chrome")
        try FileManager.default.createDirectory(at: chrome.appendingPathComponent("js"), withIntermediateDirectories: true)
        try "<html>".write(to: chrome.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
        try "x".write(to: chrome.appendingPathComponent("js/main.js"), atomically: true, encoding: .utf8)
        try "secret".write(to: root.appendingPathComponent("secret.txt"), atomically: true, encoding: .utf8)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func handler() -> DialupSchemeHandler {
        DialupSchemeHandler(roots: ["chrome": [root.appendingPathComponent("chrome")]])
    }

    private func resolve(_ url: String) -> URL? {
        URL(string: url).flatMap { handler().resolve($0) }
    }

    func testResolvesFiles() {
        XCTAssertEqual(resolve("dialup://chrome/")?.lastPathComponent, "index.html")
        XCTAssertEqual(resolve("dialup://chrome/js/main.js")?.lastPathComponent, "main.js")
    }

    func testRefusesTraversalAndUnknownAreas() {
        XCTAssertNil(resolve("dialup://chrome/../secret.txt"))
        XCTAssertNil(resolve("dialup://chrome/%2E%2E/secret.txt"))
        XCTAssertNil(resolve("dialup://skins/index.html"))
        XCTAssertNil(resolve("https://chrome/index.html"))
    }

    func testRefusesSymlinksPointingOutside() throws {
        let link = root.appendingPathComponent("chrome/leak.txt")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: root.appendingPathComponent("secret.txt"))
        XCTAssertNil(resolve("dialup://chrome/leak.txt"))
    }

    func testMimeTypes() {
        XCTAssertTrue(DialupSchemeHandler.mimeType(forExtension: "js").hasPrefix("text/javascript"))
        XCTAssertEqual(DialupSchemeHandler.mimeType(forExtension: "svg"), "image/svg+xml")
        XCTAssertEqual(DialupSchemeHandler.mimeType(forExtension: "exe"), "application/octet-stream")
    }
}
