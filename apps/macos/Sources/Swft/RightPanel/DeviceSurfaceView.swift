import AppKit
import SwftDesign
import SwftKit
import SwiftUI

struct DeviceSurfaceView: View {
    @Environment(AppModel.self) private var model
    let threadID: String
    let tabID: String
    let deviceState: DeviceTabState

    @State private var serviceState: DeviceServiceState?
    @State private var isLoadingState = true
    @State private var isBusyAction = false
    @State private var errorMessage: String?

    @State private var screenshotImage: NSImage?
    @State private var isFetchingScreenshot = false
    @State private var isLivePollingEnabled = true
    @State private var deviceDetail: DeviceDetail?
    @State private var currentOrientationIndex = 0

    @State private var showingInputPopover = false
    @State private var openURLInput = ""
    @State private var sendTextInput = ""

    private static let orientations = ["portrait", "landscape_left", "portrait_upside_down", "landscape_right"]

    private var activeDevice: DeviceSummary? {
        guard let serviceState else { return nil }
        if let targetID = deviceState.deviceId {
            return serviceState.devices.first {
                $0.id == targetID && (deviceState.hostId == nil || $0.hostId == deviceState.hostId)
            }
        }
        // Check if this thread already has an active device session.
        if let session = serviceState.sessions.first(where: { $0.threadId == threadID }) {
            return serviceState.devices.first { $0.hostId == session.hostId && $0.id == session.deviceId }
        }
        return nil
    }

    private var pollingIdentity: String {
        guard isLivePollingEnabled, let active = activeDevice, active.booted else {
            return "paused"
        }
        return "\(threadID)::\(active.hostId)::\(active.id)::\(model.isMock)"
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider().overlay(SwftColor.borderSubtle)

            if let errorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(SwftColor.warning)
                    Text(errorMessage)
                        .font(SwftType.caption)
                        .foregroundStyle(SwftColor.textPrimary)
                        .lineLimit(2)
                    Spacer()
                    Button("Dismiss") { self.errorMessage = nil }
                        .buttonStyle(.plain)
                        .font(SwftType.captionStrong)
                        .foregroundStyle(SwftColor.accent)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(SwftColor.warningSoft)
            }

            if isLoadingState && serviceState == nil {
                VStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Discovering simulators & emulators…")
                        .font(SwftType.caption)
                        .foregroundStyle(SwftColor.textTertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let state = serviceState, (!state.onboardingCompleted || state.hostStatus == .disabled) {
                setupRequiredState(state)
            } else if let device = activeDevice {
                activeDeviceViewport(device: device, hubBasePath: serviceState?.hubBasePath ?? "/api/device-hub")
            } else if let state = serviceState {
                devicePickerList(state)
            } else {
                RightPanelEmptyState(
                    icon: "iphone.slash",
                    title: "Device service unavailable",
                    message: "Connect to a T3 Code environment with simulator or emulator support."
                ) {
                    Button("Retry") {
                        Task { await refreshDeviceList() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .background(SwftColor.canvas)
        .task(id: "\(threadID)::\(model.isMock)") {
            await subscribeToDeviceState()
        }
        // Only polls screenshots while this view is mounted, visible, and an active booted device is selected.
        .task(id: pollingIdentity) {
            guard pollingIdentity != "paused",
                  let device = activeDevice,
                  device.booted
            else { return }
            let hubBasePath = serviceState?.hubBasePath ?? "/api/device-hub"
            await fetchDetail(for: device)
            while !Task.isCancelled {
                await captureScreenshot(for: device, hubBasePath: hubBasePath)
                try? await Task.sleep(for: .milliseconds(1_200))
            }
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(spacing: 6) {
            if let device = activeDevice {
                Button {
                    model.rightPanel.updateDeviceTab(
                        tabID: tabID,
                        hostId: nil,
                        deviceId: nil,
                        platform: nil,
                        deviceName: nil,
                        for: threadID
                    )
                    screenshotImage = nil
                    deviceDetail = nil
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Devices")
                            .font(SwftType.caption)
                    }
                    .foregroundStyle(SwftColor.textSecondary)
                }
                .buttonStyle(.plain)

                Divider().frame(height: 14)

                Image(systemName: device.platform.symbolName)
                    .font(.system(size: 11.5))
                    .foregroundStyle(SwftColor.textSecondary)
                Text(device.name)
                    .font(SwftType.captionStrong)
                    .foregroundStyle(SwftColor.textPrimary)
                    .lineLimit(1)

                RightPanelStatusBadge(
                    device.booted ? "Booted" : "Off",
                    tone: device.booted ? .success : .neutral
                )
            } else {
                Text("Devices")
                    .font(SwftType.captionStrong)
                    .foregroundStyle(SwftColor.textPrimary)
            }

            Spacer(minLength: 4)

            if isBusyAction {
                ProgressView().controlSize(.mini)
            }

            if activeDevice != nil {
                IconButton(
                    isLivePollingEnabled ? "pause.circle" : "play.circle",
                    help: isLivePollingEnabled ? "Pause live refresh" : "Resume live refresh",
                    size: 26,
                    tint: isLivePollingEnabled ? SwftColor.accent : SwftColor.textSecondary
                ) {
                    isLivePollingEnabled.toggle()
                }
            }

            IconButton("arrow.clockwise", help: "Refresh devices", size: 26) {
                Task {
                    await refreshDeviceList()
                    if let device = activeDevice, device.booted {
                        await captureScreenshot(for: device, hubBasePath: serviceState?.hubBasePath ?? "/api/device-hub")
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .frame(height: RightPanelMetrics.subHeaderHeight)
        .background(SwftColor.surface)
    }

    // MARK: - Setup State

    private func setupRequiredState(_ state: DeviceServiceState) -> some View {
        RightPanelEmptyState(
            icon: "iphone.gen3",
            title: "Enable Device Support",
            message: state.hostStatusDetail ?? "Turn on T3 Code's device service on this environment to boot and view iOS Simulators and Android Emulators."
        ) {
            Button("Enable Device Support") {
                Task { await enableDeviceSupport() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(isBusyAction)
        }
    }

    // MARK: - Device Picker List

    private func devicePickerList(_ state: DeviceServiceState) -> some View {
        Group {
            if state.devices.isEmpty {
                RightPanelEmptyState(
                    icon: "iphone",
                    title: "No simulators or emulators found",
                    message: "Install Xcode Simulators or Android AVDs on this environment, then refresh."
                ) {
                    Button("Refresh") {
                        Task { await refreshDeviceList() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        let booting = state.bootingDevices.filter { $0.threadId == threadID }
                        if !booting.isEmpty {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text("Booting \(booting.map(\.name).joined(separator: ", "))…")
                                    .font(SwftType.caption)
                                    .foregroundStyle(SwftColor.textSecondary)
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: SwftRadius.s).fill(SwftColor.surfaceMuted))
                        }

                        let hostLookup = Dictionary(uniqueKeysWithValues: state.hosts.map { ($0.id, $0.label) })
                        let grouped = Dictionary(grouping: state.devices, by: \.hostId)
                        let sortedHostIDs = grouped.keys.sorted { lhs, rhs in
                            if lhs == "local" { return true }
                            if rhs == "local" { return false }
                            return (hostLookup[lhs] ?? lhs) < (hostLookup[rhs] ?? rhs)
                        }

                        ForEach(sortedHostIDs, id: \.self) { hostId in
                            let devices = (grouped[hostId] ?? []).sorted { lhs, rhs in
                                if lhs.booted != rhs.booted { return lhs.booted }
                                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                            }
                            VStack(alignment: .leading, spacing: 6) {
                                Text((hostLookup[hostId] ?? hostId).uppercased())
                                    .font(SwftType.micro)
                                    .foregroundStyle(SwftColor.textTertiary)
                                ForEach(devices, id: \.compositeKey) { device in
                                    deviceRow(device)
                                }
                            }
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func deviceRow(_ device: DeviceSummary) -> some View {
        HStack(spacing: 10) {
            Image(systemName: device.platform.symbolName)
                .font(.system(size: 14))
                .foregroundStyle(device.booted ? SwftColor.accent : SwftColor.textSecondary)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(device.name)
                        .font(SwftType.captionStrong)
                        .foregroundStyle(SwftColor.textPrimary)
                        .lineLimit(1)
                    if device.booted {
                        RightPanelStatusBadge("Booted", tone: .success)
                    }
                }
                Text("\(device.platform.displayName)\(device.version.isEmpty ? "" : " · \(device.version)")")
                    .font(.system(size: 11))
                    .foregroundStyle(SwftColor.textTertiary)
            }

            Spacer(minLength: 6)

            if device.booted {
                IconButton("power", help: "Shut down device", size: 24, tint: SwftColor.textTertiary) {
                    Task { await shutdown(device) }
                }
            }

            Button(device.booted ? "Open" : "Boot") {
                Task { await openDevice(device) }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(isBusyAction)
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

    // MARK: - Live Device Viewport

    private func activeDeviceViewport(device: DeviceSummary, hubBasePath: String) -> some View {
        VStack(spacing: 0) {
            if let app = deviceDetail?.foregroundApp {
                HStack(spacing: 6) {
                    Image(systemName: "app.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(SwftColor.textTertiary)
                    Text(app.name ?? app.id)
                        .font(SwftType.monoSmall)
                        .foregroundStyle(SwftColor.textSecondary)
                        .lineLimit(1)
                    Spacer()
                    if let appearance = deviceDetail?.settings.appearance {
                        RightPanelStatusBadge(appearance.capitalized, tone: .neutral)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(SwftColor.surface.opacity(0.6))
                Divider().overlay(SwftColor.borderSubtle)
            }

            GeometryReader { geo in
                ZStack {
                    if !device.booted {
                        RightPanelEmptyState(
                            icon: device.platform.symbolName,
                            title: "\(device.name) is powered off",
                            message: "Boot this device to stream screenshots and send actions."
                        ) {
                            Button("Boot Device") {
                                Task { await openDevice(device) }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(isBusyAction)
                        }
                    } else if let screenshotImage {
                        let aspect = screenshotImage.size.height > 0
                            ? screenshotImage.size.width / screenshotImage.size.height
                            : 9.0 / 19.5
                        let maxW = max(160, geo.size.width - 32)
                        let maxH = max(200, geo.size.height - 28)
                        let fittedWidth = min(maxW, maxH * aspect)
                        let fittedHeight = fittedWidth / aspect

                        Image(nsImage: screenshotImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: fittedWidth, height: fittedHeight)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(SwftColor.border, lineWidth: 1.5)
                            )
                            .shadow(color: SwftColor.shadow, radius: 12, y: 4)
                            .contentShape(Rectangle())
                            .onTapGesture { location in
                                let nx = Double(location.x / max(1, fittedWidth))
                                let ny = Double(location.y / max(1, fittedHeight))
                                Task {
                                    await sendTap(device: device, hubBasePath: hubBasePath, x: nx, y: ny)
                                }
                            }
                            .help("Click anywhere on screen to tap")
                    } else {
                        VStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Capturing screen…")
                                .font(SwftType.caption)
                                .foregroundStyle(SwftColor.textTertiary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(SwftColor.codeBackground)

            Divider().overlay(SwftColor.borderSubtle)
            actionToolbar(device: device, hubBasePath: hubBasePath)
        }
    }

    private func actionToolbar(device: DeviceSummary, hubBasePath: String) -> some View {
        HStack(spacing: 6) {
            IconButton("camera", help: "Capture screenshot now", size: 28) {
                Task { await captureScreenshot(for: device, hubBasePath: hubBasePath) }
            }
            .disabled(!device.booted || isFetchingScreenshot)

            IconButton("house", help: "Home button", size: 28) {
                Task { await pressHardwareButton(.home, device: device, hubBasePath: hubBasePath) }
            }
            .disabled(!device.booted)

            if device.platform == .android {
                IconButton("chevron.backward", help: "Back button", size: 28) {
                    Task { await pressHardwareButton(.back, device: device, hubBasePath: hubBasePath) }
                }
                .disabled(!device.booted)
            }

            IconButton("rotate.right", help: "Rotate orientation", size: 28) {
                Task { await rotateDevice(device) }
            }
            .disabled(!device.booted)

            IconButton("iphone.radiowaves.left.and.right", help: "Shake gesture", size: 28) {
                Task { await performAction(.shake(hostId: device.hostId, deviceId: device.id), device: device, hubBasePath: hubBasePath) }
            }
            .disabled(!device.booted)

            let isDark = deviceDetail?.settings.appearance == "dark"
            IconButton(isDark ? "sun.max" : "moon", help: isDark ? "Switch to light mode" : "Switch to dark mode", size: 28) {
                Task {
                    await performAction(
                        .setAppearance(hostId: device.hostId, deviceId: device.id, value: isDark ? "light" : "dark"),
                        device: device,
                        hubBasePath: hubBasePath
                    )
                }
            }
            .disabled(!device.booted)

            IconButton("keyboard", help: "Open URL or send text", size: 28) {
                showingInputPopover = true
            }
            .disabled(!device.booted)
            .popover(isPresented: $showingInputPopover, arrowEdge: .top) {
                deviceInputPopover(device: device, hubBasePath: hubBasePath)
            }

            Spacer()

            IconButton("power", help: "Close & shut down device", size: 28, tint: SwftColor.danger) {
                Task { await closeDevice(device, shutdown: true) }
            }
            .disabled(isBusyAction)
        }
        .padding(.horizontal, 10)
        .frame(height: 38)
        .background(SwftColor.surface)
    }

    private func deviceInputPopover(device: DeviceSummary, hubBasePath: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Open URL on device")
                    .font(SwftType.captionStrong)
                    .foregroundStyle(SwftColor.textPrimary)
                HStack(spacing: 6) {
                    TextField("https://example.com or myapp://", text: $openURLInput)
                        .textFieldStyle(.roundedBorder)
                        .font(SwftType.caption)
                    Button("Open") {
                        let url = openURLInput.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !url.isEmpty else { return }
                        openURLInput = ""
                        showingInputPopover = false
                        Task {
                            await performAction(
                                .openUrl(hostId: device.hostId, deviceId: device.id, url: url),
                                device: device,
                                hubBasePath: hubBasePath
                            )
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }

            if device.platform == .android {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Text("Send text")
                        .font(SwftType.captionStrong)
                        .foregroundStyle(SwftColor.textPrimary)
                    HStack(spacing: 6) {
                        TextField("Type text to send…", text: $sendTextInput)
                            .textFieldStyle(.roundedBorder)
                            .font(SwftType.caption)
                        Button("Send") {
                            let text = sendTextInput
                            guard !text.isEmpty else { return }
                            sendTextInput = ""
                            showingInputPopover = false
                            Task { await sendText(text, device: device, hubBasePath: hubBasePath) }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
        }
        .padding(14)
        .frame(width: 290)
    }

    // MARK: - Device RPCs & Polling

    private func subscribeToDeviceState() async {
        isLoadingState = true
        if model.isMock {
            let mockState = RightPanelMockData.deviceState(for: threadID)
            serviceState = mockState
            isLoadingState = false
            syncActiveDeviceTab(from: mockState)
            return
        }

        guard let conn = model.connection(forThreadID: threadID) else {
            isLoadingState = false
            return
        }

        if let listed = try? await conn.listDevices(DeviceListInput(inspectOnly: false)) {
            serviceState = listed
            isLoadingState = false
            syncActiveDeviceTab(from: listed)
        }

        let stream = conn.subscribeDeviceState()
        do {
            for try await snapshot in stream {
                guard !Task.isCancelled else { break }
                serviceState = snapshot
                isLoadingState = false
                syncActiveDeviceTab(from: snapshot)
            }
        } catch {
            if !Task.isCancelled && serviceState == nil {
                errorMessage = error.localizedDescription
                isLoadingState = false
            }
        }
    }

    private func syncActiveDeviceTab(from state: DeviceServiceState) {
        guard deviceState.deviceId == nil,
              let session = state.sessions.first(where: { $0.threadId == threadID }),
              let device = state.devices.first(where: { $0.hostId == session.hostId && $0.id == session.deviceId })
        else { return }
        model.rightPanel.updateDeviceTab(
            tabID: tabID,
            hostId: device.hostId,
            deviceId: device.id,
            platform: device.platform,
            deviceName: device.name,
            for: threadID
        )
    }

    private func refreshDeviceList() async {
        if model.isMock {
            serviceState = RightPanelMockData.deviceState(for: threadID)
            return
        }
        guard let conn = model.connection(forThreadID: threadID) else { return }
        isBusyAction = true
        defer { isBusyAction = false }
        do {
            serviceState = try await conn.listDevices()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func enableDeviceSupport() async {
        guard !model.isMock, let conn = model.connection(forThreadID: threadID) else { return }
        isBusyAction = true
        defer { isBusyAction = false }
        do {
            serviceState = try await conn.configureDevices(
                DeviceConfigureInput(enabled: true, onboardingCompleted: true)
            )
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func openDevice(_ device: DeviceSummary) async {
        isBusyAction = true
        errorMessage = nil
        defer { isBusyAction = false }

        if model.isMock {
            if let state = serviceState {
                let updatedDevices = state.devices.map { candidate in
                    candidate.compositeKey == device.compositeKey
                        ? DeviceSummary(
                            hostId: candidate.hostId,
                            id: candidate.id,
                            platform: candidate.platform,
                            name: candidate.name,
                            version: candidate.version,
                            booted: true,
                            physical: candidate.physical
                        )
                        : candidate
                }
                let newSession = DeviceSession(
                    threadId: threadID,
                    hostId: device.hostId,
                    deviceId: device.id,
                    platform: device.platform,
                    openedAt: SwftJSON.formatISO8601(Date())
                )
                serviceState = DeviceServiceState(
                    hostStatus: state.hostStatus,
                    hostStatuses: state.hostStatuses,
                    hosts: state.hosts,
                    devices: updatedDevices,
                    sessions: [newSession],
                    onboardingCompleted: true,
                    agentAccessEnabled: true,
                    hubBasePath: state.hubBasePath,
                    revision: state.revision + 1
                )
            }
            model.rightPanel.updateDeviceTab(
                tabID: tabID,
                hostId: device.hostId,
                deviceId: device.id,
                platform: device.platform,
                deviceName: device.name,
                for: threadID
            )
            return
        }

        guard let conn = model.connection(forThreadID: threadID) else { return }
        do {
            let session = try await conn.openDevice(
                DeviceOpenInput(
                    threadId: threadID,
                    hostId: device.hostId,
                    deviceId: device.id,
                    platform: device.platform,
                    boot: true
                )
            )
            model.rightPanel.updateDeviceTab(
                tabID: tabID,
                hostId: session.hostId,
                deviceId: session.deviceId,
                platform: session.platform,
                deviceName: device.name,
                for: threadID
            )
            serviceState = try? await conn.listDevices()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func closeDevice(_ device: DeviceSummary, shutdown: Bool) async {
        isBusyAction = true
        defer { isBusyAction = false }
        if model.isMock {
            model.rightPanel.updateDeviceTab(
                tabID: tabID,
                hostId: nil,
                deviceId: nil,
                platform: nil,
                deviceName: nil,
                for: threadID
            )
            screenshotImage = nil
            return
        }
        guard let conn = model.connection(forThreadID: threadID) else { return }
        do {
            try await conn.closeDevice(
                DeviceCloseInput(
                    threadId: threadID,
                    hostId: device.hostId,
                    deviceId: device.id,
                    shutdown: shutdown
                )
            )
            model.rightPanel.updateDeviceTab(
                tabID: tabID,
                hostId: nil,
                deviceId: nil,
                platform: nil,
                deviceName: nil,
                for: threadID
            )
            screenshotImage = nil
            deviceDetail = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func shutdown(_ device: DeviceSummary) async {
        isBusyAction = true
        defer { isBusyAction = false }
        if model.isMock { return }
        guard let conn = model.connection(forThreadID: threadID) else { return }
        do {
            try await conn.shutdownDevice(
                DeviceShutdownInput(hostId: device.hostId, deviceId: device.id, platform: device.platform)
            )
            serviceState = try? await conn.listDevices()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func fetchDetail(for device: DeviceSummary) async {
        if model.isMock {
            deviceDetail = DeviceDetail(
                hostId: device.hostId,
                deviceId: device.id,
                settings: DeviceSettings(appearance: "dark"),
                foregroundApp: DeviceForegroundApp(id: "codes.t3.mobile", name: "T3 Code Mobile", version: "1.0")
            )
            return
        }
        guard let conn = model.connection(forThreadID: threadID) else { return }
        if let detail = try? await conn.getDeviceDetail(hostId: device.hostId, deviceId: device.id) {
            deviceDetail = detail
        }
    }

    private func captureScreenshot(for device: DeviceSummary, hubBasePath: String) async {
        guard !isFetchingScreenshot else { return }
        isFetchingScreenshot = true
        defer { isFetchingScreenshot = false }

        if model.isMock {
            let png = RightPanelMockData.mockImagePNGData(title: device.name)
            screenshotImage = NSImage(data: png)
            return
        }
        guard let conn = model.connection(forThreadID: threadID) else { return }
        do {
            let png = try await conn.fetchDeviceScreenshot(
                hubBasePath: hubBasePath,
                hostId: device.hostId,
                deviceId: device.id,
                platform: device.platform
            )
            if let img = NSImage(data: png) {
                screenshotImage = img
            }
        } catch {
            // Keep last valid frame during transient hub glitches.
            if screenshotImage == nil {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func performAction(_ action: DeviceActionInput, device: DeviceSummary, hubBasePath: String) async {
        if model.isMock {
            if case .setAppearance(_, _, let value) = action {
                deviceDetail = DeviceDetail(
                    hostId: device.hostId,
                    deviceId: device.id,
                    settings: DeviceSettings(appearance: value),
                    foregroundApp: deviceDetail?.foregroundApp
                )
            }
            return
        }
        guard let conn = model.connection(forThreadID: threadID) else { return }
        do {
            deviceDetail = try await conn.performDeviceAction(action)
            try? await Task.sleep(for: .milliseconds(250))
            await captureScreenshot(for: device, hubBasePath: hubBasePath)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func rotateDevice(_ device: DeviceSummary) async {
        currentOrientationIndex = (currentOrientationIndex + 1) % Self.orientations.count
        let next = Self.orientations[currentOrientationIndex]
        await performAction(
            .setOrientation(hostId: device.hostId, deviceId: device.id, value: next),
            device: device,
            hubBasePath: serviceState?.hubBasePath ?? "/api/device-hub"
        )
    }

    private func sendTap(device: DeviceSummary, hubBasePath: String, x: Double, y: Double) async {
        if model.isMock { return }
        guard let conn = model.connection(forThreadID: threadID) else { return }
        do {
            try await conn.sendDeviceTap(
                hubBasePath: hubBasePath,
                hostId: device.hostId,
                deviceId: device.id,
                platform: device.platform,
                x: x,
                y: y
            )
            try? await Task.sleep(for: .milliseconds(250))
            await captureScreenshot(for: device, hubBasePath: hubBasePath)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func pressHardwareButton(_ button: DeviceHardwareButton, device: DeviceSummary, hubBasePath: String) async {
        if model.isMock { return }
        guard let conn = model.connection(forThreadID: threadID) else { return }
        do {
            try await conn.sendDeviceHardwareButton(
                hubBasePath: hubBasePath,
                hostId: device.hostId,
                deviceId: device.id,
                platform: device.platform,
                button: button
            )
            try? await Task.sleep(for: .milliseconds(250))
            await captureScreenshot(for: device, hubBasePath: hubBasePath)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func sendText(_ text: String, device: DeviceSummary, hubBasePath: String) async {
        if model.isMock { return }
        guard let conn = model.connection(forThreadID: threadID) else { return }
        do {
            try await conn.sendDeviceText(
                hubBasePath: hubBasePath,
                hostId: device.hostId,
                deviceId: device.id,
                platform: device.platform,
                text: text
            )
            try? await Task.sleep(for: .milliseconds(250))
            await captureScreenshot(for: device, hubBasePath: hubBasePath)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
