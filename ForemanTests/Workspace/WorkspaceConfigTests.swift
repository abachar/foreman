import Foundation
import Testing

@testable import Foreman

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
        let workspace = Workspace(root: fixture.root, globalConfigFile: fixture.globalFile)

        await workspace.reloadConfig()
        try fixture.writeWorkspace("{ oops")
        await workspace.reloadConfig()

        #expect(try workspace.config.section("theme", as: String.self) == "dark")
        #expect(workspace.configErrors.count == 1)
        #expect(workspace.configErrors.first?.description.hasPrefix("config.json:1:") == true)

        try fixture.writeWorkspace(#"{ "theme": "light" }"#)
        await workspace.reloadConfig()

        #expect(try workspace.config.section("theme", as: String.self) == "light")
        #expect(workspace.configErrors.isEmpty)
    }
}

/// config R4 (amended 2026-08-30): the global file, its path and how it merges under the workspace.
struct GlobalConfigTests {
    private let fixture = Fixture()

    // MARK: - Where it lives

    @Test func livesUnderXdgConfigHomeWhenItIsAnAbsolutePath() {
        let file = WorkspaceConfig.globalFile(
            environment: ["XDG_CONFIG_HOME": "/tmp/xdg"], home: URL(filePath: "/Users/x"))

        #expect(file.path(percentEncoded: false) == "/tmp/xdg/foreman/config.json")
    }

    @Test func fallsBackToTheHomeWithoutXdgConfigHomeOrWithARelativeOne() {
        let home = URL(filePath: "/Users/x")

        #expect(
            WorkspaceConfig.globalFile(environment: [:], home: home).path(percentEncoded: false)
                == "/Users/x/.config/foreman/config.json")
        #expect(
            WorkspaceConfig.globalFile(environment: ["XDG_CONFIG_HOME": "relative"], home: home)
                .path(percentEncoded: false) == "/Users/x/.config/foreman/config.json")
    }

    // MARK: - The merge (config R4)

    private func merged(global: String, workspace: String) throws -> [String: String] {
        let sections = WorkspaceConfig.merge(
            global: try sections(global), workspace: try sections(workspace))
        return sections.mapValues { String(decoding: $0, as: UTF8.self) }
    }

    private func sections(_ json: String) throws -> [String: Data] {
        var sections: [String: Data] = [:]
        let object = try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        for (name, value) in object {
            sections[name] = try JSONSerialization.data(
                withJSONObject: value, options: [.sortedKeys, .fragmentsAllowed])
        }
        return sections
    }

    @Test func mergesAnObjectSectionKeyByKeyAndTheWorkspaceWins() throws {
        let merged = try merged(
            global: #"{ "agents": { "claude": { "command": "claude" }, "pi": { "command": "pi" } } }"#,
            workspace: #"{ "agents": { "claude": { "command": "claude --continue" } } }"#)

        #expect(
            merged["agents"]
                == #"{"claude":{"command":"claude --continue"},"pi":{"command":"pi"}}"#)
    }

    @Test func keepsASectionOnlyOneFileDeclares() throws {
        let merged = try merged(global: #"{ "theme": { "accent": "blue" } }"#, workspace: #"{ "repos": ["."] }"#)

        #expect(merged["theme"] == #"{"accent":"blue"}"#)
        #expect(merged["repos"] == #"["."]"#)
    }

    @Test func replacesAValueThatIsNotAnObjectWhole() throws {
        let merged = try merged(
            global: #"{ "repos": ["a", "b"], "theme": "dark", "terminal": { "fontSize": 13 } }"#,
            workspace: #"{ "repos": ["c"], "theme": "light", "terminal": 3 }"#)

        #expect(merged["repos"] == #"["c"]"#)
        #expect(merged["theme"] == #""light""#)
        #expect(merged["terminal"] == "3")
    }

    @Test func mergingOnlyGoesOneLevelDeep() throws {
        let merged = try merged(
            global: #"{ "commands": { "root": { "build": "make", "test": "make test" } } }"#,
            workspace: #"{ "commands": { "root": { "build": "xcodebuild" } } }"#)

        // `root` is a value of the `commands` section, so the workspace's replaces it whole.
        #expect(merged["commands"] == #"{"root":{"build":"xcodebuild"}}"#)
    }

    // MARK: - Through the workspace

    @Test func theWorkspaceReadsBothFiles() async throws {
        defer { fixture.remove() }
        try fixture.writeGlobal(#"{ "shortcuts": { "git.changes": "cmd+shift+g", "editor.save": "cmd+s" } }"#)
        try fixture.writeWorkspace(#"{ "shortcuts": { "editor.save": "cmd+opt+s" } }"#)

        let config = try await fixture.load()

        #expect(
            try config.section("shortcuts", as: [String: String].self)
                == ["git.changes": "cmd+shift+g", "editor.save": "cmd+opt+s"])
    }

    @Test @MainActor func anInvalidGlobalKeepsItsLastValidVersionAndNamesItself() async throws {
        defer { fixture.remove() }
        try fixture.writeGlobal(#"{ "theme": "dark" }"#)
        try fixture.writeWorkspace(#"{ "repos": ["."] }"#)
        let workspace = Workspace(root: fixture.root, globalConfigFile: fixture.globalFile)
        await workspace.reloadConfig()

        try fixture.writeGlobal("{ oops")
        try fixture.writeWorkspace(#"{ "browser": { "url": "http://localhost" } }"#)
        await workspace.reloadConfig()

        // The broken global keeps its last valid version, and the workspace still went through.
        #expect(try workspace.config.section("theme", as: String.self) == "dark")
        #expect(try workspace.config.section("browser", as: [String: String].self) == ["url": "http://localhost"])
        #expect(workspace.configErrors.count == 1)
        #expect(workspace.configErrors.first?.description.contains("foreman/config.json:1:") == true)
    }
}

/// A temporary workspace root.
private struct Fixture {
    let root: URL

    init() {
        root = FileManager.default.temporaryDirectory
            .appending(path: "WorkspaceConfigTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    /// config R4: the global file of this fixture alone, never the developer's own.
    var globalFile: URL {
        root.appending(components: "global", "foreman", "config.json")
    }

    func load() async throws -> WorkspaceConfig {
        try await WorkspaceConfig.load(root: root, globalFile: globalFile)
    }

    func writeWorkspace(_ json: String) throws {
        try write(json, to: root.appending(components: ".foreman", "config.json"))
    }

    func writeGlobal(_ json: String) throws {
        try write(json, to: globalFile)
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

/// product decision 2026-08-28: the `.wraith/` folder of a workspace opened before the rename.
struct LegacyFolderMigrationTests {
    @Test func renamesWraithToForemanOnce() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "LegacyFolder-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appending(path: ".wraith"), withIntermediateDirectories: true)
        try "{}".write(to: root.appending(components: ".wraith", "config.json"), atomically: true, encoding: .utf8)
        Workspace.migrateLegacyFolder(in: root)
        #expect(FileManager.default.fileExists(atPath: root.appending(components: ".foreman", "config.json").path()))
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: ".wraith").path()))
        // A second `.wraith/` next to an existing `.foreman/` is left alone.
        try FileManager.default.createDirectory(at: root.appending(path: ".wraith"), withIntermediateDirectories: true)
        Workspace.migrateLegacyFolder(in: root)
        #expect(FileManager.default.fileExists(atPath: root.appending(path: ".wraith").path()))
    }
}
