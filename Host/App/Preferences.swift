import Foundation

struct QuickLink: Codable, Equatable {
    var title: String
    var url: String
}

/// Browser preferences ("profile"): skin, home page, search engine, start page content.
/// Persisted in UserDefaults; decoding is tolerant so old or odd values never wipe settings.
struct Preferences: Codable, Equatable {
    var skin = "aqua"
    /// "start" for the built-in start page, otherwise a URL.
    var homePage = "start"
    var searchEngine = "duckduckgo"
    var name = ""
    var quickLinks: [QuickLink] = Preferences.defaultLinks

    static let skins: [(id: String, name: String)] = [("aqua", "Aqua (Mac, 2003)"), ("luna", "Luna (Windows, 2001)")]
    static let searchEngines: [(id: String, name: String, template: String)] = [
        ("duckduckgo", "DuckDuckGo", "https://duckduckgo.com/?q=%s"),
        ("google", "Google", "https://www.google.com/search?q=%s"),
        ("bing", "Bing", "https://www.bing.com/search?q=%s"),
        ("wikipedia", "Wikipedia", "https://en.wikipedia.org/w/index.php?search=%s"),
    ]
    static let defaultLinks = [
        QuickLink(title: "Wikipedia", url: "https://www.wikipedia.org/"),
        QuickLink(title: "Hacker News", url: "https://news.ycombinator.com/"),
        QuickLink(title: "Internet Archive", url: "https://web.archive.org/"),
        QuickLink(title: "Space Jam (1996)", url: "https://www.spacejam.com/1996/"),
        QuickLink(title: "Neocities", url: "https://neocities.org/"),
    ]
    static let startURL = URL(string: "dialup-start://home/")!

    init() {}

    static let fallbackKey = CodingUserInfoKey(rawValue: "fallback")!

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = decoder.userInfo[Self.fallbackKey] as? Preferences ?? Preferences()
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            ((try? c.decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback
        }
        skin = value(.skin, d.skin)
        homePage = value(.homePage, d.homePage)
        searchEngine = value(.searchEngine, d.searchEngine)
        name = value(.name, d.name)
        quickLinks = value(.quickLinks, d.quickLinks)
        sanitize(fallback: d)
    }

    /// Keeps values in range: known skin/engine, sane lengths, only http(s) links.
    mutating func sanitize(fallback: Preferences = Preferences()) {
        if !Self.skins.contains(where: { $0.id == skin }) { skin = fallback.skin }
        if !Self.searchEngines.contains(where: { $0.id == searchEngine }) { searchEngine = fallback.searchEngine }
        name = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
        if homePage != "start" {
            let resolved = AddressResolver.resolve(homePage)
            homePage = resolved.map(\.absoluteString) ?? "start"
        }
        quickLinks = quickLinks.prefix(12).compactMap { link in
            let title = String(link.title.trimmingCharacters(in: .whitespaces).prefix(60))
            let raw = link.url.trimmingCharacters(in: .whitespaces).lowercased()
            if ["javascript:", "data:", "file:", "about:", "blob:"].contains(where: raw.hasPrefix) { return nil }
            guard let url = AddressResolver.resolve(link.url), ["http", "https"].contains(url.scheme ?? "") else { return nil }
            return QuickLink(title: title.isEmpty ? (url.host ?? url.absoluteString) : title, url: url.absoluteString)
        }
    }

    var searchTemplate: String {
        Self.searchEngines.first { $0.id == searchEngine }?.template ?? AddressResolver.defaultSearchTemplate
    }

    var searchEngineName: String {
        Self.searchEngines.first { $0.id == searchEngine }?.name ?? "DuckDuckGo"
    }

    var homeURL: URL {
        homePage == "start" ? Self.startURL : (URL(string: homePage) ?? Self.startURL)
    }

    var dictionary: [String: Any] {
        (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(self))) as? [String: Any] ?? [:]
    }

    func merging(_ patch: [String: Any]) -> Preferences {
        var dict = dictionary
        for (key, value) in patch where dict[key] != nil { dict[key] = value }
        let decoder = JSONDecoder()
        decoder.userInfo[Self.fallbackKey] = self
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let merged = try? decoder.decode(Preferences.self, from: data) else { return self }
        return merged
    }

    /// Lists the chrome needs to build the settings UI.
    static var catalog: [String: Any] {
        [
            "skins": skins.map { ["id": $0.id, "name": $0.name] },
            "searchEngines": searchEngines.map { ["id": $0.id, "name": $0.name] },
        ]
    }
}

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
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let saved = try? JSONDecoder().decode(Preferences.self, from: data) {
            preferences = saved
        } else {
            preferences = Preferences()
        }
    }
}
