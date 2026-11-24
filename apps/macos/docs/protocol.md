# Swft WebSocket & RPC Protocol Reference

Precise wire reference for the T3 Code Node server (`apps/server`, orchestration protocol v2) as consumed by `SwftKit` and the web client (`packages/contracts`, `packages/client-runtime`, `apps/web`).

---

## 1. Transport, Discovery, and Authentication Handshake

Each running server instance represents **one execution environment** (`environmentId`). Multi-environment support is multiple independent `ServerConnection` instances.

### Step 1 — Environment Discovery (unauthenticated)

```
GET /.well-known/t3/environment
```

Returns `200 OK` JSON (`ExecutionEnvironmentDescriptor`):

```json
{
  "environmentId": "603033b9-f97d-42a3-9075-583217adfa8b",
  "label": "MacBook Pro",
  "platform": { "os": "darwin", "arch": "arm64", "machine": "laptop" },
  "serverVersion": "0.1.11",
  "orchestrationProtocolVersion": 2,
  "databaseMigration": 111,
  "capabilities": {
    "repositoryIdentity": true,
    "connectionProbe": true,
    "threadStop": true,
    "threadForceStop": true,
    "threadVisitedTracking": true,
    "shellThreadFamilies": true,
    "shellOlderSettled": true
  }
}
```

- **Protocol gate**: Clients MUST verify `orchestrationProtocolVersion == 2`. Connecting without protocol 2 is rejected at WebSocket upgrade with HTTP `426` (`orchestration_protocol_incompatible`).

### Step 2 — Exchange Bootstrap Credential for Access Token

```
POST /oauth/token
Content-Type: application/x-www-form-urlencoded
```

Form body:

- `grant_type=urn:ietf:params:oauth:grant-type:token-exchange`
- `subject_token=<bootstrapToken>`
- `subject_token_type=urn:t3:params:oauth:token-type:environment-bootstrap`
- `requested_token_type=urn:ietf:params:oauth:token-type:access_token`
- Optional client metadata: `client_label=Swft`, `client_device_type=desktop`, `client_os=macOS`, `scope=...`

Bootstrap token sources:

1. **Desktop-managed local server (`desktop-bootstrap`)**: passed via `--bootstrap-fd 0` stdin JSON (`desktopBootstrapToken`, or derived from `desktopBootstrapSecret` as lowercase hex `HMAC-SHA256(secret, "t3-desktop-bootstrap:" + floor(epochMs / 43_200_000))`). Grants full administrative scopes and replaces any previous `desktop-bootstrap` session.
2. **Remote pairing (`one-time-token`)**: single-use pairing credential printed by `t3 serve` or minted via Settings.

Returns `200 OK` JSON (`AuthAccessTokenResult`):

```json
{
  "access_token": "<opaque-signed-session-token>",
  "issued_token_type": "urn:ietf:params:oauth:token-type:access_token",
  "token_type": "Bearer",
  "expires_in": 2591999,
  "scope": "orchestration:read orchestration:operate ..."
}
```

_(Note: DPoP-bound tokens from remote pairing links use `token_type: "DPoP"` and can renew via `subject_token_type=urn:ietf:params:oauth:token-type:access_token`; local desktop bootstrap uses `Bearer`.)_

### Step 3 — Mint Short-Lived WebSocket Ticket

```
POST /api/auth/websocket-ticket/rpc
Authorization: Bearer <access_token>
```

_(Fallback to `POST /api/auth/websocket-ticket` if `404` on older servers.)_

Returns `200 OK` JSON (`AuthWebSocketTicketResult`):

```json
{
  "ticket": "<short-lived-single-use-ticket>",
  "expiresAt": "2026-11-24T20:01:00.411Z"
}
```

### Step 4 — WebSocket Upgrade

```
GET /ws?orchestrationProtocol=2&wsTicket=<ticket>&frameParts=1&clientSurface=desktop&clientDeviceType=desktop&clientOs=macOS&connectionMethod=direct
```

Query parameters:

- `orchestrationProtocol=2` (**required**; missing or other values return HTTP `426`)
- `wsTicket=<ticket>` (required for ticket auth; `Authorization: Bearer <token>` header is also accepted if `wsTicket` is absent)
- `frameParts=1` (opts into chunked multi-part frames for payloads > 48 KiB UTF-8)
- Analytics/telemetry hints: `clientSurface` (`web|desktop|mobile|cli`), `clientDeviceType` (`desktop|phone|tablet|unknown`), `clientOs` (`macOS|...`), `connectionMethod` (`direct|ssh|relay|unknown`)

Notes:

- The server disables `permessage-deflate` for `desktop-bootstrap` sessions.
- Every reconnect MUST mint a fresh `wsTicket` (tickets are single-use and short-lived). If minting fails with `401`, re-exchange the bootstrap credential for a new `access_token`.

---

## 2. Frame Splitting (`frameParts=1`)

When the client connects with `frameParts=1`, the server splits outbound UTF-8 text frames larger than **48 KiB** (`49,152` bytes) into multiple WebSocket text frames (`packages/shared/src/socketFrameParts.ts`):

- Every **non-final** part begins with ASCII Record Separator `U+001E` (`\u001e`).
- The **final** part does **not** begin with `\u001e`.
- Client reassembly:
  1. If `frame.hasPrefix("\u{1E}")`, drop the leading `U+001E`, append to buffer, and wait for the next frame (resetting the liveness timer).
  2. Otherwise, concatenate `buffer + frame`, clear `buffer`, and decode as a single JSON RPC message.

---

## 3. Effect RPC Message Envelope

The WebSocket carries Effect RPC JSON messages (`effect/rpc/RpcSerialization.layerJson`).

### Client → Server (`FromClientEncoded`)

| `_tag`      | Wire JSON                                                                    | Semantics                                                                                                                                                                                                                                                    |
| ----------- | ---------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `Request`   | `{"_tag":"Request","id":"1","tag":"<method>","payload":<json>,"headers":[]}` | Starts a unary RPC or streaming subscription. `id` is a monotonically increasing string (or integer) unique per connection. **`headers: []` is mandatory** — omitting it causes server-side decode failure.                                                  |
| `Ack`       | `{"_tag":"Ack","requestId":"1"}`                                             | **MANDATORY backpressure ack for streaming RPCs.** The server's `RpcServer` blocks on an internal latch after sending every `Chunk` until the client replies with `Ack` for that `requestId`. Failing to send `Ack` stalls the stream after its first chunk. |
| `Interrupt` | `{"_tag":"Interrupt","requestId":"1"}`                                       | Cancels an in-flight unary RPC or unsubscribes an active stream.                                                                                                                                                                                             |
| `Ping`      | `{"_tag":"Ping"}`                                                            | Client liveness probe. Server replies with `{"_tag":"Pong"}`.                                                                                                                                                                                                |
| `Eof`       | `{"_tag":"Eof"}`                                                             | Graceful client half-close prior to closing the WebSocket.                                                                                                                                                                                                   |

### Server → Client (`FromServerEncoded`)

| `_tag`           | Wire JSON                                                                          | Semantics                                                                                                                                                       |
| ---------------- | ---------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `Chunk`          | `{"_tag":"Chunk","requestId":"1","values":[<item>, ...]}`                          | Streaming RPC batch (one or more items). Client MUST send `Ack` for `requestId`.                                                                                |
| `Exit` (Success) | `{"_tag":"Exit","requestId":"1","exit":{"_tag":"Success","value":<json>}}`         | Unary RPC result, or clean stream completion (`value` is `null` or omitted for void/streams).                                                                   |
| `Exit` (Failure) | `{"_tag":"Exit","requestId":"1","exit":{"_tag":"Failure","cause":[<cause>, ...]}}` | RPC or stream error. Each cause item has `_tag`: `"Fail"` (`error`), `"Die"` (`defect`), or `"Interrupt"` (`fiberId`).                                          |
| `Pong`           | `{"_tag":"Pong"}`                                                                  | Reply to client `Ping`, **and** sent unsolicited every 20 seconds by `withSocketHeartbeat`.                                                                     |
| `Defect`         | `{"_tag":"Defect","defect":<json>}`                                                | Protocol-level fatal defect (e.g. unparseable client envelope). Per-handler defects arrive as `Exit` `Die` because the server sets `disableFatalDefects: true`. |

### Keepalive & Reconnect Semantics

- **Server heartbeat**: Server sends unsolicited `{"_tag":"Pong"}` every 20s and ignores client frames that aren't needed.
- **Client liveness** (matching `packages/client-runtime/src/rpc/session.ts`):
  - Send `{"_tag":"Ping"}` every **5 seconds**.
  - Any decoded inbound frame (including `Pong` and `\u001e` partial frames) resets the liveness deadline.
  - If **15 seconds** pass without any inbound frame, close the socket and reconnect.
- **Reconnect**: Exponential backoff with jitter (e.g. `0.5s` → `15s` cap). On reconnect, re-mint `wsTicket` and resubscribe streams using `afterSequence` (for `orchestration.subscribeShell` and `orchestration.subscribeThread`).

### Timestamps & IDs

- Both `IsoDateTime` and `Schema.DateTimeUtc` serialize on the wire as ISO-8601 UTC strings (e.g. `"2026-11-24T19:56:01.086Z"`). Clients should accept both fractional-second and whole-second ISO-8601 UTC strings.
- Entity IDs (`ThreadId`, `ProjectId`, `CommandId`, `MessageId`, `RunId`, etc.) are non-empty trimmed strings (typically UUIDs).

---

## 4. Core RPC Methods & Event Streams

### 4.1 Environment, Server Config, Providers, Models & Options

#### `server.getConfig` (unary)

- **Payload**: `{}`
- **Success (`ServerConfig`)**:
  - `environment`: `ExecutionEnvironmentDescriptor` (`environmentId`, `label`, `platform`, `serverVersion`, `orchestrationProtocolVersion`, `capabilities`)
  - `auth`: `ServerAuthDescriptor` (`policy`, `bootstrapMethods`, `sessionMethods`, `sessionCookieName`)
  - `cwd`: string (server's working directory)
  - `hostname`: optional string (machine hostname for sidebar host display)
  - `providers`: `[ServerProvider]`
  - `serverTime`: optional ISO-8601 string (for clock-skew calculation)
  - `scratchWorkspaceRoot`, `newProjectsRoot`: optional strings
  - Feature/stream flags: `shellResumeCompletionMarker`, `threadResumeCompletionMarker`, `shellThreadFamilies`, `shellOlderSettled`

#### `subscribeServerConfig` (stream)

- **Payload**: `{}` (optional opt-ins: `workspaceSnapshotsOnDemand`, `providerStatusDeltas`, `environmentThemes`, `usageLimitSources`)
- **Stream items (`ServerConfigStreamEvent`, all have `version: 1`)**:
  - `type: "snapshot"` → `{ version: 1, type: "snapshot", config: ServerConfig }`
    - **Quirk**: Shortly after connect, late discovery of editors/directEndpoints can emit a second full `snapshot` event. Always treat `snapshot` as idempotent replacement.
  - `type: "providerStatuses"` → `{ version: 1, type: "providerStatuses", payload: { providers: [ServerProvider] } }`
  - `type: "providerStatusDeltas"` → only sent if opted in (`providerStatusDeltas: true`); omits unchanged `models`/`slashCommands`/`skills` arrays per provider.
  - `type: "settingsUpdated"` / `"keybindingsUpdated"` / `"environmentThemesUpdated"` / `"usageLimitSourcesUpdated"` → ignore unknown event types forward-compatibly.

#### `server.refreshProviders` (unary)

- **Payload**: `{ instanceId?, cwd?, fresh?, refreshModels?, modelCatalogOnly? }`
- **Success**: `{ providers: [ServerProvider] }`

#### `server.probe` (unary)

- **Payload**: `{}`
- **Success**: `{ serverTime?: IsoDateTime }`

#### Provider, Model & Model Options Shapes

- **`ServerProvider`**:
  - `instanceId`: stable routing key (**ALWAYS route and select by `instanceId`, never by `driver`**; multiple instances can share a `driver`).
  - `driver`: driver kind (`"codex"`, `"claudeAgent"`, `"cursor"`, `"grok"`, `"opencode"`, `"antigravity"`, `"kiro"`, `"pi"`, `"muse"`, `"fx"`, `"acpRegistry"`).
  - `displayName?`, `accentColor?`, `iconUrl?`, `badgeLabel?`
  - `enabled: Bool`, `installed: Bool`, `version: String?`, `status: "ready" | "warning" | "error" | "disabled"`
  - `auth: { status: "authenticated" | "unauthenticated" | "unknown", type?, label?, email? }`
  - `supportedRuntimeModes?: [RuntimeMode]`, `showInteractionModeToggle?: Bool`
  - `models: [ServerProviderModel]`, `subProviders?: [{ name, unavailableReason? }]`
- **`ServerProviderModel`**:
  - `slug`: wire model identifier sent in `ModelSelection.model`
  - `name`, `shortName?`, `subProvider?`, `aliases?`, `badge?` (`"new"`), `isCustom: Bool`, `isDefault?: Bool`, `isLegacy?: Bool`
  - `capabilities: { optionDescriptors?: [ProviderOptionDescriptor] } | null`
- **`ProviderOptionDescriptor`** (controls like reasoning/thinking level, fast mode, etc.):
  - `type: "select"`: `{ id, label, description?, type: "select", options: [{ id, label, description?, isDefault? }], currentValue?, role?: "reasoning" }`
  - `type: "boolean"`: `{ id, label, description?, type: "boolean", currentValue? }`
- **`ModelSelection`**:
  - Wire encode: `{ "instanceId": "codex", "model": "gpt-6-astra", "options": [{ "id": "reasoningEffort", "value": "high" }] }` (`options` omitted when empty; `value` is `string | boolean`).
  - Wire decode: accept `instanceId` (fallback to legacy `provider` key) and `options` as either canonical array `[{ id, value }]` or legacy object `{ "reasoningEffort": "high" }`.

---

### 4.2 Listing Projects & Threads (Sidebar)

#### `orchestration.subscribeShell` (stream)

- **Payload**:
  ```json
  {
    "afterSequence": 42,
    "requestCompletionMarker": true
  }
  ```
  _(Omit `afterSequence` on initial connect; pass the latest known sequence on reconnect. Optional flags `omitIdleSubagents` / `omitOlderSettled` should only be sent if advertised in capabilities.)_
- **Stream items (`OrchestrationV2ShellStreamItem`)**:
  - `kind: "snapshot"` → `{ kind: "snapshot", snapshot: { schemaVersion, snapshotSequence, projects, threads, archivedThreads, olderSettled? }, resolvedRepositoryIdentityRoots?: [string] }`
  - `kind: "synchronized"` → emitted after initial snapshot/replay completes when `requestCompletionMarker: true`
  - `kind: "snapshot-required"` → only when `httpSnapshotFallback: true` was set and gap cannot be replayed
  - `kind: "project.updated"` → `{ kind: "project.updated", sequence, project: OrchestrationProjectShell }`
  - `kind: "project.removed"` → `{ kind: "project.removed", sequence, projectId }`
  - `kind: "thread.updated"` → `{ kind: "thread.updated", sequence, location: "active" | "archive", thread: OrchestrationV2ThreadShell }`
  - `kind: "thread.removed"` → `{ kind: "thread.removed", sequence, location: "active" | "archive", threadId }`

#### Sidebar Field Mapping

| Sidebar UI Field           | Wire Source                                                                                                                                                                                                                                                        |
| -------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Project                    | `project = projects[thread.projectId]` (`project.title`, `project.workspaceRoot`, `project.repositoryIdentity?.displayName`, `project.projectIcon`)                                                                                                                |
| Title                      | `thread.title`                                                                                                                                                                                                                                                     |
| Relative updated time      | `thread.updatedAt` (ISO-8601 UTC; compare against host clock using `ServerConfig.serverTime` if skew matters)                                                                                                                                                      |
| Branch / worktree          | `thread.branch` (`String?`), `thread.worktreePath` (`String?`)                                                                                                                                                                                                     |
| Host / environment         | `ServerConfig.environment.label` and `ServerConfig.hostname`                                                                                                                                                                                                       |
| Provider / model           | `thread.providerInstanceId` + `thread.modelSelection` (`instanceId`, `model`, `options`), resolved against `ServerConfig.providers` for `displayName` & model `shortName`/`name`                                                                                   |
| Needs approval             | `thread.pendingRuntimeRequest != nil && kind != "user_input" && kind != "auth_refresh"`                                                                                                                                                                            |
| Needs user input           | `thread.pendingRuntimeRequest?.kind == "user_input"`                                                                                                                                                                                                               |
| Running / working          | Not blocked on approval/user-input AND `(thread.activityRunStatus ?? thread.status)` is one of `preparing`, `queued`, `starting`, `running`, `waiting` (or `pendingBackgroundTasks` contains awaited/subagent tasks)                                               |
| Unread                     | `thread.latestRunCompletedAt != nil` AND `thread.status != "interrupted"` AND `thread.status != "cancelled"` AND `thread.lastVisitedAt != nil` AND `latestRunCompletedAt > lastVisitedAt` (matches `apps/web/src/components/Sidebar.logic.ts:hasUnseenCompletion`) |
| Pinned / Settled / Snoozed | `thread.pinnedAt != nil`, `thread.settledOverride == "settled"` (or `settledAt != nil && settledOverride != "active"`), `thread.snoozedUntil > now`                                                                                                                |

---

### 4.3 Opening a Thread & Streaming Live Turn Events

#### `orchestration.subscribeThread` (stream)

- **Payload**:
  ```json
  {
    "threadId": "<threadId>",
    "afterSequence": 100,
    "requestCompletionMarker": true
  }
  ```
  - **Wire optimization opt-ins** (leave omitted/false to receive plain, uncompressed projections):
    - `acceptBoundedSnapshot`: returns a windowed tail + `historyCursor` (`hasMoreHistory: true`)
    - `acceptDeferredWork`: collapses tool blocks into expandable `deferredWork` cursors
    - `acceptCompactTurnItems`: omits local visible items from `projection.turnItems` (`turnItemsOmitLocalVisible: true`)
    - `acceptDedupedBodies`: blanks repeated `text`/`files`/`prompt`/`result` with `*Omitted: true` markers
    - `acceptCompactIds`: replaces repeated IDs using a top-level `idTable`
- **Stream items (`OrchestrationV2ThreadStreamItem`)**:
  - `kind: "snapshot"` → `{ kind: "snapshot", snapshotSequence, projection: OrchestrationV2ThreadProjection }`
  - `kind: "synchronized"` → catch-up complete
  - `kind: "event"` → `{ kind: "event", sequence, event: OrchestrationV2DomainEvent }`

#### `OrchestrationV2ThreadProjection` Contents

- `thread`: `OrchestrationV2AppThread`
- `runs`: `[OrchestrationV2Run]` (`id`, `ordinal`, `status`, `modelSelection`, `userMessageId`, `activeAttemptId`, `requestedAt`, `startedAt`, `completedAt`, `output?`)
- `attempts`: `[OrchestrationV2RunAttempt]` (`id`, `runId`, `rootNodeId`, `status`)
- `runtimeRequests`: `[OrchestrationV2RuntimeRequest]` (`id`, `nodeId`, `kind`, `status`: `pending|resolved|expired|cancelled`, `responseCapability`, `decision?`, `feedback?`, `answers?`)
- `messages`: `[OrchestrationV2ConversationMessage]`
- `plans`: `[OrchestrationV2PlanArtifact]` (`proposed_plan` | `todo_list`)
- `turnItems`: `[OrchestrationV2TurnItem]`
- `visibleTurnItems`: `[OrchestrationV2ProjectedTurnItem]` — ordered timeline rows `{ position, visibility: "local"|"inherited"|"synthetic", sourceThreadId, sourceItemId, item }`
- `subagents`, `providerThreads`, `providerSessions`, `providerTurns`, `nodes`, `checkpointScopes`, `checkpoints`, `contextHandoffs`, `contextTransfers`

#### Key `OrchestrationV2TurnItem` Types

Every item shares base fields (`id`, `threadId`, `runId`, `nodeId`, `ordinal`, `status`, `title`, `startedAt`, `completedAt`, `updatedAt`) plus a `type` discriminator:

- `user_message`: `messageId`, `text`, `inputIntent`, `attachments`, `createdBy`, `creationSource`
- `assistant_message`: `messageId`, `text`, `streaming: Bool`, `phase?` (`commentary|partial_answer|final_answer`), `delivery?` (`async`), `attachments?`
  - **Note**: Streaming assistant text arrives as repeated `turn-item.updated` events containing the **full accumulated `text`**, NOT incremental token diffs!
- `reasoning`: `text`, `streaming: Bool`
- `proposed_plan`: `planId`, `markdown`, `streaming: Bool`
- `todo_list`: `planId`, `steps: [{ id, text, status }]`, `explanation?`
- `command_execution`: `input`, `output?`, `outputOmitted?`, `outputIndicatesFailure?`, `exitCode?`, `monitor?`
- `file_change`: `fileName`, `additions?`, `deletions?`, `diffStr?`, `oldStr?`, `newStr?`, `changes?`
- `file_search`: `pattern?`, `results?`
- `web_search`: `patterns?`, `results?`
- `dynamic_tool`: `toolName`, `viewedImagePath?`, `input`, `output?`, `outputOmitted?`
- `approval_request`: `requestId`, `requestKind` (`command|file-read|file-change|mcp-elicitation|permission`), `prompt?`, `reason?`, `fullAccessOverride?`, `appName?`, `options?`
- `user_input_request`: `requestId`, `questions: [{ id, header, question, options, multiSelect?, allowCustomAnswer?, required? }]`, `responseMode?`
- `subagent`, `checkpoint`, `notification`, `run_interrupt_request` (with optional `unresponsiveAt`), `run_interrupt_result`, `system_notice`, `error` (`failure: { class, message, code, retryable, resetAt? }`), `compaction`, `handoff`, `fork`, `thread_created`, `secret_request`, `link_request`, `feedback_request`.

#### Key `OrchestrationV2DomainEvent` Types & Projection Reducer Rules

- `thread.created`, `thread.metadata-updated`, `thread.runtime-mode-updated`, `thread.interaction-mode-updated`, `thread.model-selection-updated`, `thread.provider-switched`, `thread.archived`, `thread.unarchived`, `thread.deleted`, `thread.settled`, `thread.unsettled`, `thread.snoozed`, `thread.unsnoozed`, `thread.pinned`, `thread.unpinned` → replace `projection.thread` and advance `projection.updatedAt`.
- `thread.visited`, `thread.marked-unread`, `thread.tags-updated` → replace `projection.thread` **without** advancing `projection.updatedAt`.
- `thread.visit-recorded` → patch `projection.thread.lastVisitedAt` **without** advancing `projection.updatedAt`.
- `run.created`, `run.updated` → upsert into `projection.runs`. **Preserve existing `run.output`** if the incoming payload omits `output`. Re-filter `visibleTurnItems` (hiding rolled-back runs and queued/unstarted cancelled `queued_turn` user messages; restoring queued user messages when a run transitions out of `"queued"`).
- `run.output-submitted` → attach `payload.output` onto the matching run.
- `run-attempt.created`, `run-attempt.updated` → upsert into `projection.attempts` and re-filter superseded interrupt results.
- `provider-thread.updated` → upsert into `projection.providerThreads`; if `appThreadId == thread.id` and it is not a queued placeholder (`status == "not_loaded" && firstRunOrdinal == nil && nativeThreadRef == nil && providerSessionId == nil`), update `projection.thread.activeProviderThreadId`.
- `runtime-request.updated`, `message.updated`, `plan.updated`, `subagent.updated` → upsert by `id`.
- `turn-item.updated` → upsert into `projection.turnItems`; if visible, replace in-place (preserving `position` if `ordinal` unchanged) or insert sorted by `(ordinal asc, id asc)` among `"local"` rows and renumber `position`.
- **Unknown event or turn-item `type`**: MUST be ignored gracefully while still advancing `lastSequence` so reconnect cursors stay accurate.

---

### 4.4 Dispatching Commands (`orchestration.dispatchCommand`)

All thread mutations go through a single RPC:

- **Method**: `orchestration.dispatchCommand` (unary)
- **Payload**: `OrchestrationV2Command` (tagged by `type`, always carrying a client-generated UUID `commandId`)
- **Success**: `{ "sequence": 43 }`
- **Errors**: `OrchestrationV2DispatchCommandError` (`commandId`, `commandType`, `message`, `detail?`) or `EnvironmentAuthorizationError`.

#### Create a Thread (`thread.create`)

```json
{
  "type": "thread.create",
  "commandId": "<uuid>",
  "createdBy": "user",
  "creationSource": "web",
  "threadId": "<uuid>",
  "projectId": "<projectId>",
  "title": "New thread",
  "modelSelection": { "instanceId": "codex", "model": "gpt-6-astra" },
  "runtimeMode": "full-access",
  "interactionMode": "default",
  "branch": null,
  "worktreePath": null
}
```

- `branch` and `worktreePath` are non-optional nullable fields (`Schema.NullOr`) — always include them explicitly (`null` when unused).
- `creationSource` accepts only `"web" | "mobile" | "mcp" | "provider" | "server"` (no `"macos"` literal); `SwftKit` uses `"web"`.

#### Atomic Create + Worktree + Initial Message (`orchestration.launchThread`, unary)

For launching a thread with a managed worktree and/or initial message in one server transaction:

```json
{
  "commandId": "<uuid>",
  "creationSource": "web",
  "projectId": "<projectId>",
  "title": "Fix bug",
  "generateTitle": true,
  "modelSelection": {
    "instanceId": "claudeAgent",
    "model": "claude-opus-5-5",
    "options": [{ "id": "effort", "value": "high" }]
  },
  "runtimeMode": "full-access",
  "interactionMode": "default",
  "workspaceStrategy": { "type": "root" },
  "initialMessage": { "messageId": "<uuid>", "text": "Inspect the crash", "attachments": [] }
}
```

`workspaceStrategy` variants: `{ "type": "root", "branch"?: "..." }`, `{ "type": "existing_worktree", "worktreePath": "...", "branch"?: "..." }`, `{ "type": "worktree", "baseRef": "origin/main", "branch"?: "...", "startFromOrigin"?: true }`.
Returns `{ threadId, projection, resumed, sequence? }`.

#### Register a Project (`projects.mutate`, unary)

```json
{
  "type": "project.create",
  "commandId": "<uuid>",
  "projectId": "<uuid>",
  "title": "My Repo",
  "workspaceRoot": "/Users/me/code/my-repo",
  "createWorkspaceRootIfMissing": false
}
```

Returns `Project`.

#### Send a Message (`message.dispatch`)

1. If changing `runtimeMode` (`"approval-required" | "auto-accept-edits" | "auto" | "full-access"`) or `interactionMode` (`"default" | "plan"`), dispatch `thread.runtime-mode.set` / `thread.interaction-mode.set` **first** — `message.dispatch` does **not** carry mode fields!
2. Dispatch `message.dispatch`:

```json
{
  "type": "message.dispatch",
  "commandId": "<uuid>",
  "createdBy": "user",
  "creationSource": "web",
  "threadId": "<threadId>",
  "messageId": "<uuid>",
  "text": "Explain this function",
  "attachments": [],
  "modelSelection": {
    "instanceId": "codex",
    "model": "gpt-6-astra",
    "options": [{ "id": "reasoningEffort", "value": "high" }]
  },
  "deliveryIntent": "auto",
  "dispatchMode": { "type": "start_immediately" }
}
```

`dispatchMode` variants:

- `{ "type": "start_immediately" }` — when thread is idle
- `{ "type": "queue_after_active" }` — queue behind an active run
- `{ "type": "steer_active", "targetRunId": "<runId>" }` — mid-turn steer
- `{ "type": "restart_active", "targetRunId": "<runId>" }` — interrupt & restart active run

#### Interrupt / Stop

- **Preferred** (when `environment.capabilities.threadStop == true`):
  ```json
  {
    "type": "thread.stop",
    "commandId": "<uuid>",
    "threadId": "<threadId>",
    "reason": "User stopped"
  }
  ```
- **Legacy fallback**:
  ```json
  {
    "type": "run.interrupt",
    "commandId": "<uuid>",
    "threadId": "<threadId>",
    "runId": "<runId>",
    "holdQueue": true
  }
  ```
- **Force stop** (when a `run_interrupt_request` item gets `unresponsiveAt` set and `capabilities.threadForceStop == true`):
  RPC `orchestration.forceStopThread` with `{ "threadId": "<threadId>", "runId"?: "<runId>" }`.

#### Answer Approval (`runtime-request.respond`)

```json
{
  "type": "runtime-request.respond",
  "commandId": "<uuid>",
  "threadId": "<threadId>",
  "requestId": "<requestId>",
  "decision": "accept",
  "feedback": "Optional user note"
}
```

`decision` values: `"accept" | "acceptForSession" | "acceptAlways" | "decline" | "cancel"`.

#### Answer User Input Question (`runtime-request.respond`)

```json
{
  "type": "runtime-request.respond",
  "commandId": "<uuid>",
  "threadId": "<threadId>",
  "requestId": "<requestId>",
  "answers": { "<questionId>": "<selectedValueOrArray>" }
}
```

#### Read / Unread State

- Mark visited: `{ "type": "thread.visit", "commandId": "<uuid>", "threadId": "<threadId>", "visitedAt": "<iso8601>", "opened": true }`
- Mark unread: `{ "type": "thread.mark-unread", "commandId": "<uuid>", "threadId": "<threadId>" }`

---

## 5. Launching the Local Server (`ServerProcess`)

Matches `apps/desktop/src/backend/DesktopBackendManager.ts` and `apps/server/src/bootstrap.ts`:

1. Spawn `node <entrypoint> --bootstrap-fd 0` where `<entrypoint>` is `apps/server/dist/bin.mjs` (bundled release) or `apps/server/src/bin.ts` (development checkout on Node 22.16+/24+).
2. Strip ambient `T3CODE_*` and `VITE_DEV_SERVER_URL` variables from the child environment so a running developer T3 Code instance cannot hijack the child's home dir or port.
3. Write a single JSON line (`DesktopBackendBootstrap`) to child stdin and close stdin immediately (the server's bootstrap reader times out after 1000ms):
   ```json
   {
     "mode": "desktop",
     "noBrowser": true,
     "port": 51234,
     "t3Home": "/Users/<user>/Library/Application Support/Swft",
     "host": "127.0.0.1",
     "desktopBootstrapToken": "<64-hex-random>",
     "tailscaleServeEnabled": false,
     "tailscaleServePort": 443
   }
   ```
4. The server writes its SQLite database (`statev2.sqlite`), logs, and secrets under `<t3Home>/userdata/`. Never point `t3Home` at `~/.t3`.
5. Poll `GET http://127.0.0.1:<port>/.well-known/t3/environment` until `200 OK`.
6. Because `mode == "desktop"` and `desktopBootstrapToken` is set, the server automatically runs `stopOnLauncherLoss` (polls `process.ppid` every 2s and shuts down cleanly if the parent dies). On normal shutdown, send `SIGTERM` (then `SIGKILL` after grace period) **only to the exact spawned PID**.

---

## 6. Server Behaviors the UI Must Know About

1. **Enrichment snapshots have empty `threads: []`**: `orchestration.subscribeShell` occasionally emits a `snapshot` item carrying `resolvedRepositoryIdentityRoots` when git remote metadata finishes resolving asynchronously. That snapshot intentionally has `threads: []` and `archivedThreads: []` — merge only `projects` and **never** overwrite `threads`.
2. **Every stream `Chunk` requires an `Ack`**: Omitting `Ack` silently freezes the subscription after chunk 1. (`ServerConnection` handles this automatically.)
3. **Command acknowledgement ≠ provider completion**: `orchestration.dispatchCommand` returns `{ sequence }` as soon as the command is durably committed to SQLite. Actual agent work executes asynchronously and arrives via `subscribeThread` and `subscribeShell`.
4. **Streaming text is replacement, not diffs**: `assistant_message`, `reasoning`, and `proposed_plan` updates deliver the full accumulated text in each `turn-item.updated` event.
5. **Filter non-listed threads from the sidebar**: Exclude threads where `lineage.relationshipToParent == "subagent"`, `lineage.sideChat == true`, `lineage.workflowStep == true`, `deletedAt != nil`, or `archivedAt != nil`.
6. **Provider routing uses `instanceId`, not `driver`**: Always pass `provider.instanceId` in `ModelSelection`.
7. **`runtimeMode` and `interactionMode` live on the thread**: Changing them before sending requires dispatching `thread.runtime-mode.set` / `thread.interaction-mode.set` prior to `message.dispatch` (and only affects turns started afterward; active turns keep their `startedModes`).
8. **Idempotent retries via `commandId`**: Re-sending a command with the same UUID `commandId` after a disconnect replays the server receipt without duplicating runs or messages.
9. **Throttle `thread.visit` while viewing active runs**: During streaming, `updatedAt` changes multiple times per second; the web client throttles `thread.visit` dispatches to at most once every 10 seconds while a run is streaming (and immediately on thread open or run completion).
10. **Forward compatibility**: Newer server versions may introduce new `TurnItem.type`, `DomainEvent.type`, `ServerConfigStreamEvent.type`, or capability keys; unknown variants must be ignored without breaking streams or decoding.
