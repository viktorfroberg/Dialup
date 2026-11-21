import XCTest
@testable import Dialup

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

    func testExportEscapesHTML() {
        let html = Bookmarks.export([QuickLink(title: "<script>", url: "https://e.example/?a=\"b\"")])
        XCTAssertFalse(html.contains("<script>"))
        XCTAssertTrue(html.contains("&lt;script&gt;"))
        XCTAssertTrue(html.hasPrefix("<!DOCTYPE NETSCAPE-Bookmark-file-1>"))
    }

    /// Importing merges into the existing favorites: no duplicates, never past the cap.
    func testImportMergeSkipsDuplicatesAndRespectsTheCap() {
        var prefs = Preferences()
        let existing = prefs.quickLinks
        let file = Bookmarks.export([existing[0], QuickLink(title: "New", url: "https://new.example/")])
        let added = prefs.addFavorites(Bookmarks.parse(file))
        XCTAssertEqual(added, 1)
        XCTAssertEqual(prefs.quickLinks, existing + [QuickLink(title: "New", url: "https://new.example/")])

        let big = Bookmarks.export((0..<100).map { QuickLink(title: "Site \($0)", url: "https://site\($0).example/") })
        prefs.addFavorites(Bookmarks.parse(big))
        XCTAssertEqual(prefs.quickLinks.count, Preferences.maxFavorites)
    }
}
