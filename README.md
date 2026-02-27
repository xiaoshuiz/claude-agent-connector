# Claude Agent Connector

一个面向 macOS 的桌面应用，用于把 Slack 消息桥接到本地 Claude Agent（Claude Code CLI），并把执行结果自动回帖到 Slack 线程。

## 核心能力

- **SwiftUI + AppKit** 桌面应用界面（含状态栏菜单）
- **Slack Socket Mode** 实时监听消息事件
- 支持 `xapp-`（App-level token）与 `xoxb-`（Bot token）配置
- 监听指定频道（可多个频道 ID）
- 支持命令前缀触发（默认 `/claude`）和 bot mention 触发
- 调用本地 `claude` 命令执行任务并将结果回复到 Slack
- Keychain 安全保存 token（非 macOS 环境下自动降级为本地存储）
- 任务历史、运行日志、失败回帖、系统通知

## 目录结构

```text
Sources/ClaudeAgentConnector
├── ClaudeAgentConnectorApp.swift
├── AppViewModel.swift
├── StatusBarController.swift
├── Models
│   ├── AgentTask.swift
│   ├── AppSettings.swift
│   └── SlackModels.swift
├── Services
│   ├── ClaudeAgentRunner.swift
│   ├── KeychainStore.swift
│   ├── NotificationService.swift
│   ├── SettingsStore.swift
│   ├── SlackSocketModeClient.swift
│   ├── SlackWebAPIClient.swift
│   └── TaskHistoryStore.swift
└── Views
    └── MainView.swift
```

## 环境要求

- macOS 14+
- Xcode 15+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)（用于生成 `.xcodeproj`）
- 本地已安装 Claude CLI（`claude`）

## 运行前准备

### 1) Slack App 配置

在你的 Slack App 中启用并配置：

1. **Socket Mode**（开启）
2. **Event Subscriptions**（订阅 `app_mention`、`message.channels` 等你需要的事件）
3. Bot OAuth Scopes 至少包含：
   - `chat:write`
   - `channels:history`（按需）
   - `app_mentions:read`
4. 安装到目标工作区后，拿到：
   - `xapp-...` App-level Token
   - `xoxb-...` Bot Token

### 2) 本地 Claude CLI

确保机器上可执行 `claude` 命令，默认路径：

```bash
/usr/local/bin/claude
```

如果路径不同，可在应用设置中修改。

## 开发运行

```bash
brew install xcodegen
xcodegen generate --spec project.yml
open ClaudeAgentConnector.xcodeproj
```

然后在 Xcode 中运行 `ClaudeAgentConnector`（Debug）。

也可以命令行构建：

```bash
make debug-build
```

## 构建 release app

### 本地打包（生成可分发 zip）

```bash
make release
```

产物位于：

- `dist/ClaudeAgentConnector-macOS-Release.zip`
- `dist/ClaudeAgentConnector-macOS-Release.zip.sha256`

### GitHub Actions 自动 release

仓库已内置两个工作流：

- `.github/workflows/ci-macos.yml`：每次 push/PR 在 macOS 上构建
- `.github/workflows/release.yml`：tag 发布时自动打包并上传 release 资产

触发正式发布：

```bash
git tag v0.1.0
git push origin v0.1.0
```

随后在 GitHub Release 页面可直接下载 zip 版 app。

## 使用流程

1. 打开应用，填写 `xapp`、`xoxb`、监听频道 ID。
2. 配置 Claude 命令路径与触发前缀（默认 `/claude`）。
3. 点击「连接」。
4. 在 Slack 目标频道发送：
   - `/claude 你的任务`
   - 或 `@bot 你的任务`
5. 应用执行本地 Claude，完成后自动在线程中回复结果。

## 注意事项

- 当前版本采用**串行任务队列**，避免并发执行导致本地环境竞争。
- 若 `claude` 执行失败，会自动在线程回复错误信息。
- 若开启通知，任务完成会触发系统通知。
