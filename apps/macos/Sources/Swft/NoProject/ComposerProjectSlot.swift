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
                onClear: model.canStartWithoutProject ? { model.clearProject() } : nil,
                clearHelp: "Start without a project",
                chipHelp: chipState.isNoProject ? "Choose a project" : "Switch project"
            ) {
                pickerMenuContent
            }
        } else {
            ComposerProjectChip(
                state: chipState,
                chipHelp: chipState.isNoProject ? "This thread has no project" : nil
            )
        }
    }

    @ViewBuilder
    private var pickerMenuContent: some View {
        let selection = Binding<String>(
            get: { model.selectedProject?.id ?? NoProjectLogic.noProjectMenuTag },
            set: { tag in
                withAnimation(SwftMotion.resolve(SwftMotion.spring, reduceMotion: reduceMotion)) {
                    if tag == NoProjectLogic.noProjectMenuTag {
                        model.clearProject()
                    } else {
                        model.selectProject(tag)
                    }
                }
            }
        )

        if !model.projects.isEmpty || model.canStartWithoutProject {
            Picker("Project", selection: selection) {
                ForEach(model.projects) { project in
                    Label(project.name, systemImage: "folder")
                        .tag(project.id)
                }
                if model.canStartWithoutProject {
                    Label(NoProjectLogic.noProjectLabel, systemImage: "square.dashed")
                        .tag(NoProjectLogic.noProjectMenuTag)
                }
            }
            .pickerStyle(.inline)
        }

        if !model.canStartWithoutProject {
            Button {} label: {
                Label(NoProjectLogic.noProjectLabel, systemImage: "square.dashed")
            }
            .disabled(true)
        }

        Divider()

        Button("Add Project…") {
            model.pickAndAddProject()
        }
    }
}
