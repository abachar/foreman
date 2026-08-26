import Foundation

/// An agent Wraith can launch: built in (agents R1) or declared in `config.agents` (R3).
nonisolated struct Agent: Equatable, Sendable, Identifiable {
    let id: String
    let title: String
    /// The text passed as is to the login shell (terminal R1).
    let command: String
    /// SF Symbol name.
    let icon: String
    /// agents R2: a built-in agent is shown only when its binary is in the PATH; a declared one always.
    let isBuiltIn: Bool

    /// The binary looked up in the PATH: the first word of the command.
    var binary: String {
        String(command.split(separator: " ", maxSplits: 1).first ?? Substring(command))
    }
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
        Agent(id: "claude", title: "Claude Code", command: "claude", icon: "sparkles", isBuiltIn: true),
        Agent(
            id: "antigravity", title: "Antigravity", command: "antigravity", icon: "arrow.up.circle", isBuiltIn: true),
        Agent(
            id: "opencode", title: "OpenCode", command: "opencode", icon: "chevron.left.forwardslash.chevron.right",
            isBuiltIn: true),
    ]

    static let defaultIcon = "terminal"

    struct Merged: Equatable, Sendable {
        var agents: [Agent]
        var warnings: [String]
    }

    /// agents R3: the section on top of the built-ins.
    ///
    /// A built-in id overrides its fields, an unknown id declares a custom agent (`command`
    /// required), `enabled: false` hides; an invalid entry is reported and skipped (config R7:
    /// nothing here breaks the workspace). Built-ins first, then custom ids sorted.
    static func merge(_ section: [String: Entry]?) -> Merged {
        var warnings: [String] = []
        var agents: [Agent] = []
        let section = section ?? [:]
        for builtIn in builtIns {
            guard let entry = section[builtIn.id] else {
                agents.append(builtIn)
                continue
            }
            if entry.enabled == false { continue }
            agents.append(
                Agent(
                    id: builtIn.id, title: entry.title ?? builtIn.title, command: entry.command ?? builtIn.command,
                    icon: entry.icon ?? builtIn.icon, isBuiltIn: true))
        }
        for (id, entry) in section.sorted(by: { $0.key < $1.key }) where !builtIns.contains(where: { $0.id == id }) {
            guard isValid(id: id) else {
                warnings.append("agents.\(id) ignored: an id is [a-z0-9][a-z0-9_-]*.")
                continue
            }
            guard let command = entry.command, !command.isEmpty else {
                warnings.append("agents.\(id) ignored: \"command\" is required for a custom agent.")
                continue
            }
            if entry.enabled == false { continue }
            agents.append(
                Agent(
                    id: id, title: entry.title ?? id, command: command, icon: entry.icon ?? defaultIcon,
                    isBuiltIn: false))
        }
        return Merged(agents: agents, warnings: warnings)
    }

    /// agents R3: `[a-z0-9][a-z0-9_-]*`.
    static func isValid(id: String) -> Bool {
        guard let first = id.unicodeScalars.first, first.properties.isASCIIHexDigit || ("a"..."z").contains(first)
        else { return false }
        return id.unicodeScalars.allSatisfy { scalar in
            ("a"..."z").contains(scalar) || ("0"..."9").contains(scalar) || scalar == "_" || scalar == "-"
        }
    }

    /// agents R2: the names found as executables in `path`, without running anything.
    static func executables(among names: Set<String>, inPath path: String?) -> Set<String> {
        guard let path, !path.isEmpty else { return [] }
        var found: Set<String> = []
        for directory in path.split(separator: ":") {
            for name in names where !found.contains(name) {
                let candidate = URL(filePath: String(directory)).appending(path: name).path(percentEncoded: false)
                if FileManager.default.isExecutableFile(atPath: candidate) {
                    found.insert(name)
                }
            }
        }
        return found
    }
}
