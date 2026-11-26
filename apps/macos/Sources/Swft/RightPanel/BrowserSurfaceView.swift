import AppKit
import Observation
import SwftDesign
import SwftKit
import SwiftUI
import WebKit

/// Keeps `WKWebView` instances alive per browser tab ID across tab switches so pages don't reload.
@MainActor
final class BrowserControllerPool {
    static let shared = BrowserControllerPool()
    private var controllers: [String: BrowserTabController] = [:]

    func controller(
        for tabID: String,
        onNavigationChange: @escaping @MainActor (_ urlString: String, _ title: String?) -> Void
    ) -> BrowserTabController {
        if let existing = controllers[tabID] {
            existing.onNavigationChange = onNavigationChange
            return existing
        }
        let created = BrowserTabController(onNavigationChange: onNavigationChange)
        controllers[tabID] = created
        return created
    }

    func remove(tabID: String) {
        controllers.removeValue(forKey: tabID)?.teardown()
    }
}

@MainActor
@Observable
final class BrowserTabController: NSObject, WKNavigationDelegate {
    let webView: WKWebView
    var currentURLString: String = ""
    var pageTitle: String?
    var canGoBack: Bool = false
    var canGoForward: Bool = false
    var isLoading: Bool = false
    var estimatedProgress: Double = 0
    var loadError: String?

    @ObservationIgnored var onNavigationChange: (@MainActor (_ urlString: String, _ title: String?) -> Void)?
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []

    init(onNavigationChange: (@MainActor (_ urlString: String, _ title: String?) -> Void)? = nil) {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.preferences.isElementFullscreenEnabled = true
        self.webView = WKWebView(frame: .zero, configuration: config)
        self.onNavigationChange = onNavigationChange
        super.init()
        self.webView.navigationDelegate = self
        self.webView.allowsBackForwardNavigationGestures = true
        self.webView.allowsMagnification = true
        installObservations()
    }

    func load(_ url: URL) {
        loadError = nil
        currentURLString = url.absoluteString
        webView.load(URLRequest(url: url))
    }

    func goBack() {
        webView.goBack()
    }

    func goForward() {
        webView.goForward()
    }

    func reload() {
        loadError = nil
        webView.reload()
    }

    func stopLoading() {
        webView.stopLoading()
    }

    func teardown() {
        observations.removeAll()
        webView.navigationDelegate = nil
        webView.stopLoading()
    }

    private func installObservations() {
        observations = [
            webView.observe(\.url, options: [.new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in
                    guard let self, let nextURL = self.webView.url?.absoluteString else { return }
                    self.currentURLString = nextURL
                    self.onNavigationChange?(nextURL, self.pageTitle)
                }
            },
            webView.observe(\.title, options: [.new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    let cleaned = self.webView.title?.trimmingCharacters(in: .whitespacesAndNewlines)
                    self.pageTitle = cleaned?.isEmpty == false ? cleaned : nil
                    if !self.currentURLString.isEmpty {
                        self.onNavigationChange?(self.currentURLString, self.pageTitle)
                    }
                }
            },
            webView.observe(\.canGoBack, options: [.new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.canGoBack = self.webView.canGoBack
                }
            },
            webView.observe(\.canGoForward, options: [.new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.canGoForward = self.webView.canGoForward
                }
            },
            webView.observe(\.isLoading, options: [.new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.isLoading = self.webView.isLoading
                }
            },
            webView.observe(\.estimatedProgress, options: [.new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.estimatedProgress = self.webView.estimatedProgress
                }
            },
        ]
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        handleLoadFailure(error)
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        handleLoadFailure(error)
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor [weak self] in
            self?.loadError = nil
        }
    }

    private nonisolated func handleLoadFailure(_ error: any Error) {
        let nsError = error as NSError
        // Ignore user-cancelled navigations (e.g. clicking a new link mid-load).
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
            return
        }
        let message = error.localizedDescription
        Task { @MainActor [weak self] in
            self?.loadError = message
        }
    }
}

private struct SwftWebViewRepresentable: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

struct BrowserSurfaceView: View {
    @Environment(AppModel.self) private var model
    let threadID: String
    let tabID: String
    let browserState: BrowserTabState

    @State private var addressText: String = ""
    @State private var serverSessions: [PreviewSessionSnapshot] = []
    @State private var discoveredServers: [DiscoveredLocalServer] = []
    @State private var statusBanner: String?
    @State private var didSeedInitialURL = false
    @FocusState private var addressFocused: Bool

    private var controller: BrowserTabController {
        BrowserControllerPool.shared.controller(for: tabID) { urlString, title in
            model.rightPanel.updateBrowserTab(
                tabID: tabID,
                urlString: urlString,
                pageTitle: title,
                for: threadID
            )
            if !addressFocused {
                addressText = urlString
            }
        }
    }

    private var activeURL: URL? {
        if !controller.currentURLString.isEmpty {
            return URL(string: controller.currentURLString)
        }
        return RightPanelLogic.normalizeBrowserURL(browserState.urlString)
    }

    var body: some View {
        VStack(spacing: 0) {
            chromeBar
            if controller.isLoading {
                ProgressView(value: max(0.05, controller.estimatedProgress), total: 1.0)
                    .progressViewStyle(.linear)
                    .tint(SwftColor.accent)
                    .frame(height: 2)
            } else {
                Divider().overlay(SwftColor.borderSubtle)
            }

            if let statusBanner {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(SwftColor.textSecondary)
                    Text(statusBanner)
                        .font(SwftType.caption)
                        .foregroundStyle(SwftColor.textSecondary)
                        .lineLimit(2)
                    Spacer()
                    Button("Dismiss") { self.statusBanner = nil }
                        .buttonStyle(.plain)
                        .font(SwftType.captionStrong)
                        .foregroundStyle(SwftColor.accent)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(SwftColor.surfaceMuted)
            }

            if activeURL == nil {
                browserStartPage
            } else {
                ZStack(alignment: .top) {
                    SwftWebViewRepresentable(webView: controller.webView)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if let loadError = controller.loadError {
                        loadErrorOverlay(loadError)
                    }
                }
            }
        }
        .background(SwftColor.canvas)
        .onAppear {
            seedInitialNavigationIfNeeded()
        }
        .onChange(of: browserState.urlString) { _, newValue in
            if !newValue.isEmpty,
               newValue != controller.currentURLString,
               let normalized = RightPanelLogic.normalizeBrowserURL(newValue)
            {
                addressText = normalized.absoluteString
                controller.load(normalized)
            }
        }
        .task(id: "\(threadID)::\(model.isMock)") {
            await loadPreviewSessionsAndSubscribe()
        }
    }

    // MARK: - Chrome Bar

    private var chromeBar: some View {
        HStack(spacing: 6) {
            IconButton("chevron.left", help: "Back", size: 26) {
                controller.goBack()
            }
            .disabled(!controller.canGoBack)
            .opacity(controller.canGoBack ? 1 : 0.4)

            IconButton("chevron.right", help: "Forward", size: 26) {
                controller.goForward()
            }
            .disabled(!controller.canGoForward)
            .opacity(controller.canGoForward ? 1 : 0.4)

            IconButton(
                controller.isLoading ? "xmark" : "arrow.clockwise",
                help: controller.isLoading ? "Stop loading" : "Reload",
                size: 26
            ) {
                if controller.isLoading {
                    controller.stopLoading()
                } else {
                    controller.reload()
                }
            }
            .disabled(activeURL == nil)
            .opacity(activeURL == nil ? 0.4 : 1)

            HStack(spacing: 6) {
                Image(systemName: activeURL?.scheme == "https" ? "lock.fill" : "globe")
                    .font(.system(size: 10.5))
                    .foregroundStyle(SwftColor.textTertiary)

                TextField("Enter URL or localhost:3000…", text: $addressText)
                    .textFieldStyle(.plain)
                    .font(SwftType.caption)
                    .foregroundStyle(SwftColor.textPrimary)
                    .focused($addressFocused)
                    .onSubmit {
                        navigateToAddressInput()
                    }

                if !addressText.isEmpty && addressFocused {
                    Button {
                        addressText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(SwftColor.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: SwftRadius.s, style: .continuous)
                    .fill(SwftColor.surfaceMuted)
            )
            .overlay(
                RoundedRectangle(cornerRadius: SwftRadius.s, style: .continuous)
                    .strokeBorder(addressFocused ? SwftColor.accent.opacity(0.6) : SwftColor.borderSubtle, lineWidth: 1)
            )

            if !serverSessions.isEmpty {
                Menu {
                    Section("Server preview tabs") {
                        ForEach(serverSessions) { session in
                            let label = session.navStatus.title ?? session.navStatus.url ?? "Blank preview"
                            Button {
                                if let url = session.navStatus.url {
                                    navigate(to: url, serverPreviewTabId: session.tabId)
                                }
                            } label: {
                                Label(label, systemImage: "globe")
                            }
                        }
                    }
                    if let currentServerTab = browserState.serverPreviewTabId {
                        Divider()
                        Button("Close server preview session", role: .destructive) {
                            Task { await closeServerSession(tabId: currentServerTab) }
                        }
                    }
                } label: {
                    HStack(spacing: 3) {
                        Circle()
                            .fill(SwftColor.success)
                            .frame(width: 6, height: 6)
                        Text("\(serverSessions.count)")
                            .font(SwftType.micro)
                            .monospacedDigit()
                            .foregroundStyle(SwftColor.textSecondary)
                    }
                    .padding(.horizontal, 6)
                    .frame(height: 24)
                    .background(Capsule().fill(SwftColor.surfaceMuted))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Agent-opened preview sessions")
            }

            IconButton("arrow.up.right.square", help: "Open in external browser", size: 26) {
                if let url = activeURL {
                    NSWorkspace.shared.open(url)
                }
            }
            .disabled(activeURL == nil)
            .opacity(activeURL == nil ? 0.4 : 1)
        }
        .padding(.horizontal, 8)
        .frame(height: RightPanelMetrics.subHeaderHeight)
        .background(SwftColor.surface)
    }

    // MARK: - Start Page & Error Overlay

    private var browserStartPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Browser")
                        .font(SwftType.headline)
                        .foregroundStyle(SwftColor.textPrimary)
                    Text("Enter any URL above, or open a running dev server or agent preview session.")
                        .font(SwftType.caption)
                        .foregroundStyle(SwftColor.textTertiary)
                }

                if !serverSessions.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("ACTIVE PREVIEW SESSIONS")
                            .font(SwftType.micro)
                            .foregroundStyle(SwftColor.textTertiary)
                        ForEach(serverSessions) { session in
                            serverSessionRow(session)
                        }
                    }
                }

                if !discoveredServers.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("RUNNING LOCAL SERVERS")
                            .font(SwftType.micro)
                            .foregroundStyle(SwftColor.textTertiary)
                        ForEach(discoveredServers) { server in
                            Button {
                                navigate(to: server.url)
                            } label: {
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(SwftColor.success)
                                        .frame(width: 7, height: 7)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(server.url)
                                            .font(SwftType.captionStrong)
                                            .foregroundStyle(SwftColor.textPrimary)
                                        if let proc = server.processName {
                                            Text("\(proc) · port \(server.port)")
                                                .font(SwftType.caption)
                                                .foregroundStyle(SwftColor.textTertiary)
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: "arrow.right")
                                        .font(.system(size: 11))
                                        .foregroundStyle(SwftColor.textTertiary)
                                }
                                .padding(10)
                                .background(
                                    RoundedRectangle(cornerRadius: SwftRadius.s, style: .continuous)
                                        .fill(SwftColor.surface)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: SwftRadius.s, style: .continuous)
                                        .strokeBorder(SwftColor.borderSubtle, lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("QUICK LAUNCH")
                        .font(SwftType.micro)
                        .foregroundStyle(SwftColor.textTertiary)
                    HStack(spacing: 8) {
                        quickURLChip("localhost:3000")
                        quickURLChip("localhost:5173")
                        quickURLChip("localhost:8080")
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func serverSessionRow(_ session: PreviewSessionSnapshot) -> some View {
        let urlString = session.navStatus.url ?? ""
        let title = session.navStatus.title ?? (urlString.isEmpty ? "Blank preview" : urlString)
        return HStack(spacing: 10) {
            Image(systemName: "globe")
                .font(.system(size: 13))
                .foregroundStyle(SwftColor.accent)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(SwftType.captionStrong)
                    .foregroundStyle(SwftColor.textPrimary)
                    .lineLimit(1)
                if !urlString.isEmpty {
                    Text(urlString)
                        .font(SwftType.monoSmall)
                        .foregroundStyle(SwftColor.textTertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            if !urlString.isEmpty {
                Button("Open") {
                    navigate(to: urlString, serverPreviewTabId: session.tabId)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            IconButton("xmark", help: "Close preview session", size: 22) {
                Task { await closeServerSession(tabId: session.tabId) }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: SwftRadius.s, style: .continuous)
                .fill(SwftColor.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: SwftRadius.s, style: .continuous)
                .strokeBorder(SwftColor.borderSubtle, lineWidth: 1)
        )
    }

    private func quickURLChip(_ hostPort: String) -> some View {
        Button {
            navigate(to: hostPort)
        } label: {
            Text(hostPort)
                .font(SwftType.monoSmall)
                .foregroundStyle(SwftColor.textSecondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: SwftRadius.s, style: .continuous)
                        .fill(SwftColor.surfaceMuted)
                )
        }
        .buttonStyle(.plain)
    }

    private func loadErrorOverlay(_ message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(SwftColor.warning)
            Text("Unable to load page")
                .font(SwftType.labelStrong)
                .foregroundStyle(SwftColor.textPrimary)
            Text(message)
                .font(SwftType.caption)
                .foregroundStyle(SwftColor.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
            HStack(spacing: 8) {
                Button("Retry") {
                    controller.reload()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                if let url = activeURL {
                    Button("Open Externally") {
                        NSWorkspace.shared.open(url)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: SwftRadius.m, style: .continuous)
                .fill(SwftColor.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: SwftRadius.m, style: .continuous)
                .strokeBorder(SwftColor.borderSubtle, lineWidth: 1)
        )
        .padding(24)
    }

    // MARK: - Actions & Preview RPCs

    private func seedInitialNavigationIfNeeded() {
        guard !didSeedInitialURL else { return }
        didSeedInitialURL = true
        if !controller.currentURLString.isEmpty {
            addressText = controller.currentURLString
            return
        }
        if !browserState.urlString.isEmpty,
           let url = RightPanelLogic.normalizeBrowserURL(browserState.urlString)
        {
            addressText = url.absoluteString
            controller.load(url)
        }
    }

    private func navigateToAddressInput() {
        guard let url = RightPanelLogic.normalizeBrowserURL(addressText) else {
            statusBanner = "Enter a valid http(s) URL or host such as localhost:5173."
            return
        }
        statusBanner = nil
        addressFocused = false
        navigate(to: url.absoluteString)
    }

    private func navigate(to rawURL: String, serverPreviewTabId: String? = nil) {
        guard let url = RightPanelLogic.normalizeBrowserURL(rawURL) else { return }
        addressText = url.absoluteString
        model.rightPanel.updateBrowserTab(
            tabID: tabID,
            urlString: url.absoluteString,
            serverPreviewTabId: serverPreviewTabId,
            for: threadID
        )
        controller.load(url)
    }

    private func loadPreviewSessionsAndSubscribe() async {
        if model.isMock {
            serverSessions = RightPanelMockData.previewSessions(for: threadID)
            discoveredServers = [
                DiscoveredLocalServer(host: "localhost", port: 5173, url: "http://localhost:5173", processName: "vite", pid: 4210),
            ]
            return
        }

        guard let conn = model.connection(forThreadID: threadID) else { return }
        if let listed = try? await conn.listPreviewSessions(threadId: threadID) {
            serverSessions = listed.sessions
        }

        async let previewStreamTask: Void = listenToPreviewEvents(conn)
        async let localServersTask: Void = listenToDiscoveredLocalServers(conn)
        _ = await (previewStreamTask, localServersTask)
    }

    private func listenToPreviewEvents(_ conn: ServerConnection) async {
        let stream = conn.subscribePreviewEvents()
        do {
            for try await event in stream {
                guard !Task.isCancelled else { break }
                applyPreviewEvent(event)
            }
        } catch {
            // Non-fatal: WKWebView continues working standalone.
        }
    }

    private func listenToDiscoveredLocalServers(_ conn: ServerConnection) async {
        let stream = conn.subscribeDiscoveredLocalServers()
        do {
            for try await list in stream {
                guard !Task.isCancelled else { break }
                discoveredServers = list.servers
            }
        } catch {
            // Non-fatal.
        }
    }

    private func applyPreviewEvent(_ event: PreviewEvent) {
        switch event {
        case .opened(let eventThreadId, _, _, let snapshot),
             .navigated(let eventThreadId, _, _, let snapshot),
             .resized(let eventThreadId, _, _, let snapshot):
            guard eventThreadId == threadID else { return }
            if let index = serverSessions.firstIndex(where: { $0.tabId == snapshot.tabId }) {
                serverSessions[index] = snapshot
            } else {
                serverSessions.append(snapshot)
            }
        case .closed(let eventThreadId, let closedTabId, _):
            guard eventThreadId == threadID else { return }
            serverSessions.removeAll { $0.tabId == closedTabId }
        case .failed, .unknown:
            break
        }
    }

    private func closeServerSession(tabId: String) async {
        if model.isMock {
            serverSessions.removeAll { $0.tabId == tabId }
            return
        }
        guard let conn = model.connection(forThreadID: threadID) else { return }
        do {
            try await conn.closePreviewSession(threadId: threadID, tabId: tabId)
            serverSessions.removeAll { $0.tabId == tabId }
        } catch {
            statusBanner = error.localizedDescription
        }
    }
}
