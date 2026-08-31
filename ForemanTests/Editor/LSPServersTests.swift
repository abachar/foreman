import Foundation
import Testing

@testable import Foreman

/// editor R37: one open document per URI, however many tabs show it.
///
/// Nothing is launched: the catalog names a binary that is not in the `PATH`, so `LSPServers`
/// stops at R39's check and only its bookkeeping runs (coding rules: hermetic).
@MainActor
struct LSPServersTests {
    private func servers(_ commands: [String: String] = ["swift": "no-such-language-server"]) -> LSPServers {
        var catalog = LSPCatalog()
        catalog.commands = commands.mapValues { LSPCatalog.Entry(command: $0, cwd: nil) }
        return LSPServers(root: URL(filePath: "/w"), config: { catalog }, environment: { ["PATH": "/nowhere"] })
    }

    /// editor R36: the key is the command **and** the `cwd`, so the four entries a monorepo needs
    /// (`ts`, `tsx`, `js`, `jsx`, all `typescript-language-server --stdio` in `server/`) are one
    /// server, and two folders declaring the same binary are two (author's question, 2026-08-31).
    @Test func keysAServerByItsCommandAndItsDirectory() {
        let command = "typescript-language-server --stdio"
        let one = LSPServers.ServerKey(command: command, cwd: "server")
        #expect(one == LSPServers.ServerKey(command: command, cwd: "server"))
        #expect(one != LSPServers.ServerKey(command: command, cwd: "client"))
        #expect(one != LSPServers.ServerKey(command: command, cwd: nil))
        // The command is compared as written: a stray space is a different server.
        #expect(one != LSPServers.ServerKey(command: command + " ", cwd: "server"))
    }

    private let file = URL(filePath: "/w/a.swift")

    @Test func opensOneDocumentPerFile() {
        let lsp = servers()
        lsp.opened(file, text: "let a = 1")
        #expect(lsp.openDocuments == [file.absoluteString: 1])
    }

    /// editor R1 allows the same file in two groups: that is two tabs, one document.
    @Test func countsTheTabsShowingOneFile() {
        let lsp = servers()
        lsp.opened(file, text: "let a = 1")
        lsp.opened(file, text: "let a = 1")
        #expect(lsp.openDocuments == [file.absoluteString: 2])
        lsp.closed(file)
        // The first tab closing must not close the document the second one is still showing.
        #expect(lsp.openDocuments == [file.absoluteString: 1])
        lsp.closed(file)
        #expect(lsp.openDocuments.isEmpty)
    }

    /// editor R35: an extension with no entry has no server, and nothing is tracked for it.
    @Test func ignoresAFileWithNoDeclaredServer() {
        let lsp = servers()
        lsp.opened(URL(filePath: "/w/a.kt"), text: "fun main() {}")
        #expect(lsp.openDocuments.isEmpty)
    }

    /// A file whose extension is declared but whose language Foreman does not know has no
    /// `languageId` to send, so it is not opened either.
    @Test func ignoresAFileWithNoKnownLanguage() {
        let lsp = servers(["conf": "no-such-language-server"])
        lsp.opened(URL(filePath: "/w/a.conf"), text: "x = 1")
        #expect(lsp.openDocuments.isEmpty)
    }

    /// Closing a file that was never opened is a no-op, not a negative count.
    @Test func closingAnUntrackedFileChangesNothing() {
        let lsp = servers()
        lsp.closed(file)
        #expect(lsp.openDocuments.isEmpty)
    }
}
