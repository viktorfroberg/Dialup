import AppKit

/// The native menu bar. It owns every keyboard shortcut, so shortcuts work
/// no matter whether the chrome or the page has focus.
@MainActor
enum MainMenu {
    static func build() -> NSMenu {
        let main = NSMenu()

        @discardableResult
        func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenu {
            let menu = NSMenu(title: title)
            items.forEach(menu.addItem)
            let holder = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            holder.submenu = menu
            main.addItem(holder)
            return menu
        }

        func item(_ title: String, _ action: Selector?, _ key: String = "",
                  _ mods: NSEvent.ModifierFlags = .command) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = mods
            return item
        }

        submenu("Kikare", [
            item("About Kikare", #selector(NSApplication.orderFrontStandardAboutPanel(_:))),
            .separator(),
            item("Hide Kikare", #selector(NSApplication.hide(_:)), "h"),
            item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]),
            item("Show All", #selector(NSApplication.unhideAllApplications(_:))),
            .separator(),
            item("Quit Kikare", #selector(NSApplication.terminate(_:)), "q"),
        ])

        submenu("File", [
            item("New Window", #selector(AppDelegate.newWindow(_:)), "n"),
            item("Open Location…", #selector(BrowserWindowController.openLocation(_:)), "l"),
            .separator(),
            item("Close Window", #selector(NSWindow.performClose(_:)), "w"),
        ])

        submenu("Edit", [
            item("Undo", Selector(("undo:")), "z"),
            item("Redo", Selector(("redo:")), "z", [.command, .shift]),
            .separator(),
            item("Cut", #selector(NSText.cut(_:)), "x"),
            item("Copy", #selector(NSText.copy(_:)), "c"),
            item("Paste", #selector(NSText.paste(_:)), "v"),
            item("Select All", #selector(NSText.selectAll(_:)), "a"),
        ])

        submenu("View", [
            item("Stop", #selector(BrowserWindowController.kikareStop(_:)), "."),
            item("Refresh", #selector(BrowserWindowController.kikareReload(_:)), "r"),
            .separator(),
            item("Reload Chrome", #selector(BrowserWindowController.reloadChrome(_:)), "r", [.command, .option]),
        ])

        submenu("Go", [
            item("Back", #selector(BrowserWindowController.kikareBack(_:)), "["),
            item("Forward", #selector(BrowserWindowController.kikareForward(_:)), "]"),
            item("Home", #selector(BrowserWindowController.kikareHome(_:)), "h", [.command, .shift]),
        ])

        let windowMenu = submenu("Window", [
            item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"),
            item("Zoom", #selector(NSWindow.performZoom(_:))),
        ])
        NSApp.windowsMenu = windowMenu

        let helpMenu = submenu("Help", [])
        NSApp.helpMenu = helpMenu

        return main
    }
}
