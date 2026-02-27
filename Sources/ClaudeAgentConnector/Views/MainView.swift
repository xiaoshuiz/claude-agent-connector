import SwiftUI
#if os(macOS)
import AppKit
#endif

struct MainView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(spacing: 16) {
            Form {
                Section("Slack 连接") {
                    SecureField("App-level Token (xapp-...)", text: $viewModel.appLevelToken)
                        .help("用于打开 Socket Mode 连接。请在 Slack App 的 App-Level Tokens 中创建。")
                    HStack(spacing: 12) {
                        Link("获取 xapp Token", destination: URL(string: "https://api.slack.com/apps")!)
                        Link("Socket Mode 配置指南", destination: URL(string: "https://api.slack.com/apis/connections/socket")!)
                    }
                    .font(.caption)

                    SecureField("Bot Token (xoxb-...)", text: $viewModel.botToken)
                        .help("用于调用 chat.postMessage 等 Web API。请在 OAuth & Permissions 中安装应用后获取。")
                    HStack(spacing: 12) {
                        Link("获取 xoxb Token", destination: URL(string: "https://api.slack.com/authentication/token-types")!)
                        Link("Scopes 配置指南", destination: URL(string: "https://api.slack.com/scopes")!)
                    }
                    .font(.caption)

                    TextField("监听频道 ID（逗号分隔，如 C12345,C67890）", text: $viewModel.settings.monitoredChannelIDs)
                        .help("只处理这些频道中的 @提及消息；留空表示不限制频道。")
                    HStack(spacing: 12) {
                        Link("频道 ID 获取说明", destination: URL(string: "https://slack.com/help/articles/221769328-Locate-your-Slack-URL-or-ID")!)
                    }
                    .font(.caption)

                    Text("触发方式：仅支持 @本应用（app mention）触发，不再支持命令前缀。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Claude Agent") {
                    TextField("Claude 可执行文件路径", text: $viewModel.settings.claudeExecutablePath)
                        .help("本机 Claude CLI 可执行文件路径，例如 /usr/local/bin/claude。")
                    HStack(spacing: 12) {
                        Button("从本机选择路径…") {
                            pickClaudeExecutablePath()
                        }
                        .buttonStyle(.link)
                        .help("从本机文件系统选择 claude 可执行文件。")

                        Link("Claude Code 安装文档", destination: URL(string: "https://docs.anthropic.com/en/docs/claude-code")!)
                    }
                    .font(.caption)
                }

                Section("行为设置") {
                    Toggle("启动时自动连接", isOn: $viewModel.settings.autoConnectOnLaunch)
                        .help("应用启动后自动连接 Slack。")
                    Toggle("任务完成发送系统通知", isOn: $viewModel.settings.notifyOnCompletion)
                        .help("Claude 任务完成时发送 macOS 系统通知。")

                    HStack {
                        Text("最大历史条数")
                        Spacer()
                        Stepper(value: $viewModel.settings.maxHistoryItems, in: 10...1000, step: 10) {
                            Text("\(viewModel.settings.maxHistoryItems)")
                                .frame(width: 80, alignment: .trailing)
                        }
                        .help("任务历史和 @提及记录的最大保留条数。")
                    }
                }
            }
            .formStyle(.grouped)

            HStack(spacing: 12) {
                Button("保存设置") {
                    viewModel.saveSettings()
                }

                Button(viewModel.isConnected ? "已连接" : "连接") {
                    Task {
                        await viewModel.connect()
                    }
                }
                .disabled(viewModel.isConnected)

                Button("断开") {
                    viewModel.disconnect()
                }
                .disabled(!viewModel.isConnected)

                Button("清空历史") {
                    viewModel.clearHistory()
                }

                Button("清空@提及记录") {
                    viewModel.clearMentionRecords()
                }

                Spacer()

                Label(
                    viewModel.isConnected ? "Slack 已连接" : "Slack 未连接",
                    systemImage: viewModel.isConnected ? "bolt.horizontal.circle.fill" : "bolt.horizontal.circle"
                )
                .foregroundStyle(viewModel.isConnected ? .green : .secondary)

                if viewModel.isProcessingQueue {
                    ProgressView()
                        .controlSize(.small)
                    Text("处理中")
                        .foregroundStyle(.secondary)
                }
            }

            if let latestError = viewModel.latestError, !latestError.isEmpty {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                    Text(latestError)
                        .font(.subheadline)
                    Spacer()
                }
                .padding(10)
                .background(.yellow.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            HStack(spacing: 12) {
                GroupBox("任务历史") {
                    List(viewModel.tasks) { task in
                        TaskRowView(task: task)
                    }
                    .listStyle(.plain)
                }

                GroupBox("运行日志") {
                    List(viewModel.logs, id: \.self) { line in
                        Text(line)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    .listStyle(.plain)
                }
            }

            GroupBox("@提及记录（独立于任务窗口）") {
                List(viewModel.mentionRecords) { mention in
                    MentionRecordRowView(mention: mention)
                }
                .listStyle(.plain)
                .frame(minHeight: 180)
            }
        }
        .padding(16)
    }

    private func pickClaudeExecutablePath() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.title = "选择 Claude 可执行文件"
        panel.message = "请选择本机 claude CLI 的可执行文件路径。"
        if panel.runModal() == .OK, let url = panel.url {
            viewModel.settings.claudeExecutablePath = url.path
        }
        #endif
    }
}

private struct TaskRowView: View {
    let task: AgentTask

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(task.requestText)
                    .font(.headline)
                    .lineLimit(2)
                Spacer()
                Text(statusText(task.status))
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(statusColor(task.status).opacity(0.15))
                    .foregroundStyle(statusColor(task.status))
                    .clipShape(Capsule())
            }

            Text("channel=\(task.sourceChannelID) ts=\(task.sourceMessageTS)")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let response = task.responseText, !response.isEmpty {
                Text(response)
                    .font(.subheadline)
                    .lineLimit(4)
            }

            if let error = task.errorMessage, !error.isEmpty {
                Text(error)
                    .font(.subheadline)
                    .foregroundStyle(.red)
                    .lineLimit(3)
            }

            Text(task.createdAt.formatted(date: .numeric, time: .standard))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func statusText(_ status: TaskStatus) -> String {
        switch status {
        case .queued:
            return "排队中"
        case .running:
            return "执行中"
        case .succeeded:
            return "成功"
        case .failed:
            return "失败"
        }
    }

    private func statusColor(_ status: TaskStatus) -> Color {
        switch status {
        case .queued:
            return .orange
        case .running:
            return .blue
        case .succeeded:
            return .green
        case .failed:
            return .red
        }
    }
}

private struct MentionRecordRowView: View {
    let mention: MentionRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("@提及消息")
                    .font(.headline)
                Spacer()
                Text(statusText(mention.status))
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(statusColor(mention.status).opacity(0.15))
                    .foregroundStyle(statusColor(mention.status))
                    .clipShape(Capsule())
            }

            Text(mention.rawText)
                .font(.subheadline)
                .lineLimit(2)

            if !mention.extractedPrompt.isEmpty {
                Text("提取指令: \(mention.extractedPrompt)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Text("channel=\(mention.sourceChannelID) ts=\(mention.sourceMessageTS) user=\(mention.userID ?? "-")")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text(mention.receivedAt.formatted(date: .numeric, time: .standard))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func statusText(_ status: MentionRecordStatus) -> String {
        switch status {
        case .queued:
            return "已入队"
        case .ignoredChannel:
            return "忽略: 频道不匹配"
        case .ignoredEmptyPrompt:
            return "忽略: 空指令"
        }
    }

    private func statusColor(_ status: MentionRecordStatus) -> Color {
        switch status {
        case .queued:
            return .green
        case .ignoredChannel:
            return .orange
        case .ignoredEmptyPrompt:
            return .red
        }
    }
}
