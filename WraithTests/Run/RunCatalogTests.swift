import Foundation
import Testing

@testable import Wraith

/// The `commands` section decoded and validated (run R1–R3, R8).
struct RunCatalogTests {
    private let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "RunCatalogTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appending(components: "backend", "src"), withIntermediateDirectories: true)
    }

    /// The folders exist while `body` runs: `standardizedFileURL` reads the disk for its trailing slash.
    private func parse(_ json: String, _ body: (RunCatalog.Parsed) throws -> Void) throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try body(
            RunCatalog.parse(try JSONDecoder().decode(RunCatalog.Section.self, from: Data(json.utf8)), root: root))
    }

    @Test func withoutASectionThereIsNothing() {
        #expect(RunCatalog.parse(nil, root: root) == RunCatalog.Parsed(commands: [], warnings: []))
    }

    @Test func decodesShortAndLongFormsSortedByRepoThenName() throws {
        try parse(
            #"{ "backend": { "test": "mvn test", "build": { "run": "mvn compile", "cwd": "src" } }, ".": { "lint": "swift format lint" } }"#
        ) { parsed in
            #expect(parsed.warnings.isEmpty)
            #expect(parsed.commands.map(\.id) == ["root:lint", "backend:build", "backend:test"])
            let build = parsed.commands[1]
            #expect(build.command == "mvn compile")
            #expect(build.cwd == root.appending(components: "backend", "src").standardizedFileURL)
            #expect(build.title == "backend › build")
            #expect(build.problem == nil)
            #expect(parsed.commands[2].cwd == root.appending(path: "backend").standardizedFileURL)
            #expect(parsed.commands[0].cwd == root.standardizedFileURL)
        }
    }

    @Test func mergesTheRepoEnvironmentUnderTheCommandOne() throws {
        try parse(
            #"{ ".": { "$env": { "A": "repo", "B": "repo" }, "go": { "run": "go", "env": { "B": "cmd" } }, "plain": "ls" } }"#
        ) { parsed in
            #expect(parsed.warnings.isEmpty)
            #expect(parsed.commands.map(\.env) == [["A": "repo", "B": "cmd"], ["A": "repo", "B": "repo"]])
        }
    }

    @Test func acceptsRootAsTheWorkspaceRoot() throws {
        try parse(#"{ "root": { "echo": "echo" } }"#) { parsed in
            #expect(parsed.commands.map(\.id) == ["root:echo"])
            #expect(parsed.commands.first?.problem == nil)
            #expect(parsed.commands.first?.cwd == root.standardizedFileURL)
        }
    }

    @Test func greysTheCommandsOfAMissingRepo() throws {
        try parse(#"{ "frontend": { "dev": "npm run dev" } }"#) { parsed in
            #expect(parsed.warnings.isEmpty)
            #expect(parsed.commands.map(\.problem) == ["repo not found: frontend"])
        }
    }

    @Test func rejectsFoldersOutsideTheRoot() throws {
        try parse(
            #"{ "../other": { "x": "x" }, "/abs": { "x": "x" }, ".": { "up": { "run": "x", "cwd": "../.." } } }"#
        ) { parsed in
            #expect(parsed.commands.isEmpty)
            #expect(parsed.warnings.count == 3)
        }
    }

    @Test func reportsAndSkipsInvalidEntries() throws {
        try parse(
            #"{ ".": { "Bad": "x", "norun": { "cwd": "src" }, "empty": "", "$env": "oops", "ok": "true" } }"#
        ) { parsed in
            #expect(parsed.commands.map(\.id) == ["root:ok"])
            #expect(parsed.warnings.count == 4)
            #expect(RunCatalog.isValid(name: "db:migrate_v2-a"))
            #expect(!RunCatalog.isValid(name: ":x"))
            #expect(!RunCatalog.isValid(name: "$env"))
        }
    }
}
