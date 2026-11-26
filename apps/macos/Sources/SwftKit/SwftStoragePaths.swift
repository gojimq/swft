import Foundation

/// Cross-platform storage directories for Swft metadata and caches.
public enum SwftStoragePaths {
    /// Dedicated Swft application data directory (`Application Support/Swft`).
    /// Never points at `~/.t3` or `~/.t3/userdata`.
    public static var defaultBaseDirectory: URL {
        #if os(macOS)
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        #else
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        #endif
        return appSupport.appendingPathComponent("Swft", isDirectory: true)
    }
}

/// Client platform metadata reported during OAuth token exchange and WebSocket upgrade
/// so paired sessions display accurately in the server's Sharing & access list.
public struct ClientIdentity: Sendable, Equatable {
    public let surface: String
    public let deviceType: String
    public let os: String

    public init(surface: String, deviceType: String, os: String) {
        self.surface = surface
        self.deviceType = deviceType
        self.os = os
    }

    public static let macOSDesktop = ClientIdentity(surface: "desktop", deviceType: "desktop", os: "macOS")
    public static let iPhone = ClientIdentity(surface: "mobile", deviceType: "mobile", os: "iOS")
    public static let iPad = ClientIdentity(surface: "mobile", deviceType: "tablet", os: "iPadOS")

    public static var current: ClientIdentity {
        #if os(macOS)
        return .macOSDesktop
        #elseif os(iOS)
        return .iPhone
        #else
        return ClientIdentity(surface: "desktop", deviceType: "unknown", os: "unknown")
        #endif
    }
}
