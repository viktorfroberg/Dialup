import AppKit
import Sparkle

/// Software updates from GitHub releases, via Sparkle. The feed (appcast.xml) is attached to
/// each release; archives are checked against the EdDSA key in Info.plist before installing.
@MainActor
final class Updates: NSObject {
    static let shared = Updates()

    private lazy var controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil,
                                                               userDriverDelegate: nil)

    func start() { _ = controller }

    @objc func checkForUpdates(_ sender: Any?) { controller.checkForUpdates(sender) }
}
