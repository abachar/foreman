import Foundation
import JSONRPC
import LanguageServerProtocol
import os

/// One conversation with a debug adapter (debug R9): numbered requests, their answers matched by
/// `request_seq`, events and reverse requests handed to the owner as a stream.
///
/// The channel is already framed (`Content-Length`, see `DAPSession+Transport`); one `Data` is one
/// message. Everything the adapter says is untrusted content (debug R12): it is decoded, never run.
actor DAPSession {
    /// The breakpoints of one file, sent by `setBreakpoints` once the adapter is ready (debug R4, R9).
    nonisolated struct FileBreakpoints: Equatable, Sendable {
        var path: String
        var lines: [Int]

        /// The request's body: the path, the lines in the order given.
        var arguments: DAPSetBreakpointsArguments {
            DAPSetBreakpointsArguments(source: DAPSource(path: path), breakpoints: lines.map { .init(line: $0) })
        }
    }

    /// Why a request did not come back with a body.
    enum Failure: Error, Equatable, CustomStringConvertible {
        case timeout(String)
        /// The adapter's own sentence (debug R11).
        case rejected(command: String, message: String)
        case closed
        /// The adapter could not be started or reached (a process that does not launch, a refused port).
        case unreachable(String)

        var description: String {
            switch self {
            case .timeout(let what): return "no answer to \(what)"
            case .rejected(let command, let message): return "\(command): \(message)"
            case .closed: return "the adapter closed the connection"
            case .unreachable(let reason): return reason
            }
        }
    }

    /// Events and reverse requests, in arrival order; finishes when the adapter's side closes.
    nonisolated let messages: AsyncStream<DAPMessage>

    private enum Slot {
        case sent
        case waiting(CheckedContinuation<LSPAny, any Error>)
        case arrived(Result<LSPAny, any Error>)
    }

    /// The `initialized` event is awaited like an answer, under a key no request uses.
    private static let initializedKey = 0

    private let write: DataChannel.WriteHandler
    private let adapterID: String
    private let timeout: Duration
    private let killDelay: Duration
    private let process: Process?
    private let close: @Sendable () -> Void
    private let output: AsyncStream<DAPMessage>.Continuation
    private let logger = Logger(subsystem: "dev.crafters.foreman", category: "debug")
    private var seq = 0
    private var slots: [Int: Slot] = [:]
    private var isClosed = false
    /// The last line the adapter wrote on `stderr`, for the banner when it says nothing else (R11).
    private(set) var lastError: String?

    init(
        channel: DataChannel, adapterID: String, timeout: Duration, killDelay: Duration = .seconds(1),
        process: Process? = nil, close: @escaping @Sendable () -> Void = {}
    ) {
        write = channel.writeHandler
        self.adapterID = adapterID
        self.timeout = timeout
        self.killDelay = killDelay
        self.process = process
        self.close = close
        (messages, output) = AsyncStream<DAPMessage>.makeStream()
        Task { [weak self] in
            for await data in channel.dataSequence {
                await self?.receive(data)
            }
            await self?.finish()
        }
    }

    deinit {
        close()
        output.finish()
        if process?.isRunning == true {
            process?.terminate()
        }
    }

    // MARK: - Start and stop (debug R9)

    /// `initialize`, the `launch` or `attach` request, then — on the `initialized` event — the
    /// breakpoints and `configurationDone`; the request's own answer ends the start.
    ///
    /// Adapters answer `launch` late (`lldb-dap` only after `configurationDone`), so it is sent
    /// first and awaited last. The adapter's answer to each file's breakpoints is returned, by path.
    @discardableResult
    func start(
        _ request: DebugCommand.Request, arguments: LSPAny, breakpoints: [FileBreakpoints] = []
    ) async throws
        -> [String: DAPSetBreakpointsResponse]
    {
        slots[Self.initializedKey] = .sent
        let capabilities: DAPCapabilities = try await send(
            "initialize", DAPInitializeArguments(adapterID: adapterID), as: DAPCapabilities.self)
        let launch = try await post(request.rawValue, arguments)
        // debug R9 bounds `initialize` and the connection, not these two: an attach adapter
        // waits for the program (`java-debug` retries the JDWP port for its own `timeout` while
        // Spring Boot starts) before it sends `initialized`, and a launch answers after the
        // program is up. ■ ends the wait (found on `ccoe`, 2026-10-18).
        try await answer(to: Self.initializedKey, "the initialized event", bounded: false)
        var answers: [String: DAPSetBreakpointsResponse] = [:]
        for file in breakpoints {
            answers[file.path] = try await setBreakpoints(file)
        }
        if capabilities.supportsConfigurationDoneRequest != false {
            try await send("configurationDone", DAPEmpty())
        }
        try await answer(to: launch, request.rawValue, bounded: false)
        return answers
    }

    /// debug R4: the whole set of one file, which replaces what the adapter had for it.
    func setBreakpoints(_ file: FileBreakpoints) async throws -> DAPSetBreakpointsResponse {
        try await send("setBreakpoints", file.arguments, as: DAPSetBreakpointsResponse.self)
    }

    /// `disconnect`, then — if the adapter does not end within the timeout — `SIGTERM`, and
    /// `SIGKILL` one `killDelay` later (editor R36's ladder).
    func stop(terminateDebuggee: Bool) async {
        if !isClosed {
            _ = try? await send("disconnect", DAPDisconnectArguments(terminateDebuggee: terminateDebuggee))
        }
        close()
        if let process, !(await ended(process, within: timeout)) {
            process.terminate()
            if !(await ended(process, within: killDelay)) {
                kill(process.processIdentifier, SIGKILL)
            }
        }
        finish()
    }

    private func ended(_ process: Process, within limit: Duration) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: limit)
        while process.isRunning {
            guard ContinuousClock.now < deadline else { return false }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return true
    }

    func noteStandardError(_ line: String) {
        lastError = line
    }

    // MARK: - Requests

    /// A request and its body, bounded by the timeout (debug R9).
    @discardableResult
    func send<A: Encodable, B: Decodable>(_ command: String, _ arguments: A, as type: B.Type) async throws -> B {
        let seq = try await post(command, arguments)
        return try await answer(to: seq, command).decoded(type)
    }

    @discardableResult
    func send(_ command: String, _ arguments: some Encodable) async throws -> LSPAny {
        let seq = try await post(command, arguments)
        return try await answer(to: seq, command)
    }

    /// Answers a reverse request, so an adapter never waits for a reply (debug R8).
    func respond(to request: DAPMessage, success: Bool, message: String? = nil, body: LSPAny? = nil) async {
        seq += 1
        await transmit(
            DAPMessage(
                seq: seq, type: .response, command: request.command, body: body, requestSeq: request.seq,
                success: success, message: message))
    }

    /// Numbers the request, makes room for its answer, then writes it: an answer that beats the
    /// caller to `answer(to:)` waits in its slot instead of being lost.
    private func post(_ command: String, _ arguments: some Encodable) async throws -> Int {
        guard !isClosed else { throw Failure.closed }
        seq += 1
        let number = seq
        slots[number] = .sent
        await transmit(
            DAPMessage(seq: number, type: .request, command: command, arguments: try LSPAny(encoding: arguments)))
        return number
    }

    private func transmit(_ message: DAPMessage) async {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .withoutEscapingSlashes
            try await write(encoder.encode(message))
        } catch {
            logger.error("write failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    @discardableResult
    private func answer(to key: Int, _ what: String, bounded: Bool = true) async throws -> LSPAny {
        let timer = Task { [timeout] in
            guard bounded else { return }
            try await Task.sleep(for: timeout)
            self.deliver(key, .failure(Failure.timeout(what)))
        }
        defer { timer.cancel() }
        if case .arrived(let result)? = slots[key] {
            slots[key] = nil
            return try result.get()
        }
        return try await withCheckedThrowingContinuation { slots[key] = .waiting($0) }
    }

    // MARK: - Reading

    private func receive(_ data: Data) {
        guard let message = try? JSONDecoder().decode(DAPMessage.self, from: data) else {
            logger.debug("undecodable message (\(data.count) bytes)")
            return
        }
        switch message.type {
        case .response:
            guard let key = message.requestSeq else { return }
            if message.success == true {
                deliver(key, .success(message.body ?? .null))
            } else {
                deliver(
                    key,
                    .failure(Failure.rejected(command: message.command ?? "request", message: Self.reason(of: message)))
                )
            }
        case .event:
            if message.event == "initialized" {
                deliver(Self.initializedKey, .success(.null))
            }
            output.yield(message)
        case .request:
            output.yield(message)
        }
    }

    /// The error response's `message`, else the `format` of the `error` object of its body.
    private static func reason(of response: DAPMessage) -> String {
        if let message = response.message, !message.isEmpty {
            return message
        }
        if case .hash(let body)? = response.body, case .hash(let error)? = body["error"],
            case .string(let format)? = error["format"]
        {
            return format
        }
        return "the request failed"
    }

    private func deliver(_ key: Int, _ result: Result<LSPAny, any Error>) {
        switch slots[key] {
        case .waiting(let continuation)?:
            slots[key] = nil
            continuation.resume(with: result)
        case .sent?:
            slots[key] = .arrived(result)
        case .arrived?, nil:
            break
        }
    }

    /// The adapter's side closed, or `stop` ran: nothing more will come.
    private func finish() {
        guard !isClosed else { return }
        isClosed = true
        for key in Array(slots.keys) {
            deliver(key, .failure(Failure.closed))
        }
        output.finish()
    }
}
