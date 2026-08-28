import Foundation
import os

/// What a command wrote (git R26: stdout and stderr separated).
nonisolated struct GitOutput: Sendable {
    let stdout: Data
    let stderr: String

    var text: String {
        String(decoding: stdout, as: UTF8.self)
    }
}

/// The version of the binary, from `git --version` (git, edge cases: ≥ 2.35 required).
nonisolated struct GitVersion: Comparable, Sendable {
    static let minimum = GitVersion(major: 2, minor: 35, patch: 0)

    let major: Int
    let minor: Int
    let patch: Int

    var isSupported: Bool {
        self >= Self.minimum
    }

    /// `git version 2.39.5 (Apple Git-154)` → 2.39.5; `nil` when no `x.y[.z]` follows `git version`.
    static func parse(_ text: String) -> GitVersion? {
        let words = text.split(whereSeparator: \.isWhitespace)
        guard words.count >= 3, words[0] == "git", words[1] == "version" else { return nil }
        let numbers = words[2].split(separator: ".").prefix(3).compactMap { Int($0) }
        guard numbers.count >= 2 else { return nil }
        return GitVersion(major: numbers[0], minor: numbers[1], patch: numbers.count > 2 ? numbers[2] : 0)
    }

    static func < (lhs: GitVersion, rhs: GitVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}

/// The user's `git` binary on one repo (git R26–R29, decision 2026-08-27: one instance per repo).
///
/// Nothing exists for this in the retained libraries: it is `Process` with `arguments: [String]`,
/// never a shell, a time bound per kind of command, writes serialised and reads concurrent. Every
/// path handed to git comes after `--` (architecture, security).
actor GitCLI {
    /// git R26: the time a command may take, by what it does.
    nonisolated enum Kind: Sendable {
        case read
        /// A write may run the user's hooks (git R11): bounded like a remote operation.
        case write
        case remote

        var timeout: Duration {
            switch self {
            case .read: return .seconds(30)
            case .write, .remote: return .seconds(600)
            }
        }
    }

    /// Edge cases: another process held the index.
    static let indexLockRetry: Duration = .milliseconds(500)
    /// git R26: `SIGKILL` this long after `SIGTERM` when the process ignored it.
    static let killGrace: Duration = .seconds(2)

    let executable: URL
    let repo: URL
    private let environment: [String: String]
    private var isWriting = false
    private var writeWaiters: [CheckedContinuation<Void, Never>] = []
    private let logger = Logger(subsystem: "dev.crafters.foreman", category: "git")

    /// `loginEnvironment` is the user's shell environment (terminal R3); only what git and its
    /// helpers need is passed on (`environment(from:forRead:)`).
    init(executable: URL, repo: URL, loginEnvironment: [String: String]) {
        self.executable = executable
        self.repo = repo
        environment = loginEnvironment
    }

    // MARK: - Resolving the binary (git R26)

    /// `override` is `git.path` from the config; otherwise the first `git` in `path`.
    nonisolated static func resolveExecutable(inPath path: String?, override: String?) -> URL? {
        if let override, !override.isEmpty {
            return FileManager.default.isExecutableFile(atPath: override) ? URL(filePath: override) : nil
        }
        for directory in (path ?? "").split(separator: ":") {
            let candidate = URL(filePath: String(directory)).appending(path: "git")
            if FileManager.default.isExecutableFile(atPath: candidate.path(percentEncoded: false)) {
                return candidate
            }
        }
        return nil
    }

    /// The version of the binary; `gitNotFound` when it cannot even answer `--version`.
    func version() async throws(GitError) -> GitVersion {
        let output = try await run(["--version"])
        guard let version = GitVersion.parse(output.text) else { throw .gitNotFound }
        return version
    }

    // MARK: - Environment (git R22, R26)

    /// The variables git and its helpers (credential helpers, ssh, gpg) need, nothing else.
    ///
    /// `LC_ALL=C` keeps the output stable for the parsers, `GIT_TERMINAL_PROMPT=0` and no
    /// `SSH_ASKPASS`/`GIT_ASKPASS` make any interaction fail instead of hanging (R22),
    /// `GIT_EDITOR=true` accepts git's prepared messages (`rebase --continue`, `merge`) since the
    /// commit message always comes through `-F` (R10); `GIT_OPTIONAL_LOCKS=0` keeps reads from
    /// touching the index.
    nonisolated static func environment(from login: [String: String], forRead: Bool) -> [String: String] {
        var result: [String: String] = [:]
        for (key, value) in login
        where passedKeys.contains(key) || (key.hasPrefix("GIT_") && !droppedGitKeys.contains(key)) {
            result[key] = value
        }
        result["LC_ALL"] = "C"
        result["GIT_TERMINAL_PROMPT"] = "0"
        result["GIT_EDITOR"] = "true"
        if forRead {
            result["GIT_OPTIONAL_LOCKS"] = "0"
        }
        return result
    }

    private static let passedKeys: Set<String> = [
        "PATH", "HOME", "USER", "LOGNAME", "TMPDIR", "SHELL", "SSH_AUTH_SOCK", "GNUPGHOME", "GPG_TTY",
        "XDG_CONFIG_HOME", "XDG_CACHE_HOME",
    ]

    /// Those would redirect git away from `cwd`, or bring back an interaction.
    private static let droppedGitKeys: Set<String> = [
        "GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_ASKPASS", "GIT_TERMINAL_PROMPT", "GIT_EDITOR",
        "GIT_OPTIONAL_LOCKS",
    ]

    // MARK: - Running (git R26, R28)

    /// Runs git in the repo; a non-zero exit is classified (R28), a locked index retried once.
    ///
    /// `environment` adds to git's variables for this run only (git R30: `GIT_INDEX_FILE`).
    func run(
        _ arguments: [String], kind: Kind = .read, environment: [String: String] = [:]
    ) async throws(GitError)
        -> GitOutput
    {
        if kind == .read {
            return try await runRetryingLock(arguments, kind: kind, environment: environment)
        }
        await acquireWrite()
        defer { releaseWrite() }
        return try await runRetryingLock(arguments, kind: kind, environment: environment)
    }

    /// git R30: a tree of the whole working tree (tracked, modified, untracked; ignored left out),
    /// written through a temporary index so the user's index is never touched (R29).
    func snapshotTree() async throws(GitError) -> String {
        let index = FileManager.default.temporaryDirectory.appending(path: "foreman-index-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: index) }
        let environment = ["GIT_INDEX_FILE": index.path(percentEncoded: false)]
        _ = try await run(["add", "-A", "--", "."], environment: environment)
        return try await run(["write-tree"], environment: environment).text
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func runRetryingLock(
        _ arguments: [String], kind: Kind, environment: [String: String]
    )
        async throws(GitError) -> GitOutput
    {
        do {
            return try await execute(arguments, kind: kind, environment: environment)
        } catch .commandFailed(let stderr) where GitError.isIndexLocked(stderr: stderr) {
            logger.info("index.lock held, retrying once")
            guard (try? await Task.sleep(for: Self.indexLockRetry)) != nil else { throw .cancelled }
            return try await execute(arguments, kind: kind, environment: environment)
        }
    }

    private func acquireWrite() async {
        guard isWriting else {
            isWriting = true
            return
        }
        await withCheckedContinuation { continuation in
            writeWaiters.append(continuation)
        }
    }

    private func releaseWrite() {
        guard !writeWaiters.isEmpty else {
            isWriting = false
            return
        }
        writeWaiters.removeFirst().resume()
    }

    private func execute(
        _ arguments: [String], kind: Kind, environment extra: [String: String]
    ) async throws(GitError)
        -> GitOutput
    {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = repo
        process.environment = Self.environment(from: environment, forRead: kind == .read).merging(extra) { _, own in own
        }
        process.standardInput = FileHandle.nullDevice
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        let (exited, exit) = AsyncStream<Void>.makeStream()
        process.terminationHandler = { _ in exit.finish() }
        do {
            try process.run()
        } catch {
            logger.error("git not launched: \(error.localizedDescription, privacy: .public)")
            throw .gitNotFound
        }
        let pid = process.processIdentifier
        let watchdog = Task {
            guard (try? await Task.sleep(for: kind.timeout)) != nil else { return false }
            Self.terminate(pid)
            return true
        }
        async let outData = Self.readToEnd(stdout.fileHandleForReading)
        async let errData = Self.readToEnd(stderr.fileHandleForReading)
        await withTaskCancellationHandler {
            for await _ in exited {}
        } onCancel: {
            Self.terminate(pid)
        }
        watchdog.cancel()
        let timedOut = await watchdog.value
        let output = GitOutput(stdout: await outData, stderr: String(decoding: await errData, as: UTF8.self))
        if timedOut {
            throw .timeout
        }
        if Task.isCancelled {
            throw .cancelled
        }
        guard process.terminationStatus == 0 else {
            // git R11: a hook's output may be on stdout; the user sees both.
            throw GitError.classify(stderr: Self.failureText(stdout: output.text, stderr: output.stderr))
        }
        return output
    }

    /// stderr first, then whatever stdout says, each trimmed; the classification reads both.
    nonisolated static func failureText(stdout: String, stderr: String) -> String {
        [stderr, stdout].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    /// git R26: `SIGTERM`, then `SIGKILL` after the grace period if the process is still there.
    private nonisolated static func terminate(_ pid: pid_t) {
        kill(pid, SIGTERM)
        Task {
            try? await Task.sleep(for: killGrace)
            kill(pid, SIGKILL)
        }
    }

    @concurrent
    private static func readToEnd(_ handle: FileHandle) async -> Data {
        (try? handle.readToEnd()) ?? Data()
    }
}
