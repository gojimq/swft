import SwftDesign
import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        ZStack {
            GlowBackground()
            VStack(spacing: 0) {
                Spacer(minLength: SwftLayout.titlebarHeight)
                Text("Hi \(model.home.greetingName), what are we building?")
                    .font(SwftType.greeting)
                    .foregroundStyle(SwftColor.textPrimary)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 28)

                ComposerView(placeholder: "Ask Swft to build, fix or explain…")
                    .frame(maxWidth: SwftLayout.composerMaxWidth)

                if case .failed(let message) = model.serverStatus {
                    ServerErrorBanner(
                        title: "Local server unavailable",
                        message: message,
                        onRetry: model.retryConnection
                    )
                    .frame(maxWidth: SwftLayout.composerMaxWidth)
                    .padding(.top, 12)
                } else if let actionError = model.actionError {
                    ActionErrorBanner(message: actionError) {
                        model.actionError = nil
                    }
                    .frame(maxWidth: SwftLayout.composerMaxWidth)
                    .padding(.top, 12)
                }

                SegmentedToggle(selection: $model.composerMode, options: ComposerMode.allCases.map { ($0, $0.rawValue) })
                    .padding(.top, 14)

                VStack(spacing: 8) {
                    ForEach(model.home.suggestions) { suggestion in
                        SuggestionRow(suggestion.text, systemName: suggestion.symbol) {
                            model.composerText = suggestion.text
                        }
                    }
                }
                .frame(maxWidth: SwftLayout.composerMaxWidth - 16)
                .padding(.top, 30)
                // Suggestions hang below the optical centre, so the bottom spacer gets a head start.
                Spacer(minLength: 40)
                Color.clear.frame(height: 80)
            }
            .padding(.horizontal, 32)
        }
    }
}

/// The shared composer bound to the app's composer state.
struct ComposerView: View {
    @Environment(AppModel.self) private var model
    let placeholder: String

    var body: some View {
        @Bindable var model = model
        let composer = model.composer
        PillComposer(
            text: $model.composerText,
            placeholder: placeholder,
            isBusy: composer.isBusy,
            onSend: model.send,
            onStop: model.stopActiveRun
        ) {
            if model.selectedThreadID == nil {
                projectPicker(contextLabel: composer.contextLabel)
            } else if let context = composer.contextLabel {
                ComposerChip(context, systemName: "folder")
            }
        } trailing: {
            modelPicker(composer: composer)
        }
    }

    @ViewBuilder
    private func projectPicker(contextLabel: String?) -> some View {
        let label = contextLabel ?? (model.projects.isEmpty ? "Add project" : "Select project")
        Menu {
            if !model.projects.isEmpty {
                let selection = Binding<String>(
                    get: { model.selectedProject?.id ?? "" },
                    set: { model.selectProject($0) }
                )
                Picker("Project", selection: selection) {
                    ForEach(model.projects) { project in
                        Text(project.name).tag(project.id)
                    }
                }
                .pickerStyle(.inline)
                Divider()
            }
            Button("Add Project…") {
                model.pickAndAddProject()
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "folder").font(.system(size: 12, weight: .medium))
                Text(label).font(SwftType.label).lineLimit(1)
            }
            .foregroundStyle(model.projects.isEmpty && !model.isMock ? SwftColor.textSecondary : SwftColor.textPrimary)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .contentShape(Capsule())
            .accessibilityElement(children: .combine)
        }
        .menuStyle(.button)
        .buttonStyle(HoverFillStyle(shape: Capsule()))
        .menuIndicator(.hidden)
        .fixedSize()
    }

    @ViewBuilder
    private func modelPicker(composer: ComposerState) -> some View {
        let currentModel = composer.model
        let modelLabel: String = {
            if let currentModel { return currentModel.name }
            switch model.serverStatus {
            case .connected: return "No models"
            case .failed: return "Offline"
            case .starting, .connecting, .reconnecting: return "Connecting…"
            }
        }()

        ModelPicker(model: modelLabel, effort: composer.selectedReasoningChoice?.label) {
            if composer.availableModels.isEmpty {
                switch model.serverStatus {
                case .connected:
                    Text("No models available")
                case .failed:
                    Text("Local server offline")
                case .starting, .connecting, .reconnecting:
                    Text("Waiting for server…")
                }
            } else {
                let modelBinding = Binding<String>(
                    get: { currentModel?.id ?? "" },
                    set: { newID in
                        if let picked = composer.availableModels.first(where: { $0.id == newID }) {
                            model.selectModel(picked)
                        }
                    }
                )
                Picker("Model", selection: modelBinding) {
                    ForEach(composer.availableModels) { option in
                        Text("\(option.name) · \(option.providerDisplayName)").tag(option.id)
                    }
                }
                .pickerStyle(.inline)
            }

            if let currentModel, !currentModel.reasoningChoices.isEmpty {
                let reasoningBinding = Binding<String>(
                    get: { composer.selectedReasoningChoice?.id ?? "" },
                    set: { model.selectReasoningChoice($0) }
                )
                Picker(currentModel.reasoningOptionLabel ?? "Thinking", selection: reasoningBinding) {
                    ForEach(currentModel.reasoningChoices) { choice in
                        Text(choice.label).tag(choice.id)
                    }
                }
                .pickerStyle(.inline)
            }
        }
    }
}

struct ServerErrorBanner: View {
    let title: String
    let message: String
    let onRetry: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13))
                .foregroundStyle(SwftColor.danger)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(SwftType.labelStrong)
                    .foregroundStyle(SwftColor.textPrimary)
                Text(message)
                    .font(SwftType.caption)
                    .foregroundStyle(SwftColor.textSecondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button(action: onRetry) {
                Text("Retry")
                    .font(SwftType.labelStrong)
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .background(Capsule().fill(SwftColor.surface))
                    .overlay(Capsule().strokeBorder(SwftColor.border))
                    .foregroundStyle(SwftColor.textPrimary)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: SwftRadius.l, style: .continuous).fill(SwftColor.dangerSoft))
        .overlay(RoundedRectangle(cornerRadius: SwftRadius.l, style: .continuous).strokeBorder(SwftColor.danger.opacity(0.28)))
    }
}

struct ActionErrorBanner: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(SwftColor.danger)
            Text(message)
                .font(SwftType.caption)
                .foregroundStyle(SwftColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            IconButton("xmark", help: "Dismiss", size: 22, action: onDismiss)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: SwftRadius.m, style: .continuous).fill(SwftColor.dangerSoft))
        .overlay(RoundedRectangle(cornerRadius: SwftRadius.m, style: .continuous).strokeBorder(SwftColor.danger.opacity(0.25)))
    }
}
