import SwftDesign
import SwiftUI

/// Drop-in composer leading slot for project selection on Home and read-only project state in active threads.
struct ComposerProjectSlot: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let contextLabel: String?

    var body: some View {
        let chipState = model.composerProjectChipState(contextLabel: contextLabel)
        if model.selectedThreadID == nil {
            ComposerProjectChip(
                state: chipState,
                isOpen: model.isProjectPickerOpen,
                onClear: model.canStartWithoutProject ? { model.clearProject() } : nil,
                clearHelp: "Start without a project",
                chipHelp: chipState.isNoProject ? "Choose a project" : "Switch or manage projects"
            ) {
                withAnimation(SwftMotion.resolve(SwftMotion.popover, reduceMotion: reduceMotion)) {
                    model.toggleProjectPicker()
                }
            }
        } else {
            ComposerProjectChip(
                state: chipState,
                chipHelp: chipState.isNoProject ? "This thread has no project" : nil
            )
        }
    }
}
