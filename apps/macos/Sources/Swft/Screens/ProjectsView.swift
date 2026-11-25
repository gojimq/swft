import SwftDesign
import SwiftUI

/// Quiet list of registered projects with folder picker registration and removal, matching SwftDesign tokens.
struct ProjectsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pendingDeletion: ProjectRef?

    private var canAddProject: Bool {
        model.isMock || model.isTargetEnvironmentConnected(localConnected: model.serverStatus.isConnected)
    }

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
                    .disabled(!canAddProject)
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
                            ProjectRowCard(
                                project: project,
                                threadCount: model.projectThreadCounts(for: project).listed,
                                isSelected: model.selectedProject?.id == project.id,
                                isDeleting: model.deletingProjectIDs.contains(project.id),
                                onSelect: {
                                    if model.selectProject(project.id) {
                                        model.goHome()
                                    }
                                },
                                onRequestDelete: {
                                    pendingDeletion = project
                                }
                            )
                        }
                    }
                    .animation(SwftMotion.resolve(SwftMotion.spring, reduceMotion: reduceMotion), value: model.projects.map(\.id))
                }
            }
            .frame(maxWidth: SwftLayout.contentMaxWidth, alignment: .leading)
            .padding(.horizontal, 32)
            .padding(.top, SwftLayout.titlebarHeight + 24)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity)
            .swftOverlayScrollbars()
        }
        .onAppear {
            model.refreshLocalProjectAvailability()
        }
        .alert(
            pendingDeletion.map { ProjectDeletionLogic.confirmation(for: $0, threadCounts: model.projectThreadCounts(for: $0)).title } ?? "Remove project",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            presenting: pendingDeletion
        ) { target in
            let copy = ProjectDeletionLogic.confirmation(for: target, threadCounts: model.projectThreadCounts(for: target))
            Button(copy.confirmLabel, role: .destructive) {
                pendingDeletion = nil
                Task {
                    _ = await model.deleteProject(target)
                }
            }
            Button("Cancel", role: .cancel) {
                pendingDeletion = nil
            }
        } message: { target in
            Text(ProjectDeletionLogic.confirmation(for: target, threadCounts: model.projectThreadCounts(for: target)).message)
        }
    }
}

private struct ProjectRowCard: View {
    let project: ProjectRef
    let threadCount: Int
    let isSelected: Bool
    let isDeleting: Bool
    let onSelect: () -> Void
    let onRequestDelete: () -> Void

    @State private var isHovered = false
    @State private var isTrashHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var showsTrash: Bool {
        isHovered || project.isWorkspaceMissing || isDeleting
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: SwftRadius.l, style: .continuous)
        HStack(spacing: 8) {
            Button(action: onSelect) {
                HStack(spacing: 12) {
                    ProjectBadgeIcon(project: project, size: 28)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(project.name)
                                .font(SwftType.labelStrong)
                                .foregroundStyle(project.isWorkspaceMissing ? SwftColor.textSecondary : SwftColor.textPrimary)
                                .lineLimit(1)
                            if project.isWorkspaceMissing {
                                Text("Folder missing")
                                    .font(SwftType.micro)
                                    .foregroundStyle(SwftColor.warning)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(SwftColor.warningSoft))
                            }
                        }
                        if let path = project.workspaceRoot {
                            Text(path)
                                .font(SwftType.monoSmall)
                                .foregroundStyle(SwftColor.textTertiary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }

                    Spacer(minLength: 12)

                    Text("\(threadCount) \(threadCount == 1 ? "thread" : "threads")")
                        .font(SwftType.caption)
                        .foregroundStyle(SwftColor.textTertiary)
                }
                .padding(.leading, 14)
                .padding(.trailing, 4)
                .padding(.vertical, 12)
                .contentShape(shape)
            }
            .buttonStyle(.plain)
            .disabled(isDeleting)

            Button(action: onRequestDelete) {
                Group {
                    if isDeleting {
                        ProgressView()
                            .controlSize(.mini)
                    } else {
                        Image(systemName: "trash")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(
                                isTrashHovered
                                    ? SwftColor.danger
                                    : (project.isWorkspaceMissing ? SwftColor.warning : SwftColor.textTertiary)
                            )
                    }
                }
                .frame(width: 28, height: 28)
                .background(Circle().fill(isTrashHovered ? SwftColor.dangerSoft : .clear))
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .onHover { isTrashHovered = $0 }
            .disabled(isDeleting)
            .opacity(showsTrash ? 1 : 0)
            .allowsHitTesting(showsTrash)
            .padding(.trailing, 10)
            .help("Remove project from Swft")
            .accessibilityLabel("Remove \(project.name)")
        }
        .background(shape.fill(SwftColor.surface))
        .overlay(
            shape.strokeBorder(
                project.isWorkspaceMissing
                    ? SwftColor.warningBorder
                    : (isSelected ? SwftColor.accent.opacity(0.45) : SwftColor.borderSubtle)
            )
        )
        .contentShape(shape)
        .onHover { hovering in
            isHovered = hovering
            if !hovering { isTrashHovered = false }
        }
        .contextMenu {
            Button(role: .destructive, action: onRequestDelete) {
                Label("Remove project…", systemImage: "trash")
            }
            .disabled(isDeleting)
        }
        .animation(SwftMotion.resolve(SwftMotion.quick, reduceMotion: reduceMotion), value: isHovered)
        .animation(SwftMotion.resolve(SwftMotion.quick, reduceMotion: reduceMotion), value: isTrashHovered)
    }
}
