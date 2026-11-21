import Foundation

/// Netscape bookmark file format (bookmarks.html): what Netscape, IE, Firefox, Safari and
/// Chrome all import and export. Folders are flattened; only http(s) links are kept.
enum Bookmarks {
    static func parse(_ html: String) -> [QuickLink] {
        let pattern = #"<A\s[^>]*HREF\s*=\s*"([^"]+)"[^>]*>(.*?)</A>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return [] }
        let ns = html as NSString
        return regex.matches(in: html, range: NSRange(location: 0, length: ns.length)).compactMap { match in
            let url = decode(ns.substring(with: match.range(at: 1)))
            let title = decode(ns.substring(with: match.range(at: 2)).replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression))
            guard let parsed = URL(string: url), ["http", "https"].contains(parsed.scheme?.lowercased() ?? "") else { return nil }
            return QuickLink(title: title.trimmingCharacters(in: .whitespacesAndNewlines), url: url)
        }
    }

    static func export(_ links: [QuickLink]) -> String {
        var out = """
        <!DOCTYPE NETSCAPE-Bookmark-file-1>
        <!-- This is an automatically generated file. It will be read and overwritten. DO NOT EDIT! -->
        <META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=UTF-8">
        <TITLE>Bookmarks</TITLE>
        <H1>Bookmarks</H1>
        <DL><p>
            <DT><H3>Dialup Favorites</H3>
            <DL><p>

        """
        for link in links {
            out += "            <DT><A HREF=\"\(encode(link.url))\">\(encode(link.title))</A>\n"
        }
        out += "        </DL><p>\n</DL><p>\n"
        return out
    }

    private static func encode(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func decode(_ s: String) -> String {
        s.replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">").replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
    }
}
