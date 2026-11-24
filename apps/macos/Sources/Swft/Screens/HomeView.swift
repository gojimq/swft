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

                ComposerView(placeholder: "Ask Swft to build, fix or explain…", pickerOpensBelow: true)
                    .frame(maxWidth: SwftLayout.composerMaxWidth)
                    // The model picker drops over the toggle and suggestions below.
                    .zIndex(1)

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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let placeholder: String
    /// Home has room below the composer; a thread's composer sits at the bottom, so its picker opens above.
    var pickerOpensBelow = false
    @State private var triggerFrame: CGRect = .zero

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
            modelPickerTrigger(composer: composer)
        }
        .overlay(alignment: pickerOpensBelow ? .bottomTrailing : .topTrailing) {
            if let session = model.modelPicker, let content = model.modelPickerContent {
                ModelPickerPanel(session: session, content: content, triggerFrame: triggerFrame)
                    .padding(pickerOpensBelow ? .top : .bottom, 8)
                    // A zero-height anchor on the composer's edge; the panel overflows away from the composer.
                    .frame(height: 0, alignment: pickerOpensBelow ? .top : .bottom)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.94, anchor: pickerOpensBelow ? .topTrailing : .bottomTrailing)).combined(with: .offset(y: pickerOpensBelow ? -6 : 6)))
            }
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
    private func modelPickerTrigger(composer: ComposerState) -> some View {
        let current = composer.model
        let label: String = {
            if let current { return current.name }
            switch model.serverStatus {
            case .connected: return "No models"
            case .failed: return "Offline"
            case .starting, .connecting, .reconnecting: return "Connecting…"
            }
        }()
        let catalog = model.pickerCatalog
        let harness = current.map { ModelPickerLogic.harness($0.instanceId, in: catalog) }
        let mark = harness.map { harness in
            PickerRailItem(id: harness.id, symbol: harness.kind.pickerSymbol, monogram: harness.label, tint: harness.kind.tint, accent: harness.accentColor, tooltip: harness.label, inUse: true)
        }
        let effort = (current?.reasoningChoices.count ?? 0) > 1 ? composer.selectedReasoningChoice?.label : nil
        ModelPickerTrigger(
            mark: mark,
            disambiguator: harness.flatMap { ModelPickerLogic.disambiguator(of: $0, among: catalog.harnesses) },
            model: label,
            effort: effort,
            isOpen: model.modelPicker != nil
        ) {
            withAnimation(SwftMotion.resolve(model.modelPicker == nil ? SwftMotion.pop : SwftMotion.standard, reduceMotion: reduceMotion)) {
                model.toggleModelPicker()
            }
        }
        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { triggerFrame = $0 }
        .help("Model and thinking level")
        .accessibilityLabel(accessibilityLabel(model: label, harness: harness, effort: effort))
    }

    private func accessibilityLabel(model name: String, harness: PickerHarness?, effort: String?) -> String {
        let full = harness.map { "\(name) on \($0.label)" } ?? name
        return effort.map { "Model: \(full), \($0) thinking" } ?? "Model: \(full)"
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
