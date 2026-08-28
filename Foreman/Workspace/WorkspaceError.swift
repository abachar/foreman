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
            let location = line.map { "\(file.lastPathComponent):\($0)" } ?? file.lastPathComponent
            return "\(location): \(message)"
        case .invalidSection(let name, let underlying):
            return "Section \"\(name)\": \(underlying)"
        }
    }
}
