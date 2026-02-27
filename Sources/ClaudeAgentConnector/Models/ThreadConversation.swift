import Foundation

enum ConversationRole: String, Codable {
    case user
    case assistant
}

struct ConversationTurn: Codable {
    let role: ConversationRole
    let text: String
    let timestamp: Date

    init(role: ConversationRole, text: String, timestamp: Date = Date()) {
        self.role = role
        self.text = text
        self.timestamp = timestamp
    }
}

struct ThreadConversation: Codable {
    let channelID: String
    let threadTS: String
    var turns: [ConversationTurn]
    var updatedAt: Date

    init(channelID: String, threadTS: String, turns: [ConversationTurn] = [], updatedAt: Date = Date()) {
        self.channelID = channelID
        self.threadTS = threadTS
        self.turns = turns
        self.updatedAt = updatedAt
    }
}
