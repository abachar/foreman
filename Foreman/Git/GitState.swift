import Foundation

/// The `git` section of `state.json` (git R2: a manual collapse is persisted).
nonisolated struct GitState: Codable, Equatable, Sendable {
    /// Repo ids collapsed by hand, sorted.
    var collapsed: [String]
    /// git R12: the uncommitted message of each repo, until its commit.
    var messages: [String: String]

    init(collapsed: [String], messages: [String: String] = [:]) {
        self.collapsed = collapsed
        self.messages = messages
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        collapsed = try container.decode([String].self, forKey: .collapsed)
        messages = try container.decodeIfPresent([String: String].self, forKey: .messages) ?? [:]
    }
}

/// git R10: the subject line and its 72-character counter.
nonisolated enum CommitMessage {
    static let subjectLimit = 72

    static func subject(of message: String) -> String {
        message.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
    }

    /// Whitespace only is no message.
    static func isEmpty(_ message: String) -> Bool {
        message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// git R10: nothing staged → refused; *Amend* may reword with an empty index.
    static func canCommit(message: String, stagedCount: Int, amend: Bool) -> Bool {
        !isEmpty(message) && (stagedCount > 0 || amend)
    }
}
