import SwiftUI

struct MainView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(spacing: 16) {
            Form {
                Section("Slack 连接") {
                    SecureField("App-level Token (xapp-...)", text: $viewModel.appLevelToken)
                    SecureField("Bot Token (xoxb-...)", text: $viewModel.botToken)
                    TextField("监听频道 ID（逗号分隔，如 C12345,C67890）", text: $viewModel.settings.monitoredChannelIDs)
                }

                Section("Claude Agent") {
                    TextField("Claude 可执行文件路径", text: $viewModel.settings.claudeExecutablePath)
                    TextField("触发命令前缀（如 /claude）", text: $viewModel.settings.commandPrefix)
                }

                Section("行为设置") {
                    Toggle("启动时自动连接", isOn: $viewModel.settings.autoConnectOnLaunch)
                    Toggle("任务完成发送系统通知", isOn: $viewModel.settings.notifyOnCompletion)

                    HStack {
                        Text("最大历史条数")
                        Spacer()
                        Stepper(value: $viewModel.settings.maxHistoryItems, in: 10...1000, step: 10) {
                            Text("\(viewModel.settings.maxHistoryItems)")
                                .frame(width: 80, alignment: .trailing)
                        }
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
        }
        .padding(16)
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
