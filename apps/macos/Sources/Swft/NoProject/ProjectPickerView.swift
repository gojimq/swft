import AppKit
import SwftDesign
import SwiftUI

/// Floating Liquid Glass popover for choosing, adding, or removing projects directly from the Home composer.
struct ProjectPickerPanel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let triggerFrame: CGRect

    @State private var panelFrame: CGRect = .zero
    @State private var pendingDeletion: ProjectRef?
    @State private var inlineError: String?

    static let width: CGFloat = 312
    private static let maxScrollableListHeight: CGFloat = 264
    private static let scrollThreshold = 6

    private var isLocalEnvironment: Bool {
        model.activeComposerEnvironment?.isLocal ?? true
    }

    private var canAddProject: Bool {
        model.isMock || model.isTargetEnvironmentConnected(localConnected: model.serverStatus.isConnected)
    }

    var body: some View {
        PickerPanelSurface {
            Group {
                if let target = pendingDeletion {
                    deletionConfirmation(for: target)
                        .transition(.opacity)
                } else {
                    projectList
                        .transition(.opacity)
                }
            }
            .animation(SwftMotion.resolve(SwftMotion.quick, reduceMotion: reduceMotion), value: pendingDeletion?.id)
        }
        .frame(width: Self.width)
        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { panelFrame = $0 }
        .background(
            ProjectPickerEventMonitor(
                isInside: { point in panelFrame.contains(point) || triggerFrame.contains(point) },
                onEscape: handleEscape,
                onOutsideClick: closeAnimated
            )
        )
        .onChange(of: model.projects) { _, updated in
            if let target = pendingDeletion, !updated.contains(where: { $0.id == target.id }) {
                pendingDeletion = nil
                inlineError = nil
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Project picker")
    }

    // MARK: - Project List

    private var projectList: some View {
        let projects = model.projects
        let selectedID = model.selectedProject?.id

        return VStack(alignment: .leading, spacing: 0) {
            Group {
                if projects.isEmpty {
                    PickerNote("No recent projects yet.")
                        .padding(.horizontal, 6)
                        .padding(.vertical, 6)
                } else if projects.count > Self.scrollThreshold {
                    ScrollView {
                        projectRows(projects: projects, selectedID: selectedID)
                            .padding(6)
                    }
                    .scrollIndicators(.never)
                    .frame(height: Self.maxScrollableListHeight)
                } else {
                    projectRows(projects: projects, selectedID: selectedID)
                        .padding(6)
                }
            }

            PickerDivider()

            noProjectRow
                .padding(.horizontal, 6)
                .padding(.vertical, 4)

            PickerDivider()

            addProjectRow
                .padding(.horizontal, 6)
                .padding(.top, 4)
                .padding(.bottom, 6)
        }
    }

    private func projectRows(projects: [ProjectRef], selectedID: String?) -> some View {
        VStack(spacing: 2) {
            ForEach(projects) { project in
                ProjectPickerRow(
                    project: project,
                    displayPath: project.workspaceRoot.map {
                        ProjectDeletionLogic.displayPath($0, isLocal: isLocalEnvironment)
                    },
                    isSelected: project.id == selectedID,
                    isDeleting: model.deletingProjectIDs.contains(project.id),
                    onSelect: {
                        withAnimation(SwftMotion.resolve(SwftMotion.spring, reduceMotion: reduceMotion)) {
                            _ = model.selectProject(project.id)
                        }
                    },
                    onRequestDelete: {
                        withAnimation(SwftMotion.resolve(SwftMotion.quick, reduceMotion: reduceMotion)) {
                            inlineError = nil
                            pendingDeletion = project
                        }
                    }
                )
            }
        }
    }

    private var noProjectRow: some View {
        let isSelected = model.selectedProject == nil && model.canStartWithoutProject
        return ProjectPickerActionRow(
            title: NoProjectLogic.noProjectLabel,
            systemImage: "square.dashed",
            trailingDetail: model.canStartWithoutProject ? nil : "Unavailable",
            isSelected: isSelected,
            disabled: !model.canStartWithoutProject,
            helpText: model.noProjectUnavailableReason
        ) {
            withAnimation(SwftMotion.resolve(SwftMotion.spring, reduceMotion: reduceMotion)) {
                model.clearProject()
            }
        }
    }

    private var addProjectRow: some View {
        ProjectPickerActionRow(
            title: "Add Project…",
            systemImage: "plus",
            trailingDetail: nil,
            isSelected: false,
            disabled: !canAddProject,
            helpText: canAddProject ? "Register a folder as a project" : "Connect to the server before adding a project."
        ) {
            model.closeProjectPicker()
            model.pickAndAddProject()
        }
    }

    // MARK: - Inline Delete Confirmation

    private func deletionConfirmation(for target: ProjectRef) -> some View {
        let counts = model.projectThreadCounts(for: target)
        let copy = ProjectDeletionLogic.confirmation(for: target, threadCounts: counts)
        let isDeleting = model.deletingProjectIDs.contains(target.id)
        let formattedPath = target.workspaceRoot.map {
            ProjectDeletionLogic.displayPath($0, isLocal: isLocalEnvironment)
        }

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                ProjectBadgeIcon(project: target, size: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(copy.title)
                        .font(SwftType.labelStrong)
                        .foregroundStyle(SwftColor.textPrimary)
                        .lineLimit(2)
                    if let formattedPath {
                        Text(formattedPath)
                            .font(SwftType.monoSmall)
                            .foregroundStyle(SwftColor.textTertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }

            Text(copy.message)
                .font(SwftType.caption)
                .foregroundStyle(SwftColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if let inlineError {
                Text(inlineError)
                    .font(SwftType.caption)
                    .foregroundStyle(SwftColor.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button {
                    withAnimation(SwftMotion.resolve(SwftMotion.quick, reduceMotion: reduceMotion)) {
                        pendingDeletion = nil
                        inlineError = nil
                    }
                } label: {
                    Text("Cancel")
                        .font(SwftType.captionStrong)
                        .foregroundStyle(SwftColor.textPrimary)
                        .padding(.horizontal, 12)
                        .frame(height: 28)
                        .background(Capsule().fill(PickerPolish.hoverFill))
                        .overlay(Capsule().strokeBorder(PickerPolish.divider))
                        .contentShape(Capsule())
                }
                .buttonStyle(TactilePressStyle(shape: Capsule(), pressScale: PickerPolish.segmentPressScale))
                .disabled(isDeleting)

                Button {
                    inlineError = nil
                    Task {
                        let errorMessage = await model.deleteProject(target)
                        withAnimation(SwftMotion.resolve(SwftMotion.quick, reduceMotion: reduceMotion)) {
                            if let errorMessage {
                                inlineError = errorMessage
                            } else {
                                pendingDeletion = nil
                                inlineError = nil
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        if isDeleting {
                            ProgressView()
                                .controlSize(.mini)
                        }
                        Text(isDeleting ? "Removing…" : copy.confirmLabel)
                            .font(SwftType.captionStrong)
                    }
                    .foregroundStyle(SwftColor.danger)
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .background(Capsule().fill(SwftColor.dangerSoft))
                    .overlay(Capsule().strokeBorder(SwftColor.danger.opacity(0.35)))
                    .contentShape(Capsule())
                }
                .buttonStyle(TactilePressStyle(shape: Capsule(), pressScale: PickerPolish.segmentPressScale))
                .disabled(isDeleting)
            }
            .padding(.top, 2)
        }
        .padding(14)
    }

    // MARK: - Dismissal

    private func handleEscape() {
        if let target = pendingDeletion {
            guard !model.deletingProjectIDs.contains(target.id) else { return }
            withAnimation(SwftMotion.resolve(SwftMotion.quick, reduceMotion: reduceMotion)) {
                pendingDeletion = nil
                inlineError = nil
            }
            return
        }
        closeAnimated()
    }

    private func closeAnimated() {
        withAnimation(SwftMotion.resolve(SwftMotion.popover, reduceMotion: reduceMotion)) {
            model.closeProjectPicker()
        }
    }
}

// MARK: - Subviews

struct ProjectBadgeIcon: View {
    let project: ProjectRef
    var size: CGFloat = 22

    var body: some View {
        if project.isWorkspaceMissing {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(SwftColor.warningSoft)
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                        .strokeBorder(SwftColor.warningBorder, lineWidth: 1)
                )
                .overlay {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: size * 0.46, weight: .semibold))
                        .foregroundStyle(SwftColor.warning)
                }
                .frame(width: size, height: size)
        } else {
            ProjectChip(
                initials: project.initials ?? "",
                tint: project.tint,
                size: size,
                dashed: project.initials == nil
            )
        }
    }
}

private struct ProjectPickerRow: View {
    let project: ProjectRef
    let displayPath: String?
    let isSelected: Bool
    let isDeleting: Bool
    let onSelect: () -> Void
    let onRequestDelete: () -> Void

    @State private var isRowHovered = false
    @State private var isTrashHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var showsTrash: Bool {
        isRowHovered || project.isWorkspaceMissing || isDeleting
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        HStack(spacing: 4) {
            Button(action: onSelect) {
                HStack(spacing: 8) {
                    ProjectBadgeIcon(project: project, size: 22)

                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 5) {
                            Text(project.name)
                                .font(isSelected && !project.isWorkspaceMissing ? SwftType.labelStrong : SwftType.label)
                                .foregroundStyle(project.isWorkspaceMissing ? SwftColor.textSecondary : SwftColor.textPrimary)
                                .lineLimit(1)
                            if project.isWorkspaceMissing {
                                Text("Missing")
                                    .font(SwftType.micro)
                                    .foregroundStyle(SwftColor.warning)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(Capsule().fill(SwftColor.warningSoft))
                            }
                        }

                        if let displayPath {
                            Text(displayPath)
                                .font(SwftType.monoSmall)
                                .foregroundStyle(SwftColor.textTertiary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }

                    Spacer(minLength: 4)

                    if isSelected && !project.isWorkspaceMissing {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11.5, weight: .bold))
                            .foregroundStyle(SwftColor.accent)
                            .transition(.swftPop(reduceMotion: reduceMotion, scale: 0.5))
                    }
                }
                .padding(.leading, 8)
                .padding(.trailing, 4)
                .padding(.vertical, 5)
                .frame(minHeight: 36)
                .contentShape(shape)
            }
            .buttonStyle(TactilePressStyle(shape: shape, pressedFill: project.isWorkspaceMissing ? .clear : PickerPolish.pressedFill))
            .disabled(project.isWorkspaceMissing || isDeleting)
            .help(project.isWorkspaceMissing ? "Folder no longer exists on disk" : (project.workspaceRoot ?? project.name))
            .accessibilityAddTraits(isSelected && !project.isWorkspaceMissing ? [.isSelected] : [])

            Button(action: onRequestDelete) {
                Group {
                    if isDeleting {
                        ProgressView()
                            .controlSize(.mini)
                    } else {
                        Image(systemName: "trash")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(
                                isTrashHovered
                                    ? SwftColor.danger
                                    : (project.isWorkspaceMissing ? SwftColor.warning : SwftColor.textTertiary)
                            )
                    }
                }
                .frame(width: 24, height: 24)
                .background(Circle().fill(isTrashHovered ? SwftColor.dangerSoft : .clear))
                .contentShape(Circle())
            }
            .buttonStyle(TactilePressStyle(shape: Circle(), pressScale: 0.9, pressedFill: SwftColor.dangerSoft))
            .onHover { isTrashHovered = $0 }
            .disabled(isDeleting)
            .opacity(showsTrash ? 1 : 0)
            .allowsHitTesting(showsTrash)
            .padding(.trailing, 6)
            .help("Remove project from Swft")
            .accessibilityLabel("Remove \(project.name)")
        }
        .background(shape.fill(isRowHovered ? PickerPolish.hoverFill : .clear))
        .contentShape(shape)
        .onHover { hovering in
            isRowHovered = hovering
            if !hovering { isTrashHovered = false }
        }
        .animation(SwftMotion.resolve(SwftMotion.quick, reduceMotion: reduceMotion), value: isRowHovered)
        .animation(SwftMotion.resolve(SwftMotion.quick, reduceMotion: reduceMotion), value: isTrashHovered)
    }
}

private struct ProjectPickerActionRow: View {
    let title: String
    let systemImage: String
    let trailingDetail: String?
    let isSelected: Bool
    let disabled: Bool
    let helpText: String?
    let action: () -> Void

    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(disabled ? SwftColor.textTertiary : SwftColor.textSecondary)
                    .frame(width: 22, height: 22)
                Text(title)
                    .font(isSelected ? SwftType.labelStrong : SwftType.label)
                    .foregroundStyle(disabled ? SwftColor.textTertiary : SwftColor.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let trailingDetail {
                    Text(trailingDetail)
                        .font(SwftType.caption)
                        .foregroundStyle(SwftColor.textTertiary)
                } else if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11.5, weight: .bold))
                        .foregroundStyle(SwftColor.accent)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 32)
            .background(shape.fill(hovering && !disabled ? PickerPolish.hoverFill : .clear))
            .contentShape(shape)
        }
        .buttonStyle(TactilePressStyle(shape: shape))
        .disabled(disabled)
        .onHover { hovering = $0 }
        .animation(SwftMotion.resolve(SwftMotion.quick, reduceMotion: reduceMotion), value: hovering)
        .help(helpText ?? "")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

// MARK: - Window-Level Escape & Outside Click Dismissal

private struct ProjectPickerEventMonitor: NSViewRepresentable {
    let isInside: (CGPoint) -> Bool
    let onEscape: () -> Void
    let onOutsideClick: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.parent = self
        context.coordinator.install(for: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.parent = self
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    @MainActor
    final class Coordinator {
        var parent: ProjectPickerEventMonitor?
        private var monitors: [Any] = []
        private weak var view: NSView?

        func install(for view: NSView) {
            self.view = view
            monitors.append(NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                let window = event.window.map(ObjectIdentifier.init)
                let keyCode = event.keyCode
                let plain = event.modifierFlags.intersection([.command, .control, .option]).isEmpty
                let handled = MainActor.assumeIsolated { self?.handleKey(keyCode, plain: plain, window: window) ?? false }
                return handled ? nil : event
            } as Any)
            monitors.append(NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                let window = event.window.map(ObjectIdentifier.init)
                let height = event.window?.contentView?.bounds.height ?? 0
                let point = CGPoint(x: event.locationInWindow.x, y: height - event.locationInWindow.y)
                MainActor.assumeIsolated { self?.handleClick(at: point, window: window) }
                return event
            } as Any)
        }

        func uninstall() {
            monitors.forEach(NSEvent.removeMonitor)
            monitors.removeAll()
        }

        private var windowID: ObjectIdentifier? { view?.window.map(ObjectIdentifier.init) }

        private func handleKey(_ keyCode: UInt16, plain: Bool, window: ObjectIdentifier?) -> Bool {
            guard plain, keyCode == 53, window != nil, window == windowID, let parent else { return false }
            parent.onEscape()
            return true
        }

        private func handleClick(at point: CGPoint, window: ObjectIdentifier?) {
            guard let parent else { return }
            if window != windowID || !parent.isInside(point) { parent.onOutsideClick() }
        }
    }
}
