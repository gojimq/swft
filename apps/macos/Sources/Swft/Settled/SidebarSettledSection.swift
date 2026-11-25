import SwftDesign
import SwiftUI

/// Collapsible Settled threads section rendered at the bottom of the sidebar's scrollable thread list.
struct SidebarSettledSection: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let settledCount = model.settledThreads.count
        if settledCount > 0 {
            VStack(alignment: .leading, spacing: 2) {
                if !model.visibleThreads.isEmpty {
                    Rectangle()
                        .fill(SwftColor.borderSubtle)
                        .frame(height: 1)
                        .padding(.horizontal, 10)
                        .padding(.top, 10)
                        .padding(.bottom, 6)
                }

                SettledSectionHeader(
                    "Settled",
                    count: settledCount,
                    isExpanded: model.isSettledExpanded
                ) {
                    withAnimation(SwftMotion.resolve(SwftMotion.disclosure, reduceMotion: reduceMotion)) {
                        model.toggleSettledSection()
                    }
                }

                ForEach(model.visibleSettledThreads) { thread in
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
                    .transition(.swftRise(reduceMotion: reduceMotion, distance: -4))
                }
            }
            .animation(SwftMotion.resolve(SwftMotion.disclosure, reduceMotion: reduceMotion), value: model.isSettledExpanded)
            .animation(SwftMotion.resolve(SwftMotion.spring, reduceMotion: reduceMotion), value: model.visibleSettledThreads.map(\.id))
        }
    }
}
