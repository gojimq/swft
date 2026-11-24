import SwftDesign
import SwiftUI

/// Home composer environment selector inserted immediately before the project chip.
/// Shown when multiple environments are configured or a remote environment is active.
struct ComposerEnvironmentPicker: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let items = model.composerEnvironmentChipItems
        if model.shouldShowComposerEnvironmentPicker, !items.isEmpty {
            EnvironmentChip(
                items: items,
                selectedID: model.activeComposerEnvironmentID,
                isLocked: false,
                onSelect: { id in
                    withAnimation(SwftMotion.resolve(SwftMotion.quick, reduceMotion: reduceMotion)) {
                        model.selectEnvironment(id)
                    }
                },
                onManageConnections: {
                    model.openConnectionsSettings()
                }
            )
            .transition(.swftPop(reduceMotion: reduceMotion, scale: 0.92))
        }
    }
}
