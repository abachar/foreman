import Foundation
import JSONRPC
import LanguageServerProtocol
import Testing

@testable import Foreman

/// M27 27.1's live check: the real `xcrun lldb-dap` on stdio, launching Foreman's own Debug build.
///
/// `/usr/bin/true` is refused by lldb under SIP ("Not allowed to attach to process"), so the program
/// is this very executable, started a second time and stopped on entry, then terminated by `disconnect`.
///
/// Off by default — no default test launches an adapter. Run it with
/// `TEST_RUNNER_FOREMAN_DAP_LIVE=1 xcodebuild test … -only-testing:ForemanTests/DAPSessionLiveTests`
/// (the variable is read from xcodebuild's own environment).
struct DAPSessionLiveTests {
    @Test(
        .enabled(if: ProcessInfo.processInfo.environment["FOREMAN_DAP_LIVE"] == "1"),
        .timeLimit(.minutes(1)))
    func stopsAProgramOnEntryThroughLldbDap() async throws {
        let program = try #require(Bundle.main.executableURL?.path(percentEncoded: false))
        let session = try DAPSession.stdio(
            command: "xcrun lldb-dap", cwd: FileManager.default.temporaryDirectory,
            environment: ProcessInfo.processInfo.environment, adapterID: "swift", timeout: .seconds(5))
        var messages = session.messages.makeAsyncIterator()
        var seen: [String] = []
        var stopped: DAPStoppedEvent?
        var threads: [DAPThread] = []
        do {
            try await session.start(
                .launch, arguments: .hash(["program": .string(program), "stopOnEntry": .bool(true)]))
            while stopped == nil, let message = await messages.next() {
                if message.type == .request {
                    await session.respond(to: message, success: false, message: "not supported in this check")
                } else if message.event == "stopped" {
                    stopped = try message.decodedBody(DAPStoppedEvent.self)
                }
                seen.append(message.event ?? message.command ?? "?")
            }
            threads = try await session.send("threads", DAPEmpty(), as: DAPThreadsResponse.self).threads
        } catch {
            // The adapter is never left running (debug R11), whatever went wrong.
            await session.stop(terminateDebuggee: true)
            throw error
        }
        await session.stop(terminateDebuggee: true)
        while let message = await messages.next() {
            seen.append(message.event ?? "?")
        }
        // lldb-dap reports the stop on entry as an `exception` (checked 2026-10-17), not `entry`.
        #expect(stopped != nil, "events: \(seen)")
        #expect(!threads.isEmpty, "events: \(seen)")
        #expect(seen.contains("terminated") || seen.contains("exited"), "events: \(seen)")
    }
}
