import Foundation

/// What the explorer reports in its banner (explorer R19).
nonisolated enum ExplorerError: Error {
    /// Reading or changing `relativePath` failed; the tree is left as it was.
    case io(String, underlying: Error)
}

extension ExplorerError: CustomStringConvertible {
    var description: String {
        switch self {
        case .io(let path, let underlying):
            return "\(path.isEmpty ? "." : path): \(underlying.localizedDescription)"
        }
    }
}
