import Foundation

/// Canonical vector marks bundled in SwftDesign for providers, sub-providers, and neutral fallback.
public enum ProviderIconKind: String, CaseIterable, Hashable, Sendable {
    case claude
    case openai
    case cursor
    case grok
    case opencode
    case antigravity
    case kiro
    case pi
    case muse
    case fx
    case acpRegistry
    case anthropic
    case openrouter
    case ollama
    case generic

    /// True for marks whose original artwork carries brand color (Claude, Antigravity, Kiro, Muse Code);
    /// false for monochrome marks that tint to the surrounding text color.
    public var hasBrandColor: Bool {
        switch self {
        case .claude, .antigravity, .kiro, .muse:
            return true
        case .openai, .cursor, .grok, .opencode, .pi, .fx, .acpRegistry, .anthropic, .openrouter, .ollama, .generic:
            return false
        }
    }
}

/// Resolution result for a provider identity, distinguishing built-in marks from ACP Registry agents
/// that may supply an allowlisted CDN icon URL.
public enum ResolvedProviderIcon: Equatable, Hashable, Sendable {
    case mark(ProviderIconKind)
    case acpRegistry(iconURL: URL?)

    public var hasBrandColor: Bool {
        switch self {
        case .mark(let kind): kind.hasBrandColor
        case .acpRegistry: false
        }
    }
}

extension ProviderIconKind {
    private static let acpCDNHost = "cdn.agentclientprotocol.com"

    /// Validates that `raw` is an allowlisted official ACP Registry CDN URL, mirroring
    /// `resolveOfficialAcpRegistryIconUrl` in `@t3tools/contracts`.
    public static func validatedOfficialAcpRegistryIconURL(_ raw: String?) -> URL? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty,
              let components = URLComponents(string: trimmed),
              components.scheme?.lowercased() == "https",
              components.host?.lowercased() == acpCDNHost,
              components.port == nil,
              components.user == nil,
              components.password == nil,
              let url = components.url
        else { return nil }
        return url
    }

    /// Derives the official ACP Registry CDN icon URL for a valid registry agent id (e.g. `"devin"`).
    public static func officialAcpRegistryIconURL(forAgentID agentID: String?) -> URL? {
        guard let trimmed = agentID?.trimmingCharacters(in: .whitespacesAndNewlines),
              isValidAcpAgentID(trimmed)
        else { return nil }
        return URL(string: "https://\(acpCDNHost)/registry/v1/latest/\(trimmed).svg")
    }

    /// Resolves a provider driver / ACP identity / optional fallback hints to a `ResolvedProviderIcon`.
    public static func resolve(
        driver: String? = nil,
        acpAgentID: String? = nil,
        iconURL: String? = nil,
        instanceID: String? = nil,
        name: String? = nil,
        legacySymbol: String? = nil
    ) -> ResolvedProviderIcon {
        let normalizedDriver = driver?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""

        if !normalizedDriver.isEmpty {
            if normalizedDriver == "acpregistry" || normalizedDriver == "acp" {
                let resolvedURL = validatedOfficialAcpRegistryIconURL(iconURL)
                    ?? officialAcpRegistryIconURL(forAgentID: acpAgentID)
                    ?? officialAcpRegistryIconURL(forAgentID: inferredAcpAgentID(from: instanceID))
                return .acpRegistry(iconURL: resolvedURL)
            }
            if let exact = exactMark(for: normalizedDriver) {
                return .mark(exact)
            }
            // If an explicit unknown driver was given alongside an allowlisted ACP icon URL, honor it.
            if let validURL = validatedOfficialAcpRegistryIconURL(iconURL) {
                return .acpRegistry(iconURL: validURL)
            }
        }

        // Fall back to instanceId, display name, or legacy placeholder symbol when driver is absent or generic.
        if let hint = inferFromHint(instanceID) {
            return hint
        }
        if let hint = inferFromHint(name) {
            return hint
        }
        if let validURL = validatedOfficialAcpRegistryIconURL(iconURL) {
            return .acpRegistry(iconURL: validURL)
        }
        if let legacy = legacySymbol.flatMap(mark(forLegacySymbol:)) {
            return .mark(legacy)
        }
        return .mark(.generic)
    }

    /// Resolves a model picker sub-provider header name (e.g. `"OpenRouter"`, `"Anthropic API"`, `"xAI"`)
    /// to its icon kind, or `nil` when no upstream mark exists. Matches Studio's `resolveSubProviderIcon`.
    public static func resolveSubProvider(_ name: String) -> ProviderIconKind? {
        let key = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch key {
        case "anthropic", "anthropic api":
            return .anthropic
        case "openai", "openai api":
            return .openai
        case "openrouter":
            return .openrouter
        case "ollama":
            return .ollama
        case "opencode", "opencode zen":
            return .opencode
        case "xai", "grok":
            return .grok
        case "cursor":
            return .cursor
        case "antigravity":
            return .antigravity
        case "kiro":
            return .kiro
        case "muse", "muse code":
            return .muse
        default:
            return nil
        }
    }

    // MARK: - Private matching

    private static func exactMark(for normalized: String) -> ProviderIconKind? {
        switch normalized {
        case "claudeagent", "claude", "claude code", "claude-code", "claude_code":
            return .claude
        case "codex", "openai", "chatgpt":
            return .openai
        case "cursor":
            return .cursor
        case "grok", "xai":
            return .grok
        case "opencode", "opencode zen", "opencode-zen", "opencode-v2":
            return .opencode
        case "antigravity", "antigravity-acp", "gemini":
            return .antigravity
        case "kiro":
            return .kiro
        case "pi", "pi-acp":
            return .pi
        case "muse", "muse code", "musecode", "muse-code":
            return .muse
        case "fx":
            return .fx
        case "anthropic", "anthropic api":
            return .anthropic
        case "openrouter":
            return .openrouter
        case "ollama":
            return .ollama
        default:
            return nil
        }
    }

    private static let tokenSeparators = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "-_.:/·"))

    private static func inferFromHint(_ raw: String?) -> ResolvedProviderIcon? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        let lower = trimmed.lowercased()
        if let exact = exactMark(for: lower) {
            return .mark(exact)
        }
        if lower == "acpregistry" || lower == "acp registry" || lower == "acp" {
            return .acpRegistry(iconURL: nil)
        }

        let tokens = lower.components(separatedBy: tokenSeparators).filter { !$0.isEmpty }
        guard let first = tokens.first else { return nil }

        if first == "acp" || first == "acpregistry" {
            let agentHint = inferredAcpAgentID(from: lower)
            return .acpRegistry(iconURL: officialAcpRegistryIconURL(forAgentID: agentHint))
        }

        // Token-level match prevents false positives like "api" -> "pi" or "prefix" -> "fx".
        for token in tokens {
            switch token {
            case "claude", "claudeagent": return .mark(.claude)
            case "codex", "openai", "chatgpt": return .mark(.openai)
            case "cursor": return .mark(.cursor)
            case "grok", "xai": return .mark(.grok)
            case "opencode": return .mark(.opencode)
            case "antigravity", "gemini": return .mark(.antigravity)
            case "kiro": return .mark(.kiro)
            case "muse", "musecode": return .mark(.muse)
            case "anthropic": return .mark(.anthropic)
            case "openrouter": return .mark(.openrouter)
            case "ollama": return .mark(.ollama)
            default: continue
            }
        }
        if first == "pi" { return .mark(.pi) }
        if first == "fx" { return .mark(.fx) }
        return nil
    }

    private static func inferredAcpAgentID(from raw: String?) -> String? {
        guard let lower = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !lower.isEmpty else {
            return nil
        }
        for prefix in ["acpregistry:", "acp_registry_", "acp-", "acp_", "acp:"] {
            if lower.hasPrefix(prefix) {
                let candidate = String(lower.dropFirst(prefix.count))
                return isValidAcpAgentID(candidate) ? candidate : nil
            }
        }
        return nil
    }

    private static func isValidAcpAgentID(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 128, let first = value.unicodeScalars.first else { return false }
        let isAlnum: (UnicodeScalar) -> Bool = {
            ($0 >= "a" && $0 <= "z") || ($0 >= "0" && $0 <= "9")
        }
        guard isAlnum(first) else { return false }
        return value.unicodeScalars.allSatisfy { isAlnum($0) || $0 == "." || $0 == "_" || $0 == "-" }
    }

    /// Maps Swft's earlier SF Symbol placeholders so legacy call sites resolve to real marks automatically.
    private static func mark(forLegacySymbol symbol: String) -> ProviderIconKind? {
        switch symbol {
        case "asterisk": .claude
        case "hexagon": .openai
        case "cursorarrow": .cursor
        case "chevron.left.forwardslash.chevron.right": .opencode
        case "sparkle": .antigravity
        case "circle.dashed": .generic
        default: nil
        }
    }
}
