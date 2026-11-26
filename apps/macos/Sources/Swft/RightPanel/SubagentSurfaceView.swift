import SwftDesign
import SwftKit
import SwiftUI

/// Live right-sidebar surface displaying a delegated subagent child thread with full transcript rendering,
/// nested subagent tab opening, pending approval responses, and an interactive follow-up composer.
struct SubagentSurfaceView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let threadID: String
    let tabID: String
    let subagentState: SubagentTabState

    @State private var draftText = ""
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var imagePreview: SwftImagePreview?
    @FocusState private var composerFocused: Bool

    private var subagentThreadId: String { subagentState.subagentThreadId }

    private var resolvedEnvironmentID: String? {
        subagentState.environmentId
            ?? model.threadSummary(for: threadID)?.environmentID
            ?? model.activeThreadEnvironmentID
    }

    private var liveStore: ThreadStore? {
        guard !model.isMock else { return nil }
        return model.rightPanel.subagentStores[subagentThreadId]
    }

    private var owningThreadsStore: ThreadsStore? {
        model.threadsStore(forEnvironmentID: resolvedEnvironmentID, fallbackThreadID: threadID)
    }

    private var isConnected: Bool {
        model.isEnvironmentConnected(environmentID: resolvedEnvironmentID, fallbackThreadID: threadID)
    }

    private var liveDetail: ThreadDetailState? {
        if model.isMock {
            if let override = model.rightPanel.mockSubagentDetails[subagentThreadId] {
                return override
            }
            if let existing = model.detail(for: subagentThreadId) {
                return existing
            }
            if let prompt = subagentState.prompt?.trimmingCharacters(in: .whitespacesAndNewlines), !prompt.isEmpty {
                return ThreadDetailState(
                    summary: fallbackSummary,
                    items: [TranscriptItem(id: "prompt:\(subagentThreadId)", kind: .user(prompt))],
                    diffStat: nil,
                    isRunning: subagentState.status.showsSpinner
                )
            }
            return nil
        }

        let pending = model.rightPanel.pendingSubagentMessages[subagentThreadId] ?? []
        let optimisticApprovals = model.rightPanel.optimisticSubagentApprovals[subagentThreadId] ?? [:]

        if let projection = liveStore?.projection {
            let store = owningThreadsStore
            let providers = store?.providers ?? []
            let providersByID = Dictionary(uniqueKeysWithValues: providers.map { ($0.instanceId, $0) })
            let threadsByID = Dictionary(
                (store?.threads ?? []).map { ($0.id, $0) },
                uniquingKeysWith: { _, latest in latest }
            )
            let thread = projection.thread
            let provider = providersByID[thread.providerInstanceId]
            let location: ThreadLocation? = thread.branch.flatMap { $0.isEmpty ? nil : .branch($0) }
                ?? resolvedWorkspaceLabel.map { .branch($0) }
            let summary = ThreadSummary(
                id: subagentThreadId,
                title: thread.title,
                project: model.threadSummary(for: threadID)?.project,
                location: location,
                provider: SwftAdapters.providerKind(
                    driver: provider?.driver ?? subagentState.providerDriver ?? thread.providerInstanceId,
                    instanceId: thread.providerInstanceId
                ),
                providerDisplayName: provider?.label ?? subagentState.providerDisplayName,
                activity: (liveStore?.isRunning == true) ? .running : .idle,
                updatedAt: thread.updatedAt,
                providerDriver: SwftAdapters.providerDriverIdentifier(
                    driver: provider?.driver ?? subagentState.providerDriver,
                    instanceId: thread.providerInstanceId
                ),
                providerIconUrl: provider?.iconUrl ?? subagentState.providerIconUrl,
                environmentID: resolvedEnvironmentID
            )
            return SwftAdapters.threadDetail(
                from: projection,
                summary: summary,
                providersByID: providersByID,
                threadsByID: threadsByID,
                optimisticApprovals: optimisticApprovals,
                pendingUserMessages: pending
            )
        }

        if !pending.isEmpty {
            let items = pending.map { TranscriptItem(id: $0.messageID, kind: .user($0.text, attachments: $0.attachments)) }
            return ThreadDetailState(summary: fallbackSummary, items: items, diffStat: nil, isRunning: false)
        }

        return nil
    }

    private var fallbackSummary: ThreadSummary {
        let driver = subagentState.providerDriver ?? ""
        let instanceId = subagentState.providerInstanceId ?? ""
        return ThreadSummary(
            id: subagentThreadId,
            title: headerTitle,
            project: model.threadSummary(for: threadID)?.project,
            location: resolvedWorkspaceLabel.map { .branch($0) },
            provider: SwftAdapters.providerKind(driver: driver, instanceId: instanceId),
            providerDisplayName: subagentState.providerDisplayName,
            activity: subagentState.status.showsSpinner ? .running : .idle,
            updatedAt: model.now,
            providerDriver: driver.isEmpty ? nil : driver,
            providerIconUrl: subagentState.providerIconUrl,
            environmentID: resolvedEnvironmentID
        )
    }

    private var isRunning: Bool {
        if model.isMock {
            return liveDetail?.isRunning ?? subagentState.status.showsSpinner
        }
        return liveStore?.isRunning == true
    }

    private var hasPendingApproval: Bool {
        if model.isMock {
            return liveDetail?.items.contains { item in
                if case .approval(let approval) = item.kind {
                    return approval.status == .pending
                }
                return false
            } ?? false
        }
        return (liveStore?.pendingApprovals.isEmpty == false) || (liveStore?.pendingUserInputs.isEmpty == false)
    }

    private var effectiveStatus: SubagentStatus {
        if hasPendingApproval {
            return .waiting
        }
        if isRunning {
            return .running
        }
        if !model.isMock, let liveStore, liveStore.isSynchronized {
            if let lastRun = liveStore.runs.last {
                let mapped = RightPanelLogic.subagentStatus(from: lastRun.status)
                if subagentState.status.isActive || mapped == .failed || mapped == .cancelled || mapped == .interrupted {
                    return mapped
                }
            } else if subagentState.status.isActive {
                return .idle
            }
        }
        return subagentState.status
    }

    private var headerTitle: String {
        if let title = liveStore?.thread?.title.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            return SubagentDisplayLogic.formatDisplayTitle(title)
        }
        let trimmed = subagentState.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Subagent" : trimmed
    }

    private var resolvedModelLabel: String? {
        if let thread = liveStore?.thread {
            let store = owningThreadsStore
            let provider = store?.provider(for: thread.modelSelection.instanceId)
            if let resolved = SubagentDisplayLogic.resolveModelLabel(
                reportedModel: nil,
                executedModel: nil,
                modelSelection: thread.modelSelection,
                childModelSelection: nil,
                provider: provider
            ) {
                return resolved
            }
        }
        return subagentState.modelLabel
    }

    private var resolvedProviderDisplayName: String? {
        if let instanceId = liveStore?.thread?.providerInstanceId,
           let provider = owningThreadsStore?.provider(for: instanceId)
        {
            return provider.label
        }
        return subagentState.providerDisplayName
    }

    private var resolvedProviderIcon: ResolvedProviderIcon {
        let instanceId = liveStore?.thread?.providerInstanceId ?? subagentState.providerInstanceId ?? ""
        let provider = owningThreadsStore?.provider(for: instanceId)
        return SwftAdapters.resolvedProviderIcon(
            driver: provider?.driver ?? subagentState.providerDriver,
            instanceId: instanceId,
            iconUrl: provider?.iconUrl ?? subagentState.providerIconUrl,
            displayName: provider?.label ?? subagentState.providerDisplayName
        )
    }

    private var resolvedWorkspaceLabel: String? {
        if let branch = liveStore?.thread?.branch?.trimmingCharacters(in: .whitespacesAndNewlines), !branch.isEmpty {
            return branch
        }
        if let worktree = liveStore?.thread?.worktreePath?.trimmingCharacters(in: .whitespacesAndNewlines), !worktree.isEmpty {
            return (worktree as NSString).lastPathComponent
        }
        if let detailLocation = liveDetail?.summary.location, case .branch(let branch) = detailLocation, !branch.isEmpty {
            return branch
        }
        return subagentState.workspaceLabel
    }

    private var providerModelSummary: String? {
        let parts = [resolvedProviderDisplayName, resolvedModelLabel]
            .compactMap { value -> String? in
                guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
                    return nil
                }
                return trimmed
            }
        guard !parts.isEmpty else { return nil }
        if parts.count == 2 && parts[0].caseInsensitiveCompare(parts[1]) == .orderedSame {
            return parts[0]
        }
        return parts.joined(separator: " · ")
    }

    private var subscriptionTaskID: String {
        "\(threadID)::\(tabID)::\(subagentThreadId)::\(resolvedEnvironmentID ?? "local")"
    }

    var body: some View {
        let rows = liveDetail?.rows ?? []
        let displayError = errorMessage ?? liveStore?.lastError

        VStack(spacing: 0) {
            headerBar
            Divider().overlay(SwftColor.borderSubtle)

            if let displayError, !displayError.isEmpty {
                errorBanner(displayError)
            }

            transcriptArea(rows: rows)
            compactComposer
        }
        .background(SwftColor.canvas)
        .environment(\.swftImagePreviewAction, SwftImagePreviewAction { [binding = $imagePreview] preview in
            binding.wrappedValue = preview
        })
        .environment(\.swftImageLoader, model.imageLoader(forThreadID: subagentThreadId, environmentID: resolvedEnvironmentID))
        .overlay {
            if let imagePreview {
                SwftImageLightbox(preview: imagePreview) { self.imagePreview = nil }
                    .id(imagePreview.id)
            }
        }
        .task(id: subscriptionTaskID) {
            attachSubagentStore()
        }
        .onDisappear {
            if !model.isMock {
                model.rightPanel.releaseSubagentStore(subagentThreadId: subagentThreadId, holderTabID: tabID)
            }
        }
        .onChange(of: liveStore?.thread?.title) { _, newTitle in
            guard let newTitle, !newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            model.rightPanel.updateSubagentTab(
                tabID: tabID,
                title: SubagentDisplayLogic.formatDisplayTitle(newTitle),
                for: threadID
            )
        }
        .onChange(of: effectiveStatus) { _, newStatus in
            model.rightPanel.updateSubagentTab(tabID: tabID, status: newStatus, for: threadID)
        }
        .onChange(of: resolvedWorkspaceLabel) { _, newWorkspace in
            if let newWorkspace {
                model.rightPanel.updateSubagentTab(tabID: tabID, workspaceLabel: newWorkspace, for: threadID)
            }
        }
        .onChange(of: resolvedModelLabel) { _, newModel in
            if let newModel {
                model.rightPanel.updateSubagentTab(tabID: tabID, modelLabel: newModel, for: threadID)
            }
        }
    }

    // MARK: - Sub-header

    private var headerBar: some View {
        HStack(spacing: 8) {
            ProviderIcon(resolved: resolvedProviderIcon, size: 13)
                .foregroundStyle(resolvedProviderIcon == .mark(.generic) ? SwftColor.textTertiary : SwftColor.textSecondary)
                .frame(width: 22, height: 22)
                .background(Circle().fill(SwftColor.surfaceMuted))
                .overlay(Circle().strokeBorder(SwftColor.borderSubtle, lineWidth: 1))

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(headerTitle)
                        .font(SwftType.captionStrong)
                        .foregroundStyle(SwftColor.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    statusPill
                }

                if providerModelSummary != nil || resolvedWorkspaceLabel != nil {
                    HStack(spacing: 5) {
                        if let providerModelSummary {
                            Text(providerModelSummary)
                                .font(.system(size: 11))
                                .foregroundStyle(SwftColor.textTertiary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        if let workspace = resolvedWorkspaceLabel {
                            if providerModelSummary != nil {
                                Text("·")
                                    .font(.system(size: 11))
                                    .foregroundStyle(SwftColor.textTertiary)
                            }
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.triangle.branch")
                                    .font(.system(size: 9, weight: .medium))
                                Text(workspace)
                                    .font(.system(size: 10.5, design: .monospaced))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            .foregroundStyle(SwftColor.textTertiary)
                        }
                    }
                }
            }
            .frame(minWidth: 0, alignment: .leading)

            Spacer(minLength: 4)

            IconButton("arrow.up.forward.square", help: "Open in main view", size: 24) {
                openInMainView()
            }
        }
        .rightPanelSubHeader()
    }

    private var statusPill: some View {
        let style = statusAppearance
        return HStack(spacing: 4) {
            if effectiveStatus.showsSpinner || isRunning {
                ProgressView()
                    .controlSize(.mini)
                    .scaleEffect(0.7)
                    .frame(width: 9, height: 9)
            } else {
                Circle()
                    .fill(style.dot)
                    .frame(width: 6, height: 6)
            }
            Text(style.label)
                .font(SwftType.micro)
                .lineLimit(1)
        }
        .foregroundStyle(style.foreground)
        .padding(.horizontal, 6)
        .frame(height: 17)
        .background(Capsule().fill(style.background))
        .fixedSize()
    }

    private var statusAppearance: (label: String, dot: Color, foreground: Color, background: Color) {
        if hasPendingApproval {
            return ("Needs approval", SwftColor.warning, SwftColor.warning, SwftColor.warningSoft)
        }
        switch effectiveStatus {
        case .pending:
            return ("Queued", SwftColor.accent, SwftColor.accent, SwftColor.accentSoft.opacity(0.7))
        case .running:
            return ("Running", SwftColor.accent, SwftColor.accent, SwftColor.accentSoft.opacity(0.7))
        case .waiting:
            return ("Waiting", SwftColor.warning, SwftColor.warning, SwftColor.warningSoft)
        case .completed:
            return ("Completed", SwftColor.success, SwftColor.success, RightPanelColor.successSoft)
        case .failed:
            return ("Failed", SwftColor.danger, SwftColor.danger, SwftColor.dangerSoft)
        case .idle:
            return ("Idle", SwftColor.textTertiary, SwftColor.textSecondary, SwftColor.surfaceMuted)
        case .cancelled, .interrupted, .unknown:
            return (effectiveStatus.displayLabel, SwftColor.textTertiary, SwftColor.textSecondary, SwftColor.surfaceMuted)
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundStyle(SwftColor.warning)
            Text(message)
                .font(SwftType.caption)
                .foregroundStyle(SwftColor.textPrimary)
                .lineLimit(3)
            Spacer()
            if errorMessage != nil {
                Button("Dismiss") { errorMessage = nil }
                    .buttonStyle(.plain)
                    .font(SwftType.captionStrong)
                    .foregroundStyle(SwftColor.accent)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(SwftColor.warningSoft)
    }

    // MARK: - Transcript

    @ViewBuilder
    private func transcriptArea(rows: [TranscriptRow]) -> some View {
        let isAwaitingSnapshot = !model.isMock && liveStore != nil && liveStore?.projection == nil && liveStore?.isSynchronized == false
        let trimmedPrompt = subagentState.prompt?.trimmingCharacters(in: .whitespacesAndNewlines)

        if rows.isEmpty && isAwaitingSnapshot {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let trimmedPrompt, !trimmedPrompt.isEmpty {
                        UserBubble(trimmedPrompt)
                    }
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Loading subagent transcript…")
                            .font(SwftType.caption)
                            .foregroundStyle(SwftColor.textTertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: trimmedPrompt?.isEmpty == false ? .leading : .center)
                    .padding(.top, trimmedPrompt?.isEmpty == false ? 4 : 80)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else if rows.isEmpty {
            RightPanelEmptyState(
                icon: "cpu",
                title: isConnected ? "No messages yet" : "Environment offline",
                message: isConnected
                    ? "Send a follow-up below or wait for the subagent to emit its first response."
                    : "Reconnect to view or message this subagent."
            )
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(rows) { row in
                            transcriptRowView(row)
                                .id(row.id)
                        }
                        if showsRunningFooter(for: rows) {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.mini)
                                Text("Working…")
                                    .font(SwftType.caption)
                                    .foregroundStyle(SwftColor.textTertiary)
                            }
                            .padding(.top, 2)
                            .id("subagent-running-footer")
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .defaultScrollAnchor(.top, for: .alignment)
                .defaultScrollAnchor(.bottom, for: .initialOffset)
                .onChange(of: rows.count) { _, _ in
                    if let lastID = rows.last?.id {
                        proxy.scrollTo(lastID, anchor: .bottom)
                    }
                }
            }
        }
    }

    private func showsRunningFooter(for rows: [TranscriptRow]) -> Bool {
        guard isRunning else { return false }
        guard let last = rows.last else { return true }
        switch last {
        case .work(let fold) where fold.isLive:
            return false
        case .assistant(_, _, let streaming) where streaming:
            return false
        case .subagent(let nested) where nested.status.isActive:
            return false
        case .subagentGroup(let group) where group.hasActive:
            return false
        case .approval(_, let approval) where approval.status == .pending:
            return false
        default:
            return true
        }
    }

    @ViewBuilder
    private func transcriptRowView(_ row: TranscriptRow) -> some View {
        switch row {
        case .user(_, let text, let attachments):
            UserBubble(text, attachments: attachments)
                .equatable()
        case .assistant(_, let blocks, let streaming):
            AssistantMessage {
                ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                    switch block {
                    case .text(let markdown):
                        MessageText(markdown, streaming: streaming && index == blocks.count - 1)
                            .equatable()
                    case .code(let language, let source):
                        CodeBlock(source, language: language)
                            .equatable()
                    case .image(let alt, let source):
                        MessageImage(source: source, alt: alt)
                    case .attachments(let attachments):
                        AttachmentStrip(attachments, trailing: false)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        case .work(let fold):
            WorkFoldView(fold: fold, isExpanded: model.expandedWorkFolds.contains(fold.id)) {
                withAnimation(SwftMotion.resolve(SwftMotion.disclosure, reduceMotion: reduceMotion)) {
                    model.toggleWorkFold(fold.id)
                }
            }
        case .subagent(let nested):
            SubagentSingleRowView(
                item: nested,
                parentEnvironmentID: resolvedEnvironmentID,
                knownEnvironmentIDs: model.knownEnvironmentIDs,
                isExpanded: model.expandedSubagentRows.contains(nested.id),
                onToggleExpansion: { rowID in
                    withAnimation(SwftMotion.resolve(SwftMotion.disclosure, reduceMotion: reduceMotion)) {
                        model.toggleSubagentRow(rowID)
                    }
                },
                onOpenThread: { target in
                    withAnimation(SwftMotion.resolve(SwftMotion.screen, reduceMotion: reduceMotion)) {
                        _ = model.openSubagentInRightPanel(target, item: nested, for: threadID)
                    }
                }
            )
            .equatable()
        case .subagentGroup(let group):
            SubagentGroupRowView(
                group: group,
                parentEnvironmentID: resolvedEnvironmentID,
                knownEnvironmentIDs: model.knownEnvironmentIDs,
                expandedIDs: model.expandedSubagentRows,
                onToggleExpansion: { rowID in
                    withAnimation(SwftMotion.resolve(SwftMotion.disclosure, reduceMotion: reduceMotion)) {
                        model.toggleSubagentRow(rowID)
                    }
                },
                onOpenThread: { target in
                    let matched = group.members.first {
                        $0.childThreadID == target.threadID || $0.remoteThreadID == target.threadID
                    }
                    withAnimation(SwftMotion.resolve(SwftMotion.screen, reduceMotion: reduceMotion)) {
                        _ = model.openSubagentInRightPanel(target, item: matched, for: threadID)
                    }
                }
            )
            .equatable()
        case .approval(let itemID, let approval):
            ApprovalCard(
                title: approval.title,
                message: approval.message,
                command: approval.command,
                status: approval.status.cardStatus,
                onApprove: {
                    Task { await respondToApproval(itemID: itemID, requestId: approval.requestId, approved: true) }
                },
                onDeny: {
                    Task { await respondToApproval(itemID: itemID, requestId: approval.requestId, approved: false) }
                }
            )
        case .note(_, let title, let message, let isError):
            QuietNote(title: title, message: message, isError: isError)
        }
    }

    // MARK: - Compact Composer

    private var compactComposer: some View {
        let canInteract = model.isMock || (isConnected && liveStore != nil)
        let canSend = canInteract && !draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
        let sendState: SendButton.State = isRunning ? .stop : (canSend ? .ready : .idle)
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)

        return HStack(alignment: .bottom, spacing: 8) {
            TextField(
                canInteract ? "Follow up with subagent…" : "Environment offline",
                text: $draftText,
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .font(SwftType.label)
            .foregroundStyle(SwftColor.textPrimary)
            .lineLimit(1...6)
            .focused($composerFocused)
            .disabled(!canInteract)
            .onSubmit {
                Task { await sendFollowUp() }
            }
            .padding(.vertical, 7)
            .padding(.leading, 6)

            // Mirrors the main composer's `SendButton` look without its ⌘↩ shortcut, which belongs to the main thread.
            Button {
                Task {
                    if isRunning {
                        await stopSubagentRun()
                    } else {
                        await sendFollowUp()
                    }
                }
            } label: {
                Image(systemName: isRunning ? "stop.fill" : "arrow.up")
                    .font(.system(size: isRunning ? 9.5 : 12, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))
                    .foregroundStyle(ComposerPolish.sendIconColor(for: sendState))
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(ComposerPolish.sendFill(for: sendState)))
                    .contentShape(Circle())
            }
            .buttonStyle(HoverFillStyle(shape: Circle(), pressScale: 0.9))
            .disabled(sendState == .idle || (!canInteract && !isRunning))
            .animation(SwftMotion.resolve(SwftMotion.pop, reduceMotion: reduceMotion), value: sendState)
            .help(isRunning ? "Stop subagent" : "Send follow-up")
        }
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .background(shape.fill(SwftColor.surface).shadow(color: SwftColor.shadow, radius: 10, y: 3))
        .overlay(shape.strokeBorder(composerFocused ? SwftColor.border : SwftColor.borderSubtle, lineWidth: 1))
        .contentShape(shape)
        .onTapGesture { if canInteract { composerFocused = true } }
        .animation(SwftMotion.resolve(SwftMotion.quick, reduceMotion: reduceMotion), value: composerFocused)
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 12)
        .background(SwftColor.canvas)
    }

    // MARK: - Actions & Store Lifecycle

    private func attachSubagentStore() {
        guard !model.isMock else { return }
        guard let conn = model.connection(forEnvironmentID: resolvedEnvironmentID, fallbackThreadID: threadID) else {
            errorMessage = "Environment is not connected."
            return
        }
        errorMessage = nil
        let cached = model.rightPanel.cachedSubagentProjection(for: subagentThreadId)
            ?? model.cachedProjection(for: subagentThreadId)
        _ = model.rightPanel.ensureSubagentStore(
            subagentThreadId: subagentThreadId,
            connection: conn,
            initialProjection: cached,
            holderTabID: tabID
        )
    }

    private func openInMainView() {
        if let projection = liveStore?.projection {
            model.rememberProjection(projection)
        }
        let parentEnvID = model.threadSummary(for: threadID)?.environmentID ?? model.activeThreadEnvironmentID
        let driver = subagentState.providerDriver ?? ""
        let instanceId = subagentState.providerInstanceId ?? ""
        let target = SubagentNavigationTarget(
            threadID: subagentThreadId,
            environmentID: resolvedEnvironmentID,
            title: headerTitle,
            provider: SwftAdapters.providerKind(driver: driver, instanceId: instanceId),
            providerDriver: driver,
            providerDisplayName: resolvedProviderDisplayName,
            providerIconURL: subagentState.providerIconUrl,
            isRemoteLinked: resolvedEnvironmentID != nil && resolvedEnvironmentID != parentEnvID
        )
        model.openSubagentThread(target, fromThreadID: threadID)
    }

    private func sendFollowUp() async {
        let text = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }
        draftText = ""
        errorMessage = nil

        if model.isMock {
            var current = liveDetail ?? ThreadDetailState(summary: fallbackSummary, items: [], diffStat: nil)
            current.items.append(TranscriptItem(id: UUID().uuidString, kind: .user(text), startedAt: Date()))
            current.items.append(TranscriptItem(
                id: UUID().uuidString,
                kind: .assistant(blocks: [
                    .text("Got it — continuing in **\(headerTitle)** without leaving your main thread:\n\n> \(text)"),
                ], streaming: false),
                startedAt: Date(),
                completedAt: Date()
            ))
            current.isRunning = false
            model.rightPanel.mockSubagentDetails[subagentThreadId] = current
            model.rightPanel.updateSubagentTab(tabID: tabID, status: .completed, for: threadID)
            return
        }

        guard let conn = model.connection(forEnvironmentID: resolvedEnvironmentID, fallbackThreadID: threadID) else {
            errorMessage = "Environment is not connected."
            draftText = text
            return
        }

        let store = model.rightPanel.ensureSubagentStore(
            subagentThreadId: subagentThreadId,
            connection: conn,
            holderTabID: tabID
        )
        let messageID = UUID().uuidString
        model.rightPanel.pendingSubagentMessages[subagentThreadId, default: []].append(
            PendingUserMessage(messageID: messageID, text: text)
        )
        isSending = true
        defer { isSending = false }

        do {
            _ = try await store.sendMessage(
                text: text,
                messageId: messageID,
                modelSelection: store.thread?.modelSelection
            )
            model.rightPanel.updateSubagentTab(tabID: tabID, status: .running, for: threadID)
        } catch {
            model.rightPanel.pendingSubagentMessages[subagentThreadId]?.removeAll { $0.messageID == messageID }
            if draftText.isEmpty { draftText = text }
            errorMessage = error.localizedDescription
        }
    }

    private func stopSubagentRun() async {
        if model.isMock {
            if var current = liveDetail {
                current.isRunning = false
                model.rightPanel.mockSubagentDetails[subagentThreadId] = current
            }
            model.rightPanel.updateSubagentTab(tabID: tabID, status: .interrupted, for: threadID)
            return
        }

        guard let liveStore else { return }
        let activeRunID = liveStore.activeRun?.id
        let isUnresponsive = liveStore.visibleItems.contains { projected in
            guard projected.item.runId == activeRunID || activeRunID == nil else { return false }
            if case .runInterruptRequest(_, let unresponsiveAt) = projected.item.kind {
                return unresponsiveAt != nil
            }
            return false
        }
        let canForceStop = owningThreadsStore?.environment?.capabilities.threadForceStop == true

        do {
            if isUnresponsive && canForceStop {
                _ = try await liveStore.forceStop()
            } else {
                try await liveStore.interrupt(reason: "User stopped subagent")
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func respondToApproval(itemID: String, requestId: String, approved: Bool) async {
        if model.isMock {
            guard var current = liveDetail,
                  let index = current.items.firstIndex(where: { $0.id == itemID }),
                  case .approval(var approval) = current.items[index].kind
            else { return }
            approval.status = approved ? .approved : .denied
            current.items[index].kind = .approval(approval)
            model.rightPanel.mockSubagentDetails[subagentThreadId] = current
            return
        }

        guard !requestId.isEmpty, let liveStore else { return }
        model.rightPanel.optimisticSubagentApprovals[subagentThreadId, default: [:]][requestId] = approved ? .approved : .denied
        do {
            try await liveStore.respondToApproval(
                requestId: requestId,
                decision: approved ? .accept : .decline
            )
        } catch {
            model.rightPanel.optimisticSubagentApprovals[subagentThreadId]?.removeValue(forKey: requestId)
            errorMessage = error.localizedDescription
        }
    }
}
