import Foundation
import Testing

@testable import Wraith

/// Reading `config.json` (config R2, R5, R7, R11) on a temporary folder.
struct WorkspaceConfigTests {
    private struct Postgres: Decodable, Equatable {
        let host: String
        let port: Int
        var password: String?
    }

    private let fixture = Fixture()

    @Test func isEmptyWithoutAnyFile() async throws {
        defer { fixture.remove() }

        let config = try await fixture.load()

        #expect(try config.section("postgres", as: Postgres.self) == nil)
        #expect(config.repos.isEmpty)
        #expect(config.warnings.isEmpty)
    }

    @Test func exposesEachSectionToItsFeature() async throws {
        defer { fixture.remove() }
        try fixture.writeWorkspace(
            #"{ "shortcuts": { "git.status": "cmd+shift+g" }, "postgres": { "host": "db", "port": 1 } }"#)

        let config = try await fixture.load()

        #expect(try config.section("shortcuts", as: [String: String].self) == ["git.status": "cmd+shift+g"])
        #expect(try config.section("postgres", as: Postgres.self) == Postgres(host: "db", port: 1))
        #expect(try config.section("theme", as: String.self) == nil)
    }

    @Test func reportsTheLineOfInvalidJSON() async throws {
        defer { fixture.remove() }
        try fixture.writeWorkspace("{\n  \"a\": 1,\n  \"b\": [1, 2,\n}\n")

        await #expect(throws: WorkspaceError.self) {
            try await fixture.load()
        }
        do {
            _ = try await fixture.load()
        } catch let WorkspaceError.invalidJSON(file, line, _) {
            #expect(file.lastPathComponent == "config.json")
            #expect(line == 4)
        }
    }

    @Test func rejectsAFileWhoseTopLevelIsNotAnObject() async throws {
        defer { fixture.remove() }
        try fixture.writeWorkspace("[1, 2]")

        await #expect(throws: WorkspaceError.self) {
            try await fixture.load()
        }
    }

    @Test func keepsPasswordKeysForTheFeature() async throws {
        defer { fixture.remove() }
        try fixture.writeWorkspace(#"{ "postgres": { "host": "db", "port": 1, "password": "hunter2" } }"#)

        let config = try await fixture.load()

        // config R11 (decision 2026-08-27): the section owns its password, nothing is stripped.
        #expect(try config.section("postgres", as: Postgres.self) == Postgres(host: "db", port: 1, password: "hunter2"))
        #expect(config.warnings.isEmpty)
    }

    @Test func dropsDeclaredReposThatDoNotExist() async throws {
        defer { fixture.remove() }
        try fixture.makeFolder("backend")
        try fixture.writeWorkspace(#"{ "repos": ["backend", "frontend"] }"#)

        let config = try await fixture.load()

        #expect(config.repos == [fixture.root.appending(path: "backend", directoryHint: .isDirectory)])
        #expect(config.warnings == ["Repository \"frontend\" ignored: folder not found."])
        #expect(try config.section("repos", as: [String].self) == nil)
    }

    @Test func throwsWhenASectionHasTheWrongShape() async throws {
        defer { fixture.remove() }
        try fixture.writeWorkspace(#"{ "postgres": { "host": 5 } }"#)

        let config = try await fixture.load()

        #expect(throws: WorkspaceError.self) {
            try config.section("postgres", as: Postgres.self)
        }
    }

    @Test @MainActor func workspaceKeepsTheLastValidConfigOnError() async throws {
        defer { fixture.remove() }
        try fixture.writeWorkspace(#"{ "theme": "dark" }"#)
        let workspace = Workspace(root: fixture.root)

        await workspace.reloadConfig()
        try fixture.writeWorkspace("{ oops")
        await workspace.reloadConfig()

        #expect(try workspace.config.section("theme", as: String.self) == "dark")
        #expect(workspace.configError != nil)
        #expect(workspace.configError?.description.hasPrefix("config.json:1:") == true)

        try fixture.writeWorkspace(#"{ "theme": "light" }"#)
        await workspace.reloadConfig()

        #expect(try workspace.config.section("theme", as: String.self) == "light")
        #expect(workspace.configError == nil)
    }
}

/// A temporary workspace root.
private struct Fixture {
    let root: URL

    init() {
        root = FileManager.default.temporaryDirectory
            .appending(path: "WorkspaceConfigTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    func load() async throws -> WorkspaceConfig {
        try await WorkspaceConfig.load(root: root)
    }

    func writeWorkspace(_ json: String) throws {
        try write(json, to: root.appending(components: ".wraith", "config.json"))
    }

    func makeFolder(_ name: String) throws {
        try FileManager.default.createDirectory(
            at: root.appending(path: name, directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }

    private func write(_ json: String, to file: URL) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(json.utf8).write(to: file)
    }
}
