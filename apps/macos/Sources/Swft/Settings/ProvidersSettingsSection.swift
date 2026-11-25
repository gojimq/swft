import SwftDesign
import SwftKit
import SwiftUI

struct ProvidersSettingsSection: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingAddAccount = false
    @State private var pendingRemoval: ProviderEntry?

    private var settings: SettingsController { model.settings }
    private var entries: [ProviderEntry] { settings.providerEntries }
    private var server: ServerSettings { settings.serverSettings ?? ServerSettings() }
    private var serverDisabled: Bool { !settings.isServerConnected }

    private var enabledCount: Int {
        entries.filter(\.enabled).count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let reason = settings.readOnlyReason {
                SettingsBanner(reason, tone: .info)
            }

            SettingsSectionCard(
                entries.isEmpty ? "Providers" : "Providers · \(enabledCount) of \(entries.count) enabled",
                headerAccessory: {
                    HStack(spacing: 6) {
                        SettingsPillButton(
                            "Add account",
                            systemName: "plus",
                            variant: .primary,
                            disabled: serverDisabled
                        ) {
                            showingAddAccount = true
                        }
                        SettingsPillButton(
                            "Check again",
                            systemName: "arrow.clockwise",
                            variant: .secondary,
                            isLoading: settings.isRefreshingProviders,
                            disabled: serverDisabled
                        ) {
                            settings.refreshProviders()
                        }
                    }
                }
            ) {
                if entries.isEmpty {
                    Text(settings.isServerConnected ? "No providers reported by the server." : "Connect to the local server to view providers.")
                        .font(SwftType.label)
                        .foregroundStyle(SwftColor.textTertiary)
                        .padding(18)
                } else {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        if index > 0 {
                            SettingsRowDivider()
                        }
                        ProviderSettingsRowView(
                            provider: entry,
                            isExpanded: settings.expandedProviderID == entry.id,
                            disabled: serverDisabled,
                            onToggleExpand: {
                                withAnimation(SwftMotion.resolve(SwftMotion.disclosure, reduceMotion: reduceMotion)) {
                                    settings.toggleExpandedProvider(entry.id)
                                }
                            },
                            onRequestRemove: {
                                pendingRemoval = entry
                            }
                        )
                    }
                }
            }

            UsagePillsSettingsSection()

            SettingsSectionCard("Advanced") {
                SettingsPickerRow(
                    "Compact idle threads",
                    description: "When to compact an idle Claude thread over 200,000 tokens.",
                    selection: server.effectiveIdleCompaction,
                    options: IdleCompactionMode.allCases.map {
                        SettingsChoiceOption(value: $0, label: SettingsValuePresentation.label(for: $0))
                    },
                    disabled: serverDisabled,
                    isModified: server.effectiveIdleCompaction != .onReturn,
                    onReset: { settings.setIdleCompaction(.onReturn) }
                ) { next in
                    settings.setIdleCompaction(next)
                }
            }
        }
        .sheet(isPresented: $showingAddAccount) {
            AddAccountSheet(
                existingIDs: Set(entries.map(\.id)),
                onClose: { showingAddAccount = false }
            )
            .environment(model)
        }
        .confirmationDialog(
            "Remove provider",
            isPresented: Binding(
                get: { pendingRemoval != nil },
                set: { if !$0 { pendingRemoval = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let target = pendingRemoval {
                Button("Remove \(target.label)", role: .destructive) {
                    settings.removeProviderAccount(target.id)
                    pendingRemoval = nil
                }
            }
            Button("Cancel", role: .cancel) {
                pendingRemoval = nil
            }
        } message: {
            if let target = pendingRemoval {
                Text("Remove “\(target.label)”? Its saved settings will be removed. Existing threads remain untouched.")
            }
        }
    }
}

// MARK: - Single Expandable Provider Row

private struct ProviderSettingsRowView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let provider: ProviderEntry
    let isExpanded: Bool
    let disabled: Bool
    let onToggleExpand: () -> Void
    let onRequestRemove: () -> Void

    @State private var hoveringHeader = false
    @State private var rejectedFields: [String: String] = [:]

    private var settings: SettingsController { model.settings }
    private var status: ProviderStatusDisplay { ProviderSettingsLogic.deriveProviderStatus(provider) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerRow

            SwftDisclosure(isExpanded: isExpanded) {
                expandedContent
            }
        }
    }

    private var headerRow: some View {
        HStack(alignment: .center, spacing: 12) {
            Button(action: onToggleExpand) {
                HStack(alignment: .center, spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(SwftColor.surface)
                            .overlay(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .strokeBorder(SwftColor.borderSubtle)
                            )
                        ProviderGlyph(
                            symbol: provider.kind.symbol,
                            tint: provider.enabled ? provider.kind.tint : SwftColor.textTertiary,
                            name: provider.label
                        )
                    }
                    .frame(width: 30, height: 30)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            if let hex = provider.accentColor, let color = Color(swftHex: hex) {
                                AccentDot(color)
                            }
                            Text(provider.label)
                                .font(SwftType.labelStrong)
                                .foregroundStyle(provider.enabled ? SwftColor.textPrimary : SwftColor.textTertiary)
                                .lineLimit(1)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundStyle(SwftColor.textTertiary)
                                .rotationEffect(.degrees(isExpanded ? 180 : 0))
                                .animation(SwftMotion.resolve(SwftMotion.disclosure, reduceMotion: reduceMotion), value: isExpanded)
                        }

                        HStack(spacing: 5) {
                            statusIndicator
                            if let version = status.version {
                                Text(version)
                                    .font(SwftType.monoSmall)
                                    .foregroundStyle(SwftColor.textTertiary)
                                Text("·")
                                    .font(SwftType.caption)
                                    .foregroundStyle(SwftColor.textTertiary)
                            }
                            Text(status.text)
                                .font(SwftType.caption)
                                .foregroundStyle(status.tone == .error ? SwftColor.danger : SwftColor.textSecondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 8)
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 6)
                .background(
                    RoundedRectangle(cornerRadius: SwftRadius.m, style: .continuous)
                        .fill(hoveringHeader ? SwftColor.hover : .clear)
                )
                .contentShape(RoundedRectangle(cornerRadius: SwftRadius.m, style: .continuous))
            }
            .buttonStyle(.plain)
            .onHover { hoveringHeader = $0 }
            .animation(SwftMotion.resolve(SwftMotion.quick, reduceMotion: reduceMotion), value: hoveringHeader)

            SettingsToggle(
                isOn: Binding(
                    get: { provider.enabled },
                    set: { settings.setProviderEnabled(provider.id, enabled: $0) }
                ),
                label: "Enable \(provider.label)",
                disabled: disabled
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch status.tone {
        case .working:
            ProgressView()
                .controlSize(.mini)
                .frame(width: 10, height: 10)
        case .ready:
            Circle().fill(SwftColor.success).frame(width: 6, height: 6)
        case .warning:
            Circle().fill(SwftColor.warning).frame(width: 6, height: 6)
        case .error:
            Circle().fill(SwftColor.danger).frame(width: 6, height: 6)
        case .neutral:
            Circle().fill(SwftColor.textTertiary.opacity(0.45)).frame(width: 6, height: 6)
        }
    }

    private var expandedContent: some View {
        let dedicatedEnvNames = Set(provider.environmentFields.map(\.name))

        return VStack(alignment: .leading, spacing: 14) {
            if status.truncatedMessage, let fullMessage = provider.message {
                Text(fullMessage)
                    .font(SwftType.caption)
                    .foregroundStyle(SwftColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }

            if provider.supportsInstall || provider.supportsAuth {
                ProviderSetupControlsView(provider: provider, disabled: disabled)
            }

            if provider.driver == "cursor" && provider.setup?.canAuthenticate == false {
                Text("Using CURSOR_API_KEY. Clear it from Environment variables to use browser sign-in.")
                    .font(SwftType.caption)
                    .foregroundStyle(SwftColor.textSecondary)
            }

            if provider.driver == "claudeAgent",
               provider.auth.status != .authenticated,
               let homePath = provider.config?["homePath"]?.stringValue,
               !homePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Sign in via CLI")
                        .font(SwftType.captionStrong)
                        .foregroundStyle(SwftColor.textPrimary)
                    Text("Run this command in Terminal on this Mac, then click Check again.")
                        .font(SwftType.caption)
                        .foregroundStyle(SwftColor.textSecondary)
                    SettingsCopyableCode(
                        ProviderSettingsLogic.claudeLoginCommand(homePath: homePath),
                        copyLabel: "Copy command"
                    )
                }
            }

            // Identity: Display name & Accent color
            VStack(alignment: .leading, spacing: 10) {
                inlineFieldRow(
                    title: "Display name",
                    description: nil
                ) {
                    SettingsCommitField(
                        value: provider.displayName,
                        placeholder: provider.defaultLabel,
                        disabled: disabled
                    ) { next in
                        settings.updateProviderDisplayName(provider.id, displayName: next)
                    }
                    .frame(width: 240)
                }

                inlineFieldRow(
                    title: "Accent color",
                    description: "Shown in the model picker to distinguish accounts."
                ) {
                    AccentSwatchPicker(
                        selectedHex: provider.accentColor,
                        disabled: disabled
                    ) { next in
                        settings.updateProviderAccentColor(provider.id, accentColor: next)
                    }
                }
            }

            // Per-provider schema fields
            if provider.unknownDriver {
                Text("This provider uses driver “\(provider.driver)”, which has no configurable options in this build.")
                    .font(SwftType.caption)
                    .foregroundStyle(SwftColor.textTertiary)
            } else {
                if !provider.fields.isEmpty {
                    Divider().overlay(SwftColor.borderSubtle)
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(provider.fields) { field in
                            providerSchemaFieldRow(field)
                        }
                    }
                }

                if !provider.environmentFields.isEmpty {
                    Divider().overlay(SwftColor.borderSubtle)
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(provider.environmentFields) { field in
                            dedicatedEnvFieldRow(field)
                        }
                    }
                }

                Divider().overlay(SwftColor.borderSubtle)
                ProviderEnvironmentVariablesEditor(
                    provider: provider,
                    dedicatedNames: dedicatedEnvNames,
                    disabled: disabled
                )
            }

            Divider().overlay(SwftColor.borderSubtle)
            ProviderModelsEditor(provider: provider, disabled: disabled)

            if !provider.isDefault {
                Divider().overlay(SwftColor.borderSubtle)
                HStack {
                    SettingsPillButton(
                        "Remove account",
                        systemName: "trash",
                        variant: .destructive,
                        disabled: disabled,
                        action: onRequestRemove
                    )
                    Spacer()
                }
            }
        }
        .padding(.leading, 56)
        .padding(.trailing, 18)
        .padding(.top, 4)
        .padding(.bottom, 16)
    }

    @ViewBuilder
    private func providerSchemaFieldRow(_ field: ProviderSettingsFieldSpec) -> some View {
        switch field.control {
        case .select(let options):
            let fallback = options.first?.value ?? ""
            let current = ProviderSettingsLogic.readConfigString(provider.config, key: field.key)
            let effective = current.isEmpty ? fallback : current
            let currentLabel = options.first(where: { $0.value == effective })?.label ?? effective
            inlineFieldRow(title: field.label, description: field.description) {
                Menu {
                    ForEach(options) { option in
                        Button {
                            let wireVal = option.value == fallback && field.clearWhenEmptyOmit ? "" : option.value
                            let next = ProviderSettingsLogic.nextConfig(from: provider.config, field: field, value: wireVal)
                            settings.updateProviderConfig(provider.id, config: next)
                        } label: {
                            Text(option.value == effective ? "✓ \(option.label)" : option.label)
                        }
                    }
                } label: {
                    SettingsMenuTrigger(currentLabel, disabled: disabled)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .disabled(disabled)
                .fixedSize()
            }

        case .password:
            let configured = ProviderSettingsLogic.isConfiguredSecret(provider.config, key: field.key)
            inlineFieldRow(title: field.label, description: field.description) {
                HStack(spacing: 6) {
                    if configured && !disabled {
                        SettingsPillButton("Clear", variant: .quiet) {
                            let next = ProviderSettingsLogic.nextConfig(from: provider.config, field: field, value: "")
                            settings.updateProviderConfig(provider.id, config: next)
                        }
                    }
                    SettingsCommitField(
                        value: "",
                        placeholder: configured ? "Stored secret" : (field.placeholder.isEmpty ? "Not set" : field.placeholder),
                        monospaced: true,
                        secret: true,
                        disabled: disabled
                    ) { next in
                        let updated = ProviderSettingsLogic.nextConfig(from: provider.config, field: field, value: next)
                        settings.updateProviderConfig(provider.id, config: updated)
                    }
                    .frame(width: 220)
                }
            }

        case .text:
            let saved = ProviderSettingsLogic.readConfigString(provider.config, key: field.key)
            VStack(alignment: .leading, spacing: 4) {
                inlineFieldRow(title: field.label, description: field.description) {
                    SettingsCommitField(
                        value: saved,
                        placeholder: field.placeholder,
                        monospaced: field.monospaced,
                        disabled: disabled
                    ) { next in
                        if let error = ProviderSettingsLogic.validateFieldValue(next, for: field) {
                            rejectedFields[field.key] = error
                            return
                        }
                        rejectedFields.removeValue(forKey: field.key)
                        let updated = ProviderSettingsLogic.nextConfig(from: provider.config, field: field, value: next)
                        settings.updateProviderConfig(provider.id, config: updated)
                    }
                    .frame(width: 240)
                }
                if let error = rejectedFields[field.key] {
                    Text(error)
                        .font(SwftType.caption)
                        .foregroundStyle(SwftColor.danger)
                }
            }
        }
    }

    private func dedicatedEnvFieldRow(_ field: ProviderEnvironmentFieldSpec) -> some View {
        let existing = provider.environment.first(where: { $0.name == field.name })
        let configured = existing != nil
        let isRef = existing?.isSecretReference == true
        let plainValue = (!field.sensitive && existing?.valueRedacted != true) ? (existing?.value ?? "") : ""
        let placeholder: String = if isRef {
            "Secret reference"
        } else if field.sensitive && configured {
            "Stored secret"
        } else {
            field.placeholder
        }

        return inlineFieldRow(title: field.label, description: field.description) {
            HStack(spacing: 6) {
                if configured && !disabled {
                    SettingsPillButton("Clear", variant: .quiet) {
                        let next = ProviderSettingsLogic.removingEnvironmentVariables(
                            from: provider.environment,
                            names: [field.name]
                        )
                        settings.updateProviderEnvironment(provider.id, environment: next)
                    }
                }
                SettingsCommitField(
                    value: plainValue,
                    placeholder: placeholder,
                    monospaced: true,
                    secret: field.sensitive,
                    disabled: disabled
                ) { next in
                    let updated = ProviderSettingsLogic.nextEnvironment(
                        from: provider.environment,
                        settingName: field.name,
                        value: next,
                        sensitive: field.sensitive
                    )
                    settings.updateProviderEnvironment(provider.id, environment: updated)
                }
                .frame(width: 220)
            }
        }
    }

    private func inlineFieldRow<Control: View>(
        title: String,
        description: String?,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(SwftType.label)
                    .foregroundStyle(SwftColor.textPrimary)
                if let description, !description.isEmpty {
                    Text(description)
                        .font(SwftType.caption)
                        .foregroundStyle(SwftColor.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            control()
        }
    }
}

// MARK: - Accent Swatches

struct AccentSwatchPicker: View {
    let selectedHex: String?
    let disabled: Bool
    let onChange: (String?) -> Void

    var body: some View {
        HStack(spacing: 7) {
            ForEach(ProviderSettingsLogic.accentSwatches) { swatch in
                let isSelected = selectedHex?.lowercased() == swatch.hex.lowercased()
                Button {
                    guard !disabled else { return }
                    onChange(isSelected ? nil : swatch.hex)
                } label: {
                    Circle()
                        .fill(Color(swftHex: swatch.hex) ?? SwftColor.accent)
                        .frame(width: 16, height: 16)
                        .overlay {
                            if isSelected {
                                Circle()
                                    .strokeBorder(SwftColor.textPrimary, lineWidth: 2)
                                    .padding(-3)
                            }
                        }
                        .frame(width: 22, height: 22)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(disabled)
                .help(swatch.name)
                .accessibilityLabel("\(swatch.name) accent colour")
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
            if selectedHex != nil && !disabled {
                SettingsPillButton("Clear", variant: .quiet) {
                    onChange(nil)
                }
            }
        }
        .opacity(disabled ? 0.5 : 1)
    }
}

// MARK: - Environment Variables Editor

private struct ProviderEnvironmentVariablesEditor: View {
    @Environment(AppModel.self) private var model
    let provider: ProviderEntry
    let dedicatedNames: Set<String>
    let disabled: Bool

    @State private var isAdding = false
    @State private var nameDraft = ""
    @State private var valueDraft = ""
    @State private var sensitiveDraft = true
    @State private var validationError: String?

    private var genericVars: [ProviderInstanceEnvironmentVariable] {
        ProviderSettingsLogic.removingEnvironmentVariables(from: provider.environment, names: dedicatedNames)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Environment variables")
                        .font(SwftType.label)
                        .foregroundStyle(SwftColor.textPrimary)
                    Text("API keys, base URLs, and per-account CLI variables.")
                        .font(SwftType.caption)
                        .foregroundStyle(SwftColor.textTertiary)
                }
                Spacer()
                if !disabled && !isAdding {
                    SettingsPillButton("Add variable", systemName: "plus", variant: .quiet) {
                        isAdding = true
                    }
                }
            }

            ForEach(genericVars, id: \.name) { variable in
                HStack(spacing: 8) {
                    Text(variable.name)
                        .font(SwftType.monoSmall)
                        .foregroundStyle(SwftColor.textSecondary)
                        .lineLimit(1)
                    Text("=")
                        .font(SwftType.monoSmall)
                        .foregroundStyle(SwftColor.textTertiary)
                    if variable.isSecretReference {
                        Text("Secret reference")
                            .font(SwftType.monoSmall)
                            .foregroundStyle(SwftColor.textTertiary)
                    } else {
                        SettingsCommitField(
                            value: variable.valueRedacted == true ? "" : variable.value,
                            placeholder: variable.valueRedacted == true ? "Stored secret" : "Value",
                            monospaced: true,
                            secret: variable.sensitive,
                            disabled: disabled
                        ) { next in
                            let updated = ProviderSettingsLogic.nextEnvironment(
                                from: provider.environment,
                                settingName: variable.name,
                                value: next,
                                sensitive: variable.sensitive
                            )
                            model.settings.updateProviderEnvironment(provider.id, environment: updated)
                        }
                    }
                    if !disabled {
                        IconButton("xmark", help: "Remove \(variable.name)", size: 22) {
                            let updated = ProviderSettingsLogic.removingEnvironmentVariables(
                                from: provider.environment,
                                names: [variable.name]
                            )
                            model.settings.updateProviderEnvironment(provider.id, environment: updated)
                        }
                    }
                }
            }

            if isAdding && !disabled {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        TextField("VARIABLE_NAME", text: $nameDraft)
                            .textFieldStyle(.plain)
                            .font(SwftType.monoSmall)
                            .padding(.horizontal, 10)
                            .frame(width: 150, height: 30)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(SwftColor.surface))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(SwftColor.borderSubtle))

                        Group {
                            if sensitiveDraft {
                                SecureField("Value", text: $valueDraft)
                            } else {
                                TextField("Value", text: $valueDraft)
                            }
                        }
                        .textFieldStyle(.plain)
                        .font(SwftType.monoSmall)
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(SwftColor.surface))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(SwftColor.borderSubtle))
                        .onSubmit { commitAdd() }

                        SettingsPillButton(sensitiveDraft ? "Secret" : "Plain", variant: .secondary) {
                            sensitiveDraft.toggle()
                        }
                        SettingsPillButton("Add", variant: .primary) {
                            commitAdd()
                        }
                        SettingsPillButton("Cancel", variant: .quiet) {
                            resetAdd()
                        }
                    }
                    if let validationError {
                        Text(validationError)
                            .font(SwftType.caption)
                            .foregroundStyle(SwftColor.danger)
                    }
                }
            }
        }
    }

    private func commitAdd() {
        let trimmed = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ProviderSettingsLogic.isValidEnvironmentVariableName(trimmed) else {
            validationError = "Use letters, digits, and underscores, starting with a letter or underscore."
            return
        }
        if dedicatedNames.contains(trimmed) || genericVars.contains(where: { $0.name == trimmed }) {
            validationError = "Variable \(trimmed) is already set."
            return
        }
        let next = provider.environment + [
            ProviderInstanceEnvironmentVariable(name: trimmed, value: valueDraft, sensitive: sensitiveDraft),
        ]
        model.settings.updateProviderEnvironment(provider.id, environment: next)
        resetAdd()
    }

    private func resetAdd() {
        nameDraft = ""
        valueDraft = ""
        sensitiveDraft = true
        validationError = nil
        isAdding = false
    }
}

// MARK: - Models & Custom Models List

private struct ProviderModelsEditor: View {
    @Environment(AppModel.self) private var model
    let provider: ProviderEntry
    let disabled: Bool

    @State private var isAdding = false
    @State private var slugDraft = ""
    @State private var validationError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Models")
                    .font(SwftType.captionStrong)
                    .foregroundStyle(SwftColor.textTertiary)
                Spacer()
                if provider.canManageCustomModels && !disabled && !isAdding {
                    SettingsPillButton("Add custom model", systemName: "plus", variant: .quiet) {
                        isAdding = true
                    }
                }
            }

            if isAdding && provider.canManageCustomModels && !disabled {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        TextField(
                            ProviderSettingsLogic.customModelPlaceholder(for: provider.driver),
                            text: $slugDraft
                        )
                        .textFieldStyle(.plain)
                        .font(SwftType.monoSmall)
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(SwftColor.surface))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(SwftColor.borderSubtle))
                        .onSubmit { commitAdd() }

                        SettingsPillButton("Add", variant: .primary) { commitAdd() }
                        SettingsPillButton("Cancel", variant: .quiet) {
                            slugDraft = ""
                            validationError = nil
                            isAdding = false
                        }
                    }
                    if let validationError {
                        Text(validationError)
                            .font(SwftType.caption)
                            .foregroundStyle(SwftColor.danger)
                    }
                }
            }

            if provider.models.isEmpty {
                Text("No models reported yet.")
                    .font(SwftType.caption)
                    .foregroundStyle(SwftColor.textTertiary)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(provider.models) { item in
                        HStack(spacing: 8) {
                            Text(item.name)
                                .font(SwftType.caption)
                                .foregroundStyle(SwftColor.textPrimary)
                            if item.name != item.slug {
                                Text(item.slug)
                                    .font(SwftType.monoSmall)
                                    .foregroundStyle(SwftColor.textTertiary)
                                    .lineLimit(1)
                            }
                            if let sub = item.subProvider {
                                Text("· \(sub)")
                                    .font(SwftType.caption)
                                    .foregroundStyle(SwftColor.textTertiary)
                            }
                            if item.isCustom {
                                Text("· custom")
                                    .font(SwftType.caption)
                                    .foregroundStyle(SwftColor.accent)
                            }
                            Spacer()
                            if item.isCustom && provider.canManageCustomModels && !disabled {
                                SettingsPillButton("Remove", variant: .quiet) {
                                    model.settings.removeCustomModel(from: provider.id, slug: item.slug)
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
    }

    private func commitAdd() {
        switch ProviderSettingsLogic.validateCustomModelSlug(
            slugDraft,
            driver: provider.driver,
            models: provider.models,
            customModels: provider.customModels
        ) {
        case .success(let slug):
            model.settings.addCustomModel(to: provider.id, slug: slug)
            slugDraft = ""
            validationError = nil
            isAdding = false
        case .failure(let error):
            validationError = error.localizedDescription
        }
    }
}

// MARK: - Add Account Sheet (Mirrors Studio's AddAccountDialog)

private struct AddAccountSheet: View {
    @Environment(AppModel.self) private var model
    let existingIDs: Set<String>
    let onClose: () -> Void

    @State private var preset: AddAccountPresetID = .codex
    @State private var otherDriver: String = ProviderSettingsLogic.otherProviderDrivers.first?.value ?? "opencode"
    @State private var name = ""
    @State private var accentHex: String?
    @State private var claudeDirOverride: String?
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var effectiveDriver: String {
        preset == .other ? otherDriver : (preset.driver ?? "codex")
    }

    private var claudeDir: String {
        claudeDirOverride ?? ProviderSettingsLogic.suggestClaudeConfigDir(for: name)
    }

    private var previewInstanceID: String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return ProviderSettingsLogic.deriveAccountInstanceID(
            driver: effectiveDriver,
            name: trimmed,
            existingIDs: existingIDs
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Add account")
                        .font(SwftType.title)
                        .foregroundStyle(SwftColor.textPrimary)
                    Text("Each account appears separately in the model picker.")
                        .font(SwftType.caption)
                        .foregroundStyle(SwftColor.textSecondary)
                }
                Spacer()
                IconButton("xmark", help: "Close", size: 26, action: onClose)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Provider")
                    .font(SwftType.captionStrong)
                    .foregroundStyle(SwftColor.textTertiary)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    ForEach(AddAccountPresetID.allCases) { option in
                        let selected = option == preset
                        Button {
                            preset = option
                            errorMessage = nil
                        } label: {
                            HStack(spacing: 8) {
                                ProviderGlyph(
                                    symbol: option.providerKind.symbol,
                                    tint: selected ? SwftColor.accent : option.providerKind.tint,
                                    name: option.label
                                )
                                Text(option.label)
                                    .font(selected ? SwftType.labelStrong : SwftType.label)
                                    .foregroundStyle(SwftColor.textPrimary)
                                    .lineLimit(1)
                                Spacer(minLength: 4)
                                if selected {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(SwftColor.accent)
                                }
                            }
                            .padding(.horizontal, 12)
                            .frame(height: 36)
                            .background(
                                RoundedRectangle(cornerRadius: SwftRadius.m, style: .continuous)
                                    .fill(selected ? SwftColor.accentSoft.opacity(0.65) : SwftColor.surfaceMuted)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: SwftRadius.m, style: .continuous)
                                    .strokeBorder(selected ? SwftColor.accent.opacity(0.5) : SwftColor.borderSubtle)
                            )
                            .contentShape(RoundedRectangle(cornerRadius: SwftRadius.m, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(isSaving)
                    }
                }
                Text(preset.description)
                    .font(SwftType.caption)
                    .foregroundStyle(SwftColor.textSecondary)
            }

            if preset == .other {
                HStack {
                    Text("Driver")
                        .font(SwftType.labelStrong)
                        .foregroundStyle(SwftColor.textPrimary)
                    Spacer()
                    Menu {
                        ForEach(ProviderSettingsLogic.otherProviderDrivers) { driver in
                            Button {
                                otherDriver = driver.value
                            } label: {
                                Text(driver.value == otherDriver ? "✓ \(driver.label)" : driver.label)
                            }
                        }
                    } label: {
                        let label = ProviderSettingsLogic.otherProviderDrivers.first(where: { $0.value == otherDriver })?.label ?? otherDriver
                        SettingsMenuTrigger(label, disabled: isSaving)
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    .menuIndicator(.hidden)
                    .fixedSize()
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Account name")
                        .font(SwftType.labelStrong)
                        .foregroundStyle(SwftColor.textPrimary)
                    Spacer()
                    if let previewInstanceID {
                        Text(previewInstanceID)
                            .font(SwftType.monoSmall)
                            .foregroundStyle(SwftColor.textTertiary)
                    }
                }
                TextField(
                    preset == .other ? "e.g. Work" : "e.g. \(preset.label) Personal",
                    text: $name
                )
                .textFieldStyle(.plain)
                .font(SwftType.label)
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(SwftColor.surfaceMuted))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(SwftColor.borderSubtle))
                .disabled(isSaving)
                .onSubmit { submit() }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Accent color")
                    .font(SwftType.labelStrong)
                    .foregroundStyle(SwftColor.textPrimary)
                AccentSwatchPicker(selectedHex: accentHex, disabled: isSaving) { accentHex = $0 }
            }

            if preset == .claude {
                VStack(alignment: .leading, spacing: 8) {
                    Text("CLAUDE_CONFIG_DIR path")
                        .font(SwftType.labelStrong)
                        .foregroundStyle(SwftColor.textPrimary)
                    TextField(
                        "~/.claude-personal",
                        text: Binding(
                            get: { claudeDir },
                            set: { claudeDirOverride = $0 }
                        )
                    )
                    .textFieldStyle(.plain)
                    .font(SwftType.monoSmall)
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(SwftColor.surfaceMuted))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(SwftColor.borderSubtle))
                    .disabled(isSaving)

                    Text("Run this in Terminal to sign this account in:")
                        .font(SwftType.caption)
                        .foregroundStyle(SwftColor.textSecondary)
                    SettingsCopyableCode(
                        ProviderSettingsLogic.claudeLoginCommand(homePath: claudeDir),
                        copyLabel: "Copy"
                    )
                }
            }

            if let errorMessage {
                SettingsBanner(errorMessage, tone: .error)
            }

            HStack {
                Spacer()
                SettingsPillButton("Cancel", variant: .secondary, disabled: isSaving, action: onClose)
                SettingsPillButton(
                    isSaving ? "Adding…" : "Add account",
                    variant: .primary,
                    isLoading: isSaving,
                    disabled: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ) {
                    submit()
                }
            }
            .padding(.top, 4)
        }
        .padding(24)
        .frame(width: 440)
        .background(SwftColor.canvas)
    }

    private func submit() {
        guard !isSaving else { return }
        switch ProviderSettingsLogic.buildCreateAccountDraft(
            preset: preset,
            otherDriver: otherDriver,
            name: name,
            accentColor: accentHex,
            claudeConfigDir: claudeDir,
            existingIDs: existingIDs
        ) {
        case .failure(let error):
            errorMessage = error.localizedDescription
        case .success(let draft):
            isSaving = true
            errorMessage = nil
            Task {
                let result = await model.settings.createProviderAccount(draft: draft)
                isSaving = false
                switch result {
                case .success:
                    onClose()
                case .failure(let error):
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}
