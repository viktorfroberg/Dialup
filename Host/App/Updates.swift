import AppKit
import Sparkle

/// Software updates from GitHub releases, via Sparkle. Each release carries `appcast.xml`; the
/// archive is checked against the EdDSA key in Info.plist before it's installed. Sparkle does the
/// checking, downloading and installing; `RetroUpdateDriver` shows it as a skinned chrome dialog.
@MainActor
final class Updates: NSObject {
    static let shared = Updates()

    private let driver = RetroUpdateDriver()
    private lazy var updater = SPUUpdater(hostBundle: .main, applicationBundle: .main,
                                          userDriver: driver, delegate: nil)

    /// Starts Sparkle, then (if the preference allows) checks once quietly: the dialog only
    /// appears when there's a newer version the user hasn't skipped.
    func start() {
        do { try updater.start() } catch { NSLog("Dialup updates: %@", error.localizedDescription); return }
        applyPreference()
        if PreferencesStore.shared.preferences.checkForUpdates { updater.checkForUpdatesInBackground() }
        NotificationCenter.default.addObserver(self, selector: #selector(preferencesDidChange),
                                               name: PreferencesStore.didChange, object: nil)
    }

    @objc func checkForUpdates(_ sender: Any?) { updater.checkForUpdates() }

    /// A button in the update dialog.
    func choose(_ choice: UpdateChoice) { driver.choose(choice) }

    /// A window's chrome finished loading: show it the dialog if an update is in progress.
    func chromeDidBecomeReady(in window: BrowserWindowController) { driver.adopt(window) }

    private func applyPreference() {
        // Daily background checks while Dialup stays open follow the same preference.
        updater.automaticallyChecksForUpdates = PreferencesStore.shared.preferences.checkForUpdates
    }

    @objc private func preferencesDidChange(_ notification: Notification) { applyPreference() }
}

/// Buttons of the update dialog (the chrome's `updateChoice` command).
enum UpdateChoice: String {
    /// Install (or, when downloaded, install and relaunch).
    case install
    /// Skip this version: no more reminders until a newer one.
    case skip
    /// Remind me later, OK, Close.
    case dismiss
    /// Stop the check or the download.
    case cancel
}

/// Sparkle's user interface, drawn by the chrome as a retro dialog. Sparkle calls these on the main
/// thread; each step is sent to one window's chrome as an `update` event (see docs/host-api.md).
@MainActor
final class RetroUpdateDriver: NSObject {
    private weak var presenter: BrowserWindowController?
    /// The last step shown, so a newly opened or re-chosen window can show it too.
    private var current: [String: Any]?
    private var onChoice: ((UpdateChoice) -> Void)?
    private var expectedBytes: UInt64 = 0
    private var receivedBytes: UInt64 = 0
    private var lastProgressEmit = ContinuousClock.now

    func choose(_ choice: UpdateChoice) {
        let handler = onChoice
        onChoice = nil
        handler?(choice)
    }

    func adopt(_ window: BrowserWindowController) {
        guard let current, presenter == nil || presenter === window else { return }
        presenter = window
        // After the chrome's `ready` reply has been handled.
        DispatchQueue.main.async { window.emit("update", current) }
    }

    private func show(_ phase: String, _ data: [String: Any] = [:], onChoice: ((UpdateChoice) -> Void)? = nil) {
        self.onChoice = onChoice
        var payload = data
        payload["phase"] = phase
        current = phase == "dismiss" ? nil : payload
        if presenter?.window?.isVisible != true {
            presenter = (NSApp.keyWindow?.windowController as? BrowserWindowController)
                ?? NSApp.orderedWindows.lazy.compactMap { $0.windowController as? BrowserWindowController }.first
        }
        presenter?.emit("update", payload)
        if phase != "dismiss", phase != "progress" { presenter?.window?.makeKeyAndOrderFront(nil) }
    }

    private static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    private static func message(_ error: Error) -> String {
        (error as NSError).localizedDescription
    }
}

extension RetroUpdateDriver: SPUUserDriver {
    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        // The setting lives in Dialup Options and the setup wizard; never ask separately.
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: PreferencesStore.shared.preferences.checkForUpdates,
                                         sendSystemProfile: false))
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        show("checking", onChoice: { _ in cancellation() })
    }

    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState,
                         reply: @escaping (SPUUserUpdateChoice) -> Void) {
        let notes = appcastItem.fullReleaseNotesURL ?? appcastItem.infoURL
        show("found", [
            "version": appcastItem.displayVersionString,
            "current": Self.currentVersion,
            "notesURL": notes?.absoluteString ?? "",
            "downloaded": state.stage != .notDownloaded,
            "userInitiated": state.userInitiated,
        ], onChoice: { choice in
            switch choice {
            case .install: reply(.install)
            case .skip: reply(.skip)
            case .dismiss, .cancel: reply(.dismiss)
            }
        })
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}
    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: any Error) {}

    func showUpdateNotFoundWithError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        show("notFound", ["current": Self.currentVersion], onChoice: { _ in acknowledgement() })
    }

    func showUpdaterError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        show("error", ["message": Self.message(error)], onChoice: { _ in acknowledgement() })
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        expectedBytes = 0
        receivedBytes = 0
        show("downloading", ["received": 0, "total": 0], onChoice: { _ in cancellation() })
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        expectedBytes = expectedContentLength
    }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        receivedBytes += length
        // Many small chunks: update the progress bar a few times a second, keeping the Cancel handler.
        guard ContinuousClock.now - lastProgressEmit > .milliseconds(150) else { return }
        lastProgressEmit = .now
        let payload: [String: Any] = ["phase": "downloading", "received": receivedBytes, "total": expectedBytes]
        current = payload
        presenter?.emit("update", payload)
    }

    func showDownloadDidStartExtractingUpdate() {
        show("extracting", ["progress": 0])
    }

    func showExtractionReceivedProgress(_ progress: Double) {
        let payload: [String: Any] = ["phase": "extracting", "progress": progress]
        current = payload
        presenter?.emit("update", payload)
    }

    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        show("ready", onChoice: { choice in reply(choice == .install ? .install : .dismiss) })
    }

    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool,
                              retryTerminatingApplication: @escaping () -> Void) {
        show("installing", onChoice: { choice in if choice == .install { retryTerminatingApplication() } })
    }

    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        acknowledgement()
    }

    func showUpdateInFocus() {
        presenter?.window?.makeKeyAndOrderFront(nil)
    }

    func dismissUpdateInstallation() {
        show("dismiss")
    }
}
