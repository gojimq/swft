import SwftDesign
import SwiftUI

/// Collapsible Settled threads shelf pinned directly above the sidebar usage pills, opening upwards.
struct SidebarSettledSection: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Natural list height and matching row count, kept across collapses so reopens roll to the right size.
    @State private var measuredHeight: CGFloat = 0
    @State private var measuredRowCount: Int = 0
    /// Last pinned row, kept so it can roll away instead of vanishing when the shelf reopens.
    @State private var lastPinnedID: ThreadSummary.ID?

    var body: some View {
        let settled = model.settledThreads
        if !settled.isEmpty {
            let isExpanded = model.isSettledExpanded
            let pinned = SettledShelfLayout.pinnedThread(
                settled: settled,
                isExpanded: isExpanded,
                selectedThreadID: model.selectedThreadID
            )
            let knownHeight = measuredRowCount == settled.count ? measuredHeight : 0

            VStack(alignment: .leading, spacing: 0) {
                // Renders every settled thread even mid-collapse, so closing rolls rows back into the header.
                SwftDisclosure(isExpanded: isExpanded) {
                    ScrollView {
                        rowsList(settled)
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                                measuredHeight = height
                                measuredRowCount = settled.count
                            }
                            .swftOverlayScrollbars()
                    }
                    .defaultScrollAnchor(.top)
                    .scrollIndicators(.automatic)
                    .swftScrollEdgeFade()
                    .frame(height: SettledShelfLayout.shelfHeight(listHeight: knownHeight, rowCount: settled.count))
                    .animation(SwftMotion.resolve(SwftMotion.spring, reduceMotion: reduceMotion), value: settled.map(\.id))
                }

                // Collapsed with a settled thread open: that one row stays reachable above the header.
                SwftDisclosure(isExpanded: pinned != nil) {
                    if let shown = pinned ?? settled.first(where: { $0.id == lastPinnedID }) {
                        row(shown).padding(.bottom, 2)
                    }
                }
                .onChange(of: pinned?.id, initial: true) { _, id in
                    if let id { lastPinnedID = id }
                }

                SettledSectionHeader(
                    "Settled",
                    count: settled.count,
                    isExpanded: isExpanded,
                    opensUpward: true
                ) {
                    withAnimation(SwftMotion.resolve(SwftMotion.disclosure, reduceMotion: reduceMotion)) {
                        model.toggleSettledSection()
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 4)
            .padding(.bottom, 2)
        }
    }

    private func rowsList(_ rows: [ThreadSummary]) -> some View {
        VStack(spacing: 2) {
            ForEach(rows) { thread in
                row(thread)
                    .transition(.swftRise(reduceMotion: reduceMotion, distance: 4))
            }
        }
        .padding(.vertical, 2)
    }

    private func row(_ thread: ThreadSummary) -> some View {
        ThreadInboxRow(
            thread.inboxModel(now: model.now),
            isSelected: model.selectedThreadID == thread.id,
            hoverAction: .unsettle { model.unsettleThread(thread.id) }
        ) {
            model.open(thread.id)
        }
        .contextMenu {
            Button {
                model.unsettleThread(thread.id)
            } label: {
                Label("Un-settle thread", systemImage: "arrow.uturn.backward")
            }
        }
    }
}

/// Pure sizing and selection rules for the Settled shelf.
enum SettledShelfLayout {
    static let maxHeight: CGFloat = 240
    /// Matches a three-line `ThreadInboxRow` (~72pt) plus 2pt stack spacing, preventing a first-open jump.
    static let estimatedRowHeight: CGFloat = 74

    static func shelfHeight(listHeight: CGFloat, rowCount: Int) -> CGFloat {
        let natural = listHeight > 0 ? listHeight : CGFloat(rowCount) * estimatedRowHeight + 4
        return min(natural, maxHeight)
    }

    /// The selected settled thread shown on its own while the shelf is collapsed.
    static func pinnedThread(
        settled: [ThreadSummary],
        isExpanded: Bool,
        selectedThreadID: ThreadSummary.ID?
    ) -> ThreadSummary? {
        guard !isExpanded, let selectedThreadID else { return nil }
        return settled.first { $0.id == selectedThreadID }
    }
}
