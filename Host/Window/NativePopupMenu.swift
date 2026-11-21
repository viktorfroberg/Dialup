import AppKit

/// The `popupMenu` command: a native NSMenu built from the chrome's item specs, so it is never
/// clipped by the window. Item spec: `{ id, title, enabled?, checked?, separator?, items? }`;
/// `items` makes a submenu.
@MainActor
enum NativePopupMenu {
    /// Deeper submenus are shown as plain items.
    private static let maxDepth = 3

    /// Shows the menu at `point` (in `view`'s coordinates) and returns the picked item's `id`,
    /// or nil if the menu was dismissed. Blocks until the menu closes, like any popup menu.
    static func pick(from items: [[String: Any]], at point: NSPoint, in view: NSView) -> String? {
        let picker = Picker()
        let menu = build(items, picker: picker, depth: 0)
        menu.popUp(positioning: nil, at: point, in: view)
        return picker.picked
    }

    private static func build(_ items: [[String: Any]], picker: Picker, depth: Int) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for spec in items {
            if spec["separator"] as? Bool == true {
                menu.addItem(.separator())
                continue
            }
            let item = NSMenuItem(title: spec["title"] as? String ?? "", action: nil, keyEquivalent: "")
            item.isEnabled = spec["enabled"] as? Bool ?? true
            item.state = (spec["checked"] as? Bool ?? false) ? .on : .off
            if let children = spec["items"] as? [[String: Any]], depth < maxDepth {
                item.submenu = build(children, picker: picker, depth: depth + 1)
            } else {
                item.action = #selector(Picker.pick(_:))
                item.target = picker
                item.representedObject = spec["id"] as? String
            }
            menu.addItem(item)
        }
        return menu
    }

    /// Target of every item; remembers which one was chosen.
    private final class Picker: NSObject {
        var picked: String?
        @objc func pick(_ sender: NSMenuItem) { picked = sender.representedObject as? String }
    }
}
