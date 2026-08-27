import Foundation
import Testing

@testable import Wraith

/// The argument lists (git R7–R9; architecture, security: paths after `--`, never a shell).
struct GitCommandTests {
    @Test func stageAndUnstagePutEveryPathAfterTheDoubleDash() {
        #expect(GitCommand.stage(["a.txt", "-rf", "dir/b.txt"]) == ["add", "--", "a.txt", "-rf", "dir/b.txt"])
        #expect(GitCommand.unstage(["a.txt"], isUnborn: false) == ["restore", "--staged", "--", "a.txt"])
    }

    @Test func unstagingWithoutACommitEmptiesTheIndexInstead() {
        #expect(
            GitCommand.unstage(["a.txt", "b"], isUnborn: true) == ["rm", "--cached", "--quiet", "--", "a.txt", "b"])
    }

    @Test func discardSplitsTrackedAndUntrackedPaths() {
        let entries = [
            GitStatusEntry(path: "src/a.swift", index: .unmodified, worktree: .modified),
            GitStatusEntry(path: "new.txt", index: .untracked, worktree: .untracked),
            GitStatusEntry(path: "gone.txt", index: .unmodified, worktree: .deleted),
        ]
        #expect(
            GitCommand.discard(entries) == [
                ["restore", "--", "src/a.swift", "gone.txt"], ["clean", "-f", "--", "new.txt"],
            ])
        #expect(GitCommand.discard([entries[1]]) == [["clean", "-f", "--", "new.txt"]])
        #expect(GitCommand.discard([]).isEmpty)
    }

    @Test func abortAndContinueNameTheOperationInProgress() {
        #expect(GitCommand.abort(.merging) == ["merge", "--abort"])
        #expect(GitCommand.continue(.rebasing) == ["rebase", "--continue"])
        #expect(GitCommand.abort(.cherryPicking) == ["cherry-pick", "--abort"])
    }

    @Test func statusUsesTheMachineFormat() {
        #expect(GitCommand.status == ["status", "--porcelain=v2", "-z", "--branch"])
    }
}
