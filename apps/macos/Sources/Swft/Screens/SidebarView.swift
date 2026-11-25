import SwftDesign
import SwiftUI

struct SidebarView: View {
    @Environment(AppModel.self) private var model
    @Namespace private var selectionNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 0) {
            // Shares the traffic-light row. Like the reference, these icons sit ~5pt above the lights' centre line.
            HStack(spacing: 2) {
                Spacer()
                IconButton("magnifyingglass", help: "Search threads", weight: .medium, tint: SwftColor.textPrimary)
                IconButton("sidebar.left", help: "Hide sidebar", weight: .medium, tint: SwftColor.textPrimary, action: model.toggleSidebar)
            }
            .padding(.horizontal, 10)
            .frame(height: 42)

            HStack(spacing: 9) {
                SwftMark(size: 22)
                Text("Swft").font(SwftType.brand).foregroundStyle(SwftColor.textPrimary)
            }
            .frame(height: 24)
            .padding(.leading, 18)
            .padding(.top, 10)
            .padding(.bottom, 12)

            VStack(spacing: 2) {
                SidebarNavRow("New thread", systemName: "square.and.pencil", isSelected: model.destination == .home) {
                    model.goHome()
                }
                SidebarNavRow("Projects", systemName: "folder", isSelected: model.destination == .projects) {
                    model.destination = .projects
                }
                SidebarNavRow("Scheduled", systemName: "clock", isSelected: model.destination == .scheduled) {
                    model.destination = .scheduled
                }
                SidebarNavRow("Settings", systemName: "gearshape", isSelected: model.destination == .settings) {
                    model.destination = .settings
                }
            }
            .padding(.horizontal, 8)

            SidebarSectionHeader("Threads") {
                Menu {
                    Picker("Show", selection: $model.filter) {
                        ForEach(ThreadFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.inline)
                } label: {
                    HStack(spacing: 3) {
                        Text(model.filter.rawValue).font(SwftType.label)
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
                        ThreadInboxRow(
                            thread.inboxModel(now: model.now),
                            isSelected: model.selectedThreadID == thread.id,
                            hoverAction: .settle { model.settleThread(thread.id) }
                        ) {
                            model.open(thread.id)
                        }
                        .contextMenu {
                            Button {
                                model.settleThread(thread.id)
                            } label: {
                                Label("Settle thread", systemImage: "checkmark")
                            }
                        }
                        .transition(.swftRise(reduceMotion: reduceMotion, distance: -6))
                    }

                    SidebarSettledSection()
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
            .scrollIndicators(.automatic)
            .scrollEdgeSoftIfAvailable()

            // Reserved bottom footer area (upcoming usage widget); only shows a quiet retry pill when offline.
            if model.serverStatus.needsRetry {
                OfflineRetryPill(title: model.serverStatus.pillTitle, dotColor: model.serverStatus.dotColor) {
                    model.retryConnection()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .transition(.swftPop(reduceMotion: reduceMotion, scale: 0.92))
            } else {
                Color.clear.frame(height: 8)
            }
        }
        .environment(\.swftSelectionNamespace, selectionNamespace)
        .animation(SwftMotion.resolve(SwftMotion.glide, reduceMotion: reduceMotion), value: model.destination)
        .animation(SwftMotion.resolve(SwftMotion.spring, reduceMotion: reduceMotion), value: model.visibleThreads.map(\.id))
        .animation(SwftMotion.resolve(SwftMotion.spring, reduceMotion: reduceMotion), value: model.serverStatus.needsRetry)
        .background(SwftColor.sidebar)
    }
}
