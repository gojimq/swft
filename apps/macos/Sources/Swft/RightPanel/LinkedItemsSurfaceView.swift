import AppKit
import SwftDesign
import SwftKit
import SwiftUI

struct LinkedItemsSurfaceView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let threadID: String

    @State private var familyThreads: [ThreadShell] = []
    @State private var isLoadingFamily = false
    @State private var showingLinkPRPopover = false
    @State private var prURLInput = ""
    @State private var actionNotice: String?

    private var pullRequests: [ThreadPullRequestLink] {
        model.linkedPullRequests(forThreadID: threadID)
    }

    private var issues: [ThreadIssueLink] {
        model.linkedIssues(forThreadID: threadID)
    }

    private var relatedThreads: [LinkedThreadSummaryItem] {
        model.relatedThreads(forThreadID: threadID, fetchedFamily: familyThreads)
    }

    private var isEmpty: Bool {
        pullRequests.isEmpty && issues.isEmpty && relatedThreads.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider().overlay(SwftColor.borderSubtle)

            if let actionNotice {
                HStack(spacing: 8) {
                    Text(actionNotice)
                        .font(SwftType.caption)
                        .foregroundStyle(SwftColor.danger)
                        .lineLimit(2)
                    Spacer()
                    Button("Dismiss") { self.actionNotice = nil }
                        .buttonStyle(.plain)
                        .font(SwftType.captionStrong)
                        .foregroundStyle(SwftColor.accent)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(SwftColor.dangerSoft)
            }

            if isEmpty {
                RightPanelEmptyState(
                    icon: "link",
                    title: "No linked items",
                    message: "Pull requests, issues, side chats, and subagents linked to this thread appear here."
                ) {
                    Button {
                        showingLinkPRPopover = true
                    } label: {
                        Label("Link pull request", systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        if !pullRequests.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                sectionHeader("Pull requests", count: pullRequests.count)
                                VStack(spacing: 6) {
                                    ForEach(pullRequests) { link in
                                        pullRequestRow(link)
                                    }
                                }
                            }
                        }

                        if !issues.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                sectionHeader("Issues", count: issues.count)
                                VStack(spacing: 6) {
                                    ForEach(issues) { issue in
                                        issueRow(issue)
                                    }
                                }
                            }
                        }

                        if !relatedThreads.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                sectionHeader("Related threads", count: relatedThreads.count)
                                VStack(spacing: 6) {
                                    ForEach(relatedThreads) { related in
                                        relatedThreadRow(related)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .background(SwftColor.canvas)
        .task(id: "\(threadID)::\(model.isMock)") {
            await loadThreadFamily()
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(spacing: 8) {
            Text("Linked items")
                .font(SwftType.captionStrong)
                .foregroundStyle(SwftColor.textPrimary)

            Spacer()

            if isLoadingFamily {
                ProgressView().controlSize(.mini)
            }

            RightPanelPillButton("Link PR", systemName: "plus") {
                showingLinkPRPopover = true
            }
            .popover(isPresented: $showingLinkPRPopover, arrowEdge: .bottom) {
                linkPRPopover
            }

            IconButton("arrow.clockwise", help: "Refresh linked items", size: 26) {
                Task { await loadThreadFamily() }
            }
        }
        .rightPanelSubHeader()
    }

    private var linkPRPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Link pull request")
                .font(SwftType.labelStrong)
                .foregroundStyle(SwftColor.textPrimary)
            Text("Paste a GitHub or GitLab pull request URL to track it on this thread.")
                .font(SwftType.caption)
                .foregroundStyle(SwftColor.textTertiary)
            TextField("https://github.com/owner/repo/pull/123", text: $prURLInput)
                .textFieldStyle(.roundedBorder)
                .font(SwftType.caption)
                .onSubmit {
                    Task { await submitLinkPR() }
                }
            HStack {
                Spacer()
                Button("Cancel") {
                    showingLinkPRPopover = false
                }
                .controlSize(.small)
                Button("Link") {
                    Task { await submitLinkPR() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(RightPanelLogic.parsePullRequestURL(prURLInput) == nil)
            }
        }
        .padding(14)
        .frame(width: 300)
    }

    private func sectionHeader(_ title: String, count: Int) -> some View {
        RightPanelSectionHeader(title, count: count)
    }

    // MARK: - Pull Request Row

    private func pullRequestRow(_ link: ThreadPullRequestLink) -> some View {
        let snapshot = link.snapshot
        let badge = prStatusBadge(snapshot: snapshot)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("#" + String(link.number))
                            .font(SwftType.monoSmall)
                            .foregroundStyle(SwftColor.textTertiary)
                        RightPanelStatusBadge(badge.label, icon: badge.icon, tone: badge.tone)

                        if let checks = snapshot?.checksState {
                            let checkBadge = checksBadge(checks)
                            RightPanelStatusBadge(checkBadge.label, icon: checkBadge.icon, tone: checkBadge.tone)
                        }
                        if link.isWatching {
                            Image(systemName: "eye")
                                .font(.system(size: 10))
                                .foregroundStyle(SwftColor.accent)
                                .help("Watching for updates")
                        }
                    }

                    Text(snapshot?.title ?? "\(link.repository)#\(link.number)")
                        .font(SwftType.captionStrong)
                        .foregroundStyle(SwftColor.textPrimary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                RightPanelOverflowMenu {
                    Button {
                        model.rightPanel.openBrowser(
                            urlString: link.url,
                            pageTitle: "#\(link.number) \(snapshot?.title ?? link.repository)",
                            for: threadID
                        )
                    } label: {
                        Label("Open in Browser tab", systemImage: "globe")
                    }
                    Button {
                        if let url = URL(string: link.url) {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        Label("Open in default browser", systemImage: "arrow.up.right.square")
                    }
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(link.url, forType: .string)
                    } label: {
                        Label("Copy URL", systemImage: "doc.on.doc")
                    }
                    Divider()
                    Button(role: .destructive) {
                        Task { await unlinkPullRequest(link) }
                    } label: {
                        Label("Unlink from thread", systemImage: "link.badge.minus")
                    }
                }
            }

            HStack(spacing: 8) {
                Text(link.repository)
                    .font(SwftType.monoSmall)
                    .foregroundStyle(SwftColor.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if let snapshot {
                    Text("\(snapshot.headBranch) → \(snapshot.baseBranch)")
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(SwftColor.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer(minLength: 4)

                if let add = snapshot?.additions, let del = snapshot?.deletions, (add > 0 || del > 0) {
                    HStack(spacing: 4) {
                        Text("+\(add)")
                            .foregroundStyle(SwftColor.success)
                        Text("−\(del)")
                            .foregroundStyle(SwftColor.danger)
                    }
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .rightPanelCard()
        .onTapGesture {
            model.rightPanel.openBrowser(
                urlString: link.url,
                pageTitle: "#\(link.number) \(snapshot?.title ?? link.repository)",
                for: threadID
            )
        }
    }

    // MARK: - Issue Row

    private func issueRow(_ issue: ThreadIssueLink) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "smallcircle.filled.circle")
                .font(.system(size: 12))
                .foregroundStyle(SwftColor.success)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(issue.displayKey)
                        .font(SwftType.monoSmall)
                        .foregroundStyle(SwftColor.textSecondary)
                    RightPanelStatusBadge(RightPanelLogic.trackerDisplayName(issue.tracker), tone: .neutral)
                }
                Text(issue.title)
                    .font(SwftType.captionStrong)
                    .foregroundStyle(SwftColor.textPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(issue.scope)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(SwftColor.textTertiary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            RightPanelOverflowMenu {
                Button {
                    model.rightPanel.openBrowser(
                        urlString: issue.url,
                        pageTitle: "\(issue.displayKey) \(issue.title)",
                        for: threadID
                    )
                } label: {
                    Label("Open in Browser tab", systemImage: "globe")
                }
                Button {
                    if let url = URL(string: issue.url) {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Label("Open in default browser", systemImage: "arrow.up.right.square")
                }
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(issue.url, forType: .string)
                } label: {
                    Label("Copy URL", systemImage: "doc.on.doc")
                }
                Divider()
                Button(role: .destructive) {
                    Task { await unlinkIssue(issue) }
                } label: {
                    Label("Unlink from thread", systemImage: "link.badge.minus")
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .rightPanelCard()
        .onTapGesture {
            model.rightPanel.openBrowser(
                urlString: issue.url,
                pageTitle: "\(issue.displayKey) \(issue.title)",
                for: threadID
            )
        }
    }

    // MARK: - Related Thread Row

    private func relatedThreadRow(_ item: LinkedThreadSummaryItem) -> some View {
        HStack(spacing: 9) {
            Image(systemName: item.relation.iconName)
                .font(.system(size: 12))
                .foregroundStyle(SwftColor.textSecondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(SwftType.captionStrong)
                    .foregroundStyle(SwftColor.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(item.relation.rawValue)
                        .font(.system(size: 10.5))
                        .foregroundStyle(SwftColor.textTertiary)
                    Text("·")
                        .foregroundStyle(SwftColor.textTertiary)
                    Text(RelativeTime.short(from: item.updatedAt, to: model.now))
                        .font(.system(size: 10.5))
                        .foregroundStyle(SwftColor.textTertiary)
                }
            }

            Spacer(minLength: 6)

            if item.status == .running {
                RightPanelStatusBadge("Running", tone: .accent)
            } else if item.status == .needsApproval {
                RightPanelStatusBadge("Needs approval", tone: .warning)
            } else if item.status == .failed {
                RightPanelStatusBadge("Failed", tone: .danger)
            }

            HStack(spacing: 4) {
                if item.relation == .sideChat || item.relation == .subagent {
                    IconButton("rectangle.righthalf.inset.filled", help: "Open in right panel tab", size: 22) {
                        openRelatedInRightPanel(item)
                    }
                }
                IconButton("arrow.up.right", help: "Open in main view", size: 22) {
                    model.open(item.id)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .rightPanelCard()
        .onTapGesture {
            if item.relation == .sideChat || item.relation == .subagent {
                openRelatedInRightPanel(item)
            } else {
                model.open(item.id)
            }
        }
    }

    private func openRelatedInRightPanel(_ item: LinkedThreadSummaryItem) {
        withAnimation(SwftMotion.resolve(SwftMotion.screen, reduceMotion: reduceMotion)) {
            if item.relation == .subagent {
                let status: SubagentStatus = switch item.status {
                case .running: .running
                case .needsApproval: .waiting
                case .failed: .failed
                case .idle, .unread: .idle
                }
                let envID = model.threadSummary(for: threadID)?.environmentID ?? model.activeThreadEnvironmentID
                _ = model.rightPanel.openSubagentTab(
                    SubagentTabState(
                        subagentThreadId: item.id,
                        environmentId: envID,
                        title: item.title,
                        status: status
                    ),
                    for: threadID
                )
            } else {
                _ = model.rightPanel.openSideChat(
                    sideThreadId: item.id,
                    title: item.title,
                    for: threadID
                )
            }
        }
    }

    // MARK: - Badges & RPCs

    private func prStatusBadge(snapshot: ThreadPullRequestSnapshot?) -> (label: String, icon: String, tone: RightPanelStatusBadge.Tone) {
        guard let snapshot else {
            return ("Linked", "link", .neutral)
        }
        switch snapshot.state.lowercased() {
        case "merged":
            return ("Merged", "arrow.triangle.merge", .merged)
        case "closed":
            return ("Closed", "xmark.circle", .danger)
        default:
            if snapshot.isDraft {
                return ("Draft", "doc", .neutral)
            }
            return ("Open", "arrow.triangle.pull", .success)
        }
    }

    private func checksBadge(_ checksState: String) -> (label: String, icon: String, tone: RightPanelStatusBadge.Tone) {
        switch checksState.lowercased() {
        case "passing": ("CI passing", "checkmark.circle.fill", .success)
        case "failing": ("CI failing", "xmark.circle.fill", .danger)
        default: ("CI pending", "clock.fill", .warning)
        }
    }

    private func loadThreadFamily() async {
        guard !model.isMock, let conn = model.connection(forThreadID: threadID) else { return }
        isLoadingFamily = true
        defer { isLoadingFamily = false }
        if let result = try? await conn.getThreadFamily(threadId: threadID) {
            familyThreads = result.threads
        }
    }

    private func submitLinkPR() async {
        guard let parsed = RightPanelLogic.parsePullRequestURL(prURLInput) else { return }
        showingLinkPRPopover = false
        prURLInput = ""
        actionNotice = nil

        if model.isMock {
            var current = model.linkedPullRequests(forThreadID: threadID)
            let newLink = ThreadPullRequestLink(
                host: parsed.host,
                repository: parsed.repository,
                number: parsed.number,
                url: parsed.url,
                source: "manual",
                linkedAt: model.now
            )
            if !current.contains(where: { $0.id == newLink.id }) {
                current.insert(newLink, at: 0)
            }
            model.rightPanel.mockLinkedPRsByThreadID[threadID] = current
            return
        }

        guard let conn = model.connection(forThreadID: threadID) else {
            actionNotice = "Environment is not connected."
            return
        }
        do {
            _ = try await conn.linkPullRequest(
                threadId: threadID,
                host: parsed.host,
                repository: parsed.repository,
                number: parsed.number,
                url: parsed.url,
                source: "manual"
            )
        } catch {
            actionNotice = error.localizedDescription
        }
    }

    private func unlinkPullRequest(_ link: ThreadPullRequestLink) async {
        actionNotice = nil
        if model.isMock {
            var current = model.linkedPullRequests(forThreadID: threadID)
            current.removeAll { $0.id == link.id }
            model.rightPanel.mockLinkedPRsByThreadID[threadID] = current
            return
        }
        guard let conn = model.connection(forThreadID: threadID) else { return }
        do {
            _ = try await conn.unlinkPullRequest(
                threadId: threadID,
                host: link.host,
                repository: link.repository,
                number: link.number
            )
        } catch {
            actionNotice = error.localizedDescription
        }
    }

    private func unlinkIssue(_ issue: ThreadIssueLink) async {
        actionNotice = nil
        if model.isMock {
            var current = model.linkedIssues(forThreadID: threadID)
            current.removeAll { $0.id == issue.id }
            model.rightPanel.mockLinkedIssuesByThreadID[threadID] = current
            return
        }
        guard let conn = model.connection(forThreadID: threadID) else { return }
        do {
            _ = try await conn.unlinkIssue(
                threadId: threadID,
                tracker: issue.tracker,
                host: issue.host,
                scope: issue.scope,
                key: issue.key
            )
        } catch {
            actionNotice = error.localizedDescription
        }
    }
}
