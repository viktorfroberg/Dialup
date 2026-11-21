import AppKit
import WebKit

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windows: [BrowserWindowController] = []
    private static let sessionKey = "Session"

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { app.run() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.build()
        if !restoreSession() { openWindow() }
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) { saveSession() }

    @objc func newWindow(_ sender: Any?) { openWindow() }

    @discardableResult
    func openWindow(urls: [URL] = [], activeIndex: Int = 0) -> BrowserWindowController {
        register(BrowserWindowController(urls: urls, activeIndex: activeIndex))
    }

    /// window.open / target=_blank with tabs turned off: a new window whose first tab uses
    /// WebKit's configuration (required for the opener relationship).
    func openPopupWindow(configuration: WKWebViewConfiguration) -> WKWebView? {
        let controller = register(BrowserWindowController(popupConfiguration: configuration))
        return controller.tabs.first?.webView
    }

    private func register(_ controller: BrowserWindowController) -> BrowserWindowController {
        controller.onClose = { [weak self, weak controller] in
            // Defer: don't drop the last strong reference while the controller is still in windowWillClose.
            DispatchQueue.main.async {
                guard let self else { return }
                self.windows.removeAll { $0 === controller }
                // Keep the last window's session when it's closed, so it can be restored next launch.
                if !self.windows.isEmpty { self.scheduleSessionSave() }
            }
        }
        controller.onSessionChange = { [weak self] in self?.scheduleSessionSave() }
        windows.append(controller)
        controller.showWindow(nil)
        return controller
    }

    // MARK: Session restore

    private var saveScheduled = false

    private func scheduleSessionSave() {
        guard !saveScheduled else { return }
        saveScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self else { return }
            saveScheduled = false
            saveSession()
        }
    }

    private func saveSession() {
        guard !windows.isEmpty else { return }
        let session = windows.map { controller -> [String: Any] in
            let (urls, active) = controller.session
            return ["urls": urls.map(\.absoluteString), "active": active]
        }
        UserDefaults.standard.set(session, forKey: Self.sessionKey)
    }

    private func restoreSession() -> Bool {
        guard PreferencesStore.shared.preferences.restoreSession,
              UserDefaults.standard.string(forKey: "HomePage") == nil, // debugging override wins
              let saved = UserDefaults.standard.array(forKey: Self.sessionKey) as? [[String: Any]] else { return false }
        var opened = false
        for window in saved {
            let urls = (window["urls"] as? [String] ?? []).compactMap(URL.init(string:))
            guard !urls.isEmpty else { continue }
            openWindow(urls: urls, activeIndex: window["active"] as? Int ?? 0)
            opened = true
        }
        return opened
    }
}
