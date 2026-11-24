import Foundation

/// Configured JSON encoder/decoder matching the server's ISO-8601 UTC date wire format.
public enum SwftJSON {
    private static let fractionalISO8601 = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let wholeSecondISO8601 = Date.ISO8601FormatStyle(includingFractionalSeconds: false)

    public static func parseISO8601(_ value: String) -> Date? {
        if let date = try? fractionalISO8601.parse(value) {
            return date
        }
        return try? wholeSecondISO8601.parse(value)
    }

    public static func formatISO8601(_ date: Date) -> String {
        date.formatted(fractionalISO8601)
    }

    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            guard let date = parseISO8601(string) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Invalid ISO-8601 timestamp: \(string)"
                )
            }
            return date
        }
        return decoder
    }

    public static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(formatISO8601(date))
        }
        return encoder
    }
}

/// Empty JSON object `{}` payload for parameterless RPC calls.
public struct EmptyPayload: Codable, Sendable, Equatable {
    public init() {}
}
