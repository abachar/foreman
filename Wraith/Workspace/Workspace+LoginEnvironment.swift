import Foundation

/// terminal R3, agents R2: the environment of the user's login shell (PATH, profiles), resolved
/// once per window by running `$SHELL -l -c '/usr/bin/env -0'` off the main actor; the app's own
/// environment when the shell cannot be run.
extension Workspace {
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
        process.arguments = ["-l", "-c", "/usr/bin/env -0"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return environment
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let parsed = parseEnvironment(data)
        return parsed.isEmpty ? environment : parsed
    }

    /// The `env -0` output: `KEY=VALUE` records separated by NUL, values may hold newlines.
    nonisolated static func parseEnvironment(_ data: Data) -> [String: String] {
        var result: [String: String] = [:]
        for record in data.split(separator: 0) {
            guard let text = String(data: record, encoding: .utf8), let separator = text.firstIndex(of: "=") else {
                continue
            }
            result[String(text[..<separator])] = String(text[text.index(after: separator)...])
        }
        return result
    }
}
