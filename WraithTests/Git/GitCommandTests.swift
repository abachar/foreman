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
        #expect(GitCommand.status == ["status", "--porcelain=v2", "-z", "--branch", "--ignored=matching"])
    }
}

/// git R10–R12: the commit arguments, the subject counter, the refusal, the persisted messages.
struct GitCommitTests {
    @Test func commitReadsTheMessageFromAFileAndAddsOnlyAmend() {
        let file = URL(filePath: "/tmp/msg.txt")
        #expect(GitCommand.commit(messageFile: file, amend: false) == ["commit", "-F", "/tmp/msg.txt"])
        #expect(GitCommand.commit(messageFile: file, amend: true) == ["commit", "-F", "/tmp/msg.txt", "--amend"])
        for arguments in [GitCommand.commit(messageFile: file, amend: true), GitCommand.stage(["a"])] {
            #expect(!arguments.contains("--no-verify"))
            #expect(!arguments.contains("-c"))
            #expect(!arguments.contains("--no-gpg-sign"))
        }
        #expect(GitCommand.headMessage == ["log", "-1", "--format=%B"])
    }

    @Test func theSubjectIsTheFirstLineAndOver72IsFlaggedByTheView() {
        #expect(CommitMessage.subject(of: "feat: x\n\nbody") == "feat: x")
        #expect(CommitMessage.subject(of: "") == "")
        #expect(CommitMessage.subject(of: String(repeating: "a", count: 80)).count > CommitMessage.subjectLimit)
        #expect(CommitMessage.isEmpty(" \n\t"))
        #expect(!CommitMessage.isEmpty("x"))
    }

    @Test func anEmptyIndexRefusesTheCommitUnlessAmending() {
        #expect(!CommitMessage.canCommit(message: "m", stagedCount: 0, amend: false))
        #expect(CommitMessage.canCommit(message: "m", stagedCount: 1, amend: false))
        #expect(CommitMessage.canCommit(message: "m", stagedCount: 0, amend: true))
        #expect(!CommitMessage.canCommit(message: "  ", stagedCount: 3, amend: false))
    }

    @Test func roundtripsTheMessagesPerRepoAndReadsAnOlderSectionWithoutThem() throws {
        let state = GitState(collapsed: [], messages: [".": "wip\nbody", "libs/core": "fix"])
        let data = try JSONEncoder().encode(state)
        #expect(try JSONDecoder().decode(GitState.self, from: data) == state)
        let old = try JSONDecoder().decode(GitState.self, from: Data(#"{"collapsed":["."]}"#.utf8))
        #expect(old == GitState(collapsed: ["."]))
    }

    @Test func hookOutputOnStdoutJoinsTheFailureMessage() {
        #expect(
            GitCLI.failureText(stdout: "lint: 3 errors\n", stderr: "husky - pre-commit script failed (code 1)")
                == "husky - pre-commit script failed (code 1)\nlint: 3 errors")
        #expect(GitCLI.failureText(stdout: "", stderr: "  x \n") == "x")
        #expect(GitCLI.failureText(stdout: "", stderr: "").isEmpty)
    }
}
