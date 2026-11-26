import Foundation
import SwftDesign
import SwiftUI

/// Renders a single inline subagent indicator row inside the thread transcript.
struct SubagentSingleRowView: View, Equatable {
    let item: SubagentItem
    let parentEnvironmentID: String?
    let knownEnvironmentIDs: Set<String>
    let isExpanded: Bool
    let onToggleExpansion: (String) -> Void
    let onOpenThread: (SubagentNavigationTarget) -> Void

    nonisolated static func == (lhs: SubagentSingleRowView, rhs: SubagentSingleRowView) -> Bool {
        lhs.item == rhs.item
            && lhs.parentEnvironmentID == rhs.parentEnvironmentID
            && lhs.knownEnvironmentIDs == rhs.knownEnvironmentIDs
            && lhs.isExpanded == rhs.isExpanded
    }

    var body: some View {
        let target = SubagentDisplayLogic.navigationTarget(
            for: item,
            parentEnvironmentID: parentEnvironmentID,
            knownEnvironmentIDs: knownEnvironmentIDs
        )
        let rowModel = Self.makeRowModel(for: item, target: target)
        SubagentInlineCard(
            model: rowModel,
            embedded: false,
            isExpanded: isExpanded
        ) {
            if let target {
                onOpenThread(target)
            } else if rowModel.hasInlineDetails {
                onToggleExpansion(item.id)
            }
        }
        .equatable()
    }

    static func makeRowModel(
        for item: SubagentItem,
        target: SubagentNavigationTarget?
    ) -> SubagentRowModel {
        let icon = SwftAdapters.resolvedProviderIcon(
            driver: item.providerDriver,
            instanceId: item.providerInstanceID,
            iconUrl: item.providerIconURL,
            displayName: item.providerDisplayName ?? item.provider.displayName
        )
        let detail = SubagentDisplayLogic.detailPreview(
            status: item.status,
            progress: item.progress,
            result: item.result
        )
        let expandedBody = SubagentDisplayLogic.inlineExpandedBody(for: item)
        let modelBadge = item.modelName ?? item.providerDisplayName ?? item.provider.displayName
        let helpParts = [
            item.title,
            modelBadge,
            item.status.displayLabel,
            item.workspaceLabel,
            target != nil ? "Click to open subagent thread" : nil,
        ].compactMap { $0 }.filter { !$0.isEmpty }

        return SubagentRowModel(
            id: item.id,
            title: item.title,
            modelLabel: modelBadge,
            remoteEnvironmentLabel: item.remoteEnvironmentLabel,
            detail: detail,
            statusLabel: item.status.displayLabel,
            status: item.status.badgeStatus,
            icon: icon,
            startedAt: item.startedAt,
            completedAt: item.completedAt,
            canOpenThread: target != nil,
            prompt: item.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : item.prompt,
            expandedBodyLabel: expandedBody?.label,
            expandedBodyText: expandedBody?.text,
            workspaceLabel: item.workspaceLabel,
            helpText: helpParts.joined(separator: " · ")
        )
    }
}

/// Renders a collapsible inline group of 2+ consecutive parallel subagents spawned in a turn.
struct SubagentGroupRowView: View, Equatable {
    let group: SubagentGroup
    let parentEnvironmentID: String?
    let knownEnvironmentIDs: Set<String>
    let expandedIDs: Set<String>
    let onToggleExpansion: (String) -> Void
    let onOpenThread: (SubagentNavigationTarget) -> Void

    nonisolated static func == (lhs: SubagentGroupRowView, rhs: SubagentGroupRowView) -> Bool {
        lhs.group == rhs.group
            && lhs.parentEnvironmentID == rhs.parentEnvironmentID
            && lhs.knownEnvironmentIDs == rhs.knownEnvironmentIDs
            && lhs.expandedIDs == rhs.expandedIDs
    }

    var body: some View {
        let timing = SubagentDisplayLogic.groupTiming(for: group.members)
        let targetsByID = Dictionary(
            uniqueKeysWithValues: group.members.compactMap { member -> (String, SubagentNavigationTarget)? in
                guard let target = SubagentDisplayLogic.navigationTarget(
                    for: member,
                    parentEnvironmentID: parentEnvironmentID,
                    knownEnvironmentIDs: knownEnvironmentIDs
                ) else {
                    return nil
                }
                return (member.id, target)
            }
        )
        let memberModels = group.members.map { member in
            SubagentSingleRowView.makeRowModel(for: member, target: targetsByID[member.id])
        }
        let avatars = memberModels.prefix(3).map { member in
            SubagentAvatarSpec(id: member.id, icon: member.icon, status: nil)
        }
        let groupModel = SubagentGroupModel(
            id: group.id,
            title: SubagentDisplayLogic.groupHeaderTitle(count: group.members.count),
            statusSummary: SubagentDisplayLogic.summarizeGroupStatuses(group.members.map(\.status)),
            avatars: avatars,
            totalCount: group.members.count,
            isActive: timing.isActive,
            hasSpinnerActivity: timing.hasSpinnerActivity,
            hasWaiting: timing.hasWaiting,
            hasFailed: timing.hasFailed,
            startedAt: timing.startedAt,
            completedAt: timing.completedAt,
            members: memberModels
        )

        SubagentGroupCard(
            model: groupModel,
            isExpanded: expandedIDs.contains(group.id),
            expandedMemberIDs: expandedIDs,
            onToggleGroup: { onToggleExpansion(group.id) },
            onMemberAction: { member in
                if let target = targetsByID[member.id] {
                    onOpenThread(target)
                } else if member.hasInlineDetails {
                    onToggleExpansion(member.id)
                }
            }
        )
        .equatable()
    }
}
