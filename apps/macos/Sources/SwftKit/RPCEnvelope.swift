import Foundation

/// Request identifier normalized to a string; accepts string or integer values on decode.
public struct RPCRequestID: Hashable, Sendable, Codable, CustomStringConvertible {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ intValue: Int) {
        self.rawValue = String(intValue)
    }

    public var description: String { rawValue }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            self.rawValue = string
        } else if let int = try? container.decode(Int64.self) {
            self.rawValue = String(int)
        } else {
            throw DecodingError.typeMismatch(
                String.self,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Expected RPC request ID as String or Int"
                )
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// Typed outbound Effect RPC `Request` envelope. Always emits `"headers": []` as required by RpcServer.
public struct RPCRequestEnvelope<Payload: Encodable & Sendable>: Encodable, Sendable {
    public let _tag: String = "Request"
    public let id: String
    public let tag: String
    public let payload: Payload
    public let headers: [[String]]

    public init(id: String, tag: String, payload: Payload, headers: [[String]] = []) {
        self.id = id
        self.tag = tag
        self.payload = payload
        self.headers = headers
    }
}

/// Outbound Effect RPC control frames (`FromClientEncoded`).
public enum RPCClientMessage: Sendable, Equatable, Codable {
    case request(id: String, tag: String, payload: JSONValue, headers: [[String]] = [])
    case ack(requestId: String)
    case interrupt(requestId: String)
    case ping
    case eof

    private enum CodingKeys: String, CodingKey {
        case _tag
        case id
        case requestId
        case tag
        case payload
        case headers
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let messageTag = try container.decode(String.self, forKey: ._tag)
        switch messageTag {
        case "Request":
            let id = try container.decode(RPCRequestID.self, forKey: .id).rawValue
            let tag = try container.decode(String.self, forKey: .tag)
            let payload = try container.decodeIfPresent(JSONValue.self, forKey: .payload) ?? .null
            let headers = try container.decodeIfPresent([[String]].self, forKey: .headers) ?? []
            self = .request(id: id, tag: tag, payload: payload, headers: headers)
        case "Ack":
            let requestId = try container.decode(RPCRequestID.self, forKey: .requestId).rawValue
            self = .ack(requestId: requestId)
        case "Interrupt":
            let requestId = try container.decode(RPCRequestID.self, forKey: .requestId).rawValue
            self = .interrupt(requestId: requestId)
        case "Ping":
            self = .ping
        case "Eof":
            self = .eof
        default:
            throw DecodingError.dataCorruptedError(
                forKey: ._tag,
                in: container,
                debugDescription: "Unknown RPC client message tag: \(messageTag)"
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .request(let id, let tag, let payload, let headers):
            try container.encode("Request", forKey: ._tag)
            try container.encode(id, forKey: .id)
            try container.encode(tag, forKey: .tag)
            try container.encode(payload, forKey: .payload)
            try container.encode(headers, forKey: .headers)
        case .ack(let requestId):
            try container.encode("Ack", forKey: ._tag)
            try container.encode(requestId, forKey: .requestId)
        case .interrupt(let requestId):
            try container.encode("Interrupt", forKey: ._tag)
            try container.encode(requestId, forKey: .requestId)
        case .ping:
            try container.encode("Ping", forKey: ._tag)
        case .eof:
            try container.encode("Eof", forKey: ._tag)
        }
    }
}

/// One element of an Effect RPC failure cause array.
public enum RPCCauseItem: Sendable, Equatable, Codable {
    case fail(error: JSONValue)
    case die(defect: JSONValue)
    case interrupt(fiberId: Int?)
    case unknown(tag: String, raw: JSONValue)

    private enum CodingKeys: String, CodingKey {
        case _tag
        case error
        case defect
        case fiberId
    }

    public var displayMessage: String? {
        switch self {
        case .fail(let error):
            return Self.extractMessage(from: error)
        case .die(let defect):
            return Self.extractMessage(from: defect)
        case .interrupt:
            return "Request interrupted by server."
        case .unknown(let tag, _):
            return "Unknown RPC failure cause (\(tag))."
        }
    }

    private static func extractMessage(from value: JSONValue) -> String? {
        switch value {
        case .string(let message):
            return message
        case .object(let dict):
            if let message = dict["message"]?.stringValue {
                return message
            }
            if let reason = dict["reason"]?.stringValue {
                return reason
            }
            if let tag = dict["_tag"]?.stringValue {
                return tag
            }
            return nil
        default:
            return nil
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let tag = try container.decode(String.self, forKey: ._tag)
        switch tag {
        case "Fail":
            let error = try container.decodeIfPresent(JSONValue.self, forKey: .error) ?? .null
            self = .fail(error: error)
        case "Die":
            let defect = try container.decodeIfPresent(JSONValue.self, forKey: .defect) ?? .null
            self = .die(defect: defect)
        case "Interrupt":
            let fiberId = try container.decodeIfPresent(Int.self, forKey: .fiberId)
            self = .interrupt(fiberId: fiberId)
        default:
            let raw = try JSONValue(from: decoder)
            self = .unknown(tag: tag, raw: raw)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .fail(let error):
            try container.encode("Fail", forKey: ._tag)
            try container.encode(error, forKey: .error)
        case .die(let defect):
            try container.encode("Die", forKey: ._tag)
            try container.encode(defect, forKey: .defect)
        case .interrupt(let fiberId):
            try container.encode("Interrupt", forKey: ._tag)
            try container.encode(fiberId, forKey: .fiberId)
        case .unknown(_, let raw):
            try raw.encode(to: encoder)
        }
    }
}

/// Effect RPC `Exit` payload (`Success` or `Failure`).
public enum RPCExit<Value: Sendable>: Sendable {
    case success(Value)
    case failure([RPCCauseItem])
}

extension RPCExit: Decodable where Value: Decodable {
    private enum CodingKeys: String, CodingKey {
        case _tag
        case value
        case cause
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let tag = try container.decode(String.self, forKey: ._tag)
        switch tag {
        case "Success":
            if Value.self == VoidResponse.self {
                self = .success(VoidResponse() as! Value)
            } else {
                let value = try container.decode(Value.self, forKey: .value)
                self = .success(value)
            }
        case "Failure":
            let causes = try container.decodeIfPresent([RPCCauseItem].self, forKey: .cause) ?? []
            self = .failure(causes)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: ._tag,
                in: container,
                debugDescription: "Unknown RPC Exit tag: \(tag)"
            )
        }
    }
}

extension RPCExit: Encodable where Value: Encodable {
    private enum EncodeKeys: String, CodingKey {
        case _tag
        case value
        case cause
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: EncodeKeys.self)
        switch self {
        case .success(let value):
            try container.encode("Success", forKey: ._tag)
            try container.encode(value, forKey: .value)
        case .failure(let causes):
            try container.encode("Failure", forKey: ._tag)
            try container.encode(causes, forKey: .cause)
        }
    }
}

extension RPCExit: Equatable where Value: Equatable {}

/// Placeholder result type for RPC calls whose `Exit.Success` carries `null` or no `value`.
public struct VoidResponse: Codable, Sendable, Equatable {
    public init() {}
}

/// Typed `Chunk` envelope decoded directly from raw frame bytes without intermediate JSONValue copies.
public struct RPCChunkEnvelope<Item: Decodable & Sendable>: Decodable, Sendable {
    public let requestId: RPCRequestID
    public let values: [Item]
}

/// Typed `Exit` envelope decoded directly from raw frame bytes without intermediate JSONValue copies.
public struct RPCExitEnvelope<Value: Decodable & Sendable>: Decodable, Sendable {
    public let requestId: RPCRequestID
    public let exit: RPCExit<Value>
}

/// Minimal header decoded first to dispatch inbound frames to the matching typed handler.
public struct RPCServerFrameHeader: Decodable, Sendable {
    public let _tag: String
    public let requestId: RPCRequestID?
}

/// Untyped inbound Effect RPC message (`FromServerEncoded`) for diagnostics and unit testing.
public enum RPCServerMessage: Sendable, Equatable, Codable {
    case chunk(requestId: String, values: [JSONValue])
    case exit(requestId: String, exit: RPCExit<JSONValue>)
    case pong
    case defect(JSONValue)
    case unknown(tag: String, raw: JSONValue)

    private enum CodingKeys: String, CodingKey {
        case _tag
        case requestId
        case values
        case exit
        case defect
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let tag = try container.decode(String.self, forKey: ._tag)
        switch tag {
        case "Chunk":
            let requestId = try container.decode(RPCRequestID.self, forKey: .requestId).rawValue
            let values = try container.decode([JSONValue].self, forKey: .values)
            self = .chunk(requestId: requestId, values: values)
        case "Exit":
            let requestId = try container.decode(RPCRequestID.self, forKey: .requestId).rawValue
            let exitContainer = try container.nestedContainer(keyedBy: ExitKeys.self, forKey: .exit)
            let exitTag = try exitContainer.decode(String.self, forKey: ._tag)
            switch exitTag {
            case "Success":
                let value = try exitContainer.decodeIfPresent(JSONValue.self, forKey: .value) ?? .null
                self = .exit(requestId: requestId, exit: .success(value))
            case "Failure":
                let causes = try exitContainer.decodeIfPresent([RPCCauseItem].self, forKey: .cause) ?? []
                self = .exit(requestId: requestId, exit: .failure(causes))
            default:
                throw DecodingError.dataCorruptedError(
                    forKey: ._tag,
                    in: exitContainer,
                    debugDescription: "Unknown Exit tag: \(exitTag)"
                )
            }
        case "Pong":
            self = .pong
        case "Defect":
            let defect = try container.decodeIfPresent(JSONValue.self, forKey: .defect) ?? .null
            self = .defect(defect)
        default:
            let raw = try JSONValue(from: decoder)
            self = .unknown(tag: tag, raw: raw)
        }
    }

    private enum ExitKeys: String, CodingKey {
        case _tag
        case value
        case cause
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .chunk(let requestId, let values):
            try container.encode("Chunk", forKey: ._tag)
            try container.encode(requestId, forKey: .requestId)
            try container.encode(values, forKey: .values)
        case .exit(let requestId, let exit):
            try container.encode("Exit", forKey: ._tag)
            try container.encode(requestId, forKey: .requestId)
            try container.encode(exit, forKey: .exit)
        case .pong:
            try container.encode("Pong", forKey: ._tag)
        case .defect(let defect):
            try container.encode("Defect", forKey: ._tag)
            try container.encode(defect, forKey: .defect)
        case .unknown(_, let raw):
            try raw.encode(to: encoder)
        }
    }
}

/// Errors surfaced by `AuthClient` and `ServerConnection`.
public enum RPCError: Error, Sendable, Equatable, LocalizedError {
    case remoteFailure(tag: String, causes: [RPCCauseItem])
    case remoteDefect(JSONValue)
    case protocolError(String)
    case incompatibleProtocol(serverVersion: Int?)
    case authenticationFailed(String)
    case httpError(statusCode: Int, body: String)
    case disconnected
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .remoteFailure(let tag, let causes):
            let detail = causes.compactMap(\.displayMessage).first ?? "Unknown failure"
            return "RPC '\(tag)' failed: \(detail)"
        case .remoteDefect(let defect):
            return "Server protocol defect: \(defect)"
        case .protocolError(let message):
            return "Protocol error: \(message)"
        case .incompatibleProtocol(let serverVersion):
            let version = serverVersion.map(String.init) ?? "unknown"
            return "Server orchestration protocol \(version) is incompatible (expected 2)."
        case .authenticationFailed(let reason):
            return "Authentication failed: \(reason)"
        case .httpError(let statusCode, let body):
            return "HTTP \(statusCode): \(body)"
        case .disconnected:
            return "Server connection closed."
        case .cancelled:
            return "RPC request was cancelled."
        }
    }
}

/// Reassembles server text frames split under `frameParts=1` (`\u{1E}` prefix marks continuation).
public struct SocketFrameReassembler: Sendable {
    public static let continuationPrefix: Character = "\u{1E}"

    private var buffer: String = ""

    public init() {}

    /// Feeds one WebSocket text frame. Returns the complete message once the final part arrives.
    public mutating func feed(_ frame: String) -> String? {
        if frame.first == Self.continuationPrefix {
            buffer.append(contentsOf: frame.dropFirst())
            return nil
        }
        if buffer.isEmpty {
            return frame
        }
        let complete = buffer + frame
        buffer.removeAll(keepingCapacity: false)
        return complete
    }

    public mutating func reset() {
        buffer.removeAll(keepingCapacity: false)
    }
}
