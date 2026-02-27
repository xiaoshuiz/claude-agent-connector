import Foundation
import Combine

@MainActor
final class AppViewModel: ObservableObject {
    @Published var settings: AppSettings
    @Published var appLevelToken: String
    @Published var botToken: String
    @Published var isConnected = false
    @Published var isProcessingQueue = false
    @Published var botUserID = ""
    @Published var tasks: [AgentTask]
    @Published var logs: [String] = []
    @Published var latestError: String?

    private let settingsStore: SettingsStore
    private let secretsStore: SecretsStore
    private let historyStore: TaskHistoryStore
    private let notificationService: NotificationService
    private let socketClient: SlackSocketModeClient
    private let runner: ClaudeAgentRunner

    private var webAPIClient: SlackWebAPIClient?
    private var pendingRequests: [QueuedRequest] = []
    private var isQueueRunning = false

    private struct QueuedRequest {
        let channelID: String
        let messageTS: String
        let threadTS: String?
        let prompt: String
    }

    init(
        settingsStore: SettingsStore = SettingsStore(),
        secretsStore: SecretsStore = KeychainStore(),
        historyStore: TaskHistoryStore = TaskHistoryStore(),
        notificationService: NotificationService = NotificationService(),
        socketClient: SlackSocketModeClient = SlackSocketModeClient(),
        runner: ClaudeAgentRunner = ClaudeAgentRunner()
    ) {
        self.settingsStore = settingsStore
        self.secretsStore = secretsStore
        self.historyStore = historyStore
        self.notificationService = notificationService
        self.socketClient = socketClient
        self.runner = runner

        let loadedSettings = settingsStore.load()
        settings = loadedSettings
        appLevelToken = secretsStore.load(field: .appLevelToken)
        botToken = secretsStore.load(field: .botToken)
        tasks = historyStore.load().sorted { $0.createdAt > $1.createdAt }

        if !botToken.isEmpty {
            webAPIClient = SlackWebAPIClient(botToken: botToken)
        }

        setupSocketCallbacks()
        appendLog("应用已初始化。")

        if settings.autoConnectOnLaunch {
            Task {
                await connect()
            }
        }
    }

    func saveSettings() {
        settingsStore.save(settings)
        do {
            if appLevelToken.isEmpty {
                try secretsStore.remove(field: .appLevelToken)
            } else {
                try secretsStore.save(value: appLevelToken, field: .appLevelToken)
            }

            if botToken.isEmpty {
                try secretsStore.remove(field: .botToken)
            } else {
                try secretsStore.save(value: botToken, field: .botToken)
            }
            appendLog("设置与密钥已保存。")
        } catch {
            latestError = error.localizedDescription
            appendLog("保存密钥失败: \(error.localizedDescription)")
        }
    }

    func connect() async {
        guard !isConnected else {
            appendLog("当前已处于连接状态。")
            return
        }

        guard !appLevelToken.isEmpty, !botToken.isEmpty else {
            latestError = "请先填写 xapp 与 xoxb token。"
            appendLog(latestError ?? "")
            return
        }

        saveSettings()
        notificationService.requestAuthorizationIfNeeded()

        if webAPIClient == nil {
            webAPIClient = SlackWebAPIClient(botToken: botToken)
        } else {
            webAPIClient?.updateBotToken(botToken)
        }

        do {
            if let auth = try await webAPIClient?.authTest() {
                botUserID = auth.userId ?? ""
                appendLog("Slack 鉴权成功，team=\(auth.team ?? "-") user=\(botUserID)")
            }

            try await socketClient.connect(appLevelToken: appLevelToken)
        } catch {
            latestError = error.localizedDescription
            appendLog("连接失败: \(error.localizedDescription)")
        }
    }

    func disconnect() {
        socketClient.disconnect()
    }

    func clearHistory() {
        tasks.removeAll()
        historyStore.save([])
        appendLog("任务历史已清空。")
    }

    private func setupSocketCallbacks() {
        socketClient.onConnectionStateChanged = { [weak self] connected in
            Task { @MainActor in
                self?.isConnected = connected
            }
        }

        socketClient.onLog = { [weak self] line in
            Task { @MainActor in
                self?.appendLog(line)
            }
        }

        socketClient.onEvent = { [weak self] event in
            Task { @MainActor in
                self?.acceptIncomingEvent(event)
            }
        }
    }

    private func acceptIncomingEvent(_ event: SlackMessageEvent) {
        guard let channelID = event.channel, let messageTS = event.ts, let rawText = event.text else {
            return
        }

        if !settings.normalizedChannelIDs.isEmpty && !settings.normalizedChannelIDs.contains(channelID) {
            return
        }

        guard shouldTrigger(with: rawText) else {
            return
        }

        let prompt = extractPrompt(from: rawText)
        guard !prompt.isEmpty else {
            return
        }

        let request = QueuedRequest(
            channelID: channelID,
            messageTS: messageTS,
            threadTS: event.threadTs,
            prompt: prompt
        )
        pendingRequests.append(request)
        appendLog("任务已入队，channel=\(channelID)")

        startQueueIfNeeded()
    }

    private func startQueueIfNeeded() {
        guard !isQueueRunning else {
            return
        }

        isQueueRunning = true
        isProcessingQueue = true

        Task {
            await processQueue()
        }
    }

    private func processQueue() async {
        while !pendingRequests.isEmpty {
            let request = pendingRequests.removeFirst()
            await execute(request: request)
        }
        isQueueRunning = false
        isProcessingQueue = false
    }

    private func execute(request: QueuedRequest) async {
        guard let webAPIClient else {
            appendLog("任务执行失败：Slack API 客户端未初始化。")
            return
        }

        var task = AgentTask(
            sourceChannelID: request.channelID,
            sourceThreadTS: request.threadTS,
            sourceMessageTS: request.messageTS,
            requestText: request.prompt,
            status: .running
        )
        task.startedAt = Date()
        tasks.insert(task, at: 0)
        persistHistory()
        appendLog("开始执行任务 \(task.id.uuidString.prefix(8))")

        do {
            let result = try await runner.run(
                prompt: request.prompt,
                executablePath: settings.claudeExecutablePath
            )

            let output = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            let response = output.isEmpty ? "Claude 没有返回可见内容。" : output
            let replyThreadTS = request.threadTS ?? request.messageTS
            try await webAPIClient.postMessage(
                channel: request.channelID,
                text: response,
                threadTS: replyThreadTS
            )

            updateTask(
                id: task.id,
                status: .succeeded,
                responseText: response,
                error: nil
            )
            appendLog("任务完成并已回帖到 Slack。")

            if settings.notifyOnCompletion {
                notificationService.send(
                    title: "Claude Agent 任务完成",
                    body: "channel=\(request.channelID) 已完成一次回复。"
                )
            }
        } catch {
            let reason = error.localizedDescription
            let replyThreadTS = request.threadTS ?? request.messageTS
            try? await webAPIClient.postMessage(
                channel: request.channelID,
                text: "❌ 执行失败：\(reason)",
                threadTS: replyThreadTS
            )

            updateTask(
                id: task.id,
                status: .failed,
                responseText: nil,
                error: reason
            )
            appendLog("任务失败: \(reason)")
        }
    }

    private func updateTask(id: UUID, status: TaskStatus, responseText: String?, error: String?) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else {
            return
        }
        tasks[index].status = status
        tasks[index].finishedAt = Date()
        tasks[index].responseText = responseText
        tasks[index].errorMessage = error
        persistHistory()
    }

    private func persistHistory() {
        if tasks.count > settings.maxHistoryItems {
            tasks = Array(tasks.prefix(settings.maxHistoryItems))
        }
        historyStore.save(tasks)
    }

    private func appendLog(_ line: String) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        logs.append("[\(formatter.string(from: Date()))] \(line)")
        if logs.count > 500 {
            logs = Array(logs.suffix(500))
        }
    }

    private func shouldTrigger(with text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !settings.commandPrefix.isEmpty, trimmed.hasPrefix(settings.commandPrefix) {
            return true
        }
        if !botUserID.isEmpty, trimmed.contains("<@\(botUserID)>") {
            return true
        }
        return false
    }

    private func extractPrompt(from text: String) -> String {
        var cleaned = text
        if !botUserID.isEmpty {
            cleaned = cleaned.replacingOccurrences(of: "<@\(botUserID)>", with: "")
        }

        let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        if !settings.commandPrefix.isEmpty, trimmed.hasPrefix(settings.commandPrefix) {
            let dropped = trimmed.dropFirst(settings.commandPrefix.count)
            return String(dropped).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed
    }
}
