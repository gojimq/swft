import SwftDesign
import SwiftUI

struct NotificationsSettingsSection: View {
    @Environment(AppModel.self) private var model

    private var settings: SettingsController { model.settings }

    var body: some View {
        @Bindable var controller = model.settings

        VStack(alignment: .leading, spacing: 20) {
            SettingsSectionCard(
                "Alerts",
                footer: "Stored locally on this Mac."
            ) {
                SettingsPickerRow(
                    "Thread notifications",
                    description: "System alerts and sound when a background thread finishes, fails, or needs input or approval.",
                    statusNote: controller.notificationStatusNote,
                    selection: controller.notificationMode,
                    options: NotificationModePreference.allCases.map {
                        SettingsChoiceOption(value: $0, label: $0.label)
                    },
                    isModified: controller.notificationMode != .off,
                    onReset: { controller.selectNotificationMode(.off) }
                ) { next in
                    controller.selectNotificationMode(next)
                }

                SettingsRowDivider()

                SettingsRow(
                    "macOS permission",
                    description: controller.notificationPermission.statusText
                ) {
                    HStack(spacing: 8) {
                        if controller.notificationMode.includesSound {
                            SettingsPillButton("Test sound", systemName: "speaker.wave.2", variant: .secondary) {
                                controller.playTestNotificationSound()
                            }
                        }
                        if controller.notificationPermission == .denied {
                            SettingsPillButton("System Settings", systemName: "arrow.up.right", variant: .primary) {
                                controller.openSystemNotificationSettings()
                            }
                        } else {
                            SettingsStatusBadge(
                                controller.notificationPermission == .authorized ? "Allowed" : "Not set",
                                tone: controller.notificationPermission == .authorized ? .ready : .neutral
                            )
                        }
                    }
                }
            }

            SettingsSectionCard("Events") {
                SettingsToggleRow(
                    "Thread finishes",
                    description: "Notify when a background run completes or fails.",
                    isOn: $controller.notifyOnComplete,
                    disabled: controller.notificationMode == .off
                )

                SettingsRowDivider()

                SettingsToggleRow(
                    "Approval or input needed",
                    description: "Notify when an agent pauses waiting for your approval or answer.",
                    isOn: $controller.notifyOnAttention,
                    disabled: controller.notificationMode == .off
                )

                SettingsRowDivider()

                SettingsToggleRow(
                    "In-app notifications",
                    description: "Show a quiet banner when another thread finishes or needs you while Swft is focused.",
                    isOn: $controller.inAppNotificationsEnabled
                )
            }
        }
    }
}
