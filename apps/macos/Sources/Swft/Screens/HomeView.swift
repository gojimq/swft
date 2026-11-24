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

                SegmentedToggle(selection: $model.composer.mode, options: ComposerMode.allCases.map { ($0, $0.rawValue) })
                    .padding(.top, 14)

                VStack(spacing: 8) {
                    ForEach(model.home.suggestions) { suggestion in
                        SuggestionRow(suggestion.text, systemName: suggestion.symbol) {
                            model.composer.text = suggestion.text
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
        PillComposer(text: $model.composer.text, placeholder: placeholder, isBusy: model.composer.isBusy, onSend: model.send) {
            if let context = model.composer.contextLabel {
                ComposerChip(context, systemName: "folder")
            }
        } trailing: {
            ModelPicker(model: model.composer.model.name, effort: model.composer.effort.rawValue) {
                Picker("Model", selection: $model.composer.model) {
                    ForEach(model.composer.availableModels) { option in
                        Text("\(option.name) · \(option.provider.displayName)").tag(option)
                    }
                }
                .pickerStyle(.inline)
                Picker("Thinking", selection: $model.composer.effort) {
                    ForEach(ReasoningEffort.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.inline)
            }
        }
    }
}
