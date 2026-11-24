import Foundation
import SwftDesign
import SwftKit
import SwiftUI

/// Maps server provider identities (`driver`, `instanceId`, `iconUrl`, `acpAgentId`) onto `SwftDesign`'s provider icons.
extension SwftAdapters {
    /// Returns the provider driver identifier to carry into view state, preserving the exact server `driver`
    /// when present and falling back to `instanceId` when the provider isn't in the config snapshot yet.
    static func providerDriverIdentifier(driver: String?, instanceId: String) -> String {
        if let trimmed = driver?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty {
            return trimmed
        }
        return instanceId.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func resolvedProviderIcon(
        driver: String?,
        instanceId: String = "",
        acpAgentId: String? = nil,
        iconUrl: String? = nil,
        displayName: String? = nil
    ) -> ResolvedProviderIcon {
        ProviderIconKind.resolve(
            driver: driver,
            acpAgentID: acpAgentId,
            iconURL: iconUrl,
            instanceID: instanceId,
            name: displayName
        )
    }

    static func resolvedProviderIcon(for provider: ServerProvider) -> ResolvedProviderIcon {
        resolvedProviderIcon(
            driver: provider.driver,
            instanceId: provider.instanceId,
            iconUrl: provider.iconUrl,
            displayName: provider.displayName
        )
    }

    static func resolvedProviderIcon(for harness: PickerHarness) -> ResolvedProviderIcon {
        resolvedProviderIcon(
            driver: harness.driver,
            instanceId: harness.id,
            acpAgentId: harness.acpAgentId,
            iconUrl: harness.iconUrl,
            displayName: harness.label
        )
    }

    static func resolvedProviderIcon(for thread: ThreadSummary) -> ResolvedProviderIcon {
        resolvedProviderIcon(
            driver: thread.providerDriver ?? thread.provider.driverIdentifier,
            iconUrl: thread.providerIconUrl,
            displayName: thread.providerLabel
        )
    }
}

extension ProviderKind {
    /// Canonical server driver identifier corresponding to this coarse `ProviderKind`.
    var driverIdentifier: String {
        switch self {
        case .claude: "claudeAgent"
        case .codex: "codex"
        case .cursor: "cursor"
        case .opencode: "opencode"
        case .gemini: "antigravity"
        case .other: ""
        }
    }

    var iconKind: ProviderIconKind {
        switch self {
        case .claude: .claude
        case .codex: .openai
        case .cursor: .cursor
        case .opencode: .opencode
        case .gemini: .antigravity
        case .other: .generic
        }
    }
}
