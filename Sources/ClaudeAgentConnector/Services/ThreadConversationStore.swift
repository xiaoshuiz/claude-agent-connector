import Foundation

final class ThreadConversationStore {
    private let fileManager: FileManager
    private let fileName = "thread-conversations.json"

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func load() -> [String: ThreadConversation] {
        guard
            let url = storageURL(),
            let data = try? Data(contentsOf: url),
            let conversations = try? JSONDecoder().decode([String: ThreadConversation].self, from: data)
        else {
            return [:]
        }
        return conversations
    }

    func save(_ conversations: [String: ThreadConversation]) {
        guard let url = storageURL() else {
            return
        }

        let folder = url.deletingLastPathComponent()
        try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true)

        guard let data = try? JSONEncoder().encode(conversations) else {
            return
        }
        try? data.write(to: url, options: .atomic)
    }

    private func storageURL() -> URL? {
        if let appSupport = try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) {
            return appSupport
                .appendingPathComponent("ClaudeAgentConnector", isDirectory: true)
                .appendingPathComponent(fileName)
        }

        return fileManager.temporaryDirectory
            .appendingPathComponent("ClaudeAgentConnector", isDirectory: true)
            .appendingPathComponent(fileName)
    }
}
