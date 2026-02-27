import Foundation

struct AppSettings: Codable, Equatable {
    var monitoredChannelIDs: String
    var claudeExecutablePath: String
    var commandPrefix: String
    var autoConnectOnLaunch: Bool
    var notifyOnCompletion: Bool
    var maxHistoryItems: Int

    static let defaults = AppSettings(
        monitoredChannelIDs: "",
        claudeExecutablePath: "/usr/local/bin/claude",
        commandPrefix: "/claude",
        autoConnectOnLaunch: false,
        notifyOnCompletion: true,
        maxHistoryItems: 100
    )

    var normalizedChannelIDs: [String] {
        monitoredChannelIDs
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

struct ConnectorSecrets {
    var appLevelToken: String
    var botToken: String
}
