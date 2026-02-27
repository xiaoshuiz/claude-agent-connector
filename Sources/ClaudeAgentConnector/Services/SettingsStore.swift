import Foundation

final class SettingsStore {
    private let userDefaults: UserDefaults
    private let settingsKey = "claudeAgentConnector.settings"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func load() -> AppSettings {
        guard
            let raw = userDefaults.data(forKey: settingsKey),
            let settings = try? JSONDecoder().decode(AppSettings.self, from: raw)
        else {
            return .defaults
        }
        return settings
    }

    func save(_ settings: AppSettings) {
        guard let raw = try? JSONEncoder().encode(settings) else {
            return
        }
        userDefaults.set(raw, forKey: settingsKey)
    }
}
