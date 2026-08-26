import Foundation

/// The `explorer` section of `state.json` (explorer R5, R11).
nonisolated struct ExplorerState: Codable, Equatable, Sendable {
    var expanded: [String]
    var hidesExcluded: Bool
}
