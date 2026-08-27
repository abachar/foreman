import Foundation
import Testing

@testable import Wraith

/// Built-ins merged with `config.agents` (agents R1, R3) and PATH detection (R2).
struct AgentCatalogTests {
    private func merge(_ json: String) throws -> AgentCatalog.Merged {
        AgentCatalog.merge(try JSONDecoder().decode([String: AgentCatalog.Entry].self, from: Data(json.utf8)))
    }

    @Test func withoutASectionTheBuiltInsAreTheCatalog() {
        #expect(AgentCatalog.merge(nil).agents == AgentCatalog.builtIns)
        #expect(AgentCatalog.merge(nil).warnings.isEmpty)
    }

    @Test func overridesABuiltInFieldByField() throws {
        let merged = try merge(#"{ "claude": { "command": "claude --continue" } }"#)

        let claude = merged.agents.first { $0.id == "claude" }
        #expect(claude?.command == "claude --continue")
        #expect(claude?.title == "Claude Code")
        #expect(claude?.binary == "claude")
        #expect(claude?.isBuiltIn == true)
    }

    @Test func declaresCustomAgentsAfterTheBuiltInsAndHidesDisabledOnes() throws {
        let merged = try merge(
            #"{ "zeta": { "command": "zeta chat" }, "aider": { "command": "aider", "title": "Aider" }, "opencode": { "enabled": false } }"#
        )

        #expect(merged.agents.map(\.id) == ["claude", "antigravity", "pi", "aider", "zeta"])
        #expect(
            merged.agents.last
                == Agent(id: "zeta", title: "zeta", command: "zeta chat", icon: "terminal", isBuiltIn: false))
        #expect(merged.warnings.isEmpty)
    }

    @Test func reportsAndSkipsInvalidEntries() throws {
        let merged = try merge(#"{ "Bad Id": { "command": "x" }, "nocmd": { "title": "No" } }"#)

        #expect(merged.agents == AgentCatalog.builtIns)
        #expect(merged.warnings.count == 2)
        #expect(!AgentCatalog.isValid(id: "-x"))
        #expect(AgentCatalog.isValid(id: "my_agent-2"))
    }

    @Test func findsExecutablesInThePath() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "AgentCatalogTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let bin = root.appending(path: "bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appending(path: "empty"), withIntermediateDirectories: true)
        try Data("#!/bin/sh\n".utf8).write(to: bin.appending(path: "claude"))
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: bin.appending(path: "claude").path())
        try Data().write(to: bin.appending(path: "opencode"))

        let path = "\(root.appending(path: "empty").path()):\(bin.path())"
        let found = AgentCatalog.executables(among: ["claude", "opencode", "agy"], inPath: path)

        #expect(found == ["claude"])
        #expect(AgentCatalog.executables(among: ["claude"], inPath: nil).isEmpty)
    }

    @Test func parsesTheNulSeparatedEnvironment() {
        let data = Data("PATH=/a:/b\u{0}MULTI=line1\nline2\u{0}NOEQ\u{0}".utf8)
        #expect(Workspace.parseEnvironment(data) == ["PATH": "/a:/b", "MULTI": "line1\nline2"])
    }
}
