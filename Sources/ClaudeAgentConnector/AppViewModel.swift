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
    @Published var mentionRecords: [MentionRecord] = []
    @Published var logs: [String] = []
    @Published var latestError: String?

    private let settingsStore: SettingsStore
    private let secretsStore: SecretsStore
    private let historyStore: TaskHistoryStore
    private let conversationStore: ThreadConversationStore
    private let notificationService: NotificationService
    private let socketClient: SlackSocketModeClient
    private let runner: ClaudeAgentRunner

    private var webAPIClient: SlackWebAPIClient?
    private var threadConversations: [String: ThreadConversation]
    private var pendingRequests: [QueuedRequest] = []
    private var isQueueRunning = false
    private let maxTurnsPerThreadContext = 20
    private let maxStoredThreadContexts = 500

    private struct QueuedRequest {
        let channelID: String
        let messageTS: String
        let threadTS: String
        let prompt: String
    }

    init(
        settingsStore: SettingsStore = SettingsStore(),
        secretsStore: SecretsStore = KeychainStore(),
        historyStore: TaskHistoryStore = TaskHistoryStore(),
        conversationStore: ThreadConversationStore = ThreadConversationStore(),
        notificationService: NotificationService = NotificationService(),
        socketClient: SlackSocketModeClient = SlackSocketModeClient(),
        runner: ClaudeAgentRunner = ClaudeAgentRunner()
    ) {
        self.settingsStore = settingsStore
        self.secretsStore = secretsStore
        self.historyStore = historyStore
        self.conversationStore = conversationStore
        self.notificationService = notificationService
        self.socketClient = socketClient
        self.runner = runner

        let loadedSettings = settingsStore.load()
        settings = loadedSettings
        appLevelToken = secretsStore.load(field: .appLevelToken)
        botToken = secretsStore.load(field: .botToken)
        tasks = historyStore.load().sorted { $0.createdAt > $1.createdAt }
        threadConversations = conversationStore.load()

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

    func clearMentionRecords() {
        mentionRecords.removeAll()
        appendLog("@提及记录已清空。")
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
        let rootThreadTS = event.threadTs ?? messageTS

        guard isMentionTrigger(event: event, text: rawText) else {
            return
        }

        if !settings.normalizedChannelIDs.isEmpty && !settings.normalizedChannelIDs.contains(channelID) {
            recordMention(
                channelID: channelID,
                messageTS: messageTS,
                threadTS: rootThreadTS,
                userID: event.user,
                rawText: rawText,
                extractedPrompt: "",
                status: .ignoredChannel
            )
            return
        }

        let prompt = extractPrompt(from: rawText)
        guard !prompt.isEmpty else {
            recordMention(
                channelID: channelID,
                messageTS: messageTS,
                threadTS: rootThreadTS,
                userID: event.user,
                rawText: rawText,
                extractedPrompt: "",
                status: .ignoredEmptyPrompt
            )
            return
        }

        recordMention(
            channelID: channelID,
            messageTS: messageTS,
            threadTS: rootThreadTS,
            userID: event.user,
            rawText: rawText,
            extractedPrompt: prompt,
            status: .queued
        )

        let request = QueuedRequest(
            channelID: channelID,
            messageTS: messageTS,
            threadTS: rootThreadTS,
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
            let promptWithContext = buildPromptWithContext(
                channelID: request.channelID,
                threadTS: request.threadTS,
                latestPrompt: request.prompt
            )
            let result = try await runner.run(
                prompt: promptWithContext,
                executablePath: settings.claudeExecutablePath
            )

            let output = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            let response = output.isEmpty ? "Claude 没有返回可见内容。" : output
            try await webAPIClient.postMessage(
                channel: request.channelID,
                text: response,
                threadTS: request.threadTS
            )
            appendConversationTurns(
                channelID: request.channelID,
                threadTS: request.threadTS,
                turns: [
                    ConversationTurn(role: .user, text: request.prompt),
                    ConversationTurn(role: .assistant, text: response)
                ]
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
            try? await webAPIClient.postMessage(
                channel: request.channelID,
                text: "❌ 执行失败：\(reason)",
                threadTS: request.threadTS
            )
            appendConversationTurns(
                channelID: request.channelID,
                threadTS: request.threadTS,
                turns: [
                    ConversationTurn(role: .user, text: request.prompt),
                    ConversationTurn(role: .assistant, text: "执行失败：\(reason)")
                ]
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

    private func isMentionTrigger(event: SlackMessageEvent, text: String) -> Bool {
        if event.type == "app_mention" {
            return true
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !botUserID.isEmpty, trimmed.contains("<@\(botUserID)>") {
            return true
        }
        return false
    }

    private func extractPrompt(from text: String) -> String {
        let cleaned: String
        if !botUserID.isEmpty {
            cleaned = text.replacingOccurrences(of: "<@\(botUserID)>", with: "")
        } else {
            cleaned = stripLeadingMentionToken(from: text)
        }
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func stripLeadingMentionToken(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("<@"), let closing = trimmed.firstIndex(of: ">") else {
            return trimmed
        }
        let afterMention = trimmed.index(after: closing)
        return String(trimmed[afterMention...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func recordMention(
        channelID: String,
        messageTS: String,
        threadTS: String?,
        userID: String?,
        rawText: String,
        extractedPrompt: String,
        status: MentionRecordStatus
    ) {
        let record = MentionRecord(
            sourceChannelID: channelID,
            sourceMessageTS: messageTS,
            sourceThreadTS: threadTS,
            userID: userID,
            rawText: rawText,
            extractedPrompt: extractedPrompt,
            status: status
        )
        mentionRecords.insert(record, at: 0)
        if mentionRecords.count > max(settings.maxHistoryItems, 100) {
            mentionRecords = Array(mentionRecords.prefix(max(settings.maxHistoryItems, 100)))
        }
    }

    private func buildPromptWithContext(channelID: String, threadTS: String, latestPrompt: String) -> String {
        let key = conversationKey(channelID: channelID, threadTS: threadTS)
        guard let conversation = threadConversations[key], !conversation.turns.isEmpty else {
            return latestPrompt
        }

        let recentTurns = conversation.turns.suffix(maxTurnsPerThreadContext)
        var sections: [String] = []
        sections.append(
            """
            You are continuing an existing Slack thread conversation.
            Use the conversation history to keep context and answer the latest user request.
            """
        )

        let historyLines = recentTurns.map { turn in
            let role = turn.role == .user ? "User" : "Assistant"
            return "\(role): \(turn.text)"
        }.joined(separator: "\n")
        sections.append("Conversation history:\n\(historyLines)")
        sections.append("Latest user request:\n\(latestPrompt)")
        sections.append("Please answer as the assistant in this same Slack thread.")

        appendLog("线程上下文已加载：\(recentTurns.count) 条历史消息。")
        return sections.joined(separator: "\n\n")
    }

    private func appendConversationTurns(channelID: String, threadTS: String, turns: [ConversationTurn]) {
        let normalizedTurns = turns.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !normalizedTurns.isEmpty else {
            return
        }

        let key = conversationKey(channelID: channelID, threadTS: threadTS)
        var conversation = threadConversations[key] ?? ThreadConversation(channelID: channelID, threadTS: threadTS)
        conversation.turns.append(contentsOf: normalizedTurns)
        let maxTurnCapacity = maxTurnsPerThreadContext * 2
        if conversation.turns.count > maxTurnCapacity {
            conversation.turns = Array(conversation.turns.suffix(maxTurnCapacity))
        }
        conversation.updatedAt = Date()
        threadConversations[key] = conversation
        persistConversations()
    }

    private func persistConversations() {
        if threadConversations.count > maxStoredThreadContexts {
            let sortedKeys = threadConversations
                .sorted { $0.value.updatedAt > $1.value.updatedAt }
                .prefix(maxStoredThreadContexts)
                .map(\.key)
            let keepKeys = Set(sortedKeys)
            threadConversations = threadConversations.reduce(into: [:]) { partial, pair in
                if keepKeys.contains(pair.key) {
                    partial[pair.key] = pair.value
                }
            }
        }
        conversationStore.save(threadConversations)
    }

    private func conversationKey(channelID: String, threadTS: String) -> String {
        "\(channelID)|\(threadTS)"
    }
}
