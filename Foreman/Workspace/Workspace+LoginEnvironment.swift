import Foundation

/// terminal R3, agents R2: the environment of the user's login shell (PATH, profiles), resolved
/// once per window by running `$SHELL -l -c` over `/usr/bin/env -0` off the main actor; the app's
/// own environment when the shell cannot be run, hangs past the timeout, or prints nothing usable.
extension Workspace {
    /// How long the login shell may take: a profile that prompts or hangs must not freeze git,
    /// the editor and the agents forever (coding rules, concurrency).
    private nonisolated static let loginEnvironmentTimeout: Duration = .seconds(10)

    /// Printed by the shell command right before `env -0`, ended by a NUL of its own: whatever the
    /// profiles echo lands before it and can never fuse with the first `KEY=VALUE` record.
    nonisolated static let environmentSentinel = "FOREMAN_LOGIN_ENVIRONMENT"

    func loginEnvironment() async -> [String: String] {
        if let task = loginEnvironmentTask {
            return await task.value
        }
        let task = Task { await Self.resolveLoginEnvironment() }
        loginEnvironmentTask = task
        return await task.value
    }

    @concurrent
    private static func resolveLoginEnvironment() async -> [String: String] {
        let environment = ProcessInfo.processInfo.environment
        let shell = environment["SHELL"].flatMap { FileManager.default.isExecutableFile(atPath: $0) ? $0 : nil }
        let process = Process()
        process.executableURL = URL(filePath: shell ?? TerminalLaunch.fallbackShell)
        process.arguments = ["-l", "-c", "/usr/bin/printf '\(environmentSentinel)\\0'; /usr/bin/env -0"]
        let output = Pipe()
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        let (exited, exit) = AsyncStream<Void>.makeStream()
        process.terminationHandler = { _ in exit.finish() }
        do {
            try process.run()
        } catch {
            return environment
        }
        let pid = process.processIdentifier
        let reader = output.fileHandleForReading
        let watchdog = Task {
            guard (try? await Task.sleep(for: loginEnvironmentTimeout)) != nil else { return }
            kill(pid, SIGTERM)
            // Closing the pipe ends the read below even when a child of the profile survives
            // the signal and keeps the write end open.
            try? reader.close()
        }
        let data = await readToEnd(reader)
        for await _ in exited {}
        watchdog.cancel()
        let parsed = parseEnvironment(data)
        return parsed.isEmpty ? environment : parsed
    }

    /// The whole pipe, accumulated without holding a pool thread; a timed-out shell leaves the
    /// sentinel unwritten, so a partial read parses to nothing and the caller falls back.
    @concurrent
    private static func readToEnd(_ handle: FileHandle) async -> Data {
        var data = Data()
        do {
            for try await byte in handle.bytes {
                data.append(byte)
            }
        } catch {
            // The watchdog closed the pipe: what was read so far is all there is.
            return data
        }
        return data
    }

    /// The `env -0` output after the sentinel: `KEY=VALUE` records separated by NUL, values may
    /// hold newlines. Without the sentinel nothing is trusted and the result is empty.
    nonisolated static func parseEnvironment(_ data: Data) -> [String: String] {
        guard let marker = data.firstRange(of: Data((environmentSentinel + "\0").utf8)) else { return [:] }
        var result: [String: String] = [:]
        for record in data[marker.upperBound...].split(separator: 0) {
            guard let text = String(data: record, encoding: .utf8), let separator = text.firstIndex(of: "=") else {
                continue
            }
            result[String(text[..<separator])] = String(text[text.index(after: separator)...])
        }
        return result
    }
}
