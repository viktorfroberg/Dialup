import AppKit
import UniformTypeIdentifiers

/// The open/save sheets behind the chrome's Import and Export Favorites items.
/// Files use the Netscape bookmarks.html format (see `Bookmarks`).
@MainActor
enum BookmarksPanels {
    struct ImportResult {
        /// Favorites that were new and fit under the cap.
        var added: Int
        /// Links found in the file.
        var found: Int
    }

    /// Asks for a bookmarks file and adds its links to the favorites.
    /// Returns nil when the user cancels.
    static func importFavorites(in window: NSWindow) async -> ImportResult? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.html]
        panel.message = "Choose a bookmarks file (bookmarks.html) exported from another browser."
        guard await panel.beginSheetModal(for: window) == .OK, let url = panel.url else { return nil }
        let html = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let imported = Bookmarks.parse(html)
        let added = PreferencesStore.shared.preferences.addFavorites(imported)
        return ImportResult(added: added, found: imported.count)
    }

    /// Asks where to save, then writes the favorites as bookmarks.html.
    static func exportFavorites(in window: NSWindow) async {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.html]
        panel.nameFieldStringValue = "bookmarks.html"
        guard await panel.beginSheetModal(for: window) == .OK, let url = panel.url else { return }
        do {
            try Bookmarks.export(PreferencesStore.shared.preferences.quickLinks).write(to: url, atomically: true, encoding: .utf8)
        } catch {
            NSLog("Dialup: exporting favorites failed: %@", error.localizedDescription)
        }
    }
}
