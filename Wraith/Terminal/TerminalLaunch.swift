import Foundation

/// What a surface starts: the user's login shell running one command in one folder (terminal R1–R3).
///
/// A value, built once per launch, so the resolution of the shell and of the environment can be
/// tested without a PTY.
nonisolated struct TerminalLaunch: Equatable, Sendable {
    static let fallbackShell = "/bin/zsh"

    let executable: String
    let arguments: [String]
    /// `KEY=VALUE` lines, the form `LocalProcessTerminalView.startProcess` takes.
    let environment: [String]
    let currentDirectory: String

    /// `command` is the feature's text, passed as is (architecture, security); `extraEnvironment`
    /// is the feature's `env` (run R8), applied last; `shell` is `$SHELL`, replaced by `/bin/zsh`
    /// when missing or not executable (edge cases); `baseEnvironment` is the app's own, the login
    /// shell rebuilds PATH and profiles on top of it.
    init(
        command: String,
        cwd: URL,
        root: URL,
        extraEnvironment: [String: String] = [:],
        shell: String?,
        baseEnvironment: [String: String],
        isExecutable: (String) -> Bool
    ) {
        if let shell, !shell.isEmpty, isExecutable(shell) {
            executable = shell
        } else {
            executable = Self.fallbackShell
        }
        // terminal R1: `-l` loads the user's environment, `-c` runs the command, no prompt.
        arguments = ["-l", "-c", command]
        var variables = baseEnvironment
        // terminal R3
        variables["TERM"] = "xterm-256color"
        variables["COLORTERM"] = "truecolor"
        variables["TERM_PROGRAM"] = "wraith"
        variables["WRAITH_WORKSPACE"] = root.path(percentEncoded: false)
        for (key, value) in extraEnvironment {
            variables[key] = value
        }
        environment = variables.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }
        currentDirectory = cwd.path(percentEncoded: false)
    }
}
