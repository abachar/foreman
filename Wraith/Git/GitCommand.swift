import Foundation

/// The argument lists handed to `GitCLI` (git R7, R9, R27; architecture, security: every path
/// after `--`, nothing from a program's output before it).
nonisolated enum GitCommand {
    static let status = ["status", "--porcelain=v2", "-z", "--branch"]

    /// git R7: `add`, also for a deleted or a conflicted path (R9, *Mark as resolved*).
    static func stage(_ paths: [String]) -> [String] {
        ["add", "--"] + paths
    }

    /// git R7: `restore --staged`; without a commit yet the index is emptied with `rm --cached`.
    static func unstage(_ paths: [String], isUnborn: Bool) -> [String] {
        (isUnborn ? ["rm", "--cached", "--quiet", "--"] : ["restore", "--staged", "--"]) + paths
    }

    /// git R7, R8: the tracked paths go through `restore`, the untracked ones through `clean -f`;
    /// one command per kind, none when a kind is empty.
    static func discard(_ entries: [GitStatusEntry]) -> [[String]] {
        let untracked = entries.filter(\.isUntracked).map(\.path)
        let tracked = entries.filter { !$0.isUntracked }.map(\.path)
        var commands: [[String]] = []
        if !tracked.isEmpty {
            commands.append(["restore", "--"] + tracked)
        }
        if !untracked.isEmpty {
            commands.append(["clean", "-f", "--"] + untracked)
        }
        return commands
    }

    /// git R10, R11: the index as it is, the message from a file; `--amend` and nothing else — never
    /// `--no-verify`, never a `-c` overriding the user's config.
    static func commit(messageFile: URL, amend: Bool) -> [String] {
        ["commit", "-F", messageFile.path(percentEncoded: false)] + (amend ? ["--amend"] : [])
    }

    /// git R10: what *Amend* prefills the message with.
    static let headMessage = ["log", "-1", "--format=%B"]

    /// git R9: *Abort* on the operation in progress.
    static func abort(_ operation: GitOperation) -> [String] {
        [subcommand(operation), "--abort"]
    }

    /// git R9: *Continue*; git's prepared message is accepted through `GIT_EDITOR=true` (R26).
    static func `continue`(_ operation: GitOperation) -> [String] {
        [subcommand(operation), "--continue"]
    }

    private static func subcommand(_ operation: GitOperation) -> String {
        switch operation {
        case .merging: return "merge"
        case .rebasing: return "rebase"
        case .cherryPicking: return "cherry-pick"
        }
    }
}
