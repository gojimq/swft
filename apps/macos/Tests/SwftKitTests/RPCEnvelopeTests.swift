import Foundation
import Testing
@testable import SwftKit

@Suite("RPC Envelope & Framing")
struct RPCEnvelopeTests {
    @Test func encodesRequestEnvelopeWithMandatoryEmptyHeaders() throws {
        let envelope = RPCRequestEnvelope(
            id: "1",
            tag: RPCMethod.serverGetConfig,
            payload: EmptyPayload()
        )
        let data = try SwftJSON.makeEncoder().encode(envelope)
        let json = try JSONDecoder().decode(JSONValue.self, from: data)

        #expect(json["_tag"] == .string("Request"))
        #expect(json["id"] == .string("1"))
        #expect(json["tag"] == .string("server.getConfig"))
        #expect(json["payload"] == .object([:]))
        #expect(json["headers"] == .array([]))
    }

    @Test func roundTripsControlMessages() throws {
        let messages: [RPCClientMessage] = [
            .ack(requestId: "7"),
            .interrupt(requestId: "9"),
            .ping,
            .eof,
        ]
        let encoder = SwftJSON.makeEncoder()
        let decoder = SwftJSON.makeDecoder()
        for message in messages {
            let encoded = try encoder.encode(message)
            let decoded = try decoder.decode(RPCClientMessage.self, from: encoded)
            #expect(decoded == message)
        }
    }

    @Test func decodesChunkExitPongAndDefectFromServer() throws {
        let decoder = SwftJSON.makeDecoder()

        let chunkJSON = #"{"_tag":"Chunk","requestId":"3","values":[{"kind":"synchronized"}]}"#
        let chunk = try decoder.decode(RPCServerMessage.self, from: Data(chunkJSON.utf8))
        #expect(chunk == .chunk(requestId: "3", values: [.object(["kind": .string("synchronized")])]))

        // Numeric requestId is also valid in Effect RPC.
        let numericExitJSON = #"{"_tag":"Exit","requestId":42,"exit":{"_tag":"Success","value":{"sequence":5}}}"#
        let numericExit = try decoder.decode(RPCServerMessage.self, from: Data(numericExitJSON.utf8))
        #expect(numericExit == .exit(requestId: "42", exit: .success(.object(["sequence": .int(5)]))))

        let failureJSON = """
        {
          "_tag": "Exit",
          "requestId": "4",
          "exit": {
            "_tag": "Failure",
            "cause": [
              {"_tag": "Fail", "error": {"_tag": "OrchestrationV2DispatchCommandError", "message": "Thread not found"}},
              {"_tag": "Interrupt", "fiberId": 12}
            ]
          }
        }
        """
        let failure = try decoder.decode(RPCServerMessage.self, from: Data(failureJSON.utf8))
        if case .exit(let reqId, .failure(let causes)) = failure {
            #expect(reqId == "4")
            #expect(causes.count == 2)
            #expect(causes[0].displayMessage == "Thread not found")
            #expect(causes[1] == .interrupt(fiberId: 12))
        } else {
            Issue.record("Expected Exit.Failure, got \(failure)")
        }

        let pong = try decoder.decode(RPCServerMessage.self, from: Data(#"{"_tag":"Pong"}"#.utf8))
        #expect(pong == .pong)

        let defect = try decoder.decode(
            RPCServerMessage.self,
            from: Data(#"{"_tag":"Defect","defect":"malformed frame"}"#.utf8)
        )
        #expect(defect == .defect(.string("malformed frame")))
    }

    @Test func reassemblesMultiPartFrames() {
        var reassembler = SocketFrameReassembler()
        #expect(reassembler.feed(#"{"_tag":"Pong"}"#) == #"{"_tag":"Pong"}"#)
        #expect(reassembler.feed("\u{1E}{\"_tag\":") == nil)
        #expect(reassembler.feed("\u{1E}\"Chunk\",\"requestId\":") == nil)
        #expect(reassembler.feed(#""1","values":[]}"#) == #"{"_tag":"Chunk","requestId":"1","values":[]}"#)
        // Subsequent single frame starts fresh.
        #expect(reassembler.feed(#"{"_tag":"Pong"}"#) == #"{"_tag":"Pong"}"#)
    }

    @Test func derivesRotatingDesktopBootstrapToken() {
        // Window index 0 at epoch 0 -> HMAC-SHA256("test-secret", "t3-desktop-bootstrap:0")
        let token = DesktopBootstrapToken.derive(secret: "test-secret", now: Date(timeIntervalSince1970: 0))
        #expect(token.count == 64)
        #expect(token == token.lowercased())
        // Same 12-hour window produces identical token; next window differs.
        let sameWindow = DesktopBootstrapToken.derive(secret: "test-secret", now: Date(timeIntervalSince1970: 3600))
        let nextWindow = DesktopBootstrapToken.derive(secret: "test-secret", now: Date(timeIntervalSince1970: 12 * 3600))
        #expect(token == sameWindow)
        #expect(token != nextWindow)
    }

    @Test func constructsWebSocketURLWithRequiredParams() throws {
        let client = AuthClient()
        let wsURL = try client.webSocketURL(
            httpBaseURL: URL(string: "http://127.0.0.1:4567")!,
            ticket: "abc.123"
        )
        let components = try #require(URLComponents(url: wsURL, resolvingAgainstBaseURL: false))
        #expect(components.scheme == "ws")
        #expect(components.path == "/ws")
        let query = Dictionary(
            uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") }
        )
        #expect(query["orchestrationProtocol"] == "2")
        #expect(query["wsTicket"] == "abc.123")
        #expect(query["frameParts"] == "1")
        #expect(query["clientOs"] == "macOS")

        let wssURL = try client.webSocketURL(
            httpBaseURL: URL(string: "https://host.example.com/prefix/")!,
            ticket: "tok"
        )
        #expect(wssURL.scheme == "wss")
        #expect(wssURL.path == "/prefix/ws")

        let iosURL = try client.webSocketURL(
            httpBaseURL: URL(string: "https://mini.tailnet.ts.net")!,
            ticket: "ios-tok",
            clientIdentity: .iPhone
        )
        let iosComponents = try #require(URLComponents(url: iosURL, resolvingAgainstBaseURL: false))
        let iosQuery = Dictionary(
            uniqueKeysWithValues: (iosComponents.queryItems ?? []).map { ($0.name, $0.value ?? "") }
        )
        #expect(iosQuery["clientSurface"] == "mobile")
        #expect(iosQuery["clientDeviceType"] == "mobile")
        #expect(iosQuery["clientOs"] == "iOS")
    }
}
