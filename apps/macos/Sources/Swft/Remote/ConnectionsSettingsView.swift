import AppKit
import SwftDesign
import SwftKit
import SwiftUI

/// Settings → Connections section.
/// Exact merge seam type (`ConnectionsSettingsView` with a no-arg `init()`) consumed by the Settings screen.
struct ConnectionsSettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var showAddForm = false
    @State private var repairingEnvironmentID: String?
    @State private var renamingEnvironmentID: String?
    @State private var renameDraft = ""
    @State private var pendingRemoval: RemoteEnvironmentItem?
    @State private var statusBannerError: String?

    private let previewInvite: PairingInvite?

    init() {
        self.previewInvite = nil
    }

    init(previewInvite: PairingInvite?) {
        self.previewInvite = previewInvite
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            if let statusBannerError {
                ActionErrorBanner(message: statusBannerError) {
                    withAnimation(SwftMotion.resolve(SwftMotion.quick, reduceMotion: reduceMotion)) {
                        self.statusBannerError = nil
                    }
                }
                .transition(.swftRise(reduceMotion: reduceMotion, distance: -6))
            }

            serversSection

            ShareThisMacCard(initialInvite: previewInvite)
        }
        .animation(SwftMotion.resolve(SwftMotion.spring, reduceMotion: reduceMotion), value: model.remoteEnvironments.map(\.id))
        .animation(SwftMotion.resolve(SwftMotion.disclosure, reduceMotion: reduceMotion), value: showAddForm)
        .animation(SwftMotion.resolve(SwftMotion.disclosure, reduceMotion: reduceMotion), value: repairingEnvironmentID)
        .animation(SwftMotion.resolve(SwftMotion.quick, reduceMotion: reduceMotion), value: statusBannerError)
        .alert(
            "Remove server",
            isPresented: Binding(
                get: { pendingRemoval != nil },
                set: { if !$0 { pendingRemoval = nil } }
            ),
            presenting: pendingRemoval
        ) { target in
            Button("Remove", role: .destructive) {
                pendingRemoval = nil
                Task {
                    do {
                        try await model.removeRemoteEnvironment(id: target.id)
                    } catch {
                        statusBannerError = error.localizedDescription
                    }
                }
            }
            Button("Cancel", role: .cancel) {
                pendingRemoval = nil
            }
        } message: { target in
            Text("Remove \"\(target.label)\" from Swft? Your threads stay on that server, and you can pair again any time.")
        }
    }

    // MARK: - Servers / Saved Environments

    private var serversSection: some View {
        SettingsCardGroup(
            title: "Servers",
            trailing: {
                if !showAddForm {
                    ConnectionsPillButton("Add server", systemName: "plus", prominent: false) {
                        withAnimation(SwftMotion.resolve(SwftMotion.disclosure, reduceMotion: reduceMotion)) {
                            repairingEnvironmentID = nil
                            showAddForm = true
                        }
                    }
                }
            }
        ) {
            let environments = model.remoteEnvironments
            VStack(spacing: 0) {
                ForEach(Array(environments.enumerated()), id: \.element.id) { index, env in
                    if index > 0 {
                        Divider()
                            .overlay(SwftColor.borderSubtle)
                            .padding(.horizontal, 16)
                    }
                    environmentRow(env)
                        .transition(.swftRise(reduceMotion: reduceMotion, distance: -6))
                }

                SwftDisclosure(isExpanded: showAddForm) {
                    Divider()
                        .overlay(SwftColor.borderSubtle)
                        .padding(.horizontal, 16)
                    RemoteConnectForm(
                        expectedEnvironmentID: nil,
                        submitLabel: "Connect",
                        onConnected: {
                            withAnimation(SwftMotion.resolve(SwftMotion.disclosure, reduceMotion: reduceMotion)) {
                                showAddForm = false
                            }
                        },
                        onCancel: {
                            withAnimation(SwftMotion.resolve(SwftMotion.disclosure, reduceMotion: reduceMotion)) {
                                showAddForm = false
                            }
                        }
                    )
                    .padding(16)
                    .background(SwftColor.surfaceMuted.opacity(0.55))
                }
                SwftDisclosure(isExpanded: !showAddForm && environments.allSatisfy(\.isLocal)) {
                    Divider()
                        .overlay(SwftColor.borderSubtle)
                        .padding(.horizontal, 16)
                    HStack(spacing: 10) {
                        Image(systemName: "network")
                            .font(.system(size: 13))
                            .foregroundStyle(SwftColor.textTertiary)
                        Text("Connect another Mac or server over Cloudflare Tunnel, Tailscale, or LAN. Paste a pairing link or enter its HTTPS URL and one-time token.")
                            .font(SwftType.caption)
                            .foregroundStyle(SwftColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
        }
    }

    @ViewBuilder
    private func environmentRow(_ env: RemoteEnvironmentItem) -> some View {
        let isRepairing = repairingEnvironmentID == env.id
        let isRenaming = renamingEnvironmentID == env.id

        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                // Status dot + machine icon
                ZStack(alignment: .bottomTrailing) {
                    Image(systemName: env.machineSymbol)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(SwftColor.textSecondary)
                        .frame(width: 30, height: 30)
                        .background(
                            RoundedRectangle(cornerRadius: SwftRadius.s, style: .continuous)
                                .fill(SwftColor.surfaceMuted)
                        )
                    Circle()
                        .fill(statusDotColor(for: env.phase))
                        .frame(width: 8, height: 8)
                        .overlay(Circle().strokeBorder(SwftColor.surface, lineWidth: 1.5))
                        .offset(x: 2, y: 2)
                        .animation(SwftMotion.resolve(SwftMotion.quick, reduceMotion: reduceMotion), value: env.phase)
                }

                VStack(alignment: .leading, spacing: 2) {
                    if isRenaming {
                        HStack(spacing: 6) {
                            TextField("Server name", text: $renameDraft)
                                .textFieldStyle(.plain)
                                .font(SwftType.labelStrong)
                                .foregroundStyle(SwftColor.textPrimary)
                                .padding(.horizontal, 8)
                                .frame(height: 26)
                                .background(
                                    RoundedRectangle(cornerRadius: SwftRadius.s, style: .continuous)
                                        .fill(SwftColor.surfaceMuted)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: SwftRadius.s, style: .continuous)
                                        .strokeBorder(SwftColor.accent.opacity(0.6))
                                )
                                .onSubmit { commitRename(for: env) }
                                .onExitCommand { renamingEnvironmentID = nil }
                                .frame(maxWidth: 220)

                            ConnectionsPillButton("Save", prominent: true) {
                                commitRename(for: env)
                            }
                            ConnectionsPillButton("Cancel", prominent: false) {
                                renamingEnvironmentID = nil
                            }
                        }
                    } else {
                        HStack(spacing: 7) {
                            Text(env.label)
                                .font(SwftType.labelStrong)
                                .foregroundStyle(SwftColor.textPrimary)
                                .lineLimit(1)
                            if env.isLocal {
                                Text("This Mac")
                                    .font(SwftType.micro)
                                    .foregroundStyle(SwftColor.accent)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(SwftColor.accentSoft))
                            }
                            Text(env.statusSummary)
                                .font(SwftType.caption)
                                .foregroundStyle(SwftColor.textTertiary)
                                .contentTransition(.interpolate)
                        }
                    }

                    if let url = env.url, !url.isEmpty {
                        Text(url)
                            .font(SwftType.monoSmall)
                            .foregroundStyle(SwftColor.textTertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    if let errorDetail = env.errorDetail, !env.phase.isConnected {
                        Text(errorDetail)
                            .font(SwftType.caption)
                            .foregroundStyle(SwftColor.danger)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 2)
                    }
                }

                Spacer(minLength: 8)

                if !isRenaming {
                    HStack(spacing: 4) {
                        if env.canReconnect {
                            ConnectionsPillButton("Reconnect", systemName: "arrow.clockwise", prominent: true) {
                                Task { await model.reconnectEnvironment(id: env.id) }
                            }
                        } else if env.phase.isConnected && !env.isLocal {
                            IconButton("arrow.clockwise", help: "Reconnect", size: 28) {
                                Task { await model.reconnectEnvironment(id: env.id) }
                            }
                        }

                        if env.canRename {
                            IconButton("pencil", help: "Rename server", size: 28) {
                                renameDraft = env.label
                                renamingEnvironmentID = env.id
                            }
                        }

                        if env.canRemove {
                            ConnectionsPillButton(isRepairing ? "Close" : "Re-pair", prominent: false) {
                                withAnimation(SwftMotion.resolve(SwftMotion.disclosure, reduceMotion: reduceMotion)) {
                                    repairingEnvironmentID = isRepairing ? nil : env.id
                                    if !isRepairing { showAddForm = false }
                                }
                            }
                            IconButton("trash", help: "Remove server", size: 28, tint: SwftColor.textTertiary) {
                                pendingRemoval = env
                            }
                        }
                    }
                }
            }

            SwftDisclosure(isExpanded: isRepairing) {
                Divider().overlay(SwftColor.borderSubtle)
                    .padding(.vertical, 12)
                RemoteConnectForm(
                    expectedEnvironmentID: env.id,
                    submitLabel: "Update",
                    onConnected: {
                        withAnimation(SwftMotion.resolve(SwftMotion.disclosure, reduceMotion: reduceMotion)) {
                            repairingEnvironmentID = nil
                        }
                    },
                    onCancel: {
                        withAnimation(SwftMotion.resolve(SwftMotion.disclosure, reduceMotion: reduceMotion)) {
                            repairingEnvironmentID = nil
                        }
                    }
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private func commitRename(for env: RemoteEnvironmentItem) {
        do {
            try model.renameRemoteEnvironment(id: env.id, customLabel: renameDraft)
            renamingEnvironmentID = nil
        } catch {
            statusBannerError = error.localizedDescription
        }
    }

    private func statusDotColor(for phase: RemoteEnvironmentPhase) -> Color {
        switch phase {
        case .connected: SwftColor.success
        case .connecting, .reconnecting: SwftColor.warning
        case .offline, .failed: SwftColor.danger
        }
    }
}

// MARK: - Add / Re-pair Form

private struct RemoteConnectForm: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let expectedEnvironmentID: String?
    let submitLabel: String
    let onConnected: () -> Void
    let onCancel: (() -> Void)?

    @State private var address = ""
    @State private var token = ""
    @State private var isConnecting = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                TextField(
                    "",
                    text: $address,
                    prompt: Text("Pairing link or server URL (e.g. https://swft-mini.example.com/pair#token=…)")
                        .foregroundStyle(SwftColor.placeholder)
                )
                .textFieldStyle(.plain)
                .font(SwftType.monoSmall)
                .foregroundStyle(SwftColor.textPrimary)
                .disabled(isConnecting)
                .padding(.horizontal, 11)
                .frame(height: 34)
                .background(
                    RoundedRectangle(cornerRadius: SwftRadius.m, style: .continuous)
                        .fill(SwftColor.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: SwftRadius.m, style: .continuous)
                        .strokeBorder(errorMessage != nil ? SwftColor.danger.opacity(0.6) : SwftColor.border)
                )
                .onChange(of: address) { _, _ in errorMessage = nil }
                .onSubmit { submit() }

                IconButton("doc.on.clipboard", help: "Paste pairing link from clipboard", size: 30) {
                    if let pasted = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !pasted.isEmpty
                    {
                        address = pasted
                        errorMessage = nil
                    }
                }
            }

            HStack(spacing: 8) {
                SecureField(
                    "",
                    text: $token,
                    prompt: Text("Pairing token (optional if included in link)")
                        .foregroundStyle(SwftColor.placeholder)
                )
                .textFieldStyle(.plain)
                .font(SwftType.monoSmall)
                .foregroundStyle(SwftColor.textPrimary)
                .disabled(isConnecting)
                .padding(.horizontal, 11)
                .frame(height: 34)
                .background(
                    RoundedRectangle(cornerRadius: SwftRadius.m, style: .continuous)
                        .fill(SwftColor.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: SwftRadius.m, style: .continuous)
                        .strokeBorder(SwftColor.border)
                )
                .onChange(of: token) { _, _ in errorMessage = nil }
                .onSubmit { submit() }

                ConnectionsPillButton(
                    isConnecting ? "Connecting…" : submitLabel,
                    systemName: isConnecting ? nil : "link",
                    prominent: true,
                    disabled: isConnecting || address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    action: submit
                )

                if let onCancel {
                    ConnectionsPillButton("Cancel", prominent: false, disabled: isConnecting, action: onCancel)
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(SwftType.caption)
                    .foregroundStyle(SwftColor.danger)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.swftRise(reduceMotion: reduceMotion, distance: -4))
            }
        }
        .animation(SwftMotion.resolve(SwftMotion.quick, reduceMotion: reduceMotion), value: errorMessage)
    }

    private func submit() {
        guard !isConnecting else { return }
        let trimmedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAddress.isEmpty else { return }

        isConnecting = true
        errorMessage = nil

        Task {
            do {
                _ = try await model.pairRemoteEnvironment(
                    address: trimmedAddress,
                    token: token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : token,
                    expectedEnvironmentId: expectedEnvironmentID
                )
                address = ""
                token = ""
                isConnecting = false
                onConnected()
            } catch {
                errorMessage = error.localizedDescription
                isConnecting = false
            }
        }
    }
}

// MARK: - Share This Mac (Cloudflare Tunnel, Tailscale/LAN & Pairing QR)

private struct ShareThisMacCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var tunnelNameDraft = ""
    @State private var publicURLDraft = ""
    @State private var invite: PairingInvite?

    init(initialInvite: PairingInvite? = nil) {
        self._invite = State(initialValue: initialInvite)
    }
    @State private var isMintingInvite = false
    @State private var inviteError: String?
    @State private var copiedField: CopiedField?
    @State private var copyResetTask: Task<Void, Never>?

    @State private var networkInfo = LocalNetworkInfo()
    @State private var isProbingNetwork = false
    @State private var tailscaleServeURL: String?
    @State private var tailscaleBusy = false
    @State private var tailscaleError: String?

    private enum CopiedField: Equatable {
        case localAddress
        case tunnelURL
        case tailscaleURL
        case pairingURL
        case token
    }

    private var tunnel: CloudflareTunnelController { model.tunnelController }

    private var activePublicHTTPSURL: String? {
        tunnel.status.activePublicUrl ?? tailscaleServeURL
    }

    /// Live-upgrades the displayed QR code and pairing link if a tunnel or Tailscale HTTPS URL starts after minting.
    private var effectiveInvite: PairingInvite? {
        guard let invite else { return nil }
        if let activePublic = activePublicHTTPSURL,
           let upgraded = invite.upgraded(toPublicBaseURL: activePublic)
        {
            return upgraded
        }
        return invite
    }

    private var localEndpointLabel: String? {
        model.localServerEndpointPort.map { "127.0.0.1:\($0)" }
    }

    var body: some View {
        SettingsCardGroup(
            title: "Share this Mac",
            trailing: {
                if let localEndpointLabel {
                    ConnectionsPillButton(
                        copiedField == .localAddress ? "Copied \(localEndpointLabel)" : localEndpointLabel,
                        systemName: copiedField == .localAddress ? "checkmark" : "doc.on.doc",
                        monospaced: true,
                        prominent: false
                    ) {
                        copy(localEndpointLabel, field: .localAddress, value: "http://\(localEndpointLabel)")
                    }
                }
            }
        ) {
            VStack(alignment: .leading, spacing: 0) {
                cloudflareTunnelSection
                Divider().overlay(SwftColor.borderSubtle).padding(.horizontal, 16)
                tailscaleAndLANSection
                Divider().overlay(SwftColor.borderSubtle).padding(.horizontal, 16)
                pairDeviceSection
            }
        }
        .onAppear {
            tunnelNameDraft = tunnel.status.tunnelName
            publicURLDraft = tunnel.status.publicUrl
            refreshNetwork()
            if tunnel.status.mode == .named && tunnel.namedTunnels.isEmpty {
                Task { await tunnel.refreshNamedTunnels() }
            }
        }
        .onChange(of: tunnel.status.tunnelName) { _, newValue in
            if tunnelNameDraft != newValue { tunnelNameDraft = newValue }
        }
        .onChange(of: tunnel.status.publicUrl) { _, newValue in
            if publicURLDraft != newValue { publicURLDraft = newValue }
        }
        .onDisappear {
            copyResetTask?.cancel()
        }
    }

    // MARK: Cloudflare Tunnel

    private var cloudflareTunnelSection: some View {
        let status = tunnel.status
        let isRunningOrStarting = status.phase == .running || status.phase == .starting

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 7) {
                        Text("Cloudflare Tunnel")
                            .font(SwftType.labelStrong)
                            .foregroundStyle(SwftColor.textPrimary)
                        HStack(spacing: 5) {
                            Circle()
                                .fill(tunnelDotColor(for: status.phase))
                                .frame(width: 7, height: 7)
                                .animation(SwftMotion.resolve(SwftMotion.quick, reduceMotion: reduceMotion), value: status.phase)
                            Text(status.phase.displayName)
                                .font(SwftType.caption)
                                .foregroundStyle(SwftColor.textTertiary)
                                .contentTransition(.interpolate)
                        }
                    }
                    Text("Expose this Mac over HTTPS so another Mac or iPhone can pair from anywhere.")
                        .font(SwftType.caption)
                        .foregroundStyle(SwftColor.textSecondary)
                }

                Spacer(minLength: 8)

                SegmentedToggle(
                    selection: Binding<CloudflareTunnelMode>(
                        get: { status.mode },
                        set: { setTunnelMode($0) }
                    ),
                    options: CloudflareTunnelMode.allCases.map { ($0, $0.displayName) }
                )
                .disabled(tunnel.isBusy)
            }

            if status.mode == .quick {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Starts a temporary trycloudflare.com HTTPS tunnel forwarding to \(localEndpointLabel ?? "127.0.0.1:3773").")
                        .font(SwftType.caption)
                        .foregroundStyle(SwftColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if !status.cloudflaredInstalled {
                        Text("Install cloudflared first (`brew install cloudflared`).")
                            .font(SwftType.caption)
                            .foregroundStyle(SwftColor.warning)
                    }

                    HStack(spacing: 8) {
                        if isRunningOrStarting {
                            ConnectionsPillButton("Stop tunnel", systemName: "stop.fill", prominent: false, disabled: tunnel.isBusy) {
                                Task { await tunnel.stop() }
                            }
                        } else {
                            ConnectionsPillButton(
                                "Start quick tunnel",
                                systemName: "play.fill",
                                prominent: true,
                                disabled: tunnel.isBusy || !status.cloudflaredInstalled
                            ) {
                                Task { await tunnel.start() }
                            }
                        }
                    }
                }
                .transition(.swftRise(reduceMotion: reduceMotion, distance: -4))
            }

            if status.mode == .named {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        Text("Tunnel name")
                            .font(SwftType.caption)
                            .foregroundStyle(SwftColor.textSecondary)
                            .frame(width: 112, alignment: .leading)

                        if !tunnel.namedTunnels.isEmpty {
                            Picker("", selection: Binding<String>(
                                get: { tunnel.status.tunnelName },
                                set: { setTunnelName($0) }
                            )) {
                                Text("Select a tunnel…").tag("")
                                if !tunnel.status.tunnelName.isEmpty,
                                   !tunnel.namedTunnels.contains(where: { $0.name == tunnel.status.tunnelName })
                                {
                                    Text(tunnel.status.tunnelName).tag(tunnel.status.tunnelName)
                                }
                                ForEach(tunnel.namedTunnels) { item in
                                    let suffix = item.connectionsCount > 0 ? " (\(item.connectionsCount) active)" : ""
                                    Text("\(item.name)\(suffix)").tag(item.name)
                                }
                            }
                            .labelsHidden()
                            .frame(maxWidth: 240)
                            .disabled(tunnel.isBusy)
                        } else {
                            TextField("my-mac-tunnel", text: $tunnelNameDraft)
                                .textFieldStyle(.plain)
                                .font(SwftType.monoSmall)
                                .padding(.horizontal, 10)
                                .frame(height: 30)
                                .frame(maxWidth: 240)
                                .background(RoundedRectangle(cornerRadius: SwftRadius.s, style: .continuous).fill(SwftColor.surfaceMuted))
                                .overlay(RoundedRectangle(cornerRadius: SwftRadius.s, style: .continuous).strokeBorder(SwftColor.border))
                                .onSubmit { Task { await tunnel.configure(tunnelName: tunnelNameDraft) } }
                        }

                        ConnectionsPillButton(
                            tunnel.isLoadingTunnels ? "Loading…" : "Refresh",
                            systemName: "arrow.clockwise",
                            prominent: false,
                            disabled: tunnel.isLoadingTunnels
                        ) {
                            Task { await tunnel.refreshNamedTunnels() }
                        }
                    }

                    HStack(spacing: 10) {
                        Text("Public HTTPS URL")
                            .font(SwftType.caption)
                            .foregroundStyle(SwftColor.textSecondary)
                            .frame(width: 112, alignment: .leading)

                        TextField("https://swft.example.com", text: $publicURLDraft)
                            .textFieldStyle(.plain)
                            .font(SwftType.monoSmall)
                            .padding(.horizontal, 10)
                            .frame(height: 30)
                            .frame(maxWidth: 280)
                            .background(RoundedRectangle(cornerRadius: SwftRadius.s, style: .continuous).fill(SwftColor.surfaceMuted))
                            .overlay(RoundedRectangle(cornerRadius: SwftRadius.s, style: .continuous).strokeBorder(SwftColor.border))
                            .onSubmit { Task { await tunnel.configure(publicUrl: publicURLDraft) } }
                    }

                    if !status.cloudflaredInstalled {
                        Text("Install cloudflared first (`brew install cloudflared`).")
                            .font(SwftType.caption)
                            .foregroundStyle(SwftColor.warning)
                    }

                    Text("Auto-starts when Swft launches and follows the local server port automatically.")
                        .font(SwftType.caption)
                        .foregroundStyle(SwftColor.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 8) {
                        if isRunningOrStarting {
                            ConnectionsPillButton("Stop tunnel", systemName: "stop.fill", prominent: false, disabled: tunnel.isBusy) {
                                Task { await tunnel.stop() }
                            }
                        } else {
                            ConnectionsPillButton(
                                "Start named tunnel",
                                systemName: "play.fill",
                                prominent: true,
                                disabled: tunnel.isBusy || !status.cloudflaredInstalled
                            ) {
                                Task {
                                    await tunnel.configure(publicUrl: publicURLDraft, tunnelName: tunnelNameDraft)
                                    if tunnel.status.error == nil {
                                        await tunnel.start()
                                    }
                                }
                            }
                        }
                    }
                }
                .transition(.swftRise(reduceMotion: reduceMotion, distance: -4))
            }

            if status.mode == .external {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Use an existing cloudflared daemon or reverse proxy pointing at \(localEndpointLabel ?? "127.0.0.1:3773").")
                        .font(SwftType.caption)
                        .foregroundStyle(SwftColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 8) {
                        TextField("https://swft.example.com", text: $publicURLDraft)
                            .textFieldStyle(.plain)
                            .font(SwftType.monoSmall)
                            .padding(.horizontal, 10)
                            .frame(height: 32)
                            .background(RoundedRectangle(cornerRadius: SwftRadius.s, style: .continuous).fill(SwftColor.surfaceMuted))
                            .overlay(RoundedRectangle(cornerRadius: SwftRadius.s, style: .continuous).strokeBorder(SwftColor.border))
                            .onSubmit { Task { await tunnel.configure(publicUrl: publicURLDraft) } }

                        ConnectionsPillButton("Apply", prominent: true, disabled: tunnel.isBusy) {
                            Task { await tunnel.configure(publicUrl: publicURLDraft) }
                        }
                    }
                }
                .transition(.swftRise(reduceMotion: reduceMotion, distance: -4))
            }

            if let activeURL = status.activePublicUrl {
                HStack(spacing: 10) {
                    Image(systemName: "globe")
                        .font(.system(size: 12))
                        .foregroundStyle(SwftColor.success)
                    Text(activeURL)
                        .font(SwftType.monoSmall)
                        .foregroundStyle(SwftColor.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                    Spacer(minLength: 8)
                    ConnectionsPillButton(
                        copiedField == .tunnelURL ? "Copied" : "Copy URL",
                        systemName: copiedField == .tunnelURL ? "checkmark" : "doc.on.doc",
                        prominent: false
                    ) {
                        copy(activeURL, field: .tunnelURL, value: activeURL)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: SwftRadius.m, style: .continuous).fill(SwftColor.surfaceMuted))
                .transition(.swftRise(reduceMotion: reduceMotion, distance: -4))
            }

            if let error = status.error {
                Text(error)
                    .font(SwftType.caption)
                    .foregroundStyle(SwftColor.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .animation(SwftMotion.resolve(SwftMotion.disclosure, reduceMotion: reduceMotion), value: status.mode)
        .animation(SwftMotion.resolve(SwftMotion.spring, reduceMotion: reduceMotion), value: status.activePublicUrl)
    }

    // MARK: Tailscale & LAN

    private var tailscaleAndLANSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Tailscale & Local Network")
                            .font(SwftType.labelStrong)
                            .foregroundStyle(SwftColor.textPrimary)
                        if networkInfo.tailscale.running {
                            Text("Connected")
                                .font(SwftType.caption)
                                .foregroundStyle(SwftColor.success)
                        }
                    }

                    if networkInfo.tailscale.running, let dns = networkInfo.tailscale.magicDNSName {
                        Text("Tailnet host: \(dns)")
                            .font(SwftType.monoSmall)
                            .foregroundStyle(SwftColor.textSecondary)
                    } else if networkInfo.tailscale.installed {
                        Text("Tailscale is installed but not running. Start Tailscale to publish over MagicDNS HTTPS.")
                            .font(SwftType.caption)
                            .foregroundStyle(SwftColor.textTertiary)
                    } else {
                        Text("Tailscale not detected on this Mac.")
                            .font(SwftType.caption)
                            .foregroundStyle(SwftColor.textTertiary)
                    }
                }

                Spacer(minLength: 8)

                if networkInfo.tailscale.running, let port = model.localServerEndpointPort {
                    if tailscaleServeURL != nil {
                        ConnectionsPillButton("Stop Serve", prominent: false, disabled: tailscaleBusy) {
                            stopTailscaleServe()
                        }
                    } else {
                        ConnectionsPillButton("Publish on Tailscale", systemName: "lock.shield", prominent: false, disabled: tailscaleBusy) {
                            startTailscaleServe(localPort: port)
                        }
                    }
                }

                IconButton("arrow.clockwise", help: "Refresh network status", size: 26) {
                    refreshNetwork()
                }
                .disabled(isProbingNetwork)
            }

            if let tailscaleServeURL {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(SwftColor.success)
                    Text(tailscaleServeURL)
                        .font(SwftType.monoSmall)
                        .foregroundStyle(SwftColor.textPrimary)
                        .textSelection(.enabled)
                    Spacer()
                    ConnectionsPillButton(
                        copiedField == .tailscaleURL ? "Copied" : "Copy",
                        systemName: copiedField == .tailscaleURL ? "checkmark" : "doc.on.doc",
                        prominent: false
                    ) {
                        copy(tailscaleServeURL, field: .tailscaleURL, value: tailscaleServeURL)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: SwftRadius.m, style: .continuous).fill(SwftColor.surfaceMuted))
            }

            if let tailscaleError {
                Text(tailscaleError)
                    .font(SwftType.caption)
                    .foregroundStyle(SwftColor.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !networkInfo.lanIPv4Addresses.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "wifi")
                        .font(.system(size: 11))
                        .foregroundStyle(SwftColor.textTertiary)
                    Text("LAN: \(networkInfo.lanIPv4Addresses.joined(separator: ", ")) · Bundled server listens on loopback only; use Cloudflare Tunnel or Tailscale for remote access.")
                        .font(SwftType.caption)
                        .foregroundStyle(SwftColor.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(16)
    }

    // MARK: Pair Another Device (QR & One-Time Token)

    private var pairDeviceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pair another device")
                        .font(SwftType.labelStrong)
                        .foregroundStyle(SwftColor.textPrimary)
                    Text("Scan a QR code from iPhone or paste a one-time pairing link on another Mac.")
                        .font(SwftType.caption)
                        .foregroundStyle(SwftColor.textSecondary)
                }

                Spacer(minLength: 8)

                if invite != nil {
                    ConnectionsPillButton("Hide", prominent: false) {
                        withAnimation(SwftMotion.resolve(SwftMotion.disclosure, reduceMotion: reduceMotion)) {
                            invite = nil
                            inviteError = nil
                        }
                    }
                }

                ConnectionsPillButton(
                    isMintingInvite ? "Generating…" : (invite != nil ? "Regenerate" : "Pair device (QR & Token)"),
                    systemName: invite != nil ? "arrow.clockwise" : "qrcode",
                    prominent: invite == nil,
                    disabled: isMintingInvite || !model.canCreatePairingInvite
                ) {
                    generateInvite()
                }
            }

            if !model.canCreatePairingInvite {
                Text("Start or connect the local server to mint a pairing link.")
                    .font(SwftType.caption)
                    .foregroundStyle(SwftColor.textTertiary)
            }

            if let inviteError {
                Text(inviteError)
                    .font(SwftType.caption)
                    .foregroundStyle(SwftColor.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let effectiveInvite {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 18) {
                        QRCodeView(value: effectiveInvite.pairingURL, size: 148)

                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 8) {
                                ConnectionsPillButton(
                                    copiedField == .pairingURL ? "Copied link" : "Copy pairing link",
                                    systemName: copiedField == .pairingURL ? "checkmark" : "link",
                                    prominent: true
                                ) {
                                    copy(effectiveInvite.pairingURL, field: .pairingURL, value: effectiveInvite.pairingURL)
                                }

                                ConnectionsPillButton(
                                    copiedField == .token ? "Copied token" : "Copy token",
                                    systemName: copiedField == .token ? "checkmark" : "key",
                                    prominent: false
                                ) {
                                    copy(effectiveInvite.token, field: .token, value: effectiveInvite.token)
                                }
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("One-time token")
                                    .font(SwftType.caption)
                                    .foregroundStyle(SwftColor.textTertiary)
                                Text(effectiveInvite.token)
                                    .font(SwftType.monoSmall)
                                    .foregroundStyle(SwftColor.textPrimary)
                                    .lineLimit(2)
                                    .truncationMode(.middle)
                                    .textSelection(.enabled)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 7)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(
                                        RoundedRectangle(cornerRadius: SwftRadius.s, style: .continuous)
                                            .fill(SwftColor.surface)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: SwftRadius.s, style: .continuous)
                                            .strokeBorder(SwftColor.borderSubtle)
                                    )
                            }

                            HStack(spacing: 6) {
                                Text(effectiveInvite.origin)
                                    .font(SwftType.monoSmall)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Text("·")
                                Text(RemoteLogic.formatInviteExpiry(effectiveInvite.expiresAt))
                                    .font(SwftType.caption)
                            }
                            .foregroundStyle(SwftColor.textTertiary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if effectiveInvite.isLoopback {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "info.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(SwftColor.warning)
                                .padding(.top, 1)
                            Text("Localhost links only work on this Mac. Enable Cloudflare Tunnel or Tailscale Serve above to pair another Mac or iPhone.")
                                .font(SwftType.caption)
                                .foregroundStyle(SwftColor.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: SwftRadius.m, style: .continuous)
                                .fill(SwftColor.warningSoft)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: SwftRadius.m, style: .continuous)
                                .strokeBorder(SwftColor.warningBorder)
                        )
                    }
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: SwftRadius.m, style: .continuous)
                        .fill(SwftColor.surfaceMuted.opacity(0.65))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: SwftRadius.m, style: .continuous)
                        .strokeBorder(SwftColor.borderSubtle)
                )
                .transition(.swftRise(reduceMotion: reduceMotion, distance: 8))
            }
        }
        .padding(16)
        .animation(SwftMotion.resolve(SwftMotion.disclosure, reduceMotion: reduceMotion), value: invite != nil)
    }

    // MARK: Actions

    private func setTunnelMode(_ mode: CloudflareTunnelMode) {
        Task { await tunnel.configure(mode: mode) }
    }

    private func setTunnelName(_ name: String) {
        tunnelNameDraft = name
        Task { await tunnel.configure(tunnelName: name) }
    }

    private func generateInvite() {
        isMintingInvite = true
        inviteError = nil
        Task {
            do {
                let minted = try await model.createHostPairingInvite(publicBaseURL: activePublicHTTPSURL)
                withAnimation(SwftMotion.resolve(SwftMotion.disclosure, reduceMotion: reduceMotion)) {
                    invite = minted
                }
            } catch {
                inviteError = error.localizedDescription
            }
            isMintingInvite = false
        }
    }

    private func refreshNetwork() {
        guard !isProbingNetwork else { return }
        isProbingNetwork = true
        Task {
            let info = await HostNetworkHelper.probeNetwork()
            networkInfo = info
            isProbingNetwork = false
        }
    }

    private func startTailscaleServe(localPort: Int) {
        tailscaleBusy = true
        tailscaleError = nil
        Task {
            do {
                let url = try await HostNetworkHelper.enableTailscaleServe(localPort: localPort)
                tailscaleServeURL = url
            } catch {
                tailscaleError = error.localizedDescription
            }
            tailscaleBusy = false
        }
    }

    private func stopTailscaleServe() {
        tailscaleBusy = true
        tailscaleError = nil
        Task {
            do {
                try await HostNetworkHelper.disableTailscaleServe()
                tailscaleServeURL = nil
            } catch {
                tailscaleError = error.localizedDescription
            }
            tailscaleBusy = false
        }
    }

    private func copy(_ display: String, field: CopiedField, value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        withAnimation(SwftMotion.resolve(SwftMotion.quick, reduceMotion: reduceMotion)) {
            copiedField = field
        }
        copyResetTask?.cancel()
        copyResetTask = Task {
            try? await Task.sleep(for: .seconds(1.8))
            guard !Task.isCancelled else { return }
            withAnimation(SwftMotion.resolve(SwftMotion.quick, reduceMotion: reduceMotion)) {
                if copiedField == field { copiedField = nil }
            }
        }
    }

    private func tunnelDotColor(for phase: CloudflareTunnelPhase) -> Color {
        switch phase {
        case .running: SwftColor.success
        case .starting: SwftColor.warning
        case .error: SwftColor.danger
        case .off: SwftColor.textTertiary.opacity(0.45)
        }
    }
}

// MARK: - Local Google-Style Card & Pill Helpers

private struct SettingsCardGroup<Trailing: View, Content: View>: View {
    let title: String
    let trailing: Trailing
    let content: Content

    init(
        title: String,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() },
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.trailing = trailing()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                Text(title)
                    .font(SwftType.sectionHeader)
                    .foregroundStyle(SwftColor.textSecondary)
                    .padding(.leading, 4)
                Spacer(minLength: 8)
                trailing
            }

            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: SwftRadius.l, style: .continuous)
                        .fill(SwftColor.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: SwftRadius.l, style: .continuous)
                        .strokeBorder(SwftColor.borderSubtle)
                )
                .shadow(color: SwftColor.shadow.opacity(0.45), radius: 8, y: 2)
        }
    }
}

private struct ConnectionsPillButton: View {
    let title: String
    let systemName: String?
    var monospaced: Bool = false
    var prominent: Bool = false
    var disabled: Bool = false
    let action: () -> Void

    init(
        _ title: String,
        systemName: String? = nil,
        monospaced: Bool = false,
        prominent: Bool = false,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemName = systemName
        self.monospaced = monospaced
        self.prominent = prominent
        self.disabled = disabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let systemName {
                    Image(systemName: systemName)
                        .font(.system(size: 11, weight: .semibold))
                        .contentTransition(.symbolEffect(.replace))
                }
                Text(title)
                    .font(monospaced ? SwftType.monoSmall : (prominent ? SwftType.captionStrong : SwftType.caption))
                    .lineLimit(1)
            }
            .foregroundStyle(prominent ? SwftColor.accent : SwftColor.textPrimary)
            .padding(.horizontal, 11)
            .frame(height: 28)
            .background(
                Capsule().fill(prominent ? SwftColor.accentSoft : SwftColor.surfaceMuted)
            )
            .overlay(
                Capsule().strokeBorder(prominent ? SwftColor.accent.opacity(0.22) : SwftColor.borderSubtle)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(HoverFillStyle(shape: Capsule(), pressScale: 0.96))
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
    }
}
