import AppKit

/// The Dock icon follows the skin: each skin has an era-homage icon in Resources/SkinIcons/<skin>.png.
/// (Finder always shows the bundle's main icon, the default skin's.)
@MainActor
enum SkinIcon {
    private static var current: String?

    static func apply(_ skin: String) {
        guard skin != current else { return }
        current = skin
        if let url = Bundle.main.url(forResource: skin, withExtension: "png", subdirectory: "SkinIcons"),
           let image = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = image
        } else {
            NSApp.applicationIconImage = nil // fall back to the bundle icon
        }
    }
}
