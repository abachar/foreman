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

    /// git R19: the history menu; `--hard` is never produced.
    enum ResetMode: Sendable {
        case soft
        case mixed
    }

    static func checkoutDetached(_ sha: String) -> [String] {
        ["checkout", "--detach", sha]
    }

    static func createBranch(_ name: String, at sha: String) -> [String] {
        ["switch", "-c", name, sha]
    }

    static func cherryPick(_ sha: String) -> [String] {
        ["cherry-pick", sha]
    }

    static func revert(_ sha: String) -> [String] {
        ["revert", "--no-edit", sha]
    }

    static func reset(to sha: String, mode: ResetMode) -> [String] {
        ["reset", mode == .soft ? "--soft" : "--mixed", sha]
    }

    // MARK: - Remote, branches, stash (git R21, R23, R24)

    static let fetch = ["fetch", "--prune"]
    /// git R21: the user's `pull.rebase` decides.
    static let pull = ["pull"]

    /// git R21: `-u origin <branch>` only when the branch has no upstream yet.
    static func push(branch: String, hasUpstream: Bool) -> [String] {
        hasUpstream ? ["push"] : ["push", "-u", "origin", branch]
    }

    static let branches = ["for-each-ref", "--format=\(RefParser.branchFormat)", "refs/heads", "refs/remotes"]

    /// git R23: a local branch is switched to; a remote one gets a tracking local branch.
    static func checkout(_ branch: GitBranch) -> [String] {
        branch.isRemote ? ["checkout", "--track", branch.name] : ["switch", branch.name]
    }

    static func newBranch(_ name: String) -> [String] {
        ["switch", "-c", name]
    }

    static func renameBranch(_ name: String, to newName: String) -> [String] {
        ["branch", "-m", name, newName]
    }

    /// git R23: `-d`, or `-D` once the user confirmed with the name.
    static func deleteBranch(_ name: String, force: Bool) -> [String] {
        ["branch", force ? "-D" : "-d", name]
    }

    static func setUpstream(of branch: String, to upstream: String) -> [String] {
        ["branch", "--set-upstream-to=\(upstream)", branch]
    }

    static let stashList = ["stash", "list", "--format=\(RefParser.stashFormat)"]

    /// git R24: an optional message, `-u` on request.
    static func stashPush(message: String?, includeUntracked: Bool) -> [String] {
        var arguments = ["stash", "push"]
        if includeUntracked {
            arguments.append("--include-untracked")
        }
        if let message, !message.isEmpty {
            arguments += ["-m", message]
        }
        return arguments
    }

    enum StashAction: String, Sendable {
        case apply
        case pop
        case drop
    }

    static func stash(_ action: StashAction, _ ref: String) -> [String] {
        ["stash", action.rawValue, ref]
    }

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
