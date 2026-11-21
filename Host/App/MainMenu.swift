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

        submenu("Dialup", [
            item("About Dialup", #selector(NSApplication.orderFrontStandardAboutPanel(_:))),
            .separator(),
            item("Settings…", #selector(BrowserWindowController.openSettings(_:)), ","),
            .separator(),
            item("Hide Dialup", #selector(NSApplication.hide(_:)), "h"),
            item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]),
            item("Show All", #selector(NSApplication.unhideAllApplications(_:))),
            .separator(),
            item("Quit Dialup", #selector(NSApplication.terminate(_:)), "q"),
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
            item("Stop", #selector(BrowserWindowController.dialupStop(_:)), "."),
            item("Refresh", #selector(BrowserWindowController.dialupReload(_:)), "r"),
            .separator(),
            item("Dial-up Mode", #selector(BrowserWindowController.toggleDialupMode(_:)), "d", [.command, .shift]),
            item("Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control]),
            .separator(),
            item("Reload Chrome", #selector(BrowserWindowController.reloadChrome(_:)), "r", [.command, .option]),
        ])

        submenu("Go", [
            item("Back", #selector(BrowserWindowController.dialupBack(_:)), "["),
            item("Forward", #selector(BrowserWindowController.dialupForward(_:)), "]"),
            item("Home", #selector(BrowserWindowController.dialupHome(_:)), "h", [.command, .shift]),
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
