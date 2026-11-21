import Foundation

/// Turns whatever was typed in the address bar into a URL: a full URL,
/// a bare host ("example.com", "localhost:3000") or a search query.
enum AddressResolver {
    static let defaultSearchTemplate = "https://duckduckgo.com/?q=%s"

    private static let passthroughPrefixes = ["http://", "https://", "file://", "about:", "data:"]
    private static let queryAllowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))

    static func resolve(_ raw: String, searchTemplate: String = defaultSearchTemplate) -> URL? {
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

        guard let query = input.addingPercentEncoding(withAllowedCharacters: queryAllowed) else { return nil }
        return URL(string: searchTemplate.replacingOccurrences(of: "%s", with: query))
    }
}
