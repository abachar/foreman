import Foundation
import JSONRPC
import LanguageServerProtocol
import Testing

@testable import Foreman

// The adapter's side of a mock channel is played by the test. No adapter is launched here.
private nonisolated func decode(_ data: Data) throws -> DAPMessage {
    try JSONDecoder().decode(DAPMessage.self, from: data)
}

private nonisolated func reply(
    _ adapter: DataChannel, to request: DAPMessage, seq: Int, body: LSPAny? = nil, error: String? = nil
) async throws {
    let response = DAPMessage(
        seq: seq, type: .response, command: request.command, body: body, requestSeq: request.seq,
        success: error == nil, message: error)
    try await adapter.writeHandler(JSONEncoder().encode(response))
}

private nonisolated func announce(_ adapter: DataChannel, _ event: String, seq: Int) async throws {
    try await adapter.writeHandler(JSONEncoder().encode(DAPMessage(seq: seq, type: .event, event: event)))
}

/// What the scripted adapter saw, in order.
private nonisolated struct Transcript: Sendable {
    var commands: [String] = []
    var launchArguments: LSPAny?
    var breakpoints: DAPSetBreakpointsArguments?
}

struct DAPSessionTests {
    private let seconds5 = Duration.seconds(5)

    /// debug R9: `initialize`, the request sent but not awaited, `initialized`, the breakpoints,
    /// `configurationDone`, and only then the request's answer ends the start.
    @Test func startsInTheOrderOfR9() async throws {
        let (client, adapter) = DataChannel.withDataActor()
        let session = DAPSession(channel: client, adapterID: "swift", timeout: seconds5)
        let played = Task { () -> Transcript in
            var transcript = Transcript()
            var launch: DAPMessage?
            var seq = 100
            for await data in adapter.dataSequence {
                let request = try decode(data)
                transcript.commands.append(request.command ?? "?")
                seq += 1
                switch request.command {
                case "initialize":
                    try await reply(adapter, to: request, seq: seq, body: .hash([:]))
                case "launch":
                    launch = request
                    transcript.launchArguments = request.arguments
                    try await announce(adapter, "initialized", seq: seq)
                case "setBreakpoints":
                    transcript.breakpoints = try request.decodedArguments(DAPSetBreakpointsArguments.self)
                    try await reply(adapter, to: request, seq: seq, body: .hash(["breakpoints": .array([])]))
                case "configurationDone":
                    try await reply(adapter, to: request, seq: seq)
                    try await reply(adapter, to: try #require(launch), seq: seq + 1)
                    return transcript
                default:
                    break
                }
            }
            return transcript
        }
        let arguments: LSPAny = .hash(["program": .string("/usr/bin/true"), "stopOnEntry": .bool(true)])
        try await session.start(
            .launch, arguments: arguments, breakpoints: [.init(path: "/w/Foo.swift", lines: [3, 9])])
        let transcript = try await played.value
        #expect(transcript.commands == ["initialize", "launch", "setBreakpoints", "configurationDone"])
        #expect(transcript.launchArguments == arguments)
        #expect(transcript.breakpoints?.source.path == "/w/Foo.swift")
        #expect(transcript.breakpoints?.breakpoints.map(\.line) == [3, 9])
    }

    /// An adapter answering `launch` before `configurationDone` and sending `initialized` at once
    /// (java-debug) is served by the same order: the answer waits in its slot.
    @Test func anAnswerArrivingEarlyIsNotLost() async throws {
        let (client, adapter) = DataChannel.withDataActor()
        let session = DAPSession(channel: client, adapterID: "java", timeout: seconds5)
        let played = Task {
            var seq = 100
            for await data in adapter.dataSequence {
                let request = try decode(data)
                seq += 1
                switch request.command {
                case "initialize":
                    try await reply(adapter, to: request, seq: seq, body: .hash([:]))
                    try await announce(adapter, "initialized", seq: seq + 1)
                case "attach":
                    try await reply(adapter, to: request, seq: seq)
                case "configurationDone":
                    try await reply(adapter, to: request, seq: seq)
                    return
                default:
                    break
                }
            }
        }
        try await session.start(.attach, arguments: .hash(["port": .number(5005)]))
        try await played.value
    }

    /// `seq` counts up and an answer goes to its request, whatever the order they come back in.
    @Test func pairsAnswersByRequestSeq() async throws {
        let (client, adapter) = DataChannel.withDataActor()
        let session = DAPSession(channel: client, adapterID: "t", timeout: seconds5)
        async let threads = session.send("threads", DAPEmpty(), as: DAPThreadsResponse.self)
        async let scopes = session.send("scopes", DAPScopesArguments(frameId: 1), as: DAPScopesResponse.self)
        var iterator = adapter.dataSequence.makeAsyncIterator()
        let first = try decode(try #require(await iterator.next()))
        let second = try decode(try #require(await iterator.next()))
        #expect(Set([first.seq, second.seq]) == [1, 2])
        for request in [second, first] {
            let body: LSPAny =
                request.command == "threads"
                ? .hash(["threads": .array([.hash(["id": .number(4), "name": .string("main")])])])
                : .hash([
                    "scopes": .array([
                        .hash(["name": .string("Locals"), "variablesReference": .number(9), "expensive": .bool(false)])
                    ])
                ])
            try await reply(adapter, to: request, seq: 50 + request.seq, body: body)
        }
        #expect(try await threads.threads == [DAPThread(id: 4, name: "main")])
        #expect(try await scopes.scopes.map(\.variablesReference) == [9])
    }

    /// debug R11: the adapter's own sentence reaches the caller.
    @Test func anErrorResponseCarriesTheAdaptersMessage() async throws {
        let (client, adapter) = DataChannel.withDataActor()
        let session = DAPSession(channel: client, adapterID: "t", timeout: seconds5)
        let played = Task {
            for await data in adapter.dataSequence {
                try await reply(adapter, to: try decode(data), seq: 9, error: "program does not exist")
                return
            }
        }
        await #expect(throws: DAPSession.Failure.rejected(command: "initialize", message: "program does not exist")) {
            try await session.start(.launch, arguments: .hash([:]))
        }
        try await played.value
    }

    /// debug R11, R9: no answer within the timeout is an error, not a wait.
    @Test func aSilentAdapterTimesOut() async throws {
        let (client, _) = DataChannel.withDataActor()
        let session = DAPSession(channel: client, adapterID: "t", timeout: .milliseconds(100))
        await #expect(throws: DAPSession.Failure.timeout("initialize")) {
            try await session.start(.launch, arguments: .hash([:]))
        }
    }

    @Test func eventsAndReverseRequestsComeOutAsAStream() async throws {
        let (client, adapter) = DataChannel.withDataActor()
        let session = DAPSession(channel: client, adapterID: "t", timeout: seconds5)
        try await announce(adapter, "output", seq: 1)
        try await adapter.writeHandler(
            JSONEncoder().encode(
                DAPMessage(seq: 2, type: .request, command: "runInTerminal", arguments: .hash(["cwd": .string("/")]))))
        var messages = session.messages.makeAsyncIterator()
        #expect(await messages.next()?.event == "output")
        let reverse = try #require(await messages.next())
        #expect(reverse.type == .request)
        #expect(reverse.command == "runInTerminal")
    }

    // MARK: - The stop ladder (debug R9)

    /// `disconnect` never answered, the process never leaving: `SIGTERM` ends it.
    @Test func stopTerminatesAnAdapterThatNeverAnswersDisconnect() async throws {
        let process = try spawn("/bin/sleep", ["60"])
        let (client, _) = DataChannel.withDataActor()
        let session = DAPSession(
            channel: client, adapterID: "t", timeout: .milliseconds(100), killDelay: .milliseconds(100),
            process: process)
        await session.stop(terminateDebuggee: false)
        process.waitUntilExit()
        #expect(process.terminationReason == .uncaughtSignal)
        #expect(process.terminationStatus == SIGTERM)
    }

    /// An adapter that ignores `SIGTERM` is `SIGKILL`ed one `killDelay` later.
    @Test func stopKillsAnAdapterThatIgnoresSigterm() async throws {
        let process = try spawn("/bin/sh", ["-c", "trap '' TERM; while :; do sleep 0.1; done"])
        let (client, _) = DataChannel.withDataActor()
        let session = DAPSession(
            channel: client, adapterID: "t", timeout: .milliseconds(300), killDelay: .milliseconds(100),
            process: process)
        await session.stop(terminateDebuggee: true)
        process.waitUntilExit()
        #expect(process.terminationReason == .uncaughtSignal)
        #expect(process.terminationStatus == SIGKILL)
    }

    /// A stand-in for an adapter that says nothing, so the ladder can be walked; not a real adapter.
    private func spawn(_ executable: String, _ arguments: [String]) throws -> Process {
        let process = Process()
        process.executableURL = URL(filePath: executable)
        process.arguments = arguments
        try process.run()
        return process
    }
}
