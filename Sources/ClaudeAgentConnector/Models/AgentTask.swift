import Foundation

enum TaskStatus: String, Codable {
    case queued
    case running
    case succeeded
    case failed
}

struct AgentTask: Identifiable, Codable {
    let id: UUID
    let sourceChannelID: String
    let sourceThreadTS: String?
    let sourceMessageTS: String
    let requestText: String
    let createdAt: Date
    var startedAt: Date?
    var finishedAt: Date?
    var status: TaskStatus
    var responseText: String?
    var errorMessage: String?

    init(
        id: UUID = UUID(),
        sourceChannelID: String,
        sourceThreadTS: String?,
        sourceMessageTS: String,
        requestText: String,
        createdAt: Date = Date(),
        startedAt: Date? = nil,
        finishedAt: Date? = nil,
        status: TaskStatus = .queued,
        responseText: String? = nil,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.sourceChannelID = sourceChannelID
        self.sourceThreadTS = sourceThreadTS
        self.sourceMessageTS = sourceMessageTS
        self.requestText = requestText
        self.createdAt = createdAt
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.status = status
        self.responseText = responseText
        self.errorMessage = errorMessage
    }
}
