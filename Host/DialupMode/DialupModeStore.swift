import Foundation

/// App-wide Dial-up Mode state, persisted in UserDefaults and broadcast to all windows
/// (`didChange`). Turning the mode on at a dial-up speed plays the modem handshake.
@MainActor
final class DialupModeStore {
    static let shared = DialupModeStore()
    static let didChange = Notification.Name("DialupModeDidChange")
    private static let defaultsKey = "DialupModeSettings"

    var settings: DialupModeSettings {
        didSet {
            guard settings != oldValue else { return }
            if let data = try? JSONEncoder().encode(settings) {
                UserDefaults.standard.set(data, forKey: Self.defaultsKey)
            }
            NotificationCenter.default.post(name: Self.didChange, object: self)
            // The dial-in moment: a modem handshake for dial-up speeds, silence for broadband.
            if settings.enabled && !oldValue.enabled && settings.connection.dialsIn {
                SoundEffects.shared.play(.modem)
            } else if !settings.enabled && oldValue.enabled {
                SoundEffects.shared.stopModem()
            }
        }
    }

    private init() {
        settings = UserDefaults.standard.data(forKey: Self.defaultsKey)
            .flatMap { try? JSONDecoder().decode(DialupModeSettings.self, from: $0) } ?? DialupModeSettings()
    }
}
