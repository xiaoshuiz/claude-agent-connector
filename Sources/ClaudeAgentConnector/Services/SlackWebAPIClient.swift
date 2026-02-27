import Foundation

enum SlackWebAPIClientError: LocalizedError {
    case invalidURL
    case invalidHTTPResponse
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Slack API URL 无效。"
        case .invalidHTTPResponse:
            return "Slack API 返回了无效响应。"
        case .apiError(let message):
            return "Slack API 错误: \(message)"
        }
    }
}

final class SlackWebAPIClient {
    private var botToken: String
    private let session: URLSession

    init(botToken: String, session: URLSession = .shared) {
        self.botToken = botToken
        self.session = session
    }

    func updateBotToken(_ token: String) {
        botToken = token
    }

    func authTest() async throws -> SlackAuthTestResponse {
        let data = try await post(
            endpoint: "https://slack.com/api/auth.test",
            payload: [:]
        )
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(SlackAuthTestResponse.self, from: data)
        if !response.ok {
            throw SlackWebAPIClientError.apiError(response.error ?? "auth.test 失败")
        }
        return response
    }

    @discardableResult
    func postMessage(channel: String, text: String, threadTS: String?) async throws -> String {
        var payload: [String: Any] = [
            "channel": channel,
            "text": text
        ]
        if let threadTS {
            payload["thread_ts"] = threadTS
        }

        let data = try await post(
            endpoint: "https://slack.com/api/chat.postMessage",
            payload: payload
        )

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(SlackPostMessageResponse.self, from: data)
        if !response.ok {
            throw SlackWebAPIClientError.apiError(response.error ?? "chat.postMessage 失败")
        }
        return response.ts ?? ""
    }

    private func post(endpoint: String, payload: [String: Any]) async throws -> Data {
        guard let url = URL(string: endpoint) else {
            throw SlackWebAPIClientError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(botToken)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SlackWebAPIClientError.invalidHTTPResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw SlackWebAPIClientError.apiError("HTTP \(httpResponse.statusCode)")
        }
        return data
    }
}
