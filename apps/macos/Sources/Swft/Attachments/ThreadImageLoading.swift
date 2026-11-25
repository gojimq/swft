import AppKit
import Foundation
import SwftDesign
import SwftKit

/// Builds the image loader a thread screen installs: attachments and host paths are minted as signed asset URLs on the
/// thread's own environment (local, LAN or tunnel alike), web images are fetched directly, data URIs decode in place.
enum ThreadImageLoading {
    enum LoadError: Error {
        case unsupportedSource
        case noConnection
        case httpStatus(Int)
    }

    static func loader(threadID: String, environmentID: String?, connection: ServerConnection?) -> SwftImageLoader {
        SwftImageLoader(scope: "\(environmentID ?? "local"):\(threadID)") { reference in
            switch reference {
            case .attachment(let id, let name, let mimeType):
                guard let connection else { throw LoadError.noConnection }
                return try await connection.fetchAsset(.attachment(attachmentId: id, fileName: name, mimeType: mimeType, disposition: "inline"))
            case .source(let source):
                switch ImageSourceLocation.classify(source) {
                case .remote(let url):
                    return try await fetchRemote(url)
                case .inlineData(let data, _):
                    return data
                case .serverRelative(let path):
                    guard let connection else { throw LoadError.noConnection }
                    return try await connection.fetchAssetData(relativeUrl: path)
                case .mediaFile(let path):
                    guard let connection else { throw LoadError.noConnection }
                    return try await connection.fetchAsset(.mediaFile(threadId: threadID, path: path))
                case .unsupported:
                    throw LoadError.unsupportedSource
                }
            }
        }
    }

    private static func fetchRemote(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw LoadError.httpStatus(http.statusCode)
        }
        return data
    }
}

/// Routes ⌘V to the composer when the pasteboard holds files or an image; text pastes reach the field untouched.
/// Only the most recently shown composer listens, so a Home → thread hand-off never attaches twice.
@MainActor
enum ComposerPasteRouter {
    private static var activeToken: UUID?
    private static var monitor: Any?
    private static var shouldHandle: (() -> Bool)?
    private static var handler: (([AttachmentSource]) -> Void)?

    static func activate(
        token: UUID,
        shouldHandle predicate: @escaping () -> Bool = { true },
        handler newHandler: @escaping ([AttachmentSource]) -> Void
    ) {
        activeToken = token
        shouldHandle = predicate
        handler = newHandler
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Local monitors run on the main thread.
            nonisolated(unsafe) let keyEvent = event
            let handled = MainActor.assumeIsolated { handle(keyEvent) }
            return handled ? nil : event
        }
    }

    static func deactivate(token: UUID) {
        guard activeToken == token else { return }
        activeToken = nil
        shouldHandle = nil
        handler = nil
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private static func handle(_ event: NSEvent) -> Bool {
        guard let handler,
              shouldHandle?() ?? true,
              event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
              event.charactersIgnoringModifiers?.lowercased() == "v",
              event.window?.isKeyWindow == true,
              event.window?.attachedSheet == nil,
              let sources = AttachmentPreparer.sources(from: .general)
        else { return false }
        handler(sources)
        return true
    }
}
