import AppKit

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windows: [BrowserWindowController] = []

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { app.run() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.build()
        openWindow()
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    @objc func newWindow(_ sender: Any?) { openWindow() }

    private func openWindow() {
        let controller = BrowserWindowController()
        controller.onClose = { [weak self, weak controller] in
            // Defer: don't drop the last strong reference while the controller is still in windowWillClose.
            DispatchQueue.main.async { self?.windows.removeAll { $0 === controller } }
        }
        windows.append(controller)
        controller.showWindow(nil)
    }
}
