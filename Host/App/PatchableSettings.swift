import Foundation

/// A settings model the chrome edits by sending partial JSON patches (`prefsSet`, `dialupModeSet`).
///
/// Conforming types get, for free:
/// - `dictionary`: the JSON shape sent to the chrome (the same keys as the type's `Codable` form),
/// - `merging(_:)`: apply a patch; unknown keys and invalid values are ignored, so a bad patch
///   never resets anything.
///
/// Decoding is *tolerant*: a missing or invalid value falls back to the current value (while
/// merging) or the default (when loading from disk), so settings saved by older or newer
/// versions never wipe the rest. Conforming types implement `init(from:)` with a
/// `TolerantContainer` and may clamp values in `sanitize()`.
protocol PatchableSettings: Codable, Equatable, Sendable {
    /// The defaults.
    init()

    /// Brings decoded values back into range (lengths, allowed URLs…). Called at the end of
    /// `init(from:)`. The default implementation does nothing.
    mutating func sanitize()
}

extension CodingUserInfoKey {
    /// `JSONDecoder.userInfo` key for the settings value that invalid fields fall back to.
    /// Force-unwrapped: the initializer only fails for an empty raw value.
    static let settingsFallback = CodingUserInfoKey(rawValue: "dialup.settingsFallback")!
}

extension PatchableSettings {
    mutating func sanitize() {}

    /// What invalid or missing fields fall back to while decoding: the value being patched
    /// (see `merging`), or the defaults when loading saved settings.
    static func fallback(for decoder: any Decoder) -> Self {
        decoder.userInfo[.settingsFallback] as? Self ?? Self()
    }

    /// The JSON form as a dictionary, as sent to the chrome.
    var dictionary: [String: Any] {
        (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(self))) as? [String: Any] ?? [:]
    }

    /// Returns a copy with the given keys replaced; unknown keys and invalid values are ignored.
    func merging(_ patch: [String: Any]) -> Self {
        var merged = dictionary
        for (key, value) in patch where merged[key] != nil { merged[key] = value }
        let decoder = JSONDecoder()
        decoder.userInfo[.settingsFallback] = self
        guard JSONSerialization.isValidJSONObject(merged),
              let data = try? JSONSerialization.data(withJSONObject: merged),
              let result = try? decoder.decode(Self.self, from: data) else { return self }
        return result
    }
}

/// Reads values from a keyed container without ever failing: a missing key, `null`, a value of
/// the wrong type or an unknown enum case yields the fallback instead.
struct TolerantContainer<Key: CodingKey> {
    private let container: KeyedDecodingContainer<Key>

    init(_ decoder: any Decoder, keyedBy: Key.Type) throws {
        container = try decoder.container(keyedBy: Key.self)
    }

    func value<T: Decodable>(_ key: Key, or fallback: T) -> T {
        ((try? container.decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback
    }
}
