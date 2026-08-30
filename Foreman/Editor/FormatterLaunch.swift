import Foundation

/// Runs the user's formatter over the text (editor R26–R28, R30, R33): the command as is in the
/// login shell, the text on `stdin`, the result on `stdout`, the diagnostics on `stderr`.
///
/// Named after `TerminalLaunch` rather than `Formatter`, which Foundation already defines.
nonisolated enum FormatterLaunch {
    enum Result: Equatable, Sendable {
        case formatted(String)
        case unchanged
        case failed(status: Int32, stderr: String)
        case timedOut
    }

    /// How the process is started; built by a pure function so it can be checked.
    struct Invocation: Equatable, Sendable {
        let executable: String
        let arguments: [String]
        let cwd: URL
        let environment: [String: String]
    }

    /// editor R28: what of `stderr` reaches the banner.
    static let stderrLimit = 400
    /// editor R30: after `SIGTERM`, the grace before `SIGKILL`.
    static let killDelay: Duration = .seconds(1)

    /// editor R26: `$SHELL -l -c <command>` (the shell of `environment`, `/bin/zsh` when absent or
    /// not executable), nothing interpolated.
    static func invocation(command: String, cwd: URL, environment: [String: String]) -> Invocation {
        let shell = environment["SHELL"].flatMap { FileManager.default.isExecutableFile(atPath: $0) ? $0 : nil }
        return Invocation(
            executable: shell ?? TerminalLaunch.fallbackShell, arguments: ["-l", "-c", command], cwd: cwd,
            environment: environment)
    }

    /// editor R28: applied only on exit `0`, a non-empty `stdout` and a different text.
    static func decide(status: Int32, stdout: String, stderr: String, original: String) -> Result {
        guard status == 0 else { return .failed(status: status, stderr: truncated(stderr)) }
        guard !stdout.isEmpty else {
            return .failed(status: 0, stderr: truncated(stderr.isEmpty ? "the formatter wrote nothing" : stderr))
        }
        return stdout == original ? .unchanged : .formatted(stdout)
    }

    /// The first line(s) of `stderr`, trimmed and capped: a banner, not a log.
    static func truncated(_ stderr: String) -> String {
        let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > stderrLimit else { return trimmed }
        return String(trimmed.prefix(stderrLimit)) + "…"
    }

    /// editor R26, R27, R30: runs `command` off the main actor with `text` on `stdin`; past
    /// `timeout` the process gets `SIGTERM`, then `SIGKILL` one second later.
    @concurrent
    static func run(
        _ text: String, command: String, cwd: URL, environment: [String: String], timeout: Duration
    ) async -> Result {
        let invocation = invocation(command: command, cwd: cwd, environment: environment)
        let process = Process()
        process.executableURL = URL(filePath: invocation.executable)
        process.arguments = invocation.arguments
        process.currentDirectoryURL = invocation.cwd
        process.environment = invocation.environment
        let input = Pipe()
        let output = Pipe()
        let errors = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors
        // A formatter that exits before reading its input closes the pipe: EPIPE, not SIGPIPE.
        _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        let (exits, exited) = AsyncStream<Int32>.makeStream()
        process.terminationHandler = { process in
            exited.yield(process.terminationStatus)
            exited.finish()
        }
        do {
            try process.run()
        } catch {
            return .failed(status: -1, stderr: truncated(error.localizedDescription))
        }
        let pid = process.processIdentifier
        let reaper = Task<Bool, Never> {
            guard (try? await Task.sleep(for: timeout)) != nil else { return false }
            kill(pid, SIGTERM)
            if (try? await Task.sleep(for: killDelay)) != nil {
                kill(pid, SIGKILL)
                // A child of the formatter may keep the pipes open: closing them ends the reads.
                try? output.fileHandleForReading.close()
                try? errors.fileHandleForReading.close()
            }
            return true
        }
        async let stdout = PipeIO.readToEnd(output.fileHandleForReading)
        async let stderr = PipeIO.readToEnd(errors.fileHandleForReading)
        await PipeIO.writeAndClose(Data(text.utf8), to: input.fileHandleForWriting)
        var status: Int32 = -1
        for await exit in exits {
            status = exit
        }
        reaper.cancel()
        let (formatted, diagnostics) = await (stdout, stderr)
        if await reaper.value {
            return .timedOut
        }
        return decide(
            status: status, stdout: String(decoding: formatted, as: UTF8.self),
            stderr: String(decoding: diagnostics, as: UTF8.self), original: text)
    }
}
