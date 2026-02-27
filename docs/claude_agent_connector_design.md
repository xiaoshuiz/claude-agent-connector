# Claude Agent Connector 设计说明（实现版）

## 1. 目标

在 macOS 上提供一个本地桌面应用，将 Slack 中的指令消息桥接到本机 Claude Agent（`claude` CLI），并把执行结果自动回帖到原线程。

## 2. 关键设计点

1. **连接层**
   - 使用 Slack `apps.connections.open` 获取 Socket Mode WebSocket URL。
   - 通过 WebSocket 接收 `events_api` 事件并发送 `envelope_id` ACK。
2. **执行层**
   - 从消息中提取 prompt（命令前缀或 bot mention 触发）。
   - 通过 `Process` 启动本地 `claude -p "<prompt>"`。
3. **回写层**
   - 通过 `chat.postMessage` 将结果回帖到 `thread_ts`（若无则用原消息 ts）。
4. **状态与安全**
   - token 存储在 Keychain。
   - 任务历史持久化到 Application Support。
   - 提供运行日志与可选系统通知。

## 3. 模块划分

- `AppViewModel`: 状态管理、事件编排、任务队列
- `SlackSocketModeClient`: Socket Mode 链路
- `SlackWebAPIClient`: `auth.test` + `chat.postMessage`
- `ClaudeAgentRunner`: 本地 Claude 执行
- `SettingsStore / KeychainStore / TaskHistoryStore`: 配置、密钥、历史持久化
- `MainView`: 配置面板、历史与日志展示
- `StatusBarController`: macOS 状态栏入口

## 4. 触发规则

- 支持命令前缀：默认 `/claude`
- 支持 bot mention：`<@BOT_USER_ID>`
- 可配置频道白名单（多个频道 ID）

## 5. 任务模型

- 状态：`queued` / `running` / `succeeded` / `failed`
- 默认串行执行，避免本地资源竞争
- 失败时自动将错误回帖到 Slack

## 6. 后续可扩展

- 多任务并发池与优先级
- 更细粒度的失败重试策略
- 任务取消与中断
- 更丰富的消息模板与长输出分片
