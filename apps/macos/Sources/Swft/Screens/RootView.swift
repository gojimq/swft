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
                    } else {
                        HomeView()
                    }
                case .projects:
                    ProjectsView()
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
    @State private var showingServerPopover = false

    var body: some View {
        HStack(spacing: 8) {
            if !model.sidebarVisible {
                // Leave room for the traffic lights.
                Color.clear.frame(width: 68, height: 1)
                IconButton("sidebar.left", help: "Show sidebar", action: model.toggleSidebar)
                IconButton("square.and.pencil", help: "New thread", action: model.goHome)
            }
            if case .thread(let id) = model.destination, let summary = model.threadSummary(for: id) {
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
            if !model.serverStatus.isConnected {
                serverStatusPill
            }
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
            serverStatusPill
        }
    }

    private var serverStatusPill: some View {
        ToolbarPill {
            Button {
                showingServerPopover.toggle()
            } label: {
                HStack(spacing: 7) {
                    Circle().fill(model.serverStatus.dotColor).frame(width: 7, height: 7)
                    Text(model.serverStatus.pillTitle).font(SwftType.label)
                }
                .padding(.horizontal, 10)
                .frame(height: 28)
                .contentShape(Capsule())
            }
            .buttonStyle(HoverFillStyle(shape: Capsule()))
            .foregroundStyle(SwftColor.textPrimary)
            .popover(isPresented: $showingServerPopover, arrowEdge: .bottom) {
                ServerStatusPopover(dismiss: { showingServerPopover = false })
            }

            if model.serverStatus.needsRetry {
                PillTextButton("Retry", systemName: "arrow.clockwise") {
                    model.retryConnection()
                }
            }
        }
    }
}

/// Compact popover explaining local server connection status, active providers, or startup errors.
struct ServerStatusPopover: View {
    @Environment(AppModel.self) private var model
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle().fill(model.serverStatus.dotColor).frame(width: 8, height: 8)
                Text(model.serverStatus.pillTitle)
                    .font(SwftType.labelStrong)
                    .foregroundStyle(SwftColor.textPrimary)
                Spacer(minLength: 12)
                if case .connected(_, _, let port) = model.serverStatus, let port {
                    Text(":\(port)")
                        .font(SwftType.monoSmall)
                        .foregroundStyle(SwftColor.textTertiary)
                }
            }

            switch model.serverStatus {
            case .starting:
                Text("Launching local Swft server…")
                    .font(SwftType.caption)
                    .foregroundStyle(SwftColor.textSecondary)
            case .connecting:
                Text("Authenticating and opening WebSocket connection…")
                    .font(SwftType.caption)
                    .foregroundStyle(SwftColor.textSecondary)
            case .connected(let label, let count, _):
                Text("\(label) · \(count) \(count == 1 ? "provider" : "providers") ready")
                    .font(SwftType.caption)
                    .foregroundStyle(SwftColor.textSecondary)
                let names = model.readyProviderNames
                if !names.isEmpty {
                    Text(names.joined(separator: ", "))
                        .font(SwftType.caption)
                        .foregroundStyle(SwftColor.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            case .reconnecting(let attempt, let message):
                Text("Reconnecting (attempt \(attempt)): \(message)")
                    .font(SwftType.caption)
                    .foregroundStyle(SwftColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            case .failed(let message):
                Text(message)
                    .font(SwftType.caption)
                    .foregroundStyle(SwftColor.danger)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                Spacer()
                if model.serverStatus.isConnected && !model.isMock {
                    Button("Refresh providers") {
                        model.refreshProviders()
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                if !model.isMock {
                    Button(model.serverStatus.isConnected ? "Reconnect" : "Retry") {
                        model.retryConnection()
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
        }
        .padding(14)
        .frame(width: 300)
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
