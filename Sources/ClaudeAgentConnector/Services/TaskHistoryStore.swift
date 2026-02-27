import Foundation

final class TaskHistoryStore {
    private let fileManager: FileManager
    private let historyFileName = "task-history.json"

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func load() -> [AgentTask] {
        guard
            let url = historyURL(),
            let data = try? Data(contentsOf: url),
            let tasks = try? JSONDecoder().decode([AgentTask].self, from: data)
        else {
            return []
        }
        return tasks
    }

    func save(_ tasks: [AgentTask]) {
        guard let url = historyURL() else {
            return
        }

        let folder = url.deletingLastPathComponent()
        try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true)

        guard let data = try? JSONEncoder().encode(tasks) else {
            return
        }
        try? data.write(to: url, options: .atomic)
    }

    private func historyURL() -> URL? {
        if let appSupport = try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) {
            return appSupport
                .appendingPathComponent("ClaudeAgentConnector", isDirectory: true)
                .appendingPathComponent(historyFileName)
        }

        // Linux/CI fallback to a writable location.
        return fileManager.temporaryDirectory
            .appendingPathComponent("ClaudeAgentConnector", isDirectory: true)
            .appendingPathComponent(historyFileName)
    }
}
