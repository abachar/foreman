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
    /// run R14: the manifest a detected command comes from; `nil` for `config.commands`.
    var source: String? = nil

    var title: String {
        "\(repo) › \(name)"
    }

    /// run R5, R15: the reason when greyed, else the command, with its manifest when detected.
    var subtitle: String {
        if let problem { return problem }
        guard let source else { return command }
        return "\(command) · \(source)"
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
            // run R2: `root` is how the id spells `.`, so it is accepted unless a `root/` folder exists.
            let declared = repo == "root" && !isDirectory(root.appending(path: "root")) ? "." : repo
            guard let repoURL = url(forDeclared: declared, under: root) else {
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

    // MARK: - Detection (run R14–R15)

    /// run R16: the files whose change triggers a new detection.
    static let manifests: Set<String> = [
        "package.json", "pom.xml", "Package.swift", "Makefile", "pnpm-lock.yaml", "yarn.lock", "bun.lockb", "bun.lock",
    ]

    /// run R14: the commands the manifests declare, read-only, at the root, in the declared repos
    /// and in the root's first-level folders (a monorepo: `server/package.json`); an unreadable
    /// or malformed manifest yields nothing.
    static func detect(root: URL, repos: [URL]) -> [RunCommand] {
        var commands: [RunCommand] = []
        let root = root.standardizedFileURL
        let folders = [root] + repos.map(\.standardizedFileURL) + firstLevelFolders(of: root)
        for repoURL in folders.uniqued() where isDirectory(repoURL) {
            let repo = repoURL == root ? "." : Workspace.persistedPath(for: repoURL, root: root)
            func add(_ name: String, _ command: String, from source: String) {
                guard isValid(name: name) else { return }
                commands.append(
                    RunCommand(
                        id: id(repo: repo, name: name), repo: repo, name: name, command: command, cwd: repoURL,
                        env: [:], problem: nil, source: source))
            }
            if let scripts = packageScripts(in: repoURL) {
                let pm = packageManager(in: repoURL)
                for name in scripts.keys.sorted() {
                    add(name, "\(pm) run \(name)", from: "package.json")
                }
            }
            if exists(repoURL, "pom.xml") {
                for goal in ["test", "package", "verify"] {
                    add("mvn-\(goal)", "mvn \(goal)", from: "pom.xml")
                }
            }
            if exists(repoURL, "Package.swift") {
                for goal in ["build", "test"] {
                    add("swift-\(goal)", "swift \(goal)", from: "Package.swift")
                }
            }
            for target in makeTargets(in: repoURL) {
                add(target, "make \(target)", from: "Makefile")
            }
        }
        return commands
    }

    /// run R15: a declared id wins; the detected ones follow, in their order.
    static func merge(declared: [RunCommand], detected: [RunCommand]) -> [RunCommand] {
        let ids = Set(declared.map(\.id))
        return declared + detected.filter { !ids.contains($0.id) }
    }

    /// run R14: the root's visible, non-excluded folders, sorted.
    private static func firstLevelFolders(of root: URL) -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path(percentEncoded: false))) ?? []
        return names.sorted()
            .filter { !$0.hasPrefix(".") && !ExcludedPaths.isExcluded($0) }
            .map { root.appending(path: $0).standardizedFileURL }
            .filter(isDirectory)
    }

    /// run R14: the package manager the lockfile says, `npm` by default.
    static func packageManager(in repo: URL) -> String {
        if exists(repo, "pnpm-lock.yaml") { return "pnpm" }
        if exists(repo, "yarn.lock") { return "yarn" }
        if exists(repo, "bun.lockb") || exists(repo, "bun.lock") { return "bun" }
        return "npm"
    }

    private struct PackageManifest: Decodable {
        var scripts: [String: String]?
    }

    private static func packageScripts(in repo: URL) -> [String: String]? {
        guard let data = try? Data(contentsOf: repo.appending(path: "package.json")) else { return nil }
        return (try? JSONDecoder().decode(PackageManifest.self, from: data))?.scripts
    }

    /// run R14: `name:` at column 0; `.PHONY`, dot targets, patterns and variables are skipped.
    static func makeTargets(in repo: URL) -> [String] {
        guard let text = try? String(contentsOf: repo.appending(path: "Makefile"), encoding: .utf8) else { return [] }
        return makeTargets(text)
    }

    static func makeTargets(_ makefile: String) -> [String] {
        let target = /^([a-zA-Z0-9_-]+):(?!=)/
        var seen: Set<String> = []
        var targets: [String] = []
        for line in makefile.split(separator: "\n", omittingEmptySubsequences: false) {
            guard let match = line.firstMatch(of: target) else { continue }
            let name = String(match.1)
            if seen.insert(name).inserted {
                targets.append(name)
            }
        }
        return targets
    }

    private static func exists(_ repo: URL, _ name: String) -> Bool {
        FileManager.default.fileExists(atPath: repo.appending(path: name).path(percentEncoded: false))
    }

    /// run R3: `.` becomes `root`.
    nonisolated static func id(repo: String, name: String) -> String {
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

nonisolated extension Array where Element: Hashable {
    fileprivate func uniqued() -> [Element] {
        var seen: Set<Element> = []
        return filter { seen.insert($0).inserted }
    }
}
