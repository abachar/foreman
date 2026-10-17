import Foundation
import JSONRPC
import LanguageServerProtocol
import Testing

@testable import Foreman

/// The DAP envelope and its bodies (debug R9): what goes on the wire and what comes back.
struct DAPMessageTests {
    private func decode(_ json: String) throws -> DAPMessage {
        try JSONDecoder().decode(DAPMessage.self, from: Data(json.utf8))
    }

    @Test func encodesARequestWithTheProtocolsNames() throws {
        let request = DAPMessage(
            seq: 3, type: .request, command: "stackTrace",
            arguments: try LSPAny(encoding: DAPStackTraceArguments(threadId: 7, startFrame: nil, levels: 100)))
        let object = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
        #expect(object["seq"] as? Int == 3)
        #expect(object["type"] as? String == "request")
        #expect(object["command"] as? String == "stackTrace")
        #expect((object["arguments"] as? [String: Int]) == ["threadId": 7, "levels": 100])
        #expect(object["request_seq"] == nil)
        #expect(try decode(String(decoding: JSONEncoder().encode(request), as: UTF8.self)) == request)
    }

    @Test func decodesASuccessResponse() throws {
        let response = try decode(
            #"{"seq":5,"type":"response","request_seq":3,"success":true,"command":"threads","body":{"threads":[{"id":1,"name":"main"}]}}"#
        )
        #expect(response.type == .response)
        #expect(response.requestSeq == 3)
        #expect(response.success == true)
        #expect(try response.decodedBody(DAPThreadsResponse.self).threads == [DAPThread(id: 1, name: "main")])
    }

    @Test func decodesAnErrorResponse() throws {
        let response = try decode(
            #"{"seq":6,"type":"response","request_seq":4,"success":false,"command":"launch","message":"program does not exist"}"#
        )
        #expect(response.success == false)
        #expect(response.message == "program does not exist")
        #expect(response.body == nil)
    }

    @Test func decodesAnEvent() throws {
        let event = try decode(
            #"{"seq":8,"type":"event","event":"stopped","body":{"reason":"breakpoint","threadId":2,"allThreadsStopped":true}}"#
        )
        #expect(event.type == .event)
        #expect(event.event == "stopped")
        let stopped = try event.decodedBody(DAPStoppedEvent.self)
        #expect(stopped.reason == "breakpoint")
        #expect(stopped.threadId == 2)
    }

    @Test func decodesAnEventWithoutABody() throws {
        let event = try decode(#"{"seq":9,"type":"event","event":"initialized"}"#)
        #expect(event.body == nil)
        #expect(try event.decodedBody(DAPEmpty.self) == DAPEmpty())
    }

    @Test func decodesTheReverseRunInTerminalRequest() throws {
        let request = try decode(
            #"{"seq":10,"type":"request","command":"runInTerminal","arguments":{"kind":"integrated","cwd":"/w","args":["/bin/echo","a b"],"env":{"A":"1","B":null}}}"#
        )
        #expect(request.type == .request)
        let arguments = try request.decodedArguments(DAPRunInTerminalArguments.self)
        #expect(arguments.cwd == "/w")
        #expect(arguments.args == ["/bin/echo", "a b"])
        let env = try #require(arguments.env)
        #expect(env["A"] == .some("1"))
        // `null` is "unset this variable": present, with no value.
        #expect(env.keys.contains("B") && env["B"] == .some(nil))
    }

    @Test func initializeAnnouncesWhatForemanCan() throws {
        let arguments = try LSPAny(encoding: DAPInitializeArguments(adapterID: "swift"))
        #expect(
            arguments
                == .hash([
                    "clientID": .string("foreman"), "clientName": .string("Foreman"), "adapterID": .string("swift"),
                    "linesStartAt1": .bool(true), "columnsStartAt1": .bool(true), "pathFormat": .string("path"),
                    "supportsRunInTerminalRequest": .bool(true), "supportsVariablePaging": .bool(true),
                ]))
    }
}
