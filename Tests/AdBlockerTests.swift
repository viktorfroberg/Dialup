import XCTest
@testable import Dialup

@MainActor
final class AdBlockerTests: XCTestCase {
    func testRulesCompile() async {
        let list = await AdBlocker.ruleList()
        XCTAssertNotNil(list, "content rule list must compile")
        let again = await AdBlocker.ruleList()
        XCTAssertTrue(list === again, "compiled once per launch")
    }

    func testIdentifierFollowsTheRules() {
        XCTAssertTrue(AdBlocker.identifier.hasPrefix("dialup-adblock-"))
        XCTAssertEqual(AdBlocker.identifier, AdBlocker.identifier, "stable within a launch")
    }

    /// The url-filter syntax content blockers use is a regex subset NSRegularExpression understands.
    private func blocks(_ domain: String, _ url: String) throws -> Bool {
        let regex = try NSRegularExpression(pattern: AdBlocker.urlFilter(for: domain), options: .caseInsensitive)
        return regex.firstMatch(in: url, range: NSRange(url.startIndex..., in: url)) != nil
    }

    func testURLFilterMatchesTheDomainAndSubdomains() throws {
        XCTAssertTrue(try blocks("doubleclick.net", "https://doubleclick.net/ad.js"))
        XCTAssertTrue(try blocks("doubleclick.net", "https://securepubads.g.doubleclick.net/tag/js/gpt.js"))
        XCTAssertTrue(try blocks("doubleclick.net", "http://ad.doubleclick.net:8080/x"))
        XCTAssertTrue(try blocks("doubleclick.net", "HTTPS://AD.DOUBLECLICK.NET/X"))
    }

    func testURLFilterLeavesLookalikesAlone() throws {
        XCTAssertFalse(try blocks("doubleclick.net", "https://notdoubleclick.net/"))
        XCTAssertFalse(try blocks("doubleclick.net", "https://doubleclick.net.example.com/"))
        XCTAssertFalse(try blocks("doubleclick.net", "https://example.com/?ref=doubleclick.net/"))
        XCTAssertFalse(try blocks("doubleclick.net", "https://doubleclickxnet/"), "the dot is literal")
        XCTAssertFalse(try blocks("media.net", "https://socialmedia.network/"))
    }
}
