import Foundation

/// Dial-up Mode: browse like it's ~2000, and stay usable.
///
/// The heart of it is the *loading experience*: text appears at once, images trickle in line by
/// line at the simulated connection speed (capped), and the status bar counts down
/// "(n items remaining)". Text is never filtered unless the user opts into the hard-mode
/// whole-page effects. Everything is off and free when disabled.
///
/// Persisted as JSON and patched by the chrome (`dialupModeSet`); see `PatchableSettings`.
struct DialupModeSettings: PatchableSettings {
    enum Connection: String, CaseIterable, Codable {
        case off, dsl, isdn, modem56k

        /// Simulated line speed for image trickle-in; 0 = no throttling.
        /// The single source for these numbers (the chrome gets them as `catalog.connectionSpeeds`).
        var bitsPerSecond: Int {
            switch self {
            case .off: 0
            case .dsl: 512_000
            case .isdn: 128_000
            case .modem56k: 53_333 // what a "56k" modem actually connected at
            }
        }

        /// Connections that "dial in" with a modem handshake when Dial-up Mode is turned on.
        var dialsIn: Bool { self == .modem56k || self == .isdn }
    }

    /// `gifImages` only touches images; `thousands`, `websafe` and `websafeDither` filter the
    /// whole page (hard mode).
    enum Colors: String, Codable { case millions, gifImages, thousands, websafe, websafeDither }
    enum Resolution: String, Codable { case retina, classic, chunky }

    var enabled = false
    var connection: Connection = .modem56k
    var colors: Colors = .millions
    var resolution: Resolution = .retina
    var scanlines = true
    var oldFonts = false
    /// Off by default: window effects only touch the page, the browser UI stays crisp.
    var includeChrome = false

    // Page touches (CSS injected into pages). Safe ones default on; riskier ones are opt-in.
    /// Classic scrollbars, light mode, dotted focus, retro selection, no smooth scroll, no text shadows.
    var retroPage = true
    var squareCorners = true
    var noShadows = false
    var noAnimations = false
    var underlineLinks = false

    init() {}

    init(enabled: Bool = false, connection: Connection = .modem56k, colors: Colors = .millions,
         resolution: Resolution = .retina, scanlines: Bool = true, oldFonts: Bool = false, includeChrome: Bool = false,
         retroPage: Bool = true, squareCorners: Bool = true, noShadows: Bool = false,
         noAnimations: Bool = false, underlineLinks: Bool = false) {
        self.enabled = enabled
        self.connection = connection
        self.colors = colors
        self.resolution = resolution
        self.scanlines = scanlines
        self.oldFonts = oldFonts
        self.includeChrome = includeChrome
        self.retroPage = retroPage
        self.squareCorners = squareCorners
        self.noShadows = noShadows
        self.noAnimations = noAnimations
        self.underlineLinks = underlineLinks
    }

    init(from decoder: any Decoder) throws {
        let c = try TolerantContainer(decoder, keyedBy: CodingKeys.self)
        let d = Self.fallback(for: decoder)
        enabled = c.value(.enabled, or: d.enabled)
        connection = c.value(.connection, or: d.connection)
        colors = c.value(.colors, or: d.colors)
        resolution = c.value(.resolution, or: d.resolution)
        scanlines = c.value(.scanlines, or: d.scanlines)
        oldFonts = c.value(.oldFonts, or: d.oldFonts)
        includeChrome = c.value(.includeChrome, or: d.includeChrome)
        retroPage = c.value(.retroPage, or: d.retroPage)
        squareCorners = c.value(.squareCorners, or: d.squareCorners)
        noShadows = c.value(.noShadows, or: d.noShadows)
        noAnimations = c.value(.noAnimations, or: d.noAnimations)
        underlineLinks = c.value(.underlineLinks, or: d.underlineLinks)
    }

    /// One-click looks offered in Dialup Options, keyed by the id the chrome sends (`dialupModePreset`).
    static let presets: [String: DialupModeSettings] = [
        "1998": DialupModeSettings(enabled: true, connection: .modem56k, colors: .gifImages, scanlines: true, oldFonts: true,
                                   noShadows: true, underlineLinks: true),
        "2003": DialupModeSettings(enabled: true, connection: .dsl, colors: .millions, scanlines: false, oldFonts: false),
    ]

    /// Simulated line speed for image trickle-in right now; 0 = no throttling.
    var bitsPerSecond: Int { enabled ? connection.bitsPerSecond : 0 }
}
