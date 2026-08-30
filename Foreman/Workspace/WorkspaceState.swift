import Foundation
import os

/// The persisted UI state of a workspace, `<root>/.foreman/state.json` (config R8, R9).
///
/// Like the config, the state is a set of top-level sections `Workspace` does not interpret: each
/// feature reads and writes its own (`layout`, later `terminal`…). The file carries a schema
/// version; a file that is unreadable or of another version is set aside as `state.json.bak` and
/// the workspace starts from the default state (config R9).
nonisolated struct WorkspaceState: Sendable, Equatable {
    static let version = 1
    static let empty = WorkspaceState(sections: [:])
    private static let logger = Logger(subsystem: "dev.crafters.foreman", category: "workspace")

    /// Top-level sections, each kept as the JSON of its value.
    private var sections: [String: Data]

    /// The section `name` decoded as `type`, or `nil` when the file did not have it.
    func section<T: Decodable>(_ name: String, as type: T.Type) throws -> T? {
        guard let data = sections[name] else { return nil }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw WorkspaceError.invalidSection(name, underlying: error)
        }
    }

    mutating func setSection(_ name: String, to value: some Encodable) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        sections[name] = try encoder.encode(value)
    }

    // MARK: - File

    static func file(under root: URL) -> URL {
        root.appending(components: ".foreman", "state.json")
    }

    /// Reads `state.json`; the default state when it is missing, unreadable or of another version.
    ///
    /// An invalid file is moved to `state.json.bak` so nothing is lost (config R9). A file that
    /// exists but cannot be read (permissions, IO) also defaults, but says so: it must not pass
    /// for a fresh workspace.
    @concurrent
    static func load(root: URL) async -> WorkspaceState {
        let file = file(under: root)
        let data: Data
        do {
            data = try Data(contentsOf: file)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return .empty
        } catch {
            let path = file.path(percentEncoded: false)
            logger.warning(
                "state.json not read (\(path, privacy: .private)): \(error.localizedDescription, privacy: .public)")
            return .empty
        }
        do {
            return try parse(data, file: file)
        } catch {
            logger.warning(
                "state.json set aside as state.json.bak: \(String(describing: error), privacy: .public)")
            let backup = file.appendingPathExtension("bak")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.moveItem(at: file, to: backup)
            return .empty
        }
    }

    /// Writes the state atomically (`.atomic` is Foundation's own temporary-then-rename).
    ///
    /// `.foreman/` is created on the first write (config R1).
    @concurrent
    static func write(_ state: WorkspaceState, root: URL) async throws {
        let file = file(under: root)
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try state.data().write(to: file, options: [.atomic])
    }

    private static func parse(_ data: Data, file: URL) throws -> WorkspaceState {
        guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            object.removeValue(forKey: "version") as? Int == version
        else {
            throw WorkspaceError.invalidJSON(
                file: file, line: nil, message: "The top level must be an object with \"version\" \(version).")
        }
        var sections: [String: Data] = [:]
        for (name, value) in object {
            sections[name] = try JSONSerialization.data(
                withJSONObject: value, options: [.sortedKeys, .fragmentsAllowed])
        }
        return WorkspaceState(sections: sections)
    }

    private func data() throws -> Data {
        var object: [String: Any] = ["version": Self.version]
        for (name, data) in sections {
            object[name] = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        }
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .prettyPrinted])
    }
}
