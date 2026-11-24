import Foundation

extension MockData {
    /// A plausible "generated" title for a mock first message: up to four of its key words, capitalised. Stands in for
    /// the server's title generation in mock runs.
    static func generatedTitle(for text: String) -> String {
        let filler: Set<String> = ["a", "an", "and", "the", "of", "to", "my", "this", "that", "how", "is", "in", "for", "please", "can", "you"]
        let words = text
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { !$0.isEmpty && !filler.contains($0.lowercased()) }
            .prefix(4)
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
        return words.isEmpty ? "New thread" : words.joined(separator: " ")
    }
}
