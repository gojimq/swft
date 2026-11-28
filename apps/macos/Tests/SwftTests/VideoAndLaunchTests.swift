import AppKit
import AVFoundation
import CoreVideo
import Foundation
import SwftDesign
import SwftKit
import SwiftUI
import Testing
@testable import Swft

@Suite("Home Launch Attachments & Video Media")
struct VideoAndLaunchTests {
    @MainActor
    @Test func homeLaunchInputSuppliesThreadIDWhenLaunchingWithUploadedAttachments() {
        let modelSelection = ModelSelection(instanceId: "antigravity", model: "gemini-4-neon")
        let attachment = TranscriptAttachment(
            id: "pending-abc123",
            kind: .image,
            name: "screenshot.png",
            mimeType: "image/png",
            sizeBytes: 2048
        )

        let withAttachment = AppModel.makeHomeLaunchInput(
            projectId: "proj-1",
            title: "Fix video",
            modelSelection: modelSelection,
            runtimeMode: .fullAccess,
            interactionMode: .default,
            text: "look at this",
            attachments: [attachment],
            threadIDGenerator: { "client-thread-uuid" }
        )
        #expect(withAttachment.threadId == "client-thread-uuid")
        #expect(withAttachment.initialMessage?.attachments.count == 1)
        #expect(withAttachment.initialMessage?.attachments.first?.id == "pending-abc123")

        let withoutAttachment = AppModel.makeHomeLaunchInput(
            projectId: "proj-1",
            title: "Plain prompt",
            modelSelection: modelSelection,
            runtimeMode: .fullAccess,
            interactionMode: .default,
            text: "hello",
            attachments: [],
            threadIDGenerator: { "unused" }
        )
        #expect(withoutAttachment.threadId == nil)
    }

    @Test func classifiesVideoExtensionsURLsAndDataURIsAcrossSwftKitAndSwftDesign() {
        let videos = [
            "/tmp/right-sidebar-transition.mp4",
            "file:///Users/jim/Desktop/demo%20clip.MOV",
            "https://example.com/path/clip.m4v?token=123#t=1",
            "</Users/jim/clip with spaces.webm>",
            "data:video/mp4;base64,AAAA",
        ]
        for source in videos {
            #expect(ImageSourceLocation.mediaKind(for: source) == .video, "Expected video for \(source)")
            #expect(SwftMediaClassifier.isVideo(source), "Expected SwftMediaClassifier video for \(source)")
        }

        #expect(ImageSourceLocation.classify("</Users/jim/clip with spaces.mp4>") == .mediaFile(path: "/Users/jim/clip with spaces.mp4"))

        let images = [
            "/tmp/screenshot.png",
            "https://example.com/photo.jpg?size=large",
            "data:image/png;base64,iVBORw0KGgo=",
        ]
        for source in images {
            #expect(ImageSourceLocation.mediaKind(for: source) == .image)
            #expect(!SwftMediaClassifier.isVideo(source))
        }

        #expect(ImageSourceLocation.fileExtension(for: "/tmp/clip.MP4?foo=1") == "mp4")
        #expect(ImageSourceLocation.fileExtension(for: "file:///tmp/my%20clip.mov") == "mov")
        #expect(SwftMediaClassifier.formatDuration(4.2) == "0:04")
        #expect(SwftMediaClassifier.formatDuration(75.0) == "1:15")
        #expect(SwftMediaClassifier.formatDuration(0) == nil)
    }

    @Test func inspectsRealMP4ExtractingPosterDurationAndOrientedAspectRatio() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("swft-video-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let landscapeURL = tempDir.appendingPathComponent("landscape.mp4")
        try await Self.writeSampleMP4(to: landscapeURL, width: 320, height: 180, transform: .identity, frames: 12)
        let landscape = await SwftVideoCache.inspectVideo(at: landscapeURL)
        #expect(landscape.isPlayable)
        #expect(landscape.poster != nil)
        #expect(landscape.duration > 0.2)
        #expect(abs(landscape.aspectRatio - (16.0 / 9.0)) < 0.08)

        let portraitURL = tempDir.appendingPathComponent("portrait.mp4")
        try await Self.writeSampleMP4(
            to: portraitURL,
            width: 320,
            height: 180,
            transform: CGAffineTransform(rotationAngle: .pi / 2),
            frames: 12
        )
        let portrait = await SwftVideoCache.inspectVideo(at: portraitURL)
        #expect(portrait.isPlayable)
        #expect(portrait.poster != nil)
        #expect(abs(portrait.aspectRatio - (9.0 / 16.0)) < 0.08)
    }

    @MainActor
    @Test func videoCacheLoadsCachesAndRetriesAcrossRequests() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("swft-video-cache-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sampleURL = tempDir.appendingPathComponent("clip.mp4")
        try await Self.writeSampleMP4(to: sampleURL, width: 320, height: 180, transform: .identity, frames: 8)

        let cache = SwftVideoCache()
        let scope = "test-\(UUID().uuidString)"
        let source = "/virtual/clip-\(UUID().uuidString).mp4"

        let failingLoader = SwftMediaLoader(scope: scope) { _ in
            throw CocoaError(.fileReadNoSuchFile)
        }
        let failedResult = await cache.load(source: source, using: failingLoader)
        #expect(failedResult == nil)
        let key = cache.cacheKey(source: source, scope: scope)
        #expect(cache.hasFailed(key))

        cache.retry(key)
        #expect(!cache.hasFailed(key))

        let succeedingLoader = SwftMediaLoader(scope: scope) { _ in
            let copy = tempDir.appendingPathComponent("dl-\(UUID().uuidString).mp4")
            try FileManager.default.copyItem(at: sampleURL, to: copy)
            return copy
        }
        let loaded = await cache.load(source: source, using: succeedingLoader)
        #expect(loaded != nil)
        #expect(loaded?.isPlayable == true)
        #expect(loaded?.poster != nil)
        #expect(cache.asset(for: key) != nil)
        if let localURL = loaded?.localURL {
            try? FileManager.default.removeItem(at: localURL)
        }
    }

    @MainActor
    @Test(.enabled(if: ProcessInfo.processInfo.environment["SWFT_RECORD_VIDEO_SNAPSHOT"] != nil))
    func renderVideoPosterVisualVerification() async throws {
        guard let outputDir = ProcessInfo.processInfo.environment["SWFT_RECORD_VIDEO_SNAPSHOT"] else { return }
        let dirURL = URL(fileURLWithPath: outputDir, isDirectory: true)
        try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)

        let landscapeURL = dirURL.appendingPathComponent("sample-landscape.mp4")
        let portraitURL = dirURL.appendingPathComponent("sample-portrait.mp4")
        try await Self.writeSampleMP4(to: landscapeURL, width: 480, height: 270, transform: .identity, frames: 48)
        try await Self.writeSampleMP4(
            to: portraitURL,
            width: 480,
            height: 224,
            transform: CGAffineTransform(rotationAngle: .pi / 2),
            frames: 60
        )

        let landscapeAsset = await SwftVideoCache.inspectVideo(at: landscapeURL)
        let portraitAsset = await SwftVideoCache.inspectVideo(at: portraitURL)
        let scope = "snap-\(UUID().uuidString)"
        let landscapeKey = SwftVideoCache.shared.cacheKey(source: "/demo/landscape.mp4", scope: scope)
        let portraitKey = SwftVideoCache.shared.cacheKey(source: "/demo/portrait.mp4", scope: scope)
        SwftVideoCache.shared.store(landscapeAsset, for: landscapeKey)
        SwftVideoCache.shared.store(portraitAsset, for: portraitKey)

        let loader = SwftMediaLoader(scope: scope) { _ in landscapeURL }
        let canvas = VStack(alignment: .leading, spacing: 18) {
            Text("Native Push / Pop Transition Under the Duo Vertical Side Bar")
                .font(SwftType.label)
                .foregroundStyle(SwftColor.textPrimary)
            MessageImage(source: "/demo/portrait.mp4", alt: "iPhone Duo native Right Sidebar transition")
            MessageImage(source: "/demo/landscape.mp4", alt: "Desktop release walkthrough")
        }
        .padding(24)
        .frame(width: 640, alignment: .leading)
        .background(SwftColor.canvas)
        .environment(\.swftMediaLoader, loader)
        .environment(\.colorScheme, .dark)

        let hosting = NSHostingView(rootView: canvas)
        let fitting = hosting.fittingSize
        hosting.frame = NSRect(origin: .zero, size: CGSize(width: 640, height: fitting.height))
        hosting.appearance = NSAppearance(named: .darkAqua)
        hosting.layoutSubtreeIfNeeded()

        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            Issue.record("Failed to create bitmap rep")
            return
        }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            Issue.record("Failed to encode PNG")
            return
        }
        try png.write(to: dirURL.appendingPathComponent("macos-message-video.png"))
        try? FileManager.default.removeItem(at: landscapeURL)
        try? FileManager.default.removeItem(at: portraitURL)
    }

    private static func writeSampleMP4(
        to url: URL,
        width: Int,
        height: Int,
        transform: CGAffineTransform,
        frames: Int
    ) async throws {
        try? FileManager.default.removeItem(at: url)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.transform = transform
        input.expectsMediaDataInRealTime = false

        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: attrs)
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let fps: Int32 = 12
        for index in 0..<frames {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(5))
            }
            var pixelBuffer: CVPixelBuffer?
            guard let pool = adaptor.pixelBufferPool else { continue }
            CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pixelBuffer)
            guard let buffer = pixelBuffer else { continue }
            CVPixelBufferLockBaseAddress(buffer, [])
            if let base = CVPixelBufferGetBaseAddress(buffer) {
                let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
                let ptr = base.assumingMemoryBound(to: UInt8.self)
                for y in 0..<height {
                    let row = ptr.advanced(by: y * bytesPerRow)
                    for x in 0..<width {
                        let offset = x * 4
                        row[offset + 0] = UInt8((90 + (x * 120) / max(1, width)) & 0xFF) // B
                        row[offset + 1] = UInt8((48 + (y * 100) / max(1, height)) & 0xFF) // G
                        row[offset + 2] = UInt8((34 + (index * 4)) & 0xFF) // R
                        row[offset + 3] = 255 // A
                    }
                }
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(index), timescale: fps))
        }

        input.markAsFinished()
        await writer.finishWriting()
        if let error = writer.error {
            throw error
        }
    }
}
