# Architecture

## System overview

Claude Agent Connector is a local-first macOS app with no server-side runtime.  
It bridges Slack messages to local Claude CLI execution and posts results back to Slack.

```text
Slack (Socket Mode events)
          |
          v
SlackSocketModeClient ----> AppViewModel (filter, queue, state)
                                  |
                                  v
                         ClaudeAgentRunner (local Process)
                                  |
                                  v
                      SlackWebAPIClient (chat.postMessage)
```

## Main modules

### `AppViewModel`

The orchestration layer:

- holds UI-facing state (`@Published`)
- validates settings and tokens
- receives incoming Slack events
- applies mention-only trigger logic (`@app`)
- creates and updates task history
- creates and updates dedicated mention records
- serializes execution with an in-memory queue

### `SlackSocketModeClient`

Connection and event intake:

- opens Socket Mode session using `apps.connections.open`
- maintains WebSocket lifecycle
- acknowledges envelopes (`envelope_id`)
- parses `events_api` payloads to typed event models

### `SlackWebAPIClient`

Outbound Slack API:

- `auth.test` for startup validation
- `chat.postMessage` for threaded responses

### `ClaudeAgentRunner`

Local execution:

- invokes `claude -p <prompt>` via `Process`
- captures stdout/stderr
- maps non-zero exits to user-visible errors

### Persistence services

- `SettingsStore`: app settings via `UserDefaults`
- `KeychainStore`: token storage in Keychain
- `TaskHistoryStore`: JSON history in Application Support
- `ThreadConversationStore`: JSON thread context memory in Application Support

## Event handling lifecycle

1. Slack event arrives through Socket Mode.
2. Envelope is acknowledged immediately.
3. Event is ignored unless:
   - channel matches allowlist (if configured)
   - message includes app mention (or `app_mention` event type)
   - fallback: plain-text `@botName` mention matches when Slack sends a `message` event
4. Prompt is extracted and queued.
5. Before execution, recent thread turns are injected into the prompt context.
6. Queue executes tasks one-by-one.
7. Result or error is posted back to the same thread.
8. Task history, mention records, logs, and thread context are persisted locally.

## Failure strategy

- Network/API issues are surfaced in UI logs.
- Claude process errors are reflected in task status and Slack thread reply.
- Connector stays alive after task failure; next queued tasks continue.

## Security posture

- App-level and bot tokens are persisted through Keychain APIs.
- No external backend stores prompts or outputs by default.
- Operational logs are local to the machine.

## Future extensions

- controlled concurrency execution pool
- retry policy with exponential backoff
- richer observability and exportable diagnostics bundle
