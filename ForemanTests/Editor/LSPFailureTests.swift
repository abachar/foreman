import Foundation
import Testing

@testable import Foreman

/// editor R39: what the banner says when a server does not run.
///
/// The rule this file exists for: a server that cannot start almost always says why in one line,
/// and that line is worth more than anything Foreman can infer from the outside. Met on a React
/// project, 2026-08-31 — `typescript-language-server` without `--stdio` exits at once with the
/// exact reason, and the banner said "stopped twice".
struct LSPFailureTests {
    @Test func showsTheServersOwnWordsWhenItNeverAnswered() {
        let message = LSPServer.startupFailure(
            binary: "typescript-language-server", stderr: "error: required option '--stdio' not specified",
            timeout: .seconds(10))
        #expect(message == "`typescript-language-server`: error: required option '--stdio' not specified")
    }

    /// A server that hangs says nothing, and then the timeout is all there is to report.
    @Test func fallsBackToTheTimeoutWhenItSaidNothing() {
        #expect(
            LSPServer.startupFailure(binary: "jdtls", stderr: nil, timeout: .seconds(10))
                == "`jdtls` did not answer in 10 s")
        #expect(
            LSPServer.startupFailure(binary: "jdtls", stderr: "", timeout: .seconds(30))
                == "`jdtls` did not answer in 30 s")
    }

    @Test func carriesTheReasonIntoTheSecondDeath() {
        #expect(
            LSPServer.deathFailure(binary: "gopls", stderr: "cannot find module")
                == "`gopls` stopped twice — cannot find module")
        #expect(
            LSPServer.deathFailure(binary: "gopls", stderr: nil)
                == "`gopls` stopped twice — no LSP for this language")
    }

    /// The useful line is the last: `node` prefixes its own noise and a usage message ends with
    /// what was actually wrong.
    @Test func takesTheLastLineThatSaysSomething() {
        let output = "Usage: typescript-language-server [options]\n\n  --stdio\n\nerror: missing --stdio\n\n"
        #expect(LSPServer.meaningfulLine(of: output) == "error: missing --stdio")
    }

    @Test func hasNothingToShowForEmptyOutput() {
        #expect(LSPServer.meaningfulLine(of: "") == nil)
        #expect(LSPServer.meaningfulLine(of: "\n \n\t\n") == nil)
        // A single character is noise, not a reason.
        #expect(LSPServer.meaningfulLine(of: ">") == nil)
    }

    /// A banner is one line: a server that dumps a stack trace does not take the window with it.
    @Test func capsAVeryLongLine() throws {
        let line = try #require(LSPServer.meaningfulLine(of: String(repeating: "x", count: 400)))
        #expect(line.count == 201)
        #expect(line.hasSuffix("…"))
    }
}
