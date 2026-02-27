import Foundation

enum MentionRecordStatus: String, Codable {
    case queued
    case ignoredChannel
    case ignoredEmptyPrompt
}

struct MentionRecord: Identifiable, Codable {
    let id: UUID
    let sourceChannelID: String
    let sourceMessageTS: String
    let sourceThreadTS: String?
    let userID: String?
    let rawText: String
    let extractedPrompt: String
    let receivedAt: Date
    let status: MentionRecordStatus

    init(
        id: UUID = UUID(),
        sourceChannelID: String,
        sourceMessageTS: String,
        sourceThreadTS: String?,
        userID: String?,
        rawText: String,
        extractedPrompt: String,
        receivedAt: Date = Date(),
        status: MentionRecordStatus
    ) {
        self.id = id
        self.sourceChannelID = sourceChannelID
        self.sourceMessageTS = sourceMessageTS
        self.sourceThreadTS = sourceThreadTS
        self.userID = userID
        self.rawText = rawText
        self.extractedPrompt = extractedPrompt
        self.receivedAt = receivedAt
        self.status = status
    }
}
