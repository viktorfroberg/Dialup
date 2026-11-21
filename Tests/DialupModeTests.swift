import XCTest
@testable import Dialup

final class DialupModeSettingsTests: XCTestCase {
    func testMergeAppliesKnownKeysAndIgnoresJunk() {
        let base = DialupModeSettings()
        let merged = base.merging(["enabled": true, "colors": "thousands", "bogus": 1])
        XCTAssertTrue(merged.enabled)
        XCTAssertEqual(merged.colors, .thousands)
        XCTAssertEqual(merged.resolution, base.resolution)
        XCTAssertNil(merged.dictionary["bogus"])
    }

    func testInvalidValueKeepsCurrentSetting() {
        let current = DialupModeSettings(colors: .websafe)
        XCTAssertEqual(current.merging(["colors": "ultraviolet"]).colors, .websafe)
        // Wrong types fall back per field; the valid part of the patch still applies.
        let patched = current.merging(["scanlines": "yes", "oldFonts": true])
        XCTAssertEqual(patched.scanlines, current.scanlines)
        XCTAssertTrue(patched.oldFonts)
    }

    func testPatchFallsBackToCurrentValueNotDefault() {
        let current = DialupModeSettings(enabled: true, connection: .isdn)
        let patched = current.merging(["connection": 42])
        XCTAssertEqual(patched.connection, .isdn)
        XCTAssertTrue(patched.enabled)
    }

    func testEmptyPatchIsIdentity() {
        let current = DialupModeSettings(enabled: true, colors: .gifImages, noShadows: true)
        XCTAssertEqual(current.merging([:]), current)
    }

    func testOldSavedSettingsStillDecode() throws {
        let old = #"{"enabled":true,"colors":"websafe","resolution":"classic","scanlines":true,"oldFonts":false}"#
        let s = try JSONDecoder().decode(DialupModeSettings.self, from: Data(old.utf8))
        XCTAssertTrue(s.enabled)
        XCTAssertEqual(s.colors, .websafe)
        XCTAssertFalse(s.includeChrome)
    }

    func testDictionaryUsesPlainStrings() {
        let dict = DialupModeSettings(connection: .isdn, colors: .gifImages).dictionary
        XCTAssertEqual(dict["connection"] as? String, "isdn")
        XCTAssertEqual(dict["colors"] as? String, "gifImages")
        XCTAssertEqual(dict.count, 12)
    }

    func testConnectionSpeedOnlyWhenEnabled() {
        var s = DialupModeSettings(connection: .modem56k)
        XCTAssertEqual(s.bitsPerSecond, 0)
        s.enabled = true
        XCTAssertEqual(s.bitsPerSecond, 53_333)
        s.connection = .off
        XCTAssertEqual(s.bitsPerSecond, 0)
    }

    func testOnlyDialUpSpeedsDialIn() {
        XCTAssertTrue(DialupModeSettings.Connection.modem56k.dialsIn)
        XCTAssertTrue(DialupModeSettings.Connection.isdn.dialsIn)
        XCTAssertFalse(DialupModeSettings.Connection.dsl.dialsIn)
        XCTAssertFalse(DialupModeSettings.Connection.off.dialsIn)
    }
}

@MainActor
final class DialupModeRendererTests: XCTestCase {
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
        XCTAssertEqual(DialupModeRenderer.filters(for: s, backingScale: 2).map(\.name),
                       ["CIPixellate", "CIDither", "CIColorPosterize"])
        s.enabled = false
        XCTAssertTrue(DialupModeRenderer.filters(for: s, backingScale: 2).isEmpty)
    }

    func testClassicPixelsAreNoOpOnNonRetina() {
        let s = DialupModeSettings(enabled: true, colors: .millions, resolution: .classic, scanlines: false, oldFonts: false)
        XCTAssertTrue(DialupModeRenderer.filters(for: s, backingScale: 1).isEmpty)
        XCTAssertEqual(DialupModeRenderer.filters(for: s, backingScale: 2).first?.name, "CIPixellate")
    }
}

/// The config the page script receives (page touches, picture colours, speed).
@MainActor
final class DialupModePageScriptConfigTests: XCTestCase {
    func testSafeTouchesOnByDefaultRiskyOff() {
        var s = DialupModeSettings()
        s.enabled = true
        let cfg = DialupModePageScript.config(for: s, skin: .aqua)
        XCTAssertEqual(cfg["retroPage"] as? Bool, true)
        XCTAssertEqual(cfg["squareCorners"] as? Bool, true)
        XCTAssertEqual(cfg["noShadows"] as? Bool, false)
        XCTAssertEqual(cfg["noAnimations"] as? Bool, false)
        XCTAssertEqual(cfg["underlineLinks"] as? Bool, false)
        XCTAssertEqual(cfg["skin"] as? String, "aqua")
    }

    func testNothingInjectedWhenDisabled() {
        let cfg = DialupModePageScript.config(for: DialupModeSettings())
        XCTAssertEqual(cfg["retroPage"] as? Bool, false)
        XCTAssertEqual(cfg["squareCorners"] as? Bool, false)
        XCTAssertEqual(cfg["bps"] as? Int, 0)
    }

    func testGifImagesOnlyWhenChosen() {
        var s = DialupModeSettings(enabled: true)
        XCTAssertEqual(DialupModePageScript.config(for: s)["gifImages"] as? Bool, false) // default: millions of colours
        s.colors = .gifImages
        XCTAssertEqual(DialupModePageScript.config(for: s)["gifImages"] as? Bool, true)
    }

    func testScriptIsBundledAndConfigured() {
        XCTAssertFalse(DialupModePageScript.template.isEmpty, "page-script.js must be in the app bundle")
        XCTAssertTrue(DialupModePageScript.template.contains("__CFG__"))
        let source = DialupModePageScript.source(for: DialupModeSettings(enabled: true), skin: .classic)
        XCTAssertFalse(source.contains("__CFG__"))
        XCTAssertTrue(source.contains(#""skin":"classic""#))
    }
}
