import Foundation
import JSONRPC
import LanguageServerProtocol
import Testing

@testable import Foreman

/// The `lsp` section decoded (editor R35, R39, R57; config R7).
struct LSPCatalogTests {
    private func decode(_ json: String) throws -> LSPCatalog {
        try JSONDecoder().decode(LSPCatalog.self, from: Data(json.utf8))
    }

    @Test func aMissingSectionIsAnEmptyCatalog() throws {
        let catalog = try WorkspaceConfig.empty.section("lsp", as: LSPCatalog.self) ?? .empty
        #expect(catalog == .empty)
        #expect(catalog.timeout == .seconds(10))
        #expect(catalog.entry(for: URL(filePath: "/w/a.swift")) == nil)
    }

    @Test func theReservedKeyIsNeverAnExtension() throws {
        let catalog = try decode(#"{ "timeout": 20, "swift": "xcrun sourcekit-lsp" }"#)
        #expect(catalog.timeout == .seconds(20))
        #expect(catalog.commands == ["swift": LSPCatalog.Entry(command: "xcrun sourcekit-lsp", cwd: nil)])
        #expect(catalog.entry(for: URL(filePath: "/w/timeout")) == nil)
        #expect(catalog.warnings.isEmpty)
    }

    @Test(arguments: [(0.5, 1.0), (120.0, 60.0), (12.0, 12.0)])
    func clampsTheTimeout(declared: Double, expected: Double) throws {
        #expect(try decode(#"{ "timeout": \#(declared) }"#).timeout == .seconds(expected))
    }

    /// config R7: the entry goes, the section stays.
    @Test func dropsAnInvalidEntryAndKeepsTheRest() throws {
        let catalog = try decode(
            #"{ "swift": "xcrun sourcekit-lsp", "java": 12, "go": "   ", "timeout": "soon" }"#)
        #expect(catalog.commands == ["swift": LSPCatalog.Entry(command: "xcrun sourcekit-lsp", cwd: nil)])
        #expect(catalog.timeout == .seconds(10))
        #expect(catalog.warnings.count == 3)
    }

    /// editor R36: two extensions naming the same command share one server, which starts here —
    /// the catalog gives the same string, and `LSPServers` keys its processes on it.
    @Test func twoExtensionsCanNameTheSameCommand() throws {
        let command = "typescript-language-server --stdio"
        let catalog = try decode(#"{ "ts": "\#(command)", "tsx": "\#(command)" }"#)
        #expect(catalog.entry(for: URL(filePath: "/w/a.ts"))?.command == command)
        #expect(catalog.entry(for: URL(filePath: "/w/a.tsx"))?.command == command)
    }

    /// editor R35: an extension, or a whole file name when there is none, case-insensitively.
    @Test func keysAFileByItsExtensionOrItsWholeName() throws {
        let catalog = try decode(#"{ "SWIFT": "xcrun sourcekit-lsp", "Dockerfile": "docker-langserver --stdio" }"#)
        #expect(catalog.entry(for: URL(filePath: "/w/A.Swift"))?.command == "xcrun sourcekit-lsp")
        #expect(catalog.entry(for: URL(filePath: "/w/Dockerfile"))?.command == "docker-langserver --stdio")
        #expect(catalog.entry(for: URL(filePath: "/w/a.kt")) == nil)
    }

    /// editor R36: a repository is not always a project — a monorepo keeps its `node_modules`
    /// under `server/`, and `typescript-language-server` looks for TypeScript from its own `cwd`.
    @Test func readsACommandWithItsOwnDirectory() throws {
        let catalog = try decode(
            #"{ "ts": { "command": "typescript-language-server --stdio", "cwd": "server" } }"#)
        let entry = try #require(catalog.entry(for: URL(filePath: "/w/a.ts")))
        #expect(entry.command == "typescript-language-server --stdio")
        #expect(entry.cwd == "server")
        #expect(catalog.warnings.isEmpty)
    }

    /// The short form is unchanged, and it means the workspace root.
    @Test func aBareStringStillMeansTheRoot() throws {
        #expect(try decode(#"{ "swift": "xcrun sourcekit-lsp" }"#).entry(for: URL(filePath: "/w/a.swift"))?.cwd == nil)
    }

    /// config R7: an object with no command is as invalid as a number.
    @Test func dropsAnObjectWithoutACommand() throws {
        let catalog = try decode(#"{ "ts": { "cwd": "server" }, "js": { "command": "  " } }"#)
        #expect(catalog.commands.isEmpty)
        #expect(catalog.warnings.count == 2)
    }

    /// editor R36, security: a `cwd` from `config.json` must stay under the workspace root — the
    /// file can be shipped by a cloned repository and it names a process's working directory.
    @Test func refusesADirectoryOutsideTheWorkspace() {
        let root = URL(filePath: "/w")
        #expect(LSPServers.workingDirectory("../elsewhere", root: root) == nil)
        #expect(LSPServers.workingDirectory("/etc", root: root) == nil)
        // A folder that simply does not exist is refused too: nothing is launched in a guess.
        #expect(LSPServers.workingDirectory("no-such-folder", root: root) == nil)
    }

    /// No `cwd` is the root itself, which always exists.
    @Test func noDirectoryMeansTheRoot() throws {
        let root = URL(filePath: NSTemporaryDirectory()).standardizedFileURL
        #expect(LSPServers.workingDirectory(nil, root: root) == root)
        #expect(LSPServers.workingDirectory("", root: root) == root)
    }

    /// editor R46: the command is the user's text, run in the login shell — the formatter's rule,
    /// and the same builder, so a server is launched exactly like a formatter.
    @Test func buildsTheInvocationInTheLoginShell() {
        let invocation = FormatterLaunch.invocation(
            command: "xcrun sourcekit-lsp", cwd: URL(filePath: "/w"),
            environment: ["SHELL": "/bin/zsh", "PATH": "/usr/bin"])
        #expect(invocation.executable == "/bin/zsh")
        #expect(invocation.arguments == ["-l", "-c", "xcrun sourcekit-lsp"])
        #expect(invocation.cwd == URL(filePath: "/w"))
    }

    /// editor R35: the grammars whose LSP name is not their tree-sitter one.
    @Test func namesTheLanguageTheWayLSPDoes() {
        #expect(LSPServers.languageId(for: URL(filePath: "/w/a.tsx")) == "typescriptreact")
        #expect(LSPServers.languageId(for: URL(filePath: "/w/a.sh")) == "shellscript")
        #expect(LSPServers.languageId(for: URL(filePath: "/w/a.swift")) == "swift")
        #expect(LSPServers.languageId(for: URL(filePath: "/w/a.unknown")) == nil)
    }

    // MARK: - Settings (editor R57)

    /// editor R57: the object is kept as written — nothing renamed, nothing validated.
    @Test func keepsTheSettingsVerbatim() throws {
        let catalog = try decode(
            #"""
            { "java": { "command": "jdtls", "cwd": "backend",
                        "settings": { "java": { "import": { "exclusions": ["**/target/**"] }, "a": 1 } } } }
            """#)
        let entry = try #require(catalog.entry(for: URL(filePath: "/w/A.java")))
        #expect(entry.settings == ["java": ["import": ["exclusions": ["**/target/**"]], "a": 1]])
        #expect(catalog.settings(forCommand: "jdtls", cwd: "backend") == entry.settings)
        #expect(catalog.settings(forCommand: "jdtls", cwd: nil) == nil)
        #expect(catalog.warnings.isEmpty)
    }

    /// A string entry, or an object without the key, has none.
    @Test func anEntryWithoutSettingsHasNone() throws {
        let catalog = try decode(#"{ "swift": "xcrun sourcekit-lsp", "ts": { "command": "tsls --stdio" } }"#)
        #expect(catalog.entry(for: URL(filePath: "/w/a.swift"))?.settings == nil)
        #expect(catalog.entry(for: URL(filePath: "/w/a.ts"))?.settings == nil)
    }

    /// config R7 one level down: bad settings are dropped with a warning, the entry stays.
    @Test(arguments: [#""verbose""#, "12", "[1, 2]", "true"])
    func dropsSettingsThatAreNotAnObjectAndKeepsTheEntry(settings: String) throws {
        let catalog = try decode(#"{ "java": { "command": "jdtls", "settings": \#(settings) } }"#)
        let entry = try #require(catalog.entry(for: URL(filePath: "/w/A.java")))
        #expect(entry.command == "jdtls")
        #expect(entry.settings == nil)
        #expect(catalog.warnings == ["lsp.java.settings ignored: expected an object."])
    }

    /// editor R36, R57: one server, one object — the first extension in key order that declares
    /// settings owns them; one declaring none adopts them in silence, one declaring others is told.
    @Test func twoExtensionsOnOneServerShareTheFirstsSettings() throws {
        let catalog = try decode(
            #"""
            { "tsx": { "command": "tsls --stdio", "settings": { "preferences": { "quoteStyle": "double" } } },
              "ts": { "command": "tsls --stdio", "settings": { "preferences": { "quoteStyle": "single" } } },
              "js": { "command": "tsls --stdio" },
              "mts": { "command": "tsls --stdio", "cwd": "server", "settings": { "other": true } } }
            """#)
        let single: LSPAny = ["preferences": ["quoteStyle": "single"]]
        #expect(catalog.entry(for: URL(filePath: "/w/a.ts"))?.settings == single)
        #expect(catalog.entry(for: URL(filePath: "/w/a.tsx"))?.settings == single)
        #expect(catalog.entry(for: URL(filePath: "/w/a.js"))?.settings == single)
        // Another `cwd` is another server (R36), with its own settings.
        #expect(catalog.entry(for: URL(filePath: "/w/a.mts"))?.settings == ["other": true])
        #expect(
            catalog.warnings == [
                "lsp.tsx.settings ignored: `ts` names the same server with other settings, which win."
            ])
    }
}
