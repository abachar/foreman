import Foundation

/// A branch as `for-each-ref` lists it (git R23).
nonisolated struct GitBranch: Equatable, Sendable, Identifiable {
    /// `main`, `origin/main`.
    let name: String
    /// `refs/heads/main`, `refs/remotes/origin/main`.
    let ref: String
    let upstream: String?
    let isCurrent: Bool

    var id: String {
        ref
    }

    var isRemote: Bool {
        ref.hasPrefix("refs/remotes/")
    }
}

/// `stash@{0}` and its message (git R24).
nonisolated struct GitStash: Equatable, Sendable, Identifiable {
    let ref: String
    let message: String

    var id: String {
        ref
    }
}

/// `for-each-ref --format=<fields by \x1f>` and `stash list --format=<fields by \x1f>` (git R27).
nonisolated enum RefParser {
    static let branchFormat = "%(refname)%1f%(refname:short)%1f%(upstream:short)%1f%(HEAD)"
    /// `stash list` goes through the pretty machinery, which emits `%1f` literally and only expands `%x1f`.
    static let stashFormat = "%gd%x1f%s"

    static func branches(_ data: Data) -> [GitBranch] {
        String(decoding: data, as: UTF8.self).split(separator: "\n").compactMap { line in
            let fields = line.split(separator: "\u{1f}", omittingEmptySubsequences: false)
            guard fields.count == 4, !fields[0].isEmpty, !fields[1].hasSuffix("/HEAD") else { return nil }
            return GitBranch(
                name: String(fields[1]), ref: String(fields[0]), upstream: fields[2].isEmpty ? nil : String(fields[2]),
                isCurrent: fields[3] == "*")
        }
    }

    static func stashes(_ data: Data) -> [GitStash] {
        String(decoding: data, as: UTF8.self).split(separator: "\n").compactMap { line in
            let fields = line.split(separator: "\u{1f}", maxSplits: 1, omittingEmptySubsequences: false)
            guard fields.count == 2, fields[0].hasPrefix("stash@{") else { return nil }
            return GitStash(ref: String(fields[0]), message: String(fields[1]))
        }
    }
}

/// git R21: one remote operation at a time per repo; a request during one is refused, not queued.
nonisolated struct RemoteOperations: Equatable, Sendable {
    enum Kind: String, Sendable {
        case fetch = "Fetching"
        case pull = "Pulling"
        case push = "Pushing"
    }

    private(set) var running: [String: Kind] = [:]

    mutating func start(_ kind: Kind, in repo: String) -> Bool {
        guard running[repo] == nil else { return false }
        running[repo] = kind
        return true
    }

    mutating func finish(_ repo: String) {
        running[repo] = nil
    }

    func current(in repo: String) -> Kind? {
        running[repo]
    }
}

/// git R22: what the "authentication required" banner shows; never a secret.
nonisolated struct GitAuthRequired: Equatable, Sendable {
    let arguments: [String]
    let cwd: URL

    /// The exact command, for the terminal or an agent.
    var command: String {
        (["git"] + arguments.map(Self.quoted)).joined(separator: " ")
    }

    var copyText: String {
        "cd \(Self.quoted(cwd.path(percentEncoded: false))) && \(command)"
    }

    /// A word as it stands when the shell reads it that way, single-quoted otherwise.
    ///
    /// A branch or stash name may hold a space, a `$`, a `;` or a quote: pasted raw, the copied
    /// command would run something else than the one that failed.
    static func quoted(_ word: String) -> String {
        guard word.isEmpty || word.contains(where: { !safeCharacters.contains($0) }) else { return word }
        return "'" + word.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static let safeCharacters = Set(
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_./=:+@,")
}
