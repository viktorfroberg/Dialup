import XCTest
@testable import Dialup

final class AddressResolverTests: XCTestCase {
    private func resolve(_ s: String) -> String? { AddressResolver.resolve(s)?.absoluteString }

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

    func testStartPageAliasesOnlyWithAStartURL() {
        let start = Preferences.startURL
        XCTAssertEqual(AddressResolver.resolve(" About:Home ", startURL: start), start)
        XCTAssertEqual(AddressResolver.resolve("about:start", startURL: start), start)
        XCTAssertEqual(resolve("about:home"), "about:home") // no start URL given: passes through
    }

    func testSearchURLEncodesQueriesForAnyEngine() {
        let google = SearchEngine.google.template
        XCTAssertEqual(AddressResolver.searchURL(for: "a b&c", template: google)?.absoluteString,
                       "https://www.google.com/search?q=a%20b%26c")
        XCTAssertEqual(AddressResolver.searchURL(for: "räksmörgås")?.absoluteString,
                       "https://duckduckgo.com/?q=r%C3%A4ksm%C3%B6rg%C3%A5s")
        XCTAssertNil(AddressResolver.searchURL(for: "  "))
    }
}
