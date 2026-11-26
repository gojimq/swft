import SwftDesign
import SwftKit
import SwiftUI

struct SideChatSurfaceView: View {
    @Environment(AppModel.self) private var model
    let threadID: String
    let tabID: String
    let sideChatState: SideChatTabState

    @State private var draftText = ""
    @State private var isCreating = false
    @State private var isSending = false
    @State private var errorMessage: String?

    private var sideThreadId: String? { sideChatState.sideThreadId }

    private var liveStore: ThreadStore? {
        guard !model.isMock, let sideThreadId else { return nil }
        return model.rightPanel.sideChatStores[sideThreadId]
    }

    private var isRunning: Bool {
        liveStore?.isRunning == true
    }

    private var headerTitle: String {
        if let title = liveStore?.thread?.title.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            return title
        }
        if let title = sideChatState.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            return title
        }
        return "Side chat"
    }

    private var modelBadgeText: String? {
        if model.isMock {
            return model.selectedModel?.name ?? "Opus 5.5"
        }
        if let selection = liveStore?.thread?.modelSelection {
            let store = model.threadsStore(forThreadID: threadID)
            return store?.model(for: selection)?.displayName ?? selection.model
        }
        return model.selectedModel?.name
    }

    private var transcriptItems: [TranscriptItem] {
        if model.isMock {
            let key = sideThreadId ?? tabID
            return model.rightPanel.mockSideChatItems[key] ?? RightPanelMockData.initialMockSideChatMessages()
        }
        guard let sideThreadId, let liveStore else { return [] }
        let pending = model.rightPanel.pendingSideChatMessages[sideThreadId] ?? []
        if let projection = liveStore.projection {
            let summary = ThreadSummary(
                id: sideThreadId,
                title: projection.thread.title,
                project: model.threadSummary(for: threadID)?.project,
                location: nil,
                provider: .other,
                activity: liveStore.isRunning ? .running : .idle,
                updatedAt: projection.thread.updatedAt
            )
            return SwftAdapters.threadDetail(
                from: projection,
                summary: summary,
                pendingUserMessages: pending
            ).items
        }
        return pending.map { TranscriptItem(id: $0.messageID, kind: .user($0.text)) }
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider().overlay(SwftColor.borderSubtle)

            if let errorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(SwftColor.warning)
                    Text(errorMessage)
                        .font(SwftType.caption)
                        .foregroundStyle(SwftColor.textPrimary)
                        .lineLimit(3)
                    Spacer()
                    if sideThreadId == nil {
                        Button("Retry") {
                            Task { await ensureSideChatForked() }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    } else {
                        Button("Dismiss") { self.errorMessage = nil }
                            .buttonStyle(.plain)
                            .font(SwftType.captionStrong)
                            .foregroundStyle(SwftColor.accent)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(SwftColor.warningSoft)
            }

            if isCreating && sideThreadId == nil {
                VStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Forking side chat…")
                        .font(SwftType.caption)
                        .foregroundStyle(SwftColor.textTertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if sideThreadId == nil && !model.isMock {
                RightPanelEmptyState(
                    icon: "bubble.left.and.bubble.right",
                    title: "Side chat unavailable",
                    message: errorMessage ?? "Side chats fork from this thread's latest stable point after its first message."
                ) {
                    Button("Start Side Chat") {
                        Task { await ensureSideChatForked() }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(isCreating)
                }
            } else {
                transcriptScrollArea
                Divider().overlay(SwftColor.borderSubtle)
                compactComposer
            }
        }
        .background(SwftColor.canvas)
        .task(id: "\(threadID)::\(tabID)::\(sideThreadId ?? "none")") {
            await attachOrForkIfNeeded()
        }
        .onChange(of: liveStore?.thread?.title) { _, newTitle in
            if let newTitle, !newTitle.isEmpty {
                model.rightPanel.updateSideChatTab(tabID: tabID, title: newTitle, for: threadID)
            }
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(headerTitle)
                    .font(SwftType.captionStrong)
                    .foregroundStyle(SwftColor.textPrimary)
                    .lineLimit(1)
                if let badge = modelBadgeText {
                    HStack(spacing: 5) {
                        Text(badge)
                            .font(.system(size: 10.5))
                            .foregroundStyle(SwftColor.textTertiary)
                            .lineLimit(1)
                        if isRunning {
                            RightPanelStatusBadge("Running", tone: .accent)
                        }
                    }
                }
            }

            Spacer(minLength: 4)

            if let sideThreadId {
                IconButton("arrow.up.left.and.arrow.down.right", help: "Open in main view", size: 24) {
                    model.openSideChatInMainView(sideThreadId)
                }
            }

            IconButton("plus.bubble", help: "New side chat", size: 24) {
                _ = model.rightPanel.openSideChat(for: threadID)
            }

            if sideThreadId != nil {
                IconButton("trash", help: "Delete side chat", size: 24, tint: SwftColor.textTertiary) {
                    Task { await deleteCurrentSideChat() }
                }
            }
        }
        .padding(.horizontal, 10)
        .frame(height: RightPanelMetrics.subHeaderHeight + 4)
        .background(SwftColor.surface)
    }

    // MARK: - Transcript

    private var transcriptScrollArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                let items = transcriptItems
                if items.isEmpty {
                    RightPanelEmptyState(
                        icon: "bubble.left.and.bubble.right",
                        title: "Ask a side question",
                        message: "This side chat shares context from the main thread without interrupting its active run."
                    )
                    .frame(minHeight: 240)
                } else {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(items) { item in
                            sideChatRow(item)
                                .id(item.id)
                        }
                        if isRunning {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.mini)
                                Text("Thinking…")
                                    .font(SwftType.caption)
                                    .foregroundStyle(SwftColor.textTertiary)
                            }
                            .padding(.top, 2)
                            .id("side-chat-running")
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .onChange(of: transcriptItems.count) { _, _ in
                if let lastID = transcriptItems.last?.id {
                    proxy.scrollTo(lastID, anchor: .bottom)
                }
            }
        }
    }

    @ViewBuilder
    private func sideChatRow(_ item: TranscriptItem) -> some View {
        switch item.kind {
        case .user(let text, let attachments):
            UserBubble(text, attachments: attachments)
        case .assistant(let blocks, let streaming):
            AssistantMessage {
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                    switch block {
                    case .text(let markdown):
                        MessageText(markdown, streaming: streaming)
                    case .code(let language, let source):
                        CodeBlock(source, language: language)
                    case .image, .attachments:
                        EmptyView()
                    }
                }
            }
        case .toolCall(let tool):
            HStack(spacing: 6) {
                Image(systemName: tool.status == .failed ? "xmark.circle.fill" : (tool.status == .running ? "clock" : "checkmark.circle"))
                    .font(.system(size: 11))
                    .foregroundStyle(tool.status == .failed ? SwftColor.danger : SwftColor.textTertiary)
                Text(tool.title)
                    .font(SwftType.captionStrong)
                    .foregroundStyle(SwftColor.textSecondary)
                Text(tool.detail)
                    .font(SwftType.monoSmall)
                    .foregroundStyle(SwftColor.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 6).fill(SwftColor.surfaceMuted.opacity(0.65)))
        case .approval(let approval):
            ApprovalCard(
                title: approval.title,
                message: approval.message,
                command: approval.command,
                status: approval.status.cardStatus,
                onApprove: {
                    Task { await respondToApproval(requestId: approval.requestId, approved: true) }
                },
                onDeny: {
                    Task { await respondToApproval(requestId: approval.requestId, approved: false) }
                }
            )
        case .notice(let title, let message, let isError):
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(SwftType.captionStrong)
                    .foregroundStyle(isError ? SwftColor.danger : SwftColor.textSecondary)
                Text(message)
                    .font(SwftType.caption)
                    .foregroundStyle(SwftColor.textTertiary)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isError ? SwftColor.dangerSoft : SwftColor.surfaceMuted)
            )
        }
    }

    // MARK: - Compact Composer

    private var compactComposer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Ask a side question…", text: $draftText, axis: .vertical)
                .textFieldStyle(.plain)
                .font(SwftType.label)
                .foregroundStyle(SwftColor.textPrimary)
                .lineLimit(1...5)
                .onSubmit {
                    Task { await sendSideChatMessage() }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: SwftRadius.m, style: .continuous)
                        .fill(SwftColor.surfaceMuted)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: SwftRadius.m, style: .continuous)
                        .strokeBorder(SwftColor.borderSubtle, lineWidth: 1)
                )

            if isRunning {
                Button {
                    Task { await stopSideChatRun() }
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(SwftColor.onSend)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(SwftColor.danger))
                }
                .buttonStyle(.plain)
                .help("Stop side chat")
            } else {
                let canSend = !draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
                Button {
                    Task { await sendSideChatMessage() }
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(canSend ? SwftColor.onSend : SwftColor.textTertiary)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(canSend ? SwftColor.sendFill : SwftColor.sendFillIdle))
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .help("Send message")
            }
        }
        .padding(10)
        .background(SwftColor.surface)
    }

    // MARK: - Actions & RPCs

    private func attachOrForkIfNeeded() async {
        if model.isMock {
            if sideThreadId == nil {
                let mockID = "mock-side-\(UUID().uuidString.prefix(8))"
                model.rightPanel.mockSideChatItems[mockID] = RightPanelMockData.initialMockSideChatMessages()
                model.rightPanel.updateSideChatTab(
                    tabID: tabID,
                    sideThreadId: mockID,
                    title: "Side chat",
                    isCreating: false,
                    for: threadID
                )
            }
            return
        }

        guard let conn = model.connection(forThreadID: threadID) else {
            errorMessage = "Environment is not connected."
            return
        }

        if let existingId = sideThreadId {
            _ = model.rightPanel.ensureSideChatStore(sideThreadId: existingId, connection: conn)
            return
        }

        await ensureSideChatForked()
    }

    private func ensureSideChatForked() async {
        guard !isCreating else { return }
        guard let conn = model.connection(forThreadID: threadID) else {
            errorMessage = "Environment is not connected."
            return
        }
        isCreating = true
        errorMessage = nil
        model.rightPanel.updateSideChatTab(tabID: tabID, isCreating: true, for: threadID)
        defer {
            isCreating = false
            model.rightPanel.updateSideChatTab(tabID: tabID, isCreating: false, for: threadID)
        }

        do {
            let newId = try await conn.forkSideChat(
                sourceThreadId: threadID,
                title: "Side chat"
            )
            _ = model.rightPanel.ensureSideChatStore(sideThreadId: newId, connection: conn)
            model.rightPanel.updateSideChatTab(
                tabID: tabID,
                sideThreadId: newId,
                title: "Side chat",
                isCreating: false,
                for: threadID
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func sendSideChatMessage() async {
        let text = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }
        draftText = ""
        errorMessage = nil

        if model.isMock {
            let key = sideThreadId ?? tabID
            var items = model.rightPanel.mockSideChatItems[key] ?? RightPanelMockData.initialMockSideChatMessages()
            items.append(TranscriptItem(id: UUID().uuidString, kind: .user(text), startedAt: Date()))
            items.append(TranscriptItem(
                id: UUID().uuidString,
                kind: .assistant(blocks: [
                    .text("Got it — in mock mode, this side chat echoes back while your main thread stays untouched:\n\n> \(text)"),
                ], streaming: false),
                startedAt: Date(),
                completedAt: Date()
            ))
            model.rightPanel.mockSideChatItems[key] = items
            return
        }

        guard let sideThreadId, let conn = model.connection(forThreadID: threadID) else {
            errorMessage = "Side chat is not ready yet."
            draftText = text
            return
        }

        let store = model.rightPanel.ensureSideChatStore(sideThreadId: sideThreadId, connection: conn)
        let messageID = UUID().uuidString
        model.rightPanel.pendingSideChatMessages[sideThreadId, default: []].append(
            PendingUserMessage(messageID: messageID, text: text)
        )
        isSending = true
        defer { isSending = false }

        do {
            let selection = model.selectedModel.map {
                SwftAdapters.modelSelection(from: $0, reasoningChoiceId: model.selectedReasoningChoice?.id)
            }
            _ = try await store.sendMessage(
                text: text,
                messageId: messageID,
                modelSelection: selection
            )
        } catch {
            model.rightPanel.pendingSideChatMessages[sideThreadId]?.removeAll { $0.messageID == messageID }
            if draftText.isEmpty { draftText = text }
            errorMessage = error.localizedDescription
        }
    }

    private func stopSideChatRun() async {
        guard let liveStore else { return }
        do {
            try await liveStore.interrupt(reason: "User stopped side chat")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func respondToApproval(requestId: String, approved: Bool) async {
        guard !requestId.isEmpty, let liveStore else { return }
        do {
            try await liveStore.respondToApproval(
                requestId: requestId,
                decision: approved ? .accept : .decline
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteCurrentSideChat() async {
        guard let sideThreadId else {
            model.rightPanel.closeTab(tabID, for: threadID)
            return
        }
        if model.isMock {
            model.rightPanel.mockSideChatItems.removeValue(forKey: sideThreadId)
            model.rightPanel.closeTab(tabID, for: threadID)
            return
        }
        guard let store = model.threadsStore(forThreadID: threadID) else {
            model.rightPanel.closeTab(tabID, for: threadID)
            return
        }
        do {
            try await store.deleteSideChat(threadId: sideThreadId)
            model.rightPanel.closeTab(tabID, for: threadID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
