import Foundation

/// The merged configuration of a workspace, read from `~/.config/wraith/config.json` and
/// `<root>/.wraith/config.json` (config R3, R4).
///
/// `Workspace` does not know the schemas of the features: each feature decodes its own top-level
/// section with `section(_:as:)` (config R5). Only `repos` is interpreted here, because it belongs
/// to the workspace itself.
nonisolated struct WorkspaceConfig: Sendable {
    /// Top-level sections, each kept as the JSON of its merged value.
    private let sections: [String: Data]

    /// Repositories declared in `repos`, resolved under the root.
    ///
    /// Declared folders missing on disk are dropped and reported in `warnings` (config, edge cases).
    /// Empty when `repos` is absent.
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
            throw WorkspaceConfigError.invalidSection(name, underlying: error)
        }
    }

    // MARK: - Loading

    /// Reads and merges both files.
    ///
    /// Disk IO and parsing, so it never runs on the main actor.
    @concurrent
    static func load(root: URL, globalFile: URL) async throws -> WorkspaceConfig {
        let workspaceFile = root.appending(components: ".wraith", "config.json")
        var warnings: [String] = []
        let global = try read(globalFile, warnings: &warnings)
        let workspace = try read(workspaceFile, warnings: &warnings)
        let merged = merge(global, over: workspace)

        var sections: [String: Data] = [:]
        for (name, value) in merged where name != "repos" {
            // Values come from JSONSerialization, so they are serializable again.
            sections[name] = try JSONSerialization.data(
                withJSONObject: value, options: [.sortedKeys, .fragmentsAllowed])
        }
        let repos = repos(declared: merged["repos"], root: root, warnings: &warnings)
        return WorkspaceConfig(sections: sections, repos: repos, warnings: warnings)
    }

    /// The top-level object of `file`, or `[:]` when the file does not exist (config R2).
    private static func read(_ file: URL, warnings: inout [String]) throws -> [String: Any] {
        guard let data = try? Data(contentsOf: file) else { return [:] }
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw WorkspaceConfigError.invalidJSON(
                file: file, line: line(of: error, in: data), message: message(of: error))
        }
        guard let dictionary = object as? [String: Any] else {
            throw WorkspaceConfigError.invalidJSON(file: file, line: 1, message: "The top level must be an object.")
        }
        return withoutPasswords(dictionary, file: file, warnings: &warnings)
    }

    /// config R4: workspace wins.
    ///
    /// Inside a section that is an object in both files, keys are merged one level down so a
    /// workspace can override a single shortcut or command without repeating the global ones
    /// (config decisions, 2026-08-26).
    private static func merge(_ global: [String: Any], over workspace: [String: Any]) -> [String: Any] {
        var result = global
        for (name, value) in workspace {
            if let base = result[name] as? [String: Any], let override = value as? [String: Any] {
                result[name] = base.merging(override) { _, workspace in workspace }
            } else {
                result[name] = value
            }
        }
        return result
    }

    /// config R11: a `password` key anywhere in the file is dropped and reported, never used.
    private static func withoutPasswords(
        _ dictionary: [String: Any],
        file: URL,
        warnings: inout [String]
    ) -> [String: Any] {
        var result: [String: Any] = [:]
        for (key, value) in dictionary {
            if key == "password" {
                warnings.append("\(file.lastPathComponent): key \"password\" ignored, secrets belong in the Keychain.")
                continue
            }
            if let nested = value as? [String: Any] {
                result[key] = withoutPasswords(nested, file: file, warnings: &warnings)
            } else {
                result[key] = value
            }
        }
        return result
    }

    private static func repos(declared: Any?, root: URL, warnings: inout [String]) -> [URL] {
        guard let declared else { return [] }
        guard let paths = declared as? [String] else {
            warnings.append("\"repos\" ignored: expected an array of paths.")
            return []
        }
        return paths.compactMap { path in
            let folder = root.appending(path: path, directoryHint: .isDirectory)
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

/// What can go wrong with `config.json` (config R7).
nonisolated enum WorkspaceConfigError: Error {
    /// The file is not valid JSON, or not a JSON object; `line` is 1-based when known.
    case invalidJSON(file: URL, line: Int?, message: String)
    /// A feature could not decode its section.
    case invalidSection(String, underlying: Error)
}

extension WorkspaceConfigError: CustomStringConvertible {
    var description: String {
        switch self {
        case .invalidJSON(let file, let line, let message):
            let location = line.map { "\(file.lastPathComponent):\($0)" } ?? file.lastPathComponent
            return "\(location): \(message)"
        case .invalidSection(let name, let underlying):
            return "Section \"\(name)\": \(underlying)"
        }
    }
}
