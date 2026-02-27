import Foundation

struct SlackOpenConnectionResponse: Decodable {
    let ok: Bool
    let url: String?
    let error: String?
}

struct SlackAuthTestResponse: Decodable {
    let ok: Bool
    let user: String?
    let userId: String?
    let team: String?
    let error: String?
}

struct SlackPostMessageResponse: Decodable {
    let ok: Bool
    let ts: String?
    let error: String?
}

struct SlackSocketEnvelope: Decodable {
    let envelopeId: String?
    let type: String
    let payload: SlackSocketPayload?
}

struct SlackSocketPayload: Decodable {
    let event: SlackMessageEvent?
}

struct SlackEmbeddedMessage: Decodable {
    let type: String?
    let subtype: String?
    let user: String?
    let text: String?
    let channel: String?
    let ts: String?
    let threadTs: String?
    let botId: String?
}

struct SlackMessageEvent: Decodable {
    let type: String
    let subtype: String?
    let user: String?
    let text: String?
    let channel: String?
    let ts: String?
    let threadTs: String?
    let botId: String?
    let message: SlackEmbeddedMessage?
    let previousMessage: SlackEmbeddedMessage?
}
