import Foundation

/// The configuration of a workspace: the global file merged under `<root>/.foreman/config.json`
/// (config R3, R4).
///
/// `Workspace` does not know the schemas of the features: each feature decodes its own top-level
/// section with `section(_:as:)` (config R5). Only `repos` is interpreted here, because it belongs
/// to the workspace itself. Nothing here knows that a section makes more sense in one file than in
/// the other: every section is read and merged the same way.
nonisolated struct WorkspaceConfig: Sendable {
    /// Top-level sections, each kept as the JSON of its merged value.
    private let sections: [String: Data]

    /// Repositories declared in `repos`, resolved under the root.
    ///
    /// Declared folders missing on disk or escaping the root are dropped and reported in
    /// `warnings` (config, edge cases). Empty when `repos` is absent.
    let repos: [URL]

    /// What was ignored while loading, one message each (config R11, edge cases).
    let warnings: [String]

    /// A workspace without any `config.json` (config R2).
    static let empty = WorkspaceConfig(sections: [:], repos: [], warnings: [])

    /// The section `name` decoded as `type`, or `nil` when no file declares it.
    func section<T: Decodable>(_ name: String, as type: T.Type) throws -> T? {
        guard let data = sections[name] else { return nil }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw WorkspaceError.invalidSection(name, underlying: error)
        }
    }

    // MARK: - Loading

    static func file(under root: URL) -> URL {
        root.appending(components: ".foreman", "config.json")
    }

    /// config R4: `$XDG_CONFIG_HOME/foreman/config.json`, else `~/.config/foreman/config.json`.
    ///
    /// A relative `XDG_CONFIG_HOME` is not a location (XDG basedir): it falls back to the home.
    nonisolated static func globalFile(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        let base: URL
        if let xdg = environment["XDG_CONFIG_HOME"], xdg.hasPrefix("/") {
            base = URL(filePath: xdg, directoryHint: .isDirectory)
        } else {
            base = home.appending(path: ".config", directoryHint: .isDirectory)
        }
        return base.appending(components: "foreman", "config.json")
    }

    /// The top-level sections of one file, each as the JSON of its value; `[:]` when it is absent.
    ///
    /// Disk IO and parsing, so it never runs on the main actor.
    @concurrent
    static func readSections(_ file: URL) async throws -> [String: Data] {
        var sections: [String: Data] = [:]
        for (name, value) in try read(file) {
            // Values come from JSONSerialization, so they are serializable again.
            sections[name] = try JSONSerialization.data(
                withJSONObject: value, options: [.sortedKeys, .fragmentsAllowed])
        }
        return sections
    }

    /// config R4: the global under the workspace, **one level deep**.
    ///
    /// A section that is an object in both files is merged key by key and the workspace's key wins;
    /// any other value — a string, a number, an array such as `repos` — is replaced whole. So a
    /// workspace overrides one agent without copying the others, and no recursion is needed.
    nonisolated static func merge(global: [String: Data], workspace: [String: Data]) -> [String: Data] {
        var merged = global
        for (name, value) in workspace {
            guard let base = merged[name], let both = mergedObject(global: base, workspace: value) else {
                merged[name] = value
                continue
            }
            merged[name] = both
        }
        return merged
    }

    /// The two values merged key by key, or `nil` when either is not a JSON object.
    private static func mergedObject(global: Data, workspace: Data) -> Data? {
        guard let base = try? JSONSerialization.jsonObject(with: global) as? [String: Any],
            let over = try? JSONSerialization.jsonObject(with: workspace) as? [String: Any]
        else { return nil }
        return try? JSONSerialization.data(
            withJSONObject: base.merging(over) { _, workspace in workspace }, options: [.sortedKeys])
    }

    /// The config the features see, `repos` resolved under the root (config, edge cases).
    nonisolated static func make(_ sections: [String: Data], root: URL) -> WorkspaceConfig {
        var warnings: [String] = []
        var sections = sections
        let declared = sections.removeValue(forKey: "repos")
        let repos = repos(declared: declared, root: root, warnings: &warnings)
        return WorkspaceConfig(sections: sections, repos: repos, warnings: warnings)
    }

    /// Reads both files and merges them; `globalFile` is `nil` when there is none to read.
    static func load(root: URL, globalFile: URL? = nil) async throws -> WorkspaceConfig {
        var global: [String: Data] = [:]
        if let globalFile {
            global = try await readSections(globalFile)
        }
        let workspace = try await readSections(file(under: root))
        return make(merge(global: global, workspace: workspace), root: root)
    }

    /// The top-level object of `file`, or `[:]` when the file does not exist (config R2).
    ///
    /// A file that exists but cannot be read (permissions, IO) throws instead: defaulting would
    /// silently drop the user's config.
    private static func read(_ file: URL) throws -> [String: Any] {
        let data: Data
        do {
            data = try Data(contentsOf: file)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return [:]
        } catch {
            throw WorkspaceError.unreadable(file: file, message: error.localizedDescription)
        }
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw WorkspaceError.invalidJSON(
                file: file, line: line(of: error, in: data), message: message(of: error))
        }
        guard let dictionary = object as? [String: Any] else {
            throw WorkspaceError.invalidJSON(file: file, line: 1, message: "The top level must be an object.")
        }
        return dictionary
    }

    private static func repos(declared: Data?, root: URL, warnings: inout [String]) -> [URL] {
        guard let declared else { return [] }
        guard let paths = try? JSONDecoder().decode([String].self, from: declared) else {
            warnings.append("\"repos\" ignored: expected an array of paths.")
            return []
        }
        return paths.compactMap { path in
            let folder = root.appending(path: path, directoryHint: .isDirectory)
            // architecture, security: a declared path never resolves outside the workspace root.
            guard Workspace.contains(folder, under: root) else {
                warnings.append("Repository \"\(path)\" ignored: outside the workspace root.")
                return nil
            }
            guard (try? folder.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else {
                warnings.append("Repository \"\(path)\" ignored: folder not found.")
                return nil
            }
            return folder
        }
    }

    /// Line of a `JSONSerialization` error: the byte offset it reports, counted in newlines.
    private static func line(of error: Error, in data: Data) -> Int? {
        guard let index = (error as NSError).userInfo["NSJSONSerializationErrorIndex"] as? Int else { return nil }
        let offset = min(max(index, 0), data.count)
        return data.prefix(offset).count(where: { $0 == UInt8(ascii: "\n") }) + 1
    }

    private static func message(of error: Error) -> String {
        (error as NSError).userInfo[NSDebugDescriptionErrorKey] as? String ?? error.localizedDescription
    }
}
