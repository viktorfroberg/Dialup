import AppKit
import WebKit

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, BrowserWindowOpening {
    private var windows: [BrowserWindowController] = []
    private static let sessionKey = "Session"
    /// Session changes come in bursts (every tab title and URL), so saving waits this long.
    private static let sessionSaveDelay = Duration.seconds(1)

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { app.run() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hosting unit tests: no windows, and the user's saved session is left untouched.
        guard !LaunchEnvironment.isHostingTests else { return }
        NSApp.mainMenu = MainMenu.build()
        Updates.shared.start()
        SkinIcon.apply(PreferencesStore.shared.preferences.skin)
        NotificationCenter.default.addObserver(self, selector: #selector(preferencesDidChange),
                                               name: PreferencesStore.didChange, object: nil)
        if !restoreSession() { openWindow() }
        NSApp.activate()
    }

    @objc private func preferencesDidChange(_ notification: Notification) {
        SkinIcon.apply(PreferencesStore.shared.preferences.skin)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) { saveSession() }

    /// Links from other apps (when Dialup is the default browser) and opened HTML files.
    func application(_ application: NSApplication, open urls: [URL]) {
        let target = (NSApp.keyWindow?.windowController as? BrowserWindowController) ?? windows.last
        for url in urls {
            if let target, PreferencesStore.shared.preferences.tabs { target.openInNewTab(url) } else { openWindow(urls: [url]) }
        }
        NSApp.activate()
    }

    @objc func makeDefaultBrowser(_ sender: Any?) {
        let app = Bundle.main.bundleURL
        // macOS asks the user to confirm each change.
        Task {
            try? await NSWorkspace.shared.setDefaultApplication(at: app, toOpenURLsWithScheme: "http")
            try? await NSWorkspace.shared.setDefaultApplication(at: app, toOpenURLsWithScheme: "https")
        }
    }

    // MARK: Windows

    @objc func newWindow(_ sender: Any?) { openWindow() }

    func openWindow(urls: [URL] = []) { openWindow(urls: urls, activeIndex: 0) }

    private func openWindow(urls: [URL], activeIndex: Int) {
        register(BrowserWindowController(urls: urls, activeIndex: activeIndex, opener: self))
    }

    func openPopupWindow(configuration: WKWebViewConfiguration) -> WKWebView? {
        let controller = BrowserWindowController(popupConfiguration: configuration, opener: self)
        register(controller)
        return controller.activeTab.webView
    }

    private func register(_ controller: BrowserWindowController) {
        controller.onClose = { [weak self, weak controller] in
            // Deferred: don't drop the last strong reference while the controller is still in windowWillClose.
            Task { [weak self] in
                guard let self else { return }
                windows.removeAll { $0 === controller }
                // Keep the last window's session when it's closed, so it can be restored next launch.
                if !windows.isEmpty { scheduleSessionSave() }
            }
        }
        controller.onSessionChange = { [weak self] in self?.scheduleSessionSave() }
        windows.append(controller)
        controller.showWindow(nil)
    }

    // MARK: Session restore

    private var sessionSave: Task<Void, Never>?

    private func scheduleSessionSave() {
        guard sessionSave == nil else { return }
        sessionSave = Task { [weak self] in
            try? await Task.sleep(for: Self.sessionSaveDelay)
            guard let self else { return }
            sessionSave = nil
            saveSession()
        }
    }

    private func saveSession() {
        // A `-HomePage` debug run didn't restore the session, so it mustn't overwrite it either.
        guard !windows.isEmpty, LaunchEnvironment.homePageOverride == nil else { return }
        let session = windows.map { controller -> [String: Any] in
            let (urls, active) = controller.session
            return ["urls": urls.map(\.absoluteString), "active": active]
        }
        UserDefaults.standard.set(session, forKey: Self.sessionKey)
    }

    private func restoreSession() -> Bool {
        guard PreferencesStore.shared.preferences.restoreSession,
              LaunchEnvironment.homePageOverride == nil, // the debug override wins
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
