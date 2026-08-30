import Foundation
import Testing

@testable import Foreman

/// Built-ins merged with `config.agents` (agents R1, R3) and PATH detection (R2).
struct AgentCatalogTests {
    private func merge(_ json: String) throws -> AgentCatalog.Merged {
        AgentCatalog.merge(try JSONDecoder().decode([String: AgentCatalog.Entry].self, from: Data(json.utf8)))
    }

    @Test func withoutASectionThereIsNoAgent() {
        #expect(AgentCatalog.merge(nil).agents.isEmpty)
        #expect(AgentCatalog.merge(nil).warnings.isEmpty)
    }

    @Test func aDeclaredBuiltInKeepsItsDefaultsAndOverridesFieldByField() throws {
        let merged = try merge(#"{ "claude": { "command": "claude --continue" }, "pi": {} }"#)
        #expect(merged.agents.map(\.id) == ["claude", "pi"])
        let claude = merged.agents.first
        #expect(claude?.command == "claude --continue")
        #expect(claude?.title == "Claude Code")
        #expect(claude?.icon == "agent-claude")
        #expect(merged.agents.last == AgentCatalog.builtIns.first { $0.id == "pi" })
    }

    @Test func customAgentsInDeclarationOrderAndDisabledOnesHidden() throws {
        let merged = try merge(
            #"{ "zeta": { "command": "zeta chat" }, "aider": { "command": "aider", "title": "Aider" }, "opencode": { "enabled": false }, "claude": {} }"#
        )
        #expect(merged.agents.map(\.id) == ["aider", "claude", "zeta"])
        #expect(merged.agents.last == Agent(id: "zeta", title: "zeta", command: "zeta chat", icon: "terminal"))
        #expect(merged.warnings.isEmpty)
    }

    @Test func reportsAndSkipsInvalidEntries() throws {
        let merged = try merge(#"{ "Bad Id": { "command": "x" }, "nocmd": { "title": "No" }, "pi": {} }"#)
        #expect(merged.agents.map(\.id) == ["pi"])
        #expect(merged.warnings.count == 2)
        #expect(!AgentCatalog.isValid(id: "-x"))
        #expect(AgentCatalog.isValid(id: "my_agent-2"))
    }

    @Test func parsesTheNulSeparatedEnvironment() {
        let data = Data("\(Workspace.environmentSentinel)\u{0}PATH=/a:/b\u{0}MULTI=line1\nline2\u{0}NOEQ\u{0}".utf8)
        #expect(Workspace.parseEnvironment(data) == ["PATH": "/a:/b", "MULTI": "line1\nline2"])
    }

    @Test func discardsProfileNoiseBeforeTheSentinel() {
        let noisy = Data("Last login: today\nagent pid 42\(Workspace.environmentSentinel)\u{0}PATH=/a\u{0}".utf8)
        #expect(Workspace.parseEnvironment(noisy) == ["PATH": "/a"])
    }

    @Test func trustsNothingWithoutTheSentinel() {
        #expect(Workspace.parseEnvironment(Data("PATH=/a\u{0}HOME=/b\u{0}".utf8)) == [:])
        #expect(Workspace.parseEnvironment(Data()) == [:])
    }

    /// audit A2: the first character rule is "digit", and A–F are not digits.
    @Test func anIDStartsWithALowercaseLetterOrADigit() {
        #expect(AgentCatalog.isValid(id: "claude"))
        #expect(AgentCatalog.isValid(id: "2fa-agent"))
        #expect(!AgentCatalog.isValid(id: "Agent"))
        #expect(!AgentCatalog.isValid(id: "-agent"))
        #expect(!AgentCatalog.isValid(id: "_agent"))
        #expect(!AgentCatalog.isValid(id: ""))
    }
}
