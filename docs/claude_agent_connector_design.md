# Claude Agent Connector Design (Implemented)

## 1) Goal

Provide a local macOS desktop app that bridges Slack trigger messages to a local Claude agent (`claude` CLI), and posts execution results back to the originating Slack thread.

## 2) Core design decisions

1. **Connection layer**
   - Use Slack `apps.connections.open` to obtain a Socket Mode WebSocket URL.
   - Receive `events_api` envelopes and send `envelope_id` acknowledgements.
2. **Execution layer**
   - Extract prompt from incoming message (prefix or bot mention trigger).
   - Launch local process via `claude -p "<prompt>"`.
3. **Reply layer**
   - Post output through `chat.postMessage` to `thread_ts` (fallback to source message ts).
4. **State and security**
   - Persist tokens in Keychain.
   - Persist task history in Application Support.
   - Keep local logs and optional desktop notifications.

## 3) Module mapping

- `AppViewModel`: state, orchestration, task queue
- `SlackSocketModeClient`: Socket Mode transport
- `SlackWebAPIClient`: `auth.test` and `chat.postMessage`
- `ClaudeAgentRunner`: local Claude execution
- `SettingsStore / KeychainStore / TaskHistoryStore`: persistence layer
- `MainView`: settings panel, history, and logs
- `StatusBarController`: macOS menu bar integration

## 4) Trigger rules

- Command prefix trigger (default `/claude`)
- Bot mention trigger (`<@BOT_USER_ID>`)
- Optional channel allowlist (multiple channel IDs)

## 5) Task model

- Lifecycle: `queued` / `running` / `succeeded` / `failed`
- Queue is serialized by default to avoid local resource contention
- Failures are posted back to Slack thread automatically

## 6) Planned extensions

- controlled concurrent execution pool
- finer retry policies and backoff
- task cancellation and interruption support
- message chunking and richer response templates
