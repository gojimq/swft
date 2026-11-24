import SwftDesign
import SwftKit
import SwiftUI

struct GeneralSettingsSection: View {
    @Environment(AppModel.self) private var model

    private var settings: SettingsController { model.settings }
    private var server: ServerSettings { settings.serverSettings ?? ServerSettings() }
    private var serverDisabled: Bool { !settings.isServerConnected }

    private var availableModels: [ModelOption] { model.availableModels }

    private var effectiveDefaultModel: ModelOption? {
        if let configured = server.defaultModelSelection {
            return availableModels.first(where: {
                $0.instanceId == configured.instanceId && $0.slug == configured.model
            })
        }
        return SwftAdapters.preferredDefaultModel(from: availableModels)
    }

    private var effectiveReasoningChoiceID: String? {
        guard let option = effectiveDefaultModel else { return nil }
        if let configured = server.defaultModelSelection {
            return SwftAdapters.reasoningChoiceId(from: configured, for: option)
        }
        return option.defaultReasoningChoiceId ?? option.reasoningChoices.first?.id
    }

    var body: some View {
        @Bindable var controller = model.settings

        VStack(alignment: .leading, spacing: 20) {
            if let reason = settings.readOnlyReason {
                SettingsBanner(reason, tone: .info)
            }

            SettingsSectionCard("Appearance") {
                SettingsRow(
                    "Theme",
                    description: "Light, dark, or match your macOS system setting.",
                    isModified: controller.appearance != .system,
                    onReset: { controller.appearance = .system }
                ) {
                    SettingsSegmentedControl(
                        selection: $controller.appearance,
                        options: AppearancePreference.allCases.map {
                            SettingsChoiceOption(value: $0, label: $0.label)
                        }
                    )
                }
            }

            SettingsSectionCard("New threads") {
                defaultModelRow

                if let effectiveDefaultModel, effectiveDefaultModel.reasoningChoices.count > 1 {
                    SettingsRowDivider()
                    defaultThinkingRow(for: effectiveDefaultModel)
                }

                SettingsRowDivider()

                SettingsPickerRow(
                    "Permissions",
                    description: SettingsValuePresentation.description(for: server.defaultRuntimeMode),
                    selection: server.defaultRuntimeMode,
                    options: RuntimeMode.allCases.map {
                        SettingsChoiceOption(
                            value: $0,
                            label: SettingsValuePresentation.label(for: $0),
                            detail: SettingsValuePresentation.description(for: $0)
                        )
                    },
                    disabled: serverDisabled,
                    isModified: server.defaultRuntimeMode != .fullAccess,
                    onReset: { settings.setDefaultRuntimeMode(.fullAccess) }
                ) { next in
                    settings.setDefaultRuntimeMode(next)
                }

                SettingsRowDivider()

                SettingsRow(
                    "Workspace",
                    description: "Start new threads in the current checkout or an isolated git worktree.",
                    isModified: server.defaultThreadEnvMode != nil,
                    onReset: { settings.setDefaultThreadEnvMode(nil) }
                ) {
                    SettingsSegmentedControl(
                        selection: Binding(
                            get: { server.defaultThreadEnvMode ?? .local },
                            set: { settings.setDefaultThreadEnvMode($0) }
                        ),
                        options: ThreadEnvMode.allCases.map {
                            SettingsChoiceOption(value: $0, label: SettingsValuePresentation.label(for: $0))
                        },
                        disabled: serverDisabled
                    )
                }
            }

            SettingsSectionCard("Server behavior") {
                SettingsPickerRow(
                    "Response streaming",
                    description: SettingsValuePresentation.description(for: server.responseStreamingMode),
                    selection: server.responseStreamingMode,
                    options: ResponseStreamingMode.allCases.map {
                        SettingsChoiceOption(value: $0, label: SettingsValuePresentation.label(for: $0))
                    },
                    disabled: serverDisabled,
                    isModified: server.responseStreamingMode != .paragraph,
                    onReset: { settings.setResponseStreamingMode(.paragraph) }
                ) { next in
                    settings.setResponseStreamingMode(next)
                }

                SettingsRowDivider()

                SettingsToggleRow(
                    "Keep awake while agents work",
                    description: "Prevent this Mac from sleeping while an agent run is active.",
                    isOn: Binding(
                        get: { server.keepAwakeWhileAgentsWork },
                        set: { settings.setKeepAwake($0) }
                    ),
                    disabled: serverDisabled
                )

                SettingsRowDivider()

                SettingsToggleRow(
                    "Continue threads after restarts",
                    description: "Automatically resume interrupted runs after a server restart or update.",
                    isOn: Binding(
                        get: { server.continueThreadsAfterServerUpdate },
                        set: { settings.setContinueAfterRestart($0) }
                    ),
                    disabled: serverDisabled
                )

                SettingsRowDivider()

                SettingsToggleRow(
                    "Auto-settle merged threads",
                    description: "Mark a thread settled when its pull request is merged.",
                    isOn: Binding(
                        get: { server.sidebarAutoSettleOnMerge },
                        set: { settings.setAutoSettleOnMerge($0) }
                    ),
                    disabled: serverDisabled
                )
            }
        }
    }

    private var defaultModelRow: some View {
        let isAutomatic = server.defaultModelSelection == nil
        let triggerLabel: String = {
            if let configured = server.defaultModelSelection {
                if let matched = effectiveDefaultModel {
                    return "\(matched.providerDisplayName) · \(matched.name)"
                }
                return "\(configured.instanceId) · \(configured.model)"
            }
            if let auto = effectiveDefaultModel {
                return "Automatic (\(auto.name))"
            }
            return availableModels.isEmpty ? "No models available" : "Automatic"
        }()

        let grouped = groupedModelsByInstance()

        return SettingsRow(
            "Default model",
            description: isAutomatic
                ? "Model for new threads, chosen automatically from ready providers."
                : "Model for new threads. Projects can still override it.",
            isModified: !isAutomatic,
            onReset: { settings.setDefaultModelSelection(nil) }
        ) {
            if availableModels.isEmpty {
                Text(settings.isServerConnected ? "No models available" : "Offline")
                    .font(SwftType.caption)
                    .foregroundStyle(SwftColor.textTertiary)
            } else {
                Menu {
                    Button {
                        settings.setDefaultModelSelection(nil)
                    } label: {
                        Text(isAutomatic ? "✓ Automatic" : "Automatic")
                    }
                    Divider()
                    ForEach(grouped, id: \.instanceId) { group in
                        Section(group.providerLabel) {
                            ForEach(group.models) { option in
                                let isCurrent = server.defaultModelSelection?.instanceId == option.instanceId
                                    && server.defaultModelSelection?.model == option.slug
                                Button {
                                    let selection = SwftAdapters.modelSelection(
                                        from: option,
                                        reasoningChoiceId: option.defaultReasoningChoiceId
                                    )
                                    settings.setDefaultModelSelection(selection)
                                } label: {
                                    Text(isCurrent ? "✓ \(option.name)" : option.name)
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 7) {
                        if let effectiveDefaultModel {
                            ProviderGlyph(
                                symbol: effectiveDefaultModel.provider.symbol,
                                tint: effectiveDefaultModel.provider.tint,
                                name: effectiveDefaultModel.providerDisplayName
                            )
                        }
                        Text(triggerLabel)
                            .font(SwftType.label)
                            .foregroundStyle(SwftColor.textPrimary)
                            .lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(SwftColor.textTertiary)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(SwftColor.surface))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(SwftColor.borderSubtle))
                    .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .disabled(serverDisabled)
                .fixedSize()
            }
        }
    }

    private func defaultThinkingRow(for option: ModelOption) -> some View {
        let currentID = effectiveReasoningChoiceID ?? option.defaultReasoningChoiceId ?? option.reasoningChoices.first?.id ?? ""
        return SettingsRow(
            "Thinking level",
            description: "Default reasoning effort for \(option.name).",
            isModified: server.defaultModelSelection != nil && currentID != option.defaultReasoningChoiceId,
            onReset: {
                let selection = SwftAdapters.modelSelection(
                    from: option,
                    reasoningChoiceId: option.defaultReasoningChoiceId
                )
                settings.setDefaultModelSelection(selection)
            }
        ) {
            if option.reasoningChoices.count <= 4 {
                SettingsSegmentedControl(
                    selection: Binding(
                        get: { currentID },
                        set: { next in
                            let selection = SwftAdapters.modelSelection(from: option, reasoningChoiceId: next)
                            settings.setDefaultModelSelection(selection)
                        }
                    ),
                    options: option.reasoningChoices.map {
                        SettingsChoiceOption(value: $0.id, label: $0.label)
                    },
                    disabled: serverDisabled
                )
            } else {
                Menu {
                    ForEach(option.reasoningChoices) { choice in
                        Button {
                            let selection = SwftAdapters.modelSelection(from: option, reasoningChoiceId: choice.id)
                            settings.setDefaultModelSelection(selection)
                        } label: {
                            Text(choice.id == currentID ? "✓ \(choice.label)" : choice.label)
                        }
                    }
                } label: {
                    let label = option.reasoningChoices.first(where: { $0.id == currentID })?.label ?? currentID
                    SettingsMenuTrigger(label, disabled: serverDisabled)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .disabled(serverDisabled)
                .fixedSize()
            }
        }
    }

    private struct ModelGroup {
        let instanceId: String
        let providerLabel: String
        let models: [ModelOption]
    }

    private func groupedModelsByInstance() -> [ModelGroup] {
        var order: [String] = []
        var buckets: [String: [ModelOption]] = [:]
        for option in availableModels {
            if buckets[option.instanceId] == nil {
                order.append(option.instanceId)
            }
            buckets[option.instanceId, default: []].append(option)
        }
        return order.compactMap { id in
            guard let items = buckets[id], let first = items.first else { return nil }
            return ModelGroup(instanceId: id, providerLabel: first.providerDisplayName, models: items)
        }
    }
}
