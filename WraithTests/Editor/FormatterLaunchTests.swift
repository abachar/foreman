import Foundation
import Testing

@testable import Wraith

/// editor R26–R28, R30: the invocation, the decision to apply, and the launching over POSIX
/// binaries only (`cat`, `false`, `sleep`) — never a formatter.
struct FormatterLaunchTests {
    private let cwd = URL(filePath: "/private/tmp")
    /// `/bin/sh` as the login shell, an empty `HOME`: nothing of the author's profile runs.
    private let environment = ["SHELL": "/bin/sh", "HOME": "/private/tmp", "PATH": "/usr/bin:/bin"]

    @Test func buildsALoginShellInvocationWithoutInterpolation() {
        let command = "prettier --stdin-filepath \"$FILE\" && echo done"
        let invocation = FormatterLaunch.invocation(command: command, cwd: cwd, environment: environment)
        #expect(invocation.executable == "/bin/sh")
        #expect(invocation.arguments == ["-l", "-c", command])
        #expect(invocation.cwd == cwd)
        #expect(invocation.environment == environment)
    }

    @Test func fallsBackToZshWhenTheShellIsMissingOrNotExecutable() {
        #expect(FormatterLaunch.invocation(command: "x", cwd: cwd, environment: [:]).executable == "/bin/zsh")
        #expect(
            FormatterLaunch.invocation(command: "x", cwd: cwd, environment: ["SHELL": "/nonexistent/sh"]).executable
                == "/bin/zsh")
    }

    @Test func refusesANonZeroStatusEvenWithOutput() {
        #expect(
            FormatterLaunch.decide(status: 1, stdout: "formatted", stderr: "warning\n", original: "x")
                == .failed(status: 1, stderr: "warning"))
    }

    @Test func refusesAnEmptyOutput() {
        #expect(
            FormatterLaunch.decide(status: 0, stdout: "", stderr: "", original: "x")
                == .failed(status: 0, stderr: "the formatter wrote nothing"))
    }

    @Test func identicalTextIsUnchangedAndDifferentTextIsFormatted() {
        #expect(FormatterLaunch.decide(status: 0, stdout: "a\n", stderr: "", original: "a\n") == .unchanged)
        #expect(FormatterLaunch.decide(status: 0, stdout: "a\n", stderr: "", original: "a") == .formatted("a\n"))
    }

    @Test func truncatesStderrForTheBanner() {
        let long = String(repeating: "e", count: 1000)
        let truncated = FormatterLaunch.truncated("\n" + long + "\n")
        #expect(truncated.count == FormatterLaunch.stderrLimit + 1)
        #expect(truncated.hasSuffix("…"))
        #expect(FormatterLaunch.truncated("  short  \n") == "short")
    }

    @Test func catIsTheIdentity() async {
        let text = String(repeating: "line of text\n", count: 20_000)
        let result = await FormatterLaunch.run(
            text, command: "/bin/cat", cwd: cwd, environment: environment, timeout: .seconds(10))
        #expect(result == .unchanged)
        let upper = await FormatterLaunch.run(
            "abc\n", command: "/usr/bin/tr a-z A-Z", cwd: cwd, environment: environment, timeout: .seconds(10))
        #expect(upper == .formatted("ABC\n"))
    }

    @Test func falseFailsWithoutOutput() async {
        let result = await FormatterLaunch.run(
            "abc", command: "/usr/bin/false", cwd: cwd, environment: environment, timeout: .seconds(10))
        #expect(result == .failed(status: 1, stderr: ""))
    }

    @Test func stderrAndTheStatusComeBack() async {
        let result = await FormatterLaunch.run(
            "abc", command: "echo formatted; echo bad input >&2; exit 3", cwd: cwd, environment: environment,
            timeout: .seconds(10))
        #expect(result == .failed(status: 3, stderr: "bad input"))
    }

    @Test func aSlowFormatterIsStoppedAndTheTextIsIntact() async {
        let clock = ContinuousClock()
        let start = clock.now
        let result = await FormatterLaunch.run(
            "abc", command: "/bin/sleep 30", cwd: cwd, environment: environment, timeout: .milliseconds(300))
        #expect(result == .timedOut)
        #expect(clock.now - start < .seconds(5))
    }
}
