import XCTest
@testable import Dialup

final class PreferencesTests: XCTestCase {
    func testFirstRunDefaults() {
        let p = Preferences()
        XCTAssertEqual(p.skin, .luna)
        XCTAssertEqual(p.searchEngine, .duckduckgo)
        XCTAssertFalse(p.onboarded)
        XCTAssertTrue(p.tabs)
        XCTAssertTrue(p.restoreSession)
        XCTAssertTrue(p.blockAds)
        XCTAssertTrue(p.checkForUpdates)
        XCTAssertEqual(p.quickLinks, Preferences.defaultLinks)
    }

    func testSanitizesValues() {
        let p = Preferences().merging([
            "skin": "vista", "searchEngine": "altavista", "name": "  Viktor  ",
            "quickLinks": [["title": "", "url": "example.com"], ["title": "Bad", "url": "javascript:alert(1)"]],
        ])
        XCTAssertEqual(p.skin, Preferences().skin)
        XCTAssertEqual(p.searchEngine, .duckduckgo)
        XCTAssertEqual(p.name, "Viktor")
        XCTAssertEqual(p.quickLinks, [QuickLink(title: "example.com", url: "https://example.com")])
    }

    func testPatchKeepsCurrentValueForInvalidFields() {
        var current = Preferences()
        current.skin = .classic
        current.searchEngine = .wikipedia
        let patched = current.merging(["skin": "vista", "searchEngine": 3, "tabs": false, "unknown": "x"])
        XCTAssertEqual(patched.skin, .classic)
        XCTAssertEqual(patched.searchEngine, .wikipedia)
        XCTAssertFalse(patched.tabs)
    }

    func testEnumsStayPlainStringsInJSON() throws {
        var p = Preferences()
        p.skin = .aqua
        p.searchEngine = .bing
        XCTAssertEqual(p.dictionary["skin"] as? String, "aqua")
        XCTAssertEqual(p.dictionary["searchEngine"] as? String, "bing")
        let decoded = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(p))
        XCTAssertEqual(decoded, p)
    }

    func testOldOrBrokenSavedPreferencesKeepTheRest() throws {
        let saved = #"{"skin":"aqua","searchEngine":"lycos","name":"Ann","tabs":"maybe"}"#
        let p = try JSONDecoder().decode(Preferences.self, from: Data(saved.utf8))
        XCTAssertEqual(p.skin, .aqua)
        XCTAssertEqual(p.searchEngine, .duckduckgo)
        XCTAssertEqual(p.name, "Ann")
        XCTAssertTrue(p.tabs)
        XCTAssertTrue(p.blockAds, "a key missing from older saves gets its default")
    }

    func testLengthCaps() {
        let p = Preferences().merging([
            "name": String(repeating: "n", count: 100),
            "quickLinks": (0..<50).map { ["title": String(repeating: "t", count: 100), "url": "https://example.com/\($0)"] },
        ])
        XCTAssertEqual(p.name.count, Preferences.maxNameLength)
        XCTAssertEqual(p.quickLinks.count, Preferences.maxFavorites)
        XCTAssertEqual(p.quickLinks.first?.title.count, Preferences.maxFavoriteTitleLength)
    }

    func testHomePage() {
        XCTAssertEqual(Preferences().homeURL, Preferences.startURL)
        XCTAssertEqual(Preferences().merging(["homePage": "example.com"]).homeURL.absoluteString, "https://example.com")
    }

    func testSearchTemplateFollowsEngine() {
        XCTAssertEqual(Preferences().merging(["searchEngine": "google"]).searchTemplate, SearchEngine.google.template)
    }

    func testBooleansSurviveMerge() {
        XCTAssertTrue(Preferences().merging(["onboarded": true]).onboarded)
        XCTAssertFalse(Preferences().merging(["tabs": false]).tabs)
        XCTAssertFalse(Preferences().merging(["blockAds": false]).blockAds)
    }

    func testAddFavoritesDedupesAndCaps() {
        var p = Preferences()
        p.quickLinks = []
        let added = p.addFavorites([
            QuickLink(title: "A", url: "https://a.example/"),
            QuickLink(title: "A again", url: "https://a.example/"),
            QuickLink(title: "B", url: "https://b.example/"),
        ])
        XCTAssertEqual(added, 2)
        XCTAssertEqual(p.quickLinks.map(\.title), ["A", "B"])

        let many = (0..<40).map { QuickLink(title: "\($0)", url: "https://example.com/\($0)") }
        XCTAssertEqual(p.addFavorites(many), Preferences.maxFavorites - 2)
        XCTAssertEqual(p.quickLinks.count, Preferences.maxFavorites)
        XCTAssertEqual(p.addFavorites([QuickLink(title: "late", url: "https://late.example/")]), 0)
    }
}

/// `catalog`: the single source of lists and constants for the chrome.
final class CatalogTests: XCTestCase {
    func testCatalogCarriesTheOnlyCopyOfPresets() {
        let presets = Preferences.catalog["dialupPresets"] as? [String: [String: Any]]
        XCTAssertEqual(Set(presets?.keys ?? [:].keys), ["1998", "2003"])
        XCTAssertEqual(presets?["1998"]?["connection"] as? String, "modem56k")
        XCTAssertEqual(Preferences.catalog["pictureCapMs"] as? Int, DialupModePageScript.pictureCapMs)
        XCTAssertEqual(Preferences.catalog["maxFavorites"] as? Int, Preferences.maxFavorites)
    }

    func testConnectionSpeedsComeFromTheConnectionEnum() {
        let speeds = Preferences.catalog["connectionSpeeds"] as? [String: Int]
        XCTAssertEqual(speeds, ["modem56k": 53_333, "isdn": 128_000, "dsl": 512_000, "off": 0])
    }

    func testSkinsAndSearchEnginesAreListedInOrder() {
        let skins = Preferences.catalog["skins"] as? [[String: String]]
        XCTAssertEqual(skins?.map { $0["id"] }, ["luna", "aqua", "classic"])
        let engines = Preferences.catalog["searchEngines"] as? [[String: String]]
        XCTAssertEqual(engines?.map { $0["id"] }, ["duckduckgo", "google", "bing", "wikipedia"])
        XCTAssertEqual(engines?.first?["name"], "DuckDuckGo")
    }
}
