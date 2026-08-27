import Foundation

/// The `git` section of `state.json` (git R2: a manual collapse is persisted).
nonisolated struct GitState: Codable, Equatable, Sendable {
    /// Repo ids collapsed by hand, sorted.
    var collapsed: [String]
}
