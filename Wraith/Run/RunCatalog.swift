import Foundation

/// One command of `config.commands`, resolved against the workspace (run R1–R3).
nonisolated struct RunCommand: Equatable, Sendable, Identifiable {
    /// run R3: `repo:name`, with `.` spelled `root`; the tab kind is `run.<id>`.
    let id: String
    /// As declared: `.` or a path relative to the root.
    let repo: String
    let name: String
    /// The text passed as is to the login shell (run R8).
    let command: String
    let cwd: URL
    /// run R1: the repo's `$env` under the command's own `env`.
    let env: [String: String]
    /// run R2: why the command is listed greyed; `nil` when it can be launched.
    let problem: String?

    var title: String {
        "\(repo) › \(name)"
    }
}

/// The `commands` section decoded and validated (run R1–R3).
nonisolated enum RunCatalog {
    /// A value under a repo: `"cmd"`, `{ "run", "cwd"?, "env"? }`, or the `$env` object.
    enum Value: Decodable, Equatable, Sendable {
        struct Detailed: Decodable, Equatable, Sendable {
            var run: String
            var cwd: String?
            var env: [String: String]?
        }

        case short(String)
        case detailed(Detailed)
        case environment([String: String])

        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let text = try? container.decode(String.self) {
                self = .short(text)
            } else if let detailed = try? container.decode(Detailed.self) {
                self = .detailed(detailed)
            } else {
                self = .environment(try container.decode([String: String].self))
            }
        }
    }

    typealias Section = [String: [String: Value]]

    struct Parsed: Equatable, Sendable {
        var commands: [RunCommand]
        var warnings: [String]
    }

    static let environmentKey = "$env"

    /// Commands sorted by repo then name; an invalid entry is reported and skipped, a missing repo
    /// keeps its commands greyed (run R2, config R7: nothing here breaks the workspace).
    static func parse(_ section: Section?, root: URL) -> Parsed {
        var warnings: [String] = []
        var commands: [RunCommand] = []
        let root = root.standardizedFileURL
        for (repo, values) in (section ?? [:]).sorted(by: { $0.key < $1.key }) {
            guard let repoURL = url(forDeclared: repo, under: root) else {
                warnings.append("commands.\(repo) ignored: a repo is \".\" or a path under the root.")
                continue
            }
            let problem = isDirectory(repoURL) ? nil : "repo not found: \(repo)"
            var repoEnvironment: [String: String] = [:]
            if let value = values[environmentKey] {
                if case .environment(let env) = value {
                    repoEnvironment = env
                } else {
                    warnings.append("commands.\(repo).$env ignored: expected an object of strings.")
                }
            }
            for (name, value) in values.sorted(by: { $0.key < $1.key }) where name != environmentKey {
                guard isValid(name: name) else {
                    warnings.append("commands.\(repo).\(name) ignored: a name is [a-z0-9][a-z0-9:_-]*.")
                    continue
                }
                let command: String
                var cwd = repoURL
                var env = repoEnvironment
                switch value {
                case .short(let text):
                    command = text
                case .detailed(let detailed):
                    command = detailed.run
                    if let relative = detailed.cwd {
                        // architecture, security: a folder from the config never leaves the root.
                        guard let resolved = url(forDeclared: relative, under: repoURL), isUnder(resolved, root)
                        else {
                            warnings.append("commands.\(repo).\(name) ignored: \"cwd\" must stay under the root.")
                            continue
                        }
                        cwd = resolved
                    }
                    env.merge(detailed.env ?? [:]) { _, own in own }
                case .environment:
                    warnings.append("commands.\(repo).\(name) ignored: \"run\" is required.")
                    continue
                }
                guard !command.isEmpty else {
                    warnings.append("commands.\(repo).\(name) ignored: the command is empty.")
                    continue
                }
                commands.append(
                    RunCommand(
                        id: id(repo: repo, name: name), repo: repo, name: name, command: command, cwd: cwd, env: env,
                        problem: problem))
            }
        }
        return Parsed(commands: commands, warnings: warnings)
    }

    /// run R3: `.` becomes `root`.
    static func id(repo: String, name: String) -> String {
        "\(repo == "." ? "root" : repo):\(name)"
    }

    /// run R3: `[a-z0-9][a-z0-9:_-]*`.
    static func isValid(name: String) -> Bool {
        guard let first = name.unicodeScalars.first, ("a"..."z").contains(first) || ("0"..."9").contains(first)
        else { return false }
        return name.unicodeScalars.allSatisfy { scalar in
            ("a"..."z").contains(scalar) || ("0"..."9").contains(scalar) || scalar == ":" || scalar == "_"
                || scalar == "-"
        }
    }

    /// `.` or a relative path resolved under `base`, refused when absolute or escaping `base`.
    private static func url(forDeclared path: String, under base: URL) -> URL? {
        guard !path.isEmpty, !path.hasPrefix("/") else { return nil }
        if path == "." { return base }
        let resolved = base.appending(path: path).standardizedFileURL
        return isUnder(resolved, base) ? resolved : nil
    }

    private static func isUnder(_ url: URL, _ base: URL) -> Bool {
        let components = url.standardizedFileURL.pathComponents
        let baseComponents = base.standardizedFileURL.pathComponents
        return components.count >= baseComponents.count
            && components.prefix(baseComponents.count) == baseComponents[...]
    }

    /// Follows symlinks (`/tmp`), like `TerminalTab`.
    private static func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDirectory)
            && isDirectory.boolValue
    }
}
