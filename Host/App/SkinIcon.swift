import AppKit

/// The Dock icon follows the skin: each skin has its own icon in Resources/SkinIcons/<skin>.png.
/// (Finder always shows the bundle's main icon, the default skin's.)
@MainActor
enum SkinIcon {
    private static var current: Skin?

    static func apply(_ skin: Skin) {
        guard skin != current else { return }
        current = skin
        if let url = Bundle.main.url(forResource: skin.rawValue, withExtension: "png", subdirectory: "SkinIcons"),
           let image = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = image
        } else {
            NSApp.applicationIconImage = nil // fall back to the bundle icon
        }
    }
}
