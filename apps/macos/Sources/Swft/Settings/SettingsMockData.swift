import Foundation
import SwftKit

/// Sample settings & provider state for SwiftUI previews and `-SwftMock` screenshot captures.
enum SettingsMockData {
    static let now = Date(timeIntervalSince1970: 1_800_000_000)

    static let serverSettings = ServerSettings(
        defaultModelSelection: ModelSelection(
            instanceId: "claudeAgent",
            model: "opus",
            options: [.string("effort", "high")]
        ),
        defaultRuntimeMode: .fullAccess,
        defaultThreadEnvMode: .local,
        responseStreamingMode: .paragraph,
        keepAwakeWhileAgentsWork: true,
        continueThreadsAfterServerUpdate: true,
        sidebarAutoSettleOnMerge: true,
        enableProviderUpdateChecks: true,
        idleCompaction: .onReturn,
        providerInstances: [
            "claudeAgent": ProviderInstanceConfig(
                driver: "claudeAgent",
                enabled: true,
                config: .object(["binaryPath": .string("claude")])
            ),
            "codex": ProviderInstanceConfig(
                driver: "codex",
                enabled: true,
                config: .object(["binaryPath": .string("codex")])
            ),
            "codex_personal": ProviderInstanceConfig(
                driver: "codex",
                displayName: "Codex Personal",
                accentColor: "#8b5cf6",
                enabled: true,
                config: .object(["setupMode": .string("managed")])
            ),
            "cursor": ProviderInstanceConfig(
                driver: "cursor",
                enabled: true
            ),
            "opencode": ProviderInstanceConfig(
                driver: "opencode",
                enabled: true
            ),
            "antigravity": ProviderInstanceConfig(
                driver: "antigravity",
                enabled: true,
                config: .object(["authMethod": .string("oauth-personal")])
            ),
            "pi": ProviderInstanceConfig(
                driver: "pi",
                enabled: false
            ),
        ]
    )

    static let providers: [ServerProvider] = [
        ServerProvider(
            instanceId: "claudeAgent",
            driver: "claudeAgent",
            displayName: "Claude",
            supportedRuntimeModes: RuntimeMode.allCases,
            enabled: true,
            installed: true,
            version: "2.1.48",
            status: .ready,
            auth: ServerProviderAuth(status: .authenticated, label: "Claude Max", email: "jim@example.com", canLogout: false),
            checkedAt: now,
            models: [
                ServerProviderModel(slug: "opus", name: "Claude Opus 5.5", shortName: "Opus 5.5", isDefault: true),
                ServerProviderModel(slug: "sonnet", name: "Claude Sonnet 5.5", shortName: "Sonnet 5.5"),
                ServerProviderModel(slug: "haiku", name: "Claude Haiku 5.5", shortName: "Haiku 5.5"),
                ServerProviderModel(slug: "fable", name: "Claude Fable 5.2", shortName: "Fable 5.2", badge: "new"),
            ],
            setup: ServerProviderSetup(canAuthenticate: false, canInstall: false)
        ),
        ServerProvider(
            instanceId: "codex",
            driver: "codex",
            displayName: "Codex",
            supportedRuntimeModes: RuntimeMode.allCases,
            enabled: true,
            installed: true,
            version: "0.52.0",
            status: .ready,
            auth: ServerProviderAuth(status: .authenticated, label: "ChatGPT Pro", email: "jim@work.dev", canLogout: true),
            checkedAt: now,
            models: [
                ServerProviderModel(slug: "gpt-6.1", name: "GPT-6.1", badge: "new", isDefault: true),
                ServerProviderModel(slug: "gpt-6-luna", name: "GPT-6 Luna"),
            ],
            setup: ServerProviderSetup(canAuthenticate: true, canInstall: true)
        ),
        ServerProvider(
            instanceId: "codex_personal",
            driver: "codex",
            displayName: "Codex Personal",
            accentColor: "#8b5cf6",
            supportedRuntimeModes: RuntimeMode.allCases,
            enabled: true,
            installed: true,
            version: "0.52.0",
            status: .ready,
            auth: ServerProviderAuth(status: .authenticated, label: "ChatGPT Plus", email: "jim@example.com", canLogout: true),
            checkedAt: now,
            models: [
                ServerProviderModel(slug: "gpt-6.1", name: "GPT-6.1", isDefault: true),
                ServerProviderModel(slug: "gpt-6-astra", name: "GPT-6 Astra"),
            ],
            setup: ServerProviderSetup(canAuthenticate: true, canInstall: false)
        ),
        ServerProvider(
            instanceId: "cursor",
            driver: "cursor",
            displayName: "Cursor",
            enabled: true,
            installed: true,
            version: "1.4.2",
            status: .ready,
            auth: ServerProviderAuth(status: .authenticated, label: "Cursor Pro", email: "jim@work.dev", canLogout: true),
            checkedAt: now,
            models: [
                ServerProviderModel(slug: "composer", name: "Composer 2", isDefault: true),
            ],
            setup: ServerProviderSetup(canAuthenticate: true, canInstall: false)
        ),
        ServerProvider(
            instanceId: "opencode",
            driver: "opencode",
            displayName: "OpenCode",
            enabled: true,
            installed: true,
            version: "0.9.4",
            status: .ready,
            auth: ServerProviderAuth(status: .unknown),
            checkedAt: now,
            models: [
                ServerProviderModel(slug: "openrouter/deepseek-v4", name: "DeepSeek V4", subProvider: "OpenRouter"),
                ServerProviderModel(slug: "openrouter/kimi-k3", name: "Kimi K3", subProvider: "OpenRouter", badge: "new"),
            ],
            subProviders: [
                ServerProviderSubProvider(name: "OpenRouter"),
                ServerProviderSubProvider(name: "Anthropic API", unavailableReason: "No API key"),
            ],
            setup: ServerProviderSetup(canAuthenticate: false, canInstall: false)
        ),
        ServerProvider(
            instanceId: "antigravity",
            driver: "antigravity",
            displayName: "Antigravity",
            enabled: true,
            installed: true,
            version: "agy_acp_server_20261120_1200",
            status: .warning,
            auth: ServerProviderAuth(status: .unauthenticated, type: "oauth-personal", label: "Google account"),
            checkedAt: now,
            models: [],
            setup: ServerProviderSetup(canAuthenticate: true, canInstall: true)
        ),
        ServerProvider(
            instanceId: "pi",
            driver: "pi",
            displayName: "Pi",
            enabled: false,
            installed: false,
            status: .disabled,
            auth: ServerProviderAuth(status: .unknown),
            checkedAt: now,
            models: [],
            setup: ServerProviderSetup(canAuthenticate: false, canInstall: false)
        ),
    ]

    static let environment = ExecutionEnvironmentDescriptor(
        environmentId: "mock-local-env",
        label: "Jim’s MacBook Pro",
        platform: ExecutionEnvironmentPlatform(os: "darwin", arch: "arm64", machine: "laptop"),
        serverVersion: "0.1.14",
        orchestrationProtocolVersion: 2
    )
}
