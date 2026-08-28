import Foundation

/// The `explorer` section of `state.json` (explorer R5, R11).
nonisolated struct ExplorerState: Codable, Equatable, Sendable {
    var expanded: [String]
    var hidesExcluded: Bool
    /// explorer R14.
    var followsActiveTab = true

    init(expanded: [String], hidesExcluded: Bool, followsActiveTab: Bool = true) {
        self.expanded = expanded
        self.hidesExcluded = hidesExcluded
        self.followsActiveTab = followsActiveTab
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        expanded = try container.decode([String].self, forKey: .expanded)
        hidesExcluded = try container.decode(Bool.self, forKey: .hidesExcluded)
        followsActiveTab = try container.decodeIfPresent(Bool.self, forKey: .followsActiveTab) ?? true
    }
}
