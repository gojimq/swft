# Swft Feature Parity (macOS ↔ iOS)

Living capability matrix tracking parity between the native Swft clients (`apps/macos` and `apps/ios`) built on shared `SwftKit`.

> **Branch snapshot:** `apps/macos` (`Swft`, `SwftDesign`, `SwftKit`) ships on `swft/main`, including cross-platform `SwftKit` foundations (`.iOS("26.0")`, `SwftStoragePaths`, Keychain isolation, remote suspend/resume/network-path hooks, and `UsageSummary` RPCs). `apps/ios` (`SwftIOS` — iPhone, iPhone Duo, iPad) currently lives on branch `t3/native-ios-companion` (in progress). Active macOS right-sidebar Dia tab work lives on `t3/redesign-dia-sidebar-tabs` and `t3/subagent-right-sidebar-tabs`.

## Status Legend

| Badge | Meaning |
| --- | --- |
| `✅` | **Shipped** on `swft/main` |
| `🚧` | **Branch / In Progress** — implemented on an active feature branch (e.g. `t3/native-ios-companion` for iOS) and not yet merged to `swft/main` |
| `❌` | **Missing** — actionable parity gap to build |
| `➖` | **Platform-Specific** — intentionally macOS-only or iOS-only (rationale noted) |

---

## Parity Matrix

### 1. Core Chat & Transcript

| Capability | macOS | iOS | Notes / Differences |
| --- | :---: | :---: | --- |
| Streaming markdown & copyable code blocks | ✅ | 🚧 | macOS renders headings, paragraphs, nested lists, inline code/bold, and fenced code blocks; iOS additionally renders GFM pipe tables, blockquotes, task checkboxes, and thematic breaks. |
| Work folding (thoughts, tools, interim commentary) | ✅ | 🚧 | Both collapse turns into a quiet `"Worked for Xs"` / live step row backed by height-reveal `SwftDisclosure` hairline trees. |
| Quiet & multi-notice folding | ✅ | 🚧 | Single non-error notice renders as one quiet line; 2+ notices fold into a collapsed row; errors remain prominent banners. |
| Tool approvals | ✅ | 🚧 | macOS renders inline `ApprovalCard` (Approve / Deny, Esc). iOS docks `ApprovalDockView` above the composer with full server-provided options (including Allow for Session). |
| Agent questions (`userInputRequest`) | ❌ | 🚧 | iOS renders interactive single/multi-select + custom-answer cards via `respondToUserInput`. macOS currently renders them as read-only quiet notices. |
| Stop, force-stop & follow-up queuing | ✅ | 🚧 | Both queue prompts while a run is active; macOS auto-escalates unresponsive stops to `forceStop`, while iOS exposes Stop Turn / Force Stop in the stop control menu. |
| Checkpoints & thread rollbacks | ❌ | ❌ | Neither client has rollback/revert UI yet (macOS reads checkpoint items only for diff-stat totals). |
| In-thread J-curve send flight | ✅ | 🚧 | Both animate user messages from composer to transcript with stream-room retention, 340ms reveal hold, and Reduce Motion fade (120Hz `CADisplayLink` scroll-lock on iOS). |
| New-thread Home launch handoff | ✅ | 🚧 | macOS docks the Home composer down while simultaneously fading in the first bubble at exact transcript coordinates. iOS crossfades into the thread and fades the first bubble cleanly in place. |
| Scroll stickiness & scroll-to-bottom button | ✅ | 🚧 | Both track bottom stickiness, release on user scroll or work-fold toggle, and float a circular jump-to-latest button. |
| Thread images & lightbox | ✅ | 🚧 | Both resolve attachments, markdown images, and viewed-image tool outputs per owning environment with image caching and full-size lightbox preview. |

### 2. Composer & Input

| Capability | macOS | iOS | Notes / Differences |
| --- | :---: | :---: | --- |
| Liquid Glass pill composer | ✅ | 🚧 | Multi-line pill composer shared by Home and Thread views on both platforms. |
| Model picker & thinking/reasoning slider | ✅ | 🚧 | Both ship the frosted Liquid Glass floating picker with search, provider rail, multi-account switcher, sub-provider sections, and discrete `ThinkingSlider`. |
| Runtime permissions & interaction mode controls | ✅ | 🚧 | iOS exposes `Permissions` (`RuntimeMode`) and `Default \| Plan` (`ProviderInteractionMode`) pills directly in Home and Thread chrome. macOS puts default permissions in Settings and toggles `Plan`/`Default` via slash commands (Home currently shows a `Chat \| Task` toggle). |
| Project picker & no-project (scratch) threads | ✅ | 🚧 | Both support selecting a project or starting with `No project` via `ensureScratchProject()`. macOS also supports adding local folders (`NSOpenPanel`) or remote paths; iOS is selection-only. |
| Delete recent projects & missing-folder recovery | ✅ | ❌ | macOS detects missing local folders on disk, badges them, and supports inline removal with thread-impact confirmation. iOS has no project deletion UI (local disk check itself is `➖` macOS-only). |
| Inline attachments (staging, upload, transcoding) | ✅ | 🚧 | Both stage/upload with size limits, image transcoding (HEIC → PNG/JPEG), and cohesive send-flight. macOS supports file picker, drag-and-drop, and clipboard paste; iOS supports Photos Library and Files importer (no drag/paste yet). |
| Slash commands & skills menu (`/`) | ✅ | ❌ | macOS has full `/` trigger detection, built-ins (`/model`, `/clear` fresh-session banner, `/plan`, `/default`, `/side`, `/btw`), provider commands, and workspace skills (`$skill`) with keyboard navigation. |
| `/side` & `/btw` side-chat shortcuts | ✅ | ❌ | macOS opens a Side chat tab in the Right Sidebar and seeds the prompt; depends on slash commands + Side chat surface on iOS. |

### 3. Navigation, Sidebar & Shell

| Capability | macOS | iOS | Notes / Differences |
| --- | :---: | :---: | --- |
| Thread inbox layout | ✅ | 🚧 | Both show project chip, relative time, unread/status glyph, branch/project/host subtitle, and provider icon; iOS also groups rows into Needs Action, collapsible Working, and Threads. |
| Thread search & server/project filters | ❌ | 🚧 | iOS has live search (title/project/branch/server/snippet), Server and Project filter pills, and pull-to-refresh. macOS has `All / Active / Needs attention` filtering, but its sidebar search button is unwired. |
| Settled threads shelf & quick thread actions | ✅ | 🚧 | Both pin an upward-opening `Settled` shelf with the active settled row pinned when collapsed. macOS has hover/context Settle & Unsettle; iOS adds swipe/context **Mark Unread** and **Archive**. |
| Adaptive app shell & chrome | ➖ | 🚧 / ➖ | macOS: 3-column hidden-titlebar split (left sidebar, canvas, resizable right panel). iOS: root `TabView` (`Chats`, `Usage`, `Settings`) adapting between iPhone Duo vertical side bar + `NavigationSplitView`, iPad split, and compact iPhone bottom tab bar + push stack. |
| Scheduled tasks screen | ❌ | ❌ | macOS sidebar has a `Scheduled` nav row that currently routes back to Home; unbuilt on both platforms. |
| Keyboard shortcuts | ✅ | ❌ | macOS wires `⌘N`, `⌘,`, `⌃⌘S`, `⌥⌘B`, Esc, arrow/Tab/Enter picker nav, and single-key right-panel shortcuts (`B/F/L/M/S`). iOS has no hardware keyboard shortcuts yet. |

### 4. Subagents & Right Sidebar Surfaces

| Capability | macOS | iOS | Notes / Differences |
| --- | :---: | :---: | --- |
| Inline subagent indicators & grouped parallel cards | ✅ | ❌ | macOS renders dedicated single cards and collapsible parallel group cards with live elapsed timers, provider/model badges, and inline expansion (also inside Side chat). iOS currently folds subagents as generic tool rows inside `WorkFoldRow`. |
| Subagent detail / child-thread inspection | ✅ / 🚧 | ❌ | macOS opens child/remote subagent threads in the main canvas with a `TopBar` back-to-parent breadcrumb; opening subagents inside Right Sidebar Dia tabs is in progress (`t3/subagent-right-sidebar-tabs`). |
| Right Sidebar multi-tab shell | ✅ / 🚧 | ❌ | macOS supports per-thread tabs, drag resize, maximize, and single-key launcher; Dia-style tab redesign is in progress (`t3/redesign-dia-sidebar-tabs`). On iOS/iPad, inspector/sheet presentation is preferred over a permanent 3rd column on compact screens. |
| **Files** surface (workspace tree, search & viewer) | ✅ | ❌ | High-value parity target for iPhone Duo and iPad remote review. |
| **Side chat** surface (forked aside thread) | ✅ | ❌ | Strong fit for a modal sheet or trailing inspector on iOS/iPad. |
| **Linked items** surface (PRs, issues, thread family) | ✅ | ❌ | Strong fit for a thread inspector sheet on iOS/iPad. |
| **Browser** surface (embedded `WKWebView` preview) | ✅ | ➖ | Host `localhost` dev servers live on the Mac; desktop-first surface unless proxied. |
| **Device** surface (Simulator / Emulator streaming) | ✅ | ➖ | Streaming an iOS Simulator / Android Emulator is a desktop development workflow. |

### 5. Usage & Providers

| Capability | macOS | iOS | Notes / Differences |
| --- | :---: | :---: | --- |
| Sidebar tonal fuel pills & hover breakdown | ✅ | ➖ | macOS pins up to 3 configurable provider quota pills above the sidebar bottom with hover breakdown popover and last-good cache. iOS intentionally uses a dedicated `Usage` tab instead. |
| Full Usage dashboard (Limits / Cost / Tokens charts) | ❌ | 🚧 | iOS ships a full `Usage` tab: deduplicated multi-server Limits cards with pace ticks, plus Cost & Tokens views (`24h`/`7d`/`30d`/`90d`, KPI cards, interactive Swift Charts stacked bars, By Provider & Top Models breakdowns). `SwftKit` already exposes `UsageSummaryModels` + `getUsageSummary` on `swft/main`, making macOS UI a direct parity win. |
| Provider setup, auth & multi-account settings | ✅ | ❌ | macOS manages install/auth flows, enable toggles, multi-account add/remove, accent swatches, schema config, env vars/secrets, custom models, and idle compaction. iOS directs auth changes to the host server. |

### 6. Remote Access, Multi-Environment & Cloudflare Tunnels

| Capability | macOS | iOS | Notes / Differences |
| --- | :---: | :---: | --- |
| Multi-server registry & Keychain isolation | ✅ | 🚧 | Shared `SwftKit` `EnvironmentRegistry` + `KeychainCredentialStore` (per-`SWFT_HOME` isolation on macOS), HTTPS-downgrade protection, identity pinning, rename, re-pair, reconnect, remove. |
| QR & pairing-link onboarding | ✅ | 🚧 | macOS mints one-time invites with `QRCodeView` for sharing and accepts pasted links/tokens for adding servers. iOS adds camera `QRScannerView` (with torch), clipboard paste, and `swft://` / `t3code://` URL handling. |
| Cloudflare Tunnel (`Share this Mac`) | ✅ | ➖ | macOS manages `Off / Quick / Named / External` `cloudflared` tunnels (auto-starts named tunnel e.g. `swft` on launch, tracks ephemeral local port, upgrades QR invites to HTTPS) plus Tailscale/LAN detection. iOS is a remote client only. |
| Dedicated server tunnels (`swft-mini` / headless host) | ✅ | 🚧 | Both connect over permanent named Cloudflare Tunnel HTTPS, Tailscale MagicDNS, or LAN. |
| Foreground resume & network-path reconnect | ❌ | 🚧 | iOS wires `scenePhase` (`suspendAllRemotes` / `resumeAllRemotes`) and `NWPathMonitor` (`handleNetworkPathChanged`). `SwftKit` already exposes both methods on `swft/main`, but macOS has not yet wired wake/network-path listeners. |

### 7. Updates, Settings & Polish

| Capability | macOS | iOS | Notes / Differences |
| --- | :---: | :---: | --- |
| GitHub Releases multi-environment updater | ✅ | ➖ / ❌ | macOS updates remote servers in parallel and stages/verifies/replaces local `Swft.app`. Local iOS app updates are `➖` (App Store / TestFlight / Xcode), while triggering remote server self-updates from iOS is `❌`. |
| Appearance & typography | ✅ | 🚧 | Both support System / Light / Dark themes. macOS bundles variable `GoogleSansFlex.ttf`; iOS uses system SF with Dynamic Type plus a `Compact / Default / Large` message text-size control. |
| General & server behavior settings | ✅ | ❌ | macOS edits default model/thinking, permissions, local/worktree mode, streaming mode, keep-awake, continue-after-restart, and auto-settle-on-merge. |
| Notifications & attention alerts | ✅ | ❌ | macOS ships system notifications, sound alerts, event filters, and in-app banners. iOS relies on the Chats tab badge while open (no background push/local alerts). |
| Reduced Motion & static ambient glow | ✅ | 🚧 | Both honor `accessibilityReduceMotion` across send-flight, disclosures, and transitions with zero continuously repainting animations. |

---

## Current Parity Gaps (Prioritized Backlog)

### Missing on iOS (exists on macOS)

| Priority | Feature | Notes |
| --- | --- | --- |
| P0 | Slash commands & skills menu (`/`) | Trigger detection, built-ins (`/model`, `/clear`, `/plan`, `/default`), provider commands, workspace skills (`$skill`), and fresh-session arming. |
| P0 | Inline subagent indicators, parallel groups & drill-in | Replace generic `WorkFoldRow` tool fallback with dedicated subagent cards, consecutive parallel grouping, elapsed timers, and child-thread navigation. |
| P1 | Inspector surfaces: **Files**, **Side chat**, **Linked items** | Present via sheet or trailing inspector on iPhone Duo / iPad (and wire `/side` & `/btw` to Side chat). |
| P1 | Project management (add remote path & delete projects) | Register remote project paths and delete stale/recent projects with thread-impact confirmation. |
| P2 | Remote provider & server settings + server self-update | Toggle/inspect providers, adjust server defaults, and trigger remote `updateServerWithProgress` from Settings. |
| P2 | Hardware keyboard shortcuts & clipboard/drag attachments | Support iPad / external keyboard shortcuts (`⌘N`, `⌘,`, send) and image paste / drag-and-drop into `SwftPillComposer`. |
| P3 | Background notifications & optional `GoogleSansFlex` font | Attention alerts when backgrounded; optional bundled brand typography alignment. |

### Missing on macOS (exists on iOS)

| Priority | Feature | Notes |
| --- | --- | --- |
| P0 | Full Usage view (Cost & Tokens charts + multi-server Limits) | `SwftKit` already has `UsageSummaryModels` and `ThreadsStore.getUsageSummary` on `swft/main`; add native Swift Charts Cost/Tokens views (`24h`/`7d`/`30d`/`90d`), KPI cards, provider/model breakdowns, and multi-server deduplicated Limits cards alongside the sidebar fuel pills. |
| P0 | Interactive `userInputRequest` cards & multi-option approvals | Wire `ThreadStore.respondToUserInput` into an interactive question card (single/multi-select + custom text) and surface dynamic server approval options (e.g. `Allow for Session`) in `ApprovalCard`. |
| P1 | Wake & network-path remote reconnect | Wire `NWPathMonitor` and `NSWorkspace.didWakeNotification` to `EnvironmentRegistry.handleNetworkPathChanged()` / `resumeAllRemotes()` (already in `SwftKit`) for instant sleep/Wi-Fi/VPN recovery. |
| P1 | Sidebar thread search, server/project filters & Mark Unread / Archive | Wire the existing sidebar search button, add environment/project filtering for multi-server setups, and expose `markUnread` and `archiveThread` (already in `SwftKit`) in thread menus. |
| P2 | Rich Markdown blocks (tables, blockquotes, task lists, rules) | Bring `MessageText` up to `MarkdownProseView` parity with GFM pipe tables, blockquotes, `- [x]` checkboxes, and thematic breaks. |
| P2 | Per-thread composer permissions/interaction pills & text-size preference | Expose `RuntimeMode` and `ProviderInteractionMode` directly in thread/Home chrome and add a transcript text-size preference in Settings → General. |

*Shared gaps (missing on both macOS and iOS):* Thread checkpoint rollback/revert UI and the Scheduled tasks screen.

---

## Keeping This Doc Updated

Whenever you add, change, or merge a user-facing feature in `apps/macos` or `apps/ios`:

1. Update the feature's macOS/iOS status cell (`❌` → `🚧` when landing on a feature branch; `🚧` → `✅` when merged to `swft/main`).
2. Add a new row under the appropriate area if the capability isn't listed yet, marking intentional one-platform features as `➖` with a short rationale.
3. Add or remove matching entries in **Current Parity Gaps** so the backlog stays accurate.
4. Keep entries capability-focused — avoid file/line catalogs or implementation narration that drifts.
