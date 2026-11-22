import Foundation

/// A favorite: one entry in the Favorites menu, the Links bar and the start page.
/// Called a "quick link" in the persisted JSON and the host API (`quickLinks`).
struct QuickLink: Codable, Equatable {
    var title: String
    var url: String
}

/// A built-in skin. The raw value is the skin's id: `UI/skins/<id>.css` and
/// `Resources/SkinIcons/<id>.png`.
enum Skin: String, CaseIterable, Codable {
    case luna, aqua, classic

    var displayName: String {
        switch self {
        case .luna: "Luna (Windows, 2001)"
        case .aqua: "Aqua (Mac, 2003)"
        case .classic: "Classic (Windows, 1999)"
        }
    }
}

enum SearchEngine: String, CaseIterable, Codable {
    case duckduckgo, google, bing, wikipedia

    var displayName: String {
        switch self {
        case .duckduckgo: "DuckDuckGo"
        case .google: "Google"
        case .bing: "Bing"
        case .wikipedia: "Wikipedia"
        }
    }

    /// Search URL with `%s` where the percent-encoded query goes.
    var template: String {
        switch self {
        case .duckduckgo: "https://duckduckgo.com/?q=%s"
        case .google: "https://www.google.com/search?q=%s"
        case .bing: "https://www.bing.com/search?q=%s"
        case .wikipedia: "https://en.wikipedia.org/w/index.php?search=%s"
        }
    }
}

/// Browser preferences ("profile"): skin, home page, search engine, start page content.
/// Persisted in UserDefaults as JSON; decoding is tolerant (see `PatchableSettings`), so old or
/// odd values never wipe settings. Enums encode as their raw string, so the JSON is plain strings.
struct Preferences: PatchableSettings {
    var skin = Skin.luna
    /// Set once the first-run setup wizard has been finished or cancelled.
    var onboarded = false
    /// Tabs like Firefox 1.0 (true), or one page per window like 2001 (false).
    var tabs = true
    /// Reopen last session's windows and tabs at launch.
    var restoreSession = true
    /// Block ads and trackers (native content rule list, see AdBlocker).
    var blockAds = true
    /// Check GitHub for a new version at launch (and daily while open). See `Updates`.
    var checkForUpdates = true
    /// `startPageHome` for the built-in start page, otherwise a URL.
    var homePage = Preferences.startPageHome
    var searchEngine = SearchEngine.duckduckgo
    /// The user's name, shown on the start page.
    var name = ""
    /// The favorites.
    var quickLinks: [QuickLink] = Preferences.defaultLinks

    /// `homePage` value meaning "the built-in start page".
    static let startPageHome = "start"
    /// Force-unwrapped: a constant, valid URL.
    static let startURL = URL(string: "dialup-start://home/")!
    static let maxFavorites = 30
    static let maxNameLength = 40
    static let maxFavoriteTitleLength = 60
    static let defaultLinks = [
        QuickLink(title: "Wikipedia", url: "https://www.wikipedia.org/"),
        QuickLink(title: "Hacker News", url: "https://news.ycombinator.com/"),
        QuickLink(title: "Internet Archive", url: "https://web.archive.org/"),
        QuickLink(title: "Space Jam (1996)", url: "https://www.spacejam.com/1996/"),
        QuickLink(title: "Neocities", url: "https://neocities.org/"),
    ]
    /// Favorites with these schemes are dropped: only real web pages may be saved.
    private static let forbiddenLinkPrefixes = ["javascript:", "data:", "file:", "about:", "blob:"]

    init() {}

    init(from decoder: any Decoder) throws {
        let c = try TolerantContainer(decoder, keyedBy: CodingKeys.self)
        let d = Self.fallback(for: decoder)
        skin = c.value(.skin, or: d.skin)
        homePage = c.value(.homePage, or: d.homePage)
        searchEngine = c.value(.searchEngine, or: d.searchEngine)
        name = c.value(.name, or: d.name)
        quickLinks = c.value(.quickLinks, or: d.quickLinks)
        onboarded = c.value(.onboarded, or: d.onboarded)
        tabs = c.value(.tabs, or: d.tabs)
        restoreSession = c.value(.restoreSession, or: d.restoreSession)
        blockAds = c.value(.blockAds, or: d.blockAds)
        checkForUpdates = c.value(.checkForUpdates, or: d.checkForUpdates)
        sanitize()
    }

    /// Keeps values in range: sane lengths, a resolvable home page, only http(s) favorites.
    /// (Unknown skins and search engines already fall back while decoding.)
    mutating func sanitize() {
        name = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxNameLength))
        if homePage != Self.startPageHome {
            homePage = AddressResolver.resolveAddress(homePage)?.absoluteString ?? Self.startPageHome
        }
        quickLinks = quickLinks.prefix(Self.maxFavorites).compactMap(Self.sanitized)
    }

    private static func sanitized(_ link: QuickLink) -> QuickLink? {
        let title = String(link.title.trimmingCharacters(in: .whitespaces).prefix(maxFavoriteTitleLength))
        let raw = link.url.trimmingCharacters(in: .whitespaces).lowercased()
        if forbiddenLinkPrefixes.contains(where: raw.hasPrefix) { return nil }
        guard let url = AddressResolver.resolveAddress(link.url), ["http", "https"].contains(url.scheme ?? "") else { return nil }
        return QuickLink(title: title.isEmpty ? (url.host ?? url.absoluteString) : title, url: url.absoluteString)
    }

    var searchTemplate: String { searchEngine.template }

    var homeURL: URL {
        homePage == Self.startPageHome ? Self.startURL : (URL(string: homePage) ?? Self.startURL)
    }

    /// Adds favorites that aren't saved yet (by URL), up to `maxFavorites`.
    /// Returns how many were added.
    @discardableResult
    mutating func addFavorites(_ links: [QuickLink]) -> Int {
        var added = 0
        for link in links where !quickLinks.contains(where: { $0.url == link.url }) {
            guard quickLinks.count < Self.maxFavorites else { break }
            quickLinks.append(link)
            added += 1
        }
        sanitize()
        return added
    }

    /// Single source of truth for lists and constants the chrome needs (settings, wizard, mock).
    static var catalog: [String: Any] {
        [
            "skins": Skin.allCases.map { ["id": $0.rawValue, "name": $0.displayName] },
            "searchEngines": SearchEngine.allCases.map { ["id": $0.rawValue, "name": $0.displayName] },
            "defaultLinks": defaultLinks.map { ["title": $0.title, "url": $0.url] },
            "dialupPresets": DialupModeSettings.presets.mapValues(\.dictionary),
            "connectionSpeeds": Dictionary(uniqueKeysWithValues: DialupModeSettings.Connection.allCases.map {
                ($0.rawValue, $0.bitsPerSecond)
            }),
            "pictureCapMs": DialupModePageScript.pictureCapMs,
            "maxFavorites": maxFavorites,
        ]
    }
}

/// The app-wide preferences, persisted in UserDefaults. Posts `didChange` on every change.
@MainActor
final class PreferencesStore {
    static let shared = PreferencesStore()
    static let didChange = Notification.Name("DialupPreferencesDidChange")
    private static let defaultsKey = "Preferences"

    var preferences: Preferences {
        didSet {
            guard preferences != oldValue else { return }
            if let data = try? JSONEncoder().encode(preferences) {
                UserDefaults.standard.set(data, forKey: Self.defaultsKey)
            }
            NotificationCenter.default.post(name: Self.didChange, object: self)
        }
    }

    private init() {
        preferences = UserDefaults.standard.data(forKey: Self.defaultsKey)
            .flatMap { try? JSONDecoder().decode(Preferences.self, from: $0) } ?? Preferences()
    }
}
