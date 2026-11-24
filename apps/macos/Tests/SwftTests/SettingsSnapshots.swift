import AppKit
import SwftDesign
import SwiftUI
import Testing
@testable import Swft

/// Offscreen screenshots of the Settings screen sections and signed-out model picker deep-link state.
/// Skipped unless `SWFT_SNAPSHOT_DIR` is set:
///
///     SWFT_SNAPSHOT_DIR=/tmp/shots swift test --filter SettingsSnapshots
@MainActor
@Suite("SettingsSnapshots", .enabled(if: ProcessInfo.processInfo.environment["SWFT_SNAPSHOT_DIR"] != nil))
struct SettingsSnapshots {
    @Test(arguments: ["light", "dark"])
    func general(appearance: String) throws {
        let model = AppModel.mock()
        model.openSettings(section: .general)
        try Snapshots.capture(model, appearance: appearance, name: "settings-general-\(appearance)")
    }

    @Test(arguments: ["light", "dark"])
    func providers(appearance: String) throws {
        let model = AppModel.mock()
        model.openSettings(section: .providers)
        try Snapshots.capture(model, appearance: appearance, name: "settings-providers-\(appearance)")
    }

    @Test(arguments: ["light", "dark"])
    func providersExpanded(appearance: String) throws {
        let model = AppModel.mock()
        model.openSettings(section: .providers, providerID: "codex")
        try Snapshots.capture(model, appearance: appearance, name: "settings-providers-expanded-\(appearance)")
    }

    @Test(arguments: ["light", "dark"])
    func providersSignedOutExpanded(appearance: String) throws {
        let model = AppModel.mock()
        model.openSettings(section: .providers, providerID: "antigravity")
        try Snapshots.capture(model, appearance: appearance, name: "settings-providers-signedout-\(appearance)")
    }

    @Test(arguments: ["light", "dark"])
    func connections(appearance: String) throws {
        let model = AppModel.mock()
        model.openSettings(section: .connections)
        try Snapshots.capture(model, appearance: appearance, name: "settings-connections-\(appearance)")
    }

    @Test(arguments: ["light", "dark"])
    func notifications(appearance: String) throws {
        let model = AppModel.mock()
        model.openSettings(section: .notifications)
        try Snapshots.capture(model, appearance: appearance, name: "settings-notifications-\(appearance)")
    }

    @Test(arguments: ["light", "dark"])
    func about(appearance: String) throws {
        let model = AppModel.mock()
        model.openSettings(section: .about)
        try Snapshots.capture(model, appearance: appearance, name: "settings-about-\(appearance)")
    }

    @Test func pickerSignedOutDeepLink() throws {
        let model = AppModel.mock()
        model.destination = .thread(MockData.threadDetail.summary.id)
        model.toggleModelPicker()
        model.modelPicker?.selectGroup("antigravity", in: ModelPickerLogic.groups(model.pickerCatalog.harnesses))
        try Snapshots.capture(model, appearance: "light", name: "picker-signed-out-settings-light")
    }
}
