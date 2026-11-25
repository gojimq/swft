import Foundation
import SwftKit

/// Pure adapter functions mapping SwftKit wire/store types onto plain UI view-state types.
enum SwftAdapters {

    // MARK: - Providers & Models

    static func providerKind(driver: String, instanceId: String = "") -> ProviderKind {
        let normalizedDriver = driver.lowercased()
        switch normalizedDriver {
        case "claudeagent", "claude":
            return .claude
        case "codex":
            return .codex
        case "cursor":
            return .cursor
        case "opencode":
            return .opencode
        case "antigravity", "gemini":
            return .gemini
        default:
            let normalizedId = instanceId.lowercased()
            if normalizedId.contains("claude") { return .claude }
            if normalizedId.contains("codex") { return .codex }
            if normalizedId.contains("cursor") { return .cursor }
            if normalizedId.contains("opencode") { return .opencode }
            if normalizedId.contains("gemini") || normalizedId.contains("antigravity") { return .gemini }
            return .other
        }
    }

    static func modelOptions(from providers: [ServerProvider]) -> [ModelOption] {
        let primary = providers.filter {
            $0.enabled && $0.installed && $0.isAvailable && $0.status != .disabled && $0.status != .error && !$0.models.isEmpty
        }
        let eligible = primary.isEmpty
            ? providers.filter { $0.enabled && !$0.models.isEmpty }
            : primary

        let sortedProviders = eligible.sorted { lhs, rhs in
            let lRank = providerSortRank(lhs)
            let rRank = providerSortRank(rhs)
            if lRank != rRank { return lRank < rRank }
            return false
        }

        var options: [ModelOption] = []
        for provider in sortedProviders {
            let nonLegacy = provider.models.filter { $0.isLegacy != true }
            let models = nonLegacy.isEmpty ? provider.models : nonLegacy
            let kind = providerKind(driver: provider.driver, instanceId: provider.instanceId)
            for model in models {
                let reasoning = extractReasoningControl(from: model)
                options.append(
                    ModelOption(
                        id: modelOptionID(instanceId: provider.instanceId, slug: model.slug),
                        instanceId: provider.instanceId,
                        slug: model.slug,
                        name: model.displayName,
                        provider: kind,
                        providerDisplayName: provider.label,
                        reasoningOptionId: reasoning?.optionId,
                        reasoningOptionLabel: reasoning?.label,
                        reasoningChoices: reasoning?.choices ?? [],
                        defaultReasoningChoiceId: reasoning?.defaultChoiceId,
                        isDefault: model.isDefault == true,
                        subProvider: model.subProvider,
                        isNew: model.badge == "new"
                    )
                )
            }
        }
        return options
    }

    /// The model picker's catalog: every enabled provider instance (with why it can't be used, if so) and the models
    /// usable now. Mirrors Studio's `catalogOf`.
    static func pickerCatalog(from providers: [ServerProvider]) -> PickerCatalog {
        PickerCatalog(harnesses: providers.filter(\.enabled).map(pickerHarness(from:)), models: modelOptions(from: providers))
    }

    static func pickerHarness(from provider: ServerProvider) -> PickerHarness {
        let unauthenticated = provider.auth.status == .unauthenticated
        let ready = isPickerReady(provider) || provider.subProviders != nil
        let reason: String? = if !provider.enabled {
            "Turned off"
        } else if !provider.installed {
            "Not installed"
        } else if ready {
            nil
        } else {
            nonEmpty(provider.unavailableReason) ?? nonEmpty(provider.message) ?? (unauthenticated ? "Not signed in" : "Not ready")
        }
        return PickerHarness(
            id: provider.instanceId,
            driver: provider.driver,
            label: nonEmpty(provider.displayName) ?? provider.label,
            kind: providerKind(driver: provider.driver, instanceId: provider.instanceId),
            accentHex: normalizedAccentHex(provider.accentColor),
            account: providerAccount(provider.auth),
            unauthenticated: unauthenticated,
            unavailableReason: reason,
            subProviders: provider.subProviders?.map { PickerSubProvider(name: $0.name, unavailableReason: $0.unavailableReason) }
        )
    }

    static func usageProviders(from providers: [ServerProvider]) -> [UsageProviderEntry] {
        providers.map(usageProvider(from:))
    }

    static func usageProvider(from provider: ServerProvider) -> UsageProviderEntry {
        let harness = pickerHarness(from: provider)
        return UsageProviderEntry(
            id: provider.instanceId,
            driver: provider.driver,
            label: harness.label,
            kind: harness.kind,
            accentHex: harness.accentHex,
            account: harness.account,
            listed: true,
            enabled: provider.enabled,
            installed: provider.installed,
            unauthenticated: harness.unauthenticated,
            unavailableReason: harness.unavailableReason,
            usageLimits: provider.usageLimits.map(usageLimitsSnapshot(from:))
        )
    }

    static func usageLimitsSnapshot(from limits: ServerProviderUsageLimits) -> UsageLimitsSnapshot {
        UsageLimitsSnapshot(
            checkedAt: limits.checkedAt,
            windows: limits.windows.map { window in
                let kind: UsageWindowKind = switch window.kind {
                case .session: .session
                case .weekly: .weekly
                case .monthly: .monthly
                case .other: .other
                case .unknown: .unknown
                }
                return UsageWindow(
                    id: window.id,
                    kind: kind,
                    label: window.label,
                    modelIds: window.modelIds,
                    providerIds: window.providerIds,
                    usedPercent: window.usedPercent,
                    resetsAt: window.resetsAt,
                    windowDurationMins: window.windowDurationMins
                )
            },
            zeroSpendCap: limits.zeroSpendCap,
            credentialFingerprint: limits.credentialFingerprint,
            unavailable: limits.unavailable.map { unavailable in
                let reason: UsageUnavailableReason = switch unavailable.reason {
                case .unsupported: .unsupported
                case .probeFailed: .probeFailed
                case .unknown: .unknown
                }
                return UsageUnavailable(reason: reason, message: unavailable.message)
            }
        )
    }

    /// "Auth label · email" for a signed-in provider.
    static func providerAccount(_ auth: ServerProviderAuth) -> String? {
        guard auth.status == .authenticated else { return nil }
        let authLabel = auth.type == "customEndpoint" ? "Custom API endpoint" : nonEmpty(auth.label) ?? nonEmpty(auth.type)
        let parts = [authLabel, nonEmpty(auth.email)].compactMap { $0 }
        if parts.count == 2 && parts[0] == parts[1] { return parts[0] }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// `#rrggbb` (lowercased) or nil.
    static func normalizedAccentHex(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespaces).lowercased(),
              trimmed.count == 7, trimmed.first == "#",
              trimmed.dropFirst().allSatisfy(\.isHexDigit)
        else { return nil }
        return trimmed
    }

    private static func isPickerReady(_ provider: ServerProvider) -> Bool {
        guard provider.enabled, provider.isAvailable else { return false }
        if provider.status == .ready { return true }
        if provider.status == .warning {
            let usable = Set((provider.subProviders ?? []).filter { $0.unavailableReason == nil }.map(\.name))
            if provider.models.contains(where: { $0.subProvider.map(usable.contains) == true }) { return true }
        }
        if provider.subProviders != nil { return false }
        return provider.status == .warning && provider.installed && provider.auth.status == .authenticated && !provider.models.isEmpty
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    static func modelOptionID(instanceId: String, slug: String) -> String {
        "\(instanceId)::\(slug)"
    }

    static func preferredDefaultModel(
        from options: [ModelOption],
        projectDefault: ModelSelection? = nil
    ) -> ModelOption? {
        if let projectDefault,
           let match = options.first(where: {
               $0.instanceId == projectDefault.instanceId && $0.slug == projectDefault.model
           })
        {
            return match
        }
        return options.first(where: \.isDefault) ?? options.first
    }

    static func modelSelection(
        from option: ModelOption,
        reasoningChoiceId: String?
    ) -> ModelSelection {
        let selections: [ProviderOptionSelection]?
        if let optionId = option.reasoningOptionId, !option.reasoningChoices.isEmpty {
            let validId: String?
            if let reasoningChoiceId, option.reasoningChoices.contains(where: { $0.id == reasoningChoiceId }) {
                validId = reasoningChoiceId
            } else {
                validId = option.defaultReasoningChoiceId ?? option.reasoningChoices.first?.id
            }
            if let validId {
                selections = [.string(optionId, validId)]
            } else {
                selections = nil
            }
        } else {
            selections = nil
        }
        return ModelSelection(instanceId: option.instanceId, model: option.slug, options: selections)
    }

    static func reasoningChoiceId(
        from selection: ModelSelection,
        for option: ModelOption
    ) -> String? {
        guard let optionId = option.reasoningOptionId else { return nil }
        if let entries = selection.options,
           let match = entries.first(where: { $0.id == optionId }),
           case .string(let value) = match.value,
           option.reasoningChoices.contains(where: { $0.id == value })
        {
            return value
        }
        return option.defaultReasoningChoiceId ?? option.reasoningChoices.first?.id
    }

    static func fallbackModelOption(
        for selection: ModelSelection,
        providersByID: [String: ServerProvider]
    ) -> ModelOption {
        let provider = providersByID[selection.instanceId]
        let model = provider?.models.first(where: { $0.slug == selection.model })
        let kind = providerKind(
            driver: provider?.driver ?? selection.instanceId,
            instanceId: selection.instanceId
        )
        let reasoning = model.flatMap(extractReasoningControl(from:))
        return ModelOption(
            id: modelOptionID(instanceId: selection.instanceId, slug: selection.model),
            instanceId: selection.instanceId,
            slug: selection.model,
            name: model?.displayName ?? selection.model,
            provider: kind,
            providerDisplayName: provider?.label ?? selection.instanceId,
            reasoningOptionId: reasoning?.optionId,
            reasoningOptionLabel: reasoning?.label,
            reasoningChoices: reasoning?.choices ?? [],
            defaultReasoningChoiceId: reasoning?.defaultChoiceId,
            isDefault: model?.isDefault == true,
            subProvider: model?.subProvider,
            isNew: model?.badge == "new"
        )
    }

    private static func providerSortRank(_ provider: ServerProvider) -> Int {
        if provider.status == .ready && provider.auth.status == .authenticated { return 0 }
        if provider.status == .ready { return 1 }
        if provider.status == .warning { return 2 }
        return 3
    }

    private struct ExtractedReasoningControl {
        let optionId: String
        let label: String
        let choices: [ReasoningChoice]
        let defaultChoiceId: String?
    }

    private static func extractReasoningControl(from model: ServerProviderModel) -> ExtractedReasoningControl? {
        for descriptor in model.optionDescriptors where descriptor.isReasoningControl {
            if case .select(let select) = descriptor, !select.options.isEmpty {
                let choices = select.options.map { ReasoningChoice(id: $0.id, label: $0.label) }
                let defaultId = select.currentValue
                    ?? select.options.first(where: { $0.isDefault == true })?.id
                    ?? select.options.first?.id
                return ExtractedReasoningControl(
                    optionId: select.id,
                    label: select.label,
                    choices: choices,
                    defaultChoiceId: defaultId
                )
            }
        }
        return nil
    }

    // MARK: - Projects

    static func projectRef(from project: ProjectShell) -> ProjectRef {
        let trimmedTitle = project.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackName = project.repositoryIdentity?.displayName
            ?? URL(fileURLWithPath: project.workspaceRoot).lastPathComponent
        let name = trimmedTitle.isEmpty ? fallbackName : trimmedTitle

        let initials: String?
        let iconTint: Int?
        switch project.projectIcon {
        case .monogram(let text, let color):
            let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
            initials = cleaned.isEmpty ? deriveInitials(from: name) : String(cleaned.prefix(2)).uppercased()
            iconTint = paletteIndex(forColorName: color)
        case .emoji(let emoji):
            let cleaned = emoji.trimmingCharacters(in: .whitespacesAndNewlines)
            initials = cleaned.isEmpty ? deriveInitials(from: name) : cleaned
            iconTint = nil
        case .lucide(_, let color):
            initials = deriveInitials(from: name)
            iconTint = paletteIndex(forColorName: color)
        case .unknown, nil:
            initials = deriveInitials(from: name)
            iconTint = nil
        }

        return ProjectRef(
            id: project.id,
            name: name,
            initials: initials,
            tint: iconTint ?? stableTintIndex(for: project.id),
            workspaceRoot: project.workspaceRoot
        )
    }

    static func deriveInitials(from name: String) -> String {
        let separators = CharacterSet.whitespacesAndNewlines.union(.init(charactersIn: "-_/.:"))
        let words = name.components(separatedBy: separators).filter { !$0.isEmpty }
        if words.count >= 2 {
            let first = words[0].prefix(1)
            let second = words[1].prefix(1)
            return "\(first)\(second)".uppercased()
        }
        let compact = words.first ?? name
        let trimmed = compact.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "PR" }
        return String(trimmed.prefix(2)).uppercased()
    }

    static func stableTintIndex(for key: String) -> Int {
        // FNV-1a 32-bit hash so project colors stay deterministic across launches.
        var hash: UInt32 = 2_166_136_261
        for byte in key.utf8 {
            hash ^= UInt32(byte)
            hash &*= 16_777_619
        }
        return Int(hash % 6)
    }

    private static func paletteIndex(forColorName name: String) -> Int? {
        switch name.lowercased() {
        case "violet", "purple", "indigo": return 0
        case "blue", "sky": return 1
        case "green", "emerald", "lime": return 2
        case "amber", "orange", "yellow": return 3
        case "rose", "pink", "red", "fuchsia": return 4
        case "teal", "cyan": return 5
        default: return nil
        }
    }

    // MARK: - Sidebar Threads

    static func threadSummary(
        from shell: ThreadShell,
        projectsByID: [String: ProjectShell],
        providersByID: [String: ServerProvider],
        hostName: String?,
        activelyViewingThreadID: String?
    ) -> ThreadSummary {
        let project = projectsByID[shell.projectId].map(projectRef(from:))
        let location: ThreadLocation?
        if let branch = shell.branch?.trimmingCharacters(in: .whitespacesAndNewlines), !branch.isEmpty {
            location = .branch(branch)
        } else if let hostName = hostName?.trimmingCharacters(in: .whitespacesAndNewlines), !hostName.isEmpty {
            location = .host(hostName)
        } else {
            location = nil
        }

        let provider = providersByID[shell.providerInstanceId]
        let kind = providerKind(
            driver: provider?.driver ?? shell.providerInstanceId,
            instanceId: shell.providerInstanceId
        )

        return ThreadSummary(
            id: shell.id,
            title: shell.title,
            project: project,
            location: location,
            provider: kind,
            providerDisplayName: provider?.label,
            activity: threadActivity(from: shell, activelyViewingThreadID: activelyViewingThreadID),
            updatedAt: shell.updatedAt
        )
    }

    static func threadActivity(
        from shell: ThreadShell,
        activelyViewingThreadID: String?
    ) -> ThreadActivity {
        if shell.needsApproval || shell.needsUserInput {
            return .needsApproval
        }
        let hasActiveBackgroundWork = shell.pendingBackgroundTasks.contains {
            $0.awaited == true || $0.kind == "subagent"
        }
        let activityStatusActive = shell.activityRunStatus.map { RunStatus(rawValue: $0).isActive } ?? false
        if activityStatusActive || shell.status.isActive || hasActiveBackgroundWork {
            return .running
        }
        if shell.status == .run(.failed)
            || (shell.lastError?.isEmpty == false && shell.status != .run(.completed) && shell.status != .idle)
        {
            return .failed
        }
        if shell.isUnread && shell.id != activelyViewingThreadID {
            return .unread
        }
        return .idle
    }

    // MARK: - Thread Transcript

    static func threadDetail(
        from projection: ThreadProjection,
        summary: ThreadSummary,
        optimisticApprovals: [String: ApprovalItem.Status] = [:]
    ) -> ThreadDetailState {
        var resolvedSummary = summary
        resolvedSummary.title = projection.thread.title
        if let branch = projection.thread.branch?.trimmingCharacters(in: .whitespacesAndNewlines), !branch.isEmpty {
            resolvedSummary.location = .branch(branch)
        }

        let requestsByID = Dictionary(
            uniqueKeysWithValues: projection.runtimeRequests.map { ($0.id, $0) }
        )

        var items: [TranscriptItem] = []
        var representedApprovalIDs: Set<String> = []
        var checkpointAdditions = 0
        var checkpointDeletions = 0
        var fileChangeAdditions = 0
        var fileChangeDeletions = 0

        for projected in projection.visibleTurnItems {
            let item = projected.item
            switch item.kind {
            case .checkpoint(_, _, let files):
                checkpointAdditions = files.reduce(0) { $0 + $1.additions }
                checkpointDeletions = files.reduce(0) { $0 + $1.deletions }
            case .fileChange(_, let additions, let deletions, _, _, _, _):
                fileChangeAdditions += additions ?? 0
                fileChangeDeletions += deletions ?? 0
            case .approvalRequest(let requestId, _, _, _, _, _, _):
                representedApprovalIDs.insert(requestId)
            default:
                break
            }

            if var mapped = transcriptItem(
                from: item,
                requestsByID: requestsByID,
                optimisticApprovals: optimisticApprovals
            ) {
                mapped.startedAt = item.startedAt ?? item.updatedAt
                mapped.completedAt = item.completedAt
                items.append(mapped)
            }
        }

        // Fallback: surface any pending approval RuntimeRequest not yet backed by a turn item.
        for request in projection.runtimeRequests where request.isPending && request.isApproval {
            guard !representedApprovalIDs.contains(request.id) else { continue }
            let status = optimisticApprovals[request.id] ?? .pending
            items.append(
                TranscriptItem(
                    id: "runtime-request-\(request.id)",
                    kind: .approval(
                        ApprovalItem(
                            requestId: request.id,
                            title: approvalTitle(explicitTitle: nil, requestKind: request.kind, appName: nil),
                            message: "The agent requested permission (\(request.kind)).",
                            command: nil,
                            status: status
                        )
                    )
                )
            )
        }

        let totalAdditions = checkpointAdditions > 0 || checkpointDeletions > 0
            ? checkpointAdditions
            : fileChangeAdditions
        let totalDeletions = checkpointAdditions > 0 || checkpointDeletions > 0
            ? checkpointDeletions
            : fileChangeDeletions
        let diffStat: String? = (totalAdditions > 0 || totalDeletions > 0)
            ? "+\(totalAdditions) −\(totalDeletions)"
            : nil

        return ThreadDetailState(
            summary: resolvedSummary,
            items: items,
            diffStat: diffStat,
            isRunning: projection.runs.contains { $0.status.isActive }
        )
    }

    static let workspacePreparationInput = "Preparing workspace"

    static func transcriptItem(
        from item: TurnItem,
        requestsByID: [String: RuntimeRequest],
        optimisticApprovals: [String: ApprovalItem.Status]
    ) -> TranscriptItem? {
        let status = toolStatus(from: item.status)
        let duration = itemDuration(item)

        switch item.kind {
        case .userMessage(_, let text, _, let attachments, _, _):
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return TranscriptItem(id: item.id, kind: .user(text))
            }
            if !attachments.isEmpty {
                let names = attachments.map(\.name).joined(separator: ", ")
                return TranscriptItem(id: item.id, kind: .user(names))
            }
            return nil

        case .assistantMessage(_, let text, let streaming, _, _, _):
            let blocks = MarkdownBlockParser.parse(text)
            if blocks.isEmpty {
                guard streaming else { return nil }
                return TranscriptItem(id: item.id, kind: .assistant(blocks: [.text("")], streaming: true))
            }
            return TranscriptItem(id: item.id, kind: .assistant(blocks: blocks, streaming: streaming))

        case .reasoning(let text, let streaming):
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty || streaming else { return nil }
            let preview = singleLinePreview(trimmed, fallback: "Thinking…")
            return TranscriptItem(
                id: item.id,
                kind: .toolCall(
                    ToolCallItem(
                        kind: .thinking,
                        title: streaming ? "Thinking" : "Thought",
                        detail: preview,
                        status: streaming ? .running : status,
                        duration: duration,
                        output: trimmed.isEmpty ? nil : trimmed
                    )
                )
            )

        case .proposedPlan(_, let markdown, let streaming):
            let blocks = MarkdownBlockParser.parse(markdown)
            guard !blocks.isEmpty || streaming else { return nil }
            return TranscriptItem(
                id: item.id,
                kind: .assistant(blocks: blocks.isEmpty ? [.text("")] : blocks, streaming: streaming)
            )

        case .todoList(_, let steps, let explanation):
            guard !steps.isEmpty else { return nil }
            let completed = steps.filter { $0.status == "completed" }.count
            let detail = explanation?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                ?? "\(completed)/\(steps.count) completed"
            let lines = steps.map { step -> String in
                let marker = step.status == "completed" ? "[x]" : (step.status == "in_progress" ? "[~]" : "[ ]")
                return "\(marker) \(step.text)"
            }.joined(separator: "\n")
            return TranscriptItem(
                id: item.id,
                kind: .toolCall(
                    ToolCallItem(
                        kind: .search,
                        title: item.title?.nilIfEmpty ?? "Plan",
                        detail: detail,
                        status: status,
                        duration: duration,
                        output: lines
                    )
                )
            )

        case .commandExecution(let input, let output, let outputOmitted, let outputIndicatesFailure, let exitCode, _):
            let failed = outputIndicatesFailure == true || (exitCode != nil && exitCode != 0)
            // Server-side workspace setup is not an agent action; only surface it if it failed (matches the web client).
            if input == workspacePreparationInput && !failed { return nil }
            let resolvedStatus: ToolCallItem.Status
            if status == .running {
                resolvedStatus = .running
            } else if failed {
                resolvedStatus = .failed
            } else {
                resolvedStatus = status
            }
            let renderedOutput = output?.nilIfEmpty ?? (outputOmitted ? "(Output omitted)" : nil)
            return TranscriptItem(
                id: item.id,
                kind: .toolCall(
                    ToolCallItem(
                        kind: .command,
                        title: resolvedStatus == .running ? "Running" : "Ran",
                        detail: singleLinePreview(input, fallback: item.title ?? "command"),
                        status: resolvedStatus,
                        duration: duration,
                        output: renderedOutput
                    )
                )
            )

        case .fileChange(let fileName, let additions, let deletions, let diffStr, let oldStr, let newStr, let changes):
            let target = fileName.nilIfEmpty
                ?? changes?.map(\.path).joined(separator: ", ").nilIfEmpty
                ?? item.title
                ?? "file"
            var detail = target
            if let adds = additions, let dels = deletions, (adds > 0 || dels > 0) {
                detail = "\(target) (+\(adds) −\(dels))"
            }
            let output: String?
            if let diff = diffStr?.nilIfEmpty {
                output = diff
            } else if oldStr != nil || newStr != nil {
                var parts: [String] = []
                if let oldStr, !oldStr.isEmpty { parts.append("--- before\n\(oldStr)") }
                if let newStr, !newStr.isEmpty { parts.append("+++ after\n\(newStr)") }
                output = parts.isEmpty ? nil : parts.joined(separator: "\n")
            } else {
                output = nil
            }
            return TranscriptItem(
                id: item.id,
                kind: .toolCall(
                    ToolCallItem(
                        kind: .edit,
                        title: status == .running ? "Editing" : "Edited",
                        detail: detail,
                        status: status,
                        duration: duration,
                        output: output
                    )
                )
            )

        case .fileSearch(let pattern, let results):
            let detail = pattern?.nilIfEmpty ?? item.title ?? "files"
            let output = results.flatMap { list -> String? in
                guard !list.isEmpty else { return nil }
                return list.map { hit in
                    let location = hit.line.map { "\(hit.fileName):\($0)" } ?? hit.fileName
                    if let preview = hit.preview?.trimmingCharacters(in: .whitespacesAndNewlines), !preview.isEmpty {
                        return "\(location)  \(preview)"
                    }
                    return location
                }.joined(separator: "\n")
            }
            return TranscriptItem(
                id: item.id,
                kind: .toolCall(
                    ToolCallItem(
                        kind: .search,
                        title: status == .running ? "Searching" : "Searched",
                        detail: detail,
                        status: status,
                        duration: duration,
                        output: output
                    )
                )
            )

        case .webSearch(let patterns, let results):
            let detail = patterns?.joined(separator: ", ").nilIfEmpty ?? item.title ?? "web"
            let output = results.flatMap { list -> String? in
                guard !list.isEmpty else { return nil }
                return list.compactMap { hit in
                    let parts = [hit.title, hit.url, hit.snippet].compactMap { $0?.nilIfEmpty }
                    return parts.isEmpty ? nil : parts.joined(separator: " — ")
                }.joined(separator: "\n")
            }
            return TranscriptItem(
                id: item.id,
                kind: .toolCall(
                    ToolCallItem(
                        kind: .search,
                        title: status == .running ? "Searching web" : "Searched web",
                        detail: detail,
                        status: status,
                        duration: duration,
                        output: output
                    )
                )
            )

        case .dynamicTool(let toolName, let viewedImagePath, let input, let output, let outputOmitted):
            let (kind, verb) = classifyDynamicTool(toolName: toolName, explicitTitle: item.title, isRunning: status == .running)
            let detail = viewedImagePath?.nilIfEmpty
                ?? summarizeToolInput(input)
                ?? toolName
                ?? ""
            let renderedOutput = formatJSONValue(output)?.nilIfEmpty ?? (outputOmitted ? "(Output omitted)" : nil)
            return TranscriptItem(
                id: item.id,
                kind: .toolCall(
                    ToolCallItem(
                        kind: kind,
                        title: verb,
                        detail: singleLinePreview(detail, fallback: toolName ?? "tool"),
                        status: status,
                        duration: duration,
                        output: renderedOutput
                    )
                )
            )

        case .approvalRequest(let requestId, let requestKind, let prompt, let reason, _, let appName, _):
            let request = requestsByID[requestId]
            let approvalStatus = resolveApprovalStatus(
                requestId: requestId,
                request: request,
                itemStatus: item.status,
                optimisticApprovals: optimisticApprovals
            )
            let title = approvalTitle(explicitTitle: item.title, requestKind: requestKind, appName: appName)
            let command: String?
            let message: String
            if requestKind == "command" {
                command = prompt?.nilIfEmpty
                message = reason?.nilIfEmpty ?? "Allow the agent to run this command?"
            } else {
                command = nil
                let parts = [reason?.nilIfEmpty, prompt?.nilIfEmpty].compactMap { $0 }
                message = parts.isEmpty ? "Allow this \(requestKind) request?" : parts.joined(separator: "\n")
            }
            return TranscriptItem(
                id: item.id,
                kind: .approval(
                    ApprovalItem(
                        requestId: requestId,
                        title: title,
                        message: message,
                        command: command,
                        status: approvalStatus
                    )
                )
            )

        case .userInputRequest(_, let questions, _):
            let summary = questions.map(\.question).joined(separator: "\n")
            guard !summary.isEmpty else { return nil }
            return TranscriptItem(
                id: item.id,
                kind: .notice(title: item.title?.nilIfEmpty ?? "Question", message: summary, isError: false)
            )

        case .subagent(_, _, _, let providerInstanceId, _, let prompt, let progress, let result):
            let output = result?.nilIfEmpty ?? progress?.nilIfEmpty
            return TranscriptItem(
                id: item.id,
                kind: .toolCall(
                    ToolCallItem(
                        kind: .search,
                        title: item.title?.nilIfEmpty ?? "Subagent (\(providerInstanceId))",
                        detail: singleLinePreview(prompt, fallback: "Subagent task"),
                        status: status,
                        duration: duration,
                        output: output
                    )
                )
            )

        case .error(let failure):
            let title = failure.failureClass == "usage_limit"
                ? "Usage limit reached"
                : (item.title?.nilIfEmpty ?? "Provider error")
            return TranscriptItem(
                id: item.id,
                kind: .notice(title: title, message: failure.message, isError: true)
            )

        case .systemNotice(let message, let level):
            guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return TranscriptItem(
                id: item.id,
                kind: .notice(
                    title: item.title?.nilIfEmpty ?? "Notice",
                    message: message,
                    isError: level == "error"
                )
            )

        case .runInterruptResult(let message):
            guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return TranscriptItem(
                id: item.id,
                kind: .notice(title: "Stopped", message: message, isError: false)
            )

        case .notification(let outcome, let summary, let detail):
            let body = [summary.nilIfEmpty, detail?.nilIfEmpty].compactMap { $0 }.joined(separator: "\n")
            guard !body.isEmpty else { return nil }
            return TranscriptItem(
                id: item.id,
                kind: .notice(title: item.title?.nilIfEmpty ?? "Update", message: body, isError: outcome == "error")
            )

        case .checkpoint, .runInterruptRequest, .compaction, .handoff, .fork,
             .threadCreated, .secretRequest, .linkRequest, .unknown:
            return nil
        }
    }

    private static func toolStatus(from raw: String) -> ToolCallItem.Status {
        switch raw {
        case "pending", "running", "waiting":
            return .running
        case "failed", "cancelled", "interrupted":
            return .failed
        default:
            return .succeeded
        }
    }

    private static func itemDuration(_ item: TurnItem) -> TimeInterval? {
        guard let start = item.startedAt, let end = item.completedAt else { return nil }
        return max(0, end.timeIntervalSince(start))
    }

    private static func resolveApprovalStatus(
        requestId: String,
        request: RuntimeRequest?,
        itemStatus: String,
        optimisticApprovals: [String: ApprovalItem.Status]
    ) -> ApprovalItem.Status {
        if let request {
            if request.isPending {
                return optimisticApprovals[requestId] ?? .pending
            }
            switch request.decision {
            case .accept, .acceptForSession, .acceptAlways:
                return .approved
            case .decline, .cancel:
                return .denied
            case nil:
                return request.status == "resolved" ? .approved : .denied
            }
        }
        if itemStatus == "waiting" || itemStatus == "pending" || itemStatus == "running" {
            return optimisticApprovals[requestId] ?? .pending
        }
        return itemStatus == "completed" ? .approved : .denied
    }

    private static func approvalTitle(explicitTitle: String?, requestKind: String, appName: String?) -> String {
        if let explicitTitle = explicitTitle?.nilIfEmpty {
            return explicitTitle
        }
        switch requestKind {
        case "command": return "Run command?"
        case "file-change": return "Allow file change?"
        case "file-read": return "Allow file read?"
        case "mcp-elicitation": return appName.map { "\($0) request" } ?? "Allow tool request?"
        default: return "Approval required"
        }
    }

    private static func classifyDynamicTool(
        toolName: String?,
        explicitTitle: String?,
        isRunning: Bool
    ) -> (ToolCallItem.Kind, String) {
        let lower = (toolName ?? explicitTitle ?? "").lowercased()
        if lower.contains("read") || lower.contains("view") || lower.contains("cat") || lower.contains("open") {
            return (.read, isRunning ? "Reading" : "Read")
        }
        if lower.contains("edit") || lower.contains("write") || lower.contains("patch") || lower.contains("replace") {
            return (.edit, isRunning ? "Editing" : "Edited")
        }
        if lower.contains("search") || lower.contains("grep") || lower.contains("glob") || lower.contains("find") || lower.contains("list") {
            return (.search, isRunning ? "Searching" : "Searched")
        }
        if lower.contains("bash") || lower.contains("shell") || lower.contains("exec") || lower.contains("command") || lower.contains("run") {
            return (.command, isRunning ? "Running" : "Ran")
        }
        return (.command, explicitTitle?.nilIfEmpty ?? toolName?.nilIfEmpty ?? "Tool")
    }

    private static func summarizeToolInput(_ input: JSONValue?) -> String? {
        guard let input else { return nil }
        switch input {
        case .string(let s):
            return s.nilIfEmpty
        case .object(let dict):
            let preferredKeys = ["command", "cmd", "file_path", "path", "filePath", "pattern", "query", "url", "prompt"]
            for key in preferredKeys {
                if let value = dict[key]?.stringValue?.nilIfEmpty {
                    return value
                }
            }
            return formatJSONValue(input)
        default:
            return formatJSONValue(input)
        }
    }

    private static func formatJSONValue(_ value: JSONValue?) -> String? {
        guard let value, value != .null else { return nil }
        if case .string(let s) = value { return s }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func singleLinePreview(_ text: String, fallback: String) -> String {
        let collapsed = text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first(where: { !$0.isEmpty })
        return collapsed ?? fallback
    }
}

// MARK: - Markdown Block Parser

/// Splits assistant markdown text into prose and fenced code blocks (supporting streaming unclosed fences).
enum MarkdownBlockParser {
    static func parse(_ markdown: String) -> [MessageBlock] {
        guard !markdown.isEmpty else { return [] }

        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var blocks: [MessageBlock] = []
        var proseLines: [String] = []
        var codeLines: [String] = []
        var openFenceChar: Character?
        var openFenceLength = 0
        var openFenceLanguage: String?

        func flushProse() {
            let joined = proseLines.joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            proseLines.removeAll(keepingCapacity: true)
            if !joined.isEmpty {
                blocks.append(.text(joined))
            }
        }

        for line in lines {
            if let fenceChar = openFenceChar {
                if isClosingFence(line: line, char: fenceChar, minLength: openFenceLength) {
                    blocks.append(.code(language: openFenceLanguage, source: codeLines.joined(separator: "\n")))
                    codeLines.removeAll(keepingCapacity: true)
                    openFenceChar = nil
                    openFenceLength = 0
                    openFenceLanguage = nil
                } else {
                    codeLines.append(line)
                }
            } else if let opening = parseOpeningFence(line: line) {
                flushProse()
                openFenceChar = opening.char
                openFenceLength = opening.length
                openFenceLanguage = opening.language
            } else {
                proseLines.append(line)
            }
        }

        if openFenceChar != nil {
            // Preserve partial code blocks mid-stream instead of dumping raw backticks as prose.
            blocks.append(.code(language: openFenceLanguage, source: codeLines.joined(separator: "\n")))
        } else {
            flushProse()
        }

        return blocks
    }

    private struct FenceOpening {
        let char: Character
        let length: Int
        let language: String?
    }

    private static func parseOpeningFence(line: String) -> FenceOpening? {
        let trimmedLeading = line.drop(while: { $0 == " " })
        let leadingSpaces = line.count - trimmedLeading.count
        guard leadingSpaces <= 3, let first = trimmedLeading.first, first == "`" || first == "~" else {
            return nil
        }
        let fenceRun = trimmedLeading.prefix(while: { $0 == first })
        guard fenceRun.count >= 3 else { return nil }
        let rest = String(trimmedLeading.dropFirst(fenceRun.count)).trimmingCharacters(in: .whitespaces)
        // CommonMark: backtick info strings cannot contain backticks (prevents matching inline ```code```).
        if first == "`" && rest.contains("`") {
            return nil
        }
        let language = rest.split(whereSeparator: \.isWhitespace).first.map(String.init)?.nilIfEmpty
        return FenceOpening(char: first, length: fenceRun.count, language: language)
    }

    private static func isClosingFence(line: String, char: Character, minLength: Int) -> Bool {
        let trimmedLeading = line.drop(while: { $0 == " " })
        let leadingSpaces = line.count - trimmedLeading.count
        guard leadingSpaces <= 3 else { return false }
        let fenceRun = trimmedLeading.prefix(while: { $0 == char })
        guard fenceRun.count >= minLength else { return false }
        return trimmedLeading.dropFirst(fenceRun.count).allSatisfy { $0 == " " || $0 == "\t" }
    }
}

// MARK: - Throttled Thread Visit Policy

/// Pure decision helper mirroring `packages/client-runtime/src/state/threadVisits.ts` (10s throttle while streaming).
struct ThreadVisitPolicy {
    static let throttleInterval: TimeInterval = 10

    enum Action: Equatable {
        case none
        case dispatchNow(visitedAt: Date, opened: Bool)
        case deferBy(TimeInterval, visitedAt: Date)
    }

    private(set) var threadId: String?
    private var openPending = false
    private var lastDispatchedUpdatedAt: Date?
    private var lastDispatchAt: Date?

    mutating func selectThread(_ newThreadId: String?) {
        guard threadId != newThreadId else { return }
        threadId = newThreadId
        openPending = newThreadId != nil
        lastDispatchedUpdatedAt = nil
        lastDispatchAt = nil
    }

    mutating func evaluate(
        threadId: String,
        updatedAt: Date,
        lastVisitedAt: Date?,
        latestRunCompletedAt: Date?,
        now: Date = Date()
    ) -> Action {
        guard self.threadId == threadId else { return .none }

        if openPending {
            openPending = false
            lastDispatchedUpdatedAt = updatedAt
            lastDispatchAt = now
            return .dispatchNow(visitedAt: updatedAt, opened: true)
        }

        if let lastVisitedAt, lastVisitedAt >= updatedAt {
            if lastDispatchedUpdatedAt == nil || lastDispatchedUpdatedAt! < updatedAt {
                lastDispatchedUpdatedAt = updatedAt
            }
            return .none
        }

        if let lastDispatchedUpdatedAt, lastDispatchedUpdatedAt >= updatedAt {
            return .none
        }

        let hasUnseenCompletion: Bool = {
            guard let completedAt = latestRunCompletedAt else { return false }
            guard let lastVisitedAt else { return true }
            return completedAt > lastVisitedAt
        }()

        let elapsed = lastDispatchAt.map { now.timeIntervalSince($0) } ?? Self.throttleInterval
        if hasUnseenCompletion || elapsed >= Self.throttleInterval {
            lastDispatchedUpdatedAt = updatedAt
            lastDispatchAt = now
            return .dispatchNow(visitedAt: updatedAt, opened: false)
        }

        let remaining = max(0.05, Self.throttleInterval - elapsed)
        return .deferBy(remaining, visitedAt: updatedAt)
    }

    mutating func markDeferredDispatched(visitedAt: Date, now: Date = Date()) {
        if lastDispatchedUpdatedAt == nil || lastDispatchedUpdatedAt! < visitedAt {
            lastDispatchedUpdatedAt = visitedAt
        }
        lastDispatchAt = now
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
