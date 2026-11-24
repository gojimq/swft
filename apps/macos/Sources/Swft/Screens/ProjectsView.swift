import SwftDesign
import SwiftUI

/// Quiet list of registered projects with folder picker registration, matching SwftDesign tokens.
struct ProjectsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Projects")
                        .font(SwftType.title)
                        .foregroundStyle(SwftColor.textPrimary)
                    Spacer()
                    Button(action: model.pickAndAddProject) {
                        HStack(spacing: 6) {
                            Image(systemName: "plus").font(.system(size: 11.5, weight: .semibold))
                            Text("Add Project…").font(SwftType.labelStrong)
                        }
                        .padding(.horizontal, 14)
                        .frame(height: 32)
                        .background(Capsule().fill(SwftColor.surface))
                        .overlay(Capsule().strokeBorder(SwftColor.border))
                        .foregroundStyle(SwftColor.textPrimary)
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(!model.serverStatus.isConnected && !model.isMock)
                }

                if let actionError = model.actionError {
                    ActionErrorBanner(message: actionError) {
                        model.actionError = nil
                    }
                }

                if model.projects.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("No projects yet")
                            .font(SwftType.headline)
                            .foregroundStyle(SwftColor.textPrimary)
                        Text("Add a local folder or git repository to start threads in it.")
                            .font(SwftType.label)
                            .foregroundStyle(SwftColor.textSecondary)
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: SwftRadius.l, style: .continuous).fill(SwftColor.surface))
                    .overlay(RoundedRectangle(cornerRadius: SwftRadius.l, style: .continuous).strokeBorder(SwftColor.borderSubtle))
                } else {
                    VStack(spacing: 8) {
                        ForEach(model.projects) { project in
                            let count = model.threadCount(forProjectID: project.id)
                            let isSelected = model.selectedProject?.id == project.id
                            Button {
                                model.selectProject(project.id)
                                model.goHome()
                            } label: {
                                HStack(spacing: 12) {
                                    ProjectChip(
                                        initials: project.initials ?? "",
                                        tint: project.tint,
                                        size: 28,
                                        dashed: project.initials == nil
                                    )
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(project.name)
                                            .font(SwftType.labelStrong)
                                            .foregroundStyle(SwftColor.textPrimary)
                                        if let path = project.workspaceRoot {
                                            Text(path)
                                                .font(SwftType.monoSmall)
                                                .foregroundStyle(SwftColor.textTertiary)
                                                .lineLimit(1)
                                                .truncationMode(.middle)
                                        }
                                    }
                                    Spacer(minLength: 12)
                                    Text("\(count) \(count == 1 ? "thread" : "threads")")
                                        .font(SwftType.caption)
                                        .foregroundStyle(SwftColor.textTertiary)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: SwftRadius.l, style: .continuous)
                                        .fill(SwftColor.surface)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: SwftRadius.l, style: .continuous)
                                        .strokeBorder(isSelected ? SwftColor.accent.opacity(0.45) : SwftColor.borderSubtle)
                                )
                                .contentShape(RoundedRectangle(cornerRadius: SwftRadius.l, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .frame(maxWidth: SwftLayout.contentMaxWidth, alignment: .leading)
            .padding(.horizontal, 32)
            .padding(.top, SwftLayout.titlebarHeight + 24)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity)
        }
    }
}
