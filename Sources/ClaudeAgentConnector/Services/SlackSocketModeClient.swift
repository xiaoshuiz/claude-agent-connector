import Foundation

enum SlackSocketModeError: LocalizedError {
    case invalidURL
    case openConnectionFailed(String)
    case notConnected

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Socket Mode URL 无效。"
        case .openConnectionFailed(let message):
            return "Socket Mode 打开失败: \(message)"
        case .notConnected:
            return "Socket 尚未连接。"
        }
    }
}

final class SlackSocketModeClient {
    private let session: URLSession
    private var webSocketTask: URLSessionWebSocketTask?

    private(set) var isConnected = false

    var onEvent: ((SlackMessageEvent) -> Void)?
    var onConnectionStateChanged: ((Bool) -> Void)?
    var onLog: ((String) -> Void)?

    init(session: URLSession = .shared) {
        self.session = session
    }

    func connect(appLevelToken: String) async throws {
        let socketURL = try await fetchSocketURL(appLevelToken: appLevelToken)

        let task = session.webSocketTask(with: socketURL)
        webSocketTask = task
        task.resume()

        isConnected = true
        onConnectionStateChanged?(true)
        onLog?("Socket Mode 已连接。")

        receiveNextMessage()
    }

    func disconnect() {
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        isConnected = false
        onConnectionStateChanged?(false)
        onLog?("Socket Mode 已断开。")
    }

    private func fetchSocketURL(appLevelToken: String) async throws -> URL {
        guard let openURL = URL(string: "https://slack.com/api/apps.connections.open") else {
            throw SlackSocketModeError.invalidURL
        }

        var request = URLRequest(url: openURL)
        request.httpMethod = "POST"
        request.addValue("Bearer \(appLevelToken)", forHTTPHeaderField: "Authorization")
        request.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let (data, _) = try await session.data(for: request)

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(SlackOpenConnectionResponse.self, from: data)
        guard response.ok, let rawURL = response.url, let socketURL = URL(string: rawURL) else {
            throw SlackSocketModeError.openConnectionFailed(response.error ?? "unknown_error")
        }

        return socketURL
    }

    private func receiveNextMessage() {
        guard let webSocketTask else {
            return
        }

        webSocketTask.receive { [weak self] result in
            guard let self else { return }

            switch result {
            case .success(let message):
                self.handle(message)
                self.receiveNextMessage()

            case .failure(let error):
                self.onLog?("Socket 接收失败: \(error.localizedDescription)")
                self.disconnect()
            }
        }
    }

    private func handle(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            handleText(text)
        case .data(let data):
            if let text = String(data: data, encoding: .utf8) {
                handleText(text)
            } else {
                onLog?("收到二进制消息，无法解码。")
            }
        @unknown default:
            onLog?("收到未知 WebSocket 消息。")
        }
    }

    private func handleText(_ text: String) {
        guard let data = text.data(using: .utf8) else {
            return
        }

        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let envelope = try decoder.decode(SlackSocketEnvelope.self, from: data)

            if let envelopeId = envelope.envelopeId {
                sendAck(envelopeID: envelopeId)
            }

            if envelope.type == "hello" {
                onLog?("Socket 握手完成。")
                return
            }

            guard envelope.type == "events_api", let event = envelope.payload?.event else {
                return
            }

            if event.botId != nil {
                return
            }

            if event.type == "app_mention" || event.type == "message" {
                onEvent?(event)
            }
        } catch {
            onLog?("消息解析失败: \(error.localizedDescription)")
        }
    }

    private func sendAck(envelopeID: String) {
        guard let webSocketTask else {
            return
        }
        let payload = "{\"envelope_id\":\"\(envelopeID)\"}"
        webSocketTask.send(.string(payload)) { [weak self] error in
            if let error {
                self?.onLog?("ACK 发送失败: \(error.localizedDescription)")
            }
        }
    }
}
