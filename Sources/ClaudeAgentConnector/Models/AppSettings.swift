import Foundation

struct AppSettings: Codable, Equatable {
    var monitoredChannelIDs: String
    var claudeExecutablePath: String
    var autoConnectOnLaunch: Bool
    var notifyOnCompletion: Bool
    var maxHistoryItems: Int

    static let defaults = AppSettings(
        monitoredChannelIDs: "",
        claudeExecutablePath: "/usr/local/bin/claude",
        autoConnectOnLaunch: false,
        notifyOnCompletion: true,
        maxHistoryItems: 100
    )

    private var rawMonitoredChannels: [String] {
        monitoredChannelIDs
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func normalizeChannelEntry(_ entry: String) -> String {
        var normalized = entry.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.hasPrefix("#") {
            normalized.removeFirst()
        }
        return normalized.uppercased()
    }

    private func isValidChannelID(_ value: String) -> Bool {
        guard value.count >= 9 else {
            return false
        }
        guard let prefix = value.first, prefix == "C" || prefix == "G" || prefix == "D" else {
            return false
        }
        return value.unicodeScalars.allSatisfy { scalar in
            CharacterSet.uppercaseLetters.contains(scalar) || CharacterSet.decimalDigits.contains(scalar)
        }
    }

    var normalizedChannelIDs: [String] {
        rawMonitoredChannels
            .map { normalizeChannelEntry($0) }
            .filter { isValidChannelID($0) }
    }

    var invalidMonitoredChannelEntries: [String] {
        rawMonitoredChannels.filter { !isValidChannelID(normalizeChannelEntry($0)) }
    }
}

struct ConnectorSecrets {
    var appLevelToken: String
    var botToken: String
}
