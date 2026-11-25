import AppKit
import SwiftUI

/// Visual metrics matching `UserBubble` so the flying overlay pill lands pixel-for-pixel onto the real bubble.
public enum UserBubbleMetrics {
    public static let horizontalPadding: CGFloat = 18
    public static let verticalPadding: CGFloat = max(8, (44 - SwftFonts.lineHeight(SwftType.bodySize)) / 2)
    public static let cornerRadius: CGFloat = 22
    public static let leadingSpacerMinLength: CGFloat = 80

    /// Estimates the rendered pill size before SwiftUI reports the real bubble's measured geometry.
    public static func estimatedSize(for text: String, maxWidth: CGFloat) -> CGSize {
        let clampedMaxWidth = max(44, maxWidth)
        let innerMaxWidth = max(16, clampedMaxWidth - horizontalPadding * 2)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = SwftType.bodyLineSpacing
        paragraph.lineBreakMode = .byWordWrapping
        let font = SwftFonts.ctFont(SwftType.bodySize)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: paragraph,
        ]
        let rect = (text as NSString).boundingRect(
            with: CGSize(width: innerMaxWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes
        )
        let width = min(clampedMaxWidth, ceil(rect.width) + horizontalPadding * 2)
        let height = max(44, ceil(rect.height) + verticalPadding * 2)
        return CGSize(width: width, height: height)
    }

    /// Attachment-only messages render no text pill.
    public static func hasText(_ text: String) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Estimated size of a whole user turn (`UserTurnContent`): its attachment strip stacked above the text pill.
    public static func estimatedTurnSize(
        text: String,
        attachments: [TranscriptAttachment],
        maxWidth: CGFloat,
        aspectRatio: (TranscriptAttachment) -> CGFloat? = { _ in nil }
    ) -> CGSize {
        let strip = AttachmentMetrics.stripSize(for: attachments, maxWidth: max(44, maxWidth), aspectRatio: aspectRatio)
        guard hasText(text) else { return strip }
        let pill = estimatedSize(for: text, maxWidth: maxWidth)
        guard !attachments.isEmpty else { return pill }
        return CGSize(
            width: max(strip.width, pill.width),
            height: strip.height + AttachmentMetrics.stripToBubbleSpacing + pill.height
        )
    }
}

/// Constrains its child to `maxWidth` while hugging the child's tight intrinsic width for short messages.
private struct MaxWidthTightLayout: Layout {
    let maxWidth: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let child = subviews.first else { return .zero }
        let cappedWidth = min(proposal.width ?? maxWidth, maxWidth)
        return child.sizeThatFits(ProposedViewSize(width: cappedWidth, height: proposal.height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let child = subviews.first else { return }
        child.place(
            at: CGPoint(x: bounds.midX, y: bounds.midY),
            anchor: .center,
            proposal: ProposedViewSize(width: bounds.width, height: bounds.height)
        )
    }
}

/// Overlay clone of `UserBubble`'s pill used during the 680ms J-shaped send flight. `progress` is linear time in
/// `[0, 1]`; animate it with a linear animation of `SendFlightTiming.sendDuration` and the path applies the send
/// curve itself. Only this view re-renders per frame, so a flight never re-renders the transcript.
public struct SendFlightOverlayBubble: View, Animatable {
    let text: String
    let attachments: [TranscriptAttachment]
    let maxWidth: CGFloat
    let path: SendFlightPath
    nonisolated var progress: Double

    nonisolated public var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    public init(text: String, attachments: [TranscriptAttachment] = [], maxWidth: CGFloat, path: SendFlightPath, progress: Double) {
        self.text = text
        self.attachments = attachments
        self.maxWidth = maxWidth
        self.path = path
        self.progress = progress
    }

    public var body: some View {
        let sample = path.sample(normalizedTime: progress)
        // The same turn unit the transcript renders, so attachments and text lift out and land together.
        MaxWidthTightLayout(maxWidth: max(44, maxWidth)) {
            UserTurnContent(text: text, attachments: attachments, pillOpacity: sample.pillOpacity, interactive: false)
        }
        .scaleEffect(sample.scale, anchor: .bottomTrailing)
        .opacity(sample.opacity)
        .position(sample.center)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Quiet "Working" tail row shown while a turn is running before work steps or streaming text arrive.
/// Waits `delay` (or until `revealAt`, typically `send.timestamp + WORKING_DELAY_MS`) so the message reaches the top first.
public struct WorkingIndicatorRow: View {
    let delay: TimeInterval
    let revealAt: Date?
    let reduceMotionOverride: Bool?
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var shown: Bool

    private var reduceMotion: Bool { reduceMotionOverride ?? systemReduceMotion }

    public init(delay: TimeInterval = 0, revealAt: Date? = nil, reduceMotion: Bool? = nil) {
        self.delay = delay
        self.revealAt = revealAt
        self.reduceMotionOverride = reduceMotion
        let initialRemaining: TimeInterval
        if reduceMotion == true {
            initialRemaining = 0
        } else if let revealAt {
            initialRemaining = max(0, revealAt.timeIntervalSinceNow)
        } else {
            initialRemaining = max(0, delay)
        }
        self._shown = State(initialValue: initialRemaining <= 0)
    }

    public var body: some View {
        HStack(spacing: 8) {
            if reduceMotion {
                Circle()
                    .fill(SwftColor.textTertiary)
                    .frame(width: 6, height: 6)
                    .frame(width: 12, height: 12)
            } else {
                ProgressView()
                    .controlSize(.mini)
                    .frame(width: 12, height: 12)
            }
            Text("Working")
                .font(SwftType.label)
                .foregroundStyle(SwftColor.textSecondary)
        }
        .frame(height: 24, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(shown ? 1 : 0)
        .offset(y: shown || reduceMotion ? 0 : 8)
        .task(id: revealAt?.timeIntervalSinceReferenceDate ?? delay) {
            if shown { return }
            let remaining: TimeInterval
            if reduceMotion {
                remaining = 0
            } else if let revealAt {
                remaining = max(0, revealAt.timeIntervalSinceNow)
            } else {
                remaining = max(0, delay)
            }
            if remaining > 0 {
                try? await Task.sleep(for: .seconds(remaining))
                guard !Task.isCancelled else { return }
            }
            withAnimation(SwftMotion.resolve(SwftMotion.settle, reduceMotion: reduceMotion)) {
                shown = true
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Working")
    }
}
