import Foundation
import Testing

@testable import Foreman

/// The shell, arguments and environment of a launch (terminal R1–R3, edge cases).
struct TerminalLaunchTests {
    private let root = URL(filePath: "/tmp/ws")
    private let cwd = URL(filePath: "/tmp/ws/backend")

    private func launch(shell: String?, isExecutable: Bool = true, extra: [String: String] = [:]) -> TerminalLaunch {
        TerminalLaunch(
            command: "claude --continue", cwd: cwd, root: root, extraEnvironment: extra, shell: shell,
            baseEnvironment: ["HOME": "/Users/me", "TERM": "dumb"], isExecutable: { _ in isExecutable })
    }

    @Test func runsTheCommandThroughTheLoginShell() {
        let launch = launch(shell: "/opt/homebrew/bin/fish")

        #expect(launch.executable == "/opt/homebrew/bin/fish")
        #expect(launch.arguments == ["-l", "-c", "claude --continue"])
        #expect(launch.currentDirectory == "/tmp/ws/backend")
    }

    @Test func fallsBackToZshWhenShellIsMissingOrNotExecutable() {
        #expect(launch(shell: nil).executable == "/bin/zsh")
        #expect(launch(shell: "").executable == "/bin/zsh")
        #expect(launch(shell: "/bin/nope", isExecutable: false).executable == "/bin/zsh")
    }

    @Test func enrichesTheEnvironmentAndLetsTheFeatureWin() {
        let launch = launch(shell: "/bin/zsh", extra: ["PORT": "3000", "TERM_PROGRAM": "custom"])

        #expect(
            launch.environment == [
                "COLORTERM=truecolor", "FOREMAN_WORKSPACE=/tmp/ws", "HOME=/Users/me", "PORT=3000",
                "TERM=xterm-256color", "TERM_PROGRAM=custom",
            ])
    }
}
