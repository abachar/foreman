import Foundation

/// What can go wrong with the files under `.foreman/` (config R7, R9).
nonisolated enum WorkspaceError: Error {
    /// The file is not valid JSON, or not a JSON object; `line` is 1-based when known.
    case invalidJSON(file: URL, line: Int?, message: String)
    /// A feature could not decode its section of `config.json` or `state.json`.
    case invalidSection(String, underlying: Error)
}

extension WorkspaceError: CustomStringConvertible {
    var description: String {
        switch self {
        case .invalidJSON(let file, let line, let message):
            let name = Self.name(of: file)
            return line.map { "\(name):\($0): \(message)" } ?? "\(name): \(message)"
        case .invalidSection(let name, let underlying):
            return "Section \"\(name)\": \(underlying)"
        }
    }

    /// config R4: both files are named `config.json`, so the global one is written from the home
    /// (`~/.config/foreman/config.json`) and the workspace's keeps its bare name.
    private static func name(of file: URL) -> String {
        guard file.deletingLastPathComponent().lastPathComponent != ".foreman" else {
            return file.lastPathComponent
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false)
        let path = file.path(percentEncoded: false)
        guard path.hasPrefix(home) else { return path }
        return "~/" + path.dropFirst(home.count).drop(while: { $0 == "/" })
    }
}
