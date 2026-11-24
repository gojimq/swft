import AppKit
import Foundation
import Observation

/// Fetches and caches allowlisted official ACP Registry CDN icons (`cdn.agentclientprotocol.com`).
/// Mirrors `loadCachedAcpRegistryIcon` in T3 Code / Studio: no redirects, <= 512 KiB, `image/*` only.
@MainActor
@Observable
final class AcpRegistryIconCache {
    enum Entry {
        case loading
        case svg(SVGPathParser.ParsedSVG)
        case raster(NSImage)
        case failed
    }

    static let shared = AcpRegistryIconCache()
    private nonisolated static let maxBytes = 512 * 1_024

    private(set) var entries: [URL: Entry] = [:]
    @ObservationIgnored private var inFlight: Set<URL> = []
    @ObservationIgnored private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.httpCookieAcceptPolicy = .never
        config.httpShouldSetCookies = false
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 15
        self.session = URLSession(configuration: config, delegate: NoRedirectDelegate(), delegateQueue: nil)
    }

    func entry(for url: URL) -> Entry {
        entries[url] ?? .loading
    }

    private enum FetchedPayload: Sendable {
        case svg(SVGPathParser.ParsedSVG)
        case rasterData(Data)
        case failed
    }

    func loadIfNeeded(_ url: URL) {
        guard ProviderIconKind.validatedOfficialAcpRegistryIconURL(url.absoluteString) != nil else {
            entries[url] = .failed
            return
        }
        guard entries[url] == nil, !inFlight.contains(url) else { return }
        inFlight.insert(url)
        entries[url] = .loading

        Task { [weak self] in
            let fetched = await self?.fetch(url) ?? .failed
            guard let self else { return }
            self.inFlight.remove(url)
            switch fetched {
            case .svg(let parsed):
                self.entries[url] = .svg(parsed)
            case .rasterData(let data):
                self.entries[url] = NSImage(data: data).map(Entry.raster) ?? .failed
            case .failed:
                self.entries[url] = .failed
            }
        }
    }

    private nonisolated func fetch(_ url: URL) async -> FetchedPayload {
        var request = URLRequest(url: url)
        request.setValue("no-referrer", forHTTPHeaderField: "Referer")
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  data.count <= Self.maxBytes
            else { return .failed }

            let contentType = (http.value(forHTTPHeaderField: "Content-Type") ?? "")
                .split(separator: ";", maxSplits: 1)
                .first?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased() ?? ""
            guard contentType.hasPrefix("image/") else { return .failed }

            if contentType.contains("svg") || url.pathExtension.lowercased() == "svg" {
                if let parsed = SVGPathParser.parseSVGDocument(data) {
                    return .svg(parsed)
                }
                return .failed
            }
            return .rasterData(data)
        } catch {
            return .failed
        }
    }
}

private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
