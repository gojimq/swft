import SwftDesign
import SwiftUI

/// Calm in-window Settings screen in the main column, reached from the sidebar Settings row.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var tabs: [SettingsTabItem<SettingsSection>] {
        SettingsSection.allCases.map {
            SettingsTabItem(id: $0, title: $0.title, systemName: $0.systemName)
        }
    }

    var body: some View {
        @Bindable var settings = model.settings

        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header

                SettingsTabStrip(items: tabs, selection: $settings.section)

                if let error = settings.settingsError {
                    SettingsBanner(error, tone: .error) {
                        withAnimation(SwftMotion.resolve(SwftMotion.quick, reduceMotion: reduceMotion)) {
                            settings.settingsError = nil
                        }
                    }
                    .transition(.swftRise(reduceMotion: reduceMotion, distance: -6))
                }

                sectionContent(for: settings.section)
                    .id(settings.section)
                    .swftEntrance(reduceMotion: reduceMotion)
            }
            .frame(maxWidth: SwftLayout.contentMaxWidth, alignment: .leading)
            .padding(.horizontal, 32)
            .padding(.top, SwftLayout.titlebarHeight + 22)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.automatic)
        .scrollEdgeSoftIfAvailable()
        .ignoresSafeArea(.container, edges: .top)
        .overlay(alignment: .top) {
            LinearGradient(
                stops: [
                    .init(color: SwftColor.canvas, location: 0.72),
                    .init(color: SwftColor.canvas.opacity(0), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: SwftLayout.titlebarHeight + 14)
            .allowsHitTesting(false)
        }
        .onAppear { settings.onSettingsAppear() }
        .onDisappear { settings.onSettingsDisappear() }
        .onChange(of: model.serverStatus.isConnected) { _, connected in
            if connected { settings.ensureServerSettingsLoaded() }
        }
        .animation(SwftMotion.resolve(SwftMotion.spring, reduceMotion: reduceMotion), value: settings.settingsError)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Settings")
                .font(SwftType.title)
                .foregroundStyle(SwftColor.textPrimary)
            SwapText(model.settings.section.subtitle)
                .font(SwftType.label)
                .foregroundStyle(SwftColor.textSecondary)
        }
    }

    @ViewBuilder
    private func sectionContent(for section: SettingsSection) -> some View {
        switch section {
        case .general:
            GeneralSettingsSection()
        case .providers:
            ProvidersSettingsSection()
        case .connections:
            ConnectionsSettingsView()
        case .notifications:
            NotificationsSettingsSection()
        case .about:
            AboutSettingsSection()
        }
    }
}
