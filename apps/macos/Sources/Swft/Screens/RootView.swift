import SwftDesign
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 0) {
            if model.sidebarVisible {
                SidebarView()
                    .frame(width: SwftLayout.sidebarWidth)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
            ZStack(alignment: .top) {
                switch model.destination {
                case .thread(let id):
                    if let detail = model.detail(for: id) {
                        ThreadView(detail: detail).id(id)
                    }
                default:
                    HomeView()
                }
                TopBar()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(SwftColor.canvas)
        }
        .background(SwftColor.sidebar)
        .background(WindowChrome())
        .ignoresSafeArea()
    }
}

/// Window-top row of the content area: sidebar toggle (when collapsed) and the right-hand pill group.
struct TopBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 8) {
            if !model.sidebarVisible {
                // Leave room for the traffic lights.
                Color.clear.frame(width: 68, height: 1)
                IconButton("sidebar.left", help: "Show sidebar", action: model.toggleSidebar)
                IconButton("square.and.pencil", help: "New thread") { model.destination = .home }
            }
            if case .thread(let id) = model.destination, let summary = model.sidebar.threads.first(where: { $0.id == id }) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(summary.title).font(SwftType.labelStrong).foregroundStyle(SwftColor.textPrimary).lineLimit(1)
                    Text(summary.project?.name ?? "No project").font(SwftType.caption).foregroundStyle(SwftColor.textTertiary)
                }
                .padding(.leading, model.sidebarVisible ? 12 : 4)
            }
            Spacer(minLength: 12)
            trailingPills
        }
        .padding(.horizontal, 12)
        .frame(height: SwftLayout.titlebarHeight)
        .background {
            if model.selectedThreadID != nil {
                // Transcript scrolls under the bar; fade it out rather than drawing a hard edge.
                LinearGradient(stops: [.init(color: SwftColor.canvas, location: 0.7), .init(color: SwftColor.canvas.opacity(0), location: 1)], startPoint: .top, endPoint: .bottom)
                    .frame(height: SwftLayout.titlebarHeight + 16)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .allowsHitTesting(false)
            }
        }
    }

    @ViewBuilder private var trailingPills: some View {
        if case .thread(let id) = model.destination, let detail = model.detail(for: id) {
            if case .branch(let branch) = detail.summary.location {
                ToolbarPill {
                    PillTextButton(branch, systemName: "arrow.triangle.branch")
                    if let diff = detail.diffStat {
                        DiffStat(text: diff).padding(.trailing, 8)
                    }
                }
            }
            ToolbarPill {
                IconButton("terminal", help: "Terminal")
                IconButton("sidebar.right", help: "Changes")
            }
            ToolbarPill {
                PillTextButton("Open", systemName: "chevron.left.forwardslash.chevron.right")
            }
        } else {
            ToolbarPill {
                IconButton("clock.arrow.circlepath", help: "History")
                IconButton("arrow.down.right.and.arrow.up.left", help: "Compact window")
            }
            ToolbarPill {
                Button {} label: {
                    HStack(spacing: 7) {
                        Circle().fill(SwftColor.success).frame(width: 7, height: 7)
                        Text("Local server").font(SwftType.label)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .contentShape(Capsule())
                }
                .buttonStyle(HoverFillStyle(shape: Capsule()))
                .foregroundStyle(SwftColor.textPrimary)
            }
        }
    }
}

/// "+142 −38" in success/danger ink.
struct DiffStat: View {
    let text: String
    var body: some View {
        let parts = text.split(separator: " ")
        HStack(spacing: 5) {
            ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                Text(part)
                    .font(SwftType.captionStrong)
                    .monospacedDigit()
                    .foregroundStyle(part.hasPrefix("+") ? SwftColor.success : SwftColor.danger)
            }
        }
    }
}
