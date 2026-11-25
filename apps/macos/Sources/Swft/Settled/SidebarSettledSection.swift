import SwftDesign
import SwiftUI

/// Collapsible Settled threads shelf pinned directly above the sidebar usage pills, opening upwards.
struct SidebarSettledSection: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let settledCount = model.settledThreads.count
        let rows = model.visibleSettledThreads
        if settledCount > 0 {
            VStack(alignment: .leading, spacing: 2) {
                if !rows.isEmpty {
                    Rectangle()
                        .fill(SwftColor.borderSubtle)
                        .frame(height: 1)
                        .padding(.horizontal, 10)
                        .padding(.bottom, 4)

                    ViewThatFits(in: .vertical) {
                        settledRowsList(rows)
                        ScrollView {
                            settledRowsList(rows)
                        }
                        .scrollIndicators(.automatic)
                        .frame(height: 240)
                    }
                    .frame(maxHeight: 240)
                    .clipped()
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .opacity.combined(with: .move(edge: .bottom))
                    )
                }

                SettledSectionHeader(
                    "Settled",
                    count: settledCount,
                    isExpanded: model.isSettledExpanded,
                    opensUpward: true
                ) {
                    withAnimation(SwftMotion.resolve(SwftMotion.disclosure, reduceMotion: reduceMotion)) {
                        model.toggleSettledSection()
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 2)
            .padding(.bottom, 2)
            .clipped()
            .animation(SwftMotion.resolve(SwftMotion.disclosure, reduceMotion: reduceMotion), value: model.isSettledExpanded)
            .animation(SwftMotion.resolve(SwftMotion.spring, reduceMotion: reduceMotion), value: rows.map(\.id))
        }
    }

    @ViewBuilder
    private func settledRowsList(_ rows: [ThreadSummary]) -> some View {
        VStack(spacing: 2) {
            ForEach(rows) { thread in
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
                .transition(.swftRise(reduceMotion: reduceMotion, distance: 4))
            }
        }
        .padding(.bottom, 2)
    }
}
