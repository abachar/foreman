import Foundation

/// git R33: one entry of `git worktree list --porcelain -z`.
nonisolated struct GitWorktree: Equatable, Sendable {
    let folder: URL
    var head: String?
    /// `main`, without `refs/heads/`; `nil` when detached.
    var branch: String?
    var isBare = false
    var isDetached = false
    /// git R34, R38: `nil` when not locked, `""` when locked without a reason.
    var lockReason: String?
    /// The folder is gone (deleted by hand); git forgets it at the next `prune`.
    var isPrunable = false
}

/// git R33: `worktree list --porcelain -z`, `key value` fields ended by NUL, an empty field ending
/// each entry (git ≥ 2.36).
nonisolated enum WorktreeParser {
    static let arguments = ["worktree", "list", "--porcelain", "-z"]

    static func parse(_ data: Data) -> [GitWorktree] {
        var result: [GitWorktree] = []
        var current: GitWorktree?
        func close() {
            if let current {
                result.append(current)
            }
            current = nil
        }
        for field in data.split(separator: 0, omittingEmptySubsequences: false) {
            let text = String(decoding: field, as: UTF8.self)
            let parts = text.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
            let key = parts.first.map(String.init) ?? ""
            let value = parts.count > 1 ? String(parts[1]) : ""
            switch key {
            case "":
                close()
            case "worktree":
                close()
                current = GitWorktree(folder: URL(filePath: value).standardizedFileURL)
            case "HEAD":
                current?.head = value
            case "branch":
                current?.branch = value.hasPrefix("refs/heads/") ? String(value.dropFirst("refs/heads/".count)) : value
            case "bare":
                current?.isBare = true
            case "detached":
                current?.isDetached = true
            case "locked":
                current?.lockReason = value
            case "prunable":
                current?.isPrunable = true
            default:
                break
            }
        }
        close()
        return result
    }
}
