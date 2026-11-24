import SwftDesign
import SwiftUI

struct SidebarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 0) {
            // Shares the traffic-light row; the lights sit at the leading edge.
            HStack(spacing: 2) {
                Spacer()
                IconButton("magnifyingglass", help: "Search threads")
                IconButton("sidebar.left", help: "Hide sidebar", action: model.toggleSidebar)
            }
            .padding(.horizontal, 10)
            .frame(height: SwftLayout.titlebarHeight)

            HStack(spacing: 9) {
                SwftMark(size: 22)
                Text("Swft").font(SwftType.brand).foregroundStyle(SwftColor.textPrimary)
            }
            .padding(.leading, 18)
            .padding(.bottom, 14)

            VStack(spacing: 2) {
                SidebarNavRow("New thread", systemName: "square.and.pencil", isSelected: model.destination == .home, isProminent: true) {
                    model.destination = .home
                }
                SidebarNavRow("Projects", systemName: "folder", isSelected: model.destination == .projects) { model.destination = .projects }
                SidebarNavRow("Scheduled", systemName: "clock", isSelected: model.destination == .scheduled) { model.destination = .scheduled }
                SidebarNavRow("Settings", systemName: "gearshape", isSelected: model.destination == .settings) { model.destination = .settings }
            }
            .padding(.horizontal, 8)

            SidebarSectionHeader("Threads") {
                Menu {
                    Picker("Show", selection: $model.sidebar.filter) {
                        ForEach(ThreadFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.inline)
                } label: {
                    HStack(spacing: 3) {
                        Text(model.sidebar.filter.rawValue).font(SwftType.label)
                        Image(systemName: "chevron.down").font(.system(size: 8.5, weight: .bold))
                    }
                    .foregroundStyle(SwftColor.textSecondary)
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .contentShape(Capsule())
                }
                .menuStyle(.button)
                .buttonStyle(HoverFillStyle(shape: Capsule()))
                .menuIndicator(.hidden)
                .fixedSize()
            }
            .padding(.horizontal, 8)
            .padding(.top, 18)
            .padding(.bottom, 2)

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(model.visibleThreads) { thread in
                        ThreadInboxRow(thread.inboxModel(now: model.now), isSelected: model.selectedThreadID == thread.id) {
                            model.open(thread.id)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
            .scrollIndicators(.automatic)

            AccountRow(name: model.sidebar.account.name, detail: model.sidebar.account.detail)
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
        }
        .background(SwftColor.sidebar)
    }
}
