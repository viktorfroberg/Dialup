import Foundation

/// Turns whatever was typed in the address bar into a URL: a full URL,
/// a bare host ("example.com", "localhost:3000") or a search query.
enum AddressResolver {
    static let defaultSearchTemplate = SearchEngine.duckduckgo.template

    /// What the address bar shows for the start page, and what typing it opens.
    static let startPageAliases: Set<String> = ["about:home", "about:start"]

    private static let passthroughPrefixes = ["http://", "https://", "file://", "about:", "data:"]
    /// RFC 3986 "unreserved" characters (ASCII only); everything else in a query is percent-encoded.
    private static let queryAllowed = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")

    /// Address-bar input → URL. `startURL`, if given, is what `about:home`/`about:start` open.
    static func resolve(_ raw: String, searchTemplate: String = defaultSearchTemplate, startURL: URL? = nil) -> URL? {
        let input = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return nil }
        if let startURL, startPageAliases.contains(input.lowercased()) { return startURL }
        return resolveAddress(input) ?? searchURL(for: input, template: searchTemplate)
    }

    /// The search results URL for `query`: `%s` in `template` becomes the percent-encoded query.
    static func searchURL(for query: String, template: String = defaultSearchTemplate) -> URL? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: queryAllowed) else { return nil }
        return URL(string: template.replacingOccurrences(of: "%s", with: encoded))
    }

    /// Like `resolve`, but returns nil instead of falling back to a search.
    static func resolveAddress(_ raw: String) -> URL? {
        let input = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return nil }
        let lower = input.lowercased()

        if passthroughPrefixes.contains(where: lower.hasPrefix) {
            return URL(string: input)
        }

        let looksLikeHost = !input.contains(where: \.isWhitespace)
            && (input.contains(".") || lower.hasPrefix("localhost"))
        if looksLikeHost {
            let isLocal = lower.hasPrefix("localhost")
                || lower.range(of: #"^\d{1,3}(\.\d{1,3}){3}([:/]|$)"#, options: .regularExpression) != nil
            if let url = URL(string: (isLocal ? "http://" : "https://") + input), url.host != nil {
                return url
            }
        }
        return nil
    }
}
