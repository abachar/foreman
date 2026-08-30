import Foundation

/// An agent Foreman can launch: built in (agents R1) or declared in `config.agents` (R3).
nonisolated struct Agent: Equatable, Sendable, Identifiable {
    let id: String
    let title: String
    /// The text passed as is to the login shell (terminal R1).
    let command: String
    /// agents R3: an SF Symbol, an asset name, or a workspace file resolved by `AgentsFeature`.
    let icon: String
}

/// The built-in agents and the `agents` section merged on top of them (agents R1, R3).
nonisolated enum AgentCatalog {
    /// agents R3: `{ "<id>": { "title"?, "command"?, "icon"?, "enabled"? } }`.
    struct Entry: Decodable, Equatable, Sendable {
        var title: String?
        var command: String?
        var icon: String?
        var enabled: Bool?
    }

    /// agents R1.
    static let builtIns: [Agent] = [
        Agent(id: "claude", title: "Claude Code", command: "claude", icon: "agent-claude"),
        Agent(id: "antigravity", title: "Antigravity", command: "agy", icon: "agent-antigravity"),
        Agent(id: "opencode", title: "OpenCode", command: "opencode", icon: "agent-opencode"),
        Agent(id: "pi", title: "Pi", command: "pi", icon: "agent-pi"),
    ]

    static let defaultIcon = "terminal"

    struct Merged: Equatable, Sendable {
        var agents: [Agent]
        var warnings: [String]
    }

    /// agents R2 (amended 2026-08-28), R3: the declared ids only, in declaration order (sorted keys).
    ///
    /// A built-in id takes its defaults and overrides its fields (`{}` is enough to show it), an
    /// unknown id declares a custom agent (`command` required), `enabled: false` hides; an invalid
    /// entry is reported and skipped (config R7: nothing here breaks the workspace). No section →
    /// no agent.
    static func merge(_ section: [String: Entry]?) -> Merged {
        var warnings: [String] = []
        var agents: [Agent] = []
        for (id, entry) in (section ?? [:]).sorted(by: { $0.key < $1.key }) {
            if entry.enabled == false { continue }
            if let builtIn = builtIns.first(where: { $0.id == id }) {
                agents.append(
                    Agent(
                        id: id, title: entry.title ?? builtIn.title, command: entry.command ?? builtIn.command,
                        icon: entry.icon ?? builtIn.icon))
                continue
            }
            guard isValid(id: id) else {
                warnings.append("agents.\(id) ignored: an id is [a-z0-9][a-z0-9_-]*.")
                continue
            }
            guard let command = entry.command, !command.isEmpty else {
                warnings.append("agents.\(id) ignored: \"command\" is required for a custom agent.")
                continue
            }
            agents.append(Agent(id: id, title: entry.title ?? id, command: command, icon: entry.icon ?? defaultIcon))
        }
        return Merged(agents: agents, warnings: warnings)
    }

    /// agents R3: `[a-z0-9][a-z0-9_-]*`.
    static func isValid(id: String) -> Bool {
        guard let first = id.unicodeScalars.first, ("0"..."9").contains(first) || ("a"..."z").contains(first)
        else { return false }
        return id.unicodeScalars.allSatisfy { scalar in
            ("a"..."z").contains(scalar) || ("0"..."9").contains(scalar) || scalar == "_" || scalar == "-"
        }
    }
}
