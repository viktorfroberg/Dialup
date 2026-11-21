import XCTest
@testable import Dialup

final class HostCommandTests: XCTestCase {
    private func parse(_ cmd: String, _ args: [String: Any] = [:]) -> HostCommand? {
        try? HostCommand(cmd, args)
    }

    private func error(_ cmd: String, _ args: [String: Any] = [:]) -> HostCommand.ParseError? {
        do {
            _ = try HostCommand(cmd, args)
            return nil
        } catch {
            return error
        }
    }

    func testUnknownCommandsAreRejected() {
        XCTAssertEqual(error("formatHardDrive"), .unknownCommand("formatHardDrive"))
        XCTAssertEqual(error(""), .unknownCommand(""))
    }

    func testCommandsWithoutArguments() {
        for cmd in ["ready", "back", "forward", "reload", "stop", "home", "focusPage", "securityInfo",
                    "windowClose", "windowMinimize", "windowZoom", "windowDrag", "titlebarDoubleClick",
                    "prefsGet", "dialupModeGet", "importBookmarks", "exportBookmarks"] {
            XCTAssertNotNil(parse(cmd), cmd)
        }
    }

    func testNavigate() {
        guard case .navigate(let input) = parse("navigate", ["input": "example.com"]) else { return XCTFail() }
        XCTAssertEqual(input, "example.com")
        XCTAssertEqual(error("navigate"), .invalidArguments("navigate"))
        XCTAssertEqual(error("navigate", ["input": 42]), .invalidArguments("navigate"))
    }

    func testSearchNeedsAQuery() {
        guard case .search(let query) = parse("search", ["query": "space jam"]) else { return XCTFail() }
        XCTAssertEqual(query, "space jam")
        XCTAssertNil(parse("search", ["query": ""]))
    }

    func testSetInsetsDefaultsMissingSidesToZero() {
        guard case .setInsets(let insets) = parse("setInsets", ["top": 88, "bottom": NSNumber(value: 22.5)]) else { return XCTFail() }
        XCTAssertEqual(insets.top, 88)
        XCTAssertEqual(insets.bottom, 22.5)
        XCTAssertEqual(insets.left, 0)
        XCTAssertEqual(insets.right, 0)
    }

    func testHistoryDirectionDefaultsToBack() {
        guard case .history(let forward) = parse("history", ["direction": "forward"]) else { return XCTFail() }
        XCTAssertEqual(forward, .forward)
        guard case .history(let fallback) = parse("history", ["direction": "sideways"]) else { return XCTFail() }
        XCTAssertEqual(fallback, .back)
    }

    func testGoHistoryNeedsAnOffset() {
        guard case .goHistory(let offset) = parse("goHistory", ["offset": -2]) else { return XCTFail() }
        XCTAssertEqual(offset, -2)
        XCTAssertNil(parse("goHistory", ["offset": "two"]))
    }

    func testClearDataUnknownKindIsRejectedNotWipeEverything() {
        guard case .clearData(let missing) = parse("clearData") else { return XCTFail() }
        XCTAssertEqual(missing, .cache)
        guard case .clearData(let all) = parse("clearData", ["what": "all"]) else { return XCTFail() }
        XCTAssertEqual(all, .all)
        XCTAssertEqual(error("clearData", ["what": "cookies"]), .invalidArguments("clearData"))
    }

    func testWaybackYearsAreBounded() {
        guard case .wayback(let year) = parse("wayback", ["year": 1999]) else { return XCTFail() }
        XCTAssertEqual(year, 1999)
        XCTAssertNil(parse("wayback", ["year": 1066]))
        XCTAssertNil(parse("wayback", [:]))
    }

    func testFind() {
        guard case .find(let text, let backwards, let caseSensitive) = parse("find", ["text": "dial", "backwards": true])
        else { return XCTFail() }
        XCTAssertEqual(text, "dial")
        XCTAssertTrue(backwards)
        XCTAssertFalse(caseSensitive)
        XCTAssertNil(parse("find", ["text": ""]))
    }

    func testTabsByID() {
        guard case .closeTab(let id) = parse("closeTab", ["id": 7]) else { return XCTFail() }
        XCTAssertEqual(id, 7)
        XCTAssertNil(parse("selectTab", [:]))
        guard case .newTab(let none) = parse("newTab") else { return XCTFail() }
        XCTAssertNil(none)
        guard case .newTab(let url) = parse("newTab", ["url": "example.com"]) else { return XCTFail() }
        XCTAssertEqual(url, "example.com")
    }

    func testMenuActionsAreAllowlisted() {
        guard case .menuAction(let action) = parse("menuAction", ["action": "paste"]) else { return XCTFail() }
        XCTAssertEqual(action, .paste)
        XCTAssertNil(parse("menuAction", ["action": "terminate"]))
    }

    func testSoundsExceptTheModem() {
        guard case .sound(let sound) = parse("sound", ["name": "ding"]) else { return XCTFail() }
        XCTAssertEqual(sound, .ding)
        XCTAssertNil(parse("sound", ["name": "modem"]), "the handshake belongs to Dial-up Mode")
        XCTAssertNil(parse("sound", ["name": "fanfare"]))
        guard case .soundSet(let enabled) = parse("soundSet") else { return XCTFail() }
        XCTAssertTrue(enabled)
    }

    func testAddFavoriteTitleDefaultsToURL() {
        guard case .addFavorite(let title, let url) = parse("addFavorite", ["url": "https://e.example/"]) else { return XCTFail() }
        XCTAssertEqual(title, "https://e.example/")
        XCTAssertEqual(url, "https://e.example/")
        XCTAssertNil(parse("addFavorite", ["title": "No URL"]))
    }

    func testDialupModePresetMustExist() {
        guard case .dialupModePreset(let id) = parse("dialupModePreset", ["id": "1998"]) else { return XCTFail() }
        XCTAssertEqual(id, "1998")
        XCTAssertNil(parse("dialupModePreset", ["id": "2049"]))
    }

    func testPatchesPassThroughForTheSettingsModelsToValidate() {
        guard case .prefsSet(let patch) = parse("prefsSet", ["skin": "aqua", "junk": 1]) else { return XCTFail() }
        XCTAssertEqual(patch["skin"] as? String, "aqua")
        guard case .dialupModeSet(let modePatch) = parse("dialupModeSet", ["enabled": true]) else { return XCTFail() }
        XCTAssertEqual(modePatch["enabled"] as? Bool, true)
    }

    func testOptionalFlagsDefault() {
        guard case .overlay(let open) = parse("overlay") else { return XCTFail() }
        XCTAssertFalse(open)
        guard case .log(let message) = parse("log") else { return XCTFail() }
        XCTAssertEqual(message, "")
        guard case .popupMenu(let items, let point) = parse("popupMenu", ["x": 10, "y": 20]) else { return XCTFail() }
        XCTAssertTrue(items.isEmpty)
        XCTAssertEqual(point, NSPoint(x: 10, y: 20))
    }
}
