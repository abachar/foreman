import Foundation
import JSONRPC
import LanguageServerProtocol
import Network
import os

/// The two ways to reach an adapter (debug R1): the stdio of a process, or a TCP port on localhost.
/// Each ends in the same framed `DataChannel`, so the session does not know which it has.
extension DAPSession {
    /// debug R1, R9: the user's command run by `$SHELL -l -c` with the login environment, exactly as
    /// `LSPServer` runs a language server; its `stderr` goes to the `debug` log.
    static func stdio(
        command: String, cwd: URL, environment: [String: String], adapterID: String, timeout: Duration
    ) throws -> DAPSession {
        let invocation = FormatterLaunch.invocation(command: command, cwd: cwd, environment: environment)
        let process = Process()
        process.executableURL = URL(filePath: invocation.executable)
        process.arguments = invocation.arguments
        process.currentDirectoryURL = invocation.cwd
        process.environment = invocation.environment
        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        do {
            try process.run()
        } catch {
            throw Failure.unreachable(
                "`\(FormatterCatalog.binary(of: command))` did not start: \(error.localizedDescription)")
        }
        let writer = PipeIO.Writer(stdin.fileHandleForWriting)
        let channel = DataChannel(
            writeHandler: { await writer.write($0) },
            dataSequence: PipeIO.chunks(stdout.fileHandleForReading)
        ).withMessageFraming()
        let session = DAPSession(
            channel: channel, adapterID: adapterID, timeout: timeout, process: process, close: { writer.close() })
        Task {
            let logger = Logger(subsystem: "dev.crafters.foreman", category: "debug")
            for await chunk in PipeIO.chunks(stderr.fileHandleForReading) {
                guard let text = String(data: chunk, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                    !text.isEmpty
                else { continue }
                logger.debug("\(adapterID, privacy: .public) stderr: \(text.prefix(200), privacy: .private)")
                if let line = LSPServer.meaningfulLine(of: text) {
                    await session.noteStandardError(line)
                }
            }
        }
        return session
    }

    /// debug R1, R12: a connection to `localhost:<port>`, bounded by `timeout`; a refused port
    /// fails at once (`waiting`) instead of retrying for the whole delay.
    static func tcp(port: Int, adapterID: String, timeout: Duration) async throws -> DAPSession {
        guard let port = UInt16(exactly: port), let endpointPort = NWEndpoint.Port(rawValue: port) else {
            throw Failure.unreachable("\(port) is not a TCP port")
        }
        let connection = NWConnection(host: "localhost", port: endpointPort, using: .tcp)
        let (states, changes) = AsyncStream<NWConnection.State>.makeStream()
        connection.stateUpdateHandler = { changes.yield($0) }
        connection.start(queue: .global())
        let timer = Task {
            try await Task.sleep(for: timeout)
            connection.cancel()
        }
        defer { timer.cancel() }
        waiting: for await state in states {
            switch state {
            case .ready:
                break waiting
            case .waiting(let error), .failed(let error):
                connection.cancel()
                throw Failure.unreachable("localhost:\(port): \(error.localizedDescription)")
            case .cancelled:
                throw Failure.timeout("localhost:\(port)")
            case .setup, .preparing:
                continue
            @unknown default:
                continue
            }
        }
        connection.stateUpdateHandler = nil
        let received = AsyncStream<Data> { continuation in
            @Sendable func next() {
                connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
                    if let data, !data.isEmpty {
                        continuation.yield(data)
                    }
                    if isComplete || error != nil {
                        continuation.finish()
                    } else {
                        next()
                    }
                }
            }
            next()
        }
        let channel = DataChannel(
            writeHandler: { data in
                try await withCheckedThrowingContinuation { (done: CheckedContinuation<Void, any Error>) in
                    connection.send(
                        content: data,
                        completion: .contentProcessed { error in
                            if let error { done.resume(throwing: error) } else { done.resume() }
                        })
                }
            }, dataSequence: received
        ).withMessageFraming()
        return DAPSession(channel: channel, adapterID: adapterID, timeout: timeout, close: { connection.cancel() })
    }
}
